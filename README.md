# Loads, Not Bequests: An Order-Independent Decomposition of the Annuity Puzzle

Replication package for Tharp (working paper). A calibrated lifecycle model
nests the channels proposed to explain low voluntary annuity demand among US
retirees in a single framework and attributes the annuity-demand gap with an
exact, order-independent Shapley decomposition. The channels are organized in
three layers:

- **Seven rational channels:** pre-existing Social Security annuitization,
  bequest motives, combined medical-expenditure and health-mortality
  (Reichling-Smetters) risk, subjective survival pessimism, pricing loads,
  inflation erosion, and public-care aversion (a long-term-care/Medicaid
  channel). Medical risk and the R-S correlation enter as a single channel
  because the correlation has quantitative bite only through medical risk.
- **Two preference channels:** age-varying consumption needs
  (Aguiar-Hurst 2013) and state-dependent utility (Finkelstein-Luttmer-
  Notowidigdo 2013).
- **Two exploratory behavioral channels:** source-dependent utility
  (Blanchett-Finke 2024, 2025) raises annuitization by converting portfolio
  wealth into "spendable income"; a narrow-framing purchase-event disutility
  (Hu-Scott 2007; Brown 2008; Chalmers-Reuter 2012) suppresses it through loss
  aversion over the unrecouped premium until breakeven. Behavioral parameters
  (lambda_W = 0.625, psi_purchase = 0.05) are treated as exploratory
  literature-magnitude best guesses, not moment-matched estimates.

## Headline result

The contribution is the **order-independent ranking** of demand channels, not a
point prediction of the ownership level. An exact Shapley decomposition over all
512 subsets of the nine structural channels (seven rational + two preference,
with public-care aversion entering as a structural-LTC channel) attributes the
demand gap without dependence on the order in which channels are introduced.
Pricing loads are the dominant suppressor, survival pessimism is the sole
second tier, bequest motives -- the most-cited explanation in the literature --
are mid-pack, and the anchored Med+R-S (combined medical-expenditure and
health-mortality) attribution is near zero.

The ranking is stable where the predicted **level** is not: the baseline
predicts ownership well above the observed 3.64%/6.06% HRS measures, and the
level is quoted as a fragile range rather than a point (see the manuscript;
current values live in `paper/numbers.tex`). Predicted ownership is knife-edged
in risk aversion because the extensive margin sits on a fixed-cost threshold
interacting with the pricing load, while the channel ranking holds across the
gamma in [2.0, 3.0] range, across wealth bands, and at alternative baseline
money's worth ratios (boundary cases disclosed in the text). Predicted
ownership rises with wealth and concentrates in the upper bands (near-universal
at the top, partial in the upper-middle, near zero in the bottom two), because
the pricing load makes immediate annuitization value-destroying for all but the
wealthier. The observed HRS gradient also rises with wealth but is flatter: the
model reproduces the direction while overshooting the observed rate in the
upper-middle band and at the top (the level fragility documented in the paper). An exploratory
eleven-channel Shapley over 2,048 subsets adds the two behavioral parameters;
they carry the largest absolute contributions essentially by construction and
reorder the structural attributions, which is why the ranking is read off the
nine-channel game.

Two HRS measures of US lifetime annuity ownership (computed on the same
wealth-restricted analysis sample as the model predictions) are reported in
parallel as out-of-sample checks, neither entering the calibration: 3.64%
(the cleaner fat-file q286 lifetime annuity contract indicator) and 6.06%
(the conventional any-annuity income proxy used in prior literature); the
Wilson confidence intervals are in `paper/numbers.tex`.

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
faster iteration during development (NEVER for production). The compute stages
require the HRS population extract, which is not redistributable and must be
regenerated once from a free RAND HRS download -- see "Data availability"
below. The lock-test suite and the fast verification path run without it.

To run only the tests, use `julia --project=. test/runtests.jl` (the canonical
test runner). The project is intentionally not configured as a package for
`Pkg.test()`: each test file is `include`d in a separate process to avoid the
module re-definition conflicts that the codebase's include-based loading would
otherwise produce.

## Runtime

The full pipeline takes approximately 10 hours on a 192-vCPU AWS c7a.48xlarge
spot instance, or 12+ hours on a 16-core Mac Studio. Individual scripts run
in minutes to tens of minutes. Use `julia --project=. -p N` to parallelize
compute-heavy scripts across N cores.

### Fast verification path

