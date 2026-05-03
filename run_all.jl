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
    # Produces: data/processed/lockwood_hrs_sample.csv
    hrs_csv = joinpath(PROJECT_DIR, "data", "processed", "lockwood_hrs_sample.csv")
    if isfile(hrs_csv)
        @printf("\n  Skipping Stage 0b: %s already exists.\n", hrs_csv)
        push!(timings, "HRS sample (skipped)" => 0.0)
    else
        t = run_stage(
            "0b. Build HRS Population Sample",
            joinpath(PROJECT_DIR, "calibration", "build_hrs_sample.jl"))
        push!(timings, "HRS sample" => t)
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
    # Produces: figures/pdf/fig1-fig6.pdf, figures/png/fig1-fig6.png (6 figures)
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
        "multigamma_decomposition.tex",
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
    if isempty(missing_files)
        @printf("  All %d expected manuscript tables verified.\n\n", length(expected_tex))
    else
        println("  WARNING: Missing manuscript tables:")
        for f in missing_files
            println("    $f")
        end
        println()
    end
end

main()
