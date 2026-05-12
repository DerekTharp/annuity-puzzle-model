# Revision Plan

**Current state:** Phase 30 (production framing — two-model architecture)
**Last updated:** 2026-05-11
**Target venue:** Journal of Public Economics (primary) or Review of Economic Dynamics (backup)

---

## Phase 30 Status (current)

The manuscript is now organized around a **two-model architecture**, not a single
bundled-wedge specification. The behavioral channels are exploratory anchors to
literature magnitudes, not moment-matched parameters. All Phase 25--29 framings
(single bundled wedge, "Force C", "Option 1 a-strict", SMM identification of
behavioral parameters) are superseded.

### Model 1: structural lifecycle decomposition

- **Nine-channel structural baseline:** 1.7% predicted ownership
  - Six rational channels: Social Security, bequests, medical expenditure risk with
    health-mortality correlation, survival pessimism, pricing loads, inflation erosion
  - Plus long-term care risk
  - Plus two preference channels: age-varying consumption needs (Aguiar--Hurst 2013),
    state-dependent utility (Finkelstein--Luttmer 2013)
  - Plausibly close to two HRS empirical comparators:
    - Lifetime contract indicator: 2.02% (95% CI [1.68%, 2.43%])
    - Any-annuity income proxy: 3.34% (95% CI [2.89%, 3.85%])
  - Structural baseline underpredicts by roughly 0.3--1.6 pp. Do NOT claim "matches"
    or "resolves"; the honest reading is that standard mechanisms account for most
    of the gap, leaving a small residual.

- **Eleven-channel Model 1 (extended):** 0.1% predicted ownership
  - Adds source-dependent utility (Blanchett--Finke 2024, 2025) and a purchase-event
    disutility consistent with Brown (2008) / Chalmers--Reuter (2012) / Hu--Scott (2007)
    narrow-framing magnitudes
  - Calibrated to literature magnitudes, NOT moment-matched to US data
  - PED saturates and drives predicted ownership toward zero
  - Reported as exploratory; the structural-baseline-plus-residual reading is the
    disciplined interpretation

### Model 2: UK reduced-form transport

- Frictionless population benchmark: 41.85%
- UK 2015 pension-freedoms reform yields a behavioral wedge:
  - Pre-reform retention: 95% (mandatory annuitization)
  - Post-reform retention: 17% mid (range 13%--25%) from pooled ELSA evidence
- Transport: 41.85% × (17/95) = 7.5% mid; bracket [5.7%, 11.0%]
- The conventional HRS income proxy (3.34%) lies inside the Model 2 bracket;
  the cleaner lifetime-contract indicator (2.02%) overlaps only the bracket's lower edge

### Shapley decomposition

- Computed over all 1,024 channel subsets (order-independent attribution)
- Behavioral channels: PED = +44.4 pp, SDU = -31.1 pp
- Large but offsetting individual contributions; net behavioral effect small
- Consistent with operation on distinct decision margins, not redundant
  parameterization of the same wedge

### Key parameters (Phase 30 production)

- gamma = 2.5, beta = 0.97, r = 0.02
- lambda_W = 0.625 (was 0.85 in Phase 29; that value is stale and removed)
- psi_purchase = literature-magnitude calibration (NOT SMM-identified)
- DFJ bequest (luxury good): theta = 56.96, kappa = $272,628

### Manuscript framing

- Title: "Quantifying the Annuity Puzzle: A Unified Lifecycle Decomposition"
- Do NOT use: "dissolving", "resolves", "fully explains", "puzzle dissolves",
  "matches HRS"
- Use: "plausibly close to", "accounts for most of the gap", "substantial reduction"
- Cite Chalmers--Reuter (2012) as a literature reference for behavioral magnitudes,
  NOT as a calibration target

---

## Historical revision items (Tier 1--3, superseded)

The items below were the v0.1 → v0.2 revision plan from external peer review
(Feb 2026). They are preserved for historical context. Most have been addressed
by subsequent Phase 25--30 work, often in different form than originally proposed.
The Phase 30 production framing supersedes the original tier structure.

### Tier 1: Must Fix (blocks submission) — historical record

- **1.0 Inflation pricing consistency** — addressed; nominal pricing now consistent
  with documented insurer discount rate
- **1.1 Monte Carlo parameter uncertainty** — implemented; results in
  `numbers.tex` (mcMedianOwnership, mcLowCIOwnership, etc.)
- **1.2 Age-varying hazard multipliers** — implemented as robustness; constant
  multipliers retained as baseline for comparability
- **1.3 Bequest parameter portability** — addressed via DFJ luxury-good
  specification (theta = 56.96, kappa = $272,628)
- **1.4 Pashchenko comparison** — reframed; rational channels alone now predict
  18.2% (close to Pashchenko's ~20%), consistent with her result
- **1.5 Lifecycle moment validation** — wealth profiles and bequest distribution
  reported in appendix
- **1.6 Title and framing moderation** — title changed to "Quantifying the Annuity
  Puzzle: A Unified Lifecycle Decomposition"; "dissolving" language removed

### Tier 2: Should Fix — historical record

- **2.1 Updated MWR pricing** — addressed (MWR = 0.87 baseline; 0.82, 0.85, 0.90,
  0.95 as robustness)
- **2.2 Real annuity scenario** — implemented as a policy counterfactual
- **2.3 Two-way interaction decomposition** — superseded by exact Shapley
  decomposition over 1,024 channel subsets
- **2.4 Missing literature** — engaged in revision
- **2.5 Bequest anomaly in main text** — moved to main results

### Tier 3: Would strengthen — partial

- **3.1 HRS survey weights** — addressed; lifetime and income measures both reported
- **3.2 7-node Gauss-Hermite check** — addressed; baseline now uses 9 nodes
- **3.3 Period-certain product** — not implemented
- **3.4 Policy function smoothness** — addressed via finer alpha grid (101 points)
- **3.5 Married couples** — explicitly out of scope; flagged as future work

---

## What is explicitly out of scope

1. **Full SMM estimation of behavioral parameters** — the eleven-channel Model 1
   uses literature-magnitude calibrations rather than US-moment-matched parameters,
   by design. SMM identification would require auxiliary moments that are not
   currently available
2. **Married couples** — major model extension; flagged as future work in Discussion
3. **Housing wealth** — flagged as limitation in Discussion
4. **5-state health model** — three-state model with age-varying robustness is sufficient

---

## What earlier framings to remove on sight

The following Phase 25--29 patterns are stale and must be removed wherever they appear:

- "Bundled behavioral wedge" / "single bundled wedge" / "Force C" as a named force
- "Option 1", "Option 1 a-strict", "Option 1 bundled identification"
- "Force A" / "Force B" as named primitives — replace with explicit channel names
  (source-dependent utility, purchase-event disutility)
- Any reference to SMM identification of behavioral parameters
- "Puzzle resolves" / "puzzle dissolves" / "fully explains" — overclaiming
- "Matches HRS" — replace with "plausibly close to"
- References to Chalmers--Reuter as a calibration target (it is a literature
  reference now, not a moment)
- Stale macros: `\pPsiBracketLow`, `\pPsiBracketHigh`, `\pPsiUKMid`
- lambda_W = 0.85 (the Phase 29 value; Phase 30 uses 0.625)
