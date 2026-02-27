# Consumption-equivalent variation (CEV) welfare calculations.
# CEV = percentage increase in consumption at all dates/states that makes
# the individual indifferent between having and not having annuity access.
#
# For CRRA utility U(c) = c^(1-gamma)/(1-gamma):
#   lambda = (V_with / V_without)^(1/(1-gamma)) - 1
#
# Positive CEV means the individual benefits from annuity market access.

using Interpolations
using Printf

struct CEVResult
    cev::Float64          # consumption-equivalent variation (fraction)
    alpha_star::Float64   # optimal annuity fraction
    V_no_ann::Float64     # value without annuity access
    V_with_ann::Float64   # value with optimal annuity
end

"""
Compute CEV for a single individual.

Given a solved HealthSolution, evaluate the welfare gain from annuity
market access for an individual with initial state (W_0, y_existing, H_0).

The CEV formula for CRRA:
  lambda = (V_with / V_without)^(1/(1-gamma)) - 1

With DFJ bequests (kappa > 0) the formula is approximate but standard
in the literature (Lockwood 2012, Reichling-Smetters 2015).
"""
function compute_cev(
    sol::HealthSolution,
    W_0::Float64,
    y_existing::Float64,
    H_0::Int,
    payout_rate::Float64,
)
    p = sol.params
    g = sol.grids

    # Trivial case: no wealth to annuitize
    if W_0 < 1.0
        return CEVResult(0.0, 0.0, 0.0, 0.0)
    end

    # 2D interpolation of V(W, A, H=H_0, t=1)
    V_t1 = sol.V[:, :, H_0, 1]
    V_interp = linear_interpolation(
        (g.W, g.A), V_t1,
        extrapolation_bc=Interpolations.Flat(),
    )

    W_c = clamp(W_0, g.W[1], g.W[end])
    y_c = clamp(y_existing, g.A[1], g.A[end])

    # V without annuity purchase
    V_no_ann = V_interp(W_c, y_c)

    # Search over alpha grid for best V with annuity purchase
    best_V = V_no_ann
    best_alpha = 0.0
    for alpha in g.alpha
        alpha <= 0.0 && continue
        is_feasible_purchase(alpha, W_0, p) || continue
        pi = alpha * W_0
        W_rem = W_0 - pi
        if p.fixed_cost > 0.0
            W_rem -= p.fixed_cost
        end
        W_rem < 0.0 && continue

        A_new = pi * payout_rate
        A_total = y_existing + A_new
        W_rc = clamp(W_rem, g.W[1], g.W[end])
        A_tc = clamp(A_total, g.A[1], g.A[end])
        V_val = V_interp(W_rc, A_tc)
        if V_val > best_V
            best_V = V_val
            best_alpha = alpha
        end
    end

    V_with_ann = best_V

    # Compute CEV
    # Both V values must be finite and V_with > V_without for positive CEV
    if !isfinite(V_no_ann) || !isfinite(V_with_ann)
        return CEVResult(0.0, best_alpha, V_no_ann, V_with_ann)
    end
    if V_with_ann <= V_no_ann + 1e-12
        return CEVResult(0.0, 0.0, V_no_ann, V_no_ann)
    end

    # CRRA CEV formula: lambda = (V_with / V_without)^(1/(1-gamma)) - 1
    # Both V values are negative for gamma > 1, so the ratio is positive.
    gamma = p.gamma
    if gamma == 1.0
        # Log utility: V = log(c) + ..., CEV = exp(V_with - V_without) - 1
        cev = exp(V_with_ann - V_no_ann) - 1.0
    else
        # V = c^(1-gamma)/(1-gamma), V < 0 for gamma > 1
        ratio = V_with_ann / V_no_ann
        # For gamma > 1: both V negative, ratio > 0.
        # V_with > V_without (less negative) => ratio < 1
        # (1-gamma) < 0 => exponent 1/(1-gamma) < 0 => ratio^(neg) > 1 => cev > 0
        if ratio <= 0.0
            return CEVResult(0.0, best_alpha, V_no_ann, V_with_ann)
        end
        cev = ratio^(1.0 / (1.0 - gamma)) - 1.0
    end

    # Sanity bound: CEV shouldn't exceed 200% (numerical artifact)
    cev = clamp(cev, -1.0, 2.0)

    return CEVResult(cev, best_alpha, V_no_ann, V_with_ann)