For a laptop-scale check without the full 10-hour run: the test suite
(`julia --project=. test/runtests.jl`, ~6 minutes) locks every manuscript
number to its source CSV and exercises the solver on production-relevant
configurations; `EMG_SMOKE=1` runs the extensive-margin gate on a coarse grid
in minutes; and any single exhibit script can be run alone (see the exhibit
map below). The committed CSVs are the outputs of a from-scratch production
run, so the locks verify the deposit without re-solving.

For AWS execution see `scripts/aws/launch.sh` (provisions a spot instance,
syncs the project, runs the full pipeline, and auto-terminates on completion).

## Configuration

Baseline parameters are defined in `scripts/config.jl`. Key values: gamma=2.5,
beta=0.97, **MWR=0.87** (a deliberately conservative modern-market choice above the Mitchell-et-al./Wettstein anchors), inflation=2%, DFJ
bequests (theta=56.96, kappa=$272,628), hazard multipliers [0.50, 1.0, 3.75],
survival pessimism psi=0.981 (the O'Dea-Sturrock 2023 ages-65-69 ten-year
survival translation; psi=0.96 is the strong-pessimism robustness endpoint),
age-varying needs delta_c=0.02, health-utility weights [1.0, 0.92, 0.82]
(FLN 2013 central midpoint), **lambda_W=0.625** (source-dependent utility,
Blanchett-Finke 2024/2025 spending differential point estimate; exploratory),
**psi_purchase=0.05** (purchase-event disutility, literature-magnitude best
guess; exploratory, not moment-matched), 9-node Gauss-Hermite quadrature,
80x30x101 production grid (W x A x alpha).

## Data availability

