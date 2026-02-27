# Calibration Log: Parameter Choices and Justifications

Every parameter change from the Phase 1 defaults is documented here with
its justification and source. This log serves as the audit trail for the
paper's calibration table and replication package.

---

## Baseline Defaults (Phase 1)

| Parameter | Value | Source | Notes |
|-----------|-------|--------|-------|
| gamma | 3.0 | Standard | CRRA; range tested 1.5-5.0 |
| beta | 0.97 | Standard | Annual discount factor |
| theta | 0.0 | — | No bequest motive (Yaari benchmark) |
| kappa | 0.0 | — | No bequest shifter |
| r | 0.02 | Standard | Real risk-free rate |
| age_start | 65 | Standard | Retirement entry |
| age_end | 100 | Standard | Maximum lifespan |
| c_floor | 3,000 | Approximate | SSI/Medicaid floor |
| mwr | 1.0 | Yaari (1965) | Actuarially fair |
| n_wealth | 50 | Development | Production: 100 |
| n_annuity | 15 | Development | Production: 25+ |
| W_max | 1,000,000 | Approximate | |
| medical_sigma | 1.4 | Jones et al. (2018) | Matches P95 at age 100 |
| medical_mu_base | 7.037 | Jones et al. (2018) | E[m]=exp(mu+sigma^2/2)=$3,032 at age 65 |
| medical_mu_growth | 0.0652 | Jones et al. (2018) | Age 70 Fair: $4,201, Age 100 Fair: $29,703 |
| hazard_mult | [0.6, 1.0, 2.0] | Reichling-Smetters (2015) | s_adj = s_base^mult for [Good,Fair,Poor] |

---

## Change 1: Lockwood-Aligned Core Parameters (Phase 4 Calibration Round 1)

**Date:** 2026-02-27
**Commit context:** Phase 4 calibration refinement

| Parameter | Old | New | Justification |
|-----------|-----|-----|---------------|
| gamma | 3.0 | 2.0 | Lockwood (2012) uses sigma=2. At gamma=3, marginal bequest utility falls ~28,600x faster than at gamma=2 for large bequests, weakening the bequest channel. |
| age_end | 100 | 110 | Lockwood (2012, BAP_sim2.m) uses max_age=110 (46 periods). Longer horizon gives annuities more payout years and more time for R-S/medical channels to operate. |
| c_floor | 3,000 | 100 | Lockwood WTP code (BAP_wtp.m) uses c_floor=$100. **Subsequently revised — see Change 2.** |
| W_max | 1,000,000 | 1,100,000 | Lockwood (2012, BAP_wtp.m) W_max=$1.1M. |
| n_wealth | 50 | 60 | Finer grid for better resolution at expanded age range. |
| n_annuity | 15 | 20 | More A grid points for better near-zero resolution. |
| annuity_grid_power | 2.0 | 3.0 | New parameter (added this round). Power=3 gives first non-zero A point ~$17 vs ~$408 at power=2, resolving small annuity purchases by low-wealth agents. |

**Result:** Final ownership dropped from ~50% to ~42%. Multiplicative ratio 3.91x confirmed.
Still far from 3-8% target.

---

## Change 2: Lockwood Simulation Floor (Phase 4 Calibration Round 2)

**Date:** 2026-02-27
**Commit context:** Post-investigation of 30pp medical cost demand anomaly

| Parameter | Old | New | Justification |
|-----------|-----|-----|---------------|
| c_floor | 100 | 6,180 | Lockwood simulation code (BAP_sim2.m) uses c_floor=$6,180, which approximates the SSI federal benefit rate plus average state supplement for a single elderly person. The WTP code uses $100 because it does not model medical costs. Our decomposition includes medical expenditures and population heterogeneity, matching the simulation context. A 10-agent audit confirmed that c_floor=$100 creates an artificial mechanism where annuity income substitutes for a missing public safety net, inflating Step 3 ownership from ~50% to ~80%. |

**Verification:** 10-agent investigation (Feb 27, 2026) confirmed:
- No coding bugs in Bellman equation, medical calibration, GH quadrature, or ownership computation
- The 30pp Step 3 increase is caused by c_floor=$100, not by model error
- c_floor=$6,180 matches Lockwood's population-level analysis code

**Result (Round 2, combined with Changes 3-4):**
- Step 3 (uncorrelated medical) drops from 73.0% to 62.7% (-10.3pp) — correct sign, no longer inflated
- Full model final ownership: 0.0% (overshoots 3.6% target)
- Medical cost channel now behaves as expected (reduces demand, not increases)

---

## Change 3: DFJ Luxury Bequest Specification (Phase 4 Calibration Round 2)

**Date:** 2026-02-27
**Commit context:** Strengthen bequest channel to match Lockwood's preferred specification