end

"""
Compute CEV for each individual in a population sample.

Population columns: [wealth, income, age, health_state].
If health column is missing, defaults to Fair (2).

Returns (results, mean_cev, median_cev, frac_positive, frac_above_1pct).
"""
function compute_cev_population(
    sol::HealthSolution,
    population::Matrix{Float64},
    payout_rate_age65::Float64;
    base_surv::Union{Vector{Float64}, Nothing}=nothing,
)
    p = sol.params
    g = sol.grids
    n_individuals = size(population, 1)
    has_age = size(population, 2) >= 3
    has_health = size(population, 2) >= 4

    results = CEVResult[]
    sizehint!(results, n_individuals)

    # Precompute interpolation objects keyed by (health, time)
    interp_cache = Dict{Tuple{Int,Int}, typeof(linear_interpolation(
        (g.W, g.A), sol.V[:, :, 1, 1],
        extrapolation_bc=Interpolations.Flat(),
    ))}()

    for i in 1:n_individuals
        W_0 = population[i, 1]
        y_0 = population[i, 2]
        age = has_age ? Int(population[i, 3]) : p.age_start
        ih = has_health ? Int(population[i, 4]) : 2

        # Skip agents with wealth below minimum or above grid max
        # (boundary extrapolation produces unreliable CEV)
        if W_0 < 1.0 || W_0 > g.W[end]
            push!(results, CEVResult(0.0, 0.0, 0.0, 0.0))
            continue
        end

        t = age - p.age_start + 1
        if t < 1 || t > p.T
            push!(results, CEVResult(0.0, 0.0, 0.0, 0.0))
            continue
        end

        # Age-specific payout rate
        if base_surv !== nothing && age > p.age_start
            remaining_T = p.T - t + 1
            pv = 1.0
            for s in 1:(remaining_T - 1)
                cum_s = 1.0
                for k in t:(t + s - 1)
                    k > length(base_surv) && break
                    cum_s *= base_surv[k]
                end
                pv += cum_s / (1.0 + p.r)^s
            end
            payout_rate = p.mwr / pv
        else
            payout_rate = payout_rate_age65
        end

        # Use cached interpolation for this (health, time) pair
        V_interp = get!(interp_cache, (ih, t)) do
            linear_interpolation(
                (g.W, g.A), sol.V[:, :, ih, t],
                extrapolation_bc=Interpolations.Flat(),
            )
        end

        W_c = clamp(W_0, g.W[1], g.W[end])
        y_c = clamp(y_0, g.A[1], g.A[end])

        V_no_ann = V_interp(W_c, y_c)

        # Optimal annuity search
        best_V = V_no_ann
        best_alpha = 0.0
        for alpha in g.alpha
            alpha <= 0.0 && continue
            is_feasible_purchase(alpha, W_0, p) || continue
            pi = alpha * W_0
            W_rem = W_0 - pi
            if p.fixed_cost > 0.0
                W_rem -= p.fixed_cost
            end
            W_rem < 0.0 && continue

            A_new = pi * payout_rate
            A_total = y_0 + A_new
            W_rc = clamp(W_rem, g.W[1], g.W[end])
            A_tc = clamp(A_total, g.A[1], g.A[end])
            V_val = V_interp(W_rc, A_tc)
            if V_val > best_V
                best_V = V_val
                best_alpha = alpha
            end
        end

        # CEV calculation
        gamma = p.gamma
        if !isfinite(V_no_ann) || !isfinite(best_V) || best_V <= V_no_ann + 1e-12
            push!(results, CEVResult(0.0, 0.0, V_no_ann, V_no_ann))
            continue
        end

        if gamma == 1.0
            cev = exp(best_V - V_no_ann) - 1.0
        else
            ratio = best_V / V_no_ann
            if ratio <= 0.0
                push!(results, CEVResult(0.0, best_alpha, V_no_ann, best_V))
                continue
            end
            cev = ratio^(1.0 / (1.0 - gamma)) - 1.0
        end
        cev = clamp(cev, -1.0, 2.0)

        push!(results, CEVResult(cev, best_alpha, V_no_ann, best_V))
    end

    # Summary statistics
    cevs = [r.cev for r in results]
    mean_cev = length(cevs) > 0 ? sum(cevs) / length(cevs) : 0.0
    sorted = sort(cevs)
    median_cev = length(sorted) > 0 ? sorted[div(length(sorted) + 1, 2)] : 0.0
    frac_positive = count(c -> c > 0.0, cevs) / max(length(cevs), 1)
    frac_above_1pct = count(c -> c > 0.01, cevs) / max(length(cevs), 1)

    return (
        results=results,
        mean_cev=mean_cev,
        median_cev=median_cev,
        frac_positive=frac_positive,
        frac_above_1pct=frac_above_1pct,
    )
