# =============================================================================
# 05_solver.jl — Dynamic programming solver and simulation engine.
#
# This file consolidates:
#   src/bellman.jl       one-period Bellman equation
#   src/solve.jl         backward induction + age-65 annuitization decision
#   src/simulation.jl    Monte Carlo lifecycle simulation (per-period re-optimization)
#   src/diagnostics.jl   Euler residuals, value-function diagnostics
# =============================================================================

#=============================================================================
# ORIGINAL FILE: src/bellman.jl
#=============================================================================

# Bellman equation for the lifecycle annuitization model.
# Phase 1: no health states, no medical expenditure shocks.
#
# V(W, A, t) = max_c { U(c) + β s(t) V(W', A, t+1)
#                       + β (1-s(t)) V_bequest(W') }
#
# W' = (1+r)(W + A + SS(t) - c)
# c ∈ [c_floor, W + A + SS(t)]
#
# Safety net: if W + A + SS < c_floor, government covers shortfall.
# Agent consumes c_floor and saves nothing. This prevents -Inf utility
# propagation at zero-resource states.

using Interpolations
using Optim

"""
Solve the one-period consumption problem at state (W, A, t).
Returns (V_opt, c_opt).

`V_next_interp` is an interpolation object over the wealth grid
for the value function at t+1 (given A fixed as a state variable).
"""
function solve_consumption(
    W::Float64,          # current liquid wealth
    A::Float64,          # annuity income (fixed)
    ss::Float64,         # Social Security income this period
    V_next_interp,       # interpolated V(W', t+1) for this A level
    surv::Float64,       # survival probability s(t)
    p::ModelParams,
    t::Int,              # period index (1 = age 65)
    ih::Int=2,           # health state (1=Good, 2=Fair, 3=Poor); default Fair
)
    cash = W + A + ss  # total resources available
    inc  = A + ss      # income flow (annuity + Social Security); SDU treats
                        # consumption up to `inc` as income-financed and
                        # anything beyond as portfolio-financed.

    # Safety net: if resources below c_floor, government covers shortfall.
    # Agent consumes c_floor and saves nothing.
    if cash < p.c_floor
        c_star = p.c_floor
        W_next = 0.0
        V_flow = flow_utility_sdu(c_star, inc, p.gamma, t, ih, p)
        V_cont = surv * V_next_interp(W_next)
        V_beq = (1.0 - surv) * bequest_utility(W_next, p.gamma, p.theta, p.kappa)
        return (V_flow + p.beta * (V_cont + V_beq), c_star)
    end

    c_min = p.c_floor
    c_max = cash

    if c_max <= c_min + 1e-10
        # Corner: only option is c_floor (or all resources if barely above)
        c_star = cash
        W_next = 0.0
        V_flow = flow_utility_sdu(c_star, inc, p.gamma, t, ih, p)
        V_cont = surv * V_next_interp(W_next)
        V_beq = (1.0 - surv) * bequest_utility(W_next, p.gamma, p.theta, p.kappa)
        return (V_flow + p.beta * (V_cont + V_beq), c_star)
    end

    # Objective: maximize U(c) + β [s V(W') + (1-s) V_bequest(W')]
    # W' = (1+r)(cash - c)
    # Note: under SDU (lambda_w<1), period utility has a kink at c=inc where
    # marginal utility drops from u'(c_eff)·1 to u'(c_eff)·lambda_w. Brent's
    # method handles this fine — the function is concave on either side and
    # the kink is interior to [c_min, c_max].
    function neg_value(c::Float64)
        W_next = (1.0 + p.r) * (cash - c)
        W_next = max(W_next, 0.0)
        V_flow = flow_utility_sdu(c, inc, p.gamma, t, ih, p)
        V_cont = surv * V_next_interp(W_next)
        V_beq = (1.0 - surv) * bequest_utility(W_next, p.gamma, p.theta, p.kappa)
        return -(V_flow + p.beta * (V_cont + V_beq))
    end

    # Brent's method on [c_min, c_max]
    result = optimize(neg_value, c_min, c_max, Brent())
    c_star = Optim.minimizer(result)
    V_opt = -Optim.minimum(result)

    return (V_opt, c_star)
end

"""
Terminal value at age T (age_end).
s(T) = 0, so no continuation value. The agent splits resources between
consumption and bequest.

V(W, A, T) = max_c { U(c) + β * V_bequest(cash - c) }

With θ = 0: consume everything.
With θ > 0: interior solution splitting consumption and bequest.
"""
function terminal_value(
    W::Float64,
    A::Float64,
    ss::Float64,
    p::ModelParams,
    t::Int=36,           # period index (default T=36 for age 100)
    ih::Int=2,           # health state (default Fair)
)
    cash = W + A + ss
    inc  = A + ss

    # Safety net at terminal period
    if cash < p.c_floor
        cash = p.c_floor
    end

    if p.theta == 0.0
        # No bequest motive: consume everything
        return (flow_utility_sdu(cash, inc, p.gamma, t, ih, p), cash)
    end

    # With bequests: split between consumption and bequest
    c_min = p.c_floor
    c_max = cash

    if c_max <= c_min + 1e-10
        return (flow_utility_sdu(cash, inc, p.gamma, t, ih, p) + p.beta * bequest_utility(0.0, p.gamma, p.theta, p.kappa), cash)
    end

    function neg_val(c::Float64)
        leftover = cash - c
        return -(flow_utility_sdu(c, inc, p.gamma, t, ih, p) + p.beta * bequest_utility(leftover, p.gamma, p.theta, p.kappa))
    end

    result = optimize(neg_val, c_min, c_max, Brent())
    c_star = Optim.minimizer(result)
    V_opt = -Optim.minimum(result)

    return (V_opt, c_star)
