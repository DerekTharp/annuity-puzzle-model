# Revision Plan: v0.1 → v0.2

**Date:** 2026-02-28 (updated 2026-02-28 with external review feedback)
**Target venue:** Journal of Public Economics (primary) or Review of Economic Dynamics (backup)
**Basis:** Internal peer review by 10 simulated expert reviewers + external reviews
(ChatGPT, Grok, Gemini)

---

## Strategic Decision: Venue and Framing

The AER editor assessment was clear: this is an integration/accounting exercise, not a
new-mechanism paper. The contribution is real but better suited to JPubE (where Pashchenko
published) or RED (where Lockwood published). The revision should:

- Retitle from "Why Retirees Don't Annuitize" to something more measured
- Replace "dissolving" language with "quantitatively accounting for"
- Position as extending Pashchenko (2013) and Lockwood (2012), not superseding them
- Frame the knife-edge sensitivity honestly as a feature of the economic environment,
  not sweep it under the rug

---

## External Review Assessment

Three external AI reviewers (ChatGPT, Grok, Gemini) assessed the manuscript independently.
Quality varied enormously:

- **ChatGPT:** Most substantive review. Converged on the same venue assessment as our
  internal panel (not AER; field journal after revision). Identified a potentially
  first-order issue with the inflation channel pricing that our internal reviewers
  mostly missed (see Item 1.0 below). Correctly flagged the bequest portability problem,
  knife-edge gamma, thin empirical validation, and incomplete replication package.
  Suggested reframing as a "real-annuity puzzle" paper — worth considering.

- **Gemini:** Correct at a high level (synthesis paper, AER is a stretch, JPubE/RED are
  natural homes) but shallow. Did not engage with any substantive economic or computational
  issue. No actionable feedback beyond what the internal panel already identified.

- **Grok:** Useless. Claimed "100% fidelity match" and "publishable at AER in its current
  form" without having access to the core solver module. Did not flag any of the issues
  identified by the internal panel or ChatGPT. Pure sycophancy. Discard entirely.

**New items added from external review:** Item 1.0 (inflation pricing consistency) is
the most important addition. It is potentially a first-order issue that could change
the entire quantitative story.

---

## Revision Items

### Tier 1: Must Fix (blocks submission)

#### 1.0 Inflation Channel Pricing Consistency (HIGHEST PRIORITY)
**Source:** ChatGPT external review (missed by all 10 internal reviewers)
**Problem:** The model double-penalizes nominal annuities through inconsistent pricing.

`compute_payout_rate()` in `src/annuity.jl` (line 28) discounts using the **real** rate
`p.r = 0.02`:
```
discount = 1.0 / (1.0 + p.r)^t
```
This produces a payout rate appropriate for a **real** annuity. Then `annuity_income_real()`
(line 66) additionally erodes this payout by inflation:
```
A_nominal * (1.0 / (1.0 + p.inflation_rate))^(t - 1)
```

The agent receives the **lower** real-rate payout AND suffers inflation erosion. A
correctly priced nominal annuity uses the nominal discount rate (r_nom = r + pi ≈ 0.04),
producing a **higher** initial payout that then erodes in real terms. Over a 45-year
horizon, the nominal PV denominator is substantially smaller (perhaps 60-70% of the
real PV), meaning the correctly priced nominal payout could be 30-50% higher initially.

**Why this matters:** The inflation channel drives ownership from 41.7% to 1.4% — a 40pp
drop and the single largest step in the decomposition. If a significant portion of this
drop is an artifact of inconsistent pricing rather than genuine economic mechanism, the
headline result is overstated. Fixing this could plausibly leave ownership at 15-25%
after inflation, which would mean the model no longer matches observed data without
additional channels (behavioral, etc.).

**Fix options (choose one):**

**Option A (preferred): Correctly price the nominal annuity.**
- Use `r_nom = r + pi` (Fisher approximation) in `compute_payout_rate()` when
  `inflation_rate > 0`
- The higher initial nominal payout then erodes by `(1+pi)^(t-1)` in real terms
- This is internally consistent: the insurer discounts at the nominal rate (matching
  nominal bond yields), and the consumer receives nominal payments whose real value
  declines
- The initial payout is higher, so the product is more attractive than in v0.1
- The inflation channel's bite will be reduced, but some demand suppression remains
  because the payment profile is front-loaded relative to late-life needs

**Option B: Model both products.**
- "Nominal annuity" uses `r_nom` for pricing, erodes by inflation
- "Real annuity (COLA)" uses `r_real` for pricing, no erosion, but lower initial payout
  (25-30% lower per Brown, Mitchell, Poterba 2001)