| Parameter | Old | New | Justification |
|-----------|-----|-----|---------------|
| kappa | 10 | 272,628 | Lockwood (2012, BAP_sim2.m) DFJ bequest specification: kappa=$272,628. This makes bequests a luxury good (De Nardi 2004): low-wealth agents have negligible bequest motive, high-wealth agents strongly resist annuitization to protect bequests. With kappa=$10 (homothetic), bequests reduce demand uniformly across the wealth distribution. The luxury-good specification concentrates the bequest effect where it matters most — among wealthy agents who drive the ownership rate. |
| theta | calibrated | 56.96 | Lockwood (2012, BAP_sim2.m) DFJ bequest intensity. Calibrated jointly with kappa=$272,628 to match HRS bequest-to-wealth ratios. Note: with DFJ bequests, theta is no longer calibrated from b*/N ratio; it is taken directly from Lockwood's estimation. |

**Source:** Lockwood (2012) Table 1, DFJ specification. Parameters recovered from
BAP_sim2.m replication code. See also De Nardi (2004, Review of Economic Studies)
for the luxury good bequest model.

**Result (Round 2, combined with Changes 2 and 4):**
- Step 2 (bequests) reduces ownership by only 2.2pp (73.0% → with, 75.2% without)
- DFJ luxury good specification concentrates bequest effect at high wealth
- Small isolated effect is expected: most HRS sample is low-wealth where κ=$272K makes bequests negligible
- Full model final ownership: 0.0% — bequest channel contributes via multiplicative interaction

---

## Change 4: Strengthen Reichling-Smetters Hazard Multipliers (Phase 4 Calibration Round 2)

**Date:** 2026-02-27
**Commit context:** Increase R-S health-mortality correlation strength

| Parameter | Old | New | Justification |
|-----------|-----|-----|---------------|
| hazard_mult | [0.6, 1.0, 2.0] | [0.4, 1.0, 3.0] | Wider spread between Good and Poor health survival. The R-S mechanism requires that poor health simultaneously increases mortality AND medical costs. With hazard_mult=[0.6,1.0,2.0], the Good-to-Poor mortality gap may be too narrow to generate the full R-S sign reversal in the population. Widening to [0.4,1.0,3.0] is within the empirical range from HRS health-mortality gradients. **Pending verification against Reichling-Smetters (2015) replication package on openICPSR.** |

**Caveat:** This parameter should be cross-checked against the R-S replication code
before finalizing. If their calibration uses different values, adopt theirs.

**Result (Round 2, combined with Changes 2-3):**
- Step 4 (R-S) reduces ownership by 11.9pp (62.7% → 50.8%)
- R-S mechanism now working correctly with widened hazard spread
- Combined with c_floor=$6,180, medical costs and R-S both reduce demand as theory predicts

---

## Round 2 Combined Results (Changes 2-4 together, Feb 27, 2026)

| Step | Model Specification | Ownership | Delta |
|------|-------------------|-----------|-------|
| 0 | Yaari benchmark | 50.1% | — |
| 1 | + Pre-existing annuitization (SS) | 75.2% | +25.1pp |
| 2 | + Bequest motives (DFJ) | 73.0% | -2.2pp |
| 3 | + Medical expenditure risk | 62.7% | -10.3pp |
| 4 | + Health-mortality correlation (R-S) | 50.8% | -11.9pp |
| 5 | + Realistic pricing loads (MWR=0.82) | 15.5% | -35.3pp |
| 6 | + Inflation erosion (3%) | 0.0% | -15.5pp |
| *Observed* | *Lockwood 2012* | *3.6%* | |

**Multiplicative ratio:** 2.88x (channels compound, not add)

**Robustness:** gamma=3 → 0.9%, gamma=4 → 16.5%, all others → 0.0%

**Issues requiring further investigation:**
1. Step 1 (SS) increases demand by 25pp — counterintuitive, likely driven by
   zero-wealth HRS individuals gaining annuitizable resources
2. Final ownership 0.0% overshoots the 3.6% target — need slight recalibration
3. Yaari baseline at 50.1% (not 100%) due to zero-wealth population members

---

## Parameters NOT Changed (with justification for keeping defaults)

| Parameter | Value | Why unchanged |
|-----------|-------|---------------|
| medical_sigma | 1.4 | Matches Jones et al. (2018) published P95 at age 100 ($111,502 vs $111,200 target). One auditor suggested reducing to 0.85 based on CV comparison, but this would break the quantile calibration. CV of ~2.5 is consistent with OOP medical spending distributions in HRS/MEPS. Do not change without cross-checking R-S replication package. |
| medical_mu_base | 7.037 | Matches Jones et al. (2018) mean OOP at age 70: $4,201 vs $4,200 target. |
| medical_mu_growth | 0.0652 | Matches Jones et al. (2018) age 100 mean: $29,703 vs $29,700 target. |
| beta | 0.97 | Close to Lockwood 1/1.03=0.9709. Standard in literature. |
| r | 0.02 | Standard real risk-free rate. |
| n_quad | 5 | Verified: n=5 gives exact E[exp(Z)]=exp(0.5) to machine precision. |

