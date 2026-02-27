# Dissolving the Annuity Puzzle: A Unified Lifecycle Model

## AGENTS.md — Project Context and Roadmap

---

## 1. PROJECT OVERVIEW

**Companion survey paper:** The full JES manuscript is at `docs/dissolving_annuity_puzzle_survey.md`. Consult it for the detailed nine-assumption argument, empirical evidence, cross-cultural data, specific ownership rates and calibration targets cited in the literature, and the precise claims about what a unified model must demonstrate. That paper is the intellectual foundation; this model must deliver on its promises.

### 1.1 What This Project Is

This project builds a calibrated lifecycle model that nests all major channels proposed to explain low voluntary annuity demand — within a single unified framework. No existing paper does this. The goal is an AER- or JPE-quality publication that definitively resolves the "annuity puzzle" quantitatively.

The annuity puzzle: Yaari (1965) proved that a rational consumer facing uncertain lifetime, no bequest motive, and actuarially fair annuities should annuitize 100% of wealth. Observed voluntary annuity ownership is 3–6%. Six decades of research have proposed partial explanations — bequest motives, pre-existing annuitization through Social Security, health expenditure risk, stochastic mortality, prospect theory, pricing loads — but no single paper incorporates all channels simultaneously.

### 1.2 Why This Paper Matters

Two important papers attempted multi-channel models and reached incomplete conclusions:

- **Pashchenko (2013, Journal of Public Economics)** incorporated pre-existing annuitization, bequest motives, housing illiquidity, and minimum purchase requirements. Her model still overpredicted annuity participation by a factor of four (~20% predicted vs ~5% observed). She omitted stochastic mortality correlation and behavioral preferences.

- **Peijnenburg, Nijman, and Werker (2016, Journal of Economic Dynamics and Control)** incorporated incomplete markets, background risk, bequests, and default risk. They found full annuitization remains approximately optimal, titling their paper "The Annuity Puzzle Remains a Puzzle." They omitted stochastic mortality correlation (Reichling-Smetters mechanism).

This project resolves their disagreement by building the model neither wrote — one that nests all channels and shows which interactions close the residual gap.

### 1.3 The Intellectual Architecture

A companion survey paper (Tharp, forthcoming at Journal of Economic Surveys, "Dissolving the Annuity Puzzle: A Critical Survey") argues qualitatively that the accumulated evidence dissolves the puzzle. The present modeling paper provides the quantitative proof. The survey identifies the channels; this paper demonstrates that they compound multiplicatively within a unified framework to generate predicted demand of 3–8%, matching observed data.

### 1.4 Target Contribution

The paper delivers three novel results:

1. **Sequential decomposition**: Starting from Yaari's 100% benchmark, show how adding each channel reduces predicted annuitization, and show that the channels interact multiplicatively (not additively).

2. **Unified quantitative match**: The full model with all channels generates predicted voluntary annuity ownership of 3–8% across reasonable parameterizations, matching observed US data.

3. **Heterogeneous welfare map**: Identify which household types (by wealth, marital status, health, bequest motives) would benefit from additional annuitization, and quantify the welfare stakes in consumption-equivalent units.

---

## 2. THE ECONOMIC MODEL

### 2.1 Overview of Model Structure

The model is a discrete-time, finite-horizon lifecycle consumption-saving-annuitization problem solved by backward induction. An individual enters at age 65 (retirement) and may live to a maximum age of 100. At each age, the individual chooses how much to consume, how much to save in liquid (non-annuitized) wealth, and — at age 65 only — what fraction of initial wealth to annuitize through a single irreversible SPIA purchase.

### 2.2 State Variables

The model state at each age t is characterized by:

| Variable | Symbol | Description | Grid |
|----------|--------|-------------|------|
| Liquid wealth | W | Non-annuitized financial wealth | 50–100 points, nonuniform (denser at low wealth) |
| Annuity income | A | Annual annuity income stream from SPIA purchase | 10–20 points |
| Health status | H | Discrete health state (good, fair, poor) | 3 points |
| Age | t | Current age (65–100) | 36 points |

Total state space: ~50 × 15 × 3 × 36 ≈ 81,000 grid points per backward induction step. This is computationally tractable on a Mac Studio.

**Optional extension (Phase 5):** Add marital status as a fifth state variable (single vs. married), expanding the state space by a factor of 2. This enables analysis of Kotlikoff-Spivak intra-household risk sharing but doubles computation time.

### 2.3 Income and Pre-Existing Annuitization

The individual receives Social Security income SS(t) that is:
- Exogenous and known with certainty
- Inflation-indexed (real)
- Calibrated to match the distribution of Social Security benefits by wealth quartile from HRS/SCF data
- Non-commutable (cannot be converted to a lump sum)

For households with DB pension income, this is added as an additional exogenous annuity stream DB(t), also non-commutable. DB pension prevalence varies by cohort and wealth.

**Calibration targets for pre-existing annuitization:**
- Bottom wealth quartile: ~75% of total wealth annuitized (Lockwood, 2012)
- Median: ~67% annuitized
- 80th–90th percentile: ~50% annuitized
- Top decile: ~33% annuitized

### 2.4 Preferences and Utility

**Baseline specification (expected utility):**

```
U(c) = c^(1-γ) / (1-γ)     for consumption
V(b) = θ × (b + κ)^(1-γ) / (1-γ)   for bequests
```

Where:
- γ = coefficient of relative risk aversion (baseline: 3, range: 1–5)
- θ = bequest intensity parameter (calibrated to Lockwood 2012)
- κ = bequest shifter / luxury good parameter (ensures bequests are a luxury good; from Lockwood 2018)
- b = wealth at death (bequeathable assets only; annuity income ceases)

**Bequest calibration (from Lockwood 2012):**
- No bequest motive: θ = 0 → model predicts ~61% ownership
- Moderate bequests: θ calibrated to match bequest-to-wealth ratio of ~0.20 → model predicts ~10–15% ownership
- Strong bequests (Ameriks et al. 2011 parameterization): → model predicts ~0% ownership

**Discounting:**
- Exponential: β per period (baseline: 0.97)
- Extension: quasi-hyperbolic (β, δ) discounting following Laibson (1997) as robustness check

### 2.5 Health Dynamics and Mortality

**This is the critical innovation relative to Pashchenko (2013) and Peijnenburg et al. (2016).**

Health follows a first-order Markov process with three states {Good, Fair, Poor}. Transition probabilities are age-dependent and calibrated to HRS data:

```
Pr(H_{t+1} = h' | H_t = h, age = t) = π(h, h', t)
```

**Health-mortality correlation (Reichling-Smetters mechanism):**

Survival probability depends on current health status:

```
s(t, H_t) = base survival rate × health multiplier(H_t)
```

A negative health shock simultaneously:
1. Increases mortality (reduces expected remaining annuity payments)
2. Increases expected medical expenditures (raises marginal value of liquid wealth)
3. Reduces the value of the annuity (shorter expected payout horizon)

This correlation is what generates the Reichling-Smetters result: annuities become "valuation-risky" because they lose value precisely when liquid wealth is most needed.

**Key distinction:** Generic medical expense risk can actually increase annuity demand (longevity insurance covers old-age states with highest costs). The demand-suppressing result depends specifically on the correlation between health deterioration and both survival reduction and cost increases occurring simultaneously.

### 2.6 Medical Expenditure Process

Out-of-pocket medical expenditures depend on health status and age:

