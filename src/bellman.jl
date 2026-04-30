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