- Report decomposition under both product types
- This subsumes the old Tier 2 item 2.2 (Real Annuity Scenario)

**Option C: Reframe the inflation step.**
- If the model's approach is interpreted as: "the insurer prices with the real rate
  but pays nominally (keeping the spread as profit)," then inflation is partly captured
  by the MWR load, not a separate channel
- This interpretation implies the MWR should be higher when inflation > 0 to avoid
  double-counting
- Less clean than Option A

**Code changes:**
- `src/annuity.jl`: modify `compute_payout_rate()` to accept an optional `nominal`
  flag; when true, use `r_nom = r + inflation_rate` for discounting
- `src/decomposition.jl`: at Step 5, pass `nominal=true` to payout rate computation
- Rerun full decomposition and all robustness
- The converged ownership at Step 5 will change — this is the point

**Impact assessment:** This is the revision item most likely to change the paper's
quantitative story. If ownership after inflation lands at 15-25% instead of 1.4%, the
paper can no longer claim to match observed data within the EU framework alone. Two
possible outcomes:
1. Ownership lands at 5-15%: still a strong result, still "substantially accounts for"
   the puzzle. The paper survives with moderated framing.
2. Ownership lands at 20%+: the model resembles Pashchenko's residual, and the paper
   must either add behavioral channels or acknowledge a remaining gap.

Either outcome is more honest than the current 1.4% result. Run the fix first, then
decide how to frame the paper.

**Effort:** 2–3 days (code fix + full rerun + assess implications)

#### 1.1 Address the Knife-Edge: Monte Carlo Uncertainty Quantification
**Reviewers:** 1, 4, 5, 7, 8, 10
**Problem:** Ownership jumps from 0% to 5.3% within gamma ∈ [2.45, 2.55]. The central
result depends on gamma pinned to within ±0.05.

**Fix:** Rather than SMM estimation (which would require months of work and a fundamentally
different paper), add a Monte Carlo parameter uncertainty exercise:
- Draw gamma from N(2.5, 0.3) truncated to [1.5, 5.0] (Chetty 2006 range)
- Draw hazard_mult_poor from U(2.0, 3.5) (empirical range from HRS to R-S)
- Draw inflation from U(0.01, 0.03) (plausible range)
- Draw MWR from U(0.82, 0.95) (Mitchell 1999 to Wettstein 2021)
- 1000 draws, solve full model for each, report distribution of predicted ownership
- Report: median, IQR, fraction in [1%, 10%] range

**Why this works:** It honestly characterizes how sensitive the result is to plausible
parameter uncertainty, without claiming to have estimated the parameters. The paper can
then say: "Across 1000 draws from empirically plausible parameter distributions, median
predicted ownership is X% (IQR: Y%–Z%), with W% of draws falling within the observed
3–6% range."

**Code changes:**
- New script: `scripts/run_monte_carlo_uncertainty.jl`
- Uses existing `solve_and_evaluate()` in a loop over parameter draws
- Output: CSV of (gamma, hazard, inflation, mwr, ownership) for each draw
- New figure: histogram of predicted ownership across draws

**Effort:** 2–3 days (script + production run + figure + paper text)

#### 1.2 Age-Varying Hazard Multipliers
**Reviewers:** 3, 7
**Problem:** Constant multipliers [0.50, 1.0, 3.0] overstate R-S at advanced ages. HRS
data show gradient compresses from 3.29 at 65-74 to 1.82 at 85+.

**Fix:** Implement piecewise-linear age-varying multipliers as the primary specification.
Use the HRS empirical estimates from `data/processed/hrs_hazard_ratios.csv`:

| Age band | Good | Fair | Poor |
|----------|------|------|------|
| 65-74    | 0.49 | 1.00 | 3.29 |
| 75-84    | 0.60 | 1.00 | 2.77 |
| 85+      | 0.74 | 1.00 | 1.82 |

Linearly interpolate between band midpoints. Keep constant multipliers as a robustness
check (and for comparability with v0.1 results).

**Code changes:**
- `src/parameters.jl`: add `hazard_mult_by_age::Matrix{Float64}` option
- `src/health.jl`: modify `health_adjusted_survival()` to accept age argument
- `src/solve.jl`: pass age to survival computation (already in the loop)
- Tests: verify limiting cases still pass with age-varying multipliers

**Impact on results:** Ownership will likely increase (weaker R-S at old ages). The
Monte Carlo exercise (1.1) will incorporate this, so the combined effect is characterized.

