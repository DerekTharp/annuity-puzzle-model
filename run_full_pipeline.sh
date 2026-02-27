#!/bin/bash
set -e
source ~/.bashrc
cd ~/annuity-puzzle-model

echo "=== PIPELINE START (subset enumeration architecture): $(date) ==="

echo "=== Stage 1: Lockwood replication ==="
julia --project=. scripts/run_lockwood_replication.jl
echo "=== Stage 1 DONE: $(date) ==="

echo "=== Stage 2: Subset enumeration (512 subsets, exact Shapley) ==="
julia --project=. -p 90 scripts/run_subset_enumeration.jl
echo "=== Stage 2 DONE: $(date) ==="

echo "=== Stage 3: Sequential decomposition ==="
julia --project=. -p 90 scripts/run_decomposition.jl
echo "=== Stage 3 DONE: $(date) ==="

echo "=== Stage 4: Multi-gamma decomposition ==="
julia --project=. -p 90 scripts/run_multigamma_decomposition.jl
echo "=== Stage 4 DONE: $(date) ==="

echo "=== Stage 5: Pashchenko comparison ==="
julia --project=. -p 90 scripts/run_pashchenko_comparison.jl
echo "=== Stage 5 DONE: $(date) ==="

echo "=== Stage 6: Moment validation ==="
julia --project=. scripts/run_moment_validation.jl
echo "=== Stage 6 DONE: $(date) ==="

echo "=== Stage 7: CEV welfare analysis ==="
julia --project=. scripts/run_welfare_analysis.jl
echo "=== Stage 7 DONE: $(date) ==="

echo "=== Stage 8: Welfare counterfactuals ==="
julia --project=. -p 90 scripts/run_welfare_counterfactuals.jl
echo "=== Stage 8 DONE: $(date) ==="

echo "=== Stage 9: DIA/QLAC analysis ==="
julia --project=. scripts/run_dia_analysis.jl
echo "=== Stage 9 DONE: $(date) ==="

echo "=== Stage 10: Bequest recalibration ==="
julia --project=. calibration/recalibrate_bequests.jl
echo "=== Stage 10 DONE: $(date) ==="

echo "=== Stage 11: Robustness ==="
julia --project=. -p 90 scripts/run_robustness.jl
echo "=== Stage 11 DONE: $(date) ==="

echo "=== Stage 12: Implied gamma ==="
julia --project=. -p 90 scripts/run_implied_gamma.jl
echo "=== Stage 12 DONE: $(date) ==="

echo "=== Stage 13: SS cut robustness ==="
julia --project=. -p 90 scripts/run_ss_robustness.jl
echo "=== Stage 13 DONE: $(date) ==="

echo "=== Stage 14: Figures ==="
julia --project=. scripts/generate_figures.jl
echo "=== Stage 14 DONE: $(date) ==="

echo "=== ALL 14 STAGES COMPLETE: $(date) ==="
echo "CSV:"; ls tables/csv/
echo "TEX:"; ls tables/tex/
echo "FIGURES:"; ls figures/pdf/ 2>/dev/null
