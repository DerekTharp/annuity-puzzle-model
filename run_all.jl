# Master pipeline: reproduce all results from raw data to final tables/figures.
#
# Usage:
#   julia --project=. run_all.jl              # full pipeline (tests + all analyses)
#   julia --project=. run_all.jl --skip-tests # skip test suite, run analyses only
#   julia --project=. run_all.jl --tests-only # run tests only
#
# Expected runtime on AWS c7a.48xlarge (192 vCPU): ~7 hours.
# Single-thread:  ~50 hours (2048 Shapley + 1000 MC + everything else).
# Expects all subset/Shapley/MC stages parallelized.
# For faster development runs, use --skip-tests and comment out Stage 12.
#
# Output:
#   tables/tex/*.tex   — LaTeX tables for paper (manifest in expected_tex below)
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

    # --- Stages 0d-0f: remaining raw-gated HRS rebuilds ---
    # Each is skipped when its committed output exists (or when raw HRS data
    # are absent); ANNUITY_FORCE_HRS_REBUILD=1 forces regeneration. These
    # complete the documented rebuild path for every processed input,
    # including the person-level validation extract that is not redistributed.
    for (label, script, outfile) in [
        ("0d. Build HRS validation sample (person-level; not redistributed)",
         joinpath(PROJECT_DIR, "calibration", "build_validation_sample.jl"),
         joinpath(PROJECT_DIR, "data", "processed", "hrs_validation_sample.csv")),
        ("0e. q286 lifetime ownership by wealth band",
         joinpath(PROJECT_DIR, "calibration", "q286_by_wealth_band.jl"),
         joinpath(PROJECT_DIR, "data", "processed", "hrs_lifetime_ownership_by_band.csv")),
        ("0f. Group-annuity access by wealth band (pension linkage)",
         joinpath(PROJECT_DIR, "calibration", "build_group_access.jl"),
         joinpath(PROJECT_DIR, "data", "processed", "group_access_by_band.csv")),
    ]
        if isfile(outfile) && !force_rebuild
            @printf("  Skipping %s: output already exists.\n", label[1:2])
            push!(timings, label[1:2] * " (skipped)" => 0.0)
        else
            try
                t = run_stage(label, script)
                push!(timings, label[1:2] => t)
            catch e
                @warn "Stage failed (raw HRS data likely unavailable). Skipping; using checked-in output where applicable." label exception=e
            end
        end
    end

    # --- Stage 1: Lockwood (2012) replication ---
    # Console-only WTP replication table (no file output). The appendix prose
    # is hand-maintained; the numbers are gated by test/test_lockwood.jl.
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
        joinpath(SCRIPTS_DIR, "run_moment_validation.jl");
        parallel=true)
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

    # The behavioral parameters lambda_w (SDU) and psi_purchase (PED) are set
    # directly in scripts/config.jl as literature-anchored magnitudes
    # (Blanchett-Finke for lambda_w; exploratory magnitude for psi_purchase),
    # not moment-matched. Sensitivity ranges are reported in the manuscript
    # across plausible spans.

    # --- Stage 10: Exact Shapley decomposition (2048 subsets, 11 channels) ---
    # Produces: shapley_exact.tex/.csv
    t = run_stage(
        "10. Exact Shapley Decomposition (2048 subsets)",
        joinpath(SCRIPTS_DIR, "run_subset_enumeration.jl"); parallel=true)
    push!(timings, "Shapley" => t)

    # --- Stage 10b: Gamma-stability of the 9-channel Shapley ranking ---
    # Produces: shapley_gamma_stability.csv, shapley_gamma_stability_summary.csv
    # (the signature exhibit: ranking robust across gamma and across the
    #  ownership vs mean-alpha value statistic).
    t = run_stage(
        "10b. Shapley Ranking Gamma-Stability (512 subsets x 5 gamma)",
        joinpath(SCRIPTS_DIR, "run_shapley_gamma_stability.jl"); parallel=true)
    push!(timings, "Shapley gamma-stability" => t)

    # --- Stage 10c: Nine-channel Shapley at the focal psi=0.981 ---
    # Produces: shapley_psi981.csv/.tex (ranking robustness to survival beliefs)
    t = run_stage(
        "10c. Nine-Channel Shapley at Focal psi=0.981",
        joinpath(SCRIPTS_DIR, "run_psi981_shapley.jl"); parallel=true)
    push!(timings, "Shapley psi=0.981" => t)

    # --- Stage 10d: Loads-split Shapley (11 players, 2048 subsets) ---
    # Produces: shapley_loads_split.csv/.tex (unbundles MWR wedge, fixed
    # cost, and minimum purchase as separate players)
    t = run_stage(
        "10d. Loads-Split Shapley (2048 subsets)",
        joinpath(SCRIPTS_DIR, "run_loads_split_shapley.jl"); parallel=true)
    push!(timings, "Loads-split Shapley" => t)

    # --- Stage 10e: Sex-blended mortality Shapley (512 subsets) ---
    # Requires data/processed/blended_lifetable.csv (committed aggregate;
    # rebuilt from ssa2003_sex_qx.csv by calibration/build_blended_lifetable.jl).
    run_stage(
        "10e-prep. Build sex-blended life table",
        joinpath(CALIB_DIR, "build_blended_lifetable.jl"))
    t = run_stage(
        "10e. Sex-Blended Mortality Shapley (512 subsets)",
        joinpath(SCRIPTS_DIR, "run_blended_mortality_shapley.jl"); parallel=true)
    push!(timings, "Blended-mortality Shapley" => t)

    # --- Stage 11: SS cut robustness ---
    # Produces: ss_cut_robustness.tex/.csv
    t = run_stage(
        "11. Social Security Cut Robustness",
        joinpath(SCRIPTS_DIR, "run_ss_robustness.jl"); parallel=true)
    push!(timings, "SS cuts" => t)

    # --- Stage 11b: SS cut response by wealth (DB-cushion exhibit) ---
    # Produces: ss_cut_by_wealth.csv
    t = run_stage(
        "11b. SS Cut Response by Wealth Quartile (DB cushion)",
        joinpath(SCRIPTS_DIR, "run_ss_cut_by_wealth.jl"); parallel=true)
    push!(timings, "SS cut by wealth" => t)

    # --- Stage 11c: Model-implied gradients + empirical validation ---
    # Produces: model_gradients.csv (model side; reads subset_enumeration.csv
    # for channel on/off deltas, so runs after Stage 10) and
    # empirical_gradients_{cells,logit}.csv (HRS data side).
    t = run_stage(
        "11c. Model-Implied Ownership Gradients",
        joinpath(SCRIPTS_DIR, "run_model_gradients.jl"); parallel=true)
    push!(timings, "Model gradients" => t)
    t = run_stage(
        "11d. Empirical Gradient Validation (HRS)",
        joinpath(SCRIPTS_DIR, "run_empirical_validation.jl"))
    push!(timings, "Empirical gradients" => t)

    # --- Stage 11e: Partition robustness (Med/R-S unbundled; SS/DB split) ---
    # Produces: shapley_partition_{medrs,ssdb}.csv, partition_robustness.tex
    t = run_stage(
        "11e. Partition Robustness (Shapley under alternative partitions)",
        joinpath(SCRIPTS_DIR, "run_partition_robustness.jl"); parallel=true)
    push!(timings, "Partition robustness" => t)

    # --- Stage 11f: Extensive-margin gate (F* rational-exclusion finding) ---
    # Produces: extensive_margin_gate.csv, fstar_distribution.csv,
    # wealth_gradient_modeldata.csv
    t = run_stage(
        "11f. Extensive-Margin Gate (indifference fixed cost F*)",
        joinpath(SCRIPTS_DIR, "run_extensive_margin_gate.jl"); parallel=true)
    push!(timings, "Extensive-margin gate" => t)

    # --- Stage 11g: Gate robustness (SS-cut concentration invariance) ---
    # Produces: gate_robustness_killer.csv, gate_robustness.tex
    t = run_stage(
        "11g. Gate Robustness (SS-cut response invariance to the margin)",
        joinpath(SCRIPTS_DIR, "run_gate_robustness.jl"); parallel=true)
    push!(timings, "Gate robustness" => t)

    # --- Stage 11h: Band value-destruction diagnostic (which channel drives the
    #     bottom-band F*=0; complements the extensive-margin gate) ---
    # Produces: band_value_destruction_diagnostic.csv, band_value_destruction.tex
    t = run_stage(
        "11h. Band Value-Destruction Diagnostic (leave-one-channel-out F*)",
        joinpath(SCRIPTS_DIR, "run_band3_diagnostic.jl"); parallel=true)
    push!(timings, "Band value-destruction" => t)
    run_stage(
        "11h. Emit band value-destruction table",
        joinpath(SCRIPTS_DIR, "emit_band_value_destruction_table.jl"))

    # --- Stage 11i: Model-vs-data wealth-band table (uses Stage 11f model data
    #     and the committed HRS by-band ownership) ---
    # Produces: model_vs_data_band.tex
    run_stage(
        "11i. Emit model-vs-data wealth-band table",
        joinpath(SCRIPTS_DIR, "emit_model_vs_data_band_table.jl"))

    # --- Stage 11j: Two-product extension (group access mixture) ---
    # Requires data/processed/group_access_by_band.csv (rebuilt by Stage 0f
    # when raw HRS data are present; committed aggregate otherwise).
    # Produces: two_product_gradient.csv, two_product_ss_cut.csv, two_product.tex
    run_stage(
        "11j. Two-product extension (16 solves)",
        joinpath(SCRIPTS_DIR, "run_two_product.jl"); parallel=true)
    run_stage(
        "11j-emit. Two-product table",
        joinpath(SCRIPTS_DIR, "emit_two_product_table.jl"))

    # --- Stage 11k: Period-certain pricing comparison (Appendix H) ---
    # Produces: period_certain_pricing.csv
    run_stage(
        "11k. Period-certain pricing comparison",
        joinpath(SCRIPTS_DIR, "emit_period_certain_pricing.jl"))

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

    # --- Stage 13c: Monte Carlo parameter uncertainty ---
    # Produces: monte_carlo_ownership.csv, monte_carlo_summary.tex.
    # 1000 joint draws over (gamma fixed) hazard_poor, inflation, MWR,
    # pessimism, delta_c. Yields 90% CI bands on the rational-stack
    # ownership prediction (behavioral parameters held at production values).
    t = run_stage(
        "13c. Monte Carlo Parameter Uncertainty",
        joinpath(SCRIPTS_DIR, "run_monte_carlo_uncertainty.jl"); parallel=true)
    push!(timings, "Monte Carlo uncertainty" => t)

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
    # Produces: state_utility_sensitivity.csv. Two full rational-stack solves
    # (behavioral parameters at neutral values) under the FLN and
    # Reichling-Smetters mappings of Finkelstein-Luttmer (2013).
    t = run_stage(
        "14b. State-dependent Utility Sensitivity (FLN vs R-S)",
        joinpath(SCRIPTS_DIR, "run_state_utility_sensitivity.jl"); parallel=true)
    push!(timings, "State-util sensitivity" => t)

    # --- Stage 14c: Grid and quadrature convergence diagnostics ---
    # Produces: tables/csv/convergence_diagnostics.csv (headline per-quartile
    # config). Backs the grid/quadrature convergence table in the appendix.
    t = run_stage(
        "14c. Grid and Quadrature Convergence Diagnostics",
        joinpath(SCRIPTS_DIR, "grid_convergence_full.jl"); parallel=true)
    push!(timings, "Convergence diagnostics" => t)

    # --- Stage 14c2: Annuitization-grid (alpha) convergence diagnostic ---
    # Produces: tables/csv/alpha_grid_diagnostics.csv. Backs Panel D of the
    # grid-convergence table (ownership stability across the n_alpha grid). Kept
    # separate from convergence_diagnostics.csv so it does not regenerate the
    # production-locked grid/quadrature rows.
    t = run_stage(
        "14c2. Annuitization-Grid (alpha) Convergence",
        joinpath(SCRIPTS_DIR, "alpha_grid_diagnostics.jl"); parallel=true)
    push!(timings, "Alpha-grid diagnostic" => t)

    # --- Stage 14d: Euler equation residual diagnostics ---
    # Produces: tables/csv/euler_residuals.csv. Backs the Euler-residual
    # table in the appendix (solver-accuracy check).
    t = run_stage(
        "14d. Euler Equation Residual Diagnostics",
        joinpath(SCRIPTS_DIR, "run_euler_diagnostics.jl"); parallel=true)
    push!(timings, "Euler diagnostics" => t)

    # --- Stage 14e: Render diagnostic tables from CSVs ---
    # Produces: tables/tex/grid_convergence.tex, euler_residuals_table.tex from
    # the Stage 14c/14d CSVs, so the appendix \input's reproducible tables rather
    # than hand-typed values.
    t = run_stage(
        "14e. Render Diagnostic Tables (grid convergence, Euler)",
        joinpath(SCRIPTS_DIR, "emit_diagnostic_tables.jl"))
    push!(timings, "Diagnostic tables" => t)

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
        "band_value_destruction.tex",
        "bequest_recalibration.tex",
        "cev_counterfactuals.tex",
        "dia_comparison.tex",
        "empirical_gradients_logit.tex",  # Stage 11c output; sec:empirical \input
        "euler_residuals_table.tex",  # Stage 14e output; appendix \input
        "extension_path.tex",
        "gate_robustness.tex",        # Stage 11g output; sec:gate \input
        "grid_convergence.tex",       # Stage 14e output; appendix \input
        "implied_gamma.tex",
        "model_vs_data_band.tex",     # Stage 11i output; sec:empirical \input
        "two_product.tex",            # Stage 11j output; counterfactuals \input
        "moment_validation.tex",
        "monte_carlo_summary.tex",  # Stage 13c output; appendix \input
        # multigamma_decomposition.tex is no longer required in the
        # manuscript (the prose now reports a brief diagnostic summary
        # instead of inputting the table). The Stage 3 generator still
        # writes it to tables/tex/ for diagnostic use, but missing or
        # stale versions do not block the package as submission-grade.
        "pairwise_interactions.tex",
        "partition_robustness.tex",
        "pashchenko_comparison.tex",
        "retention_rates.tex",
        "robustness_gamma_inflation.tex",
        "shapley_exact.tex",
        "shapley_nine.tex",
        "shapley_psi981.tex",        # Stage 10c output; app:psi_ranking \input
        "shapley_loads_split.tex",   # Stage 10d output; loads-split appendix \input
        "shapley_blended_mortality.tex",  # Stage 10e output; blended-mortality appendix \input
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
