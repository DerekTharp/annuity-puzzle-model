# =============================================================================
# 08_calibration_robustness.jl — Calibration, robustness, and sensitivity scripts.
#
# This file consolidates:
#   scripts/config.jl                          canonical baseline parameters
#   scripts/estimate_psi.jl                    UK-anchored psi_purchase SMM estimator
#   scripts/run_psi_sensitivity.jl             psi_purchase sensitivity sweep
#   scripts/run_robustness.jl                  full-grid robustness across parameters
#   scripts/run_monte_carlo_uncertainty.jl     joint parameter uncertainty
#   scripts/run_implied_gamma.jl               implied risk-aversion bisection
#   scripts/run_multigamma_decomposition.jl    decomposition across gamma values
#   scripts/run_state_utility_sensitivity.jl   state-dependent utility sensitivity
#   scripts/run_ageband_hazard.jl              age-band hazard estimation from HRS
#   scripts/run_ss_robustness.jl               Social Security robustness
#   scripts/grid_convergence_full.jl           grid convergence diagnostic
# =============================================================================

#=============================================================================
# ORIGINAL FILE: scripts/config.jl
#=============================================================================

# Baseline calibration constants shared across all scripts.
# Change values here; all scripts will pick them up.

const GAMMA      = 2.5
const BETA       = 0.97
const R_RATE     = 0.02
const AGE_START  = 65
const AGE_END    = 110
const C_FLOOR    = 6_180.0
const W_MAX      = 3_000_000.0  # covers p99.5 of HRS wealth distribution
const MWR_LOADED = 0.87          # Wettstein (2021) modern-market estimate
const FIXED_COST = 1_000.0
const MIN_PURCHASE = 10_000.0    # modal SPIA minimum across major issuers
                                  # (Pacific Life, NY Life, MassMutual, Lincoln,
                                  # Symetra, Mutual of Omaha, etc.); LIMRA modern
                                  # market data. Pashchenko (2013) used $25K
                                  # reflecting late-2000s sample.
const INFLATION  = 0.02
const N_WEALTH   = 80
const N_ANNUITY  = 30
const N_ALPHA    = 101
const A_GRID_POW = 3.0
const N_QUAD     = 9
const THETA_DFJ  = 56.96
const KAPPA_DFJ  = 272_628.0
const SURVIVAL_PESSIMISM = 0.981
const MIN_WEALTH = 5_000.0

# Hazard multipliers — production now uses age-varying HRS estimates with
# constant fallback. Constant baseline kept for back-compat with scripts that
# don't accept matrices yet.
const HAZARD_MULT = [0.50, 1.0, 3.0]                    # constant fallback
const HAZARD_MULT_AGE_BANDS = [0.49 1.00 3.29;          # ages 65-74
                               0.60 1.00 2.77;          # ages 75-84
                               0.74 1.00 1.82]          # ages 85+
const HAZARD_MULT_AGE_MIDPOINTS = [69.5, 79.5, 90.0]    # band midpoints

const CONSUMPTION_DECLINE = 0.02  # age-varying consumption needs (Aguiar-Hurst 2013)
const HEALTH_UTILITY = [1.0, 0.90, 0.75]  # state-dep utility — raw FLN central (production)
const PSI_PURCHASE = 0.0163       # narrow-framing purchase penalty (Barberis-Huang 2009;
                                   # Tversky-Kahneman 1992 loss aversion). Decays with
                                   # cumulative payouts; vanishes at breakeven.
                                   # CALIBRATION: single-moment SMM on the ABI
                                   # rational-corrected mid sensitivity target — UK 2015
                                   # pension freedoms aggregate sales-volume decline
                                   # mapped through the model after stripping the
                                   # rational tax-removal response (lump-sum 55% tax
                                   # penalty removal already represented in the model's
                                   # rational pricing channels). Production point;
                                   # bracket low end. Bracket high end ψ=0.0335
                                   # corresponds to the ELSA microdata total drop with
                                   # no rational stripping. The full sensitivity range
                                   # across alternative single-anchor SMM specifications
                                   # is reported in the appendix. NOT calibrated to
                                   # observed US ownership.
const LAMBDA_W = 0.625            # source-dependent utility (FPR companion paper;
                                   # Blanchett-Finke 2024-25): retirees spend ~80% of
                                   # income but only ~50% of portfolio → 50/80 = 0.625.
                                   # 1.0 = SDU off; <1.0 = portfolio dollars discounted.

# HRS population data path
const HRS_PATH = joinpath(@__DIR__, "..", "data", "processed", "lockwood_hrs_sample.csv")

#=============================================================================
# ORIGINAL FILE: scripts/estimate_psi.jl
#=============================================================================

# Estimate the narrow-framing purchase penalty psi via single-moment SMM
# on the UK 2015 pension-freedoms reform retention moment.
#
# Identification:
#   The UK April 2015 pension-freedoms reform flipped the choice architecture
#   from compulsory annuitization to opt-in. Annuity sales fell 75-87% (ABI/FCA).
#   Post-reform retention rate is 13-25% across estimates with mid-range ~17%.
#
# Estimator: bisection on psi to match the model's voluntary opt-in ownership
# rate to the UK retention target. Just-identified single-moment SMM. Sensitivity
# is computed over the UK retention range [0.13, 0.25].
#
# Honest framing: this is calibration to a non-target external moment from a
# distinct natural experiment, not curve-fitting to US observed ownership. The
# resulting US prediction is an out-of-sample test of the model.
#
# Output: results/psi_estimation.json with point estimate, sensitivity bounds,
# and metadata. Also tables/csv/psi_estimation.csv for easier downstream parsing.
#
# Runtime: ~12 model solves at 5 min each. With 188 workers, the bisection
# parallelizes by evaluating a small grid in parallel and refining serially.

using Printf
using DelimitedFiles
using Distributed
using Dates

if nworkers() > 1
    @everywhere include(joinpath(@__DIR__, "..", "src", "AnnuityPuzzle.jl"))
    @everywhere using .AnnuityPuzzle
else
    include(joinpath(@__DIR__, "..", "src", "AnnuityPuzzle.jl"))
    using .AnnuityPuzzle
end

include(joinpath(@__DIR__, "config.jl"))

const CONSUMPTION_DECLINE_ACTIVE = 0.02
const HEALTH_UTILITY_ACTIVE = [1.0, 0.90, 0.75]

# UK retention range. Mid-range from FCA Retirement Outcomes Review;
# bracket from ABI annual reports 2015-2024. Subtract a 15-25% rational
# tax-effect component if isolating the pure behavioral residual.
const UK_RETENTION_LOW   = 0.13
const UK_RETENTION_MID   = 0.17
const UK_RETENTION_HIGH  = 0.25

const PSI_BISECTION_LO   = 0.0
const PSI_BISECTION_HI   = 1.0
const PSI_TOLERANCE      = 0.005   # match retention to within 0.5 pp
const PSI_MAX_ITER       = 25

const OUT_JSON = joinpath(@__DIR__, "..", "results", "psi_estimation.json")
const OUT_CSV  = joinpath(@__DIR__, "..", "tables", "csv", "psi_estimation.csv")

# ---------------------------------------------------------------------------
# Load HRS sample, survival, payouts, grids (shared across all psi solves)
# ---------------------------------------------------------------------------

println("Loading HRS sample...")
hrs_raw = readdlm(HRS_PATH, ',', Any; skipstart=1)
n_pop = size(hrs_raw, 1)
population = zeros(n_pop, 4)
population[:, 1] = Float64.(hrs_raw[:, 1])
population[:, 2] .= 0.0
population[:, 3] = Float64.(hrs_raw[:, 3])
if size(hrs_raw, 2) >= 4
    population[:, 4] = Float64.(hrs_raw[:, 4])
else
    population[:, 4] .= 2.0
end
pop = population[population[:, 1] .>= MIN_WEALTH, :]
if size(pop, 2) < 4
    pop = hcat(pop, fill(2.0, size(pop, 1)))
end
@printf("  Eligible: %d\n", size(pop, 1))

p_base = ModelParams(age_start=AGE_START, age_end=AGE_END)
base_surv = build_lockwood_survival(p_base)

grid_kw = (n_wealth=N_WEALTH, n_annuity=N_ANNUITY, n_alpha=N_ALPHA,
           W_max=W_MAX, age_start=AGE_START, age_end=AGE_END,
           annuity_grid_power=A_GRID_POW)

p_fair = ModelParams(; gamma=GAMMA, beta=BETA, r=R_RATE, mwr=1.0, grid_kw...)
fair_pr = compute_payout_rate(p_fair, base_surv)
p_fair_nom = ModelParams(; gamma=GAMMA, beta=BETA, r=R_RATE, mwr=1.0,
                         inflation_rate=INFLATION, grid_kw...)
fair_pr_nom = compute_payout_rate(p_fair_nom, base_surv)
loaded_pr_nom = MWR_LOADED * fair_pr_nom

common_kw = (gamma=GAMMA, beta=BETA, r=R_RATE,
             stochastic_health=true, n_health_states=3, n_quad=N_QUAD,
             c_floor=C_FLOOR, hazard_mult=Float64.(HAZARD_MULT))

p_grid = ModelParams(; common_kw..., mwr=1.0, grid_kw...)
grids = build_grids(p_grid, max(fair_pr, fair_pr_nom))

# ---------------------------------------------------------------------------
# solve_at_psi: returns voluntary ownership rate given psi
# ---------------------------------------------------------------------------

function solve_at_psi(psi::Float64; verbose::Bool=false)
    p_model = ModelParams(; common_kw...,
        theta=THETA_DFJ, kappa=KAPPA_DFJ,
        mwr=MWR_LOADED, fixed_cost=FIXED_COST,
        min_purchase=MIN_PURCHASE,
        inflation_rate=INFLATION,
        medical_enabled=true,
        health_mortality_corr=true,
        survival_pessimism=SURVIVAL_PESSIMISM,
        consumption_decline=CONSUMPTION_DECLINE_ACTIVE,
        health_utility=HEALTH_UTILITY_ACTIVE,
        lambda_w=LAMBDA_W,
        psi_purchase=psi,
        grid_kw...)
    res = solve_and_evaluate(p_model, grids, base_surv,
        Float64.(SS_QUARTILE_LEVELS), pop, loaded_pr_nom;
        step_name="", verbose=verbose)
    return res.ownership  # fraction in [0, 1]
end

# ---------------------------------------------------------------------------
# Bisection on psi to match a target retention rate
# ---------------------------------------------------------------------------

function bisect_psi(target::Float64; psi_lo::Float64=PSI_BISECTION_LO,
                    psi_hi::Float64=PSI_BISECTION_HI, tol::Float64=PSI_TOLERANCE,
                    max_iter::Int=PSI_MAX_ITER)
    @printf("\nBisecting psi for target ownership = %.4f\n", target)
    @printf("  Initial bracket: [%.3f, %.3f]\n", psi_lo, psi_hi)
    history = NamedTuple{(:iter, :psi, :ownership), Tuple{Int, Float64, Float64}}[]

    own_lo = solve_at_psi(psi_lo)
    push!(history, (iter=0, psi=psi_lo, ownership=own_lo))
    @printf("  iter %2d  psi = %.4f  -> ownership = %.4f\n", 0, psi_lo, own_lo)

    own_hi = solve_at_psi(psi_hi)
    push!(history, (iter=0, psi=psi_hi, ownership=own_hi))
    @printf("  iter %2d  psi = %.4f  -> ownership = %.4f\n", 0, psi_hi, own_hi)

    if own_lo < target
        @warn "Even at psi=0 model ownership ($(own_lo)) is below target ($(target)); bisection will return psi_lo"
        return (psi=psi_lo, ownership=own_lo, converged=false, history=history)
    end
    if own_hi > target
        @warn "Even at psi_hi=$(psi_hi) model ownership ($(own_hi)) exceeds target ($(target)); expand bracket"
        return (psi=psi_hi, ownership=own_hi, converged=false, history=history)
    end

    for k in 1:max_iter
        psi_mid = 0.5 * (psi_lo + psi_hi)
        own_mid = solve_at_psi(psi_mid)
        push!(history, (iter=k, psi=psi_mid, ownership=own_mid))
        @printf("  iter %2d  psi = %.4f  -> ownership = %.4f  (gap %+.4f)\n",
                k, psi_mid, own_mid, own_mid - target)

        if abs(own_mid - target) < tol
            return (psi=psi_mid, ownership=own_mid, converged=true, history=history)
        end

        # ownership is monotone DECREASING in psi
        if own_mid > target
            psi_lo = psi_mid
        else
            psi_hi = psi_mid
        end
    end

    psi_mid = 0.5 * (psi_lo + psi_hi)
    own_mid = solve_at_psi(psi_mid)
    push!(history, (iter=max_iter+1, psi=psi_mid, ownership=own_mid))
    return (psi=psi_mid, ownership=own_mid, converged=false, history=history)
end

# ---------------------------------------------------------------------------
# Grid-search alternative: dispatches all psi evaluations in parallel,
# interpolates to find each retention target's psi-hat. Much faster than
# 3 sequential bisections (~5 min vs ~2.5 hours) when N_workers >> grid size.
# ---------------------------------------------------------------------------

# Dense grid in [0, 0.05] (where the response curve is steep), coarse beyond.
# Total: 26 fine + 19 coarse = 45 points covering [0, 0.5]. With ≥45 workers
# the entire grid runs in approximately one model-solve wall-clock (~5 min).
const PSI_GRID = vcat(collect(0.000:0.002:0.050),
                      collect(0.075:0.025:0.500))

function grid_search_psi(grid::Vector{Float64})
    @printf("\nDispatching %d psi grid evaluations across %d workers...\n",
            length(grid), max(nworkers(), 1))
    flush(stdout)
    # Capture all the model setup as locals so they ship to workers via the
    # closure (Julia serializes captured values, not function references).
    _common_kw = common_kw
    _grid_kw = grid_kw
    _grids = grids
    _base_surv = base_surv
    _pop = pop
    _loaded_pr_nom = loaded_pr_nom
    _ss_levels = Float64.(SS_QUARTILE_LEVELS)
    _theta_dfj = THETA_DFJ
    _kappa_dfj = KAPPA_DFJ
    _mwr_loaded = MWR_LOADED
    _fixed_cost = FIXED_COST
    _min_purchase = MIN_PURCHASE
    _inflation = INFLATION
    _surv_pessimism = SURVIVAL_PESSIMISM
    _consumption_decline = CONSUMPTION_DECLINE_ACTIVE
    _health_utility = HEALTH_UTILITY_ACTIVE
    _lambda_w = LAMBDA_W

    t0 = time()
    grid_pairs = parallel_solve(grid) do psi
        # Inline equivalent of solve_at_psi (cannot reference top-level
        # function on workers since it isn't @everywhere'd).
        p_model = ModelParams(; _common_kw...,
            theta=_theta_dfj, kappa=_kappa_dfj,
            mwr=_mwr_loaded, fixed_cost=_fixed_cost,
            min_purchase=_min_purchase,
            inflation_rate=_inflation,
            medical_enabled=true,
            health_mortality_corr=true,
            survival_pessimism=_surv_pessimism,
            consumption_decline=_consumption_decline,
            health_utility=_health_utility,
            lambda_w=_lambda_w,
            psi_purchase=psi,
            _grid_kw...)
        res = solve_and_evaluate(p_model, _grids, _base_surv,
            _ss_levels, _pop, _loaded_pr_nom;
            step_name="", verbose=false)
        return (psi=psi, ownership=res.ownership)
    end
    @printf("  Completed in %.0fs (%.1f min)\n", time() - t0, (time() - t0) / 60)
    # Sort by psi (parallel_solve may return out of order)
    return sort(grid_pairs, by=p -> p.psi)
end