```
ln(m_{t+1}) = μ_m(t, H_t) + σ_m(t, H_t) × ε_{t+1}
```

Where ε is an i.i.d. shock. The distribution is right-skewed with heavy tails.

**Calibration targets (from Jones, De Nardi, French, McGee, and Kirschner 2018, in 2014 dollars):**
- Mean combined (OOP + Medicaid) at age 70: ~$5,100
- Mean combined at age 100: ~$29,700
- 95th percentile combined at age 100: ~$111,200
- OOP component at age 70: ~$4,200

**Medicaid / means-tested floor:**
- If liquid wealth falls below Medicaid threshold, government covers medical costs
- This creates the "public care aversion" mechanism (Ameriks et al. 2011): households retain liquid wealth to avoid Medicaid reliance
- Annuitizing converts liquid wealth to income, potentially accelerating Medicaid eligibility

### 2.7 Annuity Purchase Decision

At age 65 (entry), the individual chooses fraction α ∈ [0, 1] of initial liquid wealth W_0 to annuitize.

**Annuity pricing:**
- Annual payout per dollar of premium: calculated using annuitant mortality table and a discount rate
- Money's worth ratio (MWR): 0.80–0.85 against population mortality (Mitchell et al. 1999)
- The gap between population MWR and 1.0 reflects two components:
  - Adverse selection (~0.06–0.11 depending on age/sex): annuitant pool lives longer
  - Insurer expenses, reserves, profit (~0.06–0.09): operational costs
- Fixed cost of purchase: ~$500–$2,000 (Lockwood 2012 calibration)

**Annuity income stream:**
```
A = α × W_0 × payout_rate(age=65, MWR)
```

Once purchased, A is received each period conditional on survival. At death, remaining annuity value = 0 (no death benefit in baseline; period-certain as robustness check).

**Nominal vs. real distinction:**
- Baseline: nominal annuity with no COLA
- At 3% inflation, purchasing power falls ~45% by year 20
- Extension: real annuity with 25–30% lower initial payout (Brown, Mitchell, Poterba 2001, 2002)

### 2.8 Budget Constraint and Timing

Within each period, the sequence is:

1. Individual enters period with liquid wealth W_t, annuity income A, Social Security income SS(t), health H_t
2. Medical expenditure shock m_t is realized (depends on H_t and age)
3. Individual chooses consumption c_t
4. Remaining wealth earns risk-free return r (baseline: 2% real)
5. Health transitions to H_{t+1} with probability π(H_t, H_{t+1}, t)
6. Individual survives to t+1 with probability s(t, H_t)

```
W_{t+1} = (1 + r) × (W_t + A + SS(t) - m_t - c_t)
```

**Constraints:**
- c_t ≥ c_floor (minimum consumption floor, set to approximate Medicaid/SSI safety net)
- W_t ≥ 0 (no borrowing against future annuity or SS income)
- If W_t + A + SS(t) < m_t + c_floor, government covers the shortfall (Medicaid)

### 2.9 The Bellman Equation

```
V(W, A, H, t) = max_c { U(c) + β × s(t,H) × E[V(W', A, H', t+1) | H]
                        + β × (1 - s(t,H)) × V_bequest(W') }
```

Where:
- W' = (1+r)(W + A + SS(t) - m - c) is next-period liquid wealth
- The expectation is over next-period health H' and medical expenditure shock m
- V_bequest(W') = θ × (W' + κ)^(1-γ) / (1-γ) is the bequest value at death
- A enters as a state variable but is fixed after the age-65 purchase decision

**At age 65, the annuitization decision:**
```
α* = argmax_{α ∈ [0,1]} V(W_0(1-α), A(α), H_65, 65) - FixedCost × 1(α > 0)
```

Where A(α) = α × W_0 × payout_rate and the fixed cost applies only if any annuitization occurs.

---

## 3. COMPUTATIONAL ARCHITECTURE

### 3.1 Language and Framework

- **Language:** Julia (version 1.10+)
- **Why Julia:** Native speed comparable to C/Fortran without compilation complexity; strong linear algebra and interpolation libraries; QuantEcon ecosystem provides lifecycle model scaffolding; excellent parallelization support for parameter sweeps
- **Key packages:**
  - `QuantEcon.jl` — Markov chain tools, Tauchen's method
  - `Interpolations.jl` — value function interpolation on grids
  - `Distributions.jl` — probability distributions for shocks
  - `Optim.jl` — optimization for consumption choice
  - `DataFrames.jl` — data handling and calibration targets
  - `Plots.jl` or `Makie.jl` — visualization of policy functions
  - `CSV.jl` — I/O for calibration data
  - `Parameters.jl` — model parameter structs
  - `ProgressMeter.jl` — progress tracking for long computations

### 3.2 Solution Method

**Value Function Iteration (VFI) with backward induction:**

1. Start at maximum age T = 100
2. Terminal value: V(W, A, H, T) = U(c_T) + V_bequest(W_remaining) where c_T = W + A + SS(T) - m_T (consume everything)
3. For t = T-1 down to 65:
   a. For each grid point (W, A, H):
      - Solve for optimal consumption c* that maximizes the Bellman equation
      - Store V(W, A, H, t) and policy function c*(W, A, H, t)
   b. Interpolate value function for off-grid wealth values
4. At t = 65: solve for optimal annuitization fraction α* over a grid of α values

**Grid construction:**
- Wealth grid: nonuniform spacing with more points at low wealth levels (where the value function has more curvature)
- Suggested: use a power function mapping, e.g., W_i = W_max × (i/N)^2 for i = 0, ..., N
- Annuity income grid: uniform spacing from 0 to max feasible annuity income
- Health: discrete, no interpolation needed

**Interpolation:**
- Linear interpolation on wealth dimension (cubic if needed for accuracy)
- No interpolation needed on health (discrete) or age (solved at each integer age)

**Expectation computation:**
- Health transitions: discrete sum over 3 health states weighted by transition probabilities
- Medical expenditure shocks: Gauss-Hermite quadrature with 5–7 nodes (for lognormal shock)
- Combined: nested summation, 3 × 5 = 15 evaluation points per state

### 3.3 Computational Performance Estimates

- Single model solve (one parameterization): ~30 seconds to 2 minutes on Mac Studio
- Full parameter sweep (200 calibrations for robustness): ~2–6 hours
- Simulation of 100,000 lifecycle histories for moments: ~5–10 minutes per parameterization
- Total project computation: well within single-machine capacity

### 3.4 Code Organization

