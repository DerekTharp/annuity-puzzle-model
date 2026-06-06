# Build the OBSERVED Social Security and DB-pension income profile by wealth bin
# from RAND HRS, to replace the hardcoded SS_QUARTILE_LEVELS=[14k,17k,20k,25k].
#
# The current model hardcodes SS levels keyed to wealth breaks [30k,120k,350k]
# (src/decomposition.jl). Those bins fold pension/DB into the level. For the
# option-2 SS-crowd-out spine, the SS channel is load-bearing and must use
# OBSERVED SS income, separated from DB. This script computes weighted-mean
# SS-only (isret+issdi) and DB (ipeninc) income within the SAME wealth bins so
# the comparison is apples-to-apples.
#
# Sample filters mirror build_hrs_sample.jl exactly: single retirees aged 65-69,
# alive respondents, valid weight + health, waves 5-9, non-housing wealth.
# Restricts to wealth >= MIN_WEALTH (the model's analysis sample).
#
# Data-integrity note: RAND HRS income variables are imputed/cleaned. This dry
# run floors negatives at 0 (as build_hrs_sample.jl does) and reports the count
# of negative/missing values per column so any sentinel contamination is visible.
# Production use should confirm coding via codebook per project rules.
#
# Usage: julia --project=. calibration/build_ss_profile.jl

using ReadStatTables
using Printf
using Statistics

include(joinpath(@__DIR__, "..", "scripts", "config.jl"))

numval(x) = Int(getfield(x, :value))
numval(x::Number) = Int(x)
numval_float(x) = Float64(getfield(x, :value))
numval_float(x::Number) = Float64(x)

# Model wealth bins (src/decomposition.jl SS_QUARTILE_BREAKS) — keep identical
# so observed levels map onto the same four cells the solver uses.
const WEALTH_BREAKS = [30_000.0, 120_000.0, 350_000.0]
const HARDCODED_SS  = [14_000.0, 17_000.0, 20_000.0, 25_000.0]

bin_of(w) = w < WEALTH_BREAKS[1] ? 1 :
            w < WEALTH_BREAKS[2] ? 2 :
            w < WEALTH_BREAKS[3] ? 3 : 4

println("=" ^ 70)
println("  OBSERVED SS + DB INCOME PROFILE BY WEALTH BIN (RAND HRS)")
println("=" ^ 70)

dta_path = joinpath(@__DIR__, "..", "data", "raw", "HRS",
    "randhrs1992_2022v1_STATA", "randhrs1992_2022v1.dta")
println("\nLoading RAND HRS longitudinal file...")
tbl = readstat(dta_path; ntasks=0)
N = length(tbl[1])
@printf("  Loaded %d respondents\n", N)

const WAVES = 5:9
const SINGLE = Set([3, 4, 5, 7, 8])

# Accumulators per wealth bin
wsum_ss  = zeros(4); wsum_db = zeros(4); wsum_w = zeros(4); n_bin = zeros(Int, 4)
n_neg_ss = 0; n_neg_db = 0; n_obs = 0

