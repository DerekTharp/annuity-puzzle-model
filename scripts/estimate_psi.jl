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
    println("  ANCHOR C: psi calibrated to UK BEHAVIORAL elasticity (60-65 pp)")
    println("  (tax-effect-stripped UK behavioral component)")
    println("=" ^ 70)
    @printf("\n  %-30s  %10s  %12s  %10s\n",
            "UK behavioral drop (pp)", "psi_hat", "model drop pp", "US ownership")
    println("  " * "-" ^ 70)
    anchor_c_55 = find_psi_for_drop(55.0)
    anchor_c_60 = find_psi_for_drop(60.0)
    anchor_c_65 = find_psi_for_drop(65.0)
    for (lab, r) in [("UK low (55 pp behavioral)", anchor_c_55),
                     ("UK mid (60 pp behavioral)", anchor_c_60),
                     ("UK high (65 pp behavioral)", anchor_c_65)]
        @printf("  %-30s  %10.4f  %12.2f  %10.2f%%\n",
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