**Effort:** 2–3 days (code + recalibration + rerun decomposition)

#### 1.3 Bequest Parameter Portability
**Reviewers:** 5, 8
**Problem:** Lockwood estimated theta=56.96 and kappa=$272,628 at sigma=2. We use them at
gamma=2.5 without re-estimation.

**Fix (practical, not full re-estimation):**
- Compute implied bequest-to-wealth ratios at gamma=2.5 vs gamma=2.0 using forward
  simulation. Report both in a table.
- If the ratios diverge badly, re-calibrate theta at gamma=2.5 to match the same HRS
  bequest-to-wealth ratio that Lockwood targeted. This is a single-parameter calibration
  (hold kappa fixed, search over theta).
- Report the re-calibrated theta alongside Lockwood's original.

**Code changes:**
- New calibration script: `calibration/recalibrate_bequests.jl`
- Run `simulate_batch()` at gamma=2.0 and gamma=2.5, compare bequest distributions
- If needed, use Optim.jl to find theta that matches target bequest ratio at gamma=2.5

**Effort:** 2–3 days

#### 1.4 Fix the Pashchenko Comparison
**Reviewers:** 7, 8
**Problem:** Replicating "her channels" gives 66.6% vs her 20%. The 3x discrepancy is
unexplained.

**Fix (two options, pick one):**

**Option A (preferred): Honest reconciliation.** Add a table showing intermediate
specifications between our model and hers. Identify which differences drive the gap:
- Binary vs continuous annuitization margin
- DFJ vs her bequest specification
- Omission of housing illiquidity
- Different population sample
- General equilibrium vs partial equilibrium pricing

Run 2–3 intermediate specs to isolate the main driver.

**Option B: Drop the replication claim.** Reframe the comparison as: "Using our model,
the channels Pashchenko identified account for X% of the Yaari-to-observed gap. Adding
the channels she omitted closes the remaining gap." Do not claim to replicate her results.

**Effort:** 3–5 days for Option A; 1 day for Option B

#### 1.5 Lifecycle Moment Validation
**Reviewers:** 5, 10
**Problem:** The model targets one moment (ownership rate). No validation against wealth
decumulation, bequests, or medical spending profiles.

**Fix:** Use existing `simulate_batch()` to generate:
- Mean and median wealth by age (compare to HRS wealth profiles)
- Bequest distribution (mean, median, fraction positive; compare to HRS exit interviews)
- Health state prevalence by age (compare to HRS self-reported health)

Report as a table of simulated vs empirical moments. This is validation, not estimation:
the model is not re-calibrated to match these moments, but we show it does not grossly
violate them.

**Code changes:**
- Expand `simulate_batch()` output to include wealth quantiles by age
- New script: `scripts/run_moment_validation.jl`
- New table: `tables/tex/moment_validation.tex`
- Extract HRS empirical moments from `data/raw/HRS/`

**Effort:** 3–4 days

#### 1.6 Moderate the Title and Framing
**Reviewers:** 4, 7, 10
**Problem:** "Dissolving" is too strong for the parameter sensitivity observed.

**Fix:**
- New title: "Quantifying the Annuity Puzzle: A Unified Lifecycle Decomposition"
  or "Accounting for Low Annuity Demand: A Unified Lifecycle Model"
- Replace "dissolves" with "substantially accounts for" throughout
- Add explicit paragraph acknowledging the gamma sensitivity and what it implies
- Frame the contribution as: the first unified decomposition showing multiplicative
  interaction, not as definitive resolution

**Effort:** 1 day (text edits only)

---

### Tier 2: Should Fix (strengthens the paper materially)

#### 2.1 Updated MWR Pricing
**Reviewer:** 2
**Problem:** MWR=0.82 is from Mitchell et al. (1999). Modern estimates are higher.

**Fix:** Add MWR=0.90 and MWR=0.95 as robustness specifications. Report ownership at
each. This is already in the robustness infrastructure; just needs additional runs and
a row in the sensitivity table.

**Effort:** 0.5 days

#### 2.2 Real Annuity Scenario
**Reviewer:** 2
**Problem:** Only nominal annuities modeled. Real annuities (with COLA) are more
attractive for late-life insurance.

**Note:** If Item 1.0 is implemented via Option B (model both products), this item is
subsumed. If Option A is chosen instead, this remains as a separate robustness check.

