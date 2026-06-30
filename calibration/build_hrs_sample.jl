# Build HRS population sample for annuity puzzle model evaluation.
#
# Extracts single nonworking retirees aged 65-69 from the RAND HRS
# longitudinal file, pooling waves 5-9 (interviews 2000-2008), the same
# window as Lockwood (2012). All dollar amounts deflated to 2014 dollars
# (see calibration/hrs_common.jl for deflators and filter definitions).
#
# Output: data/processed/lockwood_hrs_sample.csv
# Columns: wealth, perm_income, age, health, own_life_ann, weight
#
# The model treats the pooled person-wave sample as an unweighted empirical
# population (downstream consumers read only wealth/age/health). The
# r{w}wtresp column is written as a provided-but-unused diagnostic, not used
# for weighted inference.
#
# Health mapping: RAND HRS rXshlt (1=Excellent...5=Poor)
#   {1,2} -> 1 (Good), {3} -> 2 (Fair), {4,5} -> 3 (Poor)
#
# RAND HRS variable conventions (wave w), verified against the RAND HRS 2022
# (V1) codebook:
#   r{w}agey_b     age in years (at interview)
#   r{w}mstat      marital status (single codes in hrs_common.jl)
#   r{w}lbrf       labor force status (retired codes in hrs_common.jl)
#   r{w}shlt       self-reported health level (1=Exc...5=Poor)
#   r{w}wtresp     person-level respondent weight
#   r{w}iwstat     interview status (1=resp alive)
#   h{w}atotb      total household wealth excl 2nd home (interview-year $)
#   h{w}ahous      value of primary residence (interview-year $)
#   r{w}isret      SS retirement/spouse/widow benefits, last calendar year;
#                  excludes disability-based SS by RAND construction
#   r{w}ipen       employer pension income, last calendar year (excludes
#                  annuity income, unlike r{w}ipena = pension + annuity)
#   r{w}iann       individual annuity income (positive = owner)
#
# References:
#   Lockwood (2012, RED): Table 1 sample window, single retirees 65-69
#   RAND HRS Longitudinal File 2022 (V1) codebook

using ReadStatTables
using Printf
using DelimitedFiles

include(joinpath(@__DIR__, "hrs_common.jl"))