---

## Change 5: SS Baseline Restructuring, Denominator Fix, Population Filter (Phase 4 Calibration Round 3)

**Date:** 2026-02-27
**Commit context:** Restructure decomposition to treat SS as baseline, fix ownership denominator

### 5a. Denominator bug fix in `src/wtp.jl`

Both `compute_ownership_rate` and `compute_ownership_rate_health` divided by `n_individuals`
(total population) but skipped agents with W < $1 in the loop. With 128/793 HRS agents at
zero wealth, this understated all ownership rates by ~16%. Fix: track `n_evaluated` separately
and divide by that count.

### 5b. SS as baseline (not a channel)

Social Security is the baseline environment every retiree faces, not a friction to toggle.
Yaari's question is: given your resources (including SS), should you annuitize remaining
liquid wealth? The old decomposition toggled SS at Step 1 by zeroing the population's income
column, creating two artifacts:
- Yaari baseline = 50.1% (not ~100%) because zero-wealth agents can't annuitize
- Step 1 (adding SS) paradoxically increased demand by 25pp

New structure: SS always on. Steps reduced from 7 to 6:
  0. Yaari benchmark (no bequests, fair pricing, no medical, no inflation) — SS on
  1. + Bequest motives
  2. + Medical expenditure risk (uncorrelated)
  3. + Health-mortality correlation (R-S)
  4. + Realistic pricing loads
  5. + Inflation erosion

### 5c. Population wealth filter

Added `min_wealth` parameter (default $5,000 in run script). Agents below this threshold
cannot meaningfully annuitize and distort the Yaari baseline. The full-sample rate is
computed separately for comparison with Lockwood's 3.6%.

### 5d. Multiplicative analysis

Removed "SS only" as isolated channel (SS always on). Now 4 channels:
bequests, R-S, pricing loads, inflation.

---

## Change 6: Inflation Formula Fix (Phase 4 Calibration Round 3)

**Date:** 2026-02-27

| Parameter | Old | New | Justification |
|-----------|-----|-----|---------------|
| inflation formula | A*(1-pi)^(t-1) | A/(1+pi)^(t-1) | Correct real purchasing power of nominal payment. Old formula is first-order approx that overstates erosion (at pi=1 gives A=0 immediately vs correct A/2). Numerical impact small at 2-3% but formula was economically wrong. |
| inflation_rate | 0.03 | 0.02 | Fed targets 2%. Post-Volcker average ~2.3%. Neither Lockwood (2012) nor R-S (2015) model inflation. Brown et al. (2001) use 3.2% but without our other demand-suppressing channels. At 3%, inflation wiped out all remaining demand (21.7% to 0.0%) when stacked on all other channels. |

---

## Change 7: Baseline Risk Aversion (Phase 4 Calibration Round 3)

**Date:** 2026-02-27

| Parameter | Old | New | Justification |
|-----------|-----|-----|---------------|
| gamma | 2.0 | 2.5 | Fine gamma sweep revealed sharp transition: gamma=2.4 gives 0.2%, gamma=2.5 gives 6.0%, gamma=2.6 gives 14.8%. Target is 3-8%. gamma=2.5 is in the plausible range (Chetty 2006 estimates 1-3 from labor supply; lifecycle models typically use 1-5). Lockwood uses sigma=2, but his model excludes medical costs and R-S correlation. In our richer model, slightly higher risk aversion is needed to sustain insurance demand through all channels. |

**Full gamma sensitivity (all channels, 2% inflation, filtered population):**

| gamma | Final Ownership |
|-------|----------------|
| 1.5 | 0.0% |
| 2.0 | 0.0% |
| 2.2 | 0.0% |
| 2.4 | 0.2% |
| **2.5** | **6.0%** |
| 2.6 | 14.8% |
| 2.8 | 24.9% |
| 3.0 | 30.2% |
| 4.0 | 40.8% |

---

## Change 8: Hazard Multiplier Empirical Anchoring (Phase 4.5, Feb 28, 2026)

**Purpose:** Anchor hazard multipliers to HRS empirical mortality-by-health data.
Previously [0.4, 1.0, 3.0] was chosen to generate the R-S mechanism without
verified empirical support. This was identified as the single biggest result driver.

### Empirical Evidence

**Source 1: RAND HRS longitudinal file (self-reported health, N=126,249 person-wave obs)**

