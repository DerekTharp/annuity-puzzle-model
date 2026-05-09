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
Marginal utility: U'(c) = c^(-γ). Pure CRRA, no weights.
"""
function marginal_utility(c::Float64, gamma::Float64)
    c <= 0.0 && return Inf
    return c^(-gamma)
end

"""
Marginal of flow_utility with respect to consumption c, including age-varying
needs and health-state weights. Returns w_age * w_health * c^(-γ).

This is the LHS of the agent's Euler equation under the production utility
specification (CRRA + age-varying needs + state-dependent utility). The bare
`marginal_utility(c, γ)` omits the age and health weights and is therefore
the wrong LHS whenever either channel is active.
"""
function marginal_flow_utility(c::Float64, gamma::Float64, t::Int,
                               ih::Int, p::ModelParams)
    c <= 0.0 && return Inf
    w_age = consumption_weight(t, p.consumption_decline)
    w_health = health_utility_weight(ih, p)
    return w_age * w_health * c^(-gamma)
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

# SDU (source-dependent utility) and at-purchase penalty mechanisms have been
# removed from the model. The bundled behavioral wedge (SDU + narrow-framing
# PED + choice-architecture salience) is identified externally from the UK
# 2015 pension-freedoms reform as a proportional retention factor and applied
# to the model's no-behavioral baseline as a deterministic multiplicative
# transformation in scripts/export_manuscript_numbers.jl. The model itself
# therefore parameterizes only rational + preference + structural channels.
