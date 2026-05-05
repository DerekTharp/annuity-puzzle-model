#!/bin/bash
# Resume the pipeline from Stage 12. Used after a partial-failure run where
# Stages 0-11 already wrote their CSVs. Re-running Stages 12-16 picks up the
# fresh outputs from disk; later stages (15, 16) read those CSVs to generate
# the manuscript macros and validate.
#
# Run via:  nohup bash scripts/aws/resume_pipeline_remote.sh > /tmp/run_resume.log 2>&1 &
#
# Same truthfulness contract as run_pipeline_remote.sh: .pipeline-complete
# is touched only after every resumed stage exits 0.

set -uo pipefail

cd "$(dirname "$0")/../.."

PROJECT_DIR="$PWD"
LOG="$PROJECT_DIR/logs/run_resume_$(date +%Y%m%d_%H%M%S).log"
mkdir -p "$PROJECT_DIR/logs"

rm -f "$PROJECT_DIR/.pipeline-complete" "$PROJECT_DIR/.pipeline-partial"

echo "=== Resume start: $(date) ===" | tee -a "$LOG"
echo "Project: $PROJECT_DIR" | tee -a "$LOG"
echo "vCPU:   $(nproc)" | tee -a "$LOG"

# Worker count for parallel stages — match run_all.jl logic.
N_WORKERS="${ANNUITY_N_WORKERS:-$(($(nproc) - 4))}"
[ "$N_WORKERS" -lt 1 ] && N_WORKERS=1
echo "Workers: $N_WORKERS" | tee -a "$LOG"

run_stage() {
    local label="$1"
    local script="$2"
    local parallel="${3:-no}"
    echo "" | tee -a "$LOG"
    echo "======================================================================" | tee -a "$LOG"
    echo "  STAGE: $label" | tee -a "$LOG"
    echo "======================================================================" | tee -a "$LOG"
    local t0=$(date +%s)
    if [ "$parallel" = "parallel" ]; then
        julia --project=. -p "$N_WORKERS" "$script" 2>&1 | tee -a "$LOG"
    else
        julia --project=. "$script" 2>&1 | tee -a "$LOG"
    fi
    local rc=${PIPESTATUS[0]}
    local elapsed=$(( $(date +%s) - t0 ))
    if [ "$rc" != "0" ]; then
        echo "  FAILED: $label (${elapsed}s) rc=$rc" | tee -a "$LOG"
        return $rc
    fi
    echo "  Completed: $label (${elapsed}s)" | tee -a "$LOG"
    return 0
}

OVERALL_RC=0

# Stage 12 — robustness sweeps (was the failing stage)
run_stage "12. Robustness and Sensitivity Analysis" scripts/run_robustness.jl parallel || OVERALL_RC=$?

# Stage 13 — implied gamma (Monte Carlo bisection)
[ "$OVERALL_RC" = "0" ] && { run_stage "13. Implied Risk Aversion" scripts/run_implied_gamma.jl parallel || OVERALL_RC=$?; }

# Stage 13b — psi-purchase sensitivity
[ "$OVERALL_RC" = "0" ] && { run_stage "13b. Behavioral psi-purchase Sensitivity" scripts/run_psi_sensitivity.jl parallel || OVERALL_RC=$?; }

# Stage 13c — Monte Carlo joint parameter uncertainty
[ "$OVERALL_RC" = "0" ] && { run_stage "13c. Monte Carlo Parameter Uncertainty" scripts/run_monte_carlo_uncertainty.jl parallel || OVERALL_RC=$?; }

# Stage 13d — UK-anchored psi estimation (single-moment SMM)
[ "$OVERALL_RC" = "0" ] && { run_stage "13d. UK-anchored psi estimation" scripts/estimate_psi.jl parallel || OVERALL_RC=$?; }

# Stage 14 — figure generation (reads fresh CSVs)
[ "$OVERALL_RC" = "0" ] && { run_stage "14. Figure Generation" scripts/generate_figures.jl || OVERALL_RC=$?; }

# Stage 14b — state-dependent utility sensitivity
[ "$OVERALL_RC" = "0" ] && { run_stage "14b. State-dependent Utility Sensitivity" scripts/run_state_utility_sensitivity.jl || OVERALL_RC=$?; }

# Stage 15 — export manuscript numbers
[ "$OVERALL_RC" = "0" ] && { run_stage "15. Export Manuscript Numbers" scripts/export_manuscript_numbers.jl || OVERALL_RC=$?; }

# Stage 16 — post-run validation
[ "$OVERALL_RC" = "0" ] && { run_stage "16. Post-run Validation" test/test_manuscript_numbers.jl || OVERALL_RC=$?; }

# Bundle whatever results exist (always — even on partial failure).
echo "" | tee -a "$LOG"
echo "Bundling results..." | tee -a "$LOG"
RESULTS_TARBALL="$PROJECT_DIR/results_$(date +%Y%m%d_%H%M%S).tar.gz"
tar -czf "$RESULTS_TARBALL" \
    tables/csv/*.csv \
    tables/tex/*.tex \
    figures/pdf/*.pdf \
    figures/png/*.png \
    paper/numbers.tex \
    "$LOG" 2>/dev/null || echo "  (tar warning: some expected paths missing)" | tee -a "$LOG"

ln -sf "$RESULTS_TARBALL" "$PROJECT_DIR/results-latest.tar.gz"

if [ "$OVERALL_RC" = "0" ] || [ "${ANNUITY_FORCE_COMPLETE:-0}" = "1" ]; then
    touch "$PROJECT_DIR/.pipeline-complete"
    echo "=== Resume complete: $(date) ===" | tee -a "$LOG"
else
    touch "$PROJECT_DIR/.pipeline-partial"
    echo "=== Resume FAILED with rc=$OVERALL_RC at $(date) ===" | tee -a "$LOG"
    echo "Partial results in: $RESULTS_TARBALL" | tee -a "$LOG"
fi
echo "Results: $RESULTS_TARBALL" | tee -a "$LOG"
exit "$OVERALL_RC"
