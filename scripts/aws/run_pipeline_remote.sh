#!/bin/bash
# Pipeline runner for the AWS instance.
# Resolves the Julia project, runs run_all.jl with full parallelization,
# tarballs the results, and only signals completion if every stage succeeded.
#
# Run via:  nohup bash scripts/aws/run_pipeline_remote.sh > /tmp/run_all.log 2>&1 &
#
# Truthfulness contract:
#   - `set -euo pipefail` so any unexpected error fails the script
#   - `.pipeline-complete` is touched only after run_all.jl exits 0
#   - tarball always written (so partial results can be inspected) but flagged
#     with .pipeline-partial when run_all.jl failed
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
rm -f Manifest.toml
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
# the partial CSVs aids diagnosis).
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

# Signal completion only when run_all.jl actually succeeded. Override with
# ANNUITY_FORCE_COMPLETE=1 if you want to manually flag a partial run done.
if [ "$PIPELINE_RC" = "0" ] || [ "${ANNUITY_FORCE_COMPLETE:-0}" = "1" ]; then
    touch "$PROJECT_DIR/.pipeline-complete"
    echo "=== Pipeline complete: $(date) ===" | tee -a "$LOG"
else
    touch "$PROJECT_DIR/.pipeline-partial"
    echo "=== Pipeline FAILED with rc=$PIPELINE_RC at $(date) ===" | tee -a "$LOG"
    echo "Partial results in: $RESULTS_TARBALL" | tee -a "$LOG"
    echo "(.pipeline-complete NOT touched — pull_results will refuse to declare success)" | tee -a "$LOG"
fi
echo "Results: $RESULTS_TARBALL" | tee -a "$LOG"
exit "$PIPELINE_RC"
