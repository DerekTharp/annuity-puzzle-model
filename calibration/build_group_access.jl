# Group-annuity access rates by wealth band from RAND HRS.
#
# The two-product extension gives a fraction of each wealth band access to
# group/employer annuity pricing (GROUP_MWR) in addition to the retail SPIA.
# Access is proxied by employer-pension linkage: receipt of employer pension
# income (r{w}ipen > 0), the same variable whose level feeds the DB component
# of the pre-existing income floor. A DB recipient demonstrably passed through
# an employer plan that annuitizes; the proxy is a conservative lower bound on
# access to institutionally priced annuitization (it misses DC-only workers
# whose plans offer annuity purchase options). Calibrated to COVERAGE data,
# not to any ownership rate, preserving the paper's no-fitting discipline.
#
# Sample filters and deflators identical to build_ss_profile.jl via
# hrs_common.jl: single nonworking retirees 65-69, waves 5-9.
#
# Output: data/processed/group_access_by_band.csv
# Usage:  julia --project=. calibration/build_group_access.jl

using ReadStatTables
using Printf
using Statistics

include(joinpath(@__DIR__, "hrs_common.jl"))
include(joinpath(@__DIR__, "..", "scripts", "config.jl"))

const WEALTH_BREAKS = [30_000.0, 120_000.0, 350_000.0]
bin_of(w) = w < WEALTH_BREAKS[1] ? 1 :
            w < WEALTH_BREAKS[2] ? 2 :
            w < WEALTH_BREAKS[3] ? 3 : 4

println("=" ^ 70)
println("  GROUP-ANNUITY ACCESS BY WEALTH BAND (employer-pension linkage)")
println("  Single nonworking retirees 65-69, waves 5-9")
println("=" ^ 70)

dta_path = joinpath(@__DIR__, "..", "data", "raw", "HRS",
    "randhrs1992_2022v1_STATA", "randhrs1992_2022v1.dta")
println("\nLoading RAND HRS longitudinal file...")
tbl = readstat(dta_path; ntasks=0)
N = length(tbl[1])
@printf("  Loaded %d respondents\n", N)

n_bin    = zeros(Int, 4)
n_access = zeros(Int, 4)
wt_bin   = zeros(4)
wt_access = zeros(4)

for w in 5:9
    d_w = deflator_wealth(w)

    age_c   = try collect(getproperty(tbl, Symbol("r$(w)agey_b"))) catch; nothing end
    mstat_c = try collect(getproperty(tbl, Symbol("r$(w)mstat")))  catch; nothing end
    lbrf_c  = try collect(getproperty(tbl, Symbol("r$(w)lbrf")))   catch; nothing end
    iws_c   = try collect(getproperty(tbl, Symbol("r$(w)iwstat"))) catch; nothing end
    wt_c    = try collect(getproperty(tbl, Symbol("r$(w)wtresp"))) catch; nothing end
    shlt_c  = try collect(getproperty(tbl, Symbol("r$(w)shlt")))   catch; nothing end
    atot_c  = try collect(getproperty(tbl, Symbol("h$(w)atotb")))  catch; nothing end
    ahous_c = try collect(getproperty(tbl, Symbol("h$(w)ahous")))  catch; nothing end
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

        has_pen = ipen_c !== nothing && !ismissing(ipen_c[i]) && numval_float(ipen_c[i]) > 0.0

        b = bin_of(wealth)
        n_bin[b] += 1
        wt_bin[b] += wt
        if has_pen
            n_access[b] += 1
            wt_access[b] += wt
        end
    end
end

labels = ["<30k", "30-120k", "120-350k", ">350k"]
@printf("\n  %-10s %8s %10s %12s %12s\n", "band", "n", "n_access", "access_unw", "access_wtd")
for b in 1:4
    @printf("  %-10s %8d %10d %11.1f%% %11.1f%%\n", labels[b], n_bin[b], n_access[b],
        100 * n_access[b] / max(n_bin[b], 1), 100 * wt_access[b] / max(wt_bin[b], 1e-12))
end
@printf("  %-10s %8d %10d %11.1f%%\n", "ALL", sum(n_bin), sum(n_access),
    100 * sum(n_access) / max(sum(n_bin), 1))

out = joinpath(@__DIR__, "..", "data", "processed", "group_access_by_band.csv")
open(out, "w") do f
    println(f, "band,band_label,n,n_access,access_unw,access_wtd")
    for b in 1:4
        @printf(f, "%d,%s,%d,%d,%.4f,%.4f\n", b, labels[b], n_bin[b], n_access[b],
            n_access[b] / max(n_bin[b], 1), wt_access[b] / max(wt_bin[b], 1e-12))
    end
end
println("\n  Saved: $out")
