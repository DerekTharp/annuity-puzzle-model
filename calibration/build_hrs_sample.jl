# Build HRS population sample for annuity puzzle model evaluation.
#
# Extracts single retirees aged 65-69 from the RAND HRS longitudinal file,
# pooling across waves 5-9 (2000-2008) to match Lockwood (2012) sample.
# Adds observed self-reported health mapped to 3 model states.
#
# Output: data/processed/lockwood_hrs_sample.csv
# Columns: wealth, perm_income, age, health, own_life_ann, weight
#
# Health mapping: RAND HRS rXshlt (1=Excellent...5=Poor)
#   {1,2} -> 1 (Good), {3} -> 2 (Fair), {4,5} -> 3 (Poor)
#
# RAND HRS variable conventions (wave w):
#   r{w}agey_b     age in years (at interview)
#   r{w}mstat      marital status (1=married, 3=separated, 4=divorced,
#                    5=widowed, 7=never married, 8=other)
#   r{w}shlt       self-reported health level (1=Exc...5=Poor)
#   r{w}wtresp     person-level respondent weight
#   r{w}iwstat     interview status (1=resp alive, 5/6=died)
#   h{w}atotb      total household wealth excl 2nd home
#   h{w}ahous      value of primary residence
#   r{w}iearn      individual earnings
#   r{w}issdi      individual SS disability income
#   r{w}isret      individual SS retirement income
#   r{w}igxrc      individual income from government transfers
#   r{w}ipeninc    individual pension/annuity income
#   r{w}iosdi      individual other govt transfer income
#
# References:
#   Lockwood (2012, RED): Table 1 sample, single retirees 65-69
#   RAND HRS Longitudinal File codebook (v1, 2024)

using ReadStatTables
using Printf
using DelimitedFiles

# Extract underlying numeric value from ReadStatTables LabeledValue.
numval(x) = Int(getfield(x, :value))
numval(x::Number) = Int(x)
numval_float(x) = Float64(getfield(x, :value))
numval_float(x::Number) = Float64(x)

