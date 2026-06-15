#!/bin/bash
# Thin wrapper around run_all.jl, the single source-of-truth pipeline driver.
# All stage definitions and per-stage parallelism live in run_all.jl; this
# script is only a convenience entry point. Do not maintain a separate stage
# list here -- it drifts out of sync with run_all.jl.
set -e
cd "$(dirname "$0")"
exec julia --project=. run_all.jl "$@"
