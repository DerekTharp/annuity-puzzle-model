#!/bin/bash
# Pipeline runner for the AWS instance.
# Resolves the Julia project, runs run_all.jl with full parallelization,
# tarballs the results, and only signals completion if every stage succeeded.
#
# Run via:  nohup bash scripts/aws/run_pipeline_remote.sh > /tmp/run_all.log 2>&1 &
#
# Truthfulness contract:
#   - `set -uo pipefail` (no -e): unset variables and pipeline failures are
#     fatal, but stage and tar return codes are captured explicitly so the
#     script can write a partial bundle for diagnosis before exiting
#     non-zero. `set -e` is intentionally not used because it would abort
#     before the partial-bundle write and the .pipeline-partial touch.
#   - PIPELINE_RC captures run_all.jl's exit code; TAR_RC and BUNDLE_RC
#     gate the bundle write (required-file check + tar success).
#   - `.pipeline-complete` is touched only when PIPELINE_RC=0 AND BUNDLE_RC=0.
#     Otherwise `.pipeline-partial` is written and the script exits non-zero.
#
# Override truthfulness for explicit debug:
#   ANNUITY_FORCE_COMPLETE=1 bash scripts/aws/run_pipeline_remote.sh

set -uo pipefail

cd "$(dirname "$0")/../.."

PROJECT_DIR="$PWD"
LOG="$PROJECT_DIR/logs/run_all_$(date +%Y%m%d_%H%M%S).log"
mkdir -p "$PROJECT_DIR/logs"

# Clear any stale signal files from previous runs
rm -f "$PROJECT_DIR/.pipeline-complete" "$PROJECT_DIR/.pipeline-partial"

echo "=== Pipeline start: $(date) ===" | tee -a "$LOG"
echo "Project: $PROJECT_DIR" | tee -a "$LOG"
echo "vCPU:   $(nproc)" | tee -a "$LOG"
echo "Memory: $(free -h | awk '/^Mem:/ {print $2}')" | tee -a "$LOG"

# Resolve Julia packages. On a fresh AWS instance the General registry
# isn't even installed yet; we explicitly add it, then delete any stale
# Manifest (the project tracks 1.12 macros locally; AWS runs 1.10), and
# let Pkg.instantiate generate a fresh manifest compatible with the runtime
# Julia. Skip eager Pkg.precompile (some packages with native deps fail
# eager precompile on AL2023; they precompile lazily on first load).
echo "Instantiating Julia project..." | tee -a "$LOG"
# Manifest deletion is opt-in — set ANNUITY_REFRESH_MANIFEST=1 to force a
# fresh resolve. By default the AWS pipeline reuses the local Manifest so
# that results are bit-for-bit reproducible against the committed lockfile,
# matching the README's reproducibility claim.
if [ "${ANNUITY_REFRESH_MANIFEST:-0}" = "1" ]; then
    echo "ANNUITY_REFRESH_MANIFEST=1 set — deleting Manifest.toml" | tee -a "$LOG"
    rm -f Manifest.toml
fi
if ! julia --project=. -e '
    using Pkg
    reg_dir = joinpath(DEPOT_PATH[1], "registries")
    if !isdir(reg_dir) || isempty(readdir(reg_dir; join=true))
        Pkg.Registry.add("General")
    else
        Pkg.Registry.update()
    end
    Pkg.resolve()
    Pkg.instantiate()
' 2>&1 | tee -a "$LOG"; then
    echo "FAILED: package resolve/instantiate" | tee -a "$LOG"
    exit 1
fi

# Run the full pipeline. We do NOT skip tests in production; run_all.jl
# manages worker counts per stage internally.
echo "Starting full pipeline..." | tee -a "$LOG"
PIPELINE_RC=0
julia --project=. run_all.jl 2>&1 | tee -a "$LOG"
PIPELINE_RC=${PIPESTATUS[0]}
echo "run_all.jl exit code: $PIPELINE_RC" | tee -a "$LOG"