function interp_psi_for_target(grid_pairs, target::Float64)
    # ownership is monotone DECREASING in psi; find the bracketing pair
    # and linearly interpolate. If target is outside the grid range, return
    # the boundary psi with a converged=false flag.
    own = [p.ownership for p in grid_pairs]
    psi = [p.psi       for p in grid_pairs]
    if target > maximum(own)
        return (psi=psi[1], ownership=own[1], converged=false,
                note="target above grid max ownership ($(maximum(own)))")
    end
    if target < minimum(own)
        return (psi=psi[end], ownership=own[end], converged=false,
                note="target below grid min ownership ($(minimum(own)))")
    end
    for k in 1:(length(grid_pairs) - 1)
        if (own[k] >= target && own[k+1] <= target)
            # Linear interp between (psi[k], own[k]) and (psi[k+1], own[k+1])
            slope = (psi[k+1] - psi[k]) / (own[k+1] - own[k])
            psi_interp = psi[k] + slope * (target - own[k])
            return (psi=psi_interp, ownership=target, converged=true,
                    note="linear interp between psi=$(psi[k]) and psi=$(psi[k+1])")
        end
    end
    return (psi=psi[end], ownership=own[end], converged=false,
            note="no bracketing pair found")
end

# ---------------------------------------------------------------------------
# Run estimation: prefer grid search when running with workers, fall back
# to bisection in single-process mode.
# ---------------------------------------------------------------------------

println("=" ^ 70)
println("  ESTIMATE PSI VIA UK 2015 PENSION-FREEDOMS RETENTION MOMENT")
println("=" ^ 70)
@printf("  UK retention range: [%.2f, %.2f] (FCA / ABI 2015-2024)\n",
        UK_RETENTION_LOW, UK_RETENTION_HIGH)
@printf("  Mid-range target:    %.2f\n", UK_RETENTION_MID)
println()

t_start = time()

if nworkers() > 1
    # Grid search: one parallel dispatch covers all targets
    grid_pairs = grid_search_psi(PSI_GRID)
    println("\nGrid scan results (psi, ownership):")
    for p in grid_pairs
        @printf("  psi=%.4f  ownership=%.4f\n", p.psi, p.ownership)
    end

    result_high_ret = interp_psi_for_target(grid_pairs, UK_RETENTION_HIGH)
    result_mid_ret  = interp_psi_for_target(grid_pairs, UK_RETENTION_MID)
    result_low_ret  = interp_psi_for_target(grid_pairs, UK_RETENTION_LOW)
else
    # Bisection: serial fallback when running single-process
    # psi_low corresponds to HIGH retention (less behavioral suppression)
    # psi_high corresponds to LOW retention (more behavioral suppression)
    result_high_ret = bisect_psi(UK_RETENTION_HIGH)
    result_mid_ret  = bisect_psi(UK_RETENTION_MID)
    result_low_ret  = bisect_psi(UK_RETENTION_LOW)
end

# Also compute the no-PED (psi=0) baseline for reference. The bisection branch
# stores it in history[1]; the grid-search branch has psi=0 as the first grid
# point. Compute fresh when neither structure is available.
own_no_ped = if hasproperty(result_mid_ret, :history)
    result_mid_ret.history[1].ownership
elseif @isdefined(grid_pairs)
    grid_pairs[1].ownership
else
    solve_at_psi(0.0)
end
@printf("\nNo-PED baseline (psi=0): voluntary ownership = %.4f\n", own_no_ped)

# Out-of-sample test: predicted ownership at the calibrated psi vs. observed
println("\n" * "=" ^ 70)
println("  ANCHOR A/C: psi calibrated to match UK retention LEVEL")
println("  (also reproduces the rational-corrected behavioral elasticity)")
println("=" ^ 70)

const PCT_HRS_OBSERVED = 3.4  # HRS singles 65-69
@printf("\n  %-30s  %10s  %10s\n", "UK retention target", "psi_hat", "US ownership")
println("  " * "-" ^ 56)
for (lab, r) in [("High UK retention (25%)", result_high_ret),
                 ("Mid UK retention (17%)",  result_mid_ret),
                 ("Low UK retention (13%)",  result_low_ret)]
    @printf("  %-30s  %10.4f  %10.2f%%\n", lab, r.psi, r.ownership * 100)
end
@printf("  %-30s  %10s  %10.2f%%\n", "Observed (HRS, 65-69)", "---", PCT_HRS_OBSERVED)

# ---------------------------------------------------------------------------
# ANCHOR B: psi calibrated to match UK TOTAL elasticity (75-87 pp drop)
# This anchor includes the rational tax-effect component and produces a
# larger psi_hat that drives the model to the corner.
# ---------------------------------------------------------------------------
println("\n" * "=" ^ 70)
println("  ANCHOR B: psi calibrated to match UK TOTAL elasticity (drop)")
println("  (baseline = no-PED ownership; target drop = 75 / 81 / 87 pp)")
println("=" ^ 70)

if @isdefined(grid_pairs)
    # Compute model elasticity at each grid point (always relative to no-PED)
    model_drops = [(psi=p.psi, drop_pp=(own_no_ped - p.ownership) * 100) for p in grid_pairs]
    function find_psi_for_drop(target_drop_pp::Float64)
        # Drop is monotone INCREASING in psi
        for k in 1:(length(model_drops) - 1)
            d_lo = model_drops[k].drop_pp
            d_hi = model_drops[k+1].drop_pp
            if d_lo <= target_drop_pp <= d_hi
                # Linear interpolate
                slope = (model_drops[k+1].psi - model_drops[k].psi) / (d_hi - d_lo)
                return (psi=model_drops[k].psi + slope * (target_drop_pp - d_lo),
                        ownership=own_no_ped - target_drop_pp / 100,
                        target_drop=target_drop_pp)
            end
        end
        # If outside grid, return boundary
        if target_drop_pp > model_drops[end].drop_pp
            return (psi=model_drops[end].psi, ownership=grid_pairs[end].ownership,
                    target_drop=target_drop_pp)
        end
        return (psi=model_drops[1].psi, ownership=grid_pairs[1].ownership,
                target_drop=target_drop_pp)
    end

    @printf("  No-PED baseline ownership: %.2f%%\n", own_no_ped * 100)
    @printf("\n  %-30s  %10s  %12s  %10s\n",
            "UK total drop target (pp)", "psi_hat", "model drop pp", "US ownership")
    println("  " * "-" ^ 70)
    anchor_b_75 = find_psi_for_drop(75.0)
    anchor_b_81 = find_psi_for_drop(81.0)
    anchor_b_87 = find_psi_for_drop(87.0)
    for (lab, r) in [("UK low (75 pp drop)", anchor_b_75),
                     ("UK mid (81 pp drop)", anchor_b_81),
                     ("UK high (87 pp drop)", anchor_b_87)]
        @printf("  %-30s  %10.4f  %12.2f  %10.2f%%\n",
                lab, r.psi, r.target_drop, r.ownership * 100)
    end

    # ---------------------------------------------------------------------------
    # ANCHOR C: rational-corrected behavioral elasticity (60-65 pp drop)
    # Strips out the tax-effect component of UK reform.
    # ---------------------------------------------------------------------------
    println("\n" * "=" ^ 70)
    println("  ANCHOR C: ABI rational-corrected sensitivity target (low/mid/high)")
    println("  (aggregate sales-volume decline, tax-removal response stripped)")
    println("=" ^ 70)
    @printf("\n  %-40s  %10s  %12s  %10s\n",
            "Rational-corrected drop (pp)", "psi_hat", "model drop pp", "US ownership")
    println("  " * "-" ^ 80)
    anchor_c_55 = find_psi_for_drop(55.0)
    anchor_c_60 = find_psi_for_drop(60.0)
    anchor_c_65 = find_psi_for_drop(65.0)
    for (lab, r) in [("ABI rational-corrected low (55 pp)",  anchor_c_55),
                     ("ABI rational-corrected mid (60 pp)",  anchor_c_60),
                     ("ABI rational-corrected high (65 pp)", anchor_c_65)]
        @printf("  %-40s  %10.4f  %12.2f  %10.2f%%\n",
                lab, r.psi, r.target_drop, r.ownership * 100)
    end
end

# ---------------------------------------------------------------------------
# Save outputs (CSV + JSON)
# ---------------------------------------------------------------------------

mkpath(dirname(OUT_CSV))
mkpath(dirname(OUT_JSON))

open(OUT_CSV, "w") do f
    println(f, "uk_retention_target,psi_hat,model_ownership,converged,n_iter")
    for (target, r) in [(UK_RETENTION_LOW,  result_low_ret),
                        (UK_RETENTION_MID,  result_mid_ret),
                        (UK_RETENTION_HIGH, result_high_ret)]
        @printf(f, "%.4f,%.6f,%.6f,%s,%d\n",
                target, r.psi, r.ownership, r.converged,
                hasproperty(r, :history) ? length(r.history) : 0)
    end
end
@printf("\nWrote %s\n", OUT_CSV)

# Simple JSON without dependencies
open(OUT_JSON, "w") do f
    println(f, "{")
    @printf(f, "  \"date\": \"%s\",\n", string(now()))
    @printf(f, "  \"method\": \"single-moment SMM (bisection)\",\n")
    @printf(f, "  \"identifying_moment\": \"UK 2015 pension freedoms retention rate\",\n")
    @printf(f, "  \"target_retention_range\": [%.4f, %.4f, %.4f],\n",
            UK_RETENTION_LOW, UK_RETENTION_MID, UK_RETENTION_HIGH)
    @printf(f, "  \"psi_hat_low\": %.6f,\n", result_high_ret.psi)
    @printf(f, "  \"psi_hat_mid\": %.6f,\n", result_mid_ret.psi)
    @printf(f, "  \"psi_hat_high\": %.6f,\n", result_low_ret.psi)
    @printf(f, "  \"us_ownership_low\": %.6f,\n", result_high_ret.ownership)
    @printf(f, "  \"us_ownership_mid\": %.6f,\n", result_mid_ret.ownership)
    @printf(f, "  \"us_ownership_high\": %.6f,\n", result_low_ret.ownership)
    @printf(f, "  \"observed_us_ownership\": %.4f,\n", PCT_HRS_OBSERVED / 100)
    @printf(f, "  \"no_ped_baseline\": %.6f,\n", own_no_ped)
    @printf(f, "  \"runtime_seconds\": %.1f\n", time() - t_start)
    println(f, "}")
end
@printf("Wrote %s\n", OUT_JSON)

# ---------------------------------------------------------------------------
# Recommended psi for production
# ---------------------------------------------------------------------------

println("\n" * "=" ^ 70)
println("  RECOMMENDED PRODUCTION psi")
println("=" ^ 70)
@printf("  Point estimate (UK mid-range retention 17%%):  psi = %.4f\n", result_mid_ret.psi)
@printf("  Sensitivity interval [13%% to 25%%]:           [%.4f, %.4f]\n",
        result_high_ret.psi, result_low_ret.psi)
@printf("  Implied US predicted ownership:               %.2f%%\n",
        result_mid_ret.ownership * 100)
@printf("  Observed US ownership (HRS):                  %.2f%%\n", PCT_HRS_OBSERVED)
println("=" ^ 70)

#=============================================================================
# ORIGINAL FILE: scripts/run_psi_sensitivity.jl
#=============================================================================

# Behavioral channel sensitivity: solve the full 10-channel model under multiple
# values of psi_purchase to bracket the empirical literature.
#
# Calibration anchors are derived from the UK 2015 pension freedoms reform.
# Two evidence streams supply identifying targets:
#   - ABI aggregate sales-volume decline (~75% proportional drop in annuity
#     vs drawdown sales 2014-2016), mapped through the model into an
#     ownership-rate change. About a quarter of that change is attributable
#     to the simultaneous removal of a 55% lump-sum tax penalty already
#     represented in the model's rational pricing channels; the residual is
#     the "rational-corrected" target.
#   - ELSA microdata: wave 6 (2012-13) pre-freedoms baseline vs waves 8-11
#     (2016-2024) post-freedoms disposition; n=869 DC pot holders,
#     subgroup-robust across age, sex, education, health.
#
# The rational-corrected ABI sensitivity targets strip the tax-removal
# component from the total drop; the ELSA rational-corrected targets do the
# same against the microdata drop. The total-drop variants (no rational
# stripping) are reported as the most aggressive sensitivity end and pin the
# bracket's lower-ownership bound.
#
# Calibration anchors (psi via single-moment SMM mapping):
#   psi = 0       : rational benchmark (no PED)
#   psi = 0.0142  : ABI rational-corrected low
#   psi = 0.0163  : ABI rational-corrected mid (production; bracket low end)
#   psi = 0.0194  : ABI rational-corrected high
#   psi = 0.0220  : ELSA rational-corrected low (microdata-anchored)
#   psi = 0.0240  : ELSA rational-corrected high (microdata-anchored)
#   psi = 0.0281  : ABI total drop, no rational stripping
#   psi = 0.0335  : ELSA total drop, no rational stripping (bracket high end)
#   psi = 0.0400+ : above-sensitivity range
#
# Output: tables/csv/psi_sensitivity.csv (one row per psi value)
# Runtime: ~9 full-model solves; ~30-40 minutes parallel on 32+ vCPU.

using Printf
using DelimitedFiles
using Distributed

if nworkers() > 1
    @everywhere include(joinpath(@__DIR__, "..", "src", "AnnuityPuzzle.jl"))
    @everywhere using .AnnuityPuzzle
else
    include(joinpath(@__DIR__, "..", "src", "AnnuityPuzzle.jl"))
    using .AnnuityPuzzle
end

include(joinpath(@__DIR__, "config.jl"))

const CONSUMPTION_DECLINE_ACTIVE = 0.02
const HEALTH_UTILITY_ACTIVE = [1.0, 0.90, 0.75]

const PSI_VALUES = [
    ("No PED (rational + SDU only)",                0.000),
    ("ABI rational-corrected low",                  0.0142),  # tax-stripped ABI aggregate
    ("ABI rational-corrected mid",                  0.0163),  # production; bracket low end
    ("ABI rational-corrected high",                 0.0194),  # tax-stripped ABI aggregate
    ("ELSA rational-corrected low",                 0.0220),  # ELSA microdata, low strip
    ("ELSA rational-corrected high",                0.0240),  # ELSA microdata, high strip
    ("ABI total drop (no rational stripping)",      0.0281),  # ABI aggregate, raw
    ("ELSA total drop (no rational stripping)",     0.0335),  # ELSA microdata, raw; bracket high end
    ("Above sensitivity range",                     0.040),
    ("Corner-bound region",                         0.075),
]

const OUT_CSV = joinpath(@__DIR__, "..", "tables", "csv", "psi_sensitivity.csv")

# ---------------------------------------------------------------------------
# Load HRS sample
# ---------------------------------------------------------------------------

println("Loading HRS sample...")
hrs_raw = readdlm(HRS_PATH, ',', Any; skipstart=1)
n_pop = size(hrs_raw, 1)
population = zeros(n_pop, 4)
population[:, 1] = Float64.(hrs_raw[:, 1])
population[:, 2] .= 0.0
population[:, 3] = Float64.(hrs_raw[:, 3])
if size(hrs_raw, 2) >= 4
    population[:, 4] = Float64.(hrs_raw[:, 4])
else
    population[:, 4] .= 2.0
end

# Filter to eligible
pop = population[population[:, 1] .>= MIN_WEALTH, :]
if size(pop, 2) < 4
    pop = hcat(pop, fill(2.0, size(pop, 1)))
end
@printf("  Eligible: %d\n", size(pop, 1))

# ---------------------------------------------------------------------------
# Survival, payout rates, grids (shared across solves)
# ---------------------------------------------------------------------------

p_base = ModelParams(age_start=AGE_START, age_end=AGE_END)
base_surv = build_lockwood_survival(p_base)

grid_kw = (n_wealth=N_WEALTH, n_annuity=N_ANNUITY, n_alpha=N_ALPHA,
           W_max=W_MAX, age_start=AGE_START, age_end=AGE_END,
           annuity_grid_power=A_GRID_POW)