**Fix:** Implement real annuity pricing in `src/annuity.jl`:
- COLA-adjusted present value formula
- Initial payout ~25-30% lower than nominal (Brown, Mitchell, Poterba 2001)
- Run decomposition with real annuity as robustness check
- Report: if real annuities were available at fair pricing, how much does ownership rise?

**Code changes:**
- `src/annuity.jl`: add `compute_payout_rate_real()` with COLA parameter
- `src/parameters.jl`: add `annuity_type` field
- Robustness script modification

**Effort:** 2 days (0 if subsumed by 1.0 Option B)

#### 2.3 Two-Way Interaction Decomposition
**Reviewer:** 8
**Problem:** The multiplicative ratio is a single number. Which channel pairs interact
most strongly?

**Fix:** Compute all pairwise channel combinations (bequests×loads, bequests×inflation,
R-S×loads, R-S×inflation, loads×inflation = 10 pairs from 5 channels). For each pair,
compute: drop from pair together vs sum of individual drops. Report as a matrix.

**Code changes:**
- New function in `src/decomposition.jl`: `run_pairwise_interactions()`
- New table: `tables/tex/pairwise_interactions.tex`

**Effort:** 2–3 days

#### 2.4 Missing Literature
**Reviewers:** 7
**Problem:** Several relevant papers not cited.

**Fix:** Add to bibliography and engage in text:
- Inkmann, Lopes, and Michaelides (2011, AER) — nests annuities with equity/housing
- Hosseini (2015, AEJ: Macro) — heterogeneous mortality + adverse selection
- Ameriks, Briggs, Caplin, Shapiro, Tonetti (2020, AER) — stated-preference LTC aversion
- O'Dea and Sturrock (2023, AER) — subjective survival beliefs
- Temper the "first unified model" claim: we are the first to include R-S with the
  standard channels, not the first to nest multiple channels

**Effort:** 1 day (bibliography + text edits)

#### 2.5 Bequest Anomaly in Main Text
**Reviewer:** 8
**Problem:** The bequest anomaly (homothetic bequests increasing ownership) is in the
appendix but should be in the main text.

**Fix:** Move the economic explanation to Section 4 (Results) or Section 5 (Robustness).
Add 1-2 paragraphs explaining why theta and kappa must be interpreted jointly and why
the luxury-good specification is the only economically coherent parameterization. Discuss
the 0.2pp isolated effect and why the bequest channel's power is through interactions.

**Effort:** 0.5 days

---

### Tier 3: Would Strengthen (but not required for submission)

#### 3.1 HRS Survey Weights
**Reviewer:** 9
**Problem:** Population sample is unweighted.

**Fix:** Extract survey weights from RAND HRS, apply to ownership computation. Compare
weighted vs unweighted results. If similar, note in text; if different, use weighted as
baseline.

**Effort:** 1–2 days

#### 3.2 7-Node Gauss-Hermite Check
**Reviewer:** 3
**Problem:** 5 GH nodes may be insufficient for heavy-tailed medical cost distribution.

**Fix:** Rerun decomposition with 7 nodes, compare to 5-node baseline. Report in
appendix. (Based on prior testing, 5 nodes give exact E[exp(Z)] to machine precision,
so this is likely a non-issue, but documenting it addresses the concern.)

**Effort:** 0.5 days

#### 3.3 Period-Certain Product
**Reviewer:** 2
**Problem:** Life-only annuity modeled; period-certain (e.g., 10-year guarantee) products
are common in practice.

**Fix:** Add period-certain pricing to `src/annuity.jl` (guaranteed payments for first
N years regardless of survival). Run as robustness. This partially addresses the bequest
concern: period-certain annuities reduce the bequest penalty.

**Effort:** 1–2 days

#### 3.4 Policy Function Smoothness (Fig 4a)
**Reviewer:** 10
**Problem:** Non-monotone oscillations in the no-bequest policy function suggest grid
artifacts.

**Fix:** Diagnose whether this is a grid resolution issue or a genuinely non-concave
objective (multiple local optima in alpha). If grid: increase alpha grid density in that
region. If economic: document and explain.

**Effort:** 1 day

#### 3.5 Married Couples
**Reviewers:** 1, 6, 10
**Problem:** Singles only. Most retirees are married.

**Assessment:** This is a major model extension (adds a state variable, requires
joint survival, spousal income, Kotlikoff-Spivak mechanism). It would double the state
space and computation time. Better treated as a separate follow-up paper or a future
revision if a referee insists. Acknowledge the limitation explicitly in the Discussion
section.

**Effort:** 3–6 weeks (not recommended for this revision)

---

## Execution Sequence

