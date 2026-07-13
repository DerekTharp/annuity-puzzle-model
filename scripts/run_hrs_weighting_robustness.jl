# HRS observed-ownership weighting robustness + wealth-definition band membership.
#
# Two robustness checks on the empirical annuity-ownership comparator (the
# per-person-wave indicator carried in data/processed/lockwood_hrs_sample.csv:
# own_life_ann = 1 when RAND r{w}iann > 0). Sample and filters mirror
# calibration/build_hrs_sample.jl exactly (single nonworking retirees 65-69,
# waves 5-9, alive respondents, valid health, positive person weight).
#
# 6.2  By-band ownership under three methods:
#        unweighted       — equal weight per person-wave;
#        weighted         — RAND person-level analysis weight r{w}wtresp;
#        person-balanced  — one observation per person (first eligible wave),
#                           unweighted (removes multiple-wave over-representation).
#      Bands are the model's SS_QUARTILE_BREAKS applied to NONHOUSING NET WORTH.
#      Output: tables/csv/hrs_weighting_robustness.csv
#              (method, band, ownership_pct, n)
#
# 6.3  Band membership under two wealth definitions:
#        nonhousing_net_worth   — RAND h{w}atotb - h{w}ahous (= h{w}atotn), the
#                                 production banding variable;
#        liquid_financial_wealth— RAND h{w}atotf ("Non-Housing Financial
#                                 Wealth"), which EXCLUDES housing, IRAs,
#                                 business, vehicles, and non-primary real estate.
#      Output: tables/csv/hrs_wealth_definition_bands.csv
#              (wealth_measure, band, n_personwaves, n_persons, median_wealth_2014usd)
#
# Unweighted and weighted rates (Part A) are computed as post-processing of the
# existing processed sample (no raw reload, no model re-solve); person-balanced
# and the liquid-wealth definition require the person id (hhidpn) and h{w}atotf,
# which are read from the RAND longitudinal file (Part B). Part B independently
# reproduces the unweighted rates as a cross-check.
#
# Usage: julia --project=. scripts/run_hrs_weighting_robustness.jl

using ReadStatTables, Printf, DelimitedFiles, Statistics

include(joinpath(@__DIR__, "..", "calibration", "hrs_common.jl"))
include(joinpath(@__DIR__, "config.jl"))

# Model wealth bins (src/decomposition.jl SS_QUARTILE_BREAKS) — keep identical
# so the observed comparator maps onto the four cells the solver uses.
const WEALTH_BREAKS = [30_000.0, 120_000.0, 350_000.0]
band_of(w) = w < WEALTH_BREAKS[1] ? 1 :
             w < WEALTH_BREAKS[2] ? 2 :
             w < WEALTH_BREAKS[3] ? 3 : 4
const BAND_LABELS = ["<30k", "30-120k", "120-350k", ">350k"]

function main()
println("=" ^ 70)
println("  HRS OWNERSHIP WEIGHTING ROBUSTNESS + WEALTH-DEFINITION BANDS")
println("  Single nonworking retirees 65-69, waves 5-9, 2014 dollars")
println("=" ^ 70)

# ===================================================================
# Part A: unweighted + weighted from the processed sample (post-processing)
# ===================================================================
println("\nPart A: reweighting the processed sample (no model re-solve)...")
pc = readdlm(HRS_PATH, ',', Any; skipstart=1)  # wealth,perm_income,age,health,own_life_ann,weight
wealth_pc = Float64.(pc[:, 1])
own_pc    = Float64.(pc[:, 5])
wt_pc     = Float64.(pc[:, 6])
n_pc      = length(wealth_pc)
@printf("  Processed sample: %d person-waves\n", n_pc)