p_fair = ModelParams(; gamma=GAMMA, beta=BETA, r=R_RATE, mwr=1.0, grid_kw...)
fair_pr = compute_payout_rate(p_fair, base_surv)
p_fair_nom = ModelParams(; gamma=GAMMA, beta=BETA, r=R_RATE, mwr=1.0,
                         inflation_rate=INFLATION, grid_kw...)
fair_pr_nom = compute_payout_rate(p_fair_nom, base_surv)
loaded_pr_nom = MWR_LOADED * fair_pr_nom

common_kw = (gamma=GAMMA, beta=BETA, r=R_RATE,
             stochastic_health=true, n_health_states=3, n_quad=N_QUAD,
             c_floor=C_FLOOR, hazard_mult=Float64.(HAZARD_MULT))

p_grid = ModelParams(; common_kw..., mwr=1.0, grid_kw...)
grids = build_grids(p_grid, max(fair_pr, fair_pr_nom))

# ---------------------------------------------------------------------------
# Solve the full 10-channel model at each psi value
# ---------------------------------------------------------------------------

# Parallel dispatch — each psi value is an independent full-model solve.
# With N workers, wall-clock is approximately the longest single solve
# (~25 min for the full 10-channel model) instead of N × 25 min serial.
# Capture closures-friendly locals before pmap.
const _common_kw = common_kw
const _grid_kw = grid_kw
const _grids = grids
const _base_surv = base_surv
const _pop = pop
const _loaded_pr_nom = loaded_pr_nom

println("\nDispatching $(length(PSI_VALUES)) psi solves across $(max(nworkers(), 1)) workers...")
flush(stdout)
t0_dispatch = time()

results_raw = parallel_solve(PSI_VALUES) do (label, psi_val)
    p_model = ModelParams(; _common_kw...,
        theta=THETA_DFJ, kappa=KAPPA_DFJ,
        mwr=MWR_LOADED, fixed_cost=FIXED_COST,
        min_purchase=MIN_PURCHASE,
        inflation_rate=INFLATION,
        medical_enabled=true,
        health_mortality_corr=true,
        survival_pessimism=SURVIVAL_PESSIMISM,
        consumption_decline=CONSUMPTION_DECLINE_ACTIVE,
        health_utility=HEALTH_UTILITY_ACTIVE,
        lambda_w=LAMBDA_W,
        psi_purchase=psi_val,
        _grid_kw...)
    t0 = time()
    res = solve_and_evaluate(p_model, _grids, _base_surv,
        Float64.(SS_QUARTILE_LEVELS), _pop, _loaded_pr_nom;
        step_name="", verbose=false)
    return (label=label, psi=psi_val,
            ownership_pct=res.ownership * 100, mean_alpha=res.mean_alpha,
            solve_time=time() - t0)
end
elapsed_dispatch = time() - t0_dispatch
@printf("\nMaster dispatch wall-clock: %.0fs (%.1f min)\n",
        elapsed_dispatch, elapsed_dispatch / 60)

# Render per-spec output in original format
rows = NamedTuple[]
for r in results_raw
    @printf("\n=== psi_purchase = %.2f (%s) ===\n", r.psi, r.label)
    @printf("  Ownership: %.4f%%  |  Mean alpha: %.4f  |  %.1fs\n",
            r.ownership_pct, r.mean_alpha, r.solve_time)
    push!(rows, r)
end

# ---------------------------------------------------------------------------
# Default-architecture analog: rational baseline gives implicit "default" gap
# ---------------------------------------------------------------------------

own_default = rows[1].ownership_pct  # psi=0
println("\n=== Default-architecture analog ===")
@printf("  Ownership at psi=0 (default-annuitize analog):  %.2f%%\n", own_default)
for r in rows[2:end]
    gap = own_default - r.ownership_pct
    @printf("  Default-vs-opt-in gap at psi=%.2f (%s): %+.1f pp\n",
            r.psi, r.label, gap)
end
println("  (Chalmers-Reuter (2012) Oregon PERS gap: 35 pp)")

# ---------------------------------------------------------------------------
# Save CSV
# ---------------------------------------------------------------------------

mkpath(dirname(OUT_CSV))
open(OUT_CSV, "w") do f
    println(f, "label,psi,ownership_pct,mean_alpha,solve_time,default_gap_pp")
    own_def = rows[1].ownership_pct
    for r in rows
        gap = own_def - r.ownership_pct
        @printf(f, "%s,%.4f,%.4f,%.6f,%.1f,%.4f\n",
                r.label, r.psi, r.ownership_pct, r.mean_alpha, r.solve_time, gap)
    end
end
@printf("\nWrote %s\n", OUT_CSV)

#=============================================================================
# ORIGINAL FILE: scripts/run_robustness.jl
#=============================================================================

# Comprehensive Robustness and Sensitivity Analysis
#
# Addresses reviewer concerns:
#   1. Fine-grained gamma sweep (characterize bifurcation near 2.4-2.5)
#   2. Hazard multiplier variants (literature-anchored vs current)
#   3. Ownership threshold sensitivity (min_purchase=$0, $5K, $10K, $25K)
#   4. Grid convergence check (n_wealth=30, 60, 100)
#   5. Bequest specification comparison (DFJ luxury vs homothetic)
#   6. Joint gamma × inflation sensitivity
#   7. MWR sensitivity (Mitchell 1999 to Wettstein 2021)
#   8. Gauss-Hermite quadrature check
#   9. Survival pessimism sensitivity (psi sweep)
#
# Parallelism strategy: every sub-section that needs a full-model resolve is
# flattened into a SINGLE master spec list and dispatched via one parallel_solve
# call. Wall-clock time is therefore the longest single solve (~20-30 min for
# the full 10-channel model), not the sum of sub-section times. Each sub-section
# then filters the master results and renders its block of output in the format
# the manuscript expects.
#
# Section 3 (ownership threshold) does NOT re-solve — it builds a single full
# solution and re-evaluates ownership at different min_purchase thresholds.

using Printf
using DelimitedFiles
using Distributed

# Load module on all workers when running with -p N
if nworkers() > 1
    @everywhere include(joinpath(@__DIR__, "..", "src", "AnnuityPuzzle.jl"))
    @everywhere using .AnnuityPuzzle
else
    include(joinpath(@__DIR__, "..", "src", "AnnuityPuzzle.jl"))
    using .AnnuityPuzzle
end

include(joinpath(@__DIR__, "config.jl"))

const SS_LEVELS   = SS_QUARTILE_LEVELS  # [14K, 17K, 20K, 25K] by wealth quartile

println("=" ^ 70)
println("  ROBUSTNESS AND SENSITIVITY ANALYSIS")
println("=" ^ 70)

# ===================================================================
# Load data
# ===================================================================
println("\nLoading HRS population...")
hrs_path = HRS_PATH
hrs_raw = readdlm(hrs_path, ',', Any; skipstart=1)
n_pop = size(hrs_raw, 1)
population = zeros(n_pop, 4)
population[:, 1] = Float64.(hrs_raw[:, 1])
population[:, 2] .= 0.0                      # SS enters via ss_func, not A grid
population[:, 3] = Float64.(hrs_raw[:, 3])
if size(hrs_raw, 2) >= 4
    population[:, 4] = Float64.(hrs_raw[:, 4])  # observed health (1=Good, 2=Fair, 3=Poor)
else
    population[:, 4] .= 2.0
end

p_base = ModelParams(age_start=AGE_START, age_end=AGE_END)
base_surv = build_lockwood_survival(p_base)

ss_zero(age, p) = 0.0

# Common kwargs for run_full_model
base_kw = Dict{Symbol,Any}(
    :gamma => GAMMA, :beta => BETA, :r => R_RATE,
    :theta => THETA_DFJ, :kappa => KAPPA_DFJ,
    :c_floor => C_FLOOR,
    :mwr_loaded => MWR_LOADED,
    :fixed_cost_val => FIXED_COST,
    :min_purchase_val => MIN_PURCHASE,
    :lambda_w_val => LAMBDA_W,
    :inflation_val => INFLATION,
    :n_wealth => N_WEALTH, :n_annuity => N_ANNUITY, :n_alpha => N_ALPHA,
    :W_max => W_MAX, :n_quad => N_QUAD,
    :age_start => AGE_START, :age_end => AGE_END,
    :annuity_grid_power => A_GRID_POW,
    :hazard_mult => HAZARD_MULT,
    :survival_pessimism => SURVIVAL_PESSIMISM,
    :min_wealth => MIN_WEALTH,
    :ss_levels => SS_LEVELS,
    # All headline preference / behavioral channels must be in base_kw;
    # otherwise robustness sweeps evaluate a different model than the
    # production headline.
    :consumption_decline_val => CONSUMPTION_DECLINE,
    :health_utility_vals => Float64.(HEALTH_UTILITY),
    :psi_purchase_val => PSI_PURCHASE,
    :verbose => false,
)

@everywhere function run_full_model(base_surv_arg, population_arg, base_kw_arg; overrides...)
    kw = copy(base_kw_arg)
    theta_explicitly_set = false
    for (k, v) in overrides
        kw[k] = v
        k == :theta && (theta_explicitly_set = true)
    end
    # Use Lockwood's original DFJ theta at all gamma values
    if !theta_explicitly_set
        kw[:theta] = 56.96
    end
    result = run_decomposition(base_surv_arg, population_arg; kw...)
    return result.steps[end].ownership_rate
end

# Capture data in local variables for closure serialization
_bs, _pop, _bkw = base_surv, population, base_kw

# Collect all results for final table
all_results = Tuple{String,String,String}[]

# ===================================================================
# Build master spec list (every full-resolve sub-section)
# ===================================================================
# Each spec: (section::Symbol, label::String, params::Dict{Symbol,Any})
# Single parallel_solve dispatches all of them concurrently across workers,
# so wall-clock time = longest single solve, not sum of sub-section sums.

master_specs = NamedTuple{(:section, :label, :params), Tuple{Symbol, String, Dict{Symbol, Any}}}[]

# § 1. Gamma sweep
gamma_vals = [1.5, 2.0, 2.2, 2.3, 2.35, 2.4, 2.45, 2.5, 2.55, 2.6,
              2.7, 2.8, 3.0, 3.5, 4.0, 5.0]
for g in gamma_vals
    push!(master_specs, (section=:gamma,
                         label=@sprintf("gamma=%.2f", g),
                         params=Dict{Symbol,Any}(:gamma => g)))
end

# § 2. Hazard multiplier variants (constant) + age-banded variant
hazard_specs = [
    ("[0.45, 1.0, 3.5] (R-S functional, age 65-75)", [0.45, 1.0, 3.5]),
    ("[0.50, 1.0, 3.0] (baseline)",                  [0.50, 1.0, 3.0]),
    ("[0.57, 1.0, 2.7] (HRS SRH empirical)",         [0.57, 1.0, 2.7]),
    ("[0.60, 1.0, 2.0] (conservative SRH)",           [0.60, 1.0, 2.0]),
]
for (label, hm) in hazard_specs
    push!(master_specs, (section=:hazard,
                         label=label,
                         params=Dict{Symbol,Any}(:hazard_mult => hm)))
end
hm_by_age = [0.49 1.0 3.29;   # 65-74
             0.60 1.0 2.77;   # 75-84
             0.74 1.0 1.82]   # 85+
hm_midpoints = [70.0, 80.0, 90.0]
push!(master_specs, (section=:hazard_ageband,
                     label="Age-varying HRS (3 bands)",
                     params=Dict{Symbol,Any}(:hazard_mult_by_age => hm_by_age,
                                              :hazard_mult_age_midpoints => hm_midpoints)))

# § 4. Grid convergence
grid_specs = [
    (40, 15, "Coarse (40×15)"),
    (60, 20, "Medium (60×20)"),
    (80, 30, "Production (80×30) [baseline]"),
    (100, 40, "Fine (100×40)"),
]
for (nw, na, label) in grid_specs
    push!(master_specs, (section=:grid,
                         label=label,
                         params=Dict{Symbol,Any}(:n_wealth => nw, :n_annuity => na)))
end

# § 5. Bequest specifications
bequest_specs = [
    ("No bequests",                                              0.0,        0.0),
    ("Weak bequests (theta=2, kappa=\$10)",                      2.0,       10.0),
    ("Moderate bequests (theta=10, kappa=\$10)",                10.0,       10.0),
    ("DFJ luxury (theta=$(round(THETA_DFJ, digits=1)), kappa=\$272K)", THETA_DFJ, KAPPA_DFJ),
]
for (label, theta, kappa) in bequest_specs
    push!(master_specs, (section=:bequest,
                         label=label,
                         params=Dict{Symbol,Any}(:theta => theta, :kappa => kappa)))
end

# § 6. Joint gamma × inflation
gamma_set = [2.4, 2.5, 2.6, 3.0]
inflation_set = [0.01, 0.02, 0.03]
for g in gamma_set, pi in inflation_set
    push!(master_specs, (section=:gamma_inflation,
                         label=@sprintf("g=%.1f,pi=%.0f%%", g, pi * 100),
                         params=Dict{Symbol,Any}(:gamma => g, :inflation_val => pi)))
end

# § 7. MWR sweep
mwr_vals = [0.82, 0.85, 0.90, 0.95]
for m in mwr_vals
    push!(master_specs, (section=:mwr,
                         label=@sprintf("MWR=%.2f", m),
                         params=Dict{Symbol,Any}(:mwr_loaded => m)))
end

# § 8. Gauss-Hermite quadrature
for nq in [5, 7, 11]
    push!(master_specs, (section=:gh,
                         label=@sprintf("n_quad=%d", nq),
                         params=Dict{Symbol,Any}(:n_quad => nq)))
end

# § 9. Survival pessimism
psi_vals = [0.970, 0.981, 0.990, 1.000]
for psi in psi_vals
    push!(master_specs, (section=:pessimism,
                         label=@sprintf("psi=%.3f", psi),
                         params=Dict{Symbol,Any}(:survival_pessimism => psi)))
end

# ===================================================================
# Master parallel dispatch — all sections at once
# ===================================================================
n_specs = length(master_specs)
println("\n" * "=" ^ 70)
@printf("  Dispatching %d sensitivity solves across %d workers\n", n_specs, max(nworkers(), 1))
println("=" ^ 70)
flush(stdout)

t0_master = time()
master_results = parallel_solve(master_specs) do spec
    rate = run_full_model(_bs, _pop, _bkw; spec.params...)
    (section=spec.section, label=spec.label, rate=rate)
end
elapsed_master = time() - t0_master
@printf("  Completed all %d solves in %.0fs (%.1f min)\n",
        n_specs, elapsed_master, elapsed_master / 60)

# Helper: filter master_results by section, preserving order
function results_for(section::Symbol)
    return [r for r in master_results if r.section == section]
end

# ===================================================================
# § 1. Gamma sensitivity
# ===================================================================
println("\n" * "=" ^ 70)
println("  1. GAMMA SENSITIVITY (fine-grained sweep)")
println("     Characterizing structural transition near gamma=2.4-2.5")
println("=" ^ 70)
@printf("\n  %-10s  %12s\n", "gamma", "Ownership")
println("  " * "-" ^ 24)

for (idx, g) in enumerate(gamma_vals)
    gr = results_for(:gamma)[idx]
    @printf("  %-10.2f  %10.1f%%\n", g, gr.rate * 100)
    push!(all_results, ("Gamma sweep", @sprintf("gamma=%.2f", g),
                        @sprintf("%.1f%%", gr.rate * 100)))
end

# ===================================================================
# § 2. Hazard multiplier
# ===================================================================
println("\n" * "=" ^ 70)
println("  2. HAZARD MULTIPLIER SENSITIVITY")
println("     Empirically anchored: HRS SRH [0.57,1.0,2.7] vs R-S functional [0.45,1.0,3.5]")
println("=" ^ 70)
@printf("\n  %-45s  %12s\n", "Hazard multipliers", "Ownership")
println("  " * "-" ^ 59)

