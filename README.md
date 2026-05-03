# Quantifying the Annuity Puzzle: A Unified Lifecycle Decomposition

Replication package for Tharp (working paper). A calibrated lifecycle model
nests ten channels proposed to explain low voluntary annuity demand among
US retirees, organized in three layers:

- **Six rational channels:** pre-existing Social Security annuitization,
  bequest motives, combined medical expenditure risk and health-mortality
  correlation (Reichling-Smetters bundled with medical risk because R-S has
  no economic content without stochastic medical costs to correlate against),
  subjective survival pessimism, pricing loads, and inflation erosion.
- **Two preference channels:** age-varying consumption needs
  (Aguiar-Hurst 2013) and state-dependent utility (Finkelstein-Luttmer-
  Notowidigdo 2013).
- **Two behavioral channels operating at distinct decision moments and pointing
  in opposite directions:** source-dependent utility (Force A; Blanchett-Finke
  2024, 2025) raises annuitization by converting portfolio wealth into
  "spendable income"; a narrow-framing purchase-event disutility (Force B;
  Barberis-Huang 2009 narrow framing under Tversky-Kahneman 1992 loss
  aversion) suppresses it through loss aversion over the unrecouped premium
  until breakeven.

Under baseline parameters (gamma = 2.5, MWR = 0.87, modern Wettstein-2021
pricing), the six rational channels predict 44.2% ownership relative to a
frictionless population benchmark of 41.4%. Adding the two preference
channels brings the prediction to 34.3%; adding Force A (source-dependent
utility, lambda_W = 0.625) raises it to 79.3%. The Force B parameter
psi_purchase is anchored to UK post-reform evidence (2015 pension freedoms),
combining the conservative ABI aggregate (60 pp behavioral residual after
stripping the rational tax-removal response, psi=0.0163) and a descriptive
ELSA microdata sensitivity bound (88 pp total drop, psi=0.0335). The
corresponding bracket of predicted US voluntary ownership is [2.3%, 24.5%].
Two HRS measures of US lifetime annuity ownership are reported in parallel
as out-of-sample empirical targets: 2.02% (95% CI [1.68%, 2.43%], the
cleaner fat-file q286 lifetime annuity contract indicator) and 3.34% (95% CI
[2.89%, 3.85%], the conventional any-annuity income proxy). Both are
consistent with the model's UK-anchored bracket.

An exact Shapley decomposition over all 1,024 channel subsets attributes the
demand reduction without order dependence. The narrow-framing purchase
penalty has the largest single Shapley value; Force A enters with the
opposite sign, confirming that the two behavioral channels are empirically
distinct mechanisms rather than redundant parameterizations of the same
wedge.

**All headline numbers in the manuscript are auto-generated from analysis CSV
outputs by `scripts/export_manuscript_numbers.jl` and locked by
`test/test_manuscript_numbers.jl`.** Don't hand-edit `paper/numbers.tex` or
the table inputs.

## Requirements

- **Julia:** 1.12+ (tested on 1.12.5)
- **Key packages:** Interpolations.jl, Distributions.jl, Optim.jl,
  QuantEcon.jl, DataFrames.jl, CSV.jl, Plots.jl
- **Hardware:** 4 GB RAM minimum; 16 GB recommended for parameter sweeps

All dependencies are pinned in `Manifest.toml`.

## Quick Start

```bash
julia --project=. -e 'using Pkg; Pkg.instantiate()'
julia --project=. run_all.jl
```

`run_all.jl` runs the test suite first by default; pass `--skip-tests` for
faster iteration during development (NEVER for production).

## Runtime

The full pipeline takes approximately 3 hours on a 192-vCPU AWS c7a.48xlarge
spot instance, or 12+ hours on a 16-core Mac Studio. Individual scripts run
in minutes to tens of minutes. Use `julia --project=. -p N` to parallelize
compute-heavy scripts across N cores.

For AWS execution see `scripts/aws/launch.sh` (provisions a spot instance,
syncs the project, runs the full pipeline, and auto-terminates on completion).

## Configuration

Baseline parameters are defined in `scripts/config.jl`. Key values: gamma=2.5,
beta=0.97, **MWR=0.87** (Wettstein 2021 modern-pricing), inflation=2%, DFJ
bequests (theta=56.96, kappa=$272,628), hazard multipliers [0.50, 1.0, 3.0],
survival pessimism psi=0.981, age-varying needs delta_c=0.02, health-utility
weights [1.0, 0.90, 0.75] (FLN 2013 raw central), **lambda_W=0.625** (Force A,
Blanchett-Finke 2024/2025 spending differential), **psi_purchase=0.0163**
(Force B, UK 2015 pension-freedoms midpoint anchor; bracket [0.0142, 0.0281]
across alternative SMM specifications), 9-node Gauss-Hermite quadrature,
60x20x51 production grid.

## Data

Processed HRS sample (5,303 person-wave observations with observed health) is at
`data/processed/lockwood_hrs_sample.csv`. Raw data requires a RAND HRS
Longitudinal File account (free, https://hrsdata.isr.umich.edu).

## Code Organization

```
src/                   Model source code (module: AnnuityPuzzle)
scripts/               Analysis scripts (decomposition, welfare, robustness)
scripts/config.jl      Canonical parameter configuration
test/                  Test suite (9 files, including manuscript-number lock)
data/processed/        Processed calibration inputs
tables/                LaTeX and CSV output tables
figures/               Publication-quality figures (PDF and PNG)
paper/                 Manuscript and appendix
run_all.jl             Master pipeline script
```

## Author

Derek Tharp, University of Southern Maine
derek.tharp@maine.edu
