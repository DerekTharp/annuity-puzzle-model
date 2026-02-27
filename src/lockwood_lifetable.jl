# SSA administrative life table from Lockwood (2012) replication code.
# These are exact cumulative death probabilities for ages 66–111,
# from the perspective of a 65-year-old.
# Source: BAP_wtp.m, lines 51–96.

"""
SSA admin cumulative death probabilities from Lockwood (2012).
cum_death_probs[i] = Pr(dead before age 65+i) for i=1:46.
cum_death_probs[1] = 0.0 (alive at 65), cum_death_probs[46] = ~1.0 (dead by 111).
Max age = 110 (46 periods from age 65).
"""
const LOCKWOOD_CUM_DEATH_PROBS = [
    0.0,
    0.018740306,
    0.038815572,
    0.060225799,
    0.08304727,
    0.107305414,
    0.13310194,
    0.160538561,
    0.189602563,
    0.220281232,
    0.252561853,
    0.286520711,
    0.322170519,
    0.359320569,
    0.397703868,
    0.437129707,
    0.477483663,
    0.518651308,
    0.560441936,
    0.602563125,
    0.644658886,
    0.68624609,
    0.726765327,
    0.765669896,
    0.802387673,
    0.836397386,
    0.867254049,
    0.894652529,
    0.918376688,
    0.938401098,
    0.954802044,
    0.967795662,
    0.977712513,
    0.985023012,
    0.990223002,
    0.993782897,
    0.996160399,
    0.997698782,
    0.998665039,
    0.999262593,
    0.999605869,
    0.999796577,
    0.999898289,
    0.999949144,
    0.999974572,
    0.999987286,
]

"""
Build conditional survival probabilities from Lockwood's SSA life table.
Returns a vector of length T where surv[t] = Pr(survive from age 64+t to 65+t | alive at 64+t).
surv[T] = 0.0 (certain death at max age).

If the model's age range differs from Lockwood's (65–110), this extracts
the appropriate subset or pads with zeros.
"""
function build_lockwood_survival(p::ModelParams)
    T = p.T
    cdp = LOCKWOOD_CUM_DEATH_PROBS
    n_lockwood = length(cdp)  # 46 periods (ages 65–110)

    surv = Vector{Float64}(undef, T)
    for t in 1:T
        age = p.age_start + t - 1
        lockwood_idx = age - 65 + 1  # index into cdp (1-based, age 65 = index 1)

        if age >= p.age_end
            surv[t] = 0.0
        elseif lockwood_idx < 1 || lockwood_idx >= n_lockwood
            # Outside Lockwood's table range — use Gompertz fallback
            surv[t] = survival_prob_deterministic(age)
        else
            # Conditional survival: Pr(alive at age+1) / Pr(alive at age)
            surv[t] = (1.0 - cdp[lockwood_idx + 1]) / (1.0 - cdp[lockwood_idx])
        end
    end
    return surv
end
