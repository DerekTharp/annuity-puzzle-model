# Quantifying the Annuity Puzzle: A Unified Lifecycle Decomposition

Replication package for Tharp (working paper). A calibrated lifecycle model
nests ten channels proposed to explain low voluntary annuity demand among
US retirees, organized in three layers:

- **Six rational channels:** pre-existing Social Security annuitization,
  bequest motives, combined medical expenditure risk and health-mortality
  correlation (Reichling-Smetters bundled with medical risk because the R-S
  mechanism's quantitative bite operates through the interaction with
  stochastic medical costs in this framework: without a competing use for
  liquid wealth in sick states, a lower expected annuity NPV when sick does
  not translate into a precautionary motive against annuitization),
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
combining the conservative ABI aggregate (the 75 pp pre/post drop in DC-pot
annuity ownership when the regulated default flipped from compulsory to
opt-in, after stripping the rational tax-removal response; psi=0.0163;
ABI quarterly contract volumes fell by a similar proportional magnitude,
corroborating the level shift) and a descriptive ELSA microdata total drop
in observed disposition (psi=0.0335). The corresponding bracket of predicted US voluntary ownership
is [2.3%, 24.5%].
Two HRS measures of US lifetime annuity ownership are reported in parallel
as out-of-sample empirical targets: 2.02% (95% CI [1.68%, 2.43%], the
cleaner fat-file q286 lifetime annuity contract indicator) and 3.34% (95% CI
[2.89%, 3.85%], the conventional any-annuity income proxy). The conventional
income-proxy measure lies inside the model's UK-anchored bracket; the
cleaner lifetime-contract indicator overlaps only the bracket's lower edge.

An exact Shapley decomposition over all 1,024 channel subsets attributes the
demand reduction without order dependence. The narrow-framing purchase
penalty has the largest single Shapley value; Force A enters with the
opposite sign, a pattern consistent with operation on distinct decision
margins rather than redundant parameterizations of the same wedge.

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
80x30x101 production grid (W x A x alpha).

## Data

The repository ships with all processed CSVs needed to run the structural
pipeline (Stages 1+) without raw-data access. Raw inputs are only needed to
regenerate the processed CSVs from scratch (Stages 0b--0e).

**Processed CSVs (checked in):**
- `data/processed/lockwood_hrs_sample.csv` -- HRS population sample
  (5,303 person-wave observations, single retirees aged 65--69, waves 5--9).
- `data/processed/hrs_lifetime_ownership.csv` -- HRS lifetime annuity
  contract indicator (q286 fat-file series), pooled across waves 5--9.
- `data/processed/elsa_pre_post_freedoms.csv` -- UK ELSA wave 6 vs.
  waves 8--11 disposition comparison.
- `data/processed/elsa_disposition_pooled.csv` -- UK ELSA waves 8--11
  pooled lump-sum disposition rates.
- `data/processed/elsa_disposition_subgroups.csv` -- UK ELSA subgroup
  robustness (age, sex, education, health).

**Raw inputs (not checked in; institutional access required):**
- RAND HRS Longitudinal File 2022 (v1) -- free, requires HRS account,
  <https://hrsdata.isr.umich.edu>.
- HRS public survey "fat files" -- pension/wealth modules per wave.
- UK ELSA archive deposit 5050 -- UK Data Service registration required,
  <https://beta.ukdataservice.ac.uk/datacatalogue/series/series?id=200011>.

See `data/raw/README.md` for full provenance and expected paths.

The pipeline gracefully skips raw-data stages if the source files are
absent and falls back to the checked-in processed CSVs. To force full
regeneration when raw inputs are present, set `ANNUITY_FORCE_HRS_REBUILD=1`.
The ELSA archive path can be overridden via `ANNUITY_ELSA_ARCHIVE`.

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