for w in WAVES
    age_c   = try collect(getproperty(tbl, Symbol("r$(w)agey_b"))) catch; nothing end
    mstat_c = try collect(getproperty(tbl, Symbol("r$(w)mstat")))  catch; nothing end
    iws_c   = try collect(getproperty(tbl, Symbol("r$(w)iwstat"))) catch; nothing end
    wt_c    = try collect(getproperty(tbl, Symbol("r$(w)wtresp"))) catch; nothing end
    shlt_c  = try collect(getproperty(tbl, Symbol("r$(w)shlt")))   catch; nothing end
    atot_c  = try collect(getproperty(tbl, Symbol("h$(w)atotb")))  catch; nothing end
    ahous_c = try collect(getproperty(tbl, Symbol("h$(w)ahous")))  catch; nothing end
    # CORRECTED variable names (verified against RAND HRS labels):
    #   r{w}isret = SS retirement income (the variable a trust-fund cut hits)
    #   r{w}ipena = pension + annuity income (DB pension floor; NOT cut by SS)
    # The previously-used r{w}ipeninc DOES NOT EXIST in RAND HRS and was
    # silently returning nothing -> DB income dropped to $0. build_hrs_sample.jl
    # has the same bug (its perm_income has been SS-only, mislabeled).
    isret_c = try collect(getproperty(tbl, Symbol("r$(w)isret")))  catch; nothing end
    ipena_c = try collect(getproperty(tbl, Symbol("r$(w)ipena")))  catch; nothing end
    (age_c === nothing || mstat_c === nothing) && continue

    for i in 1:N
        iws_c !== nothing && (ismissing(iws_c[i]) || numval(iws_c[i]) != 1) && continue
        ismissing(age_c[i]) && continue
        a = numval(age_c[i]); (a < 65 || a > 69) && continue
        ismissing(mstat_c[i]) && continue
        numval(mstat_c[i]) in SINGLE || continue
        (wt_c === nothing || ismissing(wt_c[i])) && continue
        wt = numval_float(wt_c[i]); wt <= 0.0 && continue
        (shlt_c === nothing || ismissing(shlt_c[i])) && continue
        sh = numval(shlt_c[i]); (sh < 1 || sh > 5) && continue

        wealth = 0.0
        atot_c !== nothing && !ismissing(atot_c[i]) && (wealth += numval_float(atot_c[i]))
        ahous_c !== nothing && !ismissing(ahous_c[i]) && (wealth -= numval_float(ahous_c[i]))
        wealth = max(wealth, 0.0)
        wealth < MIN_WEALTH && continue

        # SS = SS retirement (isret) only — this is the income a trust-fund
        # shortfall cuts. DB = pension + annuity (ipena) — pre-existing
        # annuitized income that is NOT cut by an SS shortfall.
        ss_raw = 0.0
        if isret_c !== nothing && !ismissing(isret_c[i])
            v = numval_float(isret_c[i]); v < 0 && (global n_neg_ss += 1); ss_raw += max(v, 0.0)
        end
        db_raw = 0.0
        if ipena_c !== nothing && !ismissing(ipena_c[i])
            v = numval_float(ipena_c[i]); v < 0 && (global n_neg_db += 1); db_raw += max(v, 0.0)
        end

        b = bin_of(wealth)
        wsum_ss[b] += wt * ss_raw
        wsum_db[b] += wt * db_raw
        wsum_w[b]  += wt
        n_bin[b]   += 1
        global n_obs += 1
    end
end

@printf("\n  Qualifying person-wave obs (wealth>=\$%s): %d\n",
        string(round(Int, MIN_WEALTH)), n_obs)
@printf("  Negative raw values floored: SS=%d, DB=%d\n", n_neg_ss, n_neg_db)

ss_mean = [wsum_w[b] > 0 ? wsum_ss[b]/wsum_w[b] : 0.0 for b in 1:4]
db_mean = [wsum_w[b] > 0 ? wsum_db[b]/wsum_w[b] : 0.0 for b in 1:4]

println("\n  Weighted-mean income by wealth bin:")
@printf("  %-22s %10s %10s %10s %10s\n", "bin", "n", "hardSS", "obsSS", "obsDB")
println("  " * "-"^66)
labels = ["<30k", "30-120k", "120-350k", ">350k"]
for b in 1:4
    @printf("  %-22s %10d %10s %10s %10s\n", labels[b], n_bin[b],
            "\$"*string(round(Int,HARDCODED_SS[b])),
            "\$"*string(round(Int,ss_mean[b])),
            "\$"*string(round(Int,db_mean[b])))
end

println("\n  Observed SS-only levels (replaces hardcoded SS_QUARTILE_LEVELS):")
@printf("    SS_OBS    = [%.0f, %.0f, %.0f, %.0f]\n", ss_mean...)
@printf("    SS+DB_OBS = [%.0f, %.0f, %.0f, %.0f]\n",
        (ss_mean .+ db_mean)...)
@printf("    hardcoded = [%.0f, %.0f, %.0f, %.0f]\n", HARDCODED_SS...)

# Save
out = joinpath(@__DIR__, "..", "data", "processed", "ss_income_profile.csv")
open(out, "w") do f
    println(f, "bin,wealth_lo,wealth_hi,n,hardcoded_ss,obs_ss,obs_db,obs_ss_plus_db")
    los = [0.0, WEALTH_BREAKS...]; his = [WEALTH_BREAKS..., -1.0]
    for b in 1:4
        @printf(f, "%d,%.0f,%.0f,%d,%.0f,%.2f,%.2f,%.2f\n",
                b, los[b], his[b], n_bin[b], HARDCODED_SS[b],
                ss_mean[b], db_mean[b], ss_mean[b]+db_mean[b])
    end
end
println("\n  Saved: data/processed/ss_income_profile.csv")
