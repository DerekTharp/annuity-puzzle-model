# Willingness-to-pay (WTP) and annuity demand computations.
# Implements Lockwood (2012) WTP methodology:
#   WTP = fraction of non-annuity wealth agent would pay to access annuity markets.

using Interpolations

"""
Compute WTP for annuity market access at each wealth level.

WTP(W_0) = (W_0 - W*) / W_0
where W* is the wealth that, WITH optimal annuity access, yields the same
utility as W_0 WITHOUT annuity access.

`A_existing`: pre-existing annuity income (e.g., from Social Security or prior purchases).
If 0, the agent has no pre-existing annuity income.

Returns a vector of WTP values, one per wealth grid point.
"""
function compute_wtp(sol::Solution, payout_rate::Float64; A_existing::Float64=0.0)
    p = sol.params
    g = sol.grids
    nW = length(g.W)

    # 2D interpolation of V(W, A, t=1)
    V_t1 = sol.V[:, :, 1]
    V_interp = linear_interpolation(
        (g.W, g.A), V_t1,
        extrapolation_bc=Interpolations.Flat(),
    )

    # Clamp A_existing to grid
    A_exist_c = clamp(A_existing, g.A[1], g.A[end])

    wtp = Vector{Float64}(undef, nW)
    for iw in 1:nW
        W_0 = g.W[iw]

        if W_0 < 1.0
            wtp[iw] = 0.0
            continue
        end

        # V without additional annuities: V(W_0, A_existing, t=1)
        V_no_ann = V_interp(W_0, A_exist_c)

        # V with optimal annuitization of W_0 (on top of A_existing)
        best_V = V_no_ann
        for alpha in g.alpha
            alpha <= 0.0 && continue
            is_feasible_purchase(alpha, W_0, p) || continue
            A_new = alpha * W_0 * payout_rate
            W_rem = (1.0 - alpha) * W_0
            if alpha > 0.0 && p.fixed_cost > 0.0
                W_rem -= p.fixed_cost
            end
            W_rem < 0.0 && continue

            A_total = A_existing + A_new
            W_c = clamp(W_rem, g.W[1], g.W[end])
            A_c = clamp(A_total, g.A[1], g.A[end])
            V_val = V_interp(W_c, A_c)
            if V_val > best_V
                best_V = V_val
            end
        end

        # No gain from annuities
        if best_V <= V_no_ann + 1e-12
            wtp[iw] = 0.0
            continue
        end

        # Find W* such that V_with_ann(W*) = V_no_ann
        # V_with_ann(W) = max_alpha V((1-alpha)*W, A_exist + alpha*W*pr, t=1)
        # Use bisection on W
        W_lo = 0.0
        W_hi = W_0

        # Check boundary: if V_with_ann(0) >= V_no_ann, WTP = 100%
        V_ann_at_zero = V_interp(0.0, A_exist_c)  # no wealth, no new annuity
        if V_ann_at_zero >= V_no_ann
            wtp[iw] = 1.0
            continue
        end

        for _ in 1:100
            W_mid = (W_lo + W_hi) / 2.0

            # Compute V_with_ann(W_mid)
            V_best_mid = V_interp(W_mid, A_exist_c)  # alpha=0
            for alpha in g.alpha
                alpha <= 0.0 && continue
                is_feasible_purchase(alpha, W_mid, p) || continue
                A_new = alpha * W_mid * payout_rate
                W_rem = (1.0 - alpha) * W_mid
                if alpha > 0.0 && p.fixed_cost > 0.0
                    W_rem -= p.fixed_cost
                end
                W_rem < 0.0 && continue

                A_total = A_existing + A_new
                W_c = clamp(W_rem, g.W[1], g.W[end])
                A_c = clamp(A_total, g.A[1], g.A[end])
                V_val = V_interp(W_c, A_c)
                if V_val > V_best_mid
                    V_best_mid = V_val
                end
            end

            if V_best_mid < V_no_ann
                W_lo = W_mid
            else
                W_hi = W_mid
            end
            if (W_hi - W_lo) < 1e-6 * W_0
                break
            end
        end

        W_star = (W_lo + W_hi) / 2.0
        wtp[iw] = (W_0 - W_star) / W_0
        wtp[iw] = clamp(wtp[iw], 0.0, 1.0)
    end

    return wtp
end

