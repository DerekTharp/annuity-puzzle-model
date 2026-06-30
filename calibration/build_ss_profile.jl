# Build the observed Social Security and DB-pension income profile by wealth
# bin from RAND HRS, in 2014 dollars. Replaces the legacy hardcoded
# SS_QUARTILE_LEVELS=[14k,17k,20k,25k].
#
# The SS-crowd-out exhibits cut Social Security only (a trust-fund shortfall
# does not touch employer pensions), so the pre-existing annuitization floor
# must be split into its cut-able and protected components:
#   SS = r{w}isret  — SS retirement/spouse/widow benefits; excludes
#                     disability-based SS by RAND construction. Mean taken
#                     over CLAIMERS (isret > 0): zeros among nonworking
#                     retirees 65-69 are predominantly claiming-timing cases
#                     whose permanent benefit the model needs, not genuine
#                     permanent zeros.
#   DB = r{w}ipen   — employer pension income only (r{w}ipena would fold in
#                     annuity income, contaminating the floor with the
#                     model's outcome variable). Mean over everyone: pension
#                     zeros are genuine permanent states.
#
# Sample filters and deflators are shared with build_hrs_sample.jl via
# calibration/hrs_common.jl: single nonworking retirees 65-69, waves 5-9,
# income deflated by prior-calendar-year CPI, wealth by interview-year CPI.
# Wealth bins are the model's SS_QUARTILE_BREAKS, applied to deflated wealth.
#
# Output: data/processed/ss_income_profile.csv
# Usage:  julia --project=. calibration/build_ss_profile.jl

using ReadStatTables
using Printf
using Statistics

include(joinpath(@__DIR__, "hrs_common.jl"))
include(joinpath(@__DIR__, "..", "scripts", "config.jl"))

# Model wealth bins (src/decomposition.jl SS_QUARTILE_BREAKS) — keep identical
# so observed levels map onto the same four cells the solver uses.
const WEALTH_BREAKS = [30_000.0, 120_000.0, 350_000.0]
const LEGACY_SS     = [14_000.0, 17_000.0, 20_000.0, 25_000.0]

bin_of(w) = w < WEALTH_BREAKS[1] ? 1 :
            w < WEALTH_BREAKS[2] ? 2 :
            w < WEALTH_BREAKS[3] ? 3 : 4

println("=" ^ 70)
println("  OBSERVED SS + DB INCOME PROFILE BY WEALTH BIN (RAND HRS)")
println("  Single nonworking retirees 65-69, waves 5-9, 2014 dollars")
println("=" ^ 70)

dta_path = joinpath(@__DIR__, "..", "data", "raw", "HRS",
    "randhrs1992_2022v1_STATA", "randhrs1992_2022v1.dta")
println("\nLoading RAND HRS longitudinal file...")
tbl = readstat(dta_path; ntasks=0)
N = length(tbl[1])
@printf("  Loaded %d respondents\n", N)

# Accumulators per wealth bin.
# SS uses claimer-conditional weighted means; DB uses unconditional.
wsum_ss        = zeros(4); wsum_w_claimers = zeros(4)
wsum_ss_all    = zeros(4)                      # incl. zeros (diagnostic)
wsum_db        = zeros(4); wsum_w_all = zeros(4)
n_bin          = zeros(Int, 4)
n_claimers     = zeros(Int, 4)
n_neg_ss = 0; n_neg_db = 0; n_obs = 0

