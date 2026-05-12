# Annuity Puzzle Replication Package — Reviewer Overview

This file consolidates the reproducibility-relevant top-level documents for
external review. The full project repository is structured as described in
the README section below; the source code, scripts, and tests are split
across files 04 through 10 in this folder.


---

## ORIGINAL FILE: README.md

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
combining the conservative ABI aggregate sales-volume decline mapped through
the model after stripping the rational tax-removal response (psi=0.0163)
and a descriptive ELSA microdata total drop in observed disposition
(psi=0.0335). The corresponding bracket of predicted US voluntary ownership
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

---

## ORIGINAL FILE: paper/cover_letter.tex

```latex
\documentclass[11pt]{letter}
\usepackage[margin=1in]{geometry}
\usepackage{amsmath}
\usepackage{hyperref}

% Auto-generated numeric macros (same file used by main.tex and appendix.tex).
\input{numbers.tex}

\signature{Derek Tharp\\Department of Accounting \& Finance\\University of Southern Maine\\derek.tharp@maine.edu}

\begin{document}

\begin{letter}{Editors\\Journal of Public Economics}

\opening{Dear Professors Hendren and Kopczuk,}

I am submitting ``Quantifying the Annuity Puzzle: A Unified Lifecycle Decomposition'' for consideration at the \textit{Journal of Public Economics}.

Yaari (1965) proved that rational consumers should fully annuitize under actuarially fair pricing, yet voluntary ownership among US retirees is only a few percent. Six decades of research have proposed partial explanations for this gap, but the literature has lacked a unified quantitative accounting of how the main channels interact in a single model. Pashchenko (2013, \textit{JPubE}) came closest, but still predicted participation of roughly 20\%.

This paper begins from a standard rational and preference-based account of annuity demand and then \emph{adds two behavioral channels} that operate at distinct decision moments. The standard account comprises six rational channels and two preference channels (age-varying consumption needs from Aguiar-Hurst 2013 and state-dependent utility from Finkelstein-Luttmer 2013); on its own, it predicts \ownEightChannelExt{} ownership---substantially above both empirical targets. Source-dependent utility (Force A; Blanchett-Finke 2024, 2025) raises predicted ownership to \ownNineChannelSDU{} by unlocking the post-purchase ``license to spend'' on annuity income. A narrow-framing purchase-event disutility (Force B; Barberis-Huang 2009 narrow framing under Tversky-Kahneman 1992 loss aversion) suppresses it through loss aversion over the unrecouped premium until breakeven.

The Force B parameter $\psi_{\text{purchase}}$ is disciplined by an external UK post-reform calibration bracket, drawing on the 2015 pension-freedoms reform. The reform bundled tax, advice, default, and product-market changes; the UK evidence is best read as a market-design anchor rather than a clean causal estimate of a behavioral primitive. The English Longitudinal Study of Ageing (ELSA) pension grid records pre- and post-freedoms disposition: $\pctELSAWaveSixAnnuity$ of wave 6 DC pension recipients reported annuity-style income under the pre-freedoms mandate; pooling waves 8--11, $\pctELSAPostAnnuity$ of observed lump-sum disposition records used the lump sum to buy annuity income ($n = \nELSAPostLumpSum$). Pre- and post-freedoms ELSA samples use different denominators (DC recipients vs.\ lump-sum disposition records) and are unweighted pension-grid rows. The empirically defensible UK calibration anchor range spans the conservative ABI aggregate ($\psi_{\text{purchase}} = \pPsiBracketLow$; aggregate sales-volume decline mapped through the model after stripping the rational tax-removal response) and the aggressive ELSA microdata total drop in observed disposition ($\psi_{\text{purchase}} = \pPsiBracketHigh$). Mapped through the model, this yields a predicted US ownership bracket of $[\ownBracketLow, \ownBracketHigh]$. Two HRS measures of US lifetime annuity ownership are reported in parallel as out-of-sample empirical comparisons: $\pctHRSLifetime$ (95\% CI $[\pctHRSLifetimeCILow, \pctHRSLifetimeCIHigh]$, the cleaner fat-file lifetime contract indicator) and $\pctHRSIannPooled$ (95\% CI $[\pctHRSIannCILow, \pctHRSIannCIHigh]$, the conventional any-annuity income proxy used in prior literature). The conventional income proxy lies inside the bracket, while the cleaner lifetime-contract indicator overlaps only the lower edge. No US moment is used to discipline $\psi_{\text{purchase}}$.

The paper makes four contributions. First, the unified framework---the first to nest age-varying consumption needs alongside the established rational and preference channels of the annuity-puzzle literature. Second, the formal incorporation of two countervailing behavioral channels, each disciplined out of sample from independent empirical evidence, showing a pattern consistent with distinct decision margins rather than redundant parameterizations of the same wedge. Third, the use of the UK 2015 pension-freedoms reform as external calibration evidence for the purchase-event disutility, drawing on individual-level ELSA pension-grid records alongside industry aggregates. Fourth, an exact Shapley decomposition computed over all $1{,}024$ channel subsets, delivering order-independent attribution; the two behavioral channels enter with opposite-sign Shapley values, consistent with operation on distinct decision margins. Two distinct policy levers emerge: supply-side reform (group pricing raises predicted ownership at the conservative (ABI-anchored) bracket end to \ownGroupPricing) and demand-side reform (default architecture, modeled as $\psi_{\text{purchase}} = 0$, raises it to \ownNineChannelSDU), operating on different margins.

I believe the paper is a good fit for the \textit{Journal of Public Economics}. The paper engages the journal's core interests in Social Security, retirement saving, insurance-market frictions, and the design of public and employer-sponsored retirement institutions. It also directly engages with Pashchenko (2013) and related work published in \textit{JPubE} and neighboring outlets.

Replication code in Julia and all calibration data are publicly available at \url{https://github.com/DerekTharp/annuity-puzzle-model}. The manuscript has not been submitted elsewhere.

\closing{Sincerely,}

\end{letter}
\end{document}
```

---

## ORIGINAL FILE: Project.toml

