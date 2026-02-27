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