end

#=============================================================================
# ORIGINAL FILE: src/solve.jl
#=============================================================================

# Full backward induction solver for the lifecycle model.
# Solves V(W, A, t) for t = T down to 1 (age 65).
# Phase 1: no health dimension.
# Phase 3: V(W, A, H, t) with 3-state health, medical expenses, GH quadrature.

using Interpolations

"""
Container for the solution: value and policy functions on the grid.
Phase 1/2: no health dimension.
"""
struct Solution
    V::Array{Float64, 3}       # V[w, a, t]: value function
    c_policy::Array{Float64, 3} # c[w, a, t]: optimal consumption
    grids::Grids
    params::ModelParams
    base_surv::Vector{Float64}  # period-survival hazards (kept for narrow-framing
                                 # NPV calculation at the age-65 alpha search)
end

"""
Container for the health-aware solution: value and policy functions.
Phase 3: 3-state health dimension added.
"""
struct HealthSolution
    V::Array{Float64, 4}        # V[w, a, h, t]: value function
    c_policy::Array{Float64, 4} # c[w, a, h, t]: optimal consumption
    grids::Grids
    params::ModelParams
    base_surv::Vector{Float64}  # period-survival hazards (kept for narrow-framing
                                 # NPV calculation at the age-65 alpha search)
end

"""
Solve the lifecycle problem by backward induction (Phase 1/2, no health).
Returns a Solution struct with value and policy functions.

`ss_func(age, p)` returns Social Security income at age `age`.
"""
function solve_lifecycle(
    p::ModelParams,
    grids::Grids,
    surv::Vector{Float64},
    ss_func::Function,
)
    nW = length(grids.W)
    nA = length(grids.A)
    T = p.T

    V = fill(-Inf, nW, nA, T)
    c_policy = fill(0.0, nW, nA, T)

    # --- Terminal period (t = T, age = age_end) ---
    for ia in 1:nA
        A_val = grids.A[ia]
        A_real = annuity_income_real(A_val, T, p)
        ss_val = ss_func(p.age_end, p)
        for iw in 1:nW
            W_val = grids.W[iw]
            (V[iw, ia, T], c_policy[iw, ia, T]) = terminal_value(W_val, A_real, ss_val, p, T)
        end
    end

    # --- Backward induction: t = T-1 down to 1 ---
    for t in (T-1):-1:1
        age = p.age_start + t - 1
        s_t = surv[t]
        ss_val = ss_func(age, p)

        Threads.@threads for ia in 1:nA
            A_val = grids.A[ia]
            A_real = annuity_income_real(A_val, t, p)

            # Build interpolation of V(W', A, t+1) over wealth grid
            V_next_vals = V[:, ia, t + 1]
            V_next_interp = linear_interpolation(
                grids.W, V_next_vals,
                extrapolation_bc=Interpolations.Flat(),
            )

            for iw in 1:nW
                W_val = grids.W[iw]
                (V[iw, ia, t], c_policy[iw, ia, t]) = solve_consumption(
                    W_val, A_real, ss_val, V_next_interp, s_t, p, t,
                )
            end
        end
    end

    return Solution(V, c_policy, grids, p, surv)
end

