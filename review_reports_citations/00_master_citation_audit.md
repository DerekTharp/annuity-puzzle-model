# Master Citation Audit

This file consolidates the six section-level citation audits for `paper/main.tex` and `paper/appendix.tex`. The full row-level audit is in `00_master_citation_audit.csv`; the section reports remain available for easier manuscript-by-manuscript review.

## Coverage

- Audited files: `paper/main.tex`, `paper/appendix.tex`, `paper/bibliography.bib`, and local reference files in `potential references/`.
- Citation-claim pairs audited: `81`.
- Supported: `47`.
- Partially supported: `26`.
- Not supported: `4`.
- Cannot verify locally: `4`.

## Highest-Priority Citation Fixes

| manuscript_location | citation_key | manuscript_claim | assessment | why_it_needs_attention |
|---|---|---|---|---|
| paper/main.tex:65 | `poterbaventiwise2011` | Poterba, Venti, and Wise support the claim that voluntary ownership is 3-6 percent. | not supported | This paper supports liquidity/minimum-investment frictions, not the cited ownership-rate range. |
| `paper/main.tex:292, 323` | `chetty2006` | Gamma is within a Chetty range of 1-3 estimated from labor-supply elasticities. | not supported | The manuscript's 1-3 range is much broader than the cited result and is not a fair summary of the paper. |
| `paper/main.tex:312` | `lockwood2012` | The fixed annuity purchase cost is 1,000 dollars, attributed to Lockwood. | not supported | This is the clearest numerical mismatch in the block. If the manuscript uses 1,000 on purpose, it needs a different citation or an explicit explanation. |
| `paper/main.tex:379` | `pashchenko2013` | This health-mortality correlation channel was omitted by Pashchenko. | not supported | This is the clearest overstatement in the block. Pashchenko explicitly discusses health-linked mortality and medical costs, so she did not omit the mechanism as stated here. |
| paper/main.tex:67 | `hosseini2015` | Hosseini shows heterogeneous mortality interacts with adverse selection to amplify loads. | cannot verify locally | The bibliography contains the citation, but no matching local paper file was present to check the claim. |
| paper/main.tex:73 | `chetty2006` | Chetty (2006) supports the empirically plausible gamma range used in the sensitivity check. | cannot verify locally | The bibliography has the citation, but no matching local source file was available for verification. |
| `paper/main.tex:110-112, 294-295, 325` | `lockwood2012` | The DFJ bequest parameters are taken directly from Lockwood's HRS calibration, and using one parameter with the other replaced is not a valid counterfactual. | cannot verify locally | The manuscript may well be using the correct code values, but the local text I could inspect does not expose the exact numeric pair, so the claim cannot be fully verified from the saved source text alone. |
| `paper/appendix.tex:354` and `paper/main.tex:323` | `chetty2006` | The implied risk-aversion range is 1-3, so `gamma = 2.5` and the implied median `gamma = 2.73` are within the cited Chetty range. | cannot verify locally | `paper/bibliography.bib` has a `chetty2006` entry, but the corresponding paper is not present in the local reference library. |

## Coverage Gaps / Metadata Issues

- `chetty2006` has a bibliography entry but no matching local paper file in `potential references/`.
- `hosseini2015` is cited in the manuscript but no matching local source file was found in `potential references/`.
- `james2006` is cited in the manuscript but no matching local source file was found in `potential references/`.
- `ameriks2020` is cited in the manuscript but no matching local source file was found in `potential references/`.
- `tharp2025survey` is cited but the best local match is the survey draft at `docs/dissolving_annuity_puzzle_survey.md`, not a source in `potential references/`.
- `tharpforthcoming` is cited in `paper/main.tex` but has no matching bibliography entry in `paper/bibliography.bib`.

## Additional Notes

- The sentence about Social Security trust-fund exhaustion at `paper/main.tex:521` is currently uncited and should be sourced or softened.
- A few rows rely on PDF or abstract fallback when no local `.txt` source was available, especially for `james2006` and `ameriks2020`.

## Section Reports

- `01_intro_audit.md`
- `02_model_calibration_audit.md`
- `03_results_counterfactuals_audit.md`
- `04_discussion_conclusion_audit.md`
- `05_appendix_methods_audit.md`
- `06_appendix_crosscheck_audit.md`

## How To Use The CSV

- Each row is one citation-claim pair.
- `source_text_or_best_match` contains the exact supporting text or the closest verifiable passage found.
- `assessment` is one of `supported`, `partially supported`, `not supported`, or `cannot verify locally`.
- When the manuscript is more precise than the source text, the row is typically marked `partially supported` rather than `not supported`.

