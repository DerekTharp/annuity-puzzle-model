# v0.1 — Initial Draft

**Date:** 2026-02-28
**Status:** Archived. Superseded by v0.2 revision.

## Contents
- `main.tex` / `main.pdf` — Manuscript body (28 pages compiled)
- `appendix.tex` / `appendix.pdf` — Online appendix (10 pages compiled)
- `bibliography.bib` — 39 BibTeX entries
- `figures/` — 5 publication figures (PDF + PNG)
- `tables/` — All CSV and LaTeX tables from production runs

## Key Results (v0.1)
- Production calibration: gamma=2.5, hazard_mult=[0.50, 1.0, 3.0], MWR=0.82, inflation=2%
- Sequential decomposition: 97.5% → 1.4% (5 channels)
- Grid: 80x30x101, converged within ±0.2pp

## Why Archived
Internal peer review (10 reviewers) identified:
- Knife-edge gamma sensitivity (0% at 2.45, 5.3% at 2.55)
- Bequest parameters not re-estimated at gamma=2.5 (borrowed from Lockwood at gamma=2)
- Constant hazard multipliers overstate R-S at advanced ages
- No lifecycle moment validation beyond ownership rate
- "Dissolving" framing too strong for the parameter sensitivity observed
- AER editor assessment: reject, encourage field journal submission after revision
