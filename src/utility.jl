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
Marginal of flow_utility_sdu with respect to total consumption c, evaluated
at (c, inc, t, ih, p). Returns w_age * w_health * d/dc U(c_eff(c, inc)).

For c <= inc: c_eff = c, so d/dc = w_age * w_health * c^(-γ).
For c > inc:  c_eff = inc + λ_w * (c - inc), so d/dc = w_age * w_health
              * λ_w * c_eff^(-γ).

This is the LHS of the agent's Euler equation under the production utility
specification (CRRA + age-varying needs + state-dependent utility + SDU).
The bare `marginal_utility(c, γ)` omits all four weights and is therefore
the wrong LHS whenever any of those channels is active.
"""
function marginal_flow_utility_sdu(c::Float64, inc::Float64,
                                   gamma::Float64, t::Int,
                                   ih::Int, p::ModelParams)
    c <= 0.0 && return Inf
    w_age = consumption_weight(t, p.consumption_decline)
    w_health = health_utility_weight(ih, p)
    if p.lambda_w >= 1.0 || c <= inc
        # SDU off, or consumption is fully income-funded → c_eff = c, dC_eff/dc = 1
        return w_age * w_health * c^(-gamma)
    else
        c_eff = inc + p.lambda_w * (c - inc)
        c_eff <= 0.0 && return Inf
        # dC_eff/dc = λ_w on the portfolio-funded margin
        return w_age * w_health * p.lambda_w * c_eff^(-gamma)
    end
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

"""
Source-dependent flow utility (Tharp FPR companion paper; Blanchett-Finke 2024,
2025; Shefrin-Thaler 1988 mental accounting).

Households experience consumption financed by income flows (Social Security,
annuity payouts) at full utility weight, and consumption financed by portfolio
drawdowns at a discount lambda_w in [0, 1]. The discount is applied at the
DOLLAR level (multiplicative on c) rather than at the utility level — this
avoids the sign-flip that would occur for gamma>1 if lambda_w multiplied a
negative CRRA value directly.

  c_income    = min(c, inc)            # dollars financed by income flow
  c_portfolio = max(0, c - inc)        # dollars financed by portfolio drawdown
  c_eff       = c_income + lambda_w * c_portfolio
  u           = w_age * w_health * U(c_eff, gamma)

When lambda_w = 1 (default), c_eff = c and this reduces to flow_utility above.
When lambda_w < 1, drawing from portfolio yields strictly less effective
consumption per dollar, which (i) discourages portfolio drawdown and
(ii) makes converting portfolio wealth into income (via annuitization) more
attractive on the consumption side.

Calibration: lambda_w = 0.625 from Blanchett-Finke (2024, 2025) — retirees
spend ~80% of guaranteed income but only ~50% of portfolio wealth, implying a
50/80 = 0.625 ratio in spending propensity. Same calibration as the FPR
companion paper.
"""
function flow_utility_sdu(c::Float64, inc::Float64, gamma::Float64, t::Int,
                          ih::Int, p::ModelParams)
    if p.lambda_w >= 1.0
        # SDU off: identical to flow_utility
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
Narrow-framing purchase penalty NPV (Barberis-Huang 2009; Tversky-Kahneman
1992 loss aversion; Brown et al. 2008 framing evidence).

The household mentally brackets the annuity decision as a separate "investment"
with its own gain/loss tally — the cumulative annuity payout net of the premium
paid. While the household is "underwater" (cumulative payouts < premium), the
narrow-framing loss is salient and generates a per-period disutility flow
proportional to the unrecouped premium. Once cumulative payouts cross the
premium ("breakeven"), the loss tally turns positive and the penalty vanishes.

This captures the user-described two-part felt cost of annuitization:
(i) immediate "loss" of writing the check at age 65, and (ii) ongoing
discomfort of reduced portfolio plus reduced optionality until breakeven.

Per-period flow at period t (t=1 is age 65, before any payouts received):

    flow_t = psi_purchase * u'(c_ref) * max(0, premium - A * (t-1))

where A is the annual annuity income, payout_rate = A / premium, breakeven
period is t* = ceil(1/payout_rate) ≈ 14-15 for typical SPIA pricing, and
u'(c_ref) = c_ref^(-gamma) is the marginal utility at the reference
consumption (SS mean = 18,000 dollars/yr).

The total penalty entering the age-65 alpha search is the survival- and
discount-weighted NPV of the stream:

    penalty_NPV = sum_{t=1..t*} beta^(t-1) * S(t) * flow_t

where S(1) = 1 (alive at purchase) and S(t) = prod_{s=1..t-1} surv[s].

Reduces to zero when psi_purchase = 0 (channel off) or premium = 0
(no purchase). Returns the NPV in lifetime-utility units, ready to be
subtracted from the value-function at the alpha-search step.

Note on functional form: this replaces an earlier one-time linear-in-premium
penalty whose magnitude was insensitive to whether the household actually
recouped the premium. Multiple peer reviewers flagged the earlier form as
ad hoc (no axiomatic basis). The narrow-framing stream above is derivable
from prospect-theoretic narrow framing (Barberis-Huang 2009) plus
Tversky-Kahneman loss aversion applied to the annuity's running gain/loss
tally.
"""
function purchase_penalty(premium::Float64,
                          payout_rate::Float64,
                          gamma::Float64,
                          psi_purchase::Float64,
                          c_ref::Float64,
                          beta::Float64,
                          surv::Vector{Float64};
                          purchase_period::Int=1)
    # purchase_period: index into `surv` for the period of purchase. Defaults
    # to 1 (age-65 / period-1 purchase, which is the only call site in the
    # current pipeline). For purchases at later ages, pass purchase_period =
    # period-of-purchase so the cumulative survival starts conditional on
    # being alive at the purchase moment, not at age 65.
    psi_purchase <= 0.0 && return 0.0
    premium <= 0.0 && return 0.0
    payout_rate <= 0.0 && return 0.0

    A = premium * payout_rate
    mu_ref = c_ref^(-gamma)

    # Breakeven period: smallest t such that A * (t-1) >= premium → t-1 >= 1/payout_rate.
    # After breakeven, max(0, premium - A*(t-1)) = 0 and the stream contributes nothing.
    breakeven_t = ceil(Int, 1.0 / payout_rate) + 1  # +1 for the period at-which underwater hits 0

    # Slice survival schedule from the purchase period forward. surv[t] is the
    # one-period survival probability at age 65+t-1, so for a purchase at
    # period p_t we want surv[p_t], surv[p_t+1], ... as the conditional one-
    # period probabilities going forward.
    surv_offset = purchase_period - 1
    surv_remaining = surv_offset == 0 ? surv : @view surv[purchase_period:end]

    npv = 0.0
    cum_surv = 1.0  # alive at purchase by construction
    horizon = min(breakeven_t, length(surv_remaining) + 1)
    for t in 1:horizon
        underwater = max(0.0, premium - A * (t - 1))
        underwater <= 0.0 && break
        flow = psi_purchase * mu_ref * underwater
        discount = beta^(t - 1)
        npv += cum_surv * discount * flow
        # Update cumulative survival for next period (conditional on alive at
        # the purchase moment).
        if t <= length(surv_remaining)
            cum_surv *= surv_remaining[t]
        end
    end
    return npv
end