"""
Solve the lifecycle problem with stochastic health (Phase 3).

State space: V(W, A, H, t) where H ∈ {1=Good, 2=Fair, 3=Poor}.

The Bellman equation with health:
  V(W, A, H, t) = E_m[ max_c { U(c) + β s(t,H) Σ_{H'} π(H,H',t) V(W',A,H',t+1)
                                 + β (1-s(t,H)) V_bequest(W') } ]
where:
  - W' = (1+r)(W + A + SS - m - c)
  - m is the medical expense shock (lognormal, integrated via GH quadrature)
  - π(H,H',t) is the health transition matrix
  - s(t,H) is the health-dependent survival probability

When medical_enabled=false, m=0 (no medical expense shocks).
When health_mortality_corr=false, s(t,H)=s(t) for all H.
"""
function solve_lifecycle_health(
    p::ModelParams,
    grids::Grids,
    base_surv::Vector{Float64},
    ss_func::Function,
)
    nW = length(grids.W)
    nA = length(grids.A)
    nH = 3
    T = p.T

    V = fill(-Inf, nW, nA, nH, T)
    c_policy = fill(0.0, nW, nA, nH, T)

    # Precompute health-dependent survival
    surv_health = build_health_survival(base_surv, p)

    # Precompute health transition matrices for all ages
    health_trans = build_all_health_transitions(p)

    # Gauss-Hermite nodes and weights for medical expense integration
    gh_nodes, gh_weights = gauss_hermite_normal(p.n_quad)

    # --- Terminal period (t = T, age = age_end) ---
    # At terminal period, s(T) = 0 for all health states (certain death).
    # V(W, A, H, T) = E_m[ terminal_value(cash_after_medical) ]
    # Health state affects terminal value only through medical expenses.
    for ih in 1:nH
        for ia in 1:nA
            A_val = grids.A[ia]
            A_real = annuity_income_real(A_val, T, p)
            ss_val = ss_func(p.age_end, p)
            for iw in 1:nW
                W_val = grids.W[iw]
                cash_before = W_val + A_real + ss_val

                if p.medical_enabled
                    # Source-aware accounting for SDU at terminal period
                    # (see backward-induction block below for full rationale).
                    mu_m, sigma_m = medical_expense_params(p.age_end, ih, p)
                    inc_gross = ss_val + A_real
                    V_total = 0.0
                    c_total = 0.0
                    for iq in 1:p.n_quad
                        m = exp(mu_m + sigma_m * gh_nodes[iq])
                        inc_after  = max(0.0, inc_gross - m)
                        port_drain = max(0.0, m - inc_gross)
                        W_after    = max(W_val - port_drain, 0.0)
                        if inc_after + W_after < p.c_floor
                            inc_after = p.c_floor - W_after
                        end
                        V_k, c_k = terminal_value(W_after, 0.0, inc_after, p, T, ih)
                        V_total += gh_weights[iq] * V_k
                        c_total += gh_weights[iq] * c_k
                    end
                    V[iw, ia, ih, T] = V_total
                    c_policy[iw, ia, ih, T] = c_total
                else
                    (V[iw, ia, ih, T], c_policy[iw, ia, ih, T]) =
                        terminal_value(W_val, A_real, ss_val, p, T, ih)
                end
            end
        end
    end

    # --- Backward induction: t = T-1 down to 1 ---
    for t in (T-1):-1:1
        age = p.age_start + t - 1
        ss_val = ss_func(age, p)
        trans = health_trans[t]

        # Collapse (ih, ia) into flat index for threading
        Threads.@threads for idx in 1:(nH * nA)
            ih = div(idx - 1, nA) + 1
            ia = mod(idx - 1, nA) + 1
            V_hw = Vector{Float64}(undef, nW)

            s_t_h = surv_health[t, ih]
            A_val = grids.A[ia]
            A_real = annuity_income_real(A_val, t, p)

            # Precompute health-weighted continuation value at t+1:
            # V_hw[iw] = Σ_{ih'} π(ih, ih', t) × V[iw, ia, ih', t+1]
            for iw in 1:nW
                V_hw[iw] = 0.0
                for ih_next in 1:nH
                    V_hw[iw] += trans[ih, ih_next] * V[iw, ia, ih_next, t + 1]
                end
            end

            # Build 1D interpolation of health-weighted continuation
            V_hw_interp = linear_interpolation(
                grids.W, V_hw,
                extrapolation_bc=Interpolations.Flat(),
            )

            for iw in 1:nW
                W_val = grids.W[iw]
                cash_before = W_val + A_real + ss_val

                if p.medical_enabled
                    # Integrate over medical expense shocks.
                    #
                    # Source-aware accounting for SDU: medical absorbs income
                    # first, then portfolio. This matches behavioral evidence
                    # that households fund medical from current income before
                    # tapping retirement savings, and matches the FPR companion
                    # paper's source-tracking convention. When lambda_w = 1
                    # (SDU off), only the total cash matters; with lambda_w<1,
                    # the income/portfolio split changes the effective utility.
                    mu_m, sigma_m = medical_expense_params(age, ih, p)
                    inc_gross = ss_val + A_real
                    V_total = 0.0
                    c_total = 0.0
                    for iq in 1:p.n_quad
                        m = exp(mu_m + sigma_m * gh_nodes[iq])
                        # Medical paid from income first, then portfolio
                        inc_after  = max(0.0, inc_gross - m)
                        port_drain = max(0.0, m - inc_gross)  # m above income hits W
                        W_after    = max(W_val - port_drain, 0.0)
                        # Apply Medicaid floor on total resources. The Medicaid
                        # top-up is treated as income for SDU purposes (it's a
                        # transfer payment, not portfolio drawdown).
                        if inc_after + W_after < p.c_floor
                            inc_after = p.c_floor - W_after
                        end
                        V_k, c_k = solve_consumption(
                            W_after, 0.0, inc_after,
                            V_hw_interp, s_t_h, p, t, ih,
                        )
                        V_total += gh_weights[iq] * V_k
                        c_total += gh_weights[iq] * c_k
                    end
                    V[iw, ia, ih, t] = V_total
                    c_policy[iw, ia, ih, t] = c_total
                else
                    V[iw, ia, ih, t], c_policy[iw, ia, ih, t] = solve_consumption(
                        W_val, A_real, ss_val,
                        V_hw_interp, s_t_h, p, t, ih,
                    )
                end
            end
        end
    end

    return HealthSolution(V, c_policy, grids, p, base_surv)
end