# Accumulators by band (index 5 = pooled "all").
own_unw = zeros(5); n_unw = zeros(Int, 5)
own_wtd = zeros(5); w_wtd = zeros(5)
for i in 1:n_pc
    b = band_of(wealth_pc[i])
    own_unw[b] += own_pc[i]; n_unw[b] += 1
    own_wtd[b] += own_pc[i] * wt_pc[i]; w_wtd[b] += wt_pc[i]
    own_unw[5] += own_pc[i]; n_unw[5] += 1
    own_wtd[5] += own_pc[i] * wt_pc[i]; w_wtd[5] += wt_pc[i]
end
rate_unw = [n_unw[b] > 0 ? own_unw[b] / n_unw[b] : 0.0 for b in 1:5]
rate_wtd = [w_wtd[b] > 0 ? own_wtd[b] / w_wtd[b] : 0.0 for b in 1:5]

# ===================================================================
# Part B: raw RAND file for person-balancing + liquid-wealth bands
# ===================================================================
println("\nPart B: loading RAND HRS longitudinal file (person id + h{w}atotf)...")
dta_path = joinpath(@__DIR__, "..", "data", "raw", "HRS",
    "randhrs1992_2022v1_STATA", "randhrs1992_2022v1.dta")
tbl = readstat(dta_path; ntasks=0)
N = length(tbl[1])
@printf("  Loaded %d respondents\n", N)

hhidpn_col = collect(getproperty(tbl, :hhidpn))

waves = 5:9
# Per person-wave records.
rec_id   = Float64[]
rec_wave = Int[]
rec_own  = Float64[]
rec_nhnw = Float64[]   # nonhousing net worth (2014$)
rec_liq  = Float64[]   # liquid financial wealth (2014$)
rec_wt   = Float64[]
n_missing_atotf = 0

for w in waves
    d_w = deflator_wealth(w)
    age_col    = try collect(getproperty(tbl, Symbol("r$(w)agey_b"))) catch; nothing end
    mstat_col  = try collect(getproperty(tbl, Symbol("r$(w)mstat")))  catch; nothing end
    lbrf_col   = try collect(getproperty(tbl, Symbol("r$(w)lbrf")))   catch; nothing end
    shltc_col  = try collect(getproperty(tbl, Symbol("r$(w)shlt")))   catch; nothing end
    iwstat_col = try collect(getproperty(tbl, Symbol("r$(w)iwstat"))) catch; nothing end
    wtresp_col = try collect(getproperty(tbl, Symbol("r$(w)wtresp"))) catch; nothing end
    atotb_col  = try collect(getproperty(tbl, Symbol("h$(w)atotb")))  catch; nothing end
    ahous_col  = try collect(getproperty(tbl, Symbol("h$(w)ahous")))  catch; nothing end
    atotf_col  = try collect(getproperty(tbl, Symbol("h$(w)atotf")))  catch; nothing end
    iann_col   = try collect(getproperty(tbl, Symbol("r$(w)iann")))   catch; nothing end

    (age_col === nothing || mstat_col === nothing || lbrf_col === nothing) && continue
    @assert iwstat_col !== nothing "missing r$(w)iwstat"
    @assert atotf_col !== nothing "missing h$(w)atotf (liquid financial wealth)"

    for i in 1:N
        ismissing(iwstat_col[i]) && continue
        numval(iwstat_col[i]) != 1 && continue
        ismissing(age_col[i]) && continue
        age = numval(age_col[i]); (age < 65 || age > 69) && continue
        ismissing(mstat_col[i]) && continue
        numval(mstat_col[i]) in SINGLE_MSTAT || continue
        ismissing(lbrf_col[i]) && continue
        numval(lbrf_col[i]) in RETIRED_LBRF || continue
        (wtresp_col === nothing || ismissing(wtresp_col[i])) && continue
        wt = numval_float(wtresp_col[i]); wt <= 0.0 && continue
        (shltc_col === nothing || ismissing(shltc_col[i])) && continue
        shlt_raw = numval(shltc_col[i]); (shlt_raw < 1 || shlt_raw > 5) && continue

        # Nonhousing net worth = h{w}atotb - h{w}ahous (RAND h{w}atotn).
        nhnw = 0.0
        (atotb_col !== nothing && !ismissing(atotb_col[i])) && (nhnw = numval_float(atotb_col[i]))
        (ahous_col !== nothing && !ismissing(ahous_col[i])) && (nhnw -= numval_float(ahous_col[i]))
        nhnw = max(nhnw, 0.0) * d_w

        # Liquid financial wealth = h{w}atotf (Non-Housing Financial Wealth).
        if ismissing(atotf_col[i])
            n_missing_atotf += 1
            liq = 0.0
        else
            liq = max(numval_float(atotf_col[i]), 0.0) * d_w
        end

        own = (iann_col !== nothing && !ismissing(iann_col[i]) &&
               numval_float(iann_col[i]) > 0.0) ? 1.0 : 0.0

        push!(rec_id, numval_float(hhidpn_col[i]))
        push!(rec_wave, w)
        push!(rec_own, own)
        push!(rec_nhnw, nhnw)
        push!(rec_liq, liq)
        push!(rec_wt, wt)
    end