for hr in results_for(:hazard)
    @printf("  %-45s  %10.1f%%\n", hr.label, hr.rate * 100)
    push!(all_results, ("Hazard mult", hr.label, @sprintf("%.1f%%", hr.rate * 100)))
end

println("\n  Age-varying specification (HRS empirical by age band):")
ageband = results_for(:hazard_ageband)[1]
@printf("  %-45s  %10.1f%%\n", "Age-varying HRS (3 bands)", ageband.rate * 100)
push!(all_results, ("Hazard mult", "Age-varying HRS (3 bands)",
                    @sprintf("%.1f%%", ageband.rate * 100)))

# ===================================================================
# § 3. Ownership threshold sensitivity (separate code path — single solve,
#      multiple ownership thresholds; does NOT participate in master dispatch)
# ===================================================================
println("\n" * "=" ^ 70)
println("  3. OWNERSHIP THRESHOLD SENSITIVITY")
println("     Tests whether trivial purchases drive the ownership rate")
println("=" ^ 70)

min_purchase_vals = [0.0, 1_000.0, 5_000.0, 10_000.0, 25_000.0]

@printf("\n  %-30s  %12s\n", "Minimum purchase", "Ownership")
println("  " * "-" ^ 44)

# Need to solve with min_purchase parameter once
grid_kw = (n_wealth=N_WEALTH, n_annuity=N_ANNUITY, n_alpha=N_ALPHA,
           W_max=W_MAX, age_start=AGE_START, age_end=AGE_END,
           annuity_grid_power=A_GRID_POW)

common_kw = (gamma=GAMMA, beta=BETA, r=R_RATE,
             stochastic_health=true, n_health_states=3, n_quad=N_QUAD,
             c_floor=C_FLOOR, hazard_mult=HAZARD_MULT)

p_fair = ModelParams(; common_kw..., mwr=1.0, grid_kw...)
fair_pr = compute_payout_rate(p_fair, base_surv)
p_fair_nom = ModelParams(; common_kw..., mwr=1.0, inflation_rate=INFLATION, grid_kw...)
fair_pr_nom = compute_payout_rate(p_fair_nom, base_surv)
loaded_pr = MWR_LOADED * fair_pr_nom

grids = build_grids(p_fair, max(fair_pr, fair_pr_nom))

p_full = ModelParams(; common_kw...,
    theta=THETA_DFJ, kappa=KAPPA_DFJ,
    mwr=MWR_LOADED, fixed_cost=FIXED_COST, inflation_rate=INFLATION,
    medical_enabled=true, health_mortality_corr=true,
    survival_pessimism=SURVIVAL_PESSIMISM,
    min_purchase=0.0,
    grid_kw...)

pop_h = copy(population)
pop_h = pop_h[pop_h[:, 1] .>= MIN_WEALTH, :]
sol_full = solve_lifecycle_health(p_full, grids, base_surv, ss_zero)

for mp in min_purchase_vals
    p_eval = ModelParams(; common_kw...,
        theta=THETA_DFJ, kappa=KAPPA_DFJ,
        mwr=MWR_LOADED, fixed_cost=FIXED_COST, inflation_rate=INFLATION,
        medical_enabled=true, health_mortality_corr=true,
        min_purchase=mp,
        grid_kw...)
    rate = compute_ownership_rate_health(
        HealthSolution(sol_full.V, sol_full.c_policy, sol_full.grids, p_eval, base_surv),
        pop_h, loaded_pr; base_surv=base_surv).ownership_rate
    label = mp == 0.0 ? "\$0 (any purchase)" : @sprintf("\$%s", string(round(Int, mp)))
    @printf("  %-30s  %10.1f%%\n", label, rate * 100)
    push!(all_results, ("Min purchase", label, @sprintf("%.1f%%", rate * 100)))
end

# ===================================================================
# § 4. Grid convergence
# ===================================================================
println("\n" * "=" ^ 70)
println("  4. GRID CONVERGENCE")
println("     Verifying results are stable to grid refinement")
println("=" ^ 70)
@printf("\n  %-30s  %12s\n", "Grid (wealth×annuity)", "Ownership")
println("  " * "-" ^ 44)

for gres in results_for(:grid)
    @printf("  %-30s  %10.1f%%\n", gres.label, gres.rate * 100)
    push!(all_results, ("Grid convergence", gres.label,
                        @sprintf("%.1f%%", gres.rate * 100)))
end

# ===================================================================
# § 5. Bequest specifications
# ===================================================================
println("\n" * "=" ^ 70)
println("  5. BEQUEST SPECIFICATION COMPARISON")
println("     DFJ luxury good (kappa=272K) vs no bequests vs weak bequests")
println("=" ^ 70)
@printf("\n  %-40s  %12s\n", "Bequest specification", "Ownership")
println("  " * "-" ^ 54)

for br in results_for(:bequest)
    @printf("  %-40s  %10.1f%%\n", br.label, br.rate * 100)
    push!(all_results, ("Bequest spec", br.label,
                        @sprintf("%.1f%%", br.rate * 100)))
end

# ===================================================================
# § 6. Joint gamma × inflation
# ===================================================================
println("\n" * "=" ^ 70)
println("  6. JOINT GAMMA × INFLATION SENSITIVITY")
println("=" ^ 70)

# Map results back to grid for table-style printing
gi_lookup = Dict{String, Float64}()
for r in results_for(:gamma_inflation)
    gi_lookup[r.label] = r.rate
end

@printf("\n  %10s", "")
for pi in inflation_set
    @printf("  %10s", @sprintf("pi=%.0f%%", pi * 100))
end
println()
println("  " * "-" ^ (10 + 12 * length(inflation_set)))

for g in gamma_set
    @printf("  gamma=%.1f", g)
    for pi in inflation_set
        key = @sprintf("g=%.1f,pi=%.0f%%", g, pi * 100)
        rate = gi_lookup[key]
        @printf("  %9.1f%%", rate * 100)
        push!(all_results, ("Gamma×Inflation", key,
                            @sprintf("%.1f%%", rate * 100)))
    end
    println()
end

# ===================================================================
# § 7. MWR sweep
# ===================================================================
println("\n" * "=" ^ 70)
println("  7. MWR SENSITIVITY")
println("     Mitchell et al. (1999) to Wettstein et al. (2021)")
println("=" ^ 70)
@printf("\n  %-10s  %12s\n", "MWR", "Ownership")
println("  " * "-" ^ 24)

for (idx, m) in enumerate(mwr_vals)
    mr = results_for(:mwr)[idx]
    @printf("  %-10.2f  %10.1f%%\n", m, mr.rate * 100)
    push!(all_results, ("MWR sweep", @sprintf("MWR=%.2f", m),
                        @sprintf("%.1f%%", mr.rate * 100)))
end

# ===================================================================
# § 8. Gauss-Hermite quadrature
# ===================================================================
println("\n" * "=" ^ 70)
println("  8. GAUSS-HERMITE QUADRATURE CHECK (5 / 7 / 11 nodes)")
println("=" ^ 70)
# Note: only 3, 5, 7, 9, 11 nodes have weight tables in gauss_hermite_normal.
# Higher node counts (13, 15) require extending that table; deferred until
# referees ask for finer convergence than 11 demonstrates.

@printf("\n  %-15s  %12s\n", "Nodes", "Ownership")
println("  " * "-" ^ 29)

for (idx, nq) in enumerate([5, 7, 11])
    ghr = results_for(:gh)[idx]
    @printf("  %-15d  %10.1f%%\n", nq, ghr.rate * 100)
    push!(all_results, ("GH nodes", @sprintf("n_quad=%d", nq),
                        @sprintf("%.1f%%", ghr.rate * 100)))
end

# ===================================================================
# § 9. Survival pessimism
# ===================================================================
println("\n" * "=" ^ 70)
println("  9. SURVIVAL PESSIMISM SENSITIVITY")
println("     O'Dea & Sturrock (2023) calibration range")
println("=" ^ 70)
@printf("\n  %-10s  %12s\n", "psi", "Ownership")
println("  " * "-" ^ 24)

for (idx, psi) in enumerate(psi_vals)
    pr = results_for(:pessimism)[idx]
    @printf("  %-10.3f  %10.1f%%\n", psi, pr.rate * 100)
    push!(all_results, ("Survival pessimism", @sprintf("psi=%.3f", psi),
                        @sprintf("%.1f%%", pr.rate * 100)))
end

# ===================================================================
# Generate LaTeX tables
# ===================================================================
println("\n\nGenerating LaTeX tables...")

tables_dir = joinpath(@__DIR__, "..", "tables")
mkpath(joinpath(tables_dir, "tex"))
mkpath(joinpath(tables_dir, "csv"))

const ds = '\$'  # LaTeX math delimiter (avoids Julia string interpolation issues)

# --- Gamma × Inflation table ---
tex_path = joinpath(tables_dir, "tex", "robustness_gamma_inflation.tex")
open(tex_path, "w") do f
    println(f, raw"\begin{table}[htbp]")
    println(f, raw"\centering")
    println(f, raw"\caption{Predicted Ownership (\%) by Risk Aversion and Inflation Rate}")
    println(f, raw"\label{tab:robustness_gamma_inflation}")
    ncols = length(inflation_set) + 1
    println(f, raw"\begin{tabular}{l" * "c" ^ length(inflation_set) * "}")
    println(f, raw"\toprule")
    print(f, " ")
    for pi in inflation_set
        print(f, "& ", ds, raw"\pi = ", @sprintf("%.0f", pi * 100), raw"\%", ds, " ")
    end
    println(f, "\\\\")  # LaTeX `\\` line break — non-raw string for unambiguous escaping
    println(f, raw"\midrule")

    for g in gamma_set
        print(f, ds, raw"\gamma = ", @sprintf("%.1f", g), ds, " ")
        for pi in inflation_set
            key = @sprintf("g=%.1f,pi=%.0f%%", g, pi * 100)
            idx = findfirst(r -> r[1] == "Gamma×Inflation" && r[2] == key, all_results)
            if idx !== nothing
                val = replace(all_results[idx][3], "%" => "")
                print(f, "& ", val, " ")
            end
        end
        println(f, "\\\\")  # LaTeX `\\` line break — non-raw string for unambiguous escaping
    end

    println(f, raw"\bottomrule")
    println(f, raw"\end{tabular}")
    println(f, raw"\begin{tablenotes}")
    println(f, raw"\small")
    println(f, raw"\item Baseline: ", ds, raw"\gamma = 2.5", ds, ", ",
            ds, raw"\pi = 2\%", ds, ", DFJ bequests,")
    @printf(f, "MWR = %.2f, hazard multipliers [0.50, 1.0, 3.0].\n", MWR_LOADED)
    println(f, raw"\end{tablenotes}")
    println(f, raw"\end{table}")
end
println("  $tex_path")

# --- Full robustness CSV ---
csv_path = joinpath(tables_dir, "csv", "robustness_full.csv")
open(csv_path, "w") do f
    println(f, "category,specification,ownership")
    for (cat, spec, rate) in all_results
        println(f, "$cat,$spec,$rate")
    end
end
println("  $csv_path")

println("\n" * "=" ^ 70)
println("  ROBUSTNESS ANALYSIS COMPLETE")
@printf("  Master parallel dispatch wall-clock: %.1f min over %d specs\n",
        elapsed_master / 60, n_specs)
println("=" ^ 70)

#=============================================================================
# ORIGINAL FILE: scripts/run_monte_carlo_uncertainty.jl
#=============================================================================

# Conditional Monte Carlo: Robustness of Baseline Prediction (10-channel model)
#
# Fixes gamma at the baseline and draws all empirically uncertain parameters
# from plausible distributions to show that the headline ownership result
# is robust to joint calibration uncertainty.
#
# Parameter distributions (gamma FIXED at baseline):
#   hazard_poor   ~ U(2.0, 3.5)       (HRS to R-S range)
#   inflation     ~ U(0.015, 0.025)   (near-term CPI uncertainty)
#   MWR           ~ U(0.83, 0.91)     (Mitchell 1999 / Wettstein 2021 range)
#   pessimism psi ~ U(0.97, 1.0)      (O'Dea-Sturrock CI)
#   delta_c       ~ U(0.01, 0.03)     (Aguiar-Hurst sensitivity)
#   psi_purchase  ~ U(0.005, 0.030)   (UK 2015 single-anchor SMM range
#                                      [0.014, 0.028] with modest headroom)
#
# Output: tables/csv/monte_carlo_ownership.csv
#         tables/tex/monte_carlo_summary.tex
#
# Run: julia --project=. -p 32 scripts/run_monte_carlo_uncertainty.jl

using Printf
using DelimitedFiles
using Random
using Statistics
using Distributed

if nworkers() > 1
    @everywhere include(joinpath(@__DIR__, "..", "src", "AnnuityPuzzle.jl"))
    @everywhere using .AnnuityPuzzle
else
    include(joinpath(@__DIR__, "..", "src", "AnnuityPuzzle.jl"))
    using .AnnuityPuzzle
end

include(joinpath(@__DIR__, "config.jl"))

println("=" ^ 70)
println("  CONDITIONAL MONTE CARLO: CALIBRATION ROBUSTNESS (10-channel)")
println("  gamma fixed at $GAMMA, joint draws over six nuisance parameters")
println("=" ^ 70)
flush(stdout)

# Script-specific parameters
const GAMMA_FIXED = GAMMA
# Coarser grids for speed (convergence verified at these resolutions)
const _NW         = 60
const _NA         = 20
const _NALPHA     = 51
const N_DRAWS     = 1000

# Load HRS population
hrs_path = HRS_PATH
hrs_raw = readdlm(hrs_path, ',', Any; skipstart=1)
n_pop = size(hrs_raw, 1)
population = zeros(n_pop, 4)
population[:, 1] = Float64.(hrs_raw[:, 1])
population[:, 2] .= 0.0  # SS via ss_func, not A grid
population[:, 3] = Float64.(hrs_raw[:, 3])
if size(hrs_raw, 2) >= 4
    population[:, 4] = Float64.(hrs_raw[:, 4])  # observed health (1=Good, 2=Fair, 3=Poor)
else
    population[:, 4] .= 2.0
end

p_base = ModelParams(age_start=AGE_START, age_end=AGE_END)
base_surv = build_lockwood_survival(p_base)

# Draw nuisance parameters (gamma fixed)
rng = Random.MersenneTwister(12345)

draws = Vector{NamedTuple{(:hazard_poor, :inflation, :mwr, :pessimism, :delta_c, :psi_purchase), NTuple{6, Float64}}}(undef, N_DRAWS)
for i in 1:N_DRAWS
    hp     = 2.0   + (3.5   - 2.0  ) * rand(rng)
    pi_    = 0.015 + (0.025 - 0.015) * rand(rng)
    m      = 0.83  + (0.91  - 0.83 ) * rand(rng)
    psi    = 0.97  + (1.00  - 0.97 ) * rand(rng)
    dc     = 0.01  + (0.03  - 0.01 ) * rand(rng)
    psi_p  = 0.005 + (0.030 - 0.005) * rand(rng)
    draws[i] = (hazard_poor=hp, inflation=pi_, mwr=m,
                pessimism=psi, delta_c=dc, psi_purchase=psi_p)
end

@printf("\n  Draws: %d (gamma fixed at %.1f)\n", N_DRAWS, GAMMA_FIXED)
for (lab, fn) in [("hazard_poor", d -> d.hazard_poor),
                  ("inflation",   d -> d.inflation),
                  ("MWR",         d -> d.mwr),
                  ("pessimism",   d -> d.pessimism),
                  ("delta_c",     d -> d.delta_c),
                  ("psi_purchase",d -> d.psi_purchase)]
    vals = [fn(d) for d in draws]
    @printf("  %-13s mean=%.3f, range=[%.3f, %.3f]\n",
            lab, mean(vals), minimum(vals), maximum(vals))