```
annuity-puzzle-model/
├── AGENTS.md                    # This file — project context
├── README.md                    # Academic project description
├── Project.toml                 # Julia project dependencies
├── Manifest.toml                # Julia dependency lock file
│
├── src/
│   ├── AnnuityPuzzle.jl         # Main module file
│   ├── parameters.jl            # Model parameter structs and defaults
│   ├── grids.jl                 # Grid construction for state space
│   ├── income.jl                # Social Security and DB pension income profiles
│   ├── health.jl                # Health transition matrices and mortality
│   ├── medical.jl               # Medical expenditure process
│   ├── annuity_pricing.jl       # Annuity payout rates and MWR calculations
│   ├── utility.jl               # Utility functions (consumption and bequest)
│   ├── bellman.jl               # Bellman equation and VFI solver
│   ├── annuitization.jl         # Age-65 annuitization decision solver
│   ├── simulation.jl            # Monte Carlo simulation of lifecycle paths
│   └── welfare.jl               # Welfare calculations (CEV, decomposition)
│
├── calibration/
│   ├── targets.jl               # Empirical moments to match
│   ├── lockwood_replication.jl  # Lockwood (2012) parameter recovery
│   ├── reichling_replication.jl # Reichling-Smetters (2015) parameter recovery
│   └── pashchenko_replication.jl# Pashchenko (2013) parameter recovery
│
├── experiments/
│   ├── baseline.jl              # Full model with all channels
│   ├── decomposition.jl         # Sequential channel decomposition
│   ├── robustness.jl            # Parameter sensitivity analysis
│   ├── heterogeneity.jl         # Welfare by household type
│   └── tables_figures.jl        # Generate all paper tables and figures
│
├── data/
│   ├── hrs_wealth_distribution.csv
│   ├── ss_benefit_profiles.csv
│   ├── health_transitions_hrs.csv
│   ├── medical_expenditure_profiles.csv
│   ├── mortality_tables.csv
│   └── annuity_quotes.csv
│
├── output/
│   ├── figures/
│   └── tables/
│
├── tests/
│   ├── test_bellman.jl          # Value function convergence tests
│   ├── test_replication.jl      # Reproduce published results
│   ├── test_limiting_cases.jl   # Analytical solutions for edge cases
│   └── test_simulation.jl       # Simulation validity checks
│
└── paper/
    ├── main.tex                 # LaTeX manuscript
    ├── appendix.tex             # Technical appendix
    └── figures/                 # Linked from output/figures/
```

---

## 4. VALIDATION STRATEGY

### 4.1 Rationale

Before running the novel unified model, we must demonstrate that our codebase reproduces published results from three independently verified papers. This serves two purposes: (1) building confidence that each model component is correctly implemented, and (2) providing a credibility signal to referees that the computational work is reliable.

### 4.2 Replication Target 1: Lockwood (2012)

**Paper:** "Bequest Motives and the Annuity Puzzle," *Review of Economic Dynamics* 15(2): 226–243.

**What to replicate:**
- Without bequest motives: predicted ownership ~61%, WTP ~25.3% of non-annuity wealth
- With moderate bequests: WTP collapses to ~3.7% for fair annuities, 0% for loaded annuities
- With moderate bequests + fixed purchase cost: predicted ownership ~4–5%
- Empirical target: observed ownership among single retirees 65–69 is ~3.6%

