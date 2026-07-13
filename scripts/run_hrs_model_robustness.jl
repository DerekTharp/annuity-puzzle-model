# Model-output robustness to the HRS population/weighting scheme.
#
# run_hrs_weighting_robustness.jl reweights only the OBSERVED ownership rate.
# This instead asks whether the MODEL-PREDICTED ownership level and wealth
# gradient are stable to how the evaluation population is weighted/defined. It is
# evaluation-only: the full nine-channel model (mask 511, production config, SS
# on so no commuted-PV top-up) is solved ONCE -- four band solutions differing
# only in the pre-existing-annuitization level -- and predicted ownership is then
# read off that solution several ways:
#   (a) unweighted       — equal weight per person-wave (baseline);
#   (b) weighted         — RAND person analysis weight r{w}wtresp (processed col);
#   (c) person-balanced  — one observation per person (first eligible wave).
# Methods (a)-(b) use the processed sample. Method (c) needs the person id, which
# lives only in the raw RAND file, so it is gated behind isfile like Stage 11d2.
# Two annuitizable-financial-wealth (liquid) definitions are likewise raw-gated
# (the processed sample carries only nonhousing net worth):
#   (d) liquid-band         — regroup + SS-assign by RAND h{w}atotf, but model
#                             wealth stays net worth (a mild re-banding check);
#   (e) liquid-wealth-model — model wealth ITSELF is h{w}atotf, so eligibility,
#                             premium capacity, and fixed-cost exposure all run
#                             on liquid wealth (the genuine liquid robustness).
#
# Coarse-grid smoke: ANNUITY_SMOKE=1 shrinks the grid; production uses the config
# grid. The evaluation is cheap (four solves); only the raw read is heavy.
#
# Output: tables/csv/hrs_model_robustness.csv (method, band, model_ownership_pct, n)
# Usage:  julia --project=. scripts/run_hrs_model_robustness.jl
#         ANNUITY_SMOKE=1 julia --project=. scripts/run_hrs_model_robustness.jl

using Printf, DelimitedFiles, Statistics, ReadStatTables

include(joinpath(@__DIR__, "..", "src", "AnnuityPuzzle.jl"))
using .AnnuityPuzzle
include(joinpath(@__DIR__, "config.jl"))
include(joinpath(@__DIR__, "..", "calibration", "hrs_common.jl"))

const SMOKE = get(ENV, "ANNUITY_SMOKE", "0") == "1"
const NW  = SMOKE ? 24 : N_WEALTH
const NA  = SMOKE ? 12 : N_ANNUITY
const NAL = SMOKE ? 31 : N_ALPHA
const NQ  = SMOKE ?  7 : N_QUAD

const BREAKS = SS_QUARTILE_BREAKS
band_of(w) = w < BREAKS[1] ? 1 : w < BREAKS[2] ? 2 : w < BREAKS[3] ? 3 : 4
const BAND_LABELS = ["<30k", "30-120k", "120-350k", ">350k"]

println("=" ^ 70)
println("  MODEL-OUTPUT HRS ROBUSTNESS: predicted ownership under alt. weights")
SMOKE && println("  [SMOKE] coarse grid $(NW)x$(NA)x$(NAL), n_quad=$(NQ)")
println("=" ^ 70); flush(stdout)

# ===================================================================
# Solve the full nine-channel model ONCE (four band solutions).
# ===================================================================
p_base = ModelParams(age_start=AGE_START, age_end=AGE_END)
base_surv = production_base_survival(p_base)
gkw = (n_wealth=NW, n_annuity=NA, n_alpha=NAL, W_max=W_MAX, age_start=AGE_START,
       age_end=AGE_END, annuity_grid_power=A_GRID_POW)
fair     = compute_payout_rate(ModelParams(; gamma=GAMMA, beta=BETA, r=R_RATE, mwr=1.0, gkw...), base_surv)
fair_nom = INFLATION > 0 ? compute_payout_rate(ModelParams(; gamma=GAMMA, beta=BETA, r=R_RATE, mwr=1.0, inflation_rate=INFLATION, gkw...), base_surv) : fair
pr = MWR_LOADED * fair_nom  # full model: loaded + nominal