end
flush(stdout)

# Solve for each draw
println("\nSolving $(N_DRAWS) parameterizations...")
flush(stdout)
t0 = time()

# Pre-filter population
pop_filtered = copy(population)
mask = pop_filtered[:, 1] .>= MIN_WEALTH
pop_filtered = pop_filtered[mask, :]
if size(pop_filtered, 2) < 4
    pop_filtered = hcat(pop_filtered, fill(2.0, size(pop_filtered, 1)))
end

# Capture for closure serialization
_bs = base_surv
_pop = pop_filtered
_gamma = GAMMA_FIXED
_theta = THETA_DFJ
_kappa = KAPPA_DFJ
_beta = BETA
_r = R_RATE
_c_floor = C_FLOOR
_fixed_cost = FIXED_COST
_min_purchase = MIN_PURCHASE
_lambda_w = LAMBDA_W
_nw = _NW
_na = _NA
_nalpha = _NALPHA
_wmax = W_MAX
_nq = N_QUAD
_age_s = AGE_START
_age_e = AGE_END
_agp = A_GRID_POW

results = parallel_solve(draws) do d
    _ss_mean_val = sum(SS_QUARTILE_LEVELS) / length(SS_QUARTILE_LEVELS)
    ss_mean_func(age, p) = _ss_mean_val

    hm = [0.50, 1.0, d.hazard_poor]

    grid_kw = (n_wealth=_nw, n_annuity=_na, n_alpha=_nalpha,
               W_max=_wmax, age_start=_age_s, age_end=_age_e,
               annuity_grid_power=_agp)

    common_kw = (gamma=_gamma, beta=_beta, r=_r,
                 stochastic_health=true, n_health_states=3, n_quad=_nq,
                 c_floor=_c_floor, hazard_mult=hm)

    # Nominal loaded payout rate
    p_fair_nom = ModelParams(; gamma=_gamma, beta=_beta, r=_r, mwr=1.0,
                               inflation_rate=d.inflation, grid_kw...)
    fair_pr_nom = compute_payout_rate(p_fair_nom, _bs)
    loaded_pr_nom = d.mwr * fair_pr_nom

    # Build grids
    p_fair = ModelParams(; gamma=_gamma, beta=_beta, r=_r, mwr=1.0, grid_kw...)
    fair_pr = compute_payout_rate(p_fair, _bs)
    grids = build_grids(p_fair, max(fair_pr, fair_pr_nom))

    # Full 10-channel model: rational + age-varying needs + state-dep utility
    # + behavioral purchase friction.
    p_full = ModelParams(; common_kw...,
        theta=_theta, kappa=_kappa,
        mwr=d.mwr, fixed_cost=_fixed_cost, min_purchase=_min_purchase,
        inflation_rate=d.inflation,
        medical_enabled=true, health_mortality_corr=true,
        survival_pessimism=d.pessimism,
        consumption_decline=d.delta_c,
        health_utility=[1.0, 0.90, 0.75],
        lambda_w=_lambda_w,
        psi_purchase=d.psi_purchase,
        grid_kw...)

    sol = solve_lifecycle_health(p_full, grids, _bs, ss_mean_func)
    own_result = compute_ownership_rate_health(sol, _pop, loaded_pr_nom; base_surv=_bs)
    own = own_result.ownership_rate * 100

    (hazard_poor=d.hazard_poor, inflation=d.inflation, mwr=d.mwr,
     pessimism=d.pessimism, delta_c=d.delta_c, psi_purchase=d.psi_purchase,
     ownership_pct=own)
end

elapsed = time() - t0
@printf("\n  Completed %d solves in %.0f seconds (%.1f sec/solve)\n",
    N_DRAWS, elapsed, elapsed / N_DRAWS)
flush(stdout)

# Summary statistics
ownership_vals = [r.ownership_pct for r in results]
sort!(ownership_vals)
n = length(ownership_vals)
q05 = ownership_vals[max(1, round(Int, 0.05 * n))]
q25 = ownership_vals[max(1, round(Int, 0.25 * n))]
med = ownership_vals[div(n, 2)]
q75 = ownership_vals[max(1, round(Int, 0.75 * n))]
q95 = ownership_vals[max(1, round(Int, 0.95 * n))]
frac_1_10 = count(x -> 1.0 <= x <= 10.0, ownership_vals) / n * 100
frac_3_6 = count(x -> 3.0 <= x <= 6.0, ownership_vals) / n * 100

println("\n" * "=" ^ 70)
println("  CONDITIONAL MONTE CARLO RESULTS (gamma = $GAMMA_FIXED)")
println("=" ^ 70)
@printf("\n  Median predicted ownership: %.1f%%\n", med)
@printf("  90%% CI: [%.1f%%, %.1f%%]\n", q05, q95)
@printf("  IQR (50%% CI): [%.1f%%, %.1f%%]\n", q25, q75)
@printf("  Mean: %.1f%%\n", sum(ownership_vals) / n)
@printf("  Min: %.1f%%, Max: %.1f%%\n", ownership_vals[1], ownership_vals[end])
@printf("  Fraction in [1%%, 10%%]: %.0f%%\n", frac_1_10)
@printf("  Fraction in [3%%, 6%%] (observed range): %.0f%%\n", frac_3_6)
flush(stdout)

# Save CSV
tables_dir = joinpath(@__DIR__, "..", "tables", "csv")
mkpath(tables_dir)
csv_path = joinpath(tables_dir, "monte_carlo_ownership.csv")
open(csv_path, "w") do f
    println(f, "gamma,hazard_poor,inflation,mwr,pessimism,delta_c,psi_purchase,ownership_pct")
    for r in results
        @printf(f, "%.1f,%.4f,%.4f,%.4f,%.4f,%.4f,%.4f,%.2f\n",
            GAMMA_FIXED, r.hazard_poor, r.inflation, r.mwr,
            r.pessimism, r.delta_c, r.psi_purchase, r.ownership_pct)
    end
end
println("\n  Results saved: $csv_path")

# Save summary LaTeX table
ds = '\$'
tex_dir = joinpath(@__DIR__, "..", "tables", "tex")
mkpath(tex_dir)
tex_path = joinpath(tex_dir, "monte_carlo_summary.tex")
open(tex_path, "w") do f
    println(f, raw"\begin{table}[htbp]")
    println(f, raw"\centering")
    println(f, "\\caption{Conditional Monte Carlo: Predicted Ownership at $(ds)\\gamma = $(GAMMA_FIXED)$(ds)}")
    println(f, raw"\label{tab:monte_carlo}")
    println(f, raw"\begin{tabular}{lc}")
    println(f, raw"\toprule")
    # raw"\\" emits a single backslash (closing-quote rule), so we use a
    # regular escaped string here to write two literal backslashes (LaTeX `\\`).
    println(f, "Statistic & Value \\\\")
    println(f, raw"\midrule")
    @printf(f, "Number of draws & %d %s\n", N_DRAWS, "\\\\")
    @printf(f, "Median predicted ownership & %.1f\\%% %s\n", med, "\\\\")
    @printf(f, "90\\%% sensitivity interval & [%.1f\\%%, %.1f\\%%] %s\n", q05, q95, "\\\\")
    @printf(f, "Interquartile range (50\\%% interval) & [%.1f\\%%, %.1f\\%%] %s\n", q25, q75, "\\\\")
    @printf(f, "Mean & %.1f\\%% %s\n", sum(ownership_vals) / n, "\\\\")
    @printf(f, "Min / Max & %.1f\\%% / %.1f\\%% %s\n", ownership_vals[1], ownership_vals[end], "\\\\")
    @printf(f, "Fraction in [1\\%%, 10\\%%] & %.0f\\%% %s\n", frac_1_10, "\\\\")
    @printf(f, "Fraction in [3\\%%, 6\\%%] (observed range) & %.0f\\%% %s\n", frac_3_6, "\\\\")
    println(f, raw"\bottomrule")
    println(f, raw"\end{tabular}")
    println(f, raw"\begin{tablenotes}")
    println(f, raw"\small")
    println(f, "\\item Risk aversion fixed at $(ds)\\gamma = $(GAMMA_FIXED)$(ds). Joint draws over six")
    println(f, raw"calibration-uncertain parameters: $\mu_P \sim U(2.0, 3.5)$, $\pi \sim U(0.015, 0.025)$,")
    println(f, raw"MWR $\sim U(0.83, 0.91)$, $\psi \sim U(0.97, 1.0)$, $\delta_c \sim U(0.01, 0.03)$,")
    println(f, raw"$\psi_{\text{purchase}} \sim U(0.005, 0.030)$. Full ten-channel model.")
    println(f, raw"\end{tablenotes}")
    println(f, raw"\end{table}")
end
println("  Summary LaTeX saved: $tex_path")

println("\n" * "=" ^ 70)
println("  CONDITIONAL MONTE CARLO COMPLETE")
println("=" ^ 70)
flush(stdout)

#=============================================================================
# ORIGINAL FILE: scripts/run_implied_gamma.jl
#=============================================================================

# Implied Gamma Monte Carlo
#
# Instead of drawing gamma and reporting ownership (which produces a
# wide distribution driven by gamma sensitivity), flip the question:
# for each draw of (hazard_poor, inflation, MWR), find the gamma that
# matches 3.6% observed ownership via bisection.
#
# This converts the gamma sensitivity from a weakness into a finding:
# "what risk aversion is implied by observed behavior, given parameter
# uncertainty in other channels?"
#
# Parameter distributions (excluding gamma):
#   hazard_poor ~ U(2.0, 3.5)    (HRS to R-S range)
#   inflation   ~ U(0.01, 0.03)  (plausible Fed target range)
#   MWR         ~ U(0.75, 0.89)  (recentered at 0.82; Mitchell 1999)
#
# Output: tables/csv/implied_gamma.csv

using Printf
using DelimitedFiles
using Random
using Statistics
using Distributed

if nworkers() > 1
    @everywhere include(joinpath(@__DIR__, "..", "src", "AnnuityPuzzle.jl"))
    @everywhere using .AnnuityPuzzle
else
    include(joinpath(@__DIR__, "..", "src", "AnnuityPuzzle.jl"))
    using .AnnuityPuzzle
end

include(joinpath(@__DIR__, "config.jl"))

println("=" ^ 70)
println("  IMPLIED GAMMA MONTE CARLO")
println("  Bisect gamma to match 3.6% observed ownership")
println("=" ^ 70)
flush(stdout)

# ===================================================================
# Script-specific parameters
# ===================================================================
# Coarser grids for speed (convergence verified at these resolutions)
const _NW         = 60
const _NA         = 20
const _NALPHA     = 51
const SURV_PESSIMISM = SURVIVAL_PESSIMISM
const TARGET_OWN  = 0.036      # Lockwood (2012) observed ownership
const GAMMA_LO    = 1.5
const GAMMA_HI    = 5.0
const GAMMA_TOL   = 0.01       # bisection tolerance on gamma
const N_DRAWS     = 300

# ===================================================================
# Load HRS population sample
# ===================================================================
hrs_path = HRS_PATH
hrs_raw = readdlm(hrs_path, ',', Any; skipstart=1)
n_pop = size(hrs_raw, 1)
population = zeros(n_pop, 4)
population[:, 1] = Float64.(hrs_raw[:, 1])
population[:, 2] .= 0.0   # SS via ss_func, not A grid
population[:, 3] = Float64.(hrs_raw[:, 3])
if size(hrs_raw, 2) >= 4
    population[:, 4] = Float64.(hrs_raw[:, 4])  # observed health (1=Good, 2=Fair, 3=Poor)
else
    population[:, 4] .= 2.0
end

# Pre-filter population
pop_filtered = copy(population)
mask = pop_filtered[:, 1] .>= MIN_WEALTH
pop_filtered = pop_filtered[mask, :]
if size(pop_filtered, 2) < 4
    pop_filtered = hcat(pop_filtered, fill(2.0, size(pop_filtered, 1)))
end

# Survival probabilities
p_base = ModelParams(age_start=AGE_START, age_end=AGE_END)
base_surv = build_lockwood_survival(p_base)

@printf("  Population: %d total, %d eligible (W >= \$%s)\n",
    n_pop, size(pop_filtered, 1), string(round(Int, MIN_WEALTH)))
flush(stdout)

# ===================================================================
# Draw parameter vectors (everything except gamma)
# ===================================================================
rng = Random.MersenneTwister(54321)

draws = Vector{NamedTuple{(:hazard_poor, :inflation, :mwr), NTuple{3, Float64}}}(undef, N_DRAWS)
for i in 1:N_DRAWS
    hp = 2.0 + (3.5 - 2.0) * rand(rng)
    pi = 0.01 + (0.03 - 0.01) * rand(rng)
    m  = 0.75 + (0.89 - 0.75) * rand(rng)
    draws[i] = (hazard_poor=hp, inflation=pi, mwr=m)
end

@printf("\n  Draws: %d\n", N_DRAWS)
@printf("  hazard_poor: mean=%.2f, range=[%.2f, %.2f]\n",
    mean(d.hazard_poor for d in draws),
    minimum(d.hazard_poor for d in draws), maximum(d.hazard_poor for d in draws))
@printf("  inflation:   mean=%.3f, range=[%.3f, %.3f]\n",
    mean(d.inflation for d in draws),
    minimum(d.inflation for d in draws), maximum(d.inflation for d in draws))
@printf("  MWR:         mean=%.3f, range=[%.3f, %.3f]\n",
    mean(d.mwr for d in draws),
    minimum(d.mwr for d in draws), maximum(d.mwr for d in draws))
flush(stdout)

# ===================================================================
# Solve: bisect gamma for each draw
# ===================================================================
println("\nSolving $(N_DRAWS) draws via bisection...")
flush(stdout)
t0 = time()

# Capture references for closure serialization
_bs = base_surv
_pop = pop_filtered
_theta = THETA_DFJ
_kappa = KAPPA_DFJ
_beta = BETA
_r = R_RATE
_c_floor = C_FLOOR
_fixed_cost = FIXED_COST
_min_purchase = MIN_PURCHASE
_lambda_w = LAMBDA_W
_psi_purchase = PSI_PURCHASE
_consumption_decline = CONSUMPTION_DECLINE
_health_utility = Float64.(HEALTH_UTILITY)
_nw = _NW
_na = _NA
_nalpha = _NALPHA
_wmax = W_MAX
_nq = N_QUAD
_age_s = AGE_START
_age_e = AGE_END
_agp = A_GRID_POW
_psi = SURV_PESSIMISM
_target = TARGET_OWN
_glo = GAMMA_LO
_ghi = GAMMA_HI
_gtol = GAMMA_TOL