"""
Solve the age-65 annuitization decision (Phase 1/2, no health).
For each (W_0, alpha), compute V(W_remaining, A(alpha), t=1) and find alpha*.

Returns:
- alpha_star[iw]: optimal annuitization fraction for each initial wealth
- V_annuitized[iw]: value at optimal alpha
"""
function solve_annuitization(
    sol::Solution,
    payout_rate::Float64,
)
    # The age-65 alpha decision is the only purchase moment in this solver.
    # For purchases at age > 65 (e.g., delayed-purchase robustness), the
    # bridge fix in welfare.jl/wtp.jl converts the real premium pi*W_0 into
    # a nominal premium nominal_premium = pi * (1+inflation_rate)^(t-1) before
    # multiplying by the payout rate. Here t = 1 by construction, so the
    # inflation factor is 1.0 and pi == nominal_premium. Adding A_new = pi *
    # payout_rate is therefore correct without an explicit gross-up.
    p = sol.params
    g = sol.grids
    nW = length(g.W)
    nA = length(g.A)

    alpha_star = fill(0.0, nW)
    V_annuitized = fill(-Inf, nW)

    V_t1 = sol.V[:, :, 1]
    V_interp = linear_interpolation(
        (g.W, g.A), V_t1,
        extrapolation_bc=Interpolations.Flat(),
    )

    for iw in 1:nW
        W_0 = g.W[iw]
        best_V = -Inf
        best_alpha = 0.0

        for alpha in g.alpha
            A_val = annuity_income(alpha, W_0, payout_rate)
            W_rem = post_purchase_wealth(alpha, W_0, p.fixed_cost)

            W_rem < 0.0 && continue
            is_feasible_purchase(alpha, W_0, p) || continue

            A_clamped = clamp(A_val, g.A[1], g.A[end])
            W_clamped = clamp(W_rem, g.W[1], g.W[end])

            V_val = V_interp(W_clamped, A_clamped)

            if V_val > best_V
                best_V = V_val
                best_alpha = alpha
            end
        end

        alpha_star[iw] = best_alpha
        V_annuitized[iw] = best_V
    end

    return (alpha_star, V_annuitized)
end

"""
Solve the age-65 annuitization decision with health states (Phase 3).
For a given initial health state, find optimal alpha.

Returns:
- alpha_star[iw]: optimal annuitization fraction for each initial wealth
- V_annuitized[iw]: value at optimal alpha
"""
function solve_annuitization_health(
    sol::HealthSolution,
    payout_rate::Float64;
    initial_health::Int=1,  # 1=Good, 2=Fair, 3=Poor
)
    # See solve_annuitization for the bridge-fix argument: t = 1 here, so
    # nominal_premium = pi * (1+pi)^0 = pi and no gross-up is needed.
    p = sol.params
    g = sol.grids
    nW = length(g.W)

    alpha_star = fill(0.0, nW)
    V_annuitized = fill(-Inf, nW)

    # 2D interpolation of V(W, A, H=initial_health, t=1)
    V_t1 = sol.V[:, :, initial_health, 1]
    V_interp = linear_interpolation(
        (g.W, g.A), V_t1,
        extrapolation_bc=Interpolations.Flat(),
    )

    for iw in 1:nW
        W_0 = g.W[iw]
        best_V = -Inf
        best_alpha = 0.0

        for alpha in g.alpha
            A_val = annuity_income(alpha, W_0, payout_rate)
            W_rem = post_purchase_wealth(alpha, W_0, p.fixed_cost)

            W_rem < 0.0 && continue
            is_feasible_purchase(alpha, W_0, p) || continue

            A_clamped = clamp(A_val, g.A[1], g.A[end])
            W_clamped = clamp(W_rem, g.W[1], g.W[end])

            V_val = V_interp(W_clamped, A_clamped)

            # Narrow-framing purchase penalty NPV (Barberis-Huang 2009;
            # Tversky-Kahneman 1992): per-period loss-aversion flow over the
            # underwater amount (premium - cumulative payouts), summed
            # survival- and discount-weighted from age 65 to breakeven.
            if alpha > 0.0 && p.psi_purchase > 0.0
                premium = alpha * W_0
                V_val -= purchase_penalty(premium, payout_rate, p.gamma,
                    p.psi_purchase, p.psi_purchase_c_ref, p.beta, sol.base_surv)
            end

            if V_val > best_V
                best_V = V_val
                best_alpha = alpha
            end
        end

        alpha_star[iw] = best_alpha
        V_annuitized[iw] = best_V
    end

    return (alpha_star, V_annuitized)
end

#=============================================================================
# ORIGINAL FILE: src/simulation.jl
#=============================================================================

# Forward Monte Carlo simulation of lifecycle paths.
# Given a solved model (HealthSolution), simulates individual trajectories
# by drawing medical shocks, health transitions, and survival outcomes.
# Used for validating model moments against HRS data.

using Random
using Interpolations

struct SimulationResult
    wealth_path::Vector{Float64}
    consumption_path::Vector{Float64}
    health_path::Vector{Int}
    medical_path::Vector{Float64}
    age_at_death::Int
    bequest::Float64
end