cfg = build_subset_config(Set(1:9);
    theta_dfj=THETA_DFJ, kappa_dfj=KAPPA_DFJ, mwr_loaded=MWR_LOADED, fixed_cost=FIXED_COST,
    min_purchase=MIN_PURCHASE, inflation_val=INFLATION, survival_pessimism=SURVIVAL_PESSIMISM,
    ss_quartile_levels=Float64.(SS_QUARTILE_LEVELS), consumption_decline=CONSUMPTION_DECLINE,
    health_utility=Float64.(HEALTH_UTILITY), chi_ltc_val=CHI_LTC,
    lambda_w_val=LAMBDA_W, psi_purchase_val=PSI_PURCHASE, psi_purchase_c_ref_val=PSI_PURCHASE_C_REF,
    db_levels=Float64.(DB_OBS))
@assert !cfg.commute_ss "full model has SS on; no commuted-PV top-up expected"

common = (gamma=GAMMA, beta=BETA, r=R_RATE, stochastic_health=true, n_health_states=3,
          n_quad=NQ, c_floor=C_FLOOR, hazard_mult=Float64.(HAZARD_MULT), hazard_normalize=HAZARD_NORMALIZE)
grids = build_grids(ModelParams(; common..., mwr=1.0, gkw...), max(fair, fair_nom))
p_model = ModelParams(; common..., theta=cfg.theta, kappa=cfg.kappa, mwr=cfg.mwr,
    fixed_cost=cfg.fixed_cost, min_purchase=cfg.min_purchase, inflation_rate=cfg.inflation_rate,
    medical_enabled=cfg.medical_enabled, health_mortality_corr=cfg.health_mortality_corr,
    survival_pessimism=cfg.survival_pessimism, consumption_decline=cfg.consumption_decline,
    health_utility=cfg.health_utility, chi_ltc=cfg.chi_ltc, gkw...)

println("\nSolving four band solutions (SS levels $(round.(Int, cfg.ss_levels)))..."); flush(stdout)
t0 = time()
sols = Vector{Any}(undef, 4)
for q in 1:4
    ss_val = cfg.ss_levels[q]
    db_val = cfg.db_levels[q]
    sols[q] = solve_lifecycle_health(p_model, grids, base_surv,
                                     build_ss_func(ss_val - db_val, db_val, AGE_START))
end
@printf("  done in %.0fs\n", time() - t0); flush(stdout)

# Aggregate model-predicted ownership over `popmat` (cols wealth,0,age,health),
# banding by `bandvec` and evaluating each band against its SS solution. Reuses
# the four band solutions (no re-solve). `weights` optional per-row survey weight.
function eval_by_band(popmat, bandvec; weights=nothing)
    own_b = zeros(4); n_b = zeros(Int, 4); neval_b = zeros(4)
    for b in 1:4
        idx = findall(==(b), bandvec)
        isempty(idx) && continue
        w = weights === nothing ? nothing : weights[idx]
        r = compute_ownership_rate_health(sols[b], popmat[idx, :], pr; base_surv=base_surv, weights=w)
        own_b[b] = r.ownership_rate
        neval_b[b] = r.n_evaluated
        n_b[b] = length(idx)
    end
    agg = sum(neval_b) > 0 ? sum(own_b .* neval_b) / sum(neval_b) : 0.0
    return (own_b=own_b, n_b=n_b, agg=agg, agg_n=sum(n_b))
end

# method => (own_b::Vector, n_b::Vector, agg, agg_n). Written to CSV at the end.
methods = Tuple{String, NamedTuple}[]

report(method, res) = begin
    @printf("\n  %s:\n", method)
    for b in 1:4
        @printf("    %-10s %7.2f%%  (n=%d)\n", BAND_LABELS[b], res.own_b[b]*100, res.n_b[b])
    end
    @printf("    %-10s %7.2f%%  (n=%d)\n", "ALL", res.agg*100, res.agg_n)
    push!(methods, (method, res))
end

