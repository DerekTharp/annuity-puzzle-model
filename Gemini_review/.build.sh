#!/bin/bash
# Build the Gemini_review/ folder by concatenating files with provenance banners.
# Run from the project root.

set -euo pipefail

# Banner helpers --------------------------------------------------------------
jl_banner() {
    cat <<EOF

#=============================================================================
# ORIGINAL FILE: $1
#=============================================================================

EOF
}

tex_banner() {
    cat <<EOF

% =============================================================================
% ORIGINAL FILE: $1
% =============================================================================

EOF
}

md_banner() {
    cat <<EOF

---

## ORIGINAL FILE: $1

EOF
}

# 01 — Manuscript -------------------------------------------------------------
cp paper/main.tex Gemini_review/01_manuscript.tex

# 02 — Appendix ---------------------------------------------------------------
cp paper/appendix.tex Gemini_review/02_appendix.tex

# 03 — Overview (README, cover letter, Project.toml, run_all.jl, numbers.tex) -
{
    cat <<'EOF'
# Annuity Puzzle Replication Package — Reviewer Overview

This file consolidates the reproducibility-relevant top-level documents for
external review. The full project repository is structured as described in
the README section below; the source code, scripts, and tests are split
across files 04 through 10 in this folder.

EOF
    md_banner "README.md"
    cat README.md
    md_banner "paper/cover_letter.tex"
    echo '```latex'
    cat paper/cover_letter.tex
    echo '```'
    md_banner "Project.toml"
    echo '```toml'
    cat Project.toml
    echo '```'
    md_banner "run_all.jl (master pipeline driver)"
    echo '```julia'
    cat run_all.jl
    echo '```'
    md_banner "paper/numbers.tex (auto-generated headline-number macros)"
    echo '```latex'
    cat paper/numbers.tex
    echo '```'
} > Gemini_review/03_overview.md

# 04 — Model core (small structural modules) ----------------------------------
{
    cat <<'EOF'
# =============================================================================
# 04_model_core.jl — Concatenated model module and structural primitives.
#
# This file consolidates the following original source files (in order):
#   src/AnnuityPuzzle.jl       module entry point and exports
#   src/parameters.jl          ModelParams struct and defaults
#   src/utility.jl             CRRA, bequest, source-dependent utility, narrow-framing penalty
#   src/income.jl              Social Security income profile
#   src/lockwood_lifetable.jl  SSA administrative life table builder
#   src/grids.jl               Wealth/annuity/health grid construction + clamp audit
#   src/annuity.jl             Annuity payout-rate computation, MWR loading
#
# To restore the working repository layout, split each banner-delimited
# section back into its original path under src/.
# =============================================================================
EOF
    for f in src/AnnuityPuzzle.jl src/parameters.jl src/utility.jl src/income.jl src/lockwood_lifetable.jl src/grids.jl src/annuity.jl; do
        jl_banner "$f"
        cat "$f"
    done
} > Gemini_review/04_model_core.jl

# 05 — Solver and simulation --------------------------------------------------
{
    cat <<'EOF'
# =============================================================================
# 05_solver.jl — Dynamic programming solver and simulation engine.
#
# This file consolidates:
#   src/bellman.jl       one-period Bellman equation
#   src/solve.jl         backward induction + age-65 annuitization decision
#   src/simulation.jl    Monte Carlo lifecycle simulation (per-period re-optimization)
#   src/diagnostics.jl   Euler residuals, value-function diagnostics
# =============================================================================
EOF
    for f in src/bellman.jl src/solve.jl src/simulation.jl src/diagnostics.jl; do
        jl_banner "$f"
        cat "$f"
    done
} > Gemini_review/05_solver.jl

# 06 — Health, welfare, WTP ---------------------------------------------------
{
    cat <<'EOF'
# =============================================================================
# 06_health_welfare.jl — Health/mortality dynamics and welfare metrics.
#
# This file consolidates:
#   src/health.jl     3-state health Markov, hazard multipliers, medical-cost process,
#                     Medicaid floor, age-band hazard ratios from RAND HRS
#   src/welfare.jl    Consumption-equivalent variation (CEV) computation
#   src/wtp.jl        Willingness-to-pay metrics, population WTP, force-decomposition WTP
# =============================================================================
EOF
    for f in src/health.jl src/welfare.jl src/wtp.jl; do
        jl_banner "$f"
        cat "$f"
    done
} > Gemini_review/06_health_welfare.jl

# 07 — Decomposition (channel + Shapley enumeration) --------------------------
{
    cat <<'EOF'
# =============================================================================
# 07_decomposition.jl — Channel decomposition machinery and pipeline scripts.
#
# This file consolidates:
#   src/decomposition.jl                channel-toggle harness and ModelParams overrides
#   scripts/run_decomposition.jl        sequential decomposition (rational + preference + behavioral)
#   scripts/run_subset_enumeration.jl   1024-subset enumeration for Shapley
#   scripts/run_shapley_decomposition.jl Shapley value computation from subset table
#
# This is where the 10-channel decomposition is operationalized. The Shapley
# stage is the largest single computational cost (1024 full-model solves).
# =============================================================================
EOF
    for f in src/decomposition.jl scripts/run_decomposition.jl scripts/run_subset_enumeration.jl scripts/run_shapley_decomposition.jl; do
        jl_banner "$f"
        cat "$f"
    done
} > Gemini_review/07_decomposition.jl

