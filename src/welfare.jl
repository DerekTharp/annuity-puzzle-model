# Consumption-equivalent variation (CEV) welfare calculations.
# CEV = percentage increase in consumption at all dates/states that makes
# the individual indifferent between having and not having annuity access.
#
# For CRRA utility U(c) = c^(1-gamma)/(1-gamma):
#   lambda = (V_with / V_without)^(1/(1-gamma)) - 1
#
# For log utility (gamma == 1), the multiplicative scaling enters additively:
#   V(c*(1+lambda)) = V(c) + log(1+lambda) * D
# where D = sum_t beta^(t-1) * S(t) is the discounted survival horizon. The
# CEV is then lambda = exp((V_with - V_without)/D) - 1, NOT exp(V_with - V_without) - 1.
#
# Positive CEV means the individual benefits from annuity market access.

using Interpolations
using Printf

"""
Discounted survival horizon D = sum_{t=1}^T beta^(t-1) * S(t), where S(t) is
cumulative survival to period t (S(1) = 1 by construction). Used as the
divisor in the log-utility CEV conversion.
"""
function discounted_survival_horizon(beta::Float64, base_surv::Vector{Float64})
    T = length(base_surv)
    D = 1.0  # t=1: alive at start
    cum = 1.0
    for t in 2:T
        cum *= base_surv[t - 1]
        D += beta^(t - 1) * cum
    end
    return D
end

struct CEVResult
    cev::Float64          # consumption-equivalent variation (fraction)
    alpha_star::Float64   # optimal annuity fraction
    V_no_ann::Float64     # value without annuity access
    V_with_ann::Float64   # value with optimal annuity
    excluded::Bool        # true if W_0 outside grid bounds (CEV not estimable)
end