# ===================================================================
# Part A: unweighted + survey-weighted (processed sample, no re-solve)
# ===================================================================
pc = readdlm(HRS_PATH, ',', Any; skipstart=1)  # wealth,perm_income,age,health,own_life_ann,weight
assert_hrs_schema(pc, HRS_PATH)
wealth_pc = Float64.(pc[:, 1]); age_pc = Float64.(pc[:, 3])
health_pc = Float64.(pc[:, 4]); wt_pc = Float64.(pc[:, 6])
keep = wealth_pc .>= MIN_WEALTH
popA = hcat(wealth_pc[keep], zeros(count(keep)), age_pc[keep], health_pc[keep])
bandA = band_of.(wealth_pc[keep])
wtA = wt_pc[keep]
@printf("\nProcessed sample: %d person-waves with W >= \$%.0f\n", size(popA, 1), MIN_WEALTH)

report("unweighted", eval_by_band(popA, bandA))
report("weighted",   eval_by_band(popA, bandA; weights=wtA))

# ===================================================================
# Part B: person-balanced + liquid-wealth band definition (raw-gated)
# ===================================================================
dta_path = joinpath(@__DIR__, "..", "data", "raw", "HRS",
    "randhrs1992_2022v1_STATA", "randhrs1992_2022v1.dta")

if !isfile(dta_path)
    println("\nPart B SKIPPED: raw RAND HRS file not found (non-redistributable;")
    println("  expected on AWS / non-local machines).")
    println("  Person-balanced ownership and the liquid-wealth band definition")
    println("  require the person id (hhidpn) and h{w}atotf, which live only in raw.")
    println("  Expected path: $dta_path")
