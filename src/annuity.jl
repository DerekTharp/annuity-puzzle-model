# Annuity pricing and payout rate calculations.
# Follows Mitchell et al. (1999) for MWR methodology.
# A SPIA converts a lump sum into a lifelong income stream;
# the payout rate depends on mortality assumptions and the discount rate.

"""
Compute actuarially fair annual payout per dollar of premium for a SPIA
purchased at `purchase_age`, using the given survival probabilities and
discount rate. Adjusted by the money's worth ratio.

Fair annuity value of \$1 = sum_{t=1}^{T} s(t) / (1+r)^t
Payout rate = MWR / fair_annuity_value

If MWR = 1.0, the annuity is actuarially fair.
If MWR = 0.82, the expected present value of payouts is 82 cents per dollar.
"""
function compute_payout_rate(p::ModelParams, surv::Vector{Float64})
    # Present value of \$1/year life annuity, including payment at purchase age.
    # PV = sum_{t=0}^{T-1} S(t) / (1+r_discount)^t
    # where S(0) = 1 (alive at purchase), S(t) = prod_{s=1}^{t} surv[s].
    #
    # Discount rate depends on product type:
    #   - Real annuity (inflation_rate=0): discount at r (real rate)
    #   - Nominal annuity (inflation_rate>0): discount at r_nom (exact Fisher)
    #     The insurer invests in nominal bonds yielding r_nom and pays nominal
    #     dollars; the higher discount rate produces a higher initial payout
    #     whose real value then erodes via annuity_income_real().
    r_discount = p.inflation_rate > 0 ? (1 + p.r) * (1 + p.inflation_rate) - 1 : p.r

    pv = 1.0  # t=0: alive at purchase, no discounting
    for t in 1:(p.T - 1)
        cum_surv = 1.0
        for s in 1:t
            cum_surv *= surv[s]
        end
        discount = 1.0 / (1.0 + r_discount)^t
        pv += cum_surv * discount
    end

    # Payout rate: annual income per dollar of premium
    # With fair pricing (MWR=1): premium = pv * payout => payout = 1/pv
    # With loads (MWR<1): consumer gets less => payout = MWR / pv
    payout_rate = p.mwr / pv
    return payout_rate
end

"""
Annuity income given initial wealth W_0 and annuitization fraction alpha.
A = alpha * W_0 * payout_rate
"""
function annuity_income(alpha::Float64, W_0::Float64, payout_rate::Float64)
    return alpha * W_0 * payout_rate
end

"""
Check whether an annuity purchase meets the minimum premium requirement.
Returns true if alpha is zero (no purchase) or if the premium exceeds min_purchase.
"""
function is_feasible_purchase(alpha::Float64, W_0::Float64, p::ModelParams)
    alpha == 0.0 && return true
    premium = alpha * W_0
    return premium >= p.min_purchase
end

"""
Inflation-adjusted annuity income at period t, with deferral support.
Returns 0 before the deferral start period (for DIA products).
Inflation erodes from purchase time (period 1), not payment start.
"""
function annuity_income_real(A_nominal::Float64, t::Int, p::ModelParams)
    if t < p.deferral_start_period
        return 0.0
    end
    return A_nominal * (1.0 / (1.0 + p.inflation_rate))^(t - 1)
end

"""
Compute payout rate for a deferred income annuity (DIA) purchased at age_start
with payments beginning at deferral_age. Uses dia_mwr for the money's worth ratio.
"""
function compute_payout_rate_deferred(p::ModelParams, surv::Vector{Float64}, deferral_age::Int)
    d_period = deferral_age - p.age_start  # 0-indexed period when first payment occurs
    r_discount = p.inflation_rate > 0 ? (1 + p.r) * (1 + p.inflation_rate) - 1 : p.r
    pv = 0.0
    for t in 0:(p.T - 1)
        t < d_period && continue
        cum_surv = 1.0
        for s in 1:t
            cum_surv *= surv[s]
        end
        discount = 1.0 / (1.0 + r_discount)^t
        pv += cum_surv * discount
    end
    pv < 1e-10 && return 0.0
    return p.dia_mwr / pv
end

"""
Compute payout rate for a period-certain life annuity.
Payments are guaranteed for the first `guarantee_years` regardless of
survival, then life-contingent thereafter. Partially offsets the bequest
penalty since the guaranteed period provides a quasi-bequest.
"""
function compute_payout_rate_period_certain(p::ModelParams, surv::Vector{Float64};
                                            guarantee_years::Int=10)
    r_discount = p.inflation_rate > 0 ? (1 + p.r) * (1 + p.inflation_rate) - 1 : p.r
    pv = 0.0
    for t in 0:(p.T - 1)
        if t < guarantee_years
            cum_surv = 1.0  # certain payment
        else
            cum_surv = 1.0
            for s in 1:t
                cum_surv *= surv[s]
            end
        end
        discount = 1.0 / (1.0 + r_discount)^t
        pv += cum_surv * discount
    end
    return p.mwr / pv
end

"""
Remaining liquid wealth after annuity purchase.
W_remaining = (1 - alpha) * W_0 - fixed_cost * (alpha > 0)
"""
function post_purchase_wealth(alpha::Float64, W_0::Float64, fixed_cost::Float64)
    W = (1.0 - alpha) * W_0
    if alpha > 0.0
        W -= fixed_cost
    end
    return W  # callers check W < 0 to reject infeasible purchases
end