"""
Compute WTP for a specific (N_ref, y_ref) pair, matching Lockwood's setup.

- N_ref: non-annuity (liquid) wealth
- y_ref: pre-existing annuity income per year
- sol: lifecycle solution on the full grid
- payout_rate: fair payout rate

Returns WTP as a fraction of N_ref.
"""
function compute_wtp_lockwood(
    N_ref::Float64,
    y_ref::Float64,
    sol::Solution,
    payout_rate::Float64,
)
    p = sol.params
    g = sol.grids

    V_t1 = sol.V[:, :, 1]
    V_interp = linear_interpolation(
        (g.W, g.A), V_t1,
        extrapolation_bc=Interpolations.Flat(),
    )

    N_c = clamp(N_ref, g.W[1], g.W[end])
    y_c = clamp(y_ref, g.A[1], g.A[end])

    # V without additional annuity purchase
    V_no_ann = V_interp(N_c, y_c)

    # V with optimal annuitization of N_ref
    best_V = V_no_ann
    best_alpha = 0.0
    for alpha in g.alpha
        alpha <= 0.0 && continue
        is_feasible_purchase(alpha, N_ref, p) || continue
        pi = alpha * N_ref  # premium
        W_rem = N_ref - pi
        if alpha > 0.0 && p.fixed_cost > 0.0
            W_rem -= p.fixed_cost
        end
        W_rem < 0.0 && continue

        A_new = pi * payout_rate  # fair pricing: MWR already in payout_rate
        A_total = y_ref + A_new
        W_c = clamp(W_rem, g.W[1], g.W[end])
        A_c = clamp(A_total, g.A[1], g.A[end])
        V_val = V_interp(W_c, A_c)
        if V_val > best_V
            best_V = V_val
            best_alpha = alpha
        end
    end

    if best_V <= V_no_ann + 1e-12
        return (wtp=0.0, alpha_star=0.0, V_no_ann=V_no_ann, V_ann=V_no_ann)
    end

    # Bisection: find N* such that V_with_ann(N*) = V_no_ann
    N_lo = 0.0
    N_hi = N_ref

    # Check if V_with_ann(0) already exceeds V_no_ann
    # (only if y_ref alone provides enough)
    V_at_zero = V_interp(0.0, y_c)
    if V_at_zero >= V_no_ann
        return (wtp=1.0, alpha_star=best_alpha, V_no_ann=V_no_ann, V_ann=best_V)
    end

    for _ in 1:100
        N_mid = (N_lo + N_hi) / 2.0

        # Optimal annuitization at N_mid
        V_best_mid = V_interp(clamp(N_mid, g.W[1], g.W[end]), y_c)
        for alpha in g.alpha
            alpha <= 0.0 && continue
            is_feasible_purchase(alpha, N_mid, p) || continue
            pi = alpha * N_mid
            W_rem = N_mid - pi
            if alpha > 0.0 && p.fixed_cost > 0.0
                W_rem -= p.fixed_cost
            end
            W_rem < 0.0 && continue

            A_new = pi * payout_rate
            A_total = y_ref + A_new
            W_c = clamp(W_rem, g.W[1], g.W[end])
            A_c = clamp(A_total, g.A[1], g.A[end])
            V_val = V_interp(W_c, A_c)
            if V_val > V_best_mid
                V_best_mid = V_val
            end
        end

        if V_best_mid < V_no_ann
            N_lo = N_mid
        else
            N_hi = N_mid
        end
        if (N_hi - N_lo) < 1.0  # $1 precision
            break
        end
    end

    N_star = (N_lo + N_hi) / 2.0
    wtp_val = (N_ref - N_star) / N_ref
    return (wtp=clamp(wtp_val, 0.0, 1.0), alpha_star=best_alpha,
            V_no_ann=V_no_ann, V_ann=best_V)
end

"""
Recalibrate DFJ bequest theta for a different gamma (risk aversion).

DFJ theta was estimated at gamma_ref (Lockwood sigma=2). The FOC at the
optimal bequest gives theta = ((b+kappa)/c)^gamma, so matching the same
optimal allocation at a new gamma requires:

    theta_new = theta_ref^(gamma_new / gamma_ref)

This preserves the marginal rate of substitution between consumption and
bequests at the optimum. At gamma_ref, returns theta_ref unchanged.
"""
function recalibrate_theta_dfj(theta_ref::Float64, gamma_new::Float64;
                                gamma_ref::Float64=2.0)
    gamma_new == gamma_ref && return theta_ref
    return theta_ref^(gamma_new / gamma_ref)