**CRITICAL:** Item 1.0 must be completed first. Its outcome determines the quantitative
story and may reshape the framing, title, and every downstream result. Do not proceed
to other items until the inflation pricing fix is implemented and the new decomposition
numbers are in hand.

| Order | Item | Days | Cumulative | Notes |
|-------|------|------|-----------|-------|
| **1** | **1.0 Inflation pricing fix** | **3** | **3** | **Gate: determines entire paper narrative** |
| 2 | 1.2 Age-varying hazard multipliers | 3 | 6 | Rerun decomposition with both fixes |
| 3 | 1.3 Bequest parameter recalibration | 3 | 9 | |
| 4 | 1.6 Moderate title/framing | 1 | 10 | Informed by new numbers from 1.0 |
| 5 | 2.4 Missing literature | 1 | 11 | |
| 6 | 2.5 Bequest anomaly to main text | 0.5 | 11.5 | |
| 7 | 1.4 Fix Pashchenko comparison | 3 | 14.5 | Rerun with corrected pricing |
| 8 | 1.5 Lifecycle moment validation | 4 | 18.5 | |
| 9 | 1.1 Monte Carlo uncertainty | 3 | 21.5 | Uses corrected pricing + age-varying hazards |
| 10 | 2.1 Updated MWR | 0.5 | 22 | |
| 11 | 2.2 Real annuity scenario | 2 | 24 | May be subsumed by 1.0 Option B |
| 12 | 2.3 Two-way interactions | 3 | 27 | |
| 13 | 3.1–3.4 Minor fixes | 3 | 30 | |
| 14 | Rewrite manuscript | 5 | 35 | |
| 15 | Recompile, verify numbers | 2 | 37 | |

**Total estimated: ~5.5 weeks of focused work.**

**Contingency after Item 1.0:** If corrected inflation pricing raises ownership to 20%+,
the paper faces a choice:
- (a) Accept a "substantially narrows the puzzle" framing (ownership drops from ~97% to
  ~20% through rational channels; remaining gap requires behavioral channels)
- (b) Add a reduced-form behavioral channel (e.g., subjective survival pessimism from
  O'Dea and Sturrock 2023) to close the residual
- (c) Pivot the paper's contribution toward the multiplicative interaction insight and
  heterogeneous welfare map, rather than matching the ownership level

Option (a) is the most honest and still a strong paper. The decomposition and
multiplicative interaction are novel contributions regardless of the final ownership
number.

---

## What We Explicitly Decline

These items were raised but are beyond the scope of this revision:

1. **Full SMM estimation of gamma** (R5, R10): Would transform this into a different
   paper. The Monte Carlo uncertainty exercise (1.1) is the practical alternative.
2. **Married couples** (R1, R6, R10): Major model extension, better as follow-up.
3. **Behavioral channels / prospect theory** (R4): Outside the EU framework. Acknowledged
   in Discussion as complementary.
4. **Housing wealth** (R6): Major state variable addition. Acknowledged as limitation.
5. **5-state health model** (R3): Would require re-estimating all health transition
   matrices. The 3-state model with age-varying multipliers addresses the main concern.

---

## New Tables and Figures for v0.2

| Output | Type | Source |
|--------|------|--------|
| **Corrected decomposition (nominal pricing fix)** | **Table (replaces v0.1 Table 1)** | **Item 1.0** |
| Nominal vs real annuity comparison | Table | Item 1.0 (Option B) or 2.2 |
| Monte Carlo ownership distribution | Figure + Table | Item 1.1 |
| Age-varying hazard multiplier profiles | Figure | Item 1.2 |
| Bequest-to-wealth ratios at gamma=2 vs 2.5 | Table | Item 1.3 |
| Pashchenko reconciliation specifications | Table | Item 1.4 |
| Simulated vs empirical lifecycle moments | Table | Item 1.5 |
| Pairwise channel interaction matrix | Table | Item 2.3 |

---

## External Review Quality Notes (for future reference)

When soliciting external AI reviews, quality varies dramatically:
- **ChatGPT** provided the most substantive feedback, including a potentially first-order
  issue (inflation pricing) that 10 internal reviewers missed. Worth consulting for
  economic logic and internal consistency checks.
- **Gemini** was correct at a high level but added no actionable detail beyond the internal
  panel. Useful as a sanity check on venue assessment.
- **Grok** was actively harmful — sycophantic praise ("publishable at AER in current form,"
  "100% fidelity match") despite not having access to the core code. Could create false
  confidence if taken at face value. Do not rely on for quality assessment.