```toml
[deps]
CSV = "336ed68f-0bac-5ca0-87d4-7b16caf5d00b"
DataFrames = "a93c6f00-e57d-5684-b7b6-d8193f3e46c0"
Distributions = "31c24e10-a181-5473-b8eb-7969acd0382f"
FastGaussQuadrature = "442a2c76-b920-505d-bb47-c5924d526838"
Interpolations = "a98d9a8b-a2ab-59e6-89dd-64a1c18fca59"
Optim = "429524aa-4258-5aef-a3af-852621145aeb"
Parameters = "d96e819e-fc66-5662-9728-84c9c7592b0a"
Plots = "91a5bcdd-55d7-5caf-9e0b-520d859cae80"
ReadStatTables = "52522f7a-9570-4e34-8ac6-c005c74d4b84"
ProgressMeter = "92933f4c-e287-5a05-a399-4b506db050ca"
QuantEcon = "fcd29c91-0bd7-5a09-975d-7ac3f643a60c"
TOML = "fa267f1f-6049-4f14-aa54-33bafae1ed76"
Test = "8dfed614-e22c-5e08-85e1-65c5234f0b40"
```

---

## ORIGINAL FILE: run_all.jl (master pipeline driver)

```julia
# Master pipeline: reproduce all results from raw data to final tables/figures.
#
# Usage:
#   julia --project=. run_all.jl              # full pipeline (tests + all analyses)
#   julia --project=. run_all.jl --skip-tests # skip test suite, run analyses only
#   julia --project=. run_all.jl --tests-only # run tests only
#
# Expected runtime on AWS c7a.48xlarge (192 vCPU): ~3 hours.
# Single-thread:  ~50 hours (1024 Shapley + 10 psi + 1000 MC + everything else).
# 20 stages total; expects all subset/Shapley/MC stages parallelized.
# For faster development runs, use --skip-tests and comment out Stage 12.
#
# Output:
#   tables/tex/*.tex   — LaTeX tables for paper (13 files)
#   tables/csv/*.csv   — machine-readable results
#   figures/pdf/*.pdf  — publication-quality figures
#   figures/png/*.png  — quick-inspection rasters
#   paper/numbers.tex  — auto-generated macros shared by main.tex/appendix.tex/cover_letter.tex
#   results/*/         — intermediate solution data

using Printf

const PROJECT_DIR = @__DIR__
const SCRIPTS_DIR = joinpath(PROJECT_DIR, "scripts")
const CALIB_DIR = joinpath(PROJECT_DIR, "calibration")
const TEST_DIR = joinpath(PROJECT_DIR, "test")
const TEST_RUNNER = joinpath(TEST_DIR, "runtests.jl")

skip_tests = "--skip-tests" in ARGS
tests_only = "--tests-only" in ARGS

# Workers per parallel stage. Default: min(nproc - 4, 192). Override via env:
#   ANNUITY_N_WORKERS=64 julia ... run_all.jl
# On laptop: ~6-8 workers (cores - 2 for OS).
# On AWS c7a.48xlarge: 188 workers (192 vCPU - 4 reserved).
const N_WORKERS = let
    env = get(ENV, "ANNUITY_N_WORKERS", "")
    if !isempty(env)
        parse(Int, env)
    else
        cores = Sys.CPU_THREADS
        cores >= 32 ? max(1, cores - 4) : max(1, cores - 2)
    end
end

function run_stage(label::String, script_path::String; parallel::Bool=false)
    @printf("\n%s\n", "=" ^ 70)
    @printf("  STAGE: %s\n", label)
    @printf("%s\n\n", "=" ^ 70)

    t0 = time()
    cmd = if parallel && N_WORKERS > 1
        `$(Base.julia_cmd()) --project=$PROJECT_DIR -p $N_WORKERS $script_path`
    else
        `$(Base.julia_cmd()) --project=$PROJECT_DIR $script_path`
    end
    proc = run(pipeline(cmd, stdout=stdout, stderr=stderr), wait=false)
    wait(proc)
    elapsed = time() - t0

    if proc.exitcode != 0
        @printf("\n  FAILED: %s (%.1fs)\n", label, elapsed)
        @printf("  Aborting pipeline.\n")
        exit(1)
    end

    @printf("\n  Completed: %s (%.1fs)\n", label, elapsed)
    return elapsed
end

function main()
    println("=" ^ 70)
    println("  ANNUITY PUZZLE MODEL — FULL REPRODUCTION PIPELINE")
    println("=" ^ 70)
    @printf("  Project: %s\n", PROJECT_DIR)
    @printf("  Julia:   %s\n", string(VERSION))
    println()

    timings = Pair{String, Float64}[]
    t_total = time()

    # --- Stage 0: Tests ---
    if !skip_tests
        t = run_stage("Test Suite", TEST_RUNNER)
        push!(timings, "Tests" => t)
        if tests_only
            @printf("\n  Tests completed. Total: %.1fs\n", time() - t_total)
            return
        end
    end

    # --- Stage 0b: Build HRS sample (skipped if processed CSV already present) ---
    # Produces: data/processed/lockwood_hrs_sample.csv from RAND HRS Longitudinal File.
    # Set ANNUITY_FORCE_HRS_REBUILD=1 to force regeneration.
    hrs_csv = joinpath(PROJECT_DIR, "data", "processed", "lockwood_hrs_sample.csv")
    force_rebuild = get(ENV, "ANNUITY_FORCE_HRS_REBUILD", "0") == "1"
    if isfile(hrs_csv) && !force_rebuild
        @printf("\n  Skipping Stage 0b: %s already exists (set ANNUITY_FORCE_HRS_REBUILD=1 to force).\n", hrs_csv)
        push!(timings, "HRS sample (skipped)" => 0.0)
    else
        t = run_stage(
            "0b. Build HRS Population Sample",
            joinpath(PROJECT_DIR, "calibration", "build_hrs_sample.jl"))
        push!(timings, "HRS sample" => t)
    end

    # --- Stage 0c: Compute HRS lifetime annuity rate (q286 fat-file indicator) ---
    # Produces: data/processed/hrs_lifetime_ownership.csv. Requires the HRS
    # pension/wealth fat files at data/raw/HRS/HRS Fat Files/. Skipped
    # gracefully if raw fat files are absent.
    hrs_lifetime_csv = joinpath(PROJECT_DIR, "data", "processed", "hrs_lifetime_ownership.csv")
    if isfile(hrs_lifetime_csv) && !force_rebuild
        @printf("  Skipping Stage 0c: %s already exists.\n", hrs_lifetime_csv)
        push!(timings, "HRS lifetime (skipped)" => 0.0)
    else
        try
            t = run_stage(
                "0c. Compute HRS Lifetime Annuity Rate (q286 fat-file)",
                joinpath(PROJECT_DIR, "calibration", "compute_lifetime_ownership_rate.jl"))
            push!(timings, "HRS lifetime" => t)
        catch e
            @warn "Stage 0c failed (raw HRS fat files likely unavailable). Skipping; using checked-in CSV." exception=e
        end
    end

    # --- Stage 0d: ELSA pre/post 2015 freedoms regime comparison ---
    # Produces: data/processed/elsa_pre_post_freedoms.csv. Requires the ELSA
    # archive (UK Data Service deposit 5050) at data/raw/ELSA/ or via the
    # ANNUITY_ELSA_ARCHIVE env var. Skipped gracefully if archive is absent.
    elsa_csv = joinpath(PROJECT_DIR, "data", "processed", "elsa_pre_post_freedoms.csv")
    if isfile(elsa_csv) && !force_rebuild
        @printf("  Skipping Stage 0d: %s already exists.\n", elsa_csv)
        push!(timings, "ELSA pre/post (skipped)" => 0.0)
    else
        try
            t = run_stage(
                "0d. ELSA Pre/Post 2015 Freedoms Comparison",
                joinpath(PROJECT_DIR, "calibration", "elsa_pre_post_freedoms.jl"))
            push!(timings, "ELSA pre/post" => t)
        catch e
            @warn "Stage 0d failed (ELSA archive likely unavailable). Skipping; using checked-in CSV." exception=e
        end
    end

    # --- Stage 0e: ELSA pooled disposition (waves 8-11) ---
    # Produces: data/processed/elsa_disposition_pooled.csv. Same raw-data
    # requirements as Stage 0d.
    elsa_disp_csv = joinpath(PROJECT_DIR, "data", "processed", "elsa_disposition_pooled.csv")
    if isfile(elsa_disp_csv) && !force_rebuild
        @printf("  Skipping Stage 0e: %s already exists.\n", elsa_disp_csv)
        push!(timings, "ELSA disposition (skipped)" => 0.0)
    else
        try
            t = run_stage(
                "0e. ELSA Pooled Disposition (waves 8-11)",
                joinpath(PROJECT_DIR, "calibration", "elsa_disposition_pooled.jl"))
            push!(timings, "ELSA disposition" => t)
        catch e
            @warn "Stage 0e failed (ELSA archive likely unavailable). Skipping; using checked-in CSV." exception=e
        end
    end

    # --- Stage 1: Lockwood (2012) replication ---
    # Produces: lockwood_replication.tex (appendix)
    t = run_stage(
        "1. Lockwood (2012) Replication",
        joinpath(SCRIPTS_DIR, "run_lockwood_replication.jl"))
    push!(timings, "Lockwood" => t)

    # --- Stage 2: Sequential decomposition (Table 1) ---
    # Produces: retention_rates.tex, decomposition.csv
    t = run_stage(
        "2. Sequential Decomposition",
        joinpath(SCRIPTS_DIR, "run_decomposition.jl"))
    push!(timings, "Decomposition" => t)

    # --- Stage 3: Multi-gamma decomposition ---
    # Produces: multigamma_decomposition.tex/.csv
    t = run_stage(
        "3. Multi-Gamma Decomposition",
        joinpath(SCRIPTS_DIR, "run_multigamma_decomposition.jl"); parallel=true)
    push!(timings, "Multi-gamma" => t)

    # --- Stage 4: Pashchenko (2013) comparison ---
    # Produces: pashchenko_comparison.tex/.csv
    t = run_stage(
        "4. Pashchenko (2013) Comparison",
        joinpath(SCRIPTS_DIR, "run_pashchenko_comparison.jl"); parallel=true)
    push!(timings, "Pashchenko" => t)

    # --- Stage 5: Moment validation ---
    # Produces: moment_validation.tex/.csv
    t = run_stage(
        "5. Moment Validation",
        joinpath(SCRIPTS_DIR, "run_moment_validation.jl"))
    push!(timings, "Moments" => t)

    # --- Stage 6: CEV welfare analysis ---
    # Produces: welfare_cev_grid.tex/.csv, pairwise_interactions.tex/.csv
    t = run_stage(
        "6. CEV Welfare Analysis",
        joinpath(SCRIPTS_DIR, "run_welfare_analysis.jl"))
    push!(timings, "Welfare CEV" => t)

    # --- Stage 7: Welfare counterfactuals ---
    # Produces: welfare_counterfactuals.tex/.csv, cev_counterfactuals.tex/.csv
    t = run_stage(
        "7. Welfare Counterfactuals",
        joinpath(SCRIPTS_DIR, "run_welfare_counterfactuals.jl"); parallel=true)
    push!(timings, "Counterfactuals" => t)

    # --- Stage 8: DIA/QLAC analysis ---
    # Produces: dia_comparison.tex/.csv
    t = run_stage(
        "8. DIA/QLAC Deferred Annuity Comparison",
        joinpath(SCRIPTS_DIR, "run_dia_analysis.jl"))
    push!(timings, "DIA" => t)

    # --- Stage 9: Bequest recalibration ---
    # Produces: bequest_recalibration.tex/.csv
    t = run_stage(
        "9. Bequest Parameter Portability",
        joinpath(CALIB_DIR, "recalibrate_bequests.jl"))
    push!(timings, "Bequests" => t)

    # --- Stage 10: Exact Shapley decomposition (1024 subsets, 10 channels) ---
    # Produces: shapley_exact.tex/.csv
    t = run_stage(
        "10. Exact Shapley Decomposition (1024 subsets)",
        joinpath(SCRIPTS_DIR, "run_subset_enumeration.jl"); parallel=true)
    push!(timings, "Shapley" => t)

    # --- Stage 11: SS cut robustness ---
    # Produces: ss_cut_robustness.tex/.csv
    t = run_stage(
        "11. Social Security Cut Robustness",
        joinpath(SCRIPTS_DIR, "run_ss_robustness.jl"); parallel=true)
    push!(timings, "SS cuts" => t)

    # --- Stage 12: Robustness and sensitivity ---
    # Produces: robustness_gamma_inflation.tex, retention_rates.tex, robustness_full.csv
    t = run_stage(
        "12. Robustness and Sensitivity Analysis",
        joinpath(SCRIPTS_DIR, "run_robustness.jl"); parallel=true)
    push!(timings, "Robustness" => t)

    # --- Stage 13: Implied gamma (computationally intensive) ---
    # Produces: implied_gamma.tex/.csv
    t = run_stage(
        "13. Implied Risk Aversion (Monte Carlo bisection)",
        joinpath(SCRIPTS_DIR, "run_implied_gamma.jl"); parallel=true)
    push!(timings, "Implied gamma" => t)

    # --- Stage 13b: Behavioral channel psi sensitivity sweep ---
    # Produces: psi_sensitivity.csv. Solves the full 10-channel model at six
    # psi_purchase values bracketing the Blanchett-Finke and Chalmers-Reuter
    # behavioral evidence. Establishes the demand-side counterfactual range.
    t = run_stage(
        "13b. Behavioral psi-purchase Sensitivity Sweep",
        joinpath(SCRIPTS_DIR, "run_psi_sensitivity.jl"); parallel=true)
    push!(timings, "Psi sensitivity" => t)

    # --- Stage 13c: Monte Carlo parameter uncertainty (10-channel) ---
    # Produces: monte_carlo_ownership.csv, monte_carlo_summary.tex.
    # 1000 joint draws over (gamma fixed) hazard_poor, inflation, MWR,
    # pessimism, delta_c, psi_purchase. Yields 90% CI bands on the headline.
    t = run_stage(
        "13c. Monte Carlo Parameter Uncertainty",
        joinpath(SCRIPTS_DIR, "run_monte_carlo_uncertainty.jl"); parallel=true)
    push!(timings, "Monte Carlo uncertainty" => t)

    # --- Stage 13d: UK-anchored psi estimation (single-moment SMM) ---
    # Produces: results/psi_estimation.json, tables/csv/psi_estimation.csv.
    # Bisects psi to match UK 2015 pension-freedoms retention moment (mid-range
    # 17%, sensitivity over 13-25%). Single-moment SMM, just-identified.
    # Replaces the buried-estimation TK->psi mapping with an external natural-
    # experiment calibration. US ownership becomes an out-of-sample prediction.
    # Parallelized: the three retention targets are independent bisections
    # that can dispatch evaluations across workers.
    t = run_stage(
        "13d. UK-anchored psi Estimation (single-moment SMM)",
        joinpath(SCRIPTS_DIR, "estimate_psi.jl"); parallel=true)
    push!(timings, "Psi estimation" => t)

    # --- Stage 14: Figure generation (reads CSVs) ---
    # Produces: figures/pdf/fig1-fig5.pdf, figures/png/fig1-fig5.png (5 figures).
    # If a fig6 (Monte Carlo distribution) is needed in a future revision,
    # extend generate_figures.jl to read tables/csv/monte_carlo_ownership.csv
    # and emit fig6 alongside the others.
    t = run_stage(
        "14. Figure Generation",
        joinpath(SCRIPTS_DIR, "generate_figures.jl"))
    push!(timings, "Figures" => t)

    # --- Stage 14b: State-dependent utility sensitivity ---
    # Produces: state_utility_sensitivity.csv. Two full 9-channel solves under
    # the FLN and Reichling-Smetters mappings of Finkelstein-Luttmer (2013).
    t = run_stage(
        "14b. State-dependent Utility Sensitivity (FLN vs R-S)",
        joinpath(SCRIPTS_DIR, "run_state_utility_sensitivity.jl"); parallel=true)
    push!(timings, "State-util sensitivity" => t)

    # --- Stage 15: Export manuscript numbers (must run AFTER all CSVs exist) ---
    # Produces: paper/numbers.tex — single source of truth for every numeric
    # literal cited in main.tex, appendix.tex, and cover_letter.tex. All three
    # manuscripts \input this file; regenerating it here ensures manuscript
    # values never drift from the analysis CSVs.
    t = run_stage(
        "15. Export Manuscript Numbers (paper/numbers.tex)",
        joinpath(SCRIPTS_DIR, "export_manuscript_numbers.jl"))
    push!(timings, "Manuscript numbers" => t)

    # --- Stage 16: Post-run validation ---
    # Stage 0's pre-run tests bless whatever CSVs were sitting on disk before
    # this run. We need a final pass that asserts the FRESH CSVs and
    # numbers.tex are mutually consistent. If a generator produced a malformed
    # CSV, an out-of-range value, or a manuscript macro that drifted from the
    # CSV it claims to source, this stage fails the pipeline.
    t = run_stage(
        "16. Post-run Validation (numbers.tex vs fresh CSVs)",
        joinpath(TEST_DIR, "test_manuscript_numbers.jl"))
    push!(timings, "Post-run validation" => t)

    # --- Summary ---
    total = time() - t_total

    println("\n" * "=" ^ 70)
    println("  PIPELINE COMPLETE")
    println("=" ^ 70)
    println()
    @printf("  %-35s  %8s\n", "Stage", "Time")
    println("  " * "-" ^ 45)
    for (stage, t) in sort(timings, by=x->x[2], rev=true)
        @printf("  %-35s  %7.1fs\n", stage, t)
    end
    println("  " * "-" ^ 45)
    @printf("  %-35s  %7.1fs\n", "TOTAL", total)
    println()

    # Check outputs
    println("  Output files:")
    for dir in ["tables/tex", "tables/csv", "figures/pdf"]
        full = joinpath(PROJECT_DIR, dir)
        if isdir(full)
            files = readdir(full)
            for f in sort(files)
                println("    $dir/$f")
            end
        end
    end
    println()

    # Verify expected manuscript inputs exist
    expected_tex = [
        "bequest_recalibration.tex",
        "cev_counterfactuals.tex",
        "dia_comparison.tex",
        "extension_path.tex",
        "implied_gamma.tex",
        "moment_validation.tex",
        # multigamma_decomposition.tex is no longer required in the
        # manuscript (the prose now reports a brief diagnostic summary
        # instead of inputting the table). The Stage 3 generator still
        # writes it to tables/tex/ for diagnostic use, but missing or
        # stale versions do not block the package as submission-grade.
        "pairwise_interactions.tex",
        "pashchenko_comparison.tex",
        "retention_rates.tex",
        "robustness_gamma_inflation.tex",
        "shapley_exact.tex",
        "ss_cut_robustness.tex",
        "welfare_cev_grid.tex",
        "welfare_counterfactuals.tex",
    ]
    tex_dir = joinpath(PROJECT_DIR, "tables", "tex")
    missing_files = String[]
    for f in expected_tex
        if !isfile(joinpath(tex_dir, f))
            push!(missing_files, f)
        end
    end
    if !isempty(missing_files)
        # Fail closed: a pipeline that completed every stage but did not
        # produce every expected manuscript table is not submission-grade.
        error("Missing manuscript tables: " * join(missing_files, ", "))
    end

    # Reject any shipped table that still contains stale-artifact marker
    # phrases. These typically appear in tablenotes when a generator or
    # input has been corrected but the output hasn't been regenerated yet.
    # If any of these phrases appear, the pipeline must be rerun.
    stale_markers = ["pre-date", "next AWS rerun", "TBD"]
    stale_files = Tuple{String,String}[]
    for f in expected_tex
        path = joinpath(tex_dir, f)
        content = read(path, String)
        for marker in stale_markers
            if occursin(marker, content)
                push!(stale_files, (f, marker))
                break
            end
        end
    end
    if !isempty(stale_files)
        msg = "Stale-artifact marker(s) found in shipped tables:\n" *
              join(["  $f contains \"$marker\"" for (f, marker) in stale_files], "\n")
        error(msg)
    end

    @printf("  All %d expected manuscript tables verified (no stale markers).\n\n", length(expected_tex))
end

main()
```