# Bundle whatever results exist (always — even on partial failure, having
# the partial CSVs aids diagnosis). The bundle includes:
#   - All CSVs and LaTeX tables (tables/{csv,tex})
#   - All figures (figures/{pdf,png})
#   - All intermediate result objects (results/*.json, *.jld2, etc.) so
#     downstream provenance like psi_estimation.json travels with the run
#   - Generated manuscript macros (paper/numbers.tex)
#   - Lockfile snapshot (Project.toml, Manifest.toml) for reproducibility
#   - Launch provenance manifest (.aws-launch-provenance.txt) tying the
#     run to a specific committed git state
#   - Run log (relative path; tar copes with absolute path warnings)
echo "Bundling results..." | tee -a "$LOG"
RESULTS_TARBALL="$PROJECT_DIR/results_$(date +%Y%m%d_%H%M%S).tar.gz"
LOG_REL="logs/$(basename "$LOG")"

# Required-file gate: explicitly verify every expected provenance input
# exists before tarring. If any required file is missing, fail the bundle
# step (BUNDLE_RC=1) so the pipeline cannot mark .pipeline-complete with
# an incomplete provenance bundle. Generated artifacts (tables/figures)
# are checked at the directory level.
BUNDLE_RC=0
REQUIRED_FILES=(
    "Project.toml"
    "Manifest.toml"
    ".aws-launch-provenance.txt"
    "paper/numbers.tex"
)
for f in "${REQUIRED_FILES[@]}"; do
    if [ ! -f "$PROJECT_DIR/$f" ]; then
        echo "BUNDLE GATE: missing required file: $f" | tee -a "$LOG"
        BUNDLE_RC=1
    fi
done
if [ ! -d "$PROJECT_DIR/tables/csv" ] || [ -z "$(ls -A "$PROJECT_DIR/tables/csv" 2>/dev/null)" ]; then
    echo "BUNDLE GATE: tables/csv missing or empty" | tee -a "$LOG"
    BUNDLE_RC=1
fi
if [ ! -d "$PROJECT_DIR/tables/tex" ] || [ -z "$(ls -A "$PROJECT_DIR/tables/tex" 2>/dev/null)" ]; then
    echo "BUNDLE GATE: tables/tex missing or empty" | tee -a "$LOG"
    BUNDLE_RC=1
fi

# Tar the bundle. Capture tar's exit code; any failure (including
# missing-input failures, despite the gate above) sets BUNDLE_RC.
tar -czf "$RESULTS_TARBALL" \
    tables/csv/*.csv \
    tables/tex/*.tex \
    figures/pdf/*.pdf \
    figures/png/*.png \
    paper/numbers.tex \
    Project.toml \
    Manifest.toml \
    .aws-launch-provenance.txt \
    "$LOG_REL" \
    $(find results -type f 2>/dev/null) \
    2>&1 | tee -a "$LOG"
TAR_RC=${PIPESTATUS[0]}
if [ "$TAR_RC" != "0" ]; then
    echo "BUNDLE GATE: tar exited with rc=$TAR_RC" | tee -a "$LOG"
    BUNDLE_RC=1
fi

ln -sf "$RESULTS_TARBALL" "$PROJECT_DIR/results-latest.tar.gz"

# Signal completion only when BOTH the pipeline AND the bundle gate
# succeeded. Override with ANNUITY_FORCE_COMPLETE=1 if you want to
# manually flag a partial run done.
if { [ "$PIPELINE_RC" = "0" ] && [ "$BUNDLE_RC" = "0" ]; } || [ "${ANNUITY_FORCE_COMPLETE:-0}" = "1" ]; then
    touch "$PROJECT_DIR/.pipeline-complete"
    echo "=== Pipeline complete: $(date) ===" | tee -a "$LOG"
else
    touch "$PROJECT_DIR/.pipeline-partial"
    echo "=== Pipeline FAILED: pipeline_rc=$PIPELINE_RC bundle_rc=$BUNDLE_RC at $(date) ===" | tee -a "$LOG"
    echo "Partial results in: $RESULTS_TARBALL" | tee -a "$LOG"
    echo "(.pipeline-complete NOT touched — pull_results will refuse to declare success)" | tee -a "$LOG"
fi
echo "Results: $RESULTS_TARBALL" | tee -a "$LOG"
# Exit code is nonzero if EITHER the pipeline or the bundle gate failed.
if [ "$PIPELINE_RC" != "0" ]; then
    exit "$PIPELINE_RC"
else
    exit "$BUNDLE_RC"
fi
