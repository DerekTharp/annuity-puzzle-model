# CRRA utility and bequest utility functions.
# Follows Lockwood (2012) parameterization.

"""
CRRA utility: U(c) = c^(1-γ) / (1-γ) for γ ≠ 1, log(c) for γ = 1.
Returns -Inf for c <= 0.
"""
function utility(c::Float64, gamma::Float64)
    c <= 0.0 && return -Inf
    if gamma == 1.0
        return log(c)
    else
        return c^(1.0 - gamma) / (1.0 - gamma)
    end
end

"""
Bequest utility: V(b) = θ * (b + κ)^(1-γ) / (1-γ).
κ > 0 makes bequests a luxury good (Lockwood 2018).
Returns 0 when θ = 0 (no bequest motive).
"""
function bequest_utility(b::Float64, gamma::Float64, theta::Float64, kappa::Float64)
    theta == 0.0 && return 0.0
    # Floor at $1 to prevent -Inf when kappa=0 and b=0 (warm-glow specification).
    # With kappa>0 (luxury good), (b+kappa) is bounded away from zero and this
    # floor never binds. With kappa=0, the floor avoids numerical instability
    # at boundary states while preserving the economic incentive to save.
    arg = max(b + kappa, 1.0)
    if gamma == 1.0
        return theta * log(arg)
    else
        return theta * arg^(1.0 - gamma) / (1.0 - gamma)
    end
end

"""
Marginal utility: U'(c) = c^(-γ).
"""
function marginal_utility(c::Float64, gamma::Float64)
    c <= 0.0 && return Inf
    return c^(-gamma)
end

"""
Age-varying consumption weight: (1 - delta_c)^(t-1).
At t=1 (age 65), returns 1.0. Declines geometrically with age.
Returns 1.0 when delta_c == 0.0 (channel off).
"""
function consumption_weight(t::Int, delta_c::Float64)
    delta_c == 0.0 && return 1.0
    return (1.0 - delta_c)^(t - 1)
end

"""
Health-state-dependent utility weight.
ih: health state index (1=Good, 2=Fair, 3=Poor).
"""
function health_utility_weight(ih::Int, p::ModelParams)
    return p.health_utility[ih]
end

"""
Flow utility combining CRRA with age-varying needs and health-state weights.
With defaults (consumption_decline=0, health_utility=[1,1,1]), reduces to utility(c, gamma).
"""
function flow_utility(c::Float64, gamma::Float64, t::Int, ih::Int, p::ModelParams)
    w_age = consumption_weight(t, p.consumption_decline)
    w_health = health_utility_weight(ih, p)
    return w_age * w_health * utility(c, gamma)
end