**How to replicate:**
- Set health to deterministic (no stochastic mortality — Lockwood doesn't have this)
- Set medical expenditures to zero or deterministic profile
- Use Lockwood's specific CRRA, discount rate, and bequest parameters
- Match his Social Security income calibration
- Compare predicted annuity ownership rates and WTP figures

**Key parameters from Lockwood (2012):**
- γ = 3 (CRRA)
- β = 0.97 (discount factor)
- Bequest parameters: θ and κ calibrated to HRS bequest data
- Annuity load: ~10–20% above actuarial fair value
- Fixed purchase cost: ~$500–$2,000

**Validation criterion:** Match Lockwood's key results within ±5 percentage points. Exact replication may not be possible due to differences in grid construction and interpolation, but the qualitative pattern (dramatic ownership decline with bequests) must be reproduced.

### 4.3 Replication Target 2: Reichling and Smetters (2015)

**Paper:** "Optimal Annuitization with Stochastic Mortality and Correlated Medical Costs," *American Economic Review* 105(11): 3273–3320.

**What to replicate:**
- Under deterministic mortality + no medical costs: full annuitization (Yaari result)
- Under stochastic mortality uncorrelated with costs: partial annuitization
- Under stochastic mortality correlated with medical costs: zero or negative optimal annuitization
- The key mechanism: health shock generates simultaneous survival reduction and expenditure increase

**How to replicate:**
- Set bequest motive to zero (Reichling-Smetters don't use bequests)
- Set annuity pricing to actuarially fair (MWR = 1.0)
- Implement their specific health-mortality correlation structure
- Compare optimal annuitization shares across correlation specifications

**Validation criterion:** Reproduce the sign reversal — positive annuitization under deterministic mortality, zero or negative under calibrated stochastic mortality with health-cost correlation.

### 4.4 Replication Target 3: Pashchenko (2013)

**Paper:** "Accounting for Non-Annuitization," *Journal of Public Economics* 98: 53–67.

**What to replicate:**
- Sequential decomposition: add channels one at a time, measure impact on predicted participation
- Four key channels: preannuitized wealth, minimum purchase requirement, illiquid housing, bequest motives
- Full model: ~20% predicted participation vs ~5% observed (the fourfold overprediction)

**How to replicate:**
- Match her model specification and calibration
- Run the same sequential decomposition exercise
- Confirm the ~20% prediction under her channels
- Then show that adding the channels she omitted (stochastic mortality, survival pessimism, full pricing wedge) closes the residual gap

**Validation criterion:** Approximate her reported participation rates under her assumptions. The overprediction under her channels becomes a feature, not a bug — it demonstrates exactly which omitted channels are needed.

### 4.5 Limiting Case Tests

In addition to full replications, verify the model against analytical solutions:

| Limiting Case | Expected Result | Tests |
|---|---|---|
| No mortality risk (certain lifespan) | No annuity value (mortality credit = 0) | Optimal α = 0 |
| No bequest motive + fair pricing + deterministic health | Full annuitization (Yaari) | Optimal α = 1 |
| Infinite bequest weight | Zero annuitization | Optimal α = 0 |
| Zero wealth (all SS income) | Zero annuitization (nothing to annuitize) | α = 0 trivially |
| No SS income + no bequests + fair pricing + deterministic health | Full annuitization | Optimal α = 1 |

These tests should be implemented as automated unit tests that run before any parameter sweep.

---

## 5. THE NOVEL CONTRIBUTION: UNIFIED MODEL AND DECOMPOSITION

### 5.1 The Decomposition Exercise

The core contribution is a sequential decomposition showing how each channel reduces predicted annuitization from the Yaari benchmark. The exercise proceeds as follows:

**Step 0 — Yaari Benchmark:**
- No bequests, deterministic health, fair pricing, no SS, no medical costs
- Expected result: 100% annuitization

**Step 1 — Add Pre-Existing Annuitization (Social Security):**
- Introduce SS income calibrated to wealth distribution
- Expected result: Substantial reduction (exact magnitude depends on wealth level)
- Mechanism: SS already provides longevity insurance; marginal value of additional annuitization is lower

**Step 2 — Add Bequest Motives:**
- Introduce θ and κ from Lockwood calibration
- Expected result: Large additional reduction (to ~10–15% without fixed cost)
- Mechanism: Annuitization forfeits bequeathable wealth

**Step 3 — Add Medical Expenditure Risk (without health-mortality correlation):**
- Introduce stochastic medical costs but keep survival probabilities health-independent
- Expected result: Ambiguous — may increase or decrease demand
- Mechanism: Medical costs raise value of liquidity, but longevity insurance covers high-cost states

**Step 4 — Add Health-Mortality Correlation (Reichling-Smetters):**
- Allow survival probabilities to depend on health status
- Expected result: Large additional reduction (to near zero for some parameterizations)
- Mechanism: Annuity loses value precisely when liquid wealth is most needed

**Step 5 — Add Realistic Pricing Loads:**
- Set MWR to 0.80–0.85 (population mortality) or 0.90–0.94 (annuitant mortality)
- Add fixed purchase cost
- Expected result: Further reduction; predicted ownership should be in 3–8% range
- Mechanism: Load eliminates small remaining surplus

**Step 6 — Add Inflation Erosion (nominal annuity):**
- Replace real annuity with nominal annuity losing purchasing power at 2–3% per year
- Expected result: Further reduction in welfare value
- Mechanism: Annuity provides weakest protection in late old age when costs are highest

### 5.2 Multiplicative Interaction Analysis

After the sequential decomposition, demonstrate that channels interact multiplicatively:

1. Compute predicted ownership with each channel in isolation
2. Compute predicted ownership with all channels combined
3. Show that the combined effect exceeds the sum of individual effects (multiplicative compounding)

**Concrete example to demonstrate:**
- Bequests alone: ownership drops from 100% to ~15%
- Loads alone: ownership drops from 100% to ~60%
- Bequests + loads together: ownership drops to ~4–5% (not 100% - 85% - 40% = -25%)

The interaction is economically intuitive: the load eliminates the small surplus that remained after accounting for bequests. A consumer barely willing to annuitize at fair pricing is driven decisively away by a 15% load.

### 5.3 The Key Table

**Table: Sequential Decomposition of Predicted Voluntary Annuity Ownership**

| Model Specification | Predicted Ownership (%) | Change from Previous |
|---|---|---|
| Yaari benchmark (no frictions) | 100 | — |
| + Pre-existing annuitization (SS) | [solve] | [compute] |
| + Bequest motives (Lockwood calibration) | [solve] | [compute] |
| + Medical expenditure risk (no correlation) | [solve] | [compute] |
| + Health-mortality correlation (R-S) | [solve] | [compute] |
| + Realistic pricing loads (MWR 0.82) | [solve] | [compute] |
| + Inflation erosion (nominal annuity) | [solve] | [compute] |
| **Observed (Lockwood 2012, single retirees 65–69)** | **~3.6** | — |

### 5.4 Heterogeneous Welfare Analysis

After establishing the aggregate result, compute welfare by household type:

**Dimensions of heterogeneity:**
- Wealth quartile (determines pre-existing annuitization share)
- Bequest motive (none, moderate, strong)
- Health status at age 65 (good, fair, poor)
- Marital status (single vs. married, if Phase 5 is implemented)

**Welfare metric:** Consumption-equivalent variation (CEV) — the percentage increase in consumption at all dates and states that would make the individual indifferent between having and not having access to the annuity market at realistic pricing.

**Expected pattern:**
- Low-wealth + strong bequests + poor health: CEV ≈ 0 (no welfare gain from annuitization)
- High-wealth + no bequests + good health + single: CEV > 0 (meaningful welfare gain)
- Most households: CEV small or zero (consistent with rational non-purchase)
- Key subpopulation (single, healthy, wealthy, low bequest): CEV potentially 5–15% of consumption

This identifies the specific group for whom under-annuitization is a welfare problem — the "heterogeneous welfare question" that the companion survey argues should replace the aggregate puzzle framing.

---

## 6. PHASED BUILD PLAN

### Phase 1: Foundation (Weeks 1–3)

**Goal:** Set up project infrastructure, implement core model components, verify basic functionality.

**Tasks:**
1. Initialize Julia project with all dependencies
2. Implement parameter struct with all model parameters and sensible defaults
3. Build wealth grid (nonuniform) and annuity income grid
4. Implement CRRA utility function and bequest utility function
5. Implement Social Security income profiles by wealth quartile
6. Implement basic (deterministic) mortality table
7. Write terminal value function at age T = 100
8. Implement one-period Bellman equation (no health, no medical costs)
9. Implement full backward induction loop
10. Verify: solve Yaari benchmark (no bequests, fair pricing, deterministic) → confirm 100% annuitization

**Validation tests:**
- Yaari benchmark produces α* = 1
- Value function is monotonically increasing in wealth
- Policy function (consumption) is monotonically increasing in wealth
- Euler equation residuals are small (< 1% of consumption)

### Phase 2: Lockwood Replication (Weeks 3–5)

**Goal:** Add bequest motives, replicate Lockwood (2012) results.

**Tasks:**
1. Add bequest utility V(b) = θ(b + κ)^(1-γ)/(1-γ) to the Bellman equation
2. Implement annuity pricing with realistic loads (MWR = 0.82)
3. Add fixed purchase cost for annuitization
4. Calibrate bequest parameters θ, κ to match HRS bequest data
5. Run model without bequests → verify ~61% ownership, ~25% WTP
6. Run model with moderate bequests → verify WTP collapse to ~3.7%
7. Run model with bequests + fixed cost → verify ~4–5% ownership
8. Generate comparison table matching Lockwood's Table 2

**Validation tests:**
- WTP declines monotonically with bequest intensity θ
- Ownership rate matches Lockwood within ±5 pp
- Qualitative pattern (dramatic collapse with bequests) is robust to grid density

### Phase 3: Health and Medical Expenditures (Weeks 5–8)

**Goal:** Add stochastic health, medical expenditures, and mortality correlation. Replicate Reichling-Smetters (2015) result.

**Tasks:**
1. Implement 3-state health Markov transition matrix (calibrated to HRS)
2. Implement age- and health-dependent survival probabilities
3. Implement lognormal medical expenditure process (age- and health-dependent)
4. Implement Gauss-Hermite quadrature for expenditure shock expectations
5. Implement Medicaid floor (means-tested safety net)
6. Expand Bellman equation to include health state and medical shocks
7. Re-solve backward induction with expanded state space
8. Test without health-mortality correlation → verify medical costs alone have ambiguous effect
9. Add health-mortality correlation → verify demand drops to zero or negative (R-S result)
10. Replicate R-S key result: sign reversal under correlated stochastic mortality

**Validation tests:**
- Under deterministic health + no medical costs: recovers Phase 1 results exactly
- Under stochastic health without correlation: demand may increase (longevity insurance for high-cost states)
- Under calibrated correlation: demand drops to zero (R-S mechanism)
- Medical expenditure profiles match Jones et al. (2018) moments
- Precautionary saving patterns match De Nardi, French, and Jones (2010) qualitatively

### Phase 4: Full Model and Decomposition (Weeks 8–12)

**Goal:** Run the unified model with all channels. Perform sequential decomposition. Generate the key results table.

**Tasks:**
1. Combine all components into unified model
2. Implement annuity pricing with nominal payment stream (inflation erosion)
3. Run full model → compute predicted ownership rate
4. Implement sequential decomposition loop (add channels one at a time)
5. Compute multiplicative interaction metrics
6. Generate Table 1: sequential decomposition results
7. Run Monte Carlo simulations (100,000 histories) for distributional moments
8. Compare simulated wealth decumulation profiles to HRS data
9. Compare simulated bequest distribution to observed data
10. Robustness: vary γ, β, θ, MWR, correlation strength across reasonable ranges

**Validation tests:**
- Full model predicts ownership in 3–8% range across parameterizations
- No parameterization in the empirically plausible range predicts ownership above 15%
- Multiplicative interaction: combined effect exceeds sum of individual effects
- Simulated moments (wealth profiles, bequest distribution) broadly match data

### Phase 5: Welfare Analysis and Extensions (Weeks 12–16)

**Goal:** Compute heterogeneous welfare effects. Generate the welfare map. Prepare all tables and figures for the paper.

**Tasks:**
1. Implement CEV welfare calculation (consumption-equivalent variation)
2. Compute CEV for each cell of the heterogeneity matrix (wealth × bequest × health)
3. Identify the subpopulation with CEV > 0 (welfare gain from annuitization)
4. Quantify the welfare stakes for this subpopulation
5. Generate Figure: welfare heat map across household types
6. Generate Figure: policy functions (consumption and annuitization) by household type
7. Generate Figure: simulated wealth paths with and without annuitization access
8. Optional: add marital status as fifth state variable
9. Optional: implement DIA/QLAC product (deferred annuity starting at age 80/85)
10. Final robustness checks and sensitivity analysis

**Key outputs:**
- Table: CEV by household type (the "heterogeneous welfare map")
- Table: Sequential decomposition (the core contribution)
- Figure: Policy functions showing annuitization decision by wealth and bequest motive
- Figure: Simulated wealth trajectories under full model
- Figure: Sensitivity of predicted ownership to key parameters

### Phase 6: Paper Writing (Weeks 14–20, overlapping with Phase 5)

**Goal:** Write the AER/JPE manuscript.

**Structure:**
1. Introduction: Frame the puzzle, state the contribution, preview results
2. Model: Full specification (this document is the blueprint)
3. Calibration: Data sources, parameter values, moment targets
4. Validation: Lockwood, R-S, and Pashchenko replications
5. Results: Sequential decomposition and multiplicative interactions
6. Heterogeneous welfare: The welfare map
7. Robustness: Parameter sensitivity
8. Conclusion: Retire the puzzle, redirect research toward heterogeneous welfare question

---

## 7. DATA REQUIREMENTS, OPEN-SOURCE RESOURCES, AND ASSEMBLY STRATEGY

This section catalogs everything available for free academic use — replication packages, open-source code, public data, and published calibrations — and specifies the practical assembly strategy. The infrastructure cost for this project is essentially zero.

### 7.1 Available Replication Packages

These are the most valuable accelerants for the project. Study them before writing any code.

**Reichling and Smetters (2015, AER) — AVAILABLE**
- Location: AEA openICPSR repository (https://www.openicpsr.org/openicpsr/project/116152/version/V1/view)
- Contents: Full replication code and data for "Optimal Annuitization with Stochastic Mortality and Correlated Medical Costs"
- Language: Likely Fortran or Matlab (AER standard for that era)
- Value: This is the single most important resource. Contains the exact health-mortality correlation specification, stochastic survival calibration, medical cost process, and numerical solution approach. Even though we reimplement in Julia, studying their code resolves ambiguities in the paper about grid construction, boundary conditions, convergence criteria, and interpolation choices that are never fully described in print.
- Priority: **Download and study FIRST, before writing any model code.**

**De Nardi, French, and Jones (2016, AER) — AVAILABLE**
- Location: AEA openICPSR repository (https://www.openicpsr.org/openicpsr/project/112971/version/V1/view)
- Contents: Replication data and code for "Medicaid Insurance in Old Age"
- Value: Uses the same health-expenditure lifecycle framework as their foundational 2010 JPE paper ("Why Do the Elderly Save?"). Contains health transition matrices, medical expenditure calibration by age and health state, Medicaid floor modeling, and bequest distribution targets. Directly provides the medical expenditure process and health dynamics we need for Phases 3–4.

**Lockwood (2012, RED) — NOT PUBLICLY AVAILABLE**
- Review of Economic Dynamics did not require replication packages at time of publication.
- Mitigation: The model is the simplest of our three replication targets (no stochastic health). Paper describes specification precisely enough to implement from text. Consider emailing Lockwood directly — computational economists frequently share code on request.

**Pashchenko (2013, JPubE) — NOT PUBLICLY AVAILABLE**
- No public code repository found.
- Mitigation: Her paper describes the model in sufficient detail. She has a 2025 working paper with Porapakkarm ("Saving Motives over the Life-Cycle") and a 2024 IER paper on Social Security claiming — reaching out for code on the annuity model is reasonable. She is at the University of Georgia.

### 7.2 Open-Source Computational Infrastructure

**QuantEcon.jl (BSD-3 license, free)**
- Repository: https://github.com/QuantEcon/QuantEcon.jl
- Provides: Markov chain tools, Tauchen's method for discretizing AR(1) processes, DiscreteDP solver (value function iteration, policy function iteration, modified policy iteration), grid construction utilities (gridmake), simulation tools, random variable generation.
- Use: Foundation layer. Do NOT reimplement Tauchen's method, Markov chain simulation, or basic DP solvers from scratch — use QuantEcon's tested implementations.

**Julia-LifeCycleModel (GitHub: pedm/Julia-LifeCycleModel)**
- Repository: https://github.com/pedm/Julia-LifeCycleModel
- Contents: Working Julia implementation of a lifecycle consumption-saving model with stochastic income, solved by value function iteration. Based on Costa Dias and O'Dea's "Dynamic Economics in Practice" course.
- Value: A concrete, working Julia codebase for finite-horizon backward induction with one state variable. Use as a code skeleton for Phase 1, then extend with additional state variables (annuity income, health) in subsequent phases.
- Limitation: Much simpler than our target model (no health, no annuity choice, no bequests). It's a starting scaffold, not a near-complete solution.

**QuantEcon Lecture Series (https://julia.quantecon.org/)**
- All lecture source code is open and available on GitHub.
- Relevant lectures: Optimal Growth (value function iteration), LQ Dynamic Programming, Job Search, Income Fluctuation Problem.
- Value: Working examples of VFI, interpolation, Monte Carlo simulation, and policy function analysis in Julia. Reference implementations when debugging.

**Additional Julia Packages (all free, open-source):**
- Interpolations.jl — linear and cubic interpolation on grids
- Distributions.jl — lognormal medical expenditure draws, Gauss-Hermite quadrature nodes
- Optim.jl — consumption optimization within each Bellman step
- Parameters.jl — @with_kw macro for parameter structs with defaults
- Plots.jl / Makie.jl — publication-quality figures

**Benjamin Moll's Teaching Code (Princeton)**
- Lifecycle model implementations with Julia and parallel computing examples.
- Useful reference for scaling to larger state spaces with multi-threading.

### 7.3 Public Data Sources

**RAND HRS Longitudinal File — ALREADY IN HAND**
- Derek has the RAND HRS files ready to provide.
- This is the primary calibration dataset. Cleaned, consistently named across waves (1992–2022), with imputations for income, assets, and medical expenditures. Covers health transitions, wealth distribution, bequest motives, Social Security income, and annuity ownership.
- Use for: wealth distribution at retirement by quartile, health transition matrices (self-reported health across waves), mortality by health status, bequest distributions (exit interviews), annuity ownership rates, medical expenditure profiles.

**HRS Public Survey Data (free with account, https://hrsdata.isr.umich.edu/)**
- Core interview data, exit interviews, and cross-wave products.
- Supplementary to the RAND file for variables not included in the cleaned longitudinal product.
- Note: Restricted data (linked SSA earnings, Medicare claims) requires separate application but is NOT needed for this project — published calibrations from prior papers suffice.

**SSA Annual Statistical Supplement (free, public)**
- Available at: https://www.ssa.gov/policy/docs/statcomps/supplement/
- Provides: Average monthly benefit by age, sex, and claiming age.
- Use for: Calibrating the pre-existing annuitization component (Social Security income profiles).

**Society of Actuaries Mortality Tables (free, public)**
- Period and cohort life tables for annuity pricing calculations.
- Use for: Computing actuarially fair annuity prices and MWR under population vs. annuitant mortality.

**Jones et al. (2018) — Published Moments (open access)**
- Federal Reserve Bank of Richmond Economic Quarterly article — freely available online.
- Medical expenditure calibration targets published directly in the paper: mean OOP spending by age and health, variance, 95th percentile.
- Key numbers: Mean $5,100 at age 70 rising to $29,700 at age 100; 95th percentile $111,200 at age 100.
- Use for: Calibrating the medical expenditure process WITHOUT needing to access MEPS microdata.

**Mitchell et al. (1999, AER) — Published MWR Estimates**
- Money's Worth Ratio estimates by age and sex published in the paper.
- Use for: Calibrating annuity pricing loads (MWR 0.80–0.85).

**Wettstein et al. (2021) — CRR Working Paper (free)**
- Center for Retirement Research at Boston College.
- Updated MWR estimates with more recent market data.

### 7.4 Calibration Data Summary

| Data Need | Source | Status |
|---|---|---|
| Wealth distribution at retirement | RAND HRS Longitudinal File | **In hand** |
| Social Security benefit profiles | SSA Annual Statistical Supplement | Free, public |
| Health transitions | RAND HRS + De Nardi-French-Jones replication | **In hand** + openICPSR |
| Mortality by health status | RAND HRS + Reichling-Smetters replication | **In hand** + openICPSR |
| Medical expenditures | Jones et al. (2018) published moments | Free, open access |
| Bequest distribution | RAND HRS exit interviews | **In hand** |
| Annuity ownership | RAND HRS | **In hand** |
| Annuity pricing / MWR | Mitchell et al. (1999), Wettstein et al. (2021) | Published / free working paper |

### 7.5 Published Calibrations to Borrow

Several parameter values can be taken directly from published papers rather than independently estimated:

- **Bequest parameters (θ, κ):** Lockwood (2012), Table 1
- **Medical expenditure process:** Jones et al. (2018), Table 2
- **Health transitions:** De Nardi, French, and Jones (2010), Table A1; also available in their 2016 AER replication package
- **Health-mortality correlation:** Reichling and Smetters (2015), available in their AER replication package
- **Annuity pricing loads:** Mitchell et al. (1999), Table 2; Wettstein et al. (2021)
- **Risk aversion and discount factor:** Standard values (γ = 3, β = 0.97) with robustness

### 7.6 Practical Assembly Strategy

The build sequence leverages available resources to minimize redundant implementation:

**Step 1: Download and study replication packages (before writing code)**
- Pull Reichling-Smetters from openICPSR. Read their code for health-mortality specification, grid choices, convergence criteria.
- Pull De Nardi-French-Jones from openICPSR. Extract health transition matrices and medical expenditure calibration.
- These two packages contain the hardest-to-replicate components of the model.

**Step 2: Set up Julia project with open-source foundation**
- Install QuantEcon.jl, Interpolations.jl, Distributions.jl, Optim.jl.
- Clone Julia-LifeCycleModel as reference for code structure and backward induction pattern.
- Do NOT reimplement Tauchen's method, Markov chain tools, or basic DP solvers — use QuantEcon's tested implementations.

**Step 3: Build Phase 1 (Yaari benchmark) by extending the lifecycle model skeleton**
- Adapt Julia-LifeCycleModel's backward induction structure to include annuity choice.
- Add QuantEcon.jl's grid and interpolation tools.
- Verify Yaari benchmark (α* = 1) before proceeding.

**Step 4: Calibrate from RAND HRS + published moments**
- Use RAND HRS (in hand) for wealth distribution, health transitions, bequest targets, annuity ownership rates.
- Use Jones et al. (2018) published moments for medical expenditures.
- Use Lockwood (2012) published parameters for bequest utility.
- Use Mitchell et al. (1999) / Wettstein et al. (2021) for annuity pricing.

**Step 5: Validate replications against published results**
- Lockwood: match his Table results (no public code — implement from paper).
- Reichling-Smetters: match their key results AND cross-check against their replication code.
- Pashchenko: match her ~20% prediction (no public code — implement from paper).

### 7.7 What Is NOT Available

For completeness, these are the gaps:

- **No unified Julia codebase** combining all channels. The existing Julia lifecycle models are teaching-level (1–2 state variables, simple income, no health). The gap between those and a 4-dimensional state space with health-mortality correlation is real, but it's an extension gap, not a build-from-scratch gap.
- **Lockwood and Pashchenko code** not publicly available. Replications from those papers require implementation from published descriptions. Both papers are precise enough to implement, but you cannot do exact numerical verification against unpublished intermediate outputs.
- **No one has published the sequential decomposition.** The core novel contribution — adding channels one at a time and measuring multiplicative interactions — has no precedent to verify against. This is the paper's original contribution and must be validated by internal consistency checks (limiting cases, monotonicity, economic intuitions in Section 8).

---

## 8. KEY ECONOMIC INTUITIONS TO VERIFY

When reviewing model output, check that these economic intuitions hold. If they don't, there is likely a bug.

### 8.1 Annuitization Should Increase With:
- Wealth (up to a point — at very high wealth, bequest motive as luxury good dominates)
- Risk aversion (higher γ → more insurance demand)
- Better health at age 65 (longer expected payout horizon)
- Lower bequest motive
- Higher MWR (better pricing)
- Higher SS replacement rate should DECREASE additional annuitization (already insured)

### 8.2 Annuitization Should Decrease With:
- Bequest intensity (θ)
- Medical expenditure variance (more precautionary saving)
- Health-mortality correlation strength (R-S mechanism)
- Pricing load (lower MWR)
- Pre-existing annuity income level (diminishing marginal insurance value)
- Inflation rate (if annuity is nominal)

### 8.3 Red Flags (Likely Bugs)
- Optimal annuitization > 0 when bequest weight is very large
- Consumption declining with wealth at any age
- Value function non-monotone in wealth
- Predicted ownership above 20% in the full model
- Predicted ownership of exactly 0% when bequests are zero and pricing is fair (should be 100%)
- Medical expenditure having no effect on wealth decumulation profiles
- Identical policy functions across health states when health-mortality correlation is active

---

## 9. RELATIONSHIP TO COMPANION SURVEY PAPER

### 9.1 The Two-Paper Strategy

| | Survey Paper (JES) | Modeling Paper (AER/JPE Target) |
|---|---|---|
| **Title** | "Dissolving the Annuity Puzzle: A Critical Survey" | "Dissolving the Annuity Puzzle: A Unified Lifecycle Model" (working title) |
| **Contribution** | Qualitative argument that accumulated evidence dissolves the puzzle | Quantitative proof within a single framework |
| **Method** | Literature synthesis across modeling frameworks | Calibrated structural lifecycle model |
| **Key result** | Multiple channels jointly rationalize low observed demand | Sequential decomposition showing multiplicative interaction |
| **Novel element** | Cross-framework synthesis, evolutionary psychology, cross-cultural evidence | First model nesting all major channels simultaneously |
| **The survey says** | "Resolution requires structural models incorporating all channels" | "Here is that model" |

### 9.2 How to Frame the Modeling Paper's Introduction

The introduction should cite the survey as motivation:

> "Tharp (forthcoming) argued that the accumulated evidence from six decades of research substantially dissolves the aggregate annuity puzzle for classic immediate life annuities, but identified the absence of a unified structural model incorporating all empirically relevant channels as the key gap preventing definitive resolution. This paper fills that gap."

This framing:
- Establishes the intellectual lineage
- Makes clear the modeling paper's contribution is distinct from the survey
- Signals a coherent research program
- Gives the referee the survey as a reference for the broader literature, allowing the modeling paper to focus tightly on the model and results

---

## 10. GLOSSARY OF KEY TERMS

| Term | Definition |
|---|---|
| **SPIA** | Single Premium Immediate Annuity — converts lump sum to lifelong income stream |
| **DIA** | Deferred Income Annuity — income begins at a future age (e.g., 80 or 85) |
| **QLAC** | Qualified Longevity Annuity Contract — DIA within a tax-advantaged retirement account |
| **MWR** | Money's Worth Ratio — expected present value of annuity payouts per dollar of premium |
| **Mortality credit** | The return premium on annuities financed by redistributing wealth from those who die to survivors |
| **VFI** | Value Function Iteration — backward induction algorithm for solving dynamic programming problems |
| **CEV** | Consumption-Equivalent Variation — welfare metric measuring % consumption increase to achieve indifference |
| **CRRA** | Constant Relative Risk Aversion utility: U(c) = c^(1-γ)/(1-γ) |
| **HRS** | Health and Retirement Study — primary US panel survey of older Americans |
| **SCF** | Survey of Consumer Finances — Federal Reserve triennial household survey |
| **MEPS** | Medical Expenditure Panel Survey — AHRQ survey of health costs |
| **CPT** | Cumulative Prospect Theory (Tversky and Kahneman 1992) |
| **Tauchen's method** | Algorithm for discretizing continuous AR(1) processes into Markov chains |
| **Gauss-Hermite quadrature** | Numerical integration method for expectations over normal/lognormal distributions |
| **Euler equation residual** | Error from the intertemporal optimality condition; measures solution accuracy |

---

## 11. IMPLEMENTATION NOTES FOR Codex

### 11.1 Working Style

- This is a computational economics project, not a web app. Correctness matters more than speed.
- Always verify economic intuition before moving to the next component. If a result seems wrong, it probably is.
- When in doubt about a numerical method, implement the simpler version first and verify, then optimize.
- Comment the code with economic intuition, not just computational logic. A future reader (including referees reviewing the replication package) needs to understand WHY each step exists.

### 11.2 Hardware and Development Environment

The project is designed to be **developed and tested on any modern laptop** (MacBook Air, etc.) without requiring the Mac Studio until late-stage production runs.

**What runs fine on a laptop:**
- Phase 1 (Yaari benchmark, 1 state variable): solves in seconds
- Phase 2 (Lockwood, 2 state variables): solves in seconds to low minutes
- Phase 3 (health + medical, 3-4 state variables): single solve in 30 sec to 2 min
- Phase 4 (full model, single parameterization): 1-3 min per solve
- Limiting case tests and unit tests: all trivial
- Small Monte Carlo runs (1K-10K histories): minutes

**What benefits from Mac Studio (or can be batched overnight on laptop):**
- Large parameter sweeps (200+ calibrations for robustness tables): 2-6 hours
- Full Monte Carlo simulation (100K histories x many parameterizations): hours
- Grid convergence checks (doubling grid points repeatedly): multiplicative time cost
- Final production runs for all paper tables and figures

**Development strategy:** Build, debug, and validate everything through Phase 4 on whatever hardware is available. Use coarse grids (e.g., 30 wealth points instead of 100) during development for fast iteration. Run a grid convergence check periodically to confirm coarse-grid results are qualitatively correct. Save production-quality runs (fine grids, full sweeps, large simulations) for the Mac Studio or overnight batch jobs.

**Practical implication for code:** Always parameterize grid sizes in the config file. Never hardcode grid dimensions. The same codebase should run a 2-minute development solve and a 2-hour production solve by changing a single config setting.

### 11.3 Writing and Coding Standards: No AI Fingerprints

This project uses AI coding tools, but the final code and manuscript must read as if written by a competent human researcher. Reviewers and editors are increasingly attuned to AI-generated content, and obvious tells will damage credibility. Codex must follow these rules strictly.

**Code comments and docstrings:**
- Write comments the way an experienced computational economist would: terse, precise, referencing the relevant equation or paper. Example: `# Bellman eq. (7) from Lockwood (2012)` not `# This elegantly computes the optimal value function using dynamic programming`
- No superlatives or evaluative language in comments. Never write "crucial," "elegant," "key insight," "importantly," or "note that" in code comments.
- No meta-commentary about what the code is doing at a high level unless it's a module-level docstring. Comments explain the non-obvious, not the obvious.
- Variable names should follow economics conventions: `V` for value function, `c_star` for optimal consumption, `alpha_star` for optimal annuity share, `beta` for discount factor, `gamma` for risk aversion, `theta` for bequest weight, `kappa` for bequest curvature. Not `optimal_consumption_policy` or `bequest_utility_weight_parameter`.
- No comments that reference AI, machine learning, Codex, or any AI tool. No `# Generated by Codex` headers. No `# AI-assisted implementation` notes. The code should be indistinguishable from code written in a text editor.

**Prose (docstrings, README, paper drafts):**
- Avoid excessive em dashes. Use them sparingly (once or twice per paragraph maximum). Prefer commas, semicolons, colons, or separate sentences.
- Avoid the word "straightforward." Avoid "notably," "crucially," "importantly," "it's worth noting," "it bears mentioning," and similar throat-clearing.
- Do not begin paragraphs or sections with "In this section, we..." or "Here, we..." Just state what is being done.
- Vary sentence length. AI prose tends toward uniform medium-length sentences. Mix short declarative sentences with longer complex ones.
- Use the specific over the general. "The value function is concave in wealth" not "The results exhibit the expected mathematical properties."
- When describing results, be direct and quantitative. "Predicted ownership falls from 61% to 4.3%" not "We observe a substantial reduction in predicted annuity demand."
- Match the rhetorical conventions of the target journal. AER papers are precise and understated. They do not use exclamation points, do not editorialize about the importance of their own results, and trust the reader to recognize significance.

**Commit messages and documentation:**
- Write commit messages in standard terse style: `Add bequest utility to Bellman equation`, `Fix boundary condition at W=0`, `Replicate Lockwood Table 3`. Not `Implement an elegant bequest utility function that captures the luxury good nature of bequests`.
- README should be written in the clipped, functional style of economics replication packages. See AEA Data Editor guidelines for formatting conventions.

### 11.4 Replication Package Standards

The codebase must ship as a polished, publication-ready replication package from day one. This is not cleanup done at the end; it is a design constraint on every line of code. Top journals (AER, JPE, QJE) now evaluate replication packages seriously via the AEA Data Editor, and a clean package signals computational competence to referees.

**No hardcoded values in computation code:**
- ALL model parameters live in a single config file (e.g., `config/baseline.toml` or a Julia `Parameters` struct in `src/parameters.jl`).
- No magic numbers anywhere in the solution, simulation, or analysis code. Every numerical value traces back to the config file or a calibration target with a citation.
- Grid sizes, convergence tolerances, quadrature nodes, simulation draw counts: all in config.
- Calibration targets (e.g., "Lockwood Table 1 reports theta = 2.3") should be stored in a calibration targets file with the citation, not scattered through code.
- Exception: mathematical constants (pi, euler's number) and structural zeros/ones in matrix construction are fine inline.

**Automated pipeline (raw data to final output):**
- A single master script (e.g., `run_all.jl` or `Makefile`) reproduces every table and figure in the paper from raw inputs.
- Pipeline stages: (1) process raw data and calibration targets, (2) solve model for each specification, (3) run simulations, (4) generate tables and figures, (5) compile LaTeX.
- Each stage reads from the previous stage's output directory and writes to its own. No circular dependencies.
- Intermediate results saved to disk so individual stages can be re-run without starting from scratch.

**Directory structure:**

```
AnnuityPuzzle/
  config/
    baseline.toml           # All model parameters, grid sizes, tolerances
    lockwood.toml           # Lockwood replication parameters
    reichling_smetters.toml # R-S replication parameters
    robustness/             # Parameter variations for sensitivity tables
  src/
    parameters.jl           # Parameter struct, load from config
    grids.jl                # Grid construction (wealth, annuity, health)
    utility.jl              # CRRA utility, bequest utility
    income.jl               # Social Security, pension income
    health.jl               # Health transitions, mortality, medical costs
    annuity.jl              # Annuity pricing, MWR calculation
    bellman.jl              # Bellman equation, one-period problem
    solve.jl                # Full backward induction solver
    simulate.jl             # Monte Carlo forward simulation
    welfare.jl              # CEV calculation
    decomposition.jl        # Sequential channel decomposition
  test/
    test_utility.jl         # Unit tests for utility functions
    test_limiting_cases.jl  # Yaari benchmark, infinite bequest, etc.
    test_lockwood.jl        # Lockwood replication targets
    test_rs.jl              # Reichling-Smetters replication targets
    test_grid_convergence.jl
  data/
    raw/                    # RAND HRS files, SSA tables (gitignored if large)
    processed/              # Cleaned calibration inputs
    calibration_targets.jl  # Published moments with citations
  results/
    baseline/               # Output from baseline specification
    lockwood/               # Lockwood replication output
    reichling_smetters/     # R-S replication output
    decomposition/          # Sequential decomposition results
    robustness/             # Sensitivity analysis output
  figures/
    pdf/                    # Publication-quality vector figures
    png/                    # Quick-inspection raster figures
  tables/
    tex/                    # LaTeX-formatted tables
    csv/                    # Machine-readable tables
  paper/
    main.tex                # Manuscript
    bibliography.bib
  README.md                 # Reproduction instructions
  run_all.jl                # Master pipeline script
  Project.toml              # Julia dependencies with exact versions
  Manifest.toml             # Julia lockfile (exact reproducibility)
```

**Dependency management:**
- Pin all Julia package versions in `Manifest.toml`. The replication package must produce identical results on any machine with the same Julia version.
- Specify the exact Julia version in README (e.g., "Julia 1.10.4").
- No dependencies on system-specific paths. Use `joinpath` and `@__DIR__` for all file paths.

**Reproducibility checks:**
- Set random seeds explicitly for all stochastic components (Monte Carlo simulation, bootstrap standard errors). Document seeds in config.
- Results should be bitwise reproducible given the same Julia version, package versions, and random seeds.
- Include a `test/test_reproducibility.jl` that runs a small-scale version of the full pipeline and checks output against stored reference values.

**README requirements (following AEA Data Editor guidelines):**
- System requirements (Julia version, OS tested on, RAM, approximate runtime)
- Data availability statement (which data is public, how to obtain it, any access restrictions)
- Step-by-step instructions to reproduce all results
- Expected output description
- Contact information

### 11.5 Common Pitfalls in Lifecycle Models

- **Interpolation at boundaries:** Value function interpolation near W = 0 can produce artifacts. Use a minimum wealth floor slightly above zero.
- **Convergence criteria:** VFI converges when the maximum absolute change in the value function across all grid points falls below tolerance (e.g., 1e-8). Don't use relative tolerance alone; it can produce false convergence at low wealth levels.
- **Consumption bounds:** Optimal consumption must satisfy c >= c_floor and c <= W + A + SS - m (can't consume more than available resources net of medical costs). Handle corner solutions explicitly.
- **Negative wealth:** If medical costs exceed income + wealth, the government (Medicaid) covers the shortfall. Implement a smooth transition or hard floor to avoid numerical issues.
- **Grid density sensitivity:** Always check that results are stable to doubling the number of grid points on the wealth dimension. If results change substantially, the grid is too coarse.

### 11.6 Testing Protocol

For each phase:
1. Write the component
2. Write unit tests for that component
3. Run limiting case tests (Section 4.5)
4. Check economic intuitions (Section 8)
5. If replicating a published paper, compare quantitative results
6. Only then proceed to the next phase

### 11.7 Output Standards

All figures should be publication-quality:
- Font size >= 10pt
- Clear axis labels with units
- Legends when multiple series
- Save as both .pdf (for LaTeX) and .png (for quick inspection)
- Use colorblind-friendly palettes

All tables should include:
- Clear column headers
- Standard errors or confidence intervals where relevant
- Notes explaining the specification
- Save as both .tex (for LaTeX) and .csv (for data inspection)

### 11.8 Versioning and Folder Hygiene

The project uses version numbers for manuscript revisions. When a draft is superseded, archive the old version to keep the working directories clean.

**Version numbering:**
- v0.1, v0.2, v0.3, etc. for major drafts
- Archive format: `archive/v{X.Y}-{short-description}/`
- Each archive contains: manuscript files, compiled PDFs, figures, tables, and a `VERSION_NOTES.md` explaining why the version was archived

**Archive protocol:**
- Before beginning a revision that will change results or manuscript structure, copy the current `paper/`, `figures/`, and `tables/` contents into `archive/v{current}/`
- The working `paper/`, `figures/`, and `tables/` directories always contain the *current* version only
- Do not accumulate old drafts, superseded figures, or stale tables in the working directories
- Intermediate outputs (`.aux`, `.log`, `.blg`, `.out` files) do not need to be archived
- The `archive/` directory is append-only; never delete or modify archived versions

**Current version:** v0.2 (revision addressing internal peer review)
**Archived:** v0.1 (initial draft, Feb 28, 2026)

---

## 12. REFERENCES (KEY PAPERS FOR IMPLEMENTATION)

These are the papers to consult for specific implementation details. The full reference list is in the companion survey.

1. **Yaari (1965)** — The benchmark to replicate as limiting case
2. **Lockwood (2012)** — Bequest calibration, ownership prediction methodology, WTP calculation
3. **Lockwood (2018)** — Bequest as luxury good parameterization
4. **Reichling and Smetters (2015)** — Health-mortality correlation mechanism, stochastic mortality implementation
5. **De Nardi, French, and Jones (2010)** — Health transitions, medical expenditure process, precautionary saving
6. **Jones et al. (2018)** — Medical expenditure calibration targets by age
7. **Mitchell et al. (1999)** — Annuity pricing, MWR calculation methodology
8. **Wettstein et al. (2021)** — Updated MWR estimates, socioeconomic heterogeneity in pricing
9. **Pashchenko (2013)** — Sequential decomposition methodology, channel interaction
10. **Ameriks et al. (2011)** — Public care aversion calibration, strategic survey methodology
11. **Hu and Scott (2007)** — CPT reservation price calculation (for behavioral extension)
12. **Davidoff, Brown, and Diamond (2005)** — Complete markets result, partial annuitization under incomplete markets