function main()
    println("=" ^ 70)
    println("  BUILD HRS POPULATION SAMPLE")
    println("  Single nonworking retirees 65-69, waves 5-9, 2014 dollars")
    println("=" ^ 70)

    # ------------------------------------------------------------------
    # Load RAND HRS
    # ------------------------------------------------------------------
    println("\nLoading RAND HRS longitudinal file...")
    dta_path = joinpath(@__DIR__, "..", "data", "raw", "HRS",
        "randhrs1992_2022v1_STATA", "randhrs1992_2022v1.dta")
    tbl = readstat(dta_path; ntasks=0)
    N = length(tbl[1])
    println("  Loaded $N respondents")

    waves = 5:9

    # ------------------------------------------------------------------
    # Extract observations
    # ------------------------------------------------------------------
    # Each person-wave observation that meets criteria becomes one row.
    # A person appearing in multiple waves contributes multiple observations
    # (consistent with Lockwood's pooled sample).

    out_wealth     = Float64[]
    out_perm_inc   = Float64[]
    out_age        = Float64[]
    out_health     = Float64[]
    out_ann_own    = Float64[]
    out_weight     = Float64[]

    n_skipped_age = 0
    n_skipped_marital = 0
    n_skipped_working = 0
    n_skipped_status = 0
    n_skipped_weight = 0
    n_skipped_health = 0

    for w in waves
        println("\n  Processing wave $w ($(WAVE_YEARS[w]))...")
        d_w = deflator_wealth(w)
        d_i = deflator_income(w)
        @printf("    Deflators to 2014\$: wealth x%.4f (CPI %d), income x%.4f (CPI %d)\n",
            d_w, WAVE_YEARS[w], d_i, WAVE_YEARS[w] - 1)

        age_col    = try collect(getproperty(tbl, Symbol("r$(w)agey_b"))) catch; nothing end
        mstat_col  = try collect(getproperty(tbl, Symbol("r$(w)mstat")))  catch; nothing end
        lbrf_col   = try collect(getproperty(tbl, Symbol("r$(w)lbrf")))   catch; nothing end
        shltc_col  = try collect(getproperty(tbl, Symbol("r$(w)shlt")))   catch; nothing end
        iwstat_col = try collect(getproperty(tbl, Symbol("r$(w)iwstat"))) catch; nothing end
        wtresp_col = try collect(getproperty(tbl, Symbol("r$(w)wtresp"))) catch; nothing end
        hatota_col = try collect(getproperty(tbl, Symbol("h$(w)atotb")))  catch; nothing end
        hahous_col = try collect(getproperty(tbl, Symbol("h$(w)ahous")))  catch; nothing end
        isret_col  = try collect(getproperty(tbl, Symbol("r$(w)isret")))  catch; nothing end
        ipen_col   = try collect(getproperty(tbl, Symbol("r$(w)ipen")))   catch; nothing end
        iann_col   = try collect(getproperty(tbl, Symbol("r$(w)iann")))   catch; nothing end

        if age_col === nothing || mstat_col === nothing || lbrf_col === nothing
            println("    Warning: missing age/mstat/lbrf column for wave $w, skipping")
            continue
        end
        # The alive-respondent restriction is sample-defining; a missing
        # iwstat column must fail loudly, not silently admit deceased/proxy rows.
        @assert iwstat_col !== nothing "missing r$(w)iwstat column for wave $w"

        n_wave = 0
        for i in 1:N
            # Must be alive respondent
            ismissing(iwstat_col[i]) && continue
            numval(iwstat_col[i]) != 1 && (n_skipped_status += 1; continue)

            # Must have age 65-69
            ismissing(age_col[i]) && continue
            age = numval(age_col[i])
            if age < 65 || age > 69
                n_skipped_age += 1
                continue
            end

            # Must be single
            ismissing(mstat_col[i]) && continue
            if !(numval(mstat_col[i]) in SINGLE_MSTAT)
                n_skipped_marital += 1
                continue
            end

            # Must be retired / out of the labor force (no labor income in
            # the model; active workers' unclaimed SS would bias levels)
            ismissing(lbrf_col[i]) && (n_skipped_working += 1; continue)
            if !(numval(lbrf_col[i]) in RETIRED_LBRF)
                n_skipped_working += 1
                continue
            end

            # Must have respondent weight
            if wtresp_col === nothing || ismissing(wtresp_col[i])
                n_skipped_weight += 1
                continue
            end
            wt = numval_float(wtresp_col[i])
            wt <= 0.0 && (n_skipped_weight += 1; continue)

            # Must have health
            if shltc_col === nothing || ismissing(shltc_col[i])
                n_skipped_health += 1
                continue
            end
            shlt_raw = numval(shltc_col[i])
            if shlt_raw < 1 || shlt_raw > 5
                n_skipped_health += 1
                continue
            end

            # Map 5-point health to 3 states
            health_3 = shlt_raw <= 2 ? 1.0 : (shlt_raw == 3 ? 2.0 : 3.0)

            # Wealth: total household assets minus primary residence,
            # deflated to 2014 dollars (interview-year CPI). No MIN_WEALTH
            # floor is applied here; the floor is enforced downstream at solve
            # time, so this CSV retains sub-floor observations.
            wealth = 0.0
            if hatota_col !== nothing && !ismissing(hatota_col[i])
                wealth = numval_float(hatota_col[i])
            end
            if hahous_col !== nothing && !ismissing(hahous_col[i])
                wealth -= numval_float(hahous_col[i])
            end
            wealth = max(wealth, 0.0) * d_w

            # Permanent annuitized income: SS retirement + employer pension,
            # deflated to 2014 dollars (income-year CPI). SSI/SSDI excluded:
            # SSI is the means-tested floor the model represents via c_floor.
            perm_inc = 0.0
            if isret_col !== nothing && !ismissing(isret_col[i])
                perm_inc += max(numval_float(isret_col[i]), 0.0)
            end
            if ipen_col !== nothing && !ismissing(ipen_col[i])
                perm_inc += max(numval_float(ipen_col[i]), 0.0)
            end
            perm_inc *= d_i

            # Annuity ownership: r{w}iann > 0 indicates individual receives
            # annuity income (RAND HRS harmonized variable)
            own_ann = 0.0
            if iann_col !== nothing && !ismissing(iann_col[i])
                own_ann = numval_float(iann_col[i]) > 0.0 ? 1.0 : 0.0
            end

            push!(out_wealth, wealth)
            push!(out_perm_inc, perm_inc)
            push!(out_age, Float64(age))
            push!(out_health, health_3)
            push!(out_ann_own, own_ann)
            push!(out_weight, wt)
            n_wave += 1
        end
        @printf("    Extracted %d observations from wave %d\n", n_wave, w)
    end

    n_total = length(out_wealth)
    println("\n" * "=" ^ 70)
    @printf("  Total observations: %d\n", n_total)
    @printf("  Skipped (wrong age):          %d\n", n_skipped_age)
    @printf("  Skipped (married):            %d\n", n_skipped_marital)
    @printf("  Skipped (working/unemp/miss): %d\n", n_skipped_working)
    @printf("  Skipped (not alive resp):     %d\n", n_skipped_status)
    @printf("  Skipped (no weight):          %d\n", n_skipped_weight)
    @printf("  Skipped (no health):          %d\n", n_skipped_health)

    # ------------------------------------------------------------------
    # Summary statistics
    # ------------------------------------------------------------------
    println("\n  SUMMARY STATISTICS (2014 dollars)")
    println("  " * "-" ^ 50)

    med_idx = max(div(n_total, 2), 1)
    sorted_w = sort(out_wealth)
    sorted_inc = sort(out_perm_inc)
    @printf("  Median wealth:           \$%s\n", string(round(Int, sorted_w[med_idx])))
    @printf("  Mean wealth:             \$%s\n", string(round(Int, sum(out_wealth) / n_total)))
    @printf("  Median perm income:      \$%s\n", string(round(Int, sorted_inc[med_idx])))
    @printf("  Mean perm income:        \$%s\n", string(round(Int, sum(out_perm_inc) / n_total)))

    n_ann_owners = count(x -> x == 1.0, out_ann_own)
    @printf("  Annuity owners:          %d (%.1f%%)\n", n_ann_owners, n_ann_owners/n_total*100)

    n_good = count(x -> x == 1.0, out_health)
    n_fair = count(x -> x == 2.0, out_health)
    n_poor = count(x -> x == 3.0, out_health)
    @printf("  Health: Good=%d (%.1f%%), Fair=%d (%.1f%%), Poor=%d (%.1f%%)\n",
        n_good, n_good/n_total*100,
        n_fair, n_fair/n_total*100,
        n_poor, n_poor/n_total*100)

    for a in 65:69
        n_a = count(x -> x == Float64(a), out_age)
        @printf("  Age %d: %d (%.1f%%)\n", a, n_a, n_a/n_total*100)
    end

    # ------------------------------------------------------------------
    # Write CSV
    # ------------------------------------------------------------------
    outpath = joinpath(@__DIR__, "..", "data", "processed", "lockwood_hrs_sample.csv")
    println("\nWriting to $outpath...")

    open(outpath, "w") do io
        println(io, "wealth,perm_income,age,health,own_life_ann,weight")
        for i in 1:n_total
            @printf(io, "%.1f,%.1f,%d,%d,%.1f,%.1f\n",
                out_wealth[i], out_perm_inc[i], Int(out_age[i]),
                Int(out_health[i]), out_ann_own[i], out_weight[i])
        end
    end

    @printf("  Wrote %d rows\n", n_total)
    println("=" ^ 70)
    println("  DONE")
    println("=" ^ 70)
end

main()