else
    println("\nPart B: loading RAND HRS longitudinal file (person id + h{w}atotf)..."); flush(stdout)
    tbl = readstat(dta_path; ntasks=0)
    N = length(tbl[1])
    @printf("  Loaded %d respondents\n", N); flush(stdout)
    hhidpn_col = collect(getproperty(tbl, :hhidpn))

    rec_id = Float64[]; rec_wave = Int[]
    rec_nhnw = Float64[]; rec_liq = Float64[]; rec_age = Float64[]; rec_h = Float64[]
    for w in 5:9
        d_w = deflator_wealth(w)
        age_col    = try collect(getproperty(tbl, Symbol("r$(w)agey_b"))) catch; nothing end
        mstat_col  = try collect(getproperty(tbl, Symbol("r$(w)mstat")))  catch; nothing end
        lbrf_col   = try collect(getproperty(tbl, Symbol("r$(w)lbrf")))   catch; nothing end
        shlt_col   = try collect(getproperty(tbl, Symbol("r$(w)shlt")))   catch; nothing end
        iwstat_col = try collect(getproperty(tbl, Symbol("r$(w)iwstat"))) catch; nothing end
        wtresp_col = try collect(getproperty(tbl, Symbol("r$(w)wtresp"))) catch; nothing end
        atotb_col  = try collect(getproperty(tbl, Symbol("h$(w)atotb")))  catch; nothing end
        ahous_col  = try collect(getproperty(tbl, Symbol("h$(w)ahous")))  catch; nothing end
        atotf_col  = try collect(getproperty(tbl, Symbol("h$(w)atotf")))  catch; nothing end
        (age_col === nothing || mstat_col === nothing || lbrf_col === nothing) && continue
        @assert iwstat_col !== nothing "missing r$(w)iwstat"
        @assert atotf_col !== nothing "missing h$(w)atotf"
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
            numval_float(wtresp_col[i]) <= 0.0 && continue
            (shlt_col === nothing || ismissing(shlt_col[i])) && continue
            shlt_raw = numval(shlt_col[i]); (shlt_raw < 1 || shlt_raw > 5) && continue

            nhnw = 0.0
            (atotb_col !== nothing && !ismissing(atotb_col[i])) && (nhnw = numval_float(atotb_col[i]))
            (ahous_col !== nothing && !ismissing(ahous_col[i])) && (nhnw -= numval_float(ahous_col[i]))
            nhnw = max(nhnw, 0.0) * d_w
            liq = ismissing(atotf_col[i]) ? 0.0 : max(numval_float(atotf_col[i]), 0.0) * d_w

            push!(rec_id, numval_float(hhidpn_col[i])); push!(rec_wave, w)
            push!(rec_nhnw, nhnw); push!(rec_liq, liq); push!(rec_age, Float64(age))
            push!(rec_h, shlt_raw <= 2 ? 1.0 : (shlt_raw == 3 ? 2.0 : 3.0))  # build_hrs_sample map
        end
    end
    # Model-eligible on the model's wealth concept (net worth).
    elig = rec_nhnw .>= MIN_WEALTH
    rid = rec_id[elig]; rwave = rec_wave[elig]; rnhnw = rec_nhnw[elig]
    rliq = rec_liq[elig]; rage = rec_age[elig]; rh = rec_h[elig]
    @printf("  Raw eligible person-waves (W >= \$%.0f): %d (processed: %d)\n",
            MIN_WEALTH, length(rid), size(popA, 1))

    # Cross-check: raw unweighted net-worth banding vs processed unweighted.
    popR = hcat(rnhnw, zeros(length(rid)), rage, rh)
    bandR = band_of.(rnhnw)
    res_raw_unw = eval_by_band(popR, bandR)
    maxdiff = maximum(abs.(res_raw_unw.own_b .- methods[1][2].own_b)) * 100
    @printf("  Cross-check max |raw - processed| by-band ownership: %.3f pp\n", maxdiff); flush(stdout)

    # (c) Person-balanced: first eligible wave per person.
    first_wave = Dict{Float64,Int}()
    for i in eachindex(rid)
        (!haskey(first_wave, rid[i]) || rwave[i] < first_wave[rid[i]]) && (first_wave[rid[i]] = rwave[i])
    end
    seen = Set{Float64}(); pbidx = Int[]
    for i in eachindex(rid)
        (rwave[i] == first_wave[rid[i]] && !(rid[i] in seen)) || continue
        push!(seen, rid[i]); push!(pbidx, i)
    end
    report("person-balanced", eval_by_band(popR[pbidx, :], band_of.(rnhnw[pbidx])))

    # (d) Liquid-band: regroup + SS-assign by h{w}atotf, but MODEL wealth stays
    # net worth (popR col 1 = rnhnw). Milder sensitivity — eligibility, premium
    # capacity, and fixed-cost exposure still run on net worth; only band
    # membership and the pre-existing-annuitization level move to liquid wealth.
    # Person-wave level, unweighted.
    report("liquid-band", eval_by_band(popR, band_of.(rliq)))

    # (e) Liquid-wealth model: MODEL wealth column IS liquid financial wealth
    # (h{w}atotf), so eligibility (is_feasible_purchase), premium capacity
    # (pi = alpha*W), and fixed-cost exposure all run on liquid wealth, with band
    # membership and SS assigned by liquid wealth too. Reuses the four band
    # solutions (no re-solve); the liquid-band row only re-bands a net-worth model.
    popLiq = hcat(rliq, zeros(length(rliq)), rage, rh)
    report("liquid-wealth-model", eval_by_band(popLiq, band_of.(rliq)))
end

# ===================================================================
# Write CSV
# ===================================================================
csvdir = joinpath(@__DIR__, "..", "tables", "csv"); mkpath(csvdir)
csv = joinpath(csvdir, "hrs_model_robustness.csv")
open(csv, "w") do io
    println(io, "method,band,model_ownership_pct,n")
    for (method, res) in methods
        for b in 1:4
            @printf(io, "%s,%s,%.4f,%d\n", method, BAND_LABELS[b], res.own_b[b]*100, res.n_b[b])
        end
        @printf(io, "%s,%s,%.4f,%d\n", method, "all", res.agg*100, res.agg_n)
    end
end
println("\n  CSV: $csv"); flush(stdout)

println("\n  Headline predicted level/gradient stable across weighting schemes")
println("  when the ALL rate and the monotone by-band gradient agree across methods.")
println("=" ^ 70); flush(stdout)