end

"""
Calibrate bequest intensity theta from a target bequest-to-wealth ratio.

From Lockwood (BAP_wtp.m line 206):
  theta = (b*/c*)^sigma
where b* = b_star_over_N * N and c* = (N - b*) / p_unit_ann.
"""
function calibrate_theta(
    b_star_over_N::Float64,
    W_0::Float64,
    payout_rate::Float64,
    p::ModelParams,
)
    N = W_0
    b_star = b_star_over_N * N

    # Present value of fair annuity = 1/payout_rate
    p_unit_ann = 1.0 / payout_rate

    # Fair annuity budget constraint: N = p_ann * c* + b*
    # (with PV bequest preferences, p_unit_b = 1)
    c_star = (N - b_star) / p_unit_ann
    c_star = max(c_star, 0.01)

    # From BAP_wtp.m: theta = (b*/c*)^sigma
    theta = (b_star / c_star)^p.gamma

    return theta
end

"""
Compute annuity ownership rate from a population of individuals.

For each individual (wealth, income, age), finds optimal annuity purchase
and counts as "owner" if optimal purchase > 0.

`population` is a matrix where each row is [wealth, income] or [wealth, income, age].
If age is provided, the annuitization decision uses V at the individual's age.
The payout rate is also age-adjusted when ages are provided.
"""
function compute_ownership_rate(
    sol::Solution,
    population::Matrix{Float64},
    payout_rate_age65::Float64;
    surv::Union{Vector{Float64}, Nothing}=nothing,
)
    p = sol.params
    g = sol.grids
    n_individuals = size(population, 1)
    has_age = size(population, 2) >= 3
    n_owners = 0
    n_evaluated = 0

    # Precompute interpolation objects keyed by time period
    interp_cache = Dict{Int, typeof(linear_interpolation(
        (g.W, g.A), sol.V[:, :, 1],
        extrapolation_bc=Interpolations.Flat(),
    ))}()

    n_above_grid = 0
    for i in 1:n_individuals
        raw_W = population[i, 1]
        # Skip agents above grid max (extrapolation unreliable)
        if raw_W > g.W[end]
            n_above_grid += 1
            continue
        end
        W_0 = max(raw_W, 0.0)
        y_0 = clamp(population[i, 2], g.A[1], g.A[end])
        age = has_age ? Int(population[i, 3]) : p.age_start

        W_0 < 1.0 && continue

        # Time period for this individual's age
        t = age - p.age_start + 1
        t < 1 && continue
        t > p.T && continue

        n_evaluated += 1

        # Age-specific payout rate (older => fewer expected payments => higher rate)
        if surv !== nothing && age > p.age_start
            r_discount = p.inflation_rate > 0 ? (1 + p.r) * (1 + p.inflation_rate) - 1 : p.r
            remaining_T = p.T - t + 1
            pv = 1.0
            for s in 1:(remaining_T - 1)
                cum_s = 1.0
                for k in t:(t + s - 1)
                    k > length(surv) && break
                    cum_s *= surv[k]
                end
                pv += cum_s / (1.0 + r_discount)^s
            end
            payout_rate = p.mwr / pv
        else
            payout_rate = payout_rate_age65
        end

        # Use cached interpolation for this time period
        V_interp = get!(interp_cache, t) do
            linear_interpolation(
                (g.W, g.A), sol.V[:, :, t],
                extrapolation_bc=Interpolations.Flat(),
            )
        end

        V_no_ann = V_interp(W_0, y_0)
        best_V = V_no_ann
        best_pi = 0.0

        for alpha in g.alpha
            alpha <= 0.0 && continue
            is_feasible_purchase(alpha, W_0, p) || continue
            pi = alpha * W_0
            W_rem = W_0 - pi
            if p.fixed_cost > 0.0
                W_rem -= p.fixed_cost
            end
            W_rem < 0.0 && continue

            # Convert real premium pi (age-65 dollars) to nominal at purchase
            # age. A_state stores the constant nominal annual payment; the
            # Bellman deflates via A_real(t) = A * (1+π)^-(t-1).
            inflation_factor = (1.0 + p.inflation_rate)^(t - 1)
            nominal_premium = pi * inflation_factor
            A_new = nominal_premium * payout_rate
            A_total = y_0 + A_new
            W_c = clamp(W_rem, g.W[1], g.W[end])
            A_c = clamp(A_total, g.A[1], g.A[end])
            V_val = V_interp(W_c, A_c)
            if V_val > best_V
                best_V = V_val
                best_pi = pi
            end
        end

        if best_pi > 0.0
            n_owners += 1
        end
    end

    return n_evaluated > 0 ? n_owners / n_evaluated : 0.0
