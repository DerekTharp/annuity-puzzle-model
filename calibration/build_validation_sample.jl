# Build the person-wave covariate sample for the empirical validation of the
# model's channel ranking. The structural channels predict cross-sectional
# ownership gradients; this sample lets the manuscript test them directly:
#
#   channel              covariate                      predicted gradient
#   survival pessimism   r{w}liv10r (self-reported /    ownership rises with
#                        life-table P(live ~10 yrs))    optimism
#   bequests (luxury)    r{w}beq100 (prob bequest       ownership falls with
#                        >= $100k), r{w}beq10k          bequest intention
#   health / Med+R-S     r{w}shlt (3-state)             ownership falls in poor
#                                                       health at purchase ages
#   SS/DB crowd-out      isret + ipen (2014$)           conditional on wealth,
#                                                       ownership falls with
#                                                       pre-annuitized income
#   loads/min purchase   wealth (2014$)                 ownership rises with
#                                                       wealth (feasibility)
#
# Same filters and deflators as the model population (calibration/hrs_common.jl):
# single nonworking retirees 65-69, waves 5-9. One row per person-wave;
# hhidpn retained for person-clustered inference.
#
# Output: data/processed/hrs_validation_sample.csv
# Usage:  julia --project=. calibration/build_validation_sample.jl

using ReadStatTables
using Printf

include(joinpath(@__DIR__, "hrs_common.jl"))