results = parallel_solve(draws) do d
    # Mean SS across quartiles (avoids 4x per-quartile solving overhead)
    _ss_mean_val = sum(SS_QUARTILE_LEVELS) / length(SS_QUARTILE_LEVELS)
    ss_mean_func(age, p) = _ss_mean_val

    # Solve ownership at a given gamma
    function _solve_own(gamma)
        hm = [0.50, 1.0, d.hazard_poor]

        grid_kw = (n_wealth=_nw, n_annuity=_na, n_alpha=_nalpha,
                   W_max=_wmax, age_start=_age_s, age_end=_age_e,
                   annuity_grid_power=_agp)

        common_kw = (gamma=gamma, beta=_beta, r=_r,
                     stochastic_health=true, n_health_states=3, n_quad=_nq,
                     c_floor=_c_floor, hazard_mult=hm)

        p_fair_nom = ModelParams(; gamma=gamma, beta=_beta, r=_r, mwr=1.0,
                                   inflation_rate=d.inflation, grid_kw...)
        fair_pr_nom = compute_payout_rate(p_fair_nom, _bs)
        loaded_pr_nom = d.mwr * fair_pr_nom

        p_fair = ModelParams(; gamma=gamma, beta=_beta, r=_r, mwr=1.0, grid_kw...)
        fair_pr = compute_payout_rate(p_fair, _bs)
        grids = build_grids(p_fair, max(fair_pr, fair_pr_nom))

        p_full = ModelParams(; common_kw...,
            theta=_theta, kappa=_kappa,
            mwr=d.mwr, fixed_cost=_fixed_cost, min_purchase=_min_purchase,
            inflation_rate=d.inflation,
            medical_enabled=true, health_mortality_corr=true,
            survival_pessimism=_psi,
            consumption_decline=_consumption_decline,
            health_utility=_health_utility,
            lambda_w=_lambda_w,
            psi_purchase=_psi_purchase,
            grid_kw...)

        sol = solve_lifecycle_health(p_full, grids, _bs, ss_mean_func)
        result = compute_ownership_rate_health(sol, _pop, loaded_pr_nom; base_surv=_bs)
        return result.ownership_rate
    end

    # Bisection: find gamma such that ownership(gamma, d) ≈ target
    lo = _glo
    hi = _ghi
    n_iter = 0

    own_hi = _solve_own(hi)
    n_iter += 1
    if own_hi < _target
        return (hazard_poor=d.hazard_poor, inflation=d.inflation, mwr=d.mwr,
                implied_gamma=hi, converged=false, n_iter=n_iter)
    end

    own_lo = _solve_own(lo)
    n_iter += 1
    if own_lo > _target
        return (hazard_poor=d.hazard_poor, inflation=d.inflation, mwr=d.mwr,
                implied_gamma=lo, converged=false, n_iter=n_iter)
    end

    while (hi - lo) > _gtol
        mid = (lo + hi) / 2.0
        own_mid = _solve_own(mid)
        n_iter += 1

        if own_mid > _target
            hi = mid
        else
            lo = mid
        end

        if n_iter >= 30
            break
        end
    end

    implied_gamma = (lo + hi) / 2.0
    return (hazard_poor=d.hazard_poor, inflation=d.inflation, mwr=d.mwr,
            implied_gamma=implied_gamma, converged=true, n_iter=n_iter)
end

elapsed = time() - t0
@printf("\n  Completed %d draws in %.0f seconds (%.1f sec/draw)\n",
    N_DRAWS, elapsed, elapsed / N_DRAWS)
flush(stdout)

# ===================================================================
# Summary statistics
# ===================================================================
converged = filter(r -> r.converged, results)
n_conv = length(converged)
n_total = length(results)

gammas = [r.implied_gamma for r in converged]
sort!(gammas)

if n_conv > 0
    med = gammas[max(1, div(n_conv, 2))]
    q25 = gammas[max(1, round(Int, 0.25 * n_conv))]
    q75 = gammas[max(1, round(Int, 0.75 * n_conv))]
    mn = sum(gammas) / n_conv
    frac_chetty = count(g -> 1.5 <= g <= 3.0, gammas) / n_conv * 100
    frac_narrow = count(g -> 2.0 <= g <= 2.5, gammas) / n_conv * 100

    println("\n" * "=" ^ 70)
    println("  IMPLIED GAMMA RESULTS")
    println("=" ^ 70)
    @printf("\n  Converged: %d / %d (%.0f%%)\n", n_conv, n_total, n_conv / n_total * 100)
    @printf("  Median implied gamma: %.2f\n", med)
    @printf("  Mean implied gamma:   %.2f\n", mn)
    @printf("  IQR: [%.2f, %.2f]\n", q25, q75)
    @printf("  Min: %.2f, Max: %.2f\n", gammas[1], gammas[end])
    @printf("  Fraction in [1.5, 3.0] (Chetty 2006 range): %.0f%%\n", frac_chetty)
    @printf("  Fraction in [2.0, 2.5] (narrow range):      %.0f%%\n", frac_narrow)
    flush(stdout)
else
    println("\n  WARNING: No draws converged!")
    flush(stdout)
end

# ===================================================================
# Save CSV
# ===================================================================
tables_dir = joinpath(@__DIR__, "..", "tables", "csv")
mkpath(tables_dir)

csv_path = joinpath(tables_dir, "implied_gamma.csv")
open(csv_path, "w") do f
    println(f, "hazard_poor,inflation,mwr,implied_gamma,converged,n_iter")
    for r in results
        @printf(f, "%.4f,%.4f,%.4f,%.4f,%s,%d\n",
            r.hazard_poor, r.inflation, r.mwr, r.implied_gamma,
            r.converged ? "true" : "false", r.n_iter)
    end
end
println("\n  Results saved: $csv_path")
flush(stdout)

# ===================================================================
# Save summary LaTeX table
# ===================================================================
if n_conv > 0
    tex_dir = joinpath(@__DIR__, "..", "tables", "tex")
    mkpath(tex_dir)
    tex_path = joinpath(tex_dir, "implied_gamma.tex")
    open(tex_path, "w") do f
        println(f, raw"\begin{table}[htbp]")
        println(f, raw"\centering")
        println(f, raw"\caption{Implied Risk Aversion from Monte Carlo Parameter Uncertainty}")
        println(f, raw"\label{tab:implied_gamma}")
        println(f, raw"\begin{tabular}{lc}")
        println(f, raw"\toprule")
        println(f, "Statistic & Value \\\\")
        println(f, raw"\midrule")
        println(f, "Number of draws & $n_conv \\\\")
        println(f, "Target ownership & $(round(TARGET_OWN * 100, digits=1))\\% \\\\")
        println(f, "Median implied \$\\gamma\$ & $(round(med, digits=2)) \\\\")
        println(f, "Mean implied \$\\gamma\$ & $(round(mn, digits=2)) \\\\")
        println(f, "Interquartile range & [$(round(q25, digits=2)), $(round(q75, digits=2))] \\\\")
        println(f, "Min / Max & $(round(gammas[1], digits=2)) / $(round(gammas[end], digits=2)) \\\\")
        println(f, "Fraction in [1.5, 3.0] & $(round(Int, frac_chetty))\\% \\\\")
        println(f, raw"\bottomrule")
        println(f, raw"\end{tabular}")
        println(f, raw"\begin{tablenotes}")
        println(f, raw"\small")
        println(f, raw"\item For each draw of nuisance parameters ($\mu_P$, $\pi$, MWR),")
        println(f, raw"we bisect over $\gamma$ to find the value that generates 3.6\%")
        println(f, raw"predicted ownership (Lockwood 2012 observed rate).")
        println(f, raw"Draws: $\mu_P \sim U(2.0, 3.5)$, $\pi \sim U(0.01, 0.03)$, MWR $\sim U(0.75, 0.89)$.")
        println(f, raw"Survival pessimism $\psi = 0.981$ (O'Dea \& Sturrock 2023).")
        println(f, raw"\end{tablenotes}")
        println(f, raw"\end{table}")
    end
    println("  Summary LaTeX saved: $tex_path")
    flush(stdout)
end

println("\n" * "=" ^ 70)
println("  IMPLIED GAMMA COMPLETE")
println("=" ^ 70)
flush(stdout)

#=============================================================================
# ORIGINAL FILE: scripts/run_multigamma_decomposition.jl
#=============================================================================

# Multi-gamma decomposition: run the full 8-step decomposition at
# gamma = 2.0, 2.5, 3.0 side-by-side. Shows which channels are
# gamma-sensitive and which are not.
#
# Output: tables/csv/multigamma_decomposition.csv
#         tables/tex/multigamma_decomposition.tex

using Printf, DelimitedFiles, Distributed

if nworkers() > 1
    @everywhere include(joinpath(@__DIR__, "..", "src", "AnnuityPuzzle.jl"))
    @everywhere using .AnnuityPuzzle
else
    include(joinpath(@__DIR__, "..", "src", "AnnuityPuzzle.jl"))
    using .AnnuityPuzzle
end

include(joinpath(@__DIR__, "config.jl"))

println("=" ^ 70); flush(stdout)
println("  MULTI-GAMMA DECOMPOSITION"); flush(stdout)
println("=" ^ 70); flush(stdout)

hrs_raw = readdlm(HRS_PATH,
                   ',', Any; skipstart=1)
n_pop = size(hrs_raw, 1)
population = zeros(n_pop, 4)
population[:, 1] = Float64.(hrs_raw[:, 1])
population[:, 2] .= 0.0
population[:, 3] = Float64.(hrs_raw[:, 3])
if size(hrs_raw, 2) >= 4
    population[:, 4] = Float64.(hrs_raw[:, 4])  # observed health (1=Good, 2=Fair, 3=Poor)
else
    population[:, 4] .= 2.0
end

p_base = ModelParams(age_start=AGE_START, age_end=AGE_END)
base_surv = build_lockwood_survival(p_base)
println("Data loaded ($n_pop obs)"); flush(stdout)

gammas = [2.0, 2.5, 3.0]
all_results = Dict{Float64, Any}()

for g in gammas
    println("\n--- gamma = $g ---"); flush(stdout)
    t0 = time()
    decomp = run_decomposition(
        base_surv, population;
        gamma=g, beta=BETA, r=R_RATE,
        theta=THETA_DFJ, kappa=KAPPA_DFJ,
        c_floor=C_FLOOR,
        mwr_loaded=MWR_LOADED,
        fixed_cost_val=FIXED_COST,
        min_purchase_val=MIN_PURCHASE,
        lambda_w_val=LAMBDA_W,
        # Preference + behavioral channels: passing the production values
        # so this multi-gamma table reflects the full ten-channel model
        # rather than the SDU-only legacy specification. Default kwargs
        # would silently leave consumption_decline, health_utility, and
        # psi_purchase off.
        consumption_decline_val=CONSUMPTION_DECLINE,
        health_utility_vals=HEALTH_UTILITY,
        psi_purchase_val=PSI_PURCHASE,
        inflation_val=INFLATION,
        n_wealth=N_WEALTH, n_annuity=N_ANNUITY, n_alpha=N_ALPHA,
        W_max=W_MAX, n_quad=N_QUAD,
        age_start=AGE_START, age_end=AGE_END,
        annuity_grid_power=A_GRID_POW,
        hazard_mult=HAZARD_MULT,
        survival_pessimism=SURVIVAL_PESSIMISM,
        min_wealth=MIN_WEALTH,
        ss_levels=SS_QUARTILE_LEVELS,
        verbose=true,
    )
    dt = time() - t0
    all_results[g] = decomp
    @printf("  gamma=%.1f complete in %.0f sec\n", g, dt); flush(stdout)
end

# Print side-by-side table
println("\n" * "=" ^ 70); flush(stdout)
println("  SIDE-BY-SIDE DECOMPOSITION"); flush(stdout)
println("=" ^ 70); flush(stdout)

step_names = [s.name for s in all_results[gammas[1]].steps]
n_steps = length(step_names)

# Header
@printf("\n  %-45s", "Channel")
for g in gammas
    @printf("  γ=%.1f  ", g)
end
println(); flush(stdout)
println("  " * "-" ^ (45 + length(gammas) * 10)); flush(stdout)

for i in 1:n_steps
    @printf("  %-45s", step_names[i])
    for g in gammas
        own = all_results[g].steps[i].ownership_rate * 100
        @printf("  %5.1f%%  ", own)
    end
    println(); flush(stdout)
end

# Retention rates
println("\n  Retention Rates:"); flush(stdout)
@printf("  %-45s", "Channel")
for g in gammas
    @printf("  γ=%.1f  ", g)
end
println(); flush(stdout)
println("  " * "-" ^ (45 + length(gammas) * 10)); flush(stdout)

for i in 2:n_steps
    @printf("  %-45s", step_names[i])
    for g in gammas
        prev = all_results[g].steps[i-1].ownership_rate
        curr = all_results[g].steps[i].ownership_rate
        ret = prev > 0.001 ? curr / prev * 100 : 0.0
        @printf("  %5.1f%%  ", ret)
    end
    println(); flush(stdout)
end

# Save CSV
tables_dir = joinpath(@__DIR__, "..", "tables", "csv")
mkpath(tables_dir)
csv_path = joinpath(tables_dir, "multigamma_decomposition.csv")
open(csv_path, "w") do f
    print(f, "step")
    for g in gammas
        @printf(f, ",own_gamma%.1f,alpha_gamma%.1f,ret_gamma%.1f", g, g, g)
    end
    println(f)
    for i in 1:n_steps
        print(f, step_names[i])
        for g in gammas
            own = all_results[g].steps[i].ownership_rate * 100
            alpha = all_results[g].steps[i].mean_alpha
            if i == 1
                ret = 0.0
            else
                prev = all_results[g].steps[i-1].ownership_rate
                ret = prev > 0.001 ? all_results[g].steps[i].ownership_rate / prev * 100 : 0.0
            end
            @printf(f, ",%.2f,%.4f,%.1f", own, alpha, ret)
        end
        println(f)
    end
end
println("\nCSV written: $csv_path"); flush(stdout)

# Save LaTeX table
tex_dir = joinpath(@__DIR__, "..", "tables", "tex")
mkpath(tex_dir)
tex_path = joinpath(tex_dir, "multigamma_decomposition.tex")
open(tex_path, "w") do f
    println(f, raw"\begin{table}[htbp]")
    println(f, raw"\centering")
    println(f, raw"\caption{Sequential Decomposition at Alternative Risk Aversion Values}")
    println(f, raw"\label{tab:multigamma}")
    println(f, raw"\begin{threeparttable}")
    # 3 gammas × 2 cols (own + ret) + step name = 7 cols
    println(f, raw"\begin{tabular}{l" * repeat("cc", length(gammas)) * "}")
    println(f, raw"\toprule")
    print(f, " ")
    for g in gammas
        @printf(f, " & \\multicolumn{2}{c}{\$\\gamma = %.1f\$}", g)
    end
    println(f, " \\\\")
    # Sub-header
    for _ in gammas
        print(f, " & Own.\\ (\\%) & Ret.\\ (\\%)")
    end
    println(f, " \\\\")
    println(f, raw"\midrule")
    for i in 1:n_steps
        print(f, step_names[i])
        for g in gammas
            own = all_results[g].steps[i].ownership_rate * 100
            if i == 1
                @printf(f, " & %.1f & ---", own)
            else
                prev = all_results[g].steps[i-1].ownership_rate
                ret = prev > 0.001 ? all_results[g].steps[i].ownership_rate / prev * 100 : 0.0
                @printf(f, " & %.1f & %.1f", own, ret)
            end
        end
        println(f, " \\\\")
    end
    println(f, raw"\bottomrule")
    println(f, raw"\end{tabular}")
    println(f, raw"\begin{tablenotes}")
    println(f, raw"\small")
    println(f, raw"\item Own.\ = predicted ownership rate (\%). Ret.\ = retention rate relative to previous step (\%).")
    @printf(f, "\\item All other parameters at production values (DFJ bequests, MWR \$= %.2f\$, \$\\pi = 2\\%%\$, \$\\psi = %.3f\$, \$\\lambda_W = %.3f\$, \$\\psi_{\\text{purchase}} = %.4f\$).\n",
            MWR_LOADED, SURVIVAL_PESSIMISM, LAMBDA_W, PSI_PURCHASE)
    println(f, raw"\end{tablenotes}")
    println(f, raw"\end{threeparttable}")
    println(f, raw"\end{table}")
end
println("LaTeX written: $tex_path"); flush(stdout)

println("\n" * "=" ^ 70); flush(stdout)
println("  MULTI-GAMMA DECOMPOSITION COMPLETE"); flush(stdout)
println("=" ^ 70); flush(stdout)

#=============================================================================
# ORIGINAL FILE: scripts/run_state_utility_sensitivity.jl
#=============================================================================