end


# ===================================================================
# Phase 3: Health-Aware WTP and Ownership
# ===================================================================

"""
Compute WTP for annuity market access with health states (Phase 3).

For a given initial health state, computes the fraction of non-annuity
wealth the agent would pay to access annuity markets.

Arguments:
- N_ref: non-annuity (liquid) wealth
- y_ref: pre-existing annuity income per year
- sol: HealthSolution from solve_lifecycle_health
- payout_rate: annuity payout rate
- initial_health: 1=Good, 2=Fair, 3=Poor (default: 2=Fair)
"""
function compute_wtp_health(
    N_ref::Float64,
    y_ref::Float64,
    sol::HealthSolution,
    payout_rate::Float64;
    initial_health::Int=2,
)
    p = sol.params
    g = sol.grids

    V_t1 = sol.V[:, :, initial_health, 1]
    V_interp = linear_interpolation(
        (g.W, g.A), V_t1,
        extrapolation_bc=Interpolations.Flat(),
    )

    N_c = clamp(N_ref, g.W[1], g.W[end])
    y_c = clamp(y_ref, g.A[1], g.A[end])

    # V without additional annuity purchase
    V_no_ann = V_interp(N_c, y_c)

    # V with optimal annuitization of N_ref
    best_V = V_no_ann
    best_alpha = 0.0
    for alpha in g.alpha
        alpha <= 0.0 && continue
        is_feasible_purchase(alpha, N_ref, p) || continue
        pi = alpha * N_ref
        W_rem = N_ref - pi
        if alpha > 0.0 && p.fixed_cost > 0.0
            W_rem -= p.fixed_cost
        end
        W_rem < 0.0 && continue

        A_new = pi * payout_rate
        A_total = y_ref + A_new
        W_c = clamp(W_rem, g.W[1], g.W[end])
        A_c = clamp(A_total, g.A[1], g.A[end])
        V_val = V_interp(W_c, A_c)
        if V_val > best_V
            best_V = V_val
            best_alpha = alpha
        end
    end

    if best_V <= V_no_ann + 1e-12
        return (wtp=0.0, alpha_star=0.0, V_no_ann=V_no_ann, V_ann=V_no_ann)
    end

    # Bisection: find N* such that V_with_ann(N*) = V_no_ann
    N_lo = 0.0
    N_hi = N_ref

    V_at_zero = V_interp(0.0, y_c)
    if V_at_zero >= V_no_ann
        return (wtp=1.0, alpha_star=best_alpha, V_no_ann=V_no_ann, V_ann=best_V)
    end

    for _ in 1:100
        N_mid = (N_lo + N_hi) / 2.0

        V_best_mid = V_interp(clamp(N_mid, g.W[1], g.W[end]), y_c)
        for alpha in g.alpha
            alpha <= 0.0 && continue
            is_feasible_purchase(alpha, N_mid, p) || continue
            pi = alpha * N_mid
            W_rem = N_mid - pi
            if alpha > 0.0 && p.fixed_cost > 0.0
                W_rem -= p.fixed_cost
            end
            W_rem < 0.0 && continue

            A_new = pi * payout_rate
            A_total = y_ref + A_new
            W_c = clamp(W_rem, g.W[1], g.W[end])
            A_c = clamp(A_total, g.A[1], g.A[end])
            V_val = V_interp(W_c, A_c)
            if V_val > V_best_mid
                V_best_mid = V_val
            end
        end

        if V_best_mid < V_no_ann
            N_lo = N_mid
        else
            N_hi = N_mid
        end
        if (N_hi - N_lo) < 1.0
            break
        end
    end

    N_star = (N_lo + N_hi) / 2.0
    wtp_val = (N_ref - N_star) / N_ref
    return (wtp=clamp(wtp_val, 0.0, 1.0), alpha_star=best_alpha,
            V_no_ann=V_no_ann, V_ann=best_V)
end

