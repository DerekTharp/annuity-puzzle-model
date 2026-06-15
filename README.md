# Quantifying the Annuity Puzzle: A Unified Lifecycle Decomposition

Replication package for Tharp (working paper). A calibrated lifecycle model
nests the channels proposed to explain low voluntary annuity demand among US
retirees in a single framework and attributes the annuity-demand gap with an
exact, order-independent Shapley decomposition. The channels are organized in
three layers:

- **Seven rational channels:** pre-existing Social Security annuitization,
  bequest motives, medical expenditure risk, health-mortality correlation
  (Reichling-Smetters), subjective survival pessimism, pricing loads, and
  inflation erosion.
- **Two preference channels:** age-varying consumption needs
  (Aguiar-Hurst 2013) and state-dependent utility (Finkelstein-Luttmer-
  Notowidigdo 2013).
- **Two exploratory behavioral channels:** source-dependent utility
  (Blanchett-Finke 2024, 2025) raises annuitization by converting portfolio
  wealth into "spendable income"; a narrow-framing purchase-event disutility
  (Hu-Scott 2007; Brown 2008; Chalmers-Reuter 2012) suppresses it through loss
  aversion over the unrecouped premium until breakeven. Behavioral parameters
  (lambda_W = 0.625, psi = 0.05) are treated as exploratory literature-magnitude
  best guesses, not moment-matched estimates.

## Headline result

The contribution is the **order-independent ranking** of demand channels, not a
point prediction of the ownership level. An exact Shapley decomposition over all
512 subsets of the nine structural channels (seven rational + two preference,
with public-care aversion entering as a structural-LTC channel) attributes the
demand gap without dependence on the order in which channels are introduced.
Pricing loads are the dominant suppressor (~81% of the structural drop), with
survival pessimism and the combined medical-expenditure/health-mortality channel
as the co-leading second tier, and bequest motives -- the most-cited explanation
in the literature -- mid-pack.

The ranking is stable where the predicted **level** is not: predicted ownership
is knife-edged in risk aversion (it spans 0% to roughly 22% across
gamma in [2.0, 3.0]) because the extensive margin sits on the minimum-purchase
threshold, while the channel ranking holds across risk aversion, across wealth
quartiles, and across the discrete-vs-continuous demand statistic. The nine-
channel structural baseline predicts roughly 8% ownership under the baseline
calibration (gamma = 2.5, MWR = 0.87, Wettstein-2021 modern pricing); predicted
ownership concentrates in the top wealth quartile and is essentially zero below
it. An exploratory eleven-channel Shapley over 2,048 subsets adds the two
behavioral parameters; they carry large but offsetting contributions and do not
disturb the structural ranking.

Two HRS measures of US lifetime annuity ownership (computed on the same
wealth-restricted analysis sample as the model predictions) are reported in
parallel as out-of-sample checks, neither entering the calibration: 3.11%
(95% CI [2.54%, 3.81%], the cleaner fat-file q286 lifetime annuity contract
indicator) and 5.21% (95% CI [4.45%, 6.09%], the conventional any-annuity
income proxy used in prior literature).

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

To run only the tests, use `julia --project=. test/runtests.jl` (the canonical
test runner). The project is intentionally not configured as a package for
`Pkg.test()`: each test file is `include`d in a separate process to avoid the
module re-definition conflicts that the codebase's include-based loading would
otherwise produce.

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
bequests (theta=56.96, kappa=$272,628), hazard multipliers [0.50, 1.0, 3.75],
survival pessimism psi=0.96 (Heimer-Myrseth-Schoenle 2019; Payne et al. 2013),
age-varying needs delta_c=0.02, health-utility weights [1.0, 0.92, 0.82]
(FLN 2013 central midpoint), **lambda_W=0.625** (source-dependent utility,
Blanchett-Finke 2024/2025 spending differential point estimate; exploratory),
**psi_purchase=0.05** (purchase-event disutility, literature-magnitude best
guess; exploratory, not moment-matched), 9-node Gauss-Hermite quadrature,
80x30x101 production grid (W x A x alpha).

## Data

The repository ships with all processed CSVs needed to run the structural
pipeline (Stages 1+) without raw-data access. Raw inputs are only needed to
regenerate the processed CSVs from scratch (Stage 0b onward).

**Processed CSVs (checked in).** Each is regenerated by one calibration script
from the raw RAND HRS inputs:
- `data/processed/lockwood_hrs_sample.csv` -- HRS population sample
  (5,303 person-wave observations, single retirees aged 65--69, waves 5--9);
  `calibration/pashchenko_replication.jl`.
- `data/processed/hrs_lifetime_ownership.csv` -- HRS lifetime annuity
  contract indicator (q286 fat-file series), pooled across waves 5--9;
  `calibration/compute_lifetime_ownership_rate.jl`.
- `data/processed/ss_income_profile.csv` -- claimer-conditional Social Security
  and pension-only DB income by wealth quartile (2014 dollars);
  `calibration/build_ss_profile.jl`.
- `data/processed/health_transitions_age_bands.csv` -- three-state health
  Markov transition matrices by age band;
  `calibration/estimate_health_transitions.jl`.
- `data/processed/hrs_hazard_ratios.csv` -- health-specific mortality hazard
  ratios by age band; `calibration/compute_hazard_ratios.jl`.
- `data/processed/hrs_validation_sample.csv` -- cross-sectional sample for the
  empirical ownership-gradient validation; `calibration/build_validation_sample.jl`.
- `data/processed/hrs_acquisition_decomposition.csv` and
  `hrs_acquisition_decomposition_robust.csv` -- HRS annuity-acquisition
  covariate decomposition (baseline and robustness);
  `calibration/decompose_hrs_acquisition.jl` and `..._robust.jl`.

**Raw inputs (not checked in; institutional access required):**
- RAND HRS Longitudinal File 2022 (v1) -- free, requires HRS account,
  <https://hrsdata.isr.umich.edu>.
- HRS public survey "fat files" -- pension/wealth modules per wave.

See `data/raw/README.md` for full provenance and expected paths.

The pipeline gracefully skips raw-data stages if the source files are
absent and falls back to the checked-in processed CSVs. To force full
regeneration when raw inputs are present, set `ANNUITY_FORCE_HRS_REBUILD=1`.

## Code Organization

```
src/                   Model source code (module: AnnuityPuzzle)
scripts/               Analysis scripts (decomposition, welfare, robustness)
scripts/config.jl      Canonical parameter configuration
test/                  Test suite (including manuscript-number lock)
data/processed/        Processed calibration inputs
tables/                LaTeX and CSV output tables
figures/               Publication-quality figures (PDF and PNG)
paper/                 Manuscript and appendix
run_all.jl             Master pipeline script
```

## Author

Derek Tharp, University of Southern Maine
derek.tharp@maine.edu