"""
Simulate a single lifecycle trajectory from age 65 to death.

Given initial state (W_0, A_nominal, H_0), draws medical shocks,
health transitions, and survival outcomes each period. Consumption
is read from the policy function via interpolation.

Returns a SimulationResult with the full trajectory.
"""
function simulate_lifecycle(
    sol::HealthSolution,
    W_0::Float64,
    A_nominal::Float64,
    H_0::Int,
    base_surv::Vector{Float64},
    ss_func::Function,
    p::ModelParams;
    rng::AbstractRNG=Random.default_rng(),
    c_interps::Union{Matrix, Nothing}=nothing,
)
    g = sol.grids
    T = p.T
    # Use OBJECTIVE survival for forward simulation: actual death is governed
    # by physical mortality, not the agent's belief. Subjective survival
    # (with p.survival_pessimism applied) is already baked into the value
    # function used to compute the policy, so the consumption choice is correct
    # under the agent's beliefs; the forward draws here just need to reflect
    # actual mortality.
    surv_health = build_health_survival(base_surv, p; psi_override=1.0)
    health_trans = build_all_health_transitions(p)

    wealth_path = zeros(T)
    consumption_path = zeros(T)
    health_path = zeros(Int, T)
    medical_path = zeros(T)

    W = W_0
    H = H_0
    age_at_death = p.age_end
    bequest = 0.0

    A_nom_c = clamp(A_nominal, g.A[1], g.A[end])

    # Build health-weighted continuation interpolations for each (ih, t)
    # so we can re-optimize consumption given the realized medical shock
    # (matching solve.jl's source-aware accounting). The stored c_policy is
    # E_m[c*(m)] -- the m-averaged optimum -- which is not what the agent
    # would do at any single realized m. Re-optimizing fixes that. The
    # continuation V at (t+1) is health-weighted using the current period's
    # health-transition matrix.
    if c_interps === nothing
        # Caller did not precompute V_hw_interps; build them locally for
        # this single simulation. simulate_batch precomputes them across
        # threads to amortize the cost.
        nW = length(g.W); nA = length(g.A); nH = 3
        V_hw_interps = Matrix{Any}(undef, nH, T)
        for ih in 1:nH
            for tt in 1:T
                if tt < T
                    V_hw = zeros(nW, nA)
                    for ih_next in 1:nH
                        prob = health_trans[tt][ih, ih_next]
                        @views V_hw .+= prob .* sol.V[:, :, ih_next, tt + 1]
                    end
                else
                    # Terminal period: continuation is bequest only;
                    # solve_consumption handles this via the surv=0 path.
                    V_hw = zeros(nW, nA)
                end
                V_hw_interps[ih, tt] = linear_interpolation(
                    (g.W, g.A), V_hw,
                    extrapolation_bc=Interpolations.Flat(),
                )
            end
        end
    end

    for t in 1:T
        age = p.age_start + t - 1
        wealth_path[t] = W
        health_path[t] = H

        # Inflation-adjusted annuity income (with deferral support)
        A_real = annuity_income_real(A_nominal, t, p)

        ss_val = ss_func(age, p)

        # Draw medical expense shock
        m = 0.0
        if p.medical_enabled
            mu_m, sigma_m = medical_expense_params(age, H, p)
            m = exp(mu_m + sigma_m * randn(rng))
        end
        medical_path[t] = m

        # Source-aware accounting (matches solve.jl): medical absorbs
        # income first, then portfolio. The Medicaid floor lifts inc_after
        # if total resources fall below c_floor.
        inc_gross = ss_val + A_real
        inc_after = max(0.0, inc_gross - m)
        port_drain = max(0.0, m - inc_gross)
        W_after = max(W - port_drain, 0.0)
        if inc_after + W_after < p.c_floor
            inc_after = p.c_floor - W_after
        end

        # Re-optimize consumption given the realized shock. solve_consumption
        # handles the SDU kink and the c_floor corner. The continuation is
        # the health-weighted V at t+1 evaluated at the agent's nominal A.
        W_after_c = clamp(W_after, g.W[1], g.W[end])
        V_hw_interp_2d = c_interps === nothing ? V_hw_interps[H, t] : c_interps[H, t]
        # Build a 1D continuation V(W) at the agent's fixed nominal A.
        V_next_interp = let A_fixed = A_nom_c, V_hw_2d = V_hw_interp_2d
            W_eval -> V_hw_2d(clamp(W_eval, g.W[1], g.W[end]), A_fixed)
        end
        s_t_h = surv_health[t, H]
        _, c = solve_consumption(W_after_c, 0.0, inc_after,
                                 V_next_interp, s_t_h, p, t, H)
        consumption_path[t] = c

        # Next-period wealth: cash net of consumption.
        cash = inc_after + W_after
        W_next = (1.0 + p.r) * (cash - c)
        W_next = max(W_next, 0.0)

        # Survival draw
        s = surv_health[t, H]
        if rand(rng) > s || t == T
            bequest = W_next
            age_at_death = age
            break
        end

        # Health transition draw
        u = rand(rng)
        cum = 0.0
        H_next = 3
        for h_next in 1:3
            cum += health_trans[t][H, h_next]
            if u < cum
                H_next = h_next
                break
            end
        end

        W = W_next
        H = H_next
    end

    return SimulationResult(
        wealth_path, consumption_path, health_path, medical_path,
        age_at_death, bequest,
    )
