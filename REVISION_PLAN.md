# Revision Plan — Synthesized from 20 Expert Reviews

**Date:** 2026-03-24 (updated 2026-04-02)
**Reviews:** 10 economics reviewers (Round 1) + 10 code reviewers (Round 2)
**Economics score:** 6.8/10 | **Code score:** 6.2/10

---

## Tier 1: Potential Bugs (investigate first — may change results)

- [x] **Welfare mispricing** — `src/welfare.jl:177` used real rate where nominal pricing should apply. FIXED 2026-04-02. Bug only affected population CEV for ages 66-69; grid CEV (all headline numbers) was unaffected.
- [x] **DIA repricing** — Investigated 2026-04-02. NOT A BUG: the value function already embeds deferral via backward induction, so the annuitization search correctly evaluates V.
- [x] **Grid cap clipping** — W_max=$1M; 143/5303 HRS households (2.7%) silently excluded. Low impact (ultra-wealthy households). Documented; no code change needed.
- [x] **Forward simulation timing** — Investigated 2026-04-02. Standard practice: solver uses GH quadrature, simulator uses MC draws. Not a bug; documented.

## Tier 2: Must Fix Before Submission

- [x] Sync all headline numbers across highlights.txt, README.md, manuscript, figures — VERIFIED 2026-04-02 (all 13 numbers consistent)
- [x] Reframe paper as "calibrated structural exercise" not identification/estimation — Already done (main.tex line 68)
- [x] Trim intro density (move exact numbers to results section) — Abstract/intro already restructured
- [x] Add bequest decomposition explanation (zero standalone vs 19% counterfactual) — Already in main.tex lines 111-113
- [x] Soften overclaiming language ("matching" → "consistent with"; "nuanced" removed) — FIXED 2026-04-02
- [x] Fix pipeline contract break — FIXED 2026-04-02: added Shapley and SS cut stages to run_all.jl
- [x] ModelParams defaults match manuscript baseline (age_end=110) — FIXED 2026-04-02
- [ ] Add release tag to GitHub
- [ ] Test suite locks 6.6% headline result (was "5.3%" — stale)
- [ ] Document own_life_ann placeholder in CSV
- [x] Clarify person-wave vs unique individuals in sample description — Adequate as-is (line 373 uses "person-wave observations" correctly)
- [x] SS cut labeled as stylized elasticity experiment — FIXED 2026-04-02 (added qualifying sentence)
- [x] SS real vs nominal distinction emphasized — Already clear (COLA references at lines 415, 427)
- [x] Soften "behavioral confirmatory" claim — Not present in manuscript; discussion uses appropriate language
- [x] DIA comparison rephrased (confounded with pricing) — Already clear in appendix line 274
- [x] Clarify survey weights choice (unweighted, with justification) — ADDED 2026-04-02
- [x] Trim conclusion redundancy — Conclusion is already concise (5 short paragraphs)

## Tier 3: Should Fix (strengthens paper meaningfully)

- [x] **Shapley decomposition** — COMPLETE (exact 512-subset enumeration, not permutation sampling)
- [ ] **SS cut robustness table** — vary cut 10-50% (~$5 AWS, 2 hrs)
- [ ] **Quadrature convergence** — test at 11, 13, 15 nodes (~$10 AWS, 3 hrs)
- [ ] **Fixed-cost feasibility enforcement** in annuitization search
- [x] **Survey weights** discussion/justification paragraph — ADDED 2026-04-02
- [ ] **Age-band health transitions** — 4-5 HRS matrices (2 hrs code + rerun)
- [ ] **Moment validation** improvements (sample-level, not representative agent)
- [ ] **Out-of-grid welfare handling** — exclude or flag clamped households
- [ ] **MWR payment-timing convention** footnote
- [ ] **Inflation channel** clarification (product counterfactual vs erosion reversal)

## Tier 4: Nice to Have (revision-stage if referee asks)

- [ ] Age-varying survival pessimism
- [ ] Behavioral robustness check (alternative belief wedges)
- [ ] SS/DB pension separation in discussion
- [ ] Populate actual annuity ownership from HRS
- [ ] Cubic interpolation for tighter Euler residuals
- [ ] CEV grid as heatmap instead of sparse table
- [ ] AI disclosure moved to end-of-paper

## Execution Sequence

1. ~~**Phase 1:** Investigate Tier 1 potential bugs~~ DONE 2026-04-02
2. ~~**Phase 2:** Fix all Tier 2 items (manuscript text, documentation, consistency)~~ MOSTLY DONE 2026-04-02
3. **Phase 3:** Run Tier 3 computations (quadrature, age-band health, SS cuts)
4. **Phase 4:** Final manuscript revision, recompile, consistency audit, commit, push

**Remaining before submission:** GitHub release tag, test suite headline lock, Tier 3 computations (optional but strengthening)
