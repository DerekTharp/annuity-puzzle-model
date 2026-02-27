# Implementation Spec: Two New Channels

## Context

The model currently predicts 18.3% ownership with age-band health transitions and W_MAX=$3M. Observed ownership is 3-6%. Two novel channels are proposed to close the gap.

## Channel 1: Front-Loaded Spending Preferences (Age-Declining Consumption Needs)

### Economic Motivation

Aguiar and Hurst (2005, 2013) document that consumption expenditure declines ~2% per year after retirement, even controlling for health. Banks, Blundell, and Tanner (1998) find similar patterns in UK data. If the marginal utility of a dollar of consumption declines with age (because consumption needs shrink), the value of late-life annuity income falls, reducing annuity demand.

### Mathematical Specification

Replace the current flow utility:
```
U(c) = c^(1-γ) / (1-γ)
```

With age-weighted utility:
```
U(c, t) = w(t) · c^(1-γ) / (1-γ)
```

Where `w(t)` is an age-dependent consumption weight:
```
w(t) = (1 - δ_c)^(t-1)
```

- `δ_c` = annual consumption-need decline rate
- `t` = period (1 = age 65, 46 = age 110)
- `w(1) = 1.0` (normalized at entry)
- At δ_c = 0.02 (Aguiar-Hurst central estimate): w(20) = 0.67 at age 85, w(35) = 0.49 at age 100

### Where it enters the code

1. **`src/parameters.jl`**: Add `consumption_decline::Float64 = 0.0` to ModelParams. When 0.0, no age weighting (backward compatible).

2. **`src/utility.jl`**: Add function:
```julia
function consumption_weight(t::Int, delta_c::Float64)
    delta_c == 0.0 && return 1.0
    return (1.0 - delta_c)^(t - 1)
end
```

3. **`src/bellman.jl`**: In `solve_consumption()` and `solve_consumption_health()` (in solve.jl), multiply the flow utility by w(t):
```julia
V_flow = consumption_weight(t, p.consumption_decline) * utility(c, p.gamma)
```
The age/time period `t` must be passed to the consumption solver. Currently it's not — `solve_consumption` only receives (W, A, ss, V_next_interp, surv, p). The time period `t` needs to be added as an argument.

4. **`src/solve.jl`**: Pass `t` to the consumption solver at each grid point.

5. **Bequest utility is NOT age-weighted** — the value of leaving wealth to heirs doesn't decline with the retiree's age.

6. **`scripts/config.jl`**: Add `const CONSUMPTION_DECLINE = 0.02` (Aguiar-Hurst central estimate).

### Calibration

- Central: δ_c = 0.02 (Aguiar-Hurst 2013)
- Sensitivity: δ_c ∈ {0.0, 0.01, 0.02, 0.03}
- Source: Aguiar and Hurst (2013, "Deconstructing Life Cycle Expenditure," JPE)

### Effect on annuity demand

This uniformly reduces the value of late-life annuity income. The mortality credit is earned primarily from surviving to advanced ages (80+), but if consumption utility at those ages is discounted by w(t), the effective mortality credit shrinks. Agents who were marginally willing to annuitize will no longer find it worthwhile.

### Interaction with other channels

- Amplifies inflation erosion: annuity payments already lose purchasing power with inflation, and age-declining utility further reduces their value
- Amplifies the R-S mechanism: health shocks at older ages (when w(t) is low) reduce both annuity value and consumption value simultaneously
- Partially substitutes for the discount factor β: both discount the future, but w(t) discounts consumption specifically while β discounts all utility equally

---

## Channel 2: State-Dependent Utility (Health-Varying Marginal Utility)

### Economic Motivation

Finkelstein, Luttmer, and Notowidigdo (2013, QJE) estimate that the marginal utility of consumption declines with health deterioration. A dollar is worth less when you're in a nursing home than when you're active. They estimate a decline of ~11% for each additional chronic condition, or equivalently, marginal utility in "Poor" health is roughly 75-85% of marginal utility in "Good" health.

### Mathematical Specification

Replace flow utility:
```
U(c) = c^(1-γ) / (1-γ)
```

With health-dependent utility:
```
U(c, H) = φ(H) · c^(1-γ) / (1-γ)
```

