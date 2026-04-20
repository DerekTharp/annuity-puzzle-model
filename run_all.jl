# Master pipeline: reproduce all results from raw data to final tables/figures.
#
# Usage:
#   julia --project=. run_all.jl              # full pipeline (tests + all analyses)
#   julia --project=. run_all.jl --skip-tests # skip test suite, run analyses only
#   julia --project=. run_all.jl --tests-only # run tests only
#
# Expected runtime: ~4-6 hours (15 stages, ~550 model solves including Shapley).
# For faster development runs, use --skip-tests and comment out Stage 12.
#
# Output:
#   tables/tex/*.tex   — LaTeX tables for paper (13 files)
#   tables/csv/*.csv   — machine-readable results
#   figures/pdf/*.pdf   — publication-quality figures
#   figures/png/*.png   — quick-inspection rasters
#   results/*/         — intermediate solution data

using Printf

const PROJECT_DIR = @__DIR__
const SCRIPTS_DIR = joinpath(PROJECT_DIR, "scripts")
const CALIB_DIR = joinpath(PROJECT_DIR, "calibration")
const TEST_RUNNER = joinpath(PROJECT_DIR, "test", "runtests.jl")

skip_tests = "--skip-tests" in ARGS
tests_only = "--tests-only" in ARGS

const N_WORKERS = min(div(Sys.CPU_THREADS, 2), 8)  # half of cores, cap at 8

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

    # --- Stage 10: Exact Shapley decomposition (512 subsets) ---
    # Produces: shapley_exact.tex/.csv
    t = run_stage(
        "10. Exact Shapley Decomposition (512 subsets)",
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

    # --- Stage 14: Figure generation (must run last — reads CSVs) ---
    # Produces: figures/pdf/fig1-fig6.pdf, figures/png/fig1-fig6.png (6 figures)
    t = run_stage(
        "14. Figure Generation",
        joinpath(SCRIPTS_DIR, "generate_figures.jl"))
    push!(timings, "Figures" => t)

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