# 08 — Calibration, robustness, sensitivity -----------------------------------
{
    cat <<'EOF'
# =============================================================================
# 08_calibration_robustness.jl — Calibration, robustness, and sensitivity scripts.
#
# This file consolidates:
#   scripts/config.jl                          canonical baseline parameters
#   scripts/estimate_psi.jl                    UK-anchored psi_purchase SMM estimator
#   scripts/run_psi_sensitivity.jl             psi_purchase sensitivity sweep
#   scripts/run_robustness.jl                  full-grid robustness across parameters
#   scripts/run_monte_carlo_uncertainty.jl     joint parameter uncertainty
#   scripts/run_implied_gamma.jl               implied risk-aversion bisection
#   scripts/run_multigamma_decomposition.jl    decomposition across gamma values
#   scripts/run_state_utility_sensitivity.jl   state-dependent utility sensitivity
#   scripts/run_ageband_hazard.jl              age-band hazard estimation from HRS
#   scripts/run_ss_robustness.jl               Social Security robustness
#   scripts/grid_convergence_full.jl           grid convergence diagnostic
# =============================================================================
EOF
    for f in scripts/config.jl scripts/estimate_psi.jl scripts/run_psi_sensitivity.jl scripts/run_robustness.jl scripts/run_monte_carlo_uncertainty.jl scripts/run_implied_gamma.jl scripts/run_multigamma_decomposition.jl scripts/run_state_utility_sensitivity.jl scripts/run_ageband_hazard.jl scripts/run_ss_robustness.jl scripts/grid_convergence_full.jl; do
        jl_banner "$f"
        cat "$f"
    done
} > Gemini_review/08_calibration_robustness.jl

# 09 — Validation, replication, welfare counterfactuals, figures, export ------
{
    cat <<'EOF'
# =============================================================================
# 09_validation_export.jl — Replication targets, welfare counterfactuals, output.
#
# This file consolidates:
#   scripts/run_lockwood_replication.jl    Lockwood (2012) replication
#   scripts/run_pashchenko_comparison.jl   Pashchenko (2013) comparison
#   scripts/run_dia_analysis.jl            DIA/QLAC deferred-annuity analysis
#   scripts/run_moment_validation.jl       moment-match diagnostics vs HRS
#   scripts/run_welfare_analysis.jl        baseline welfare analysis
#   scripts/run_welfare_counterfactuals.jl welfare counterfactuals (no-bequest, etc.)
#   scripts/run_health_analysis.jl         health-state-conditional analysis
#   scripts/run_simulation.jl              standalone simulation driver
#   scripts/generate_figures.jl            figure generation
#   scripts/export_manuscript_numbers.jl   numbers.tex macro generator (387 macros)
# =============================================================================
EOF
    for f in scripts/run_lockwood_replication.jl scripts/run_pashchenko_comparison.jl scripts/run_dia_analysis.jl scripts/run_moment_validation.jl scripts/run_welfare_analysis.jl scripts/run_welfare_counterfactuals.jl scripts/run_health_analysis.jl scripts/run_simulation.jl scripts/generate_figures.jl scripts/export_manuscript_numbers.jl; do
        jl_banner "$f"
        cat "$f"
    done
} > Gemini_review/09_validation_export.jl

# 10 — Test suite -------------------------------------------------------------
{
    cat <<'EOF'
# =============================================================================
# 10_tests.jl — Test suite.
#
# This file consolidates:
#   test/runtests.jl                  test driver
#   test/test_utility.jl              CRRA + bequest + purchase-penalty unit tests
#   test/test_limiting_cases.jl       Yaari benchmark, infinite bequest, etc.
#   test/test_grid_clamp_audit.jl     wealth/annuity grid clamp audit
#   test/test_age_invariance.jl       age-invariance regression tests
#   test/test_health.jl               health Markov + medical-cost tests
#   test/test_lockwood.jl             Lockwood (2012) replication tests
#   test/test_pashchenko_dia.jl       Pashchenko + DIA tests
#   test/test_phase4.jl               Phase 4 build-stage integration tests
#   test/test_welfare.jl              CEV computation tests
#   test/test_10channel_smoke.jl      10-channel smoke test
#   test/test_manuscript_numbers.jl   manuscript-number lock against numbers.tex
#
# Note: test/test_headline_regression.jl.deprecated is not included
# (deprecated in favor of test_manuscript_numbers.jl + test_age_invariance.jl).
# =============================================================================
EOF
    for f in test/runtests.jl test/test_utility.jl test/test_limiting_cases.jl test/test_grid_clamp_audit.jl test/test_age_invariance.jl test/test_health.jl test/test_lockwood.jl test/test_pashchenko_dia.jl test/test_phase4.jl test/test_welfare.jl test/test_10channel_smoke.jl test/test_manuscript_numbers.jl; do
        jl_banner "$f"
        cat "$f"
    done
} > Gemini_review/10_tests.jl

echo "Build complete."