function main()
    println("=" ^ 70)
    println("  BUILD HRS VALIDATION SAMPLE (covariates for gradient tests)")
    println("=" ^ 70)

    dta_path = joinpath(@__DIR__, "..", "data", "raw", "HRS",
        "randhrs1992_2022v1_STATA", "randhrs1992_2022v1.dta")
    println("\nLoading RAND HRS longitudinal file...")
    tbl = readstat(dta_path; ntasks=0)
    N = length(tbl[1])
    println("  Loaded $N respondents")

    col(s) = try collect(getproperty(tbl, Symbol(s))) catch; nothing end
    hhidpn_c = col("hhidpn")
    gender_c = col("ragender")   # 1=male, 2=female

    rows = NamedTuple[]
    for w in 5:9
        d_w = deflator_wealth(w)
        d_i = deflator_income(w)

        age_c    = col("r$(w)agey_b")
        mstat_c  = col("r$(w)mstat")
        lbrf_c   = col("r$(w)lbrf")
        iws_c    = col("r$(w)iwstat")
        wt_c     = col("r$(w)wtresp")
        shlt_c   = col("r$(w)shlt")
        atot_c   = col("h$(w)atotb")
        ahous_c  = col("h$(w)ahous")
        isret_c  = col("r$(w)isret")
        ipen_c   = col("r$(w)ipen")
        iann_c   = col("r$(w)iann")
        liv10_c  = col("r$(w)liv10")    # self-reported P(live ~10 more yrs), 0-100
        liv10r_c = col("r$(w)liv10r")   # ratio: self-report / life-table
        beq10k_c = col("r$(w)beq10k")   # P(bequest >= 10k), 0-100
        beq100_c = col("r$(w)beq100")   # P(bequest >= 100k), 0-100
        (age_c === nothing || mstat_c === nothing || lbrf_c === nothing) && continue

        n_wave = 0
        for i in 1:N
            iws_c !== nothing && (ismissing(iws_c[i]) || numval(iws_c[i]) != 1) && continue
            ismissing(age_c[i]) && continue
            a = numval(age_c[i]); (a < 65 || a > 69) && continue
            ismissing(mstat_c[i]) && continue
            numval(mstat_c[i]) in SINGLE_MSTAT || continue
            ismissing(lbrf_c[i]) && continue
            numval(lbrf_c[i]) in RETIRED_LBRF || continue
            (wt_c === nothing || ismissing(wt_c[i])) && continue
            wt = numval_float(wt_c[i]); wt <= 0.0 && continue
            (shlt_c === nothing || ismissing(shlt_c[i])) && continue
            sh = numval(shlt_c[i]); (sh < 1 || sh > 5) && continue
            health3 = sh <= 2 ? 1 : (sh == 3 ? 2 : 3)

            wealth = 0.0
            atot_c !== nothing && !ismissing(atot_c[i]) && (wealth += numval_float(atot_c[i]))
            ahous_c !== nothing && !ismissing(ahous_c[i]) && (wealth -= numval_float(ahous_c[i]))
            wealth = max(wealth, 0.0) * d_w
            # Housing wealth kept separately: bequest-expectation covariates
            # proxy housing (the modal $100k+ bequest IS the house), so the
            # gradient logit needs it as a control.
            hous = ahous_c !== nothing && !ismissing(ahous_c[i]) ?
                   max(numval_float(ahous_c[i]), 0.0) * d_w : 0.0

            ss_db = 0.0
            isret_c !== nothing && !ismissing(isret_c[i]) &&
                (ss_db += max(numval_float(isret_c[i]), 0.0))
            ipen_c !== nothing && !ismissing(ipen_c[i]) &&
                (ss_db += max(numval_float(ipen_c[i]), 0.0))
            ss_db *= d_i

            own = 0.0
            iann_c !== nothing && !ismissing(iann_c[i]) &&
                (own = numval_float(iann_c[i]) > 0.0 ? 1.0 : 0.0)

            # Expectation covariates: keep missing as NaN (the analysis script
            # handles listwise deletion per specification, preserving the full
            # sample for specifications that omit a covariate).
            liv10  = liv10_c  !== nothing && !ismissing(liv10_c[i])  ? numval_float(liv10_c[i])  : NaN
            liv10r = liv10r_c !== nothing && !ismissing(liv10r_c[i]) ? numval_float(liv10r_c[i]) : NaN
            beq10k = beq10k_c !== nothing && !ismissing(beq10k_c[i]) ? numval_float(beq10k_c[i]) : NaN
            beq100 = beq100_c !== nothing && !ismissing(beq100_c[i]) ? numval_float(beq100_c[i]) : NaN

            hid = hhidpn_c !== nothing && !ismissing(hhidpn_c[i]) ?
                  numval_float(hhidpn_c[i]) : Float64(i)
            sex = gender_c !== nothing && !ismissing(gender_c[i]) ?
                  numval(gender_c[i]) : 0

            push!(rows, (hhidpn=hid, wave=w, age=a, female=(sex == 2 ? 1 : 0),
                         health3=health3, wealth=wealth, hous_wealth=hous,
                         ss_db_income=ss_db,
                         liv10=liv10, liv10r=liv10r, beq10k=beq10k, beq100=beq100,
# NOTE: despite the name, own_life_ann holds the ANY-ANNUITY income proxy
# (r{w}iann > 0), not the life-contingent q286 measure; see the Table 11 note.
                         own_life_ann=own, weight=wt))
            n_wave += 1
        end
        @printf("  wave %d: %d observations\n", w, n_wave)
    end

    n = length(rows)
    println("\n  Total person-wave observations: $n")
    @printf("  liv10r nonmissing: %d (%.0f%%)\n",
        count(r -> !isnan(r.liv10r), rows), count(r -> !isnan(r.liv10r), rows) / n * 100)
    @printf("  beq100 nonmissing: %d (%.0f%%)\n",
        count(r -> !isnan(r.beq100), rows), count(r -> !isnan(r.beq100), rows) / n * 100)
    @printf("  owners: %d (%.1f%%)\n",
        count(r -> r.own_life_ann == 1.0, rows),
        count(r -> r.own_life_ann == 1.0, rows) / n * 100)

    outpath = joinpath(@__DIR__, "..", "data", "processed", "hrs_validation_sample.csv")
    open(outpath, "w") do io
        println(io, "hhidpn,wave,age,female,health3,wealth,hous_wealth,ss_db_income," *
                    "liv10,liv10r,beq10k,beq100,own_life_ann,weight")
        for r in rows
            @printf(io, "%.0f,%d,%d,%d,%d,%.1f,%.1f,%.1f,%.2f,%.4f,%.2f,%.2f,%.0f,%.1f\n",
                r.hhidpn, r.wave, r.age, r.female, r.health3, r.wealth,
                r.hous_wealth, r.ss_db_income, r.liv10, r.liv10r, r.beq10k,
                r.beq100, r.own_life_ann, r.weight)
        end
    end
    println("\n  Saved: $outpath")
    println("=" ^ 70)
end

main()