Computed in `calibration/compute_hazard_ratios.jl` from waves 4-16, ages 65+.
3-state recoding: Good (Exc/VG), Fair (Good), Poor (Fair/Poor).

| Age band | Good | Fair | Poor | N |
|----------|------|------|------|---|
| 65-74 | 0.49 | 1.00 | 3.29 | 64,106 |
| 75-84 | 0.60 | 1.00 | 2.77 | 44,788 |
| 85+ | 0.74 | 1.00 | 1.82 | 17,355 |
| **All 65+** | **0.57** | **1.00** | **2.70** | **126,249** |

Key feature: gradient compresses with age as baseline mortality rises.

**Source 2: Reichling-Smetters (2015) Figure 7 survival curves**

R-S use functional limitation states (ADL/IADL from Robinson 1996), not SRH.
Implied hazard ratios from their survival probability curves:

| Age | H1/H2 | H3/H2 |
|-----|-------|-------|
| 65-75 | ~0.45 | ~3.5-4.0 |
| 85+ | ~0.45 | ~2.5 |

Functional limitations have wider mortality spread than SRH.

**Source 3: Epidemiological meta-analyses**

- DeSalvo et al. (2006): Poor vs Fair HR ~1.33 (all ages, attenuated)
- Woo & Kao (2014, oldest-old): [0.60, 1.00, 1.91] relative to Good SRH
- Chandola & Jenkinson (2000): Poor vs Excellent HR = 4.35

### Decision

| Specification | Multipliers | Justification |
|--------------|-------------|---------------|
| **Baseline** | [0.50, 1.00, 3.00] | Midpoint of HRS SRH (0.57) and R-S functional (0.45) for Good; R-S functional for Poor |
| Robustness (SRH) | [0.57, 1.00, 2.70] | Direct HRS empirical estimate |
| Robustness (R-S) | [0.45, 1.00, 3.50] | Consistent with R-S Figure 7 at ages 65-75 |
| Robustness (narrow) | [0.60, 1.00, 2.00] | Conservative SRH-based (Woo & Kao 2014) |

The model uses a constant multiplier for tractability. R-S have age-varying curves.
This is a model simplification acknowledged in the paper.

---

## Change 9: Production Grid Resolution (Feb 28, 2026)

**Purpose:** Resolve grid convergence failure. At the old production grid (60×20×51),
ownership was 6.0%, but coarser (30×10) gave 26.1% and finer (100×30) gave 1.8%.
Isolated testing revealed two opposing forces:

### Convergence Anatomy

**Wealth grid (n_wealth):** Converges quickly. At nW=50+, ownership stable at 5.7-6.0%
(holding nA=20, nα=51).

**Annuity grid (n_annuity):** Primary source of non-convergence. Coarser grids smooth
over the dip in value at intermediate alpha, inflating ownership. Stabilizes at nA≥30.

**Alpha grid (n_alpha):** Pulls in the opposite direction from annuity grid. Finer alpha
search finds beneficial annuitization fractions that coarse search misses. Stabilizes at
nα≥101.

### Joint Convergence Table

| Grid (nW × nA × nα) | Ownership |
|----------------------|-----------|
| 30 × 10 × 21 | 22.1% |
| 40 × 15 × 31 | 12.2% |
| 60 × 20 × 51 | 5.3% |
| 60 × 25 × 101 | 2.8% |
| 80 × 30 × 101 | 1.4% |
| 80 × 30 × 201 | 1.6% |
| 100 × 40 × 101 | **1.4%** |
| 100 × 40 × 201 | **1.4%** |

### Decision

| Parameter | Old | New | Justification |
|-----------|-----|-----|---------------|
| n_wealth | 60 | 80 | Converged at nW≥80 |
| n_annuity | 20 | 30 | Converged at nA≥30 (main convergence driver) |
| n_alpha | 51 | 101 | Converged at nα≥101 |

Production grid (80×30×101) gives 1.4% ownership. Further refinement to 100×40×201
also gives 1.4%. Convergence within ±0.2pp achieved.

Note: The converged ownership rate of ~1.4% is LOWER than the previous 6.0% at 60×20×51.
This strengthens the paper's conclusion (lower predicted demand matches observed data even
better) but requires recalibrating to understand how the decomposition steps change.

---

## Robustness Parameters (tested in sensitivity analysis)

These are varied systematically in the robustness section, not fixed:
- gamma: {1.5, 2.0, 2.2, 2.4, 2.6, 2.8, 3.0, 4.0}
- beta: {0.95, 0.97, 0.99}
- mwr_loaded: {0.82, 0.85, 0.90}
- inflation_val: {0.01, 0.02, 0.03}
- hazard_mult: baseline vs widened
- c_floor: {3000, 6180, 10000}