end

"""
Simulate n_sim lifecycle trajectories from a fixed initial state
and return aggregate statistics.

Returns a NamedTuple with:
- mean_wealth_by_age: average wealth at each age (among survivors)
- mean_consumption_by_age: average consumption at each age
- alive_fraction: fraction surviving to each age
- bequests: vector of all bequests
- mean_bequest: unconditional mean bequest
- frac_positive_bequest: fraction with bequest > 0
"""
function simulate_batch(
    sol::HealthSolution,
    W_0::Float64,
    A_nominal::Float64,
    H_0::Int,
    base_surv::Vector{Float64},
    ss_func::Function,
    p::ModelParams;
    n_sim::Int=10_000,
    rng_seed::Int=42,
)
    rng = Random.MersenneTwister(rng_seed)
    T = p.T
    g = sol.grids

    # Precompute health-weighted V continuation interpolations once.
    # simulate_lifecycle re-optimizes consumption given the realized medical
    # shock (matching solve.jl's source-aware accounting). The continuation
    # V at (t+1) is health-weighted using the current period's health
    # transition matrix; we precompute these 2D (W, A) interps here so
    # individual sims share the work.
    nW = length(g.W); nA = length(g.A); nH = 3
    health_trans_pre = build_all_health_transitions(p)
    c_interps = Matrix{Any}(undef, nH, T)  # name preserved for backward compat
    for ih in 1:nH
        for t in 1:T
            if t < T
                V_hw = zeros(nW, nA)
                for ih_next in 1:nH
                    prob = health_trans_pre[t][ih, ih_next]
                    @views V_hw .+= prob .* sol.V[:, :, ih_next, t + 1]
                end
            else
                V_hw = zeros(nW, nA)  # terminal: continuation is zero (bequest handled elsewhere)
            end
            c_interps[ih, t] = linear_interpolation(
                (g.W, g.A), V_hw,
                extrapolation_bc=Interpolations.Flat(),
            )
        end
    end

    wealth_sums = zeros(T)
    wealth_sq_sums = zeros(T)
    consumption_sums = zeros(T)
    medical_sums = zeros(T)
    alive_count = zeros(Int, T)
    health_counts = zeros(Int, T, 3)
    bequests = Vector{Float64}(undef, n_sim)

    # Collect individual wealth paths for percentile computation
    all_wealth = fill(NaN, n_sim, T)

    for i in 1:n_sim
        result = simulate_lifecycle(
            sol, W_0, A_nominal, H_0, base_surv, ss_func, p;
            rng=rng, c_interps=c_interps,
        )
        death_t = result.age_at_death - p.age_start + 1
        for t in 1:min(death_t, T)
            w = result.wealth_path[t]
            wealth_sums[t] += w
            wealth_sq_sums[t] += w^2
            consumption_sums[t] += result.consumption_path[t]
            medical_sums[t] += result.medical_path[t]
            alive_count[t] += 1
            all_wealth[i, t] = w
            h = result.health_path[t]
            if h >= 1 && h <= 3
                health_counts[t, h] += 1
            end
        end
        bequests[i] = result.bequest
    end

    mean_wealth = [alive_count[t] > 0 ? wealth_sums[t] / alive_count[t] : 0.0
                   for t in 1:T]
    mean_consumption = [alive_count[t] > 0 ? consumption_sums[t] / alive_count[t] : 0.0
                        for t in 1:T]
    mean_medical = [alive_count[t] > 0 ? medical_sums[t] / alive_count[t] : 0.0
                    for t in 1:T]
    alive_frac = [alive_count[t] / n_sim for t in 1:T]

    # Wealth percentiles among survivors at each age
    wealth_p25 = zeros(T)
    wealth_p50 = zeros(T)
    wealth_p75 = zeros(T)
    for t in 1:T
        vals = filter(!isnan, all_wealth[:, t])
        if length(vals) >= 4
            sort!(vals)
            n = length(vals)
            wealth_p25[t] = vals[max(1, round(Int, 0.25 * n))]
            wealth_p50[t] = vals[max(1, round(Int, 0.50 * n))]
            wealth_p75[t] = vals[max(1, round(Int, 0.75 * n))]
        end
    end

    # Bequest statistics
    pos_beq = filter(b -> b > 0, bequests)
    frac_pos = length(pos_beq) / n_sim
    mean_beq = sum(bequests) / n_sim
    median_beq = sort(bequests)[max(1, div(n_sim, 2))]
    frac_beq_10k = count(b -> b > 10_000, bequests) / n_sim

    # Health state prevalence by age (fraction in each state among survivors)
    health_prevalence = zeros(T, 3)
    for t in 1:T
        if alive_count[t] > 0
            for h in 1:3
                health_prevalence[t, h] = health_counts[t, h] / alive_count[t]
            end
        end
    end

    return (
        mean_wealth_by_age=mean_wealth,
        mean_consumption_by_age=mean_consumption,
        mean_medical_by_age=mean_medical,
        alive_fraction=alive_frac,
        bequests=bequests,
        mean_bequest=mean_beq,
        median_bequest=median_beq,
        frac_positive_bequest=frac_pos,
        frac_bequest_above_10k=frac_beq_10k,
        health_counts=health_counts,
        health_prevalence=health_prevalence,
        alive_count=alive_count,
        wealth_p25=wealth_p25,
        wealth_p50=wealth_p50,
        wealth_p75=wealth_p75,
        n_sim=n_sim,
    )
