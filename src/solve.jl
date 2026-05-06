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
                        medicaid_binding = (inc_after + W_after < p.c_floor)
                        if medicaid_binding
                            inc_after = p.c_floor - W_after
                        end
                        V_k, c_k = terminal_value(W_after, 0.0, inc_after, p, T, ih)
                        # Public-care aversion at terminal period (mirrors the
                        # backward-induction block). Apply chi_ltc to flow
                        # utility only; bequest component of V_k is unaffected.
                        if p.chi_ltc < 1.0 && medicaid_binding && ih == 3
                            flow_u = flow_utility_sdu(c_k, inc_after, p.gamma, T, ih, p)
                            V_k = V_k + (p.chi_ltc - 1.0) * flow_u
                        end
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
                    # Source-aware accounting for SDU (income-first waterfall):
                    # medical absorbs income first, then portfolio. This matches
                    # the modal retiree pattern where routine OOP (Medicare
                    # premiums, supplements, copays) is paid from SS direct
                    # deposit / autopay; portfolio is drawn only when income
                    # is exhausted by catastrophic expenses. The behavioral
                    # economics literature is split on this convention —
                    # Hurd-Rohwedder (2013), Sussman & Shafir (2012), and
                    # Ameriks et al. (2011) suggest households mentally protect
                    # liquid wealth, which would imply portfolio-first
                    # ordering for non-routine medical. We adopt income-first
                    # as the production default because: (i) it matches the
                    # observed direct-deposit/autopay pattern for routine OOP,
                    # which is the modal medical event; (ii) the catastrophic
                    # case (m > inc_gross) still triggers forced portfolio
                    # drawdown via the (m - inc_gross) branch below, capturing
                    # the involuntary nature of the LTC liquidation. The
                    # income-first convention mechanically inflates Force A's
                    # contribution (it shrinks the high-utility income envelope
                    # in high-medical states); a portfolio-first robustness
                    # specification is reported in the manuscript appendix.
                    # When lambda_w = 1 (SDU off), the ordering is irrelevant.
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
                        medicaid_binding = (inc_after + W_after < p.c_floor)
                        if medicaid_binding
                            inc_after = p.c_floor - W_after
                        end
                        V_k, c_k = solve_consumption(
                            W_after, 0.0, inc_after,
                            V_hw_interp, s_t_h, p, t, ih,
                        )
                        # Public-care aversion (Ameriks 2011 QJE; 2020 ECMA):
                        # when the agent must rely on Medicaid AND is in Poor
                        # health (proxy for LTC need), the realized consumption
                        # is Medicaid-financed and yields utility multiplied by
                        # chi_ltc < 1. The multiplier applies to FLOW utility
                        # only — continuation V already incorporates chi_ltc at
                        # future binding states via the backward induction.
                        # Multiplying V_k directly would compound the penalty
                        # geometrically across periods, which is stronger than
                        # the Ameriks specification.
                        if p.chi_ltc < 1.0 && medicaid_binding && ih == 3
                            flow_u = flow_utility_sdu(c_k, inc_after, p.gamma, t, ih, p)
                            V_k = V_k + (p.chi_ltc - 1.0) * flow_u
                        end
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