end

"""
Compute CEV across a wealth x bequest x health grid.

This produces the "heterogeneous welfare map" — the key Phase 5 output.
For each bequest specification, solves the full model (all channels on)
then evaluates CEV at each (wealth, health) point.

Returns a NamedTuple with:
- grid: 3D array (n_wealth x n_bequest x n_health) of CEVResult
- wealth_points, bequest_names, health_names: labels
- population_cev: per-bequest population-level CEV stats
"""
function compute_cev_grid(
    base_surv::Vector{Float64},
    population_full::Matrix{Float64};
    bequest_specs::Union{Vector{<:NamedTuple}, Nothing}=nothing,
    wealth_points::Vector{Float64}=[10_000.0, 25_000.0, 50_000.0, 100_000.0,
                                     200_000.0, 500_000.0, 1_000_000.0],
    y_existing::Float64=0.0,
    gamma::Float64=2.5,
    beta::Float64=0.97,
    r::Float64=0.02,
    c_floor::Float64=6_180.0,
    mwr_loaded::Float64=0.82,
    fixed_cost_val::Float64=1_000.0,
    inflation_val::Float64=0.02,
    n_wealth::Int=60,
    n_annuity::Int=20,
    n_alpha::Int=51,
    W_max::Float64=3_000_000.0,
    n_quad::Int=5,
    age_start::Int=65,
    age_end::Int=110,
    annuity_grid_power::Float64=3.0,
    hazard_mult::Vector{Float64}=[0.50, 1.0, 3.0],
    survival_pessimism::Float64=1.0,
    verbose::Bool=true,
)
    # Default bequest specs using Lockwood's original DFJ theta (no recalibration)
    if bequest_specs === nothing
        bequest_specs = [
            (name="No bequest",     theta=0.0,    kappa=0.0),
            (name="Moderate (DFJ)", theta=56.96,  kappa=272_628.0),
            (name="Strong bequest",  theta=200.0, kappa=272_628.0),
        ]
    end

    ss_zero(age, p) = 0.0

    grid_kw = (n_wealth=n_wealth, n_annuity=n_annuity, n_alpha=n_alpha,
               W_max=W_max, age_start=age_start, age_end=age_end,
               annuity_grid_power=annuity_grid_power)

    common_kw = (gamma=gamma, beta=beta, r=r,
                 stochastic_health=true, n_health_states=3, n_quad=n_quad,
                 c_floor=c_floor, hazard_mult=hazard_mult,
                 survival_pessimism=survival_pessimism)

    # Payout rates: real (for grid sizing) and nominal (for pricing when inflation active)
    p_fair = ModelParams(; gamma=gamma, beta=beta, r=r, mwr=1.0, grid_kw...)
    fair_pr = compute_payout_rate(p_fair, base_surv)

    # Nominal payout rate (higher initial payout, eroded by inflation)
    p_fair_nom = ModelParams(; gamma=gamma, beta=beta, r=r, mwr=1.0,
                               inflation_rate=inflation_val, grid_kw...)
    fair_pr_nom = inflation_val > 0 ? compute_payout_rate(p_fair_nom, base_surv) : fair_pr

    # Build grids using the LARGER payout rate to cover full A range
    grids = build_grids(p_fair, max(fair_pr, fair_pr_nom))

    # Loaded payout rate: use nominal when inflation active (matches model solve)
    loaded_pr = mwr_loaded * (inflation_val > 0 ? fair_pr_nom : fair_pr)

    n_w = length(wealth_points)
    n_b = length(bequest_specs)
    n_h = 3
    health_names = ["Good", "Fair", "Poor"]

    cev_grid = Array{CEVResult}(undef, n_w, n_b, n_h)
    population_cev = []

    # Ensure population has health column
    pop = copy(population_full)
    if size(pop, 2) < 4
        pop = hcat(pop, fill(2.0, size(pop, 1)))
    end

    for (ib, bspec) in enumerate(bequest_specs)
        if verbose
            @printf("  Solving model: %s (theta=%.1f, kappa=\$%s)...\n",
                bspec.name, bspec.theta, string(round(Int, bspec.kappa)))
        end

        p_model = ModelParams(; common_kw...,
            theta=bspec.theta, kappa=bspec.kappa,
            mwr=mwr_loaded, fixed_cost=fixed_cost_val,
            inflation_rate=inflation_val,
            medical_enabled=true, health_mortality_corr=true,
            grid_kw...)

        t0 = time()
        sol = solve_lifecycle_health(p_model, grids, base_surv, ss_zero)
        solve_time = time() - t0

        if verbose
            @printf("    Solved in %.1fs\n", solve_time)
        end

        # CEV at each grid point
        for ih in 1:n_h
            for iw in 1:n_w
                cev_grid[iw, ib, ih] = compute_cev(
                    sol, wealth_points[iw], y_existing, ih, loaded_pr,
                )
            end
        end

        # Population-level CEV
        pop_result = compute_cev_population(
            sol, pop, loaded_pr; base_surv=base_surv,
        )
        push!(population_cev, (
            name=bspec.name,
            mean_cev=pop_result.mean_cev,
            median_cev=pop_result.median_cev,
            frac_positive=pop_result.frac_positive,
            frac_above_1pct=pop_result.frac_above_1pct,
            results=pop_result.results,
        ))
    end

    return (
        grid=cev_grid,
        wealth_points=wealth_points,
        bequest_names=[b.name for b in bequest_specs],
        health_names=health_names,
        population_cev=population_cev,
    )