end

#=============================================================================
# ORIGINAL FILE: src/diagnostics.jl
#=============================================================================

# Euler equation residual diagnostics for solution accuracy validation.
# Computes normalized residuals at each grid point to verify that the
# numerical solution satisfies the intertemporal optimality condition.

using Interpolations

"""
Numerical derivative of an interpolation object via central finite differences.
Falls back to one-sided differences at boundaries.
"""
function interp_derivative(itp, x::Float64; eps_fd=1.0)
    lo = x - eps_fd
    hi = x + eps_fd
    return (itp(hi) - itp(lo)) / (2.0 * eps_fd)
end

"""
Marginal bequest utility: d/dW [θ (W + κ)^(1-γ) / (1-γ)] = θ (W + κ)^(-γ).
"""
function marginal_bequest(W::Float64, gamma::Float64, theta::Float64, kappa::Float64)
    theta == 0.0 && return 0.0
    arg = max(W + kappa, 1.0)
    return theta * arg^(-gamma)
end

"""
Compute Euler equation residuals for the health-aware lifecycle solution.

At each interior grid point (W, A, H, t), the Euler equation is:

  U'(c*) = β(1+r) E_m[ s ΣH' π(H,H') V'_W(W',A,H',t+1) + (1-s) V'_beq(W') ]

where W' = (1+r)(W + A + SS - m - c*).

Returns a NamedTuple with:
- residuals: 4D array of normalized residuals |LHS - RHS| / max(|LHS|, 1e-10)
- max_residual: maximum residual across all grid points
- mean_residual: mean residual
- median_residual: median residual
- pct_above_1pct: fraction of grid points with residual > 1%
- pct_above_5pct: fraction of grid points with residual > 5%
"""
function compute_euler_residuals(
    sol::HealthSolution,
    base_surv::Vector{Float64},
    ss_func::Function;
    eps_fd::Float64=50.0,   # finite difference step for dV/dW
)
    p = sol.params
    g = sol.grids
    nW = length(g.W)
    nA = length(g.A)
    nH = 3
    T = p.T

    residuals = fill(NaN, nW, nA, nH, T - 1)

    surv_health = build_health_survival(base_surv, p)
    health_trans = build_all_health_transitions(p)
    gh_nodes, gh_weights = gauss_hermite_normal(p.n_quad)

    for t in 1:(T - 1)
        age = p.age_start + t - 1
        ss_val = ss_func(age, p)
        trans = health_trans[t]

        for ih in 1:nH
            s_t_h = surv_health[t, ih]

            for ia in 1:nA
                A_val = g.A[ia]
                A_real = annuity_income_real(A_val, t, p)

                # Build health-weighted continuation interpolation at t+1
                V_hw = Vector{Float64}(undef, nW)
                for iw in 1:nW
                    V_hw[iw] = 0.0
                    for ih_next in 1:nH
                        V_hw[iw] += trans[ih, ih_next] * sol.V[iw, ia, ih_next, t + 1]
                    end
                end
                V_hw_interp = linear_interpolation(
                    g.W, V_hw,
                    extrapolation_bc=Interpolations.Flat(),
                )

                for iw in 1:nW
                    W_val = g.W[iw]
                    c_star = sol.c_policy[iw, ia, ih, t]
                    cash_before = W_val + A_real + ss_val

                    if p.medical_enabled
                        mu_m, sigma_m = medical_expense_params(age, ih, p)
                        # c_policy stores E[c*] across quadrature nodes.
                        # Re-solve for per-node c*(m) and check the expected
                        # Euler equation: E_m[ U'(c*(m)) ] = E_m[ β(1+r) RHS(m) ]
                        lhs_total = 0.0
                        rhs_total = 0.0
                        for iq in 1:p.n_quad
                            m = exp(mu_m + sigma_m * gh_nodes[iq])
                            cash_after = apply_medicaid_floor(cash_before, m, p.c_floor)

                            # Re-solve for optimal consumption at this draw
                            _, c_q = solve_consumption(
                                cash_after, 0.0, 0.0,
                                V_hw_interp, s_t_h, p, t, ih,
                            )

                            # Skip if corner solution at this node
                            if c_q <= p.c_floor + 1e-6 || c_q >= cash_after - 1e-6
                                continue
                            end

                            lhs_total += gh_weights[iq] * marginal_utility(c_q, p.gamma)

                            W_next = (1.0 + p.r) * max(cash_after - c_q, 0.0)
                            W_next_cl = clamp(W_next, g.W[1], g.W[end])

                            dV_cont = interp_derivative(V_hw_interp, W_next_cl; eps_fd=eps_fd)
                            dV_beq = marginal_bequest(W_next, p.gamma, p.theta, p.kappa)

                            rhs_q = p.beta * (1.0 + p.r) * (s_t_h * dV_cont + (1.0 - s_t_h) * dV_beq)
                            rhs_total += gh_weights[iq] * rhs_q
                        end
                        lhs = lhs_total
                        rhs = rhs_total
                        # All nodes hit corner solutions
                        if lhs == 0.0 && rhs == 0.0
                            residuals[iw, ia, ih, t] = 0.0
                            continue
                        end
                    else
                        # No medical expenses: corner check on stored c_star
                        if c_star <= p.c_floor + 1e-6 || c_star >= cash_before - 1e-6
                            residuals[iw, ia, ih, t] = 0.0
                            continue
                        end
                        lhs = marginal_utility(c_star, p.gamma)

                        W_next = (1.0 + p.r) * (cash_before - c_star)
                        W_next = max(W_next, 0.0)
                        W_next_cl = clamp(W_next, g.W[1], g.W[end])

                        dV_cont = interp_derivative(V_hw_interp, W_next_cl; eps_fd=eps_fd)
                        dV_beq = marginal_bequest(W_next, p.gamma, p.theta, p.kappa)

                        rhs = p.beta * (1.0 + p.r) * (s_t_h * dV_cont + (1.0 - s_t_h) * dV_beq)
                    end

                    # Normalized residual
                    residuals[iw, ia, ih, t] = abs(lhs - rhs) / max(abs(lhs), 1e-10)
                end
            end
        end
    end

    # Filter out NaN and corner-solution zeros for summary stats
    valid = filter(x -> !isnan(x) && x > 0.0, vec(residuals))
    all_valid = filter(x -> !isnan(x), vec(residuals))

    return (
        residuals = residuals,
        max_residual = length(valid) > 0 ? maximum(valid) : 0.0,
        mean_residual = length(valid) > 0 ? sum(valid) / length(valid) : 0.0,
        median_residual = length(valid) > 0 ? sort(valid)[div(length(valid), 2) + 1] : 0.0,
        pct_above_1pct = length(all_valid) > 0 ? sum(all_valid .> 0.01) / length(all_valid) * 100 : 0.0,
        pct_above_5pct = length(all_valid) > 0 ? sum(all_valid .> 0.05) / length(all_valid) * 100 : 0.0,
        n_interior = length(valid),
        n_total = length(all_valid),
    )