# State-dependent utility sensitivity: solve the full 9-channel model under both
# candidate φ(H) mappings and save the ownership predictions.
#
# Motivation: Finkelstein-Luttmer-Notowidigdo (2013) estimate that marginal utility
# of consumption is 10–25% lower in poor health. The literature uses two mappings:
#
#   Raw FLN central:            φ = [1.0, 0.90, 0.75]   (10%/25% reductions)
#   Reichling-Smetters (2015):  φ = [1.0, 0.95, 0.85]   (5%/15% reductions)
#
# Both are defensible. This script solves the full 9-channel model under each so
# the manuscript can report the sensitivity.
#
# Output: tables/csv/state_utility_sensitivity.csv
# Runtime: ~2–5 minutes (2 full-model solves).

using Printf
using DelimitedFiles
using Distributed

# Load module on all workers when running with -p N
if nworkers() > 1
    @everywhere include(joinpath(@__DIR__, "..", "src", "AnnuityPuzzle.jl"))
    @everywhere using .AnnuityPuzzle
else
    include(joinpath(@__DIR__, "..", "src", "AnnuityPuzzle.jl"))
    using .AnnuityPuzzle
end
include(joinpath(@__DIR__, "config.jl"))

const MAPPINGS = [
    ("FLN",             [1.0, 0.90, 0.75]),
    ("ReichlingSmetters",[1.0, 0.95, 0.85]),
]
const CONSUMPTION_DECLINE_ACTIVE = 0.02

const OUT_CSV = joinpath(@__DIR__, "..", "tables", "csv", "state_utility_sensitivity.csv")

# Mirror whatever MWR was used when the production CSVs were generated. We read
# the "Baseline" row of welfare_counterfactuals.csv so results stay comparable
# with the rest of tables/csv/ even if config.jl MWR_LOADED has since drifted.
function csv_baseline_mwr()
    path = joinpath(@__DIR__, "..", "tables", "csv", "welfare_counterfactuals.csv")
    for (i, line) in enumerate(eachline(path))
        i == 1 && continue
        if startswith(line, "Baseline,")
            toks = split(chopprefix(line, "Baseline,"), ',')
            return parse(Float64, toks[1])
        end
    end
    error("welfare_counterfactuals.csv: no Baseline row")
end
const MWR_FOR_RUN = csv_baseline_mwr()
@printf("MWR used for this sensitivity: %.2f  (from welfare_counterfactuals.csv)\n", MWR_FOR_RUN)

# ---------------------------------------------------------------------------
# Load HRS population sample (same filter as run_subset_enumeration.jl)
# ---------------------------------------------------------------------------

println("Loading HRS population sample...")
hrs_raw = readdlm(HRS_PATH, ',', Any; skipstart=1)
n_pop = size(hrs_raw, 1)
population = zeros(n_pop, 4)
population[:, 1] = Float64.(hrs_raw[:, 1])
population[:, 2] .= 0.0
population[:, 3] = Float64.(hrs_raw[:, 3])
if size(hrs_raw, 2) >= 4
    population[:, 4] = Float64.(hrs_raw[:, 4])
else
    population[:, 4] .= 2.0
end
@printf("  Loaded %d individuals\n", n_pop)

# ---------------------------------------------------------------------------
# Payout rates and survival (shared across solves)
# ---------------------------------------------------------------------------

p_base = ModelParams(age_start=AGE_START, age_end=AGE_END)
base_surv = build_lockwood_survival(p_base)

grid_kw = (n_wealth=N_WEALTH, n_annuity=N_ANNUITY, n_alpha=N_ALPHA,
           W_max=W_MAX, age_start=AGE_START, age_end=AGE_END,
           annuity_grid_power=A_GRID_POW)

p_fair = ModelParams(; gamma=GAMMA, beta=BETA, r=R_RATE, mwr=1.0, grid_kw...)
fair_pr = compute_payout_rate(p_fair, base_surv)

p_fair_nom = ModelParams(; gamma=GAMMA, beta=BETA, r=R_RATE, mwr=1.0,
                           inflation_rate=INFLATION, grid_kw...)
fair_pr_nom = compute_payout_rate(p_fair_nom, base_surv)
loaded_pr_nom = MWR_FOR_RUN * fair_pr_nom

# ---------------------------------------------------------------------------
# Filter population to wealth >= MIN_WEALTH
# ---------------------------------------------------------------------------

pop = population[population[:, 1] .>= MIN_WEALTH, :]
if size(pop, 2) < 4
    pop = hcat(pop, fill(2.0, size(pop, 1)))
end
@printf("  Eligible (W >= \$%d): %d\n", round(Int, MIN_WEALTH), size(pop, 1))

# ---------------------------------------------------------------------------
# Solve full 9-channel model under each mapping
# ---------------------------------------------------------------------------

common_kw = (gamma=GAMMA, beta=BETA, r=R_RATE,
             stochastic_health=true, n_health_states=3, n_quad=N_QUAD,
             c_floor=C_FLOOR, hazard_mult=Float64.(HAZARD_MULT))

# Build grids once (fair payout for coverage)
p_grid = ModelParams(; common_kw..., mwr=1.0, grid_kw...)
grids = build_grids(p_grid, max(fair_pr, fair_pr_nom))

# Parallel dispatch — each mapping is an independent full-model solve.
# Capture closures-friendly locals before pmap.
const _su_common_kw = common_kw
const _su_grid_kw = grid_kw
const _su_grids = grids
const _su_base_surv = base_surv
const _su_pop = pop
const _su_loaded_pr_nom = loaded_pr_nom

println("\nDispatching $(length(MAPPINGS)) mapping solves across $(max(nworkers(), 1)) workers...")
flush(stdout)
t0_dispatch = time()

results_raw = parallel_solve(MAPPINGS) do (label, phi)
    # Nine-channel solve: rational stack + age-varying needs + state-dependent
    # utility under each mapping. The two behavioral channels (lambda_w, psi_purchase)
    # are intentionally OFF so the output is a true nine-channel ownership.
    p_model = ModelParams(; _su_common_kw...,
        theta=THETA_DFJ, kappa=KAPPA_DFJ,
        mwr=MWR_FOR_RUN, fixed_cost=FIXED_COST,
        min_purchase=MIN_PURCHASE,
        inflation_rate=INFLATION,
        medical_enabled=true,
        health_mortality_corr=true,
        survival_pessimism=SURVIVAL_PESSIMISM,
        consumption_decline=CONSUMPTION_DECLINE_ACTIVE,
        health_utility=phi,
        _su_grid_kw...)
    t0 = time()
    res = solve_and_evaluate(p_model, _su_grids, _su_base_surv,
        Float64.(SS_QUARTILE_LEVELS), _su_pop, _su_loaded_pr_nom;
        step_name="", verbose=false)
    return (label=label, phi_good=phi[1], phi_fair=phi[2], phi_poor=phi[3],
            ownership_pct=res.ownership * 100, mean_alpha=res.mean_alpha,
            solve_time=time() - t0)
end
elapsed_dispatch = time() - t0_dispatch
@printf("\nMaster dispatch wall-clock: %.0fs (%.1f min)\n",
        elapsed_dispatch, elapsed_dispatch / 60)

# Render per-spec output in original format
rows = Vector{NamedTuple}()
for r in results_raw
    @printf("\n=== Mapping: %s  φ = [%.2f, %.2f, %.2f] ===\n",
            r.label, r.phi_good, r.phi_fair, r.phi_poor)
    @printf("  Ownership: %.4f%%  |  Mean alpha: %.4f  |  %.1fs\n",
            r.ownership_pct, r.mean_alpha, r.solve_time)
    push!(rows, r)
end

# ---------------------------------------------------------------------------
# Write CSV
# ---------------------------------------------------------------------------

mkpath(dirname(OUT_CSV))
open(OUT_CSV, "w") do f
    println(f, "label,phi_good,phi_fair,phi_poor,ownership_pct,mean_alpha,solve_time")
    for r in rows
        @printf(f, "%s,%.2f,%.2f,%.2f,%.4f,%.6f,%.1f\n",
                r.label, r.phi_good, r.phi_fair, r.phi_poor,
                r.ownership_pct, r.mean_alpha, r.solve_time)
    end
end
@printf("\nWrote %s\n", OUT_CSV)

#=============================================================================
# ORIGINAL FILE: scripts/run_ageband_hazard.jl
#=============================================================================

# Compute ownership under age-varying HRS hazard multipliers.
# Uses solve_lifecycle_health + compute_ownership_rate_health directly.

using Printf, DelimitedFiles

include(joinpath(@__DIR__, "..", "src", "AnnuityPuzzle.jl"))
using .AnnuityPuzzle

include(joinpath(@__DIR__, "config.jl"))

println("Loading data...")
flush(stdout)

p_base = ModelParams(age_start=AGE_START, age_end=AGE_END)
base_surv = build_lockwood_survival(p_base)

hrs_raw = readdlm(HRS_PATH, ',', Any; skipstart=1)
n_pop = size(hrs_raw, 1)
population = zeros(n_pop, 4)
population[:, 1] = Float64.(hrs_raw[:, 1])
population[:, 2] .= 0.0
population[:, 3] = Float64.(hrs_raw[:, 3])
population[:, 4] = size(hrs_raw, 2) >= 4 ? Float64.(hrs_raw[:, 4]) : fill(2.0, n_pop)

# HRS empirical hazard multipliers by age band
hm_by_age = [0.49 1.0 3.29;   # 65-74
             0.60 1.0 2.77;   # 75-84
             0.74 1.0 1.82]   # 85+
hm_midpoints = [70.0, 80.0, 90.0]

println("Building model with age-varying hazard multipliers...")
flush(stdout)
t0 = time()

# Full model with all channels + age-varying hazard
p_model = ModelParams(
    gamma=GAMMA, beta=BETA, r=R_RATE, c_floor=C_FLOOR,
    mwr=MWR_LOADED, fixed_cost=FIXED_COST, inflation_rate=INFLATION,
    theta=THETA_DFJ, kappa=KAPPA_DFJ,
    stochastic_health=true, n_health_states=3, n_quad=N_QUAD,
    medical_enabled=true, health_mortality_corr=true,
    hazard_mult_by_age=hm_by_age, hazard_mult_age_midpoints=hm_midpoints,
    survival_pessimism=SURVIVAL_PESSIMISM,
    n_wealth=N_WEALTH, n_annuity=N_ANNUITY, n_alpha=N_ALPHA,
    W_max=W_MAX, age_start=AGE_START, age_end=AGE_END,
    annuity_grid_power=A_GRID_POW,
)

# Payout rate
fair_pr_nom = compute_payout_rate(
    ModelParams(gamma=GAMMA, beta=BETA, r=R_RATE, mwr=1.0,
                inflation_rate=INFLATION,
                n_wealth=N_WEALTH, n_annuity=N_ANNUITY, n_alpha=N_ALPHA,
                W_max=W_MAX, age_start=AGE_START, age_end=AGE_END,
                annuity_grid_power=A_GRID_POW),
    base_surv)
loaded_pr = MWR_LOADED * fair_pr_nom
grids = build_grids(p_model, fair_pr_nom)

# SS function
function ss_func(age, p)
    # Use the same quartile-based SS as the decomposition
    return 0.0  # Will be handled via population income column
end

println("Solving lifecycle model...")
flush(stdout)
sol = solve_lifecycle_health(p_model, grids, base_surv, ss_func)

println("Computing ownership rate...")
flush(stdout)

# Set population income to SS levels by wealth quartile
pop_with_ss = copy(population)
wealth_col = pop_with_ss[:, 1]
sorted_w = sort(wealth_col)
q25 = sorted_w[max(1, div(length(sorted_w), 4))]
q50 = sorted_w[max(1, div(length(sorted_w), 2))]
q75 = sorted_w[max(1, div(3 * length(sorted_w), 4))]

ss_levels = [14_000.0, 17_000.0, 20_000.0, 25_000.0]
for i in 1:size(pop_with_ss, 1)
    w = pop_with_ss[i, 1]
    if w <= q25
        pop_with_ss[i, 2] = ss_levels[1]
    elseif w <= q50
        pop_with_ss[i, 2] = ss_levels[2]
    elseif w <= q75
        pop_with_ss[i, 2] = ss_levels[3]
    else
        pop_with_ss[i, 2] = ss_levels[4]
    end
end

result = compute_ownership_rate_health(sol, pop_with_ss, loaded_pr)
elapsed = time() - t0

@printf("\n  Age-varying HRS (3 bands): %.1f%% ownership (%.0fs)\n", result.ownership_rate * 100, elapsed)
@printf("  Compare baseline [0.50, 1.0, 3.0]: 18.3%%\n")
flush(stdout)

# Append to robustness CSV
csv_path = joinpath(@__DIR__, "..", "tables", "csv", "robustness_full.csv")
if isfile(csv_path)
    open(csv_path, "a") do io
        @printf(io, "Hazard mult,Age-varying HRS (3 bands),%.1f%%\n", result.ownership_rate * 100)
    end
    println("  Appended to $csv_path")
end
println("Done.")
flush(stdout)

#=============================================================================
# ORIGINAL FILE: scripts/run_ss_robustness.jl
#=============================================================================

# Social Security Benefit Cut Robustness Analysis
#
# Computes predicted private annuity demand under varying magnitudes
# of Social Security benefit reductions. The full model (all channels
# on) is solved at each cut level.
#
# Cut sizes: 0% (baseline), 10%, 15%, 23% (trust fund), 30%, 40%, 50%, 100%
#
# Usage: julia --project=. -p 8 scripts/run_ss_robustness.jl

using Printf
using DelimitedFiles
using Distributed

if nworkers() > 1
    @everywhere include(joinpath(@__DIR__, "..", "src", "AnnuityPuzzle.jl"))
    @everywhere using .AnnuityPuzzle
else
    include(joinpath(@__DIR__, "..", "src", "AnnuityPuzzle.jl"))
    using .AnnuityPuzzle
end

include(joinpath(@__DIR__, "config.jl"))

println("=" ^ 70)
println("  SOCIAL SECURITY BENEFIT CUT ROBUSTNESS ANALYSIS")
println("  Private Annuity Demand Response to SS Reductions")
println("=" ^ 70)
flush(stdout)

# ===================================================================
# Load HRS population sample
# ===================================================================
println("\nLoading HRS population sample...")
flush(stdout)
hrs_raw = readdlm(HRS_PATH, ',', Any; skipstart=1)
n_pop = size(hrs_raw, 1)
population = zeros(n_pop, 4)
population[:, 1] = Float64.(hrs_raw[:, 1])  # wealth
population[:, 2] .= 0.0                      # SS via ss_func, not A grid
population[:, 3] = Float64.(hrs_raw[:, 3])  # age
if size(hrs_raw, 2) >= 4
    population[:, 4] = Float64.(hrs_raw[:, 4])  # health (1=Good, 2=Fair, 3=Poor)
else
    population[:, 4] .= 2.0
end
@printf("  Loaded %d individuals\n", n_pop)
flush(stdout)

# ===================================================================
# Build survival probabilities
# ===================================================================
p_base = ModelParams(age_start=AGE_START, age_end=AGE_END)
base_surv = build_lockwood_survival(p_base)

# Pre-compute payout rates
grid_kw = (n_wealth=N_WEALTH, n_annuity=N_ANNUITY, n_alpha=N_ALPHA,
           W_max=W_MAX, age_start=AGE_START, age_end=AGE_END,
           annuity_grid_power=A_GRID_POW)

common_kw = (gamma=GAMMA, beta=BETA, r=R_RATE,
             stochastic_health=true, n_health_states=3, n_quad=N_QUAD,
             c_floor=C_FLOOR, hazard_mult=HAZARD_MULT)

p_fair = ModelParams(; common_kw..., mwr=1.0, grid_kw...)
fair_pr = compute_payout_rate(p_fair, base_surv)

p_fair_nom = ModelParams(; common_kw..., mwr=1.0,
                           inflation_rate=INFLATION, grid_kw...)
fair_pr_nom = INFLATION > 0 ? compute_payout_rate(p_fair_nom, base_surv) : fair_pr