---

## ORIGINAL FILE: paper/numbers.tex (auto-generated headline-number macros)

```latex
% !TEX root = main.tex
% ------------------------------------------------------------------
% AUTO-GENERATED by scripts/export_manuscript_numbers.jl
% Do not edit by hand. Regenerate after any analysis re-run.
% ------------------------------------------------------------------

\newcommand{\pGamma}{2.5}
\newcommand{\pBeta}{0.97}
\newcommand{\pRRate}{2\%}
\newcommand{\pRRateNum}{0.02}
\newcommand{\pInflation}{2\%}
\newcommand{\pInflationNum}{0.02}
\newcommand{\pCFloor}{\$6{,}180}
\newcommand{\pFixedCost}{\$1{,}000}
\newcommand{\pMinWealth}{\$5{,}000}
\newcommand{\pWMax}{\$3{,}000{,}000}
\newcommand{\pWMaxMillions}{\$3\text{ million}}
\newcommand{\pThetaDFJ}{56.96}
\newcommand{\pKappaDFJ}{\$272{,}628}
\newcommand{\pDeltaC}{0.02}
\newcommand{\pHealthUtilGood}{1.00}
\newcommand{\pHealthUtilFair}{0.90}
\newcommand{\pHealthUtilPoor}{0.75}
\newcommand{\pHazardGood}{0.50}
\newcommand{\pHazardFair}{1.0}
\newcommand{\pHazardPoor}{3.0}
\newcommand{\pPessimism}{0.981}
\newcommand{\pAgeStart}{65}
\newcommand{\pAgeEnd}{110}
\newcommand{\pT}{46}
\newcommand{\pNWealth}{80}
\newcommand{\pNAnnuity}{30}
\newcommand{\pNAlpha}{101}
\newcommand{\pNQuad}{9}
\newcommand{\pMwrBaseline}{0.87}
\newcommand{\pMwrLoad}{13\%}
\newcommand{\nHRSTotal}{5,303}
\newcommand{\nHRSEligible}{2846}
\newcommand{\nHRSMedianWealth}{\$8{,}000}
\newcommand{\nHRSAboveWmax}{23}
\newcommand{\pctHRSAboveWmax}{0.4\%}
\newcommand{\pctHRSObserved}{3.4\%}
\newcommand{\nHRSOwners}{178}
\newcommand{\nHRSLifetimeEligible}{5,396}
\newcommand{\nHRSLifetimeOwners}{109}
\newcommand{\pctHRSLifetime}{2.02\%}
\newcommand{\pctHRSIannPooled}{3.34\%}
\newcommand{\nHRSIannOwners}{180}
\newcommand{\pctHRSLifetimeCILow}{1.68\%}
\newcommand{\pctHRSLifetimeCIHigh}{2.43\%}
\newcommand{\pctHRSIannCILow}{2.89\%}
\newcommand{\pctHRSIannCIHigh}{3.85\%}
\newcommand{\nELSAWaveSixDC}{5313}
\newcommand{\nELSAWaveSixAnnuity}{4793}
\newcommand{\pctELSAWaveSixAnnuity}{90.2\%}
\newcommand{\nELSAPostPlanDC}{16765}
\newcommand{\nELSAPostPlanAnnuity}{587}
\newcommand{\pctELSAPostPlanAnnuity}{3.5\%}
\newcommand{\nELSAPostLumpSum}{869}
\newcommand{\nELSAPostAnnuity}{11}
\newcommand{\pctELSAPostAnnuity}{1.27\%}
\newcommand{\ELSADropLumpSum}{89}
\newcommand{\ELSADropPlan}{87}
\newcommand{\ELSADropRange}{87--89}
\newcommand{\ownFrictionless}{41.4\%}
\newcommand{\ownAddSS}{100.0\%}
\newcommand{\ownAddBequests}{100.0\%}
\newcommand{\ownAddMedRS}{93.3\%}
\newcommand{\ownAddMedical}{93.3\%}
\newcommand{\ownAddRS}{93.3\%}
\newcommand{\ownAddPessimism}{80.2\%}
\newcommand{\ownAddLoads}{44.3\%}
\newcommand{\ownSixChannel}{44.2\%}
\newcommand{\ownSevenChannel}{44.2\%}
\newcommand{\ownSevenChannelExt}{33.6\%}
\newcommand{\ownEightChannel}{33.6\%}
\newcommand{\ownEightChannelExt}{34.3\%}
\newcommand{\ownNineChannel}{34.3\%}
\newcommand{\ownNineChannelSDU}{79.3\%}
\newcommand{\ownTenChannel}{79.3\%}
\newcommand{\ownTenChannelFull}{24.5\%}
\newcommand{\ownElevenChannel}{24.5\%}
\newcommand{\retentionSS}{241.7\%}
\newcommand{\ownPrePessimism}{93.3\%}
\newcommand{\deltaPessimism}{-13.1}
\newcommand{\retentionPessimism}{86.0\%}
\newcommand{\retentionLoads}{55.2\%}
\newcommand{\retentionInflation}{99.8\%}
\newcommand{\deltaMedRS}{-6.7}
\newcommand{\magDeltaMedRS}{6.7}
\newcommand{\retentionMedRS}{93.3\%}
\newcommand{\deltaMedical}{-6.7}
\newcommand{\magDeltaMedical}{6.7}
\newcommand{\retentionMedical}{93.3\%}
\newcommand{\deltaRS}{-6.7}
\newcommand{\magDeltaRS}{6.7}
\newcommand{\retentionRS}{93.3\%}
\newcommand{\deltaAgeNeeds}{-10.6}
\newcommand{\deltaStateUtil}{0.7}
\newcommand{\shapSS}{-23.9}
\newcommand{\shapBequests}{1.0}
\newcommand{\shapMedRS}{16.2}
\newcommand{\shapMedical}{16.2}
\newcommand{\shapRS}{16.2}
\newcommand{\shapPessimism}{6.3}
\newcommand{\shapAgeNeeds}{7.0}
\newcommand{\shapStateUtil}{1.2}
\newcommand{\shapLoads}{23.2}
\newcommand{\shapInflation}{-1.7}
\newcommand{\shapSDU}{-40.6}
\newcommand{\shapNarrowFraming}{28.1}
\newcommand{\shapShareSS}{-141\%}
\newcommand{\shapShareBequests}{6\%}
\newcommand{\shapShareMedRS}{96\%}
\newcommand{\shapShareMedical}{96\%}
\newcommand{\shapShareRS}{96\%}
\newcommand{\shapSharePessimism}{38\%}
\newcommand{\shapShareAgeNeeds}{42\%}
\newcommand{\shapShareStateUtil}{7\%}
\newcommand{\shapShareLoads}{137\%}
\newcommand{\shapShareInflation}{-10\%}
\newcommand{\shapShareSDU}{-240\%}
\newcommand{\shapShareNarrowFraming}{166\%}
\newcommand{\shapRSPessAge}{29.6}
\newcommand{\shapShareRSPessAge}{175\%}
\newcommand{\cevGoodHundredKNoBq}{0.6\%}
\newcommand{\cevGoodHundredKDFJ}{0.4\%}
\newcommand{\cevGoodHundredKStrong}{0.1\%}
\newcommand{\cevGoodTwoHundredKNoBq}{0.2\%}
\newcommand{\cevGoodTwoHundredKDFJ}{0.1\%}
\newcommand{\cevGoodTwoHundredKStrong}{0.0\%}
\newcommand{\cevGoodOneMillNoBq}{0.0\%}
\newcommand{\cevGoodOneMillDFJ}{0.0\%}
\newcommand{\cevGoodOneMillStrong}{0.0\%}
\newcommand{\popMeanCevNoBq}{0.1\%}
\newcommand{\popMeanCevDFJ}{0.0\%}
\newcommand{\popFracPosNoBq}{16.8\%}
\newcommand{\popFracPosDFJ}{12.6\%}
\newcommand{\popFracAboveOneNoBq}{0.4\%}
\newcommand{\popFracAboveOneDFJ}{0.0\%}
\newcommand{\ownGroupPricing}{34.1\%}
\newcommand{\ownPublicOption}{49.2\%}
\newcommand{\ownActuariallyFair}{56.1\%}
\newcommand{\ownRealTIPS}{1.0\%}
\newcommand{\ownRealNomEquiv}{16.4\%}
\newcommand{\ownFairReal}{52.5\%}
\newcommand{\ownCorrectPessimism}{45.7\%}
\newcommand{\ownGroupPlusCorrect}{52.5\%}
\newcommand{\ownBestFeasible}{48.7\%}
\newcommand{\cevGoodHundredKBaseline}{0.4\%}
\newcommand{\cevGoodHundredKGroupPrice}{0.9\%}
\newcommand{\cevGoodHundredKRealAnn}{0.0\%}
\newcommand{\cevGoodHundredKBestFeas}{5.3\%}
\newcommand{\cevGoodTwoHundredKBaseline}{0.1\%}
\newcommand{\cevGoodTwoHundredKGroupPrice}{0.4\%}
\newcommand{\cevGoodTwoHundredKRealAnn}{0.0\%}
\newcommand{\cevGoodTwoHundredKBestFeas}{12.9\%}
\newcommand{\cevGoodFiveHundredKBaseline}{0.0\%}
\newcommand{\cevGoodFiveHundredKGroupPrice}{0.0\%}
\newcommand{\cevGoodFiveHundredKRealAnn}{0.0\%}
\newcommand{\cevGoodFiveHundredKBestFeas}{26.8\%}
\newcommand{\cevGoodOneMillBaseline}{0.0\%}
\newcommand{\cevGoodOneMillGroupPrice}{0.0\%}
\newcommand{\cevGoodOneMillRealAnn}{0.0\%}
\newcommand{\cevGoodOneMillBestFeas}{37.8\%}
\newcommand{\ownGammaTwo}{11.2\%}
\newcommand{\ownGammaTwoPointThree}{22.0\%}
\newcommand{\ownGammaTwoPointFour}{23.5\%}
\newcommand{\ownGammaTwoPointFive}{24.5\%}
\newcommand{\ownGammaThree}{25.9\%}
\newcommand{\ownInflationOne}{20.4\%}
\newcommand{\ownInflationTwo}{24.5\%}
\newcommand{\ownInflationThree}{29.0\%}
\newcommand{\ownPsiObjective}{45.7\%}
\newcommand{\ownPsiNinetySeven}{15.8\%}
\newcommand{\ownPsiBaseline}{24.5\%}
\newcommand{\ownPsiNinetyNine}{34.1\%}
\newcommand{\ownMWREightyTwo}{10.4\%}
\newcommand{\ownMWREightyFive}{18.8\%}
\newcommand{\ownMWRNinety}{34.2\%}
\newcommand{\ownMWRNinetyFive}{49.2\%}
\newcommand{\ownBequestNone}{27.9\%}
\newcommand{\ownHazardRS}{21.3\%}
\newcommand{\ownHazardHRS}{25.6\%}
\newcommand{\ownHazardConservative}{34.7\%}
\newcommand{\ownHazardAgeBand}{24.6\%}
\newcommand{\ownSSCutZero}{24.5\%}
\newcommand{\ownSSCutTen}{43.4\%}
\newcommand{\ownSSCutFifteen}{51.6\%}
\newcommand{\ownSSCutTwentyThree}{63.3\%}
\newcommand{\ownSSCutThirty}{64.4\%}
\newcommand{\ownSSCutForty}{61.1\%}
\newcommand{\ownSSCutFifty}{55.4\%}
\newcommand{\ownSSCutHundred}{15.7\%}
\newcommand{\pHealthUtilFairFLN}{0.90}
\newcommand{\pHealthUtilPoorFLN}{0.75}
\newcommand{\ownNineChannelFLN}{34.3\%}
\newcommand{\pHealthUtilFairRS}{0.95}
\newcommand{\pHealthUtilPoorRS}{0.85}
\newcommand{\ownNineChannelRS}{33.8\%}
\newcommand{\deltaNineChannelRSmFLN}{-0.5}
\newcommand{\ownPsiZero}{79.3\%}
\newcommand{\pPsiZero}{0.0000}
\newcommand{\defaultGapPsiZero}{0.0}
\newcommand{\ownPsiUKLow}{31.8\%}
\newcommand{\pPsiUKLow}{0.0142}
\newcommand{\defaultGapPsiUKLow}{47.5}
\newcommand{\ownPsiUKMid}{24.5\%}
\newcommand{\pPsiUKMid}{0.0163}
\newcommand{\defaultGapPsiUKMid}{54.8}
\newcommand{\ownPsiUKHigh}{18.5\%}
\newcommand{\pPsiUKHigh}{0.0194}
\newcommand{\defaultGapPsiUKHigh}{60.8}
\newcommand{\ownPsiUKELSALow}{13.4\%}
\newcommand{\pPsiUKELSALow}{0.0220}
\newcommand{\defaultGapPsiUKELSALow}{65.9}
\newcommand{\ownPsiUKELSAHigh}{10.5\%}
\newcommand{\pPsiUKELSAHigh}{0.0240}
\newcommand{\defaultGapPsiUKELSAHigh}{68.7}
\newcommand{\ownPsiUKBLow}{3.5\%}
\newcommand{\pPsiUKBLow}{0.0281}
\newcommand{\defaultGapPsiUKBLow}{75.7}
\newcommand{\ownPsiUKELSATotal}{2.3\%}
\newcommand{\pPsiUKELSATotal}{0.0335}
\newcommand{\defaultGapPsiUKELSATotal}{77.0}
\newcommand{\ownPsiAboveRange}{1.3\%}
\newcommand{\pPsiAboveRange}{0.0400}
\newcommand{\defaultGapPsiAboveRange}{78.0}
\newcommand{\ownPsiCorner}{0.0\%}
\newcommand{\pPsiCorner}{0.0750}
\newcommand{\defaultGapPsiCorner}{79.3}
\newcommand{\pPsiPurchase}{0.0163}
\newcommand{\pLambdaW}{0.625}
\newcommand{\pPsiPurchaseCRef}{18{,}000}
\newcommand{\ownBracketHigh}{24.5\%}
\newcommand{\ownBracketLow}{2.3\%}
\newcommand{\pPsiBracketLow}{0.0163}
\newcommand{\pPsiBracketHigh}{0.0335}
\newcommand{\ownBracketWideHigh}{31.8\%}
\newcommand{\ownBracketWideLow}{1.3\%}
\newcommand{\mcMedianOwnership}{16.1\%}
\newcommand{\mcMeanOwnership}{21.4\%}
\newcommand{\mcLowCIOwnership}{0.5\%}
\newcommand{\mcHighCIOwnership}{57.0\%}
\newcommand{\mcLowIQROwnership}{0.8\%}
\newcommand{\mcHighIQROwnership}{37.8\%}
\newcommand{\mcMinOwnership}{0.1\%}
\newcommand{\mcMaxOwnership}{66.6\%}
\newcommand{\nMCDraws}{1,000}
\newcommand{\pMwrLoadNum}{13}
\newcommand{\pctHRSAboveWmaxNum}{0.4}
\newcommand{\pctHRSObservedNum}{3.4}
\newcommand{\pctHRSLifetimeNum}{2.02}
\newcommand{\pctHRSIannPooledNum}{3.34}
\newcommand{\pctHRSLifetimeCILowNum}{1.68}
\newcommand{\pctHRSLifetimeCIHighNum}{2.43}
\newcommand{\pctHRSIannCILowNum}{2.89}
\newcommand{\pctHRSIannCIHighNum}{3.85}
\newcommand{\pctELSAWaveSixAnnuityNum}{90.2}
\newcommand{\pctELSAPostPlanAnnuityNum}{3.5}
\newcommand{\pctELSAPostAnnuityNum}{1.27}
\newcommand{\ownFrictionlessNum}{41.4}
\newcommand{\ownAddSSNum}{100.0}
\newcommand{\ownAddBequestsNum}{100.0}
\newcommand{\ownAddMedRSNum}{93.3}
\newcommand{\ownAddMedicalNum}{93.3}
\newcommand{\ownAddRSNum}{93.3}
\newcommand{\ownAddPessimismNum}{80.2}
\newcommand{\ownAddLoadsNum}{44.3}
\newcommand{\ownSixChannelNum}{44.2}
\newcommand{\ownSevenChannelNum}{44.2}
\newcommand{\ownSevenChannelExtNum}{33.6}
\newcommand{\ownEightChannelNum}{33.6}
\newcommand{\ownEightChannelExtNum}{34.3}
\newcommand{\ownNineChannelNum}{34.3}
\newcommand{\ownNineChannelSDUNum}{79.3}
\newcommand{\ownTenChannelNum}{79.3}
\newcommand{\ownTenChannelFullNum}{24.5}
\newcommand{\ownElevenChannelNum}{24.5}
\newcommand{\retentionSSNum}{241.7}
\newcommand{\ownPrePessimismNum}{93.3}
\newcommand{\retentionPessimismNum}{86.0}
\newcommand{\retentionLoadsNum}{55.2}
\newcommand{\retentionInflationNum}{99.8}
\newcommand{\retentionMedRSNum}{93.3}
\newcommand{\retentionMedicalNum}{93.3}
\newcommand{\retentionRSNum}{93.3}
\newcommand{\shapShareSSNum}{-141}
\newcommand{\shapShareBequestsNum}{6}
\newcommand{\shapShareMedRSNum}{96}
\newcommand{\shapShareMedicalNum}{96}
\newcommand{\shapShareRSNum}{96}
\newcommand{\shapSharePessimismNum}{38}
\newcommand{\shapShareAgeNeedsNum}{42}
\newcommand{\shapShareStateUtilNum}{7}
\newcommand{\shapShareLoadsNum}{137}
\newcommand{\shapShareInflationNum}{-10}
\newcommand{\shapShareSDUNum}{-240}
\newcommand{\shapShareNarrowFramingNum}{166}
\newcommand{\shapShareRSPessAgeNum}{175}
\newcommand{\cevGoodHundredKNoBqNum}{0.6}
\newcommand{\cevGoodHundredKDFJNum}{0.4}
\newcommand{\cevGoodHundredKStrongNum}{0.1}
\newcommand{\cevGoodTwoHundredKNoBqNum}{0.2}
\newcommand{\cevGoodTwoHundredKDFJNum}{0.1}
\newcommand{\cevGoodTwoHundredKStrongNum}{0.0}
\newcommand{\cevGoodOneMillNoBqNum}{0.0}
\newcommand{\cevGoodOneMillDFJNum}{0.0}
\newcommand{\cevGoodOneMillStrongNum}{0.0}
\newcommand{\popMeanCevNoBqNum}{0.1}
\newcommand{\popMeanCevDFJNum}{0.0}
\newcommand{\popFracPosNoBqNum}{16.8}
\newcommand{\popFracPosDFJNum}{12.6}
\newcommand{\popFracAboveOneNoBqNum}{0.4}
\newcommand{\popFracAboveOneDFJNum}{0.0}
\newcommand{\ownGroupPricingNum}{34.1}
\newcommand{\ownPublicOptionNum}{49.2}
\newcommand{\ownActuariallyFairNum}{56.1}
\newcommand{\ownRealTIPSNum}{1.0}
\newcommand{\ownRealNomEquivNum}{16.4}
\newcommand{\ownFairRealNum}{52.5}
\newcommand{\ownCorrectPessimismNum}{45.7}
\newcommand{\ownGroupPlusCorrectNum}{52.5}
\newcommand{\ownBestFeasibleNum}{48.7}
\newcommand{\cevGoodHundredKBaselineNum}{0.4}
\newcommand{\cevGoodHundredKGroupPriceNum}{0.9}
\newcommand{\cevGoodHundredKRealAnnNum}{0.0}
\newcommand{\cevGoodHundredKBestFeasNum}{5.3}
\newcommand{\cevGoodTwoHundredKBaselineNum}{0.1}
\newcommand{\cevGoodTwoHundredKGroupPriceNum}{0.4}
\newcommand{\cevGoodTwoHundredKRealAnnNum}{0.0}
\newcommand{\cevGoodTwoHundredKBestFeasNum}{12.9}
\newcommand{\cevGoodFiveHundredKBaselineNum}{0.0}
\newcommand{\cevGoodFiveHundredKGroupPriceNum}{0.0}
\newcommand{\cevGoodFiveHundredKRealAnnNum}{0.0}
\newcommand{\cevGoodFiveHundredKBestFeasNum}{26.8}
\newcommand{\cevGoodOneMillBaselineNum}{0.0}
\newcommand{\cevGoodOneMillGroupPriceNum}{0.0}
\newcommand{\cevGoodOneMillRealAnnNum}{0.0}
\newcommand{\cevGoodOneMillBestFeasNum}{37.8}
\newcommand{\ownGammaTwoNum}{11.2}
\newcommand{\ownGammaTwoPointThreeNum}{22.0}
\newcommand{\ownGammaTwoPointFourNum}{23.5}
\newcommand{\ownGammaTwoPointFiveNum}{24.5}
\newcommand{\ownGammaThreeNum}{25.9}
\newcommand{\ownInflationOneNum}{20.4}
\newcommand{\ownInflationTwoNum}{24.5}
\newcommand{\ownInflationThreeNum}{29.0}
\newcommand{\ownPsiObjectiveNum}{45.7}
\newcommand{\ownPsiNinetySevenNum}{15.8}
\newcommand{\ownPsiBaselineNum}{24.5}
\newcommand{\ownPsiNinetyNineNum}{34.1}
\newcommand{\ownMWREightyTwoNum}{10.4}
\newcommand{\ownMWREightyFiveNum}{18.8}
\newcommand{\ownMWRNinetyNum}{34.2}
\newcommand{\ownMWRNinetyFiveNum}{49.2}
\newcommand{\ownBequestNoneNum}{27.9}
\newcommand{\ownHazardRSNum}{21.3}
\newcommand{\ownHazardHRSNum}{25.6}
\newcommand{\ownHazardConservativeNum}{34.7}
\newcommand{\ownHazardAgeBandNum}{24.6}
\newcommand{\ownSSCutZeroNum}{24.5}
\newcommand{\ownSSCutTenNum}{43.4}
\newcommand{\ownSSCutFifteenNum}{51.6}
\newcommand{\ownSSCutTwentyThreeNum}{63.3}
\newcommand{\ownSSCutThirtyNum}{64.4}
\newcommand{\ownSSCutFortyNum}{61.1}
\newcommand{\ownSSCutFiftyNum}{55.4}
\newcommand{\ownSSCutHundredNum}{15.7}
\newcommand{\ownNineChannelFLNNum}{34.3}
\newcommand{\ownNineChannelRSNum}{33.8}
\newcommand{\ownPsiZeroNum}{79.3}
\newcommand{\ownPsiUKLowNum}{31.8}
\newcommand{\ownPsiUKMidNum}{24.5}
\newcommand{\ownPsiUKHighNum}{18.5}
\newcommand{\ownPsiUKELSALowNum}{13.4}
\newcommand{\ownPsiUKELSAHighNum}{10.5}
\newcommand{\ownPsiUKBLowNum}{3.5}
\newcommand{\ownPsiUKELSATotalNum}{2.3}
\newcommand{\ownPsiAboveRangeNum}{1.3}
\newcommand{\ownPsiCornerNum}{0.0}
\newcommand{\ownBracketHighNum}{24.5}
\newcommand{\ownBracketLowNum}{2.3}
\newcommand{\ownBracketWideHighNum}{31.8}
\newcommand{\ownBracketWideLowNum}{1.3}
\newcommand{\mcMedianOwnershipNum}{16.1}
\newcommand{\mcMeanOwnershipNum}{21.4}
\newcommand{\mcLowCIOwnershipNum}{0.5}
\newcommand{\mcHighCIOwnershipNum}{57.0}
\newcommand{\mcLowIQROwnershipNum}{0.8}
\newcommand{\mcHighIQROwnershipNum}{37.8}
\newcommand{\mcMinOwnershipNum}{0.1}
\newcommand{\mcMaxOwnershipNum}{66.6}
```