"""
Compute annuity ownership rate with health states (Phase 3).

For each individual, uses the value function at their health state
to determine if annuity purchase is optimal.

`population` columns: [wealth, income, age, health_state].
If health_state column is missing, defaults to Fair (2).

Optional `weights` vector: if provided, computes weighted ownership rate
using HRS survey weights (one weight per row of `population`).
"""
function compute_ownership_rate_health(
    sol::HealthSolution,
    population::Matrix{Float64},
    payout_rate_age65::Float64;
    base_surv::Union{Vector{Float64}, Nothing}=nothing,
    weights::Union{Vector{Float64}, Nothing}=nothing,
)
    p = sol.params
    g = sol.grids
    n_individuals = size(population, 1)
    has_age = size(population, 2) >= 3
    has_health = size(population, 2) >= 4
    n_owners = 0.0
    n_evaluated = 0.0
    sum_alpha = 0.0

    # Precompute interpolation objects keyed by (health, time)
    interp_cache = Dict{Tuple{Int,Int}, typeof(linear_interpolation(
        (g.W, g.A), sol.V[:, :, 1, 1],
        extrapolation_bc=Interpolations.Flat(),
    ))}()

    n_above_grid = 0
    for i in 1:n_individuals
        raw_W = population[i, 1]
        # Skip agents above grid max (extrapolation unreliable)
        if raw_W > g.W[end]
            n_above_grid += 1
            continue
        end
        W_0 = max(raw_W, 0.0)
        y_0 = clamp(population[i, 2], g.A[1], g.A[end])
        age = has_age ? Int(population[i, 3]) : p.age_start
        ih = has_health ? Int(population[i, 4]) : 2  # default Fair

        W_0 < 1.0 && continue

        t = age - p.age_start + 1
        t < 1 && continue
        t > p.T && continue

        w_i = weights !== nothing ? weights[i] : 1.0
        n_evaluated += w_i

        # Age-specific payout rate
        if base_surv !== nothing && age > p.age_start
            r_discount = p.inflation_rate > 0 ? (1 + p.r) * (1 + p.inflation_rate) - 1 : p.r
            remaining_T = p.T - t + 1
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

        V_no_ann = V_interp(W_0, y_0)
        best_V = V_no_ann
        best_pi = 0.0

        for alpha in g.alpha
            alpha <= 0.0 && continue
            is_feasible_purchase(alpha, W_0, p) || continue
            pi = alpha * W_0
            W_rem = W_0 - pi
            if p.fixed_cost > 0.0
                W_rem -= p.fixed_cost
            end
            W_rem < 0.0 && continue

            # Convert the real premium pi (in age-65 dollars) to a nominal
            # premium at the purchase age. compute_payout_rate returns nominal
            # payment per nominal premium, so we need a nominal-units bridge.
            inflation_factor = (1.0 + p.inflation_rate)^(t - 1)
            nominal_premium = pi * inflation_factor
            # A_state stores the constant nominal annuity payment. The Bellman
            # then converts to age-65 real dollars via A_real(t) = A * (1+π)^-(t-1).
            A_new = nominal_premium * payout_rate
            A_total = y_0 + A_new
            W_c = clamp(W_rem, g.W[1], g.W[end])
            A_c = clamp(A_total, g.A[1], g.A[end])
            V_val = V_interp(W_c, A_c)
            # Narrow-framing purchase penalty NPV: the agent's mental accounting
            # tracks nominal cumulative receipts vs nominal premium, so pass
            # the nominal premium (not the real one). purchase_period=t slices
            # the survival schedule conditional on being alive at the purchase
            # age (default purchase_period=1 was wrong for any age > 65).
            if p.psi_purchase > 0.0
                V_val -= purchase_penalty(nominal_premium, payout_rate, p.gamma,
                    p.psi_purchase, p.psi_purchase_c_ref, p.beta, sol.base_surv;
                    purchase_period=t)
            end
            if V_val > best_V
                best_V = V_val
                best_pi = pi
            end
        end

        best_alpha_i = W_0 > 0.0 ? best_pi / W_0 : 0.0
        sum_alpha += w_i * best_alpha_i
        if best_pi > 0.0
            n_owners += w_i
        end
    end

    if n_evaluated > 0.0
        return (ownership_rate = n_owners / n_evaluated,
                mean_alpha = sum_alpha / n_evaluated,
                n_above_grid = n_above_grid,
                n_evaluated = Int(round(n_evaluated)))
    else
        return (ownership_rate = 0.0, mean_alpha = 0.0,
                n_above_grid = n_above_grid,
                n_evaluated = 0)
    end
end
