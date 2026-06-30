# q286 lifetime-SPIA ownership rate BY WEALTH BAND (verification probe).
# Reuses the EXACT sample filters and wealth definition from
# compute_lifetime_ownership_rate.jl, but stratifies the lifetime indicator
# into the model's four SS_QUARTILE_BREAKS wealth bands ($30k/$120k/$350k on
# CPI-deflated non-housing wealth). Unweighted and respondent-weighted rates.

using ReadStatTables
using Printf
using Statistics

const PROJ = joinpath(@__DIR__, "..")
const RAND_HRS = joinpath(PROJ, "data", "raw", "HRS",
                          "randhrs1992_2022v1_STATA", "randhrs1992_2022v1.dta")

WAVES = [
    (5, "h00f1d", [Symbol("g5494_1"), Symbol("g5494_2")]),
    (6, "h02f2c", [Symbol("hq286_1"), Symbol("hq286_2")]),
    (7, "h04f1c", [Symbol("jq286_1"), Symbol("jq286_2")]),
    (8, "h06f4b", [Symbol("kq286_1"), Symbol("kq286_2")]),
    (9, "h08f3b", [Symbol("lq286_1"), Symbol("lq286_2")]),
]

include(joinpath(@__DIR__, "hrs_common.jl"))
include(joinpath(@__DIR__, "..", "scripts", "config.jl"))

const BREAKS = [30_000.0, 120_000.0, 350_000.0]
band_of(w) = w < BREAKS[1] ? 1 : w < BREAKS[2] ? 2 : w < BREAKS[3] ? 3 : 4

rand_tbl = readstat(RAND_HRS)
const RAND_HHIDPN = collect(getproperty(rand_tbl, :hhidpn))
rand_idx = Dict{Float64, Int}()
for (i, h) in enumerate(RAND_HHIDPN)
    ismissing(h) || (rand_idx[Float64(h)] = i)
end

# accumulators per band: n, weighted denom, lifetime count, weighted lifetime,
# iann count, any-contract count
n_b      = zeros(Int, 4)
wt_b     = zeros(Float64, 4)
life_b   = zeros(Int, 4)
wlife_b  = zeros(Float64, 4)
iann_b   = zeros(Int, 4)
anyc_b   = zeros(Int, 4)

for (w, ff, life_vars) in WAVES
    fat_path = joinpath(PROJ, "data", "raw", "HRS", "HRS Fat Files",
                       "$(ff)_STATA", "$(ff).dta")
    fat_tbl = readstat(fat_path)
    fat_hhidpn = collect(getproperty(fat_tbl, :hhidpn))

    age_col    = collect(getproperty(rand_tbl, Symbol("r$(w)agey_b")))
    mstat_col  = collect(getproperty(rand_tbl, Symbol("r$(w)mstat")))
    lbrf_col   = collect(getproperty(rand_tbl, Symbol("r$(w)lbrf")))
    wtresp_col = collect(getproperty(rand_tbl, Symbol("r$(w)wtresp")))
    shlt_col   = collect(getproperty(rand_tbl, Symbol("r$(w)shlt")))
    hatotb_col = collect(getproperty(rand_tbl, Symbol("h$(w)atotb")))
    hahous_col = collect(getproperty(rand_tbl, Symbol("h$(w)ahous")))
    iwstat_col = collect(getproperty(rand_tbl, Symbol("r$(w)iwstat")))
    iann_col   = collect(getproperty(rand_tbl, Symbol("r$(w)iann")))

    life_cols = []
    for v in life_vars
        hasproperty(fat_tbl, v) && push!(life_cols, collect(getproperty(fat_tbl, v)))
    end

    for fi in 1:length(fat_hhidpn)
        ismissing(fat_hhidpn[fi]) && continue
        h = Float64(fat_hhidpn[fi])
        ri = get(rand_idx, h, nothing)
        ri === nothing && continue

        (iwstat_col[ri] === missing || numval_float(iwstat_col[ri]) != 1) && continue
        ismissing(age_col[ri]) && continue
        age = numval_float(age_col[ri]); (age < 65 || age > 69) && continue
        ismissing(mstat_col[ri]) && continue
        numval_float(mstat_col[ri]) in SINGLE_MSTAT || continue
        ismissing(lbrf_col[ri]) && continue
        numval_float(lbrf_col[ri]) in RETIRED_LBRF || continue
        (ismissing(wtresp_col[ri]) || numval_float(wtresp_col[ri]) <= 0.0) && continue
        ismissing(shlt_col[ri]) && continue
        ismissing(hatotb_col[ri]) && continue

        wealth_total = numval_float(hatotb_col[ri])
        wealth_house = ismissing(hahous_col[ri]) ? 0.0 : numval_float(hahous_col[ri])
        wnh = max(wealth_total - wealth_house, 0.0) * deflator_wealth(w)
        wnh >= MIN_WEALTH || continue

        b = band_of(wnh)
        wt = numval_float(wtresp_col[ri])
        n_b[b]  += 1
        wt_b[b] += wt

        (iann_col[ri] !== missing && numval_float(iann_col[ri]) > 0) && (iann_b[b] += 1)

        any_contract = false; any_lifetime = false
        for col in life_cols
            v = col[fi]; ismissing(v) && continue
            val = numval_float(v)
            (val == 1.0 || val == 5.0 || val == 8.0 || val == 9.0) && (any_contract = true)
            val == 1.0 && (any_lifetime = true)
        end
        any_contract && (anyc_b[b] += 1)
        if any_lifetime
            life_b[b] += 1
            wlife_b[b] += wt
        end
    end
end

println("=" ^ 78)
println("  q286 LIFETIME-SPIA OWNERSHIP BY WEALTH BAND")
println("  (single nonworking retirees 65-69, waves 5-9, CPI-deflated non-housing wealth)")
println("=" ^ 78)
labels = ["<\$30k", "\$30-120k", "\$120-350k", ">\$350k"]
@printf("  %-12s %6s %8s %10s %12s %10s %10s\n",
        "band", "n", "life", "life_unw%", "life_wtd%", "iann%", "anyC%")
println("  " * "-" ^ 72)
for b in 1:4
    @printf("  %-12s %6d %8d %9.2f %11.2f %9.2f %9.2f\n",
        labels[b], n_b[b], life_b[b],
        100*life_b[b]/max(n_b[b],1),
        100*wlife_b[b]/max(wt_b[b],1),
        100*iann_b[b]/max(n_b[b],1),
        100*anyc_b[b]/max(n_b[b],1))
end
println("  " * "-" ^ 72)
tot_n = sum(n_b); tot_life = sum(life_b); tot_wt = sum(wt_b); tot_wlife = sum(wlife_b)
@printf("  %-12s %6d %8d %9.2f %11.2f\n", "POOLED", tot_n, tot_life,
        100*tot_life/max(tot_n,1), 100*tot_wlife/max(tot_wt,1))

# Save CSV
out_path = joinpath(PROJ, "data", "processed", "hrs_lifetime_ownership_by_band.csv")
open(out_path, "w") do f
    println(f, "band,band_label,n,n_lifetime,lifetime_unw_pct,lifetime_wtd_pct,iann_pct,anyc_pct")
    for b in 1:4
        @printf(f, "%d,%s,%d,%d,%.4f,%.4f,%.4f,%.4f\n", b, labels[b], n_b[b], life_b[b],
            100*life_b[b]/max(n_b[b],1), 100*wlife_b[b]/max(wt_b[b],1),
            100*iann_b[b]/max(n_b[b],1), 100*anyc_b[b]/max(n_b[b],1))
    end
end
println("\n  Saved: $out_path")
