# Specific Revision Recommendations

## Bottom line

The paper now looks strongest as a **two-layer contribution**:

1. **Seven standard rational channels** reduce predicted ownership from **41.4% to 18.3%**, showing that the standard literature explains a large share of the gap but still overpredicts.
2. **Two added preference channels**, especially **age-varying consumption needs**, bring the full model to **6.6%**, near the observed 3--6% range.
3. The **exact 512-subset Shapley decomposition** is the clean methodological contribution that makes the attribution credible.

The revisions below are designed to make the manuscript tell that story clearly and credibly.

## P0: Must-fix before submission

### 1. Rebuild the front-end narrative around the 7-channel / 9-channel distinction

Files:

- `paper/main.tex`
- `paper/cover_letter.tex`
- `paper/highlights.txt`

Problem:

The manuscript currently states the new numbers, but it still reads like a one-shot "full model matches the data" paper. That undersells the stronger structure you now have.

Recommendation:

- Make the **7-channel result (18.3%)** the first main finding.
- Make the **9-channel result (6.6%)** the second main finding.
- Make the **exact Shapley decomposition** the third main finding.

Suggested contribution structure:

- **Contribution 1:** Standard rational channels explain much of the gap, but not all of it.
- **Contribution 2:** Age-varying consumption needs are a quantitatively important missing channel.
- **Contribution 3:** Exact Shapley decomposition gives order-independent attribution.

### 2. Synchronize all headline numbers from the authoritative tables

Files:

- `paper/main.tex`
- `paper/cover_letter.tex`
- `paper/highlights.txt`
- `tables/tex/welfare_counterfactuals.tex`
- `tables/tex/ss_cut_robustness.tex`
- `tables/tex/shapley_exact.tex`

Problem:

There are still small internal inconsistencies. The clearest one is group pricing:

