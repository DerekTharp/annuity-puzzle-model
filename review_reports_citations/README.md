# Citation Audit Handoff

This folder contains the full reference/citation audit and the follow-up patch list.

## Key Files

- Master audit summary: `review_reports_citations/00_master_citation_audit.md`
- Master row-level audit table: `review_reports_citations/00_master_citation_audit.csv`
- Actionable patch list: `review_reports_citations/01_citation_patch_list.md`
- Patch list in CSV form: `review_reports_citations/01_citation_patch_list.csv`

## Section-Level Reports

- `review_reports_citations/01_intro_audit.md`
- `review_reports_citations/02_model_calibration_audit.md`
- `review_reports_citations/03_results_counterfactuals_audit.md`
- `review_reports_citations/04_discussion_conclusion_audit.md`
- `review_reports_citations/05_appendix_methods_audit.md`
- `review_reports_citations/06_appendix_crosscheck_audit.md`

## Manuscript Files Audited

- Main manuscript: `paper/main.tex`
- Appendix: `paper/appendix.tex`
- Bibliography: `paper/bibliography.bib`

## Local Source Library Used For Verification

- Primary reference folder: `potential references/`
- Survey draft used for local unpublished-source cross-checks: `docs/dissolving_annuity_puzzle_survey.md`

## Known Source-Library Gaps

- `chetty2006`
- `hosseini2015`
- `james2006`
- `ameriks2020`
- `tharpforthcoming` is cited in the manuscript but does not exist as a bibliography key; the closest existing key is `tharp2025survey`.

## Suggested Workflow

1. Start with `01_citation_patch_list.md`.
2. Make the `P0` edits in `paper/main.tex` and `paper/bibliography.bib`.
3. Use `00_master_citation_audit.csv` for row-level fact checking while editing.
4. Re-run a narrow citation audit on the edited lines.
