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

    # --- Stage 9b: UK-anchored psi estimation (single-moment SMM) ---
    # Produces: results/psi_estimation.json, tables/csv/psi_estimation.csv.
    # Bisects psi to match UK 2015 pension-freedoms retention moment (mid-range
    # 17%, sensitivity over 13-25%). Single-moment SMM, just-identified.
    #
    # SEQUENCING NOTE: This stage is intentionally placed BEFORE the Shapley
    # subset enumeration (Stage 10), the SS cut robustness (Stage 11), and the
    # gamma/inflation robustness sweep (Stage 12), so the SMM-derived psi is
    # available on disk when downstream stages run. Currently those downstream
    # stages still read PSI_PURCHASE from scripts/config.jl (the placeholder
    # value); a follow-up refactor should have them read the SMM result from
    # tables/csv/psi_estimation.csv. Until that refactor lands, the SMM
    # estimate is reported separately and the downstream-stage headline
    # reflects the placeholder; the UK-anchored ownership BRACKET (Stage 13b
    # sensitivity sweep) is the empirical headline regardless of the
    # placeholder choice.
    t = run_stage(
        "9b. UK-anchored psi Estimation (single-moment SMM)",
        joinpath(SCRIPTS_DIR, "estimate_psi.jl"); parallel=true)
    push!(timings, "Psi estimation" => t)

    # --- Stage 10: Exact Shapley decomposition (2048 subsets, 11 channels) ---
    # Produces: shapley_exact.tex/.csv
    # NOTE: uses PSI_PURCHASE from scripts/config.jl (placeholder); see
    # Stage 9b sequencing note above.
    t = run_stage(
        "10. Exact Shapley Decomposition (2048 subsets)",
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

    # (Stage 13d / UK-anchored psi estimation has been moved to Stage 9b
    #  so its output is available before the subset enumeration runs.)

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

    # --- Stage 14c: Force A (lambda_W) sensitivity ---
    # Produces: lambda_w_sensitivity.csv. Five full 11-channel solves at
    # lambda_w in {0.625, 0.70, 0.85, 0.95, 1.00}, bracketing the SDU
    # calibration uncertainty (raw Blanchett-Finke 0.625 vs production 0.85
    # vs SDU-off 1.00).
    t = run_stage(
        "14c. Force A (lambda_W) Sensitivity",
        joinpath(SCRIPTS_DIR, "run_lambda_w_sensitivity.jl"); parallel=true)
    push!(timings, "Lambda_W sensitivity" => t)

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

    # --- Stage 17: Pipeline validation gates ---
    # Three gates implementing the forensic-review recommendation to harden
    # against "stale artifact drift":
    #   (1) Manifest gate: every \input{tables/tex/X.tex} in the manuscript
    #       must appear in expected_tex.
    #   (2) Freshness gate: every consumed .tex must be at least as new as
    #       paper/numbers.tex (catches stale tables that survived a partial
    #       rerun).
    #   (3) Hardcode-stale-numbers gate: greps the manuscript and code surface
    #       for known stale literals (old observed-rate placeholder, stale
    #       MWR labels, old title strings, arithmetic errors, etc.). Lines
    #       can opt out of the scan with a `# ALLOWLIST: <reason>` comment.
    t = run_stage(
        "17. Pipeline Validation Gates",
        joinpath(SCRIPTS_DIR, "validate_pipeline.jl"))
    push!(timings, "Pipeline validation" => t)

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
        "monte_carlo_summary.tex",  # Stage 13c output; appendix \input
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