# Backward-compatible constructor — defaults excluded=false.
CEVResult(cev, alpha_star, V_no_ann, V_with_ann) =
    CEVResult(cev, alpha_star, V_no_ann, V_with_ann, false)

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

    # Search over alpha grid for best V with annuity purchase. Apply the
    # behavioral purchase penalty when psi_purchase > 0 — must mirror the
    # solver's treatment in src/solve.jl, otherwise CEV with the behavioral
    # channel active overstates the welfare gain (the agent would not
    # actually choose this alpha given the friction).
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

        # Age-65 purchase: nominal_premium = pi (inflation_factor = 1).
        # Convention matches wtp.jl/welfare.jl elsewhere: pass nominal_premium
        # to purchase_penalty so the dollar amount is unambiguous.
        nominal_premium = pi
        A_new = nominal_premium * payout_rate
        A_total = y_existing + A_new
        W_rc = clamp(W_rem, g.W[1], g.W[end])
        A_tc = clamp(A_total, g.A[1], g.A[end])
        V_val = V_interp(W_rc, A_tc)
        if p.psi_purchase > 0.0
            V_val -= purchase_penalty(nominal_premium, payout_rate, p.gamma,
                p.psi_purchase, p.psi_purchase_c_ref, p.beta, sol.base_surv)
        end
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

    # CRRA value-ratio CEV approximation: lambda = (V_with / V_without)^(1/(1-gamma)) - 1.
    #
    # NOTE: This is an APPROXIMATION when the model includes non-CRRA value
    # contributions — specifically the bequest shifter kappa (V_bequest is
    # CRRA in (b + kappa), not CRRA in c), the consumption floor c_floor (a
    # kink), source-dependent utility (lambda_W reweights consumption by
    # source), and the Force B purchase-event disutility (additive
    # adjustment to V at the purchase moment, not a flow). The exact CEV
    # would solve V_no_access(c * (1 + lambda)) = V_access for lambda. The
    # closed-form ratio is exact only in the pure CRRA + Yaari special case
    # and is reported here as a tractable approximation; see appendix
    # discussion of welfare interpretation. The ranking of CEV across
    # scenarios (and signs) is preserved by the approximation.
    gamma = p.gamma
    if gamma == 1.0
        # Log utility: V(c*(1+lambda)) = V(c) + log(1+lambda) * D where
        # D = sum_t beta^(t-1) * S(t). Solving V(c*(1+lambda)) = V_with for
        # lambda: log(1+lambda) = (V_with - V_no)/D, so lambda = exp(.../D) - 1.
        # The earlier formulation cev = exp(V_with - V_no) - 1 omitted the D
        # divisor and overstated CEV by a factor of D in log-space.
        D = discounted_survival_horizon(p.beta, sol.base_surv)
        cev = exp((V_with_ann - V_no_ann) / D) - 1.0
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

        # Flag agents with wealth outside grid bounds — CEV is not well-defined
        # because boundary extrapolation produces unreliable values.
        if W_0 < 1.0 || W_0 > g.W[end]
            push!(results, CEVResult(0.0, 0.0, 0.0, 0.0, true))
            continue
        end

        t = age - p.age_start + 1
        if t < 1 || t > p.T
            push!(results, CEVResult(0.0, 0.0, 0.0, 0.0, true))
            continue
        end

        # Age-specific payout rate
        if base_surv !== nothing && age > p.age_start
            remaining_T = p.T - t + 1
            r_discount = p.inflation_rate > 0 ? (1 + p.r) * (1 + p.inflation_rate) - 1 : p.r
            pv = 1.0
            for s in 1:(remaining_T - 1)
                cum_s = 1.0
                for k in t:(t + s - 1)
                    k > length(base_surv) && break
                    cum_s *= base_surv[k]
                end
                pv += cum_s / (1.0 + r_discount)^s
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

            # Premium is in real (= age-65 nominal) dollars throughout. The
            # model's A grid is also in age-65 nominal dollars (the Bellman
            # deflates via A_real(s) = A * (1+π)^-(s-1) at each period s),
            # so A_new = pi * payout_rate is on the same scale as y_0 and
            # the V interpolant. Earlier code grossed pi up by (1+π)^(t-1)
            # before multiplying by the payout rate, which silently inflated
            # both A_new and the underwater amount fed to purchase_penalty
            # by (1+π)^(t-1) for any agent observed at age > 65 (the bulk of
            # the HRS sample). The c_ref reference consumption used by the
            # penalty is real, so the inflated nominal premium produced an
            # (1+π)^(t-1) bloat in the loss-aversion utility cost. The fix is
            # to keep everything in real / age-65-nominal terms.
            premium = pi
            A_new = premium * payout_rate
            A_total = y_0 + A_new
            W_rc = clamp(W_rem, g.W[1], g.W[end])
            A_tc = clamp(A_total, g.A[1], g.A[end])
            V_val = V_interp(W_rc, A_tc)
            if p.psi_purchase > 0.0
                # purchase_period=t passes the survival clock starting at the
                # actual purchase age (period t), not period 1. Default
                # purchase_period=1 was wrong for any age-of-purchase > 65.
                V_val -= purchase_penalty(premium, payout_rate, p.gamma,
                    p.psi_purchase, p.psi_purchase_c_ref, p.beta, sol.base_surv;
                    purchase_period=t)
            end
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
            # See note in compute_cev: log-utility CEV requires the discounted
            # survival horizon as divisor.
            D = discounted_survival_horizon(p.beta, base_surv === nothing ? sol.base_surv : base_surv)
            cev = exp((best_V - V_no_ann) / D) - 1.0
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

    # Summary statistics — exclude out-of-grid agents from aggregates so they
    # don't bias mean/median downward toward zero. Report n_excluded separately
    # so the manuscript can flag the small affected subpopulation.
    n_excluded = count(r -> r.excluded, results)
    included = [r.cev for r in results if !r.excluded]
    mean_cev = length(included) > 0 ? sum(included) / length(included) : 0.0
    sorted = sort(included)
    median_cev = length(sorted) > 0 ? sorted[div(length(sorted) + 1, 2)] : 0.0
    frac_positive = count(c -> c > 0.0, included) / max(length(included), 1)
    frac_above_1pct = count(c -> c > 0.01, included) / max(length(included), 1)

    return (
        results=results,
        mean_cev=mean_cev,
        median_cev=median_cev,
        frac_positive=frac_positive,
        frac_above_1pct=frac_above_1pct,
        n_total=n_individuals,
        n_excluded=n_excluded,
        n_included=n_individuals - n_excluded,
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
    min_purchase_val::Float64=0.0,
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
    consumption_decline::Float64=0.0,
    health_utility::Vector{Float64}=[1.0, 1.0, 1.0],
    psi_purchase::Float64=0.0,
    psi_purchase_c_ref::Float64=18_000.0,
    lambda_w::Float64=1.0,
    chi_ltc::Float64=1.0,
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

    # SS function for the welfare model. The production decomposition solves
    # per quartile and aggregates; here we solve once with a representative
    # level (median across quartiles, $18,500). This aligns the welfare CEV's
    # baseline with production rather than treating retirees as having zero
    # SS, which previously inflated the marginal value of annuitization. A
    # per-quartile dispatch is left as a future tightening.
    ss_func_welfare(age, p) = 18_500.0

    grid_kw = (n_wealth=n_wealth, n_annuity=n_annuity, n_alpha=n_alpha,
               W_max=W_max, age_start=age_start, age_end=age_end,
               annuity_grid_power=annuity_grid_power)

    # Common keyword args: include preference + behavioral channels so the
    # CEV computation uses the same model the production solve uses. Without
    # these the CEV table would silently report six-channel values while
    # the rest of the pipeline is ten-channel.
    common_kw = (gamma=gamma, beta=beta, r=r,
                 stochastic_health=true, n_health_states=3, n_quad=n_quad,
                 c_floor=c_floor, hazard_mult=hazard_mult,
                 survival_pessimism=survival_pessimism,
                 consumption_decline=consumption_decline,
                 health_utility=health_utility,
                 psi_purchase=psi_purchase,
                 psi_purchase_c_ref=psi_purchase_c_ref)

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
            mwr=mwr_loaded, fixed_cost=fixed_cost_val, min_purchase=min_purchase_val,
            lambda_w=lambda_w,
            chi_ltc=chi_ltc,
            inflation_rate=inflation_val,
            medical_enabled=true, health_mortality_corr=true,
            grid_kw...)

        t0 = time()
        sol = solve_lifecycle_health(p_model, grids, base_surv, ss_func_welfare)
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
            n_total=pop_result.n_total,
            n_excluded=pop_result.n_excluded,
            n_included=pop_result.n_included,
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
    # Match the SS function used by compute_cev_grid for internal consistency.
    ss_func_welfare(age, p) = 18_500.0

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
        # Age-65 purchase: nominal_premium = pi (inflation_factor = 1).
        nominal_premium = pi
        A_new = nominal_premium * payout_rate
        A_total = y_existing + A_new
        W_rc = clamp(W_rem, g.W[1], g.W[end])
        A_tc = clamp(A_total, g.A[1], g.A[end])
        V_val = V_interp(W_rc, A_tc)
        if p.psi_purchase > 0.0
            V_val -= purchase_penalty(nominal_premium, payout_rate, p.gamma,
                p.psi_purchase, p.psi_purchase_c_ref, p.beta, sol.base_surv)
        end
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
        sol, W_rem_opt, A_opt, H_0, base_surv, ss_func_welfare, p;
        n_sim=n_sim, rng_seed=rng_seed,
    )

    # Simulate WITHOUT annuity (same seed for paired comparison)
    batch_without = simulate_batch(
        sol, W_0, y_existing, H_0, base_surv, ss_func_welfare, p;
        n_sim=n_sim, rng_seed=rng_seed,
    )

    return (
        alpha_star=best_alpha,
        with_annuity=batch_with,
        without_annuity=batch_without,
    )
end