# Loaded nominal payout rate (full model uses inflation + loads)
loaded_pr_nom = MWR_LOADED * fair_pr_nom

# Build grids (shared across all cut levels)
grids = build_grids(p_fair, max(fair_pr, fair_pr_nom))

@printf("  Loaded payout rate (MWR=%.2f, infl=%.0f%%): %.4f\n",
    MWR_LOADED, INFLATION * 100, loaded_pr_nom)
flush(stdout)

# ===================================================================
# Define SS cut levels
# ===================================================================
cut_fractions = [0.0, 0.10, 0.15, 0.23, 0.30, 0.40, 0.50, 1.0]

@printf("\n  SS quartile levels (baseline): [%s]\n",
    join([@sprintf("\$%.0fK", l / 1000) for l in SS_QUARTILE_LEVELS], ", "))
flush(stdout)

# ===================================================================
# Solve each cut level (parallelized)
# ===================================================================
println("\nSolving full model at each SS cut level...")
flush(stdout)

# Capture for closures (explicit local variables for pmap serialization)
_population = population
_base_surv = base_surv
_ss_q_levels = Float64.(SS_QUARTILE_LEVELS)
_min_wealth = MIN_WEALTH
_gamma = GAMMA
_beta = BETA
_r_rate = R_RATE
_n_quad = N_QUAD
_c_floor = C_FLOOR
_hazard_mult = Float64.(HAZARD_MULT)
_theta_dfj = THETA_DFJ
_kappa_dfj = KAPPA_DFJ
_mwr_loaded = MWR_LOADED
_fixed_cost = FIXED_COST
_min_purchase = MIN_PURCHASE
_lambda_w = LAMBDA_W
_psi_purchase = PSI_PURCHASE
_consumption_decline = CONSUMPTION_DECLINE
_health_utility = Float64.(HEALTH_UTILITY)
_inflation = INFLATION
_surv_pess = SURVIVAL_PESSIMISM
_n_wealth = N_WEALTH
_n_annuity = N_ANNUITY
_n_alpha = N_ALPHA
_w_max = W_MAX
_age_start = AGE_START
_age_end = AGE_END
_a_grid_pow = A_GRID_POW

t0 = time()

cut_results = parallel_solve(cut_fractions) do cut_frac
    # Scale SS levels
    ss_lvls = (1.0 - cut_frac) .* _ss_q_levels

    # Full model params (all channels on)
    gkw = (n_wealth=_n_wealth, n_annuity=_n_annuity, n_alpha=_n_alpha,
           W_max=_w_max, age_start=_age_start, age_end=_age_end,
           annuity_grid_power=_a_grid_pow)

    ckw = (gamma=_gamma, beta=_beta, r=_r_rate,
           stochastic_health=true, n_health_states=3, n_quad=_n_quad,
           c_floor=_c_floor, hazard_mult=_hazard_mult)

    p_model = ModelParams(; ckw...,
        theta=_theta_dfj, kappa=_kappa_dfj,
        mwr=_mwr_loaded, fixed_cost=_fixed_cost, min_purchase=_min_purchase,
        inflation_rate=_inflation,
        medical_enabled=true, health_mortality_corr=true,
        survival_pessimism=_surv_pess,
        consumption_decline=_consumption_decline,
        health_utility=_health_utility,
        lambda_w=_lambda_w,
        psi_purchase=_psi_purchase,
        gkw...)

    # Build grids on worker
    p_fg = ModelParams(; ckw..., mwr=1.0, gkw...)
    fp = compute_payout_rate(p_fg, _base_surv)
    p_fn = ModelParams(; ckw..., mwr=1.0, inflation_rate=_inflation, gkw...)
    fpn = _inflation > 0 ? compute_payout_rate(p_fn, _base_surv) : fp
    local_grids = build_grids(p_fg, max(fp, fpn))

    lpr = _mwr_loaded * fpn

    # Filter population
    pop = copy(_population)
    if _min_wealth > 0.0
        mask = pop[:, 1] .>= _min_wealth
        pop = pop[mask, :]
    end
    if size(pop, 2) < 4
        pop = hcat(pop, fill(2.0, size(pop, 1)))
    end

    res = solve_and_evaluate(p_model, local_grids, _base_surv, ss_lvls,
        pop, lpr; step_name="", verbose=false)

    (cut_pct=cut_frac * 100,
     ownership=res.ownership,
     mean_alpha=res.mean_alpha)
end

solve_time = time() - t0
@printf("  Solved %d configurations in %.0fs\n", length(cut_fractions), solve_time)
flush(stdout)

# Sort by cut percentage
sort!(cut_results, by=r -> r.cut_pct)

# ===================================================================
# Print results
# ===================================================================
println("\n" * "=" ^ 70)
println("  RESULTS: PRIVATE ANNUITY DEMAND vs SS BENEFIT CUTS")
println("=" ^ 70)

baseline_own = cut_results[1].ownership

@printf("\n  %-15s  %12s  %10s  %12s\n",
    "SS Cut (%)", "Ownership", "Mean alpha", "vs Baseline")
println("  " * "-" ^ 55)

for r in cut_results
    delta = r.ownership - baseline_own
    delta_str = r.cut_pct == 0.0 ? "---" : @sprintf("%+.1f pp", delta * 100)
    label = r.cut_pct == 23.0 ? @sprintf("%.0f (trust fund)", r.cut_pct) :
            r.cut_pct == 100.0 ? @sprintf("%.0f (elimination)", r.cut_pct) :
            @sprintf("%.0f", r.cut_pct)
    @printf("  %-15s  %10.1f%%  %10.3f  %12s\n",
        label, r.ownership * 100, r.mean_alpha, delta_str)
end
println("  " * "-" ^ 55)
@printf("  %-15s  %10.1f%%\n", "Observed", 3.6)
flush(stdout)

# ===================================================================
# Save CSV
# ===================================================================
tables_dir = joinpath(@__DIR__, "..", "tables")
mkpath(joinpath(tables_dir, "csv"))
mkpath(joinpath(tables_dir, "tex"))

csv_path = joinpath(tables_dir, "csv", "ss_cut_robustness.csv")
open(csv_path, "w") do f
    println(f, "cut_pct,ownership_pct,mean_alpha")
    for r in cut_results
        @printf(f, "%.0f,%.2f,%.4f\n", r.cut_pct, r.ownership * 100, r.mean_alpha)
    end
end
println("\n  CSV saved: $csv_path")
flush(stdout)

# ===================================================================
# Save LaTeX table
# ===================================================================
tex_path = joinpath(tables_dir, "tex", "ss_cut_robustness.tex")
open(tex_path, "w") do f
    println(f, raw"\begin{table}[htbp]")
    println(f, raw"\centering")
    println(f, raw"\caption{Private Annuity Demand Response to Social Security Benefit Reductions}")
    println(f, raw"\label{tab:ss_cut}")
    println(f, raw"\begin{tabular}{lccc}")
    println(f, raw"\toprule")
    println(f, "SS Benefit Cut & Ownership (\\%) & Mean \$\\alpha\$ & \$\\Delta\$ (pp) \\\\")
    println(f, raw"\midrule")

    for r in cut_results
        delta = r.ownership - baseline_own
        label = if r.cut_pct == 0.0
            "0\\% (baseline)"
        elseif r.cut_pct == 23.0
            "23\\% (trust fund)"
        elseif r.cut_pct == 100.0
            "100\\% (elimination)"
        else
            @sprintf("%.0f\\%%", r.cut_pct)
        end
        delta_str = r.cut_pct == 0.0 ? "---" : @sprintf("%+.1f", delta * 100)
        @printf(f, "%s & %.1f & %.3f & %s \\\\\n",
            label, r.ownership * 100, r.mean_alpha, delta_str)
    end

    println(f, raw"\midrule")
    println(f, "Observed (Lockwood 2012) & 3.6 & & \\\\")
    println(f, raw"\bottomrule")
    println(f, raw"\end{tabular}")
    println(f, raw"\begin{tablenotes}")
    println(f, raw"\small")
    println(f, raw"\item Full model with all channels active. SS quartile levels")
    levels_str = join([string("\\\$", round(Int, l / 1000), "K") for l in SS_QUARTILE_LEVELS], ", ")
    println(f, "scaled by (1 -- cut fraction). Baseline levels: [$(levels_str)].")
    println(f, raw"23\% cut corresponds to projected trust fund exhaustion circa 2033.")
    println(f, raw"100\% cut is a theoretical benchmark (complete SS elimination).")
    println(f, raw"\end{tablenotes}")
    println(f, raw"\end{table}")
end
println("  LaTeX saved: $tex_path")

println("\n" * "=" ^ 70)
println("  SS CUT ROBUSTNESS ANALYSIS COMPLETE")
println("=" ^ 70)
flush(stdout)

#=============================================================================
# ORIGINAL FILE: scripts/grid_convergence_full.jl
#=============================================================================

# Quadrature and grid convergence diagnostics.
# Runs the full model at multiple quadrature node counts and grid resolutions,
# reporting both binary ownership rate and continuous metrics (mean alpha).
#
# Output: tables/csv/convergence_diagnostics.csv

using Printf, DelimitedFiles

include(joinpath(@__DIR__, "..", "src", "AnnuityPuzzle.jl"))
using .AnnuityPuzzle

println("=" ^ 70); flush(stdout)
println("  QUADRATURE & GRID CONVERGENCE DIAGNOSTICS"); flush(stdout)
println("=" ^ 70); flush(stdout)

# Setup
const THETA_DFJ = 56.96
const KAPPA_DFJ = 272_628.0

hrs_raw = readdlm(joinpath(@__DIR__, "..", "data", "processed", "lockwood_hrs_sample.csv"),
                   ',', Any; skipstart=1)
n_pop = size(hrs_raw, 1)
population = zeros(n_pop, 4)
population[:, 1] = Float64.(hrs_raw[:, 1])
population[:, 2] .= 0.0                      # SS enters via ss_func, not A grid
population[:, 3] = Float64.(hrs_raw[:, 3])
if size(hrs_raw, 2) >= 4
    population[:, 4] = Float64.(hrs_raw[:, 4])  # observed health (1=Good, 2=Fair, 3=Poor)
else
    population[:, 4] .= 2.0
end

p_base = ModelParams(age_start=65, age_end=110)
base_surv = build_lockwood_survival(p_base)
println("Data loaded ($n_pop obs)"); flush(stdout)

results = Tuple{String,String,Float64,Float64}[]  # (category, spec, ownership, mean_alpha)

function solve_and_report(label, category, base_surv, population; kw...)
    t0 = time()

    kw_dict = Dict{Symbol,Any}(kw...)
    # Defaults
    gamma = get(kw_dict, :gamma, 2.5)
    beta = get(kw_dict, :beta, 0.97)
    r = get(kw_dict, :r, 0.02)
    nw = get(kw_dict, :n_wealth, 80)
    na = get(kw_dict, :n_annuity, 30)
    nalpha = get(kw_dict, :n_alpha, 101)
    wmax = get(kw_dict, :W_max, 3_000_000.0)
    agp = get(kw_dict, :annuity_grid_power, 3.0)
    nq = get(kw_dict, :n_quad, 5)
    mwr_loaded = get(kw_dict, :mwr_loaded, 0.82)
    inflation = get(kw_dict, :inflation_val, 0.02)
    psi = get(kw_dict, :survival_pessimism, 0.981)
    hm = get(kw_dict, :hazard_mult, [0.50, 1.0, 3.0])
    min_wealth = get(kw_dict, :min_wealth, 5000.0)

    grid_kw = (n_wealth=nw, n_annuity=na, n_alpha=nalpha,
               W_max=wmax, age_start=65, age_end=110,
               annuity_grid_power=agp)

    # Compute payout rates
    p_fair_nom = ModelParams(; gamma=gamma, beta=beta, r=r, mwr=1.0,
                               inflation_rate=inflation, grid_kw...)
    fair_pr_nom = compute_payout_rate(p_fair_nom, base_surv)
    loaded_pr_nom = mwr_loaded * fair_pr_nom

    p_fair = ModelParams(; gamma=gamma, beta=beta, r=r, mwr=1.0, grid_kw...)
    fair_pr = compute_payout_rate(p_fair, base_surv)
    grids = build_grids(p_fair, max(fair_pr, fair_pr_nom))

    # Full model params
    p_full = ModelParams(; gamma=gamma, beta=beta, r=r,
        theta=THETA_DFJ, kappa=KAPPA_DFJ,
        stochastic_health=true, n_health_states=3, n_quad=nq,
        c_floor=6180.0, hazard_mult=hm,
        mwr=mwr_loaded, fixed_cost=1000.0, inflation_rate=inflation,
        medical_enabled=true, health_mortality_corr=true,
        survival_pessimism=psi,
        grid_kw...)

    # Mean SS
    ss_mean_val = sum(SS_QUARTILE_LEVELS) / length(SS_QUARTILE_LEVELS)
    ss_func(age, p) = ss_mean_val

    # Filter population
    pop_filt = copy(population)
    mask = pop_filt[:, 1] .>= min_wealth
    pop_filt = pop_filt[mask, :]
    if size(pop_filt, 2) < 4
        pop_filt = hcat(pop_filt, fill(2.0, size(pop_filt, 1)))
    end

    sol = solve_lifecycle_health(p_full, grids, base_surv, ss_func)
    result = compute_ownership_rate_health(sol, pop_filt, loaded_pr_nom;
                                           base_surv=base_surv)

    own = result.ownership_rate
    mean_a = result.mean_alpha
    dt = time() - t0
    @printf("  %-45s  own=%6.2f%%  mean_α=%.5f  (%5.1fs)\n", label, own * 100, mean_a, dt)
    flush(stdout)
    push!(results, (category, label, own, mean_a))
    return (own, mean_a)
end

# --- 1. Quadrature convergence (fixed grid 80x30) ---
println("\n--- QUADRATURE CONVERGENCE (80x30 grid) ---"); flush(stdout)
for nq in [3, 5, 7, 9, 11, 13, 15]
    label = @sprintf("n_quad=%d", nq)
    solve_and_report(label, "Quadrature", base_surv, population; n_quad=nq)
end

# --- 2. Grid convergence (fixed 5-node GH) ---
println("\n--- GRID CONVERGENCE (5-node GH) ---"); flush(stdout)
for (nw, na) in [(40, 15), (60, 20), (80, 30), (100, 40), (120, 50)]
    label = @sprintf("Grid %dx%d (5-node)", nw, na)
    solve_and_report(label, "Grid (5-node)", base_surv, population; n_wealth=nw, n_annuity=na, n_quad=5)
end

# --- 3. Grid convergence with 9-node GH ---
println("\n--- GRID CONVERGENCE (9-node GH) ---"); flush(stdout)
for (nw, na) in [(60, 20), (80, 30), (100, 40), (120, 50)]
    label = @sprintf("Grid %dx%d (9-node)", nw, na)
    solve_and_report(label, "Grid (9-node)", base_surv, population; n_wealth=nw, n_annuity=na, n_quad=9)
end

# --- 4. Combined: finest grid + highest quadrature ---
println("\n--- REFERENCE (120x50, 11-node GH) ---"); flush(stdout)
solve_and_report("Grid 120x50 (11-node)", "Reference", base_surv, population;
                 n_wealth=120, n_annuity=50, n_quad=11)

println("\n" * "=" ^ 70); flush(stdout)
println("  CONVERGENCE DIAGNOSTICS COMPLETE"); flush(stdout)
println("=" ^ 70); flush(stdout)

# Save CSV
csv_path = joinpath(@__DIR__, "..", "tables", "csv", "convergence_diagnostics.csv")
mkpath(dirname(csv_path))
open(csv_path, "w") do f
    println(f, "category,specification,ownership_pct,mean_alpha")
    for (cat, spec, own, ma) in results
        @printf(f, "%s,%s,%.2f,%.6f\n", cat, spec, own * 100, ma)
    end
end
println("CSV written: $csv_path"); flush(stdout)