for w in 5:9
    d_i = deflator_income(w)
    d_w = deflator_wealth(w)

    age_c   = try collect(getproperty(tbl, Symbol("r$(w)agey_b"))) catch; nothing end
    mstat_c = try collect(getproperty(tbl, Symbol("r$(w)mstat")))  catch; nothing end
    lbrf_c  = try collect(getproperty(tbl, Symbol("r$(w)lbrf")))   catch; nothing end
    iws_c   = try collect(getproperty(tbl, Symbol("r$(w)iwstat"))) catch; nothing end
    wt_c    = try collect(getproperty(tbl, Symbol("r$(w)wtresp"))) catch; nothing end
    shlt_c  = try collect(getproperty(tbl, Symbol("r$(w)shlt")))   catch; nothing end
    atot_c  = try collect(getproperty(tbl, Symbol("h$(w)atotb")))  catch; nothing end
    ahous_c = try collect(getproperty(tbl, Symbol("h$(w)ahous")))  catch; nothing end
    isret_c = try collect(getproperty(tbl, Symbol("r$(w)isret")))  catch; nothing end
    ipen_c  = try collect(getproperty(tbl, Symbol("r$(w)ipen")))   catch; nothing end
    (age_c === nothing || mstat_c === nothing || lbrf_c === nothing) && continue

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

        wealth = 0.0
        atot_c !== nothing && !ismissing(atot_c[i]) && (wealth += numval_float(atot_c[i]))
        ahous_c !== nothing && !ismissing(ahous_c[i]) && (wealth -= numval_float(ahous_c[i]))
        wealth = max(wealth, 0.0) * d_w
        wealth < MIN_WEALTH && continue

        ss_raw = 0.0
        if isret_c !== nothing && !ismissing(isret_c[i])
            v = numval_float(isret_c[i]); v < 0 && (global n_neg_ss += 1)
            ss_raw = max(v, 0.0) * d_i
        end
        db_raw = 0.0
        if ipen_c !== nothing && !ismissing(ipen_c[i])
            v = numval_float(ipen_c[i]); v < 0 && (global n_neg_db += 1)
            db_raw = max(v, 0.0) * d_i
        end

        b = bin_of(wealth)
        if ss_raw > 0.0
            wsum_ss[b] += wt * ss_raw
            wsum_w_claimers[b] += wt
            n_claimers[b] += 1
        end
        wsum_ss_all[b] += wt * ss_raw
        wsum_db[b]     += wt * db_raw
        wsum_w_all[b]  += wt
        n_bin[b]       += 1
        global n_obs += 1
    end
end

@printf("\n  Qualifying person-wave obs (wealth >= \$%s): %d\n",
        string(round(Int, MIN_WEALTH)), n_obs)
@printf("  Negative raw values floored: SS=%d, DB=%d\n", n_neg_ss, n_neg_db)

ss_claimer = [wsum_w_claimers[b] > 0 ? wsum_ss[b] / wsum_w_claimers[b] : 0.0 for b in 1:4]
ss_all     = [wsum_w_all[b] > 0 ? wsum_ss_all[b] / wsum_w_all[b] : 0.0 for b in 1:4]
db_mean    = [wsum_w_all[b] > 0 ? wsum_db[b] / wsum_w_all[b] : 0.0 for b in 1:4]

println("\n  Weighted-mean income by wealth bin (2014 dollars):")
@printf("  %-12s %6s %8s %10s %12s %12s %10s\n",
        "bin", "n", "claim%", "legacySS", "SS(claimers)", "SS(incl 0s)", "DB(ipen)")
println("  " * "-" ^ 76)
labels = ["<30k", "30-120k", "120-350k", ">350k"]
for b in 1:4
    claim_share = n_bin[b] > 0 ? n_claimers[b] / n_bin[b] * 100 : 0.0
    @printf("  %-12s %6d %7.1f%% %10s %12s %12s %10s\n", labels[b], n_bin[b], claim_share,
            "\$" * string(round(Int, LEGACY_SS[b])),
            "\$" * string(round(Int, ss_claimer[b])),
            "\$" * string(round(Int, ss_all[b])),
            "\$" * string(round(Int, db_mean[b])))
end

println("\n  Production constants (claimer-conditional SS, unconditional DB):")
@printf("    SS_OBS    = [%.0f, %.0f, %.0f, %.0f]\n", ss_claimer...)
@printf("    DB_OBS    = [%.0f, %.0f, %.0f, %.0f]\n", db_mean...)
@printf("    SS+DB     = [%.0f, %.0f, %.0f, %.0f]\n", (ss_claimer .+ db_mean)...)
@printf("    legacy    = [%.0f, %.0f, %.0f, %.0f]\n", LEGACY_SS...)

out = joinpath(@__DIR__, "..", "data", "processed", "ss_income_profile.csv")
open(out, "w") do f
    println(f, "bin,wealth_lo,wealth_hi,n,n_claimers,obs_ss_claimers,obs_ss_incl_zeros,obs_db_ipen,obs_ss_plus_db")
    # Bin 1 is left-truncated at MIN_WEALTH: line 97 drops everyone below the
    # model's eligibility floor, so its reported lower bound is MIN_WEALTH, not 0.
    los = [MIN_WEALTH, WEALTH_BREAKS...]; his = [WEALTH_BREAKS..., -1.0]
    for b in 1:4
        @printf(f, "%d,%.0f,%.0f,%d,%d,%.2f,%.2f,%.2f,%.2f\n",
                b, los[b], his[b], n_bin[b], n_claimers[b],
                ss_claimer[b], ss_all[b], db_mean[b], ss_claimer[b] + db_mean[b])
    end
end
println("\n  Saved: data/processed/ss_income_profile.csv")