end

"""
Compute Euler residuals for the non-health solution (Phase 1/2).
Simpler version without medical expenses or health transitions.
"""
function compute_euler_residuals(
    sol::Solution,
    surv::Vector{Float64},
    ss_func::Function;
    eps_fd::Float64=50.0,
)
    p = sol.params
    g = sol.grids
    nW = length(g.W)
    nA = length(g.A)
    T = p.T

    residuals = fill(NaN, nW, nA, T - 1)

    for t in 1:(T - 1)
        age = p.age_start + t - 1
        s_t = surv[t]
        ss_val = ss_func(age, p)

        for ia in 1:nA
            A_val = g.A[ia]
            A_real = annuity_income_real(A_val, t, p)

            V_next_vals = sol.V[:, ia, t + 1]
            V_next_interp = linear_interpolation(
                g.W, V_next_vals,
                extrapolation_bc=Interpolations.Flat(),
            )

            for iw in 1:nW
                W_val = g.W[iw]
                c_star = sol.c_policy[iw, ia, t]
                cash = W_val + A_real + ss_val

                if c_star <= p.c_floor + 1e-6 || c_star >= cash - 1e-6
                    residuals[iw, ia, t] = 0.0
                    continue
                end

                lhs = marginal_utility(c_star, p.gamma)

                W_next = (1.0 + p.r) * (cash - c_star)
                W_next = max(W_next, 0.0)
                W_next_cl = clamp(W_next, g.W[1], g.W[end])

                dV_cont = interp_derivative(V_next_interp, W_next_cl; eps_fd=eps_fd)
                dV_beq = marginal_bequest(W_next, p.gamma, p.theta, p.kappa)

                rhs = p.beta * (1.0 + p.r) * (s_t * dV_cont + (1.0 - s_t) * dV_beq)

                residuals[iw, ia, t] = abs(lhs - rhs) / max(abs(lhs), 1e-10)
            end
        end
    end

    valid = filter(x -> !isnan(x) && x > 0.0, vec(residuals))
    all_valid = filter(x -> !isnan(x), vec(residuals))

    return (
        residuals = residuals,
        max_residual = length(valid) > 0 ? maximum(valid) : 0.0,
        mean_residual = length(valid) > 0 ? sum(valid) / length(valid) : 0.0,
        median_residual = length(valid) > 0 ? sort(valid)[div(length(valid), 2) + 1] : 0.0,
        pct_above_1pct = length(all_valid) > 0 ? sum(all_valid .> 0.01) / length(all_valid) * 100 : 0.0,
        pct_above_5pct = length(all_valid) > 0 ? sum(all_valid .> 0.05) / length(all_valid) * 100 : 0.0,
        n_interior = length(valid),
        n_total = length(all_valid),
    )
end