Where `φ(H)` is a health-utility multiplier:
```
φ(Good)  = 1.0
φ(Fair)  = φ_fair    (e.g., 0.90)
φ(Poor)  = φ_poor    (e.g., 0.75)
```

### Where it enters the code

1. **`src/parameters.jl`**: Add `health_utility::Vector{Float64} = [1.0, 1.0, 1.0]` to ModelParams. Default [1.0, 1.0, 1.0] = no state dependence (backward compatible).

2. **`src/utility.jl`**: Add function:
```julia
function health_utility_weight(H::Int, p::ModelParams)
    return p.health_utility[H]
end
```

3. **`src/solve.jl`**: In the health-aware Bellman loop, multiply flow utility by φ(H):
```julia
V_flow = health_utility_weight(ih, p) * utility(c, p.gamma)
```
The health state `ih` is already available in the loop over health states.

4. **Bequest utility is NOT health-weighted** — the value of bequests doesn't depend on the retiree's health at death.

5. **`scripts/config.jl`**: Add `const HEALTH_UTILITY = [1.0, 0.90, 0.75]` (Finkelstein et al. 2013 central estimates).

### Calibration

- Central: φ = [1.0, 0.90, 0.75] (Finkelstein, Luttmer, Notowidigdo 2013)
- Sensitivity: φ_poor ∈ {0.60, 0.70, 0.75, 0.80, 0.90, 1.00}
- Source: Finkelstein, Luttmer, and Notowidigdo (2013, "What Good Is Wealth Without Health?", QJE)
- Note: Their estimates use PSID data and a structural model. The 0.75 value for "Poor" is a midpoint of their range. The exact mapping from their health measures to our 3-state model is approximate.

### Effect on annuity demand

This reduces the value of annuity income in states where the annuitant is in Poor health. Since the R-S mechanism already makes annuities lose value when health deteriorates (through mortality), state-dependent utility adds a second channel: the income itself is worth less because consumption utility is lower. The two mechanisms reinforce each other.

### Interaction with other channels

- Strongly amplifies the R-S mechanism: health shocks now cause THREE simultaneous effects: (1) higher mortality reduces expected remaining payments, (2) higher medical costs raise liquidity demand, (3) lower marginal utility reduces the value of each remaining payment
- Interacts with bequests: in Poor health, the marginal utility of consumption is low while the marginal utility of bequests (which is NOT health-dependent) is unchanged — this tilts toward saving for bequests rather than consuming annuity income

---

## Combined Implementation Notes

Both channels multiply the flow utility. If both are active:
```
V_flow = w(t) · φ(H) · c^(1-γ) / (1-γ)
```

This is a single multiplication: `consumption_weight(t, p.consumption_decline) * health_utility_weight(ih, p) * utility(c, p.gamma)`.

Neither channel adds state variables, changes the grid structure, or requires new interpolation. The computational cost is essentially zero — just one or two multiplications per grid point evaluation.

Both are off by default (w(t)=1.0, φ(H)=[1,1,1]) for backward compatibility.

## Decomposition Integration

These become Channels 8 and 9 in the sequential decomposition. The ordering should be:
0. Yaari benchmark
1. + Social Security
2. + Bequest motives
3. + Medical expenditure risk
4. + Health-mortality correlation (R-S)
5. + Survival pessimism
6. + Front-loaded spending preferences (NEW)
7. + State-dependent utility (NEW)
8. + Pricing loads
9. + Inflation erosion

Placing them before pricing loads but after the health/mortality channels is natural: they modify preferences (utility weights) rather than market frictions (loads, inflation).

## Questions for Review

1. Should w(t) multiply only consumption utility, or also bequest utility? (Proposed: consumption only)
2. Should φ(H) apply at the moment of death for bequest value? (Proposed: no)
3. Is the ordering in the decomposition appropriate?
4. Is δ_c = 0.02 the right central estimate? Aguiar-Hurst find ~2% but this varies by expenditure category.
5. Is φ(Poor) = 0.75 well-calibrated? Finkelstein et al.'s estimates range from 0.65 to 0.90.
6. Should front-loaded spending interact with the discount factor β? (They are mathematically similar but economically distinct — δ_c reflects changing needs, β reflects time preference.)