end

"""
Compare lifecycle paths with and without optimal annuity purchase.

Simulates n_sim paths under both regimes (same random seeds) and
reports consumption, wealth, and bequest differences.

y_existing: pre-existing annuity income (e.g., from SS). The agent
receives this regardless; the alpha search adds annuity income on top.
"""
function simulate_welfare_comparison(
    sol::HealthSolution,
    W_0::Float64,
    H_0::Int,
    base_surv::Vector{Float64},
    p::ModelParams;
    payout_rate::Float64,
    y_existing::Float64=0.0,
    n_sim::Int=10_000,
    rng_seed::Int=42,
)
    g = sol.grids
    ss_zero(age, p) = 0.0

    # Find optimal alpha (same logic as compute_cev)
    V_t1 = sol.V[:, :, H_0, 1]
    V_interp = linear_interpolation(
        (g.W, g.A), V_t1,
        extrapolation_bc=Interpolations.Flat(),
    )

    W_c = clamp(W_0, g.W[1], g.W[end])
    y_c = clamp(y_existing, g.A[1], g.A[end])

    best_V = V_interp(W_c, y_c)
    best_alpha = 0.0
    for alpha in g.alpha
        alpha <= 0.0 && continue
        is_feasible_purchase(alpha, W_0, p) || continue
        pi = alpha * W_0
        W_rem = W_0 - pi
        if p.fixed_cost > 0.0
            W_rem -= p.fixed_cost
        end
        W_rem < 0.0 && continue
        A_new = pi * payout_rate
        A_total = y_existing + A_new
        W_rc = clamp(W_rem, g.W[1], g.W[end])
        A_tc = clamp(A_total, g.A[1], g.A[end])
        V_val = V_interp(W_rc, A_tc)
        if V_val > best_V
            best_V = V_val
            best_alpha = alpha
        end
    end

    # Simulate WITH optimal annuity
    A_opt = y_existing + best_alpha * W_0 * payout_rate
    W_rem_opt = W_0 * (1.0 - best_alpha)
    if best_alpha > 0.0
        W_rem_opt -= p.fixed_cost
    end
    W_rem_opt = max(W_rem_opt, 0.0)

    batch_with = simulate_batch(
        sol, W_rem_opt, A_opt, H_0, base_surv, ss_zero, p;
        n_sim=n_sim, rng_seed=rng_seed,
    )

    # Simulate WITHOUT annuity (same seed for paired comparison)
    batch_without = simulate_batch(
        sol, W_0, y_existing, H_0, base_surv, ss_zero, p;
        n_sim=n_sim, rng_seed=rng_seed,
    )

    return (
        alpha_star=best_alpha,
        with_annuity=batch_with,
        without_annuity=batch_without,
    )
end
