# Gemini Review Folder — Annuity Puzzle Replication Package

This folder packages the manuscript and replication code into **10 uploadable
files** that fit the Gemini upload limit. The 10 files are `01_*.tex` through
`10_*.jl`. This `00_README.md` is a guide for the user assembling the upload;
it is **not** one of the 10 files Gemini reads.

## What to upload

Upload these 10 files (in order) to Gemini:

| # | File | Original location(s) | Size |
|---|------|----------------------|------|
| 01 | `01_manuscript.tex` | `paper/main.tex` | ~115 KB |
| 02 | `02_appendix.tex` | `paper/appendix.tex` | ~46 KB |
| 03 | `03_overview.md` | README + cover letter + Project.toml + run_all.jl + numbers.tex | ~45 KB |
| 04 | `04_model_core.jl` | 7 src files (module, params, utility, income, lifetable, grids, annuity) | ~34 KB |
| 05 | `05_solver.jl` | 4 src files (bellman, solve, simulation, diagnostics) | ~39 KB |
| 06 | `06_health_welfare.jl` | 3 src files (health, welfare, wtp) | ~56 KB |
| 07 | `07_decomposition.jl` | 1 src + 3 scripts (decomposition + 3 run_* drivers) | ~104 KB |
| 08 | `08_calibration_robustness.jl` | 11 scripts (config + estimation + sensitivity sweeps) | ~108 KB |
| 09 | `09_validation_export.jl` | 10 scripts (replications + welfare CFs + figures + numbers exporter) | ~155 KB |
| 10 | `10_tests.jl` | 12 test files | ~106 KB |

Total: ~810 KB across 10 files.

## How the merges work

Files 04 through 10 each consolidate multiple original source files. Each
merged file begins with a header listing its constituent files in order, and
each constituent is preceded by a banner of the form:

```julia
#=============================================================================
# ORIGINAL FILE: src/utility.jl
#=============================================================================
```

In `03_overview.md`, the equivalent banner is a Markdown second-level header
(`## ORIGINAL FILE: README.md`).

## What was excluded and why

These files exist in the repository but are **not** included in the upload:

- `archive/` — superseded drafts and old result tarballs.
- `data/raw/` — institutional-access data (RAND HRS, ELSA archive). Provenance
  documented in `data/raw/README.md`; processed CSVs ship with the repo.
- `data/processed/` — processed calibration CSVs. Reviewable inside the model
  via the calibration code; not duplicated here.
- `figures/` and `tables/` — outputs of the pipeline. Their contents are
  summarized by macros in `paper/numbers.tex` (included in `03_overview.md`)
  and reproduced from code in files 04–10.
- `scripts/aws/` — AWS spot-instance launch and pull scripts. Operational, not
  part of the model itself.
- `scripts/diagnose_bequest_anomaly.jl`, `scripts/grid_convergence_isolated.jl`,
  `scripts/grid_convergence_joint.jl`, `scripts/run_euler_diagnostics.jl`,
  `scripts/test_bequest_specifications.jl` — exploratory or one-off
  diagnostics, superseded by other scripts in files 07–09.
- `test/test_headline_regression.jl.deprecated` — replaced by
  `test_manuscript_numbers.jl` and `test_age_invariance.jl`.
- `CLAUDE.md` — internal project context with development history and AI-tool
  usage notes; excluded to keep the review surface to publication-relevant
  artifacts.
- `docs/dissolving_annuity_puzzle_survey.md` — companion survey paper
  (separate publication track).

## Suggested prompt to Gemini

When uploading, lead with something like:

> I'm submitting a structural-economics replication package for review. The
> 10 attached files are organized as: file 01 is the manuscript, file 02 is
> the technical appendix, file 03 is the README plus reproducibility metadata,
> files 04–06 are the Julia model source code (~15 modules merged into 3
> files), files 07–09 are the analysis pipeline scripts (~24 scripts merged
> into 3 files), and file 10 is the test suite (~11 tests merged). Each
> merged file lists its constituents at the top and uses banner comments to
> separate them. Please review the model specification, identification, and
> code quality with an eye toward [target journal] standards.

## Regenerating this folder

If the source files change, regenerate by running:

```bash
bash Gemini_review/.build.sh
```

from the project root. The build script reads the current versions of every
constituent file and rebuilds files 01 through 10. The `00_README.md` is not
auto-generated — update it by hand if the file list changes.

## Pinned to commit

This folder reflects the source tree at commit `671d456` (Phase 17 — psi
anchor label rename) on branch `main`.