end
n_raw = length(rec_id)
@printf("  Raw eligible person-waves: %d (processed sample: %d)\n", n_raw, n_pc)
n_raw == n_pc || @warn "raw N != processed N; filter drift" n_raw n_pc

# Cross-check: raw unweighted by-band ownership should match Part A.
rawchk_own = zeros(5); rawchk_n = zeros(Int, 5)
for i in 1:n_raw
    b = band_of(rec_nhnw[i])
    rawchk_own[b] += rec_own[i]; rawchk_n[b] += 1
    rawchk_own[5] += rec_own[i]; rawchk_n[5] += 1
end
rawchk_rate = [rawchk_n[b] > 0 ? rawchk_own[b] / rawchk_n[b] : 0.0 for b in 1:5]
maxdiff = maximum(abs.(rawchk_rate .- rate_unw))
@printf("  Cross-check max |raw unweighted - processed unweighted| = %.4g pp\n", maxdiff * 100)

# --- Person-balanced: first eligible wave per person (earliest wave) ---
first_wave = Dict{Float64, Int}()
for i in 1:n_raw
    id = rec_id[i]
    if !haskey(first_wave, id) || rec_wave[i] < first_wave[id]
        first_wave[id] = rec_wave[i]
    end
end
own_pb = zeros(5); n_pb = zeros(Int, 5)
seen = Set{Float64}()
for i in 1:n_raw
    id = rec_id[i]
    (rec_wave[i] == first_wave[id] && !(id in seen)) || continue
    push!(seen, id)
    b = band_of(rec_nhnw[i])
    own_pb[b] += rec_own[i]; n_pb[b] += 1
    own_pb[5] += rec_own[i]; n_pb[5] += 1
end
rate_pb = [n_pb[b] > 0 ? own_pb[b] / n_pb[b] : 0.0 for b in 1:5]
@printf("  Unique persons (first eligible wave): %d\n", n_pb[5])

# ===================================================================
# Report: ownership by band under the three methods
# ===================================================================
println("\n  OBSERVED OWNERSHIP BY BAND (own_life_ann = r_iann > 0):")
@printf("  %-10s %12s %12s %14s\n", "band", "unweighted", "weighted", "person-balanced")
for b in 1:4
    @printf("  %-10s %9.2f%% (%d) %9.2f%% (%d) %10.2f%% (%d)\n",
        BAND_LABELS[b], rate_unw[b]*100, n_unw[b], rate_wtd[b]*100, n_unw[b],
        rate_pb[b]*100, n_pb[b])
end
@printf("  %-10s %9.2f%% (%d) %9.2f%% (%d) %10.2f%% (%d)\n",
    "ALL", rate_unw[5]*100, n_unw[5], rate_wtd[5]*100, n_unw[5], rate_pb[5]*100, n_pb[5])