function main()
    println("=" ^ 70)
    println("  BUILD HRS POPULATION SAMPLE")
    println("  Single retirees aged 65-69, waves 5-9 (2000-2008)")
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

    # Wave mapping: wave 5=2000, 6=2002, 7=2004, 8=2006, 9=2008
    # Lockwood pools HRS 2000-2008 (5 waves).
    waves = 5:9
    wave_years = Dict(5=>2000, 6=>2002, 7=>2004, 8=>2006, 9=>2008)

    # Marital status codes indicating single:
    #   3=separated, 4=divorced, 5=widowed, 7=never married, 8=other
    single_codes = Set([3, 4, 5, 7, 8])

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
    n_skipped_status = 0
    n_skipped_weight = 0
    n_skipped_health = 0
    n_total_checked = 0

    for w in waves
        println("\n  Processing wave $w ($(wave_years[w]))...")

        # Build column symbols for this wave
        age_sym     = Symbol("r$(w)agey_b")
        mstat_sym   = Symbol("r$(w)mstat")
        shltc_sym   = Symbol("r$(w)shlt")
        iwstat_sym  = Symbol("r$(w)iwstat")
        wtresp_sym  = Symbol("r$(w)wtresp")

        # Wealth: household total assets minus housing
        hatota_sym  = Symbol("h$(w)atotb")
        hahous_sym  = Symbol("h$(w)ahous")

        # Income components for permanent/annuity income
        isret_sym   = Symbol("r$(w)isret")    # SS retirement benefits
        issdi_sym   = Symbol("r$(w)issdi")    # SS disability income
        ipeninc_sym = Symbol("r$(w)ipeninc")  # pension/annuity income

        # Collect columns
        # Use try/catch for columns that may not exist in all waves
        age_col     = try collect(getproperty(tbl, age_sym))     catch; nothing end
        mstat_col   = try collect(getproperty(tbl, mstat_sym))   catch; nothing end
        shltc_col   = try collect(getproperty(tbl, shltc_sym))   catch; nothing end
        iwstat_col  = try collect(getproperty(tbl, iwstat_sym))  catch; nothing end
        wtresp_col  = try collect(getproperty(tbl, wtresp_sym))  catch; nothing end
        hatota_col  = try collect(getproperty(tbl, hatota_sym))  catch; nothing end
        hahous_col  = try collect(getproperty(tbl, hahous_sym))  catch; nothing end
        isret_col   = try collect(getproperty(tbl, isret_sym))   catch; nothing end
        issdi_col   = try collect(getproperty(tbl, issdi_sym))   catch; nothing end
        ipeninc_col = try collect(getproperty(tbl, ipeninc_sym)) catch; nothing end

        # Check that essential columns exist
        if age_col === nothing || mstat_col === nothing
            println("    Warning: missing age or marital status column for wave $w, skipping")
            continue
        end

        n_wave = 0
        for i in 1:N
            n_total_checked += 1

            # Must be alive respondent
            if iwstat_col !== nothing
                ismissing(iwstat_col[i]) && continue
                numval(iwstat_col[i]) != 1 && (n_skipped_status += 1; continue)
            end

            # Must have age
            ismissing(age_col[i]) && continue
            age = numval(age_col[i])
            if age < 65 || age > 69
                n_skipped_age += 1
                continue
            end

            # Must be single
            ismissing(mstat_col[i]) && continue
            mstat_val = numval(mstat_col[i])
            if !(mstat_val in single_codes)
                n_skipped_marital += 1
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
            # 1=Excellent, 2=VeryGood -> Good(1)
            # 3=Good -> Fair(2)
            # 4=Fair, 5=Poor -> Poor(3)
            health_3 = shlt_raw <= 2 ? 1.0 : (shlt_raw == 3 ? 2.0 : 3.0)

            # Wealth: total household assets minus primary residence
            wealth = 0.0
            if hatota_col !== nothing && !ismissing(hatota_col[i])
                wealth = numval_float(hatota_col[i])
            end
            if hahous_col !== nothing && !ismissing(hahous_col[i])
                wealth -= numval_float(hahous_col[i])
            end
            # Floor at zero (some households have negative non-housing wealth)
            wealth = max(wealth, 0.0)

            # Permanent income: SS retirement + SS disability + pension/annuity
            perm_inc = 0.0
            if isret_col !== nothing && !ismissing(isret_col[i])
                perm_inc += max(numval_float(isret_col[i]), 0.0)
            end
            if issdi_col !== nothing && !ismissing(issdi_col[i])
                perm_inc += max(numval_float(issdi_col[i]), 0.0)
            end
            if ipeninc_col !== nothing && !ismissing(ipeninc_col[i])
                perm_inc += max(numval_float(ipeninc_col[i]), 0.0)
            end

            # Annuity ownership: count as owner if pension/annuity income > 0
            # This is an approximation; the RAND HRS does not directly flag
            # life annuity ownership. Pension income could include DB pensions
            # and purchased annuities. Set to 0 as default since Lockwood's
            # observed rate (3.6%) comes from a separate question.
            # TODO: use fat file annuity ownership variable if available
            own_ann = 0.0

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
    @printf("  Skipped (wrong age):       %d\n", n_skipped_age)
    @printf("  Skipped (married):         %d\n", n_skipped_marital)
    @printf("  Skipped (not alive resp):  %d\n", n_skipped_status)
    @printf("  Skipped (no weight):       %d\n", n_skipped_weight)
    @printf("  Skipped (no health):       %d\n", n_skipped_health)

    # ------------------------------------------------------------------
    # Summary statistics
    # ------------------------------------------------------------------
    println("\n  SUMMARY STATISTICS")
    println("  " * "-" ^ 50)

    med_idx = div(n_total, 2)
    sorted_w = sort(out_wealth)
    sorted_inc = sort(out_perm_inc)
    @printf("  Median wealth:           \$%s\n", string(round(Int, sorted_w[med_idx])))
    @printf("  Mean wealth:             \$%s\n", string(round(Int, sum(out_wealth) / n_total)))
    @printf("  Median perm income:      \$%s\n", string(round(Int, sorted_inc[med_idx])))
    @printf("  Mean perm income:        \$%s\n", string(round(Int, sum(out_perm_inc) / n_total)))

    # Health distribution
    n_good = count(x -> x == 1.0, out_health)
    n_fair = count(x -> x == 2.0, out_health)
    n_poor = count(x -> x == 3.0, out_health)
    @printf("  Health: Good=%d (%.1f%%), Fair=%d (%.1f%%), Poor=%d (%.1f%%)\n",
        n_good, n_good/n_total*100,
        n_fair, n_fair/n_total*100,
        n_poor, n_poor/n_total*100)

    # Age distribution
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