The model is solved from calibration parameters and the processed inputs below;
no proprietary data are required to reproduce the structural results, tables, or
figures. All raw data used for calibration come from the Health and Retirement
Study (HRS), publicly available at no cost to registered users
(<https://hrsdata.isr.umich.edu>).

The repository ships with all *aggregate* processed CSVs (transition matrices,
hazard ratios, income profiles, band-level counts). Two person-level extracts
are NOT shipped because HRS conditions of use restrict redistribution of
individual-level records: `lockwood_hrs_sample.csv` (the HRS population file
over which the model is evaluated) and `hrs_validation_sample.csv`. The
compute stages (Stage 1 onward) require the population file, so running
`run_all.jl` end to end requires regenerating it first from a free RAND HRS
download (`ANNUITY_FORCE_HRS_REBUILD=1`; see below). Without HRS access, the
committed table/figure CSVs and the lock-test suite still verify the deposit
(see "Fast verification path"). HRS conditions of use prohibit redistributing
the person-level extracts to anyone, including journals; the deposit instead
provides the generating programs and reconstruction documentation, and any
journal replication requirement is handled per the HRS journal replication
policy (data exemption request, with reviewers obtaining the raw files
directly from HRS under their own free registration).

**Processed CSVs.** Each is regenerated by one calibration script from the
raw RAND HRS inputs. All aggregate CSVs are checked in; the two person-level
extracts (`lockwood_hrs_sample.csv`, `hrs_validation_sample.csv`) are NOT
shipped (HRS conditions of use) and must be regenerated locally:
- `data/processed/lockwood_hrs_sample.csv` -- HRS population sample
  (4,258 person-wave observations, single retirees aged 65--69, waves 5--9;
  person-level, not shipped); `calibration/build_hrs_sample.jl`.
- `data/processed/hrs_lifetime_ownership.csv` -- HRS lifetime annuity
  contract indicator (q286 fat-file series), pooled across waves 5--9;
  `calibration/compute_lifetime_ownership_rate.jl`.
- `data/processed/ss_income_profile.csv` -- claimer-conditional Social Security
  and pension-only DB income by wealth band (2014 dollars);
  `calibration/build_ss_profile.jl`.
- `data/processed/health_transitions_age_bands.csv` -- three-state health
  Markov transition matrices by age band;
  `calibration/estimate_health_transitions.jl`.
- `data/processed/hrs_hazard_ratios.csv` -- health-specific mortality hazard
  ratios by age band; `calibration/compute_hazard_ratios.jl`.
- `data/processed/hrs_lifetime_ownership_by_band.csv` -- lifetime annuity
  ownership by wealth band, person-wave and person-level counts;
  `calibration/q286_by_wealth_band.jl`.
- `data/processed/group_access_by_band.csv` -- group-annuity access rates by
  wealth band (employer-pension linkage); `calibration/build_group_access.jl`.
- `data/processed/hrs_validation_sample.csv` -- person-level cross-sectional
  extract for the empirical ownership-gradient checks (NOT shipped; regenerate
  via ANNUITY_FORCE_HRS_REBUILD=1); `calibration/build_validation_sample.jl`.
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

**Redistribution of HRS-derived files.** Two intermediate CSVs
(`lockwood_hrs_sample.csv`, `hrs_validation_sample.csv`) hold individual
person-wave records extracted from the RAND HRS file. HRS data are
distributed under a conditions-of-use agreement that restricts redistribution
of individual-level records, so these two files are NOT included in this
repository (they are gitignored and absent from its history). Users
regenerate them from their own RAND HRS download via
`ANNUITY_FORCE_HRS_REBUILD=1`; see the Data availability section for the HRS
access route. All checked-in processed CSVs are aggregates (transition
matrices, hazard ratios, income profiles, band-level ownership counts) and
carry no individual-level records; these and all calibration targets may be
shared freely.

## Reproducing the exhibits

`run_all.jl` regenerates every table and figure from the processed inputs. To
rebuild one exhibit, run its script directly (each writes to `tables/` and
`figures/`); `scripts/export_manuscript_numbers.jl` then refreshes
`paper/numbers.tex`, and `scripts/validate_pipeline.jl` checks that every
manuscript macro is defined and matches its source CSV.

| Manuscript exhibit | Generating script |
|---|---|
| Figures 1--5 | `scripts/generate_figures.jl` |
| Shapley decomposition (9- and 11-channel) | `scripts/run_subset_enumeration.jl` |
| Pairwise interactions, retention path | `scripts/run_decomposition.jl` |
| Welfare CEV grid | `scripts/run_welfare_analysis.jl` |
| CEV / welfare counterfactuals | `scripts/run_welfare_counterfactuals.jl` |
| Social Security cut robustness | `scripts/run_ss_robustness.jl` |
| gamma / inflation robustness | `scripts/run_robustness.jl` |
| Implied risk aversion | `scripts/run_implied_gamma.jl` |
| Moment validation | `scripts/run_moment_validation.jl` |
| Empirical ownership gradients | `scripts/run_empirical_validation.jl` |
| Pashchenko comparison | `scripts/run_pashchenko_comparison.jl` |
| DIA comparison | `scripts/run_dia_analysis.jl` |
| gamma-stability of the ranking | `scripts/run_shapley_gamma_stability.jl` |
| Monte Carlo uncertainty | `scripts/run_monte_carlo_uncertainty.jl` |
| Extensive-margin gate (F* distribution, smoothed gradient) | `scripts/run_extensive_margin_gate.jl` |
| Gate robustness ("killer table") | `scripts/run_gate_robustness.jl` |
| Band value-destruction diagnostic | `scripts/run_band3_diagnostic.jl` + `scripts/emit_band_value_destruction_table.jl` |
| Model-vs-data wealth-band table | `scripts/emit_model_vs_data_band_table.jl` |
| Channel-partition robustness | `scripts/run_partition_robustness.jl` |
| psi=0.96 endpoint ranking | `scripts/run_psi_endpoint_shapley.jl` (output `shapley_psi_endpoint.csv`) |
| Grid-robustness of the ranking | `scripts/run_grid_robustness_shapley.jl` |
| Seven-channel sub-game | `scripts/compute_subgame_shapley.jl` |
| Alternative-baseline Shapley + by-band policy MWRs | `scripts/run_referee_proofing.jl` |
| Grid convergence, Euler residuals | `scripts/grid_convergence_full.jl`, `scripts/run_euler_diagnostics.jl` -> `scripts/emit_diagnostic_tables.jl` |

**Development vs. production grids.** Grid sizes and quadrature nodes are set in
`scripts/config.jl`. Production exhibits use the 80x30x101 grid (W x A x alpha)
with 9-node quadrature. For fast iteration, coarsen the grid in `config.jl`
(e.g. 40x15x51): the channel ranking is stable to grid coarsening, but the
predicted ownership *level* is not, and levels should be quoted only from a
production run.

**On the ownership level.** The predicted level is a step function of the
threshold wealth band whose marginal household flips in or out of
participation, so intermediate specifications can differ across solution paths
(for example, the eight-channel decomposition step and the chi_LTC robustness
cell bracket the same region without coinciding). These intermediate levels are
not interchangeable and should not be quoted against one another. The headline
nine-channel level should be quoted only from `paper/numbers.tex`, and as a
fragile range; the paper's claims rest on the channel *ranking*, which is
order-independent and stable across risk aversion.

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

## License

Code and processed data in this repository are released under the MIT License
(see `LICENSE`). The underlying RAND HRS microdata are subject to the HRS data
use agreement and are not redistributed here.
