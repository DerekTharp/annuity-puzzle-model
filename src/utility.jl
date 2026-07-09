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
κ > 0 makes bequests a luxury good; parameter values are Lockwood (2012)'s
DFJ specification (BAP_sim2.m), and the luxury-good interpretation of κ is
developed in Lockwood (2018).
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

# Weighting convention for the age-needs and health-state channels.
# The age (consumption_decline) and health (health_utility) weights enter as
# multipliers on CRRA flow utility, w_age * w_health * U(c), in the
# flow_utility_sdu* variants below. Under gamma > 1, U(c) is negative, so a
# weight w < 1 makes the utility LEVEL less negative (higher); but the MARGINAL
# utility w * c^(-gamma) is correctly lower for w < 1. Policy decisions are
# driven by marginal utility, so the behavioral direction is correct: declining
# needs (w_age < 1 at older ages) and Poor health (w_health < 1) both LOWER the
# marginal utility of consumption and suppress annuity demand. The level
# inversion only affects cross-state value-function comparisons, which is why
# public-care aversion (chi_LTC) -- a state-comparison primitive -- enters as a
# consumption-equivalent discount inside the binding state
# (flow_utility_sdu_chi_ltc) rather than as a multiplier on negative CRRA utility.

"""
Flow utility with the chi_LTC public-care aversion discount applied as a
consumption-equivalent transformation in the Medicaid-binding Poor state.

Ameriks et al. (2020 JPE) identify a preference for self-financed over
publicly-financed long-term care from strategic-survey wealth equivalents.
The operationalization here: when the consumption floor binds AND health is
Poor, the household's effective consumption is chi_LTC * c (the
publicly-financed portion delivers chi_LTC < 1 units of effective
consumption per dollar). This is then evaluated through CRRA, with the age and
health weights applied multiplicatively as elsewhere.

The earlier specification multiplied flow utility by chi_LTC (i.e., flow utility
became chi_LTC * [w_age * w_health * U(c)]). Under gamma > 1 that specification is
sign-inverted: chi_LTC < 1 multiplies a negative CRRA value, making the
binding state LESS negative (higher value), which means the agent prefers
to enter Medicaid — the OPPOSITE of the Ameriks aversion. The
consumption-equivalent form below has the correct sign under any gamma > 0.
"""
function flow_utility_chi_ltc(c::Float64, gamma::Float64, t::Int, ih::Int,
                              p::ModelParams)
    c_eff = p.chi_ltc * c
    w_age = consumption_weight(t, p.consumption_decline)
    w_health = health_utility_weight(ih, p)
    return w_age * w_health * utility(c_eff, gamma)
end

"""
Source-dependent flow utility (Shefrin-Thaler 1988 mental accounting;
Blanchett-Finke 2024-25 spending differential).

Households consume income (SS, annuity payouts) at full utility weight and
portfolio drawdowns at a discount lambda_w in (0, 1]. The discount applies at
the dollar level (multiplicative on c) rather than at the utility level — this
avoids the sign-flip that would occur for gamma>1 if lambda_w multiplied a
negative CRRA value directly.

  c_income    = min(c, inc)
  c_portfolio = max(0, c - inc)
  c_eff       = c_income + lambda_w * c_portfolio
  u           = w_age * w_health * U(c_eff, gamma)

When lambda_w = 1 (default), c_eff = c and this reduces to w_age * w_health * U(c).
When lambda_w < 1, drawing from portfolio yields strictly less effective
consumption per dollar.
"""
function flow_utility_sdu(c::Float64, inc::Float64, gamma::Float64, t::Int,
                          ih::Int, p::ModelParams)
    if p.lambda_w >= 1.0
        c_eff = c
    else
        c_income = min(c, inc)
        c_portfolio = max(0.0, c - inc)
        c_eff = c_income + p.lambda_w * c_portfolio
    end
    w_age = consumption_weight(t, p.consumption_decline)
    w_health = health_utility_weight(ih, p)
    return w_age * w_health * utility(c_eff, gamma)
end

"""
SDU flow utility with the chi_LTC public-care aversion discount applied as a
consumption-equivalent transformation in the Medicaid-binding Poor state.
Combines the SDU income-vs-portfolio waterfall with the consumption-equivalent
chi_LTC discount; this is the binding-state utility under the production
specification when both channels are active.
"""
function flow_utility_sdu_chi_ltc(c::Float64, inc::Float64, gamma::Float64,
                                  t::Int, ih::Int, p::ModelParams)
    if p.lambda_w >= 1.0
        c_eff_sdu = c
    else
        c_income = min(c, inc)
        c_portfolio = max(0.0, c - inc)
        c_eff_sdu = c_income + p.lambda_w * c_portfolio
    end
    c_eff = p.chi_ltc * c_eff_sdu
    w_age = consumption_weight(t, p.consumption_decline)
    w_health = health_utility_weight(ih, p)
    return w_age * w_health * utility(c_eff, gamma)
end

"""
Narrow-framing at-purchase penalty NPV (Barberis-Huang 2009 narrow framing;
Tversky-Kahneman 1992 loss aversion).

The household evaluates the SPIA as a stand-alone investment with its own
gain/loss tally. While cumulative payouts are below the premium ("underwater"),
the household experiences per-period loss-aversion disutility proportional to
the unrecouped premium. Once cumulative payouts cross the premium (breakeven),
the loss tally turns positive and the penalty vanishes.

Per-period flow at period t (t=1 is age 65):

    flow_t = psi_purchase * u'(c_ref) * max(0, premium - A * (t-1))

where A = annual annuity income, payout_rate = A / premium, and breakeven
period t* = ceil(1/payout_rate). Total disutility is the survival- and
discount-weighted NPV.
"""
function purchase_penalty(premium::Float64,
                          payout_rate::Float64,
                          gamma::Float64,
                          psi_purchase::Float64,
                          c_ref::Float64,
                          beta::Float64,
                          surv::Vector{Float64};
                          purchase_period::Int=1)
    psi_purchase <= 0.0 && return 0.0
    premium <= 0.0 && return 0.0
    payout_rate <= 0.0 && return 0.0

    A = premium * payout_rate
    mu_ref = c_ref^(-gamma)
    breakeven_t = ceil(Int, 1.0 / payout_rate) + 1

    surv_offset = purchase_period - 1
    surv_remaining = surv_offset == 0 ? surv : @view surv[purchase_period:end]

    npv = 0.0
    cum_surv = 1.0
    horizon = min(breakeven_t, length(surv_remaining) + 1)
    for t in 1:horizon
        underwater = max(0.0, premium - A * (t - 1))
        underwater <= 0.0 && break
        flow = psi_purchase * mu_ref * underwater
        discount = beta^(t - 1)
        npv += cum_surv * discount * flow
        if t <= length(surv_remaining)
            cum_surv *= surv_remaining[t]
        end
    end
    return npv
end
