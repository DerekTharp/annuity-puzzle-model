# Revision Plan — Synthesized from 20 Expert Reviews

**Date:** 2026-03-24
**Reviews:** 10 economics reviewers (Round 1) + 10 code reviewers (Round 2)
**Economics score:** 6.8/10 | **Code score:** 6.2/10

---

## Tier 1: Potential Bugs (investigate first — may change results)

- [ ] **Welfare mispricing** — `src/welfare.jl:318-372` may use real payout rate where nominal pricing should apply. If confirmed, CEV numbers change.
- [ ] **DIA repricing** — `src/wtp.jl:555-570` may reprice deferred products as immediate for ages >65. If confirmed, appendix DIA table changes.
- [ ] **Grid cap clipping** — W_max=$1.1M but HRS sample has households above this. Check how many obs affected; raise W_max or document exclusion.
- [ ] **Forward simulation timing** — solver averages over medical shocks, simulator applies single policy. Check if materially affects simulated moments. May just need documentation.

## Tier 2: Must Fix Before Submission

- [ ] Sync all headline numbers across highlights.txt, README.md, manuscript, figures
- [ ] Reframe paper as "calibrated structural exercise" not identification/estimation
- [ ] Trim intro density (move exact numbers to results section)
- [ ] Add bequest decomposition explanation (zero standalone vs 19% counterfactual)
- [ ] Soften overclaiming language ("matching" → "consistent with"; "multiplicatively" → qualified)
- [ ] Fix pipeline contract break (Lockwood artifact in run_all.jl)
- [ ] ModelParams defaults match manuscript baseline (age_end=110)
- [ ] Add release tag to GitHub
- [ ] Test suite locks 5.3% headline result
- [ ] Document own_life_ann placeholder in CSV
- [ ] Clarify person-wave vs unique individuals in sample description
- [ ] SS cut labeled as stylized elasticity experiment
- [ ] SS real vs nominal distinction emphasized
- [ ] Soften "behavioral confirmatory" claim
- [ ] DIA comparison rephrased (confounded with pricing)
- [ ] Clarify survey weights choice (unweighted, with justification)
- [ ] Trim conclusion redundancy

## Tier 3: Should Fix (strengthens paper meaningfully)

- [ ] **Shapley decomposition** — 100-500 random permutations (~$15 AWS, 4 hrs)
- [ ] **SS cut robustness table** — vary cut 10-50% (~$5 AWS, 2 hrs)
- [ ] **Quadrature convergence** — test at 11, 13, 15 nodes (~$10 AWS, 3 hrs)
- [ ] **Fixed-cost feasibility enforcement** in annuitization search
- [ ] **Survey weights** discussion/justification paragraph
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

1. **Phase 1:** Investigate Tier 1 potential bugs (welfare.jl, wtp.jl, grid cap, simulation timing)
2. **Phase 2:** Fix all Tier 2 items (manuscript text, documentation, consistency)
3. **Phase 3:** Run Tier 3 computations on AWS (Shapley, quadrature, SS cuts)
4. **Phase 4:** Final manuscript revision, recompile, consistency audit, commit, push

**Estimated timeline:** 4-5 days focused work, ~$30-50 AWS compute