- `43.2` in [main.tex](/Users/derektharp/Documents/_Projects/26.29%20Annuity%20Puzzle%20Simulation/paper/main.tex#L46)
- `43.2` in [cover_letter.tex](/Users/derektharp/Documents/_Projects/26.29%20Annuity%20Puzzle%20Simulation/paper/cover_letter.tex#L17)
- `43.2` in [highlights.txt](/Users/derektharp/Documents/_Projects/26.29%20Annuity%20Puzzle%20Simulation/paper/highlights.txt#L7)
- `43.1` in [welfare_counterfactuals.tex](/Users/derektharp/Documents/_Projects/26.29%20Annuity%20Puzzle%20Simulation/tables/tex/welfare_counterfactuals.tex#L11)

Recommendation:

- Choose one authoritative source of truth for all headline numbers, ideally the generated table files in `tables/tex/`.
- Standardize all public-facing mentions to that rounding convention.
- Do the same for all policy numbers, welfare figures, and the 7.4% intermediate result.

### 3. Add one visible table or panel for the 18.3 -> 7.4 -> 6.6 extension path

Files:

- `paper/main.tex`
- likely a new `tables/tex/*.tex` file

Problem:

The current manuscript states the extension numbers in prose, but the intermediate `7.4%` step is easy to miss because it does not have its own displayed table.

Recommendation:

- Either add two rows to the main decomposition display:
  - `+ Age-varying consumption needs -> 7.4`
  - `+ State-dependent utility -> 6.6`
- Or add a small two-row extension table immediately after the seven-channel decomposition.

Why this matters:

The manuscript should not make readers reconstruct the central quantitative path from scattered sentences.

### 4. Rewrite the abstract so it presents a hierarchy, not a data dump

File:

- `paper/main.tex`

Problem:

The abstract in [main.tex](/Users/derektharp/Documents/_Projects/26.29%20Annuity%20Puzzle%20Simulation/paper/main.tex#L44) currently tries to do everything at once: benchmark, 7-channel result, 9-channel result, Shapley ranking, counterfactuals, welfare.

Recommendation:

Use a four-part abstract:

- puzzle and contribution setup
- 7-channel result
- 9-channel result + Shapley result
- one policy/welfare takeaway

Specific cuts:

- Keep `41.4 -> 18.3 -> 6.6`
- Keep loads `30.3 pp` and age-needs `6.2 pp`
- Keep either the `13.8%` CEV or the SS-cut result, but not both
- Drop one or two smaller policy numbers from the abstract

## P1: High-value manuscript revisions

### 5. Tighten the introduction and reduce overclaiming

File:

- `paper/main.tex`

Key locations:

- [main.tex](/Users/derektharp/Documents/_Projects/26.29%20Annuity%20Puzzle%20Simulation/paper/main.tex#L60)
- [main.tex](/Users/derektharp/Documents/_Projects/26.29%20Annuity%20Puzzle%20Simulation/paper/main.tex#L69)
- [main.tex](/Users/derektharp/Documents/_Projects/26.29%20Annuity%20Puzzle%20Simulation/paper/main.tex#L75)

Recommendations:

- Shorten the literature-positioning paragraph by about 25%.
- Replace "This paper does so" with a more measured opener.
- Stop trying to make every paragraph prove novelty at once.
- Frame the paper as a **disciplined quantitative accounting exercise** rather than a definitive "resolution."

Preferred tone:

- "standard rational channels go a long way but do not fully close the gap"
- "age-varying needs close much of the remaining overprediction"
- "the full model reaches the observed range"

Tone to avoid:

- "the annuity puzzle is fundamentally a pricing puzzle"
- "the accumulated evidence is sufficient to account for observed demand" without qualification
- "none of the prior literature incorporated X" unless you are completely certain

### 6. Rename or qualify the "Yaari benchmark"

Files:

- `paper/main.tex`
- `tables/tex/retention_rates.tex`

Problem:

The paper repeatedly refers to a **41.4%** ownership outcome as the "Yaari benchmark." That invites an obvious objection because the theoretical Yaari benchmark is full annuitization.

Recommendation:

- Call it something like:
  - `Population-adjusted Yaari benchmark`
  - `HRS benchmark without SS`
  - `Frictionless benchmark in the empirical population`
- Then explain in one sentence that the empirical benchmark is below 100% because the participation metric is computed in the HRS sample with low-wealth households and the fixed cost still matters for marginal participation.

This will head off unnecessary seminar and referee confusion.

### 7. Make the Shapley decomposition the centerpiece of the attribution section

Files:

- `paper/main.tex`
- `tables/tex/shapley_exact.tex`

Problem:

The Shapley results are strong, but the paper still treats them partly like an add-on after the sequential decomposition.

Recommendation:

- Keep the sequential decomposition first because it is intuitive.
- But explicitly say the **Shapley table is the preferred attribution result** because it is order-independent.
- Consider making the Shapley table the first table discussed in the introduction's preview paragraph.

Also revise the interpretation:

- Loads are the **largest single channel**
- R-S correlation is the **largest omitted rational channel from prior unified models**
- State-dependent utility is **empirically present but quantitatively negligible in this framework**

### 8. Recast the welfare section around heterogeneity, not "zero for most"

Files:

- `paper/main.tex`
- `tables/tex/welfare_cev_grid.tex`
- `tables/tex/cev_counterfactuals.tex`

Key locations:

- [main.tex](/Users/derektharp/Documents/_Projects/26.29%20Annuity%20Puzzle%20Simulation/paper/main.tex#L475)
- [main.tex](/Users/derektharp/Documents/_Projects/26.29%20Annuity%20Puzzle%20Simulation/paper/main.tex#L535)

Recommendation:

- Lead with the positive finding:
  - CEV reaches `13.8%` at `$1,000,000` with no bequests
  - CEV remains economically meaningful with DFJ bequests
- Then explain that gains are concentrated in wealthier households.
- Add at least one population-level summary:
  - mean CEV
  - median CEV
  - share of households with strictly positive CEV

Why this matters:

Right now the welfare section is better than before, but it still reads defensively. It should instead support the paper's closing shift from a universal ownership puzzle to a **heterogeneous welfare question**.

### 9. Strengthen the Social Security section by foregrounding the non-monotonicity

Files:

- `paper/main.tex`
- `tables/tex/ss_cut_robustness.tex`

Recommendation:

- Treat the SS result as more than a robustness check.
- Explicitly state the mechanism in two regimes:
  - **moderate cuts** reduce crowd-out and raise private annuitization
  - **full elimination** destroys the income floor and lowers annuitization
- If space permits, add a simple figure for the SS-cut schedule rather than only a table.

This is one of the most JPubE-relevant parts of the paper and should read that way.

### 10. Demote state-dependent utility from headline novelty

Files:

- `paper/main.tex`
- `paper/highlights.txt`
- `paper/cover_letter.tex`

Problem:

The model includes state-dependent utility, but the Shapley value is only `0.1 pp`.

Recommendation:

- Keep it in the model for completeness.
- Present it as a robustness/completeness channel rather than a coequal contributor.
- Avoid giving it too much abstract or introduction real estate.

In the highlights especially, age-varying needs deserves the space; state-dependent utility does not.

## P2: Results presentation improvements

### 11. Move or compress pairwise interactions unless they are used heavily

File:

- `paper/main.tex`

Problem:

The pairwise interaction subsection is interesting, but it risks feeling like a lot of machinery after the exact Shapley result already made the main methodological point.

Recommendation:

- Keep one paragraph in the main text on the most important interactions.
- Move the full pairwise matrix to the appendix unless you are using it repeatedly later.

That gives more room for welfare and policy discussion, which matter more for JPubE.

### 12. Rewrite the discussion so it stops arguing with the old version of the paper

File:

- `paper/main.tex`

Key locations:

- [main.tex](/Users/derektharp/Documents/_Projects/26.29%20Annuity%20Puzzle%20Simulation/paper/main.tex#L602)

Recommendations:

- Replace "quantitatively sufficient to account for observed annuity demand" with a more disciplined formulation:
  - the 7-channel model narrows the gap substantially
  - the 9-channel extended model reaches the observed range
- Delete the sentence about the "residual gap between 6.6 and 3.6" unless you want to re-open a problem you no longer need.
- Reframe the behavioral paragraph as optional omitted mechanisms, not necessary rescue devices.

### 13. Rewrite the conclusion to match the actual contribution hierarchy

File:

- `paper/main.tex`

Key locations:

- [main.tex](/Users/derektharp/Documents/_Projects/26.29%20Annuity%20Puzzle%20Simulation/paper/main.tex#L627)

Recommendation:

The conclusion should end with this sequence:

1. standard rational channels explain much but not all of the gap
2. age-varying needs are a quantitatively important missing channel
3. exact Shapley identifies pricing as the largest channel and SS as dual-role
4. the welfare question is heterogeneous and policy-relevant

That is the cleanest high-status version of the paper.

## P3: Cover letter and highlights

### 14. Update the cover letter to sound like a JPubE paper, not just a methods paper

File:

- `paper/cover_letter.tex`

Recommendations:

- Lead with the JPubE angle:
  - Social Security crowd-out/complementarity
  - pricing frictions in retirement markets
  - welfare implications of annuity market design
- Mention exact Shapley, but do not let the cover letter read like a numerical methods note.
- Verify the repository URL before submission.

### 15. Rewrite the highlights to emphasize the three strongest takeaways

File:

- `paper/highlights.txt`

Recommended highlights structure:

- Standard rational channels reduce predicted ownership from `41.4%` to `18.3%`
- Age-varying consumption needs lower the prediction further to `7.4%`
- The full nine-channel model predicts `6.6%`, near observed ownership rates
- Exact Shapley decomposition shows pricing loads are the largest single channel
- Social Security both crowds in and crowds out private annuitization, depending on the environment

## P4: Literature and citation cleanup

### 16. Apply the existing citation audit before final submission

Files already prepared:

- [00_master_citation_audit.md](/Users/derektharp/Documents/_Projects/26.29%20Annuity%20Puzzle%20Simulation/review_reports_citations/00_master_citation_audit.md)
- [01_citation_patch_list.md](/Users/derektharp/Documents/_Projects/26.29%20Annuity%20Puzzle%20Simulation/review_reports_citations/01_citation_patch_list.md)

Recommendation:

- Apply the citation patch list before submission.
- In particular, make sure the literature framing around Pashchenko, fixed costs, risk-aversion ranges, and ownership-rate evidence is fully aligned with the audited sources.

## Suggested revision order

1. Synchronize all numbers and public-facing materials.
2. Rewrite abstract, introduction, discussion, and conclusion.
3. Add a visible display for `18.3 -> 7.4 -> 6.6`.
4. Rework welfare and SS sections so they read as substantive results.
5. Apply citation patch list.
6. Do one final consistency pass across manuscript, highlights, cover letter, and generated tables.

## Files to hand Claude Code

- [main.tex](/Users/derektharp/Documents/_Projects/26.29%20Annuity%20Puzzle%20Simulation/paper/main.tex)
- [cover_letter.tex](/Users/derektharp/Documents/_Projects/26.29%20Annuity%20Puzzle%20Simulation/paper/cover_letter.tex)
- [highlights.txt](/Users/derektharp/Documents/_Projects/26.29%20Annuity%20Puzzle%20Simulation/paper/highlights.txt)
- [00_synthesis.md](/Users/derektharp/Documents/_Projects/26.29%20Annuity%20Puzzle%20Simulation/review_reports_jpube_refresh/00_synthesis.md)
- [01_specific_revision_recommendations.md](/Users/derektharp/Documents/_Projects/26.29%20Annuity%20Puzzle%20Simulation/review_reports_jpube_refresh/01_specific_revision_recommendations.md)
- [00_master_citation_audit.md](/Users/derektharp/Documents/_Projects/26.29%20Annuity%20Puzzle%20Simulation/review_reports_citations/00_master_citation_audit.md)
- [01_citation_patch_list.md](/Users/derektharp/Documents/_Projects/26.29%20Annuity%20Puzzle%20Simulation/review_reports_citations/01_citation_patch_list.md)
