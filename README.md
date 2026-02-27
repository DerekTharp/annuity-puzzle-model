# Quantifying the Annuity Puzzle: A Unified Lifecycle Decomposition

Replication package for Tharp (working paper). A calibrated lifecycle model
nests nine channels proposed to explain low voluntary annuity demand among US
retirees: pre-existing Social Security annuitization, bequest motives, medical
expenditure risk, health-mortality correlation (Reichling-Smetters), subjective
survival pessimism, pricing loads, inflation erosion, age-varying consumption
needs (Aguiar-Hurst 2013), and state-dependent utility (Finkelstein-Luttmer-
Notowidigdo 2013). The full model predicts 6.6% voluntary annuity ownership
under baseline parameters (gamma = 2.5), consistent with observed rates of
3-6%. An exact Shapley decomposition over all 512 channel subsets identifies
pricing loads as the dominant channel (30.3 pp, 87% share).

## Requirements

- **Julia:** 1.12+ (tested on 1.12.5)
- **Key packages:** Interpolations.jl, Distributions.jl, Optim.jl,
  QuantEcon.jl, DataFrames.jl, CSV.jl, Plots.jl
- **Hardware:** 4 GB RAM minimum; 16 GB recommended for parameter sweeps

All dependencies are pinned in `Manifest.toml`.

## Quick Start

```bash
julia --project=. -e 'using Pkg; Pkg.instantiate()'
julia --project=. run_all.jl --skip-tests
```

## Runtime

The full pipeline (tests + all analyses) takes approximately 13 hours on a
96-vCPU machine or 6 hours on a 16-core Mac Studio. Individual scripts run in
minutes to tens of minutes. Use `julia --project=. -p N` to parallelize
compute-heavy scripts across N cores.

## Configuration

Baseline parameters are defined in `scripts/config.jl`. Key values: gamma=2.5,
beta=0.97, MWR=0.82, inflation=2%, DFJ bequests (theta=56.96,
kappa=$272,628), hazard multipliers [0.50, 1.0, 3.0], survival pessimism
psi=0.981, age-varying needs delta_c=0.02, health-utility weights
[1.0, 0.95, 0.85], 9-node Gauss-Hermite quadrature, 80x30x101 grid.

## Data

Processed HRS sample (5,303 person-wave observations with observed health) is at
`data/processed/lockwood_hrs_sample.csv`. Raw data requires a RAND HRS
Longitudinal File account (free, https://hrsdata.isr.umich.edu).

## Code Organization

```
src/                   Model source code (module: AnnuityPuzzle)
scripts/               Analysis scripts (decomposition, welfare, robustness)
scripts/config.jl      Canonical parameter configuration
test/                  Test suite (7 files, ~163K assertions)
data/processed/        Processed calibration inputs
tables/                LaTeX and CSV output tables
figures/               Publication-quality figures (PDF and PNG)
paper/                 Manuscript and appendix
run_all.jl             Master pipeline script
```

## Author

Derek Tharp, University of Southern Maine
derek.tharp@maine.edu