# ===================================================================
# Wealth-definition band membership (6.3)
# ===================================================================
# Person-wave counts and per-person (first-wave) counts by band, under each
# wealth definition. The first-wave record per person supplies the person-level
# wealth used for the person count and median.
nw_pw = zeros(Int, 4); liq_pw = zeros(Int, 4)
nw_vals = [Float64[] for _ in 1:4]; liq_vals = [Float64[] for _ in 1:4]
nw_p = zeros(Int, 4); liq_p = zeros(Int, 4)
seen2 = Set{Float64}()
n_shift = 0
for i in 1:n_raw
    bnw = band_of(rec_nhnw[i]); bliq = band_of(rec_liq[i])
    nw_pw[bnw] += 1; liq_pw[bliq] += 1
    push!(nw_vals[bnw], rec_nhnw[i]); push!(liq_vals[bliq], rec_liq[i])
    bnw != bliq && (n_shift += 1)
    id = rec_id[i]
    if rec_wave[i] == first_wave[id] && !(id in seen2)
        push!(seen2, id)
        nw_p[band_of(rec_nhnw[i])] += 1
        liq_p[band_of(rec_liq[i])] += 1
    end
end
med(v) = isempty(v) ? 0.0 : median(v)

println("\n  BAND MEMBERSHIP BY WEALTH DEFINITION (person-waves / persons):")
@printf("  %-10s | %-28s | %-28s\n", "band", "nonhousing net worth", "liquid financial wealth")
@printf("  %-10s | %10s %8s %8s | %10s %8s %8s\n",
    "", "n_pw", "n_pers", "median", "n_pw", "n_pers", "median")
for b in 1:4
    @printf("  %-10s | %10d %8d %8.0f | %10d %8d %8.0f\n",
        BAND_LABELS[b], nw_pw[b], nw_p[b], med(nw_vals[b]),
        liq_pw[b], liq_p[b], med(liq_vals[b]))
end
@printf("\n  Person-waves that change band under the liquid definition: %d of %d (%.1f%%)\n",
    n_shift, n_raw, n_shift / n_raw * 100)
n_missing_atotf > 0 && @printf("  (h{w}atotf missing for %d eligible person-waves, set to 0)\n", n_missing_atotf)

# ===================================================================
# Write CSVs
# ===================================================================
csvdir = joinpath(@__DIR__, "..", "tables", "csv")
mkpath(csvdir)

csv1 = joinpath(csvdir, "hrs_weighting_robustness.csv")
open(csv1, "w") do io
    println(io, "method,band,ownership_pct,n")
    for (method, rate, ns) in (("unweighted", rate_unw, n_unw),
                               ("weighted", rate_wtd, n_unw),
                               ("person-balanced", rate_pb, n_pb))
        for b in 1:4
            @printf(io, "%s,%s,%.4f,%d\n", method, BAND_LABELS[b], rate[b]*100, ns[b])
        end
        @printf(io, "%s,%s,%.4f,%d\n", method, "all", rate[5]*100, ns[5])
    end
end
@printf("\n  CSV: %s\n", csv1)

csv2 = joinpath(csvdir, "hrs_wealth_definition_bands.csv")
open(csv2, "w") do io
    println(io, "wealth_measure,band,n_personwaves,n_persons,median_wealth_2014usd")
    for b in 1:4
        @printf(io, "nonhousing_net_worth,%s,%d,%d,%.1f\n",
            BAND_LABELS[b], nw_pw[b], nw_p[b], med(nw_vals[b]))
    end
    for b in 1:4
        @printf(io, "liquid_financial_wealth,%s,%d,%d,%.1f\n",
            BAND_LABELS[b], liq_pw[b], liq_p[b], med(liq_vals[b]))
    end
end
@printf("  CSV: %s\n", csv2)

println("\n" * "=" ^ 70)
println("  DONE")
println("=" ^ 70)
end  # main

main()
