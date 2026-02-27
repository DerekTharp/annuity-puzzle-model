# Grid convergence isolation test.
# The robustness test varied n_wealth AND n_annuity together.
# This script tests each dimension separately and also tests n_alpha.

using Printf
using DelimitedFiles
include(joinpath(@__DIR__, "..", "src", "AnnuityPuzzle.jl"))
using .AnnuityPuzzle

println("=" ^ 70)
println("  GRID CONVERGENCE ISOLATION TESTS")
println("=" ^ 70)

# Baseline calibration
const GAMMA       = 2.5
const BETA        = 0.97
const R_RATE      = 0.02
const AGE_START   = 65
const AGE_END     = 110
const C_FLOOR     = 6_180.0
const W_MAX       = 3_000_000.0
const A_GRID_POW  = 3.0
const N_QUAD      = 5
const MWR_LOADED  = 0.82
const FIXED_COST  = 1_000.0
const INFLATION   = 0.02
const THETA_DFJ   = 56.96
const KAPPA_DFJ   = 272_628.0
const HAZARD_MULT = [0.50, 1.0, 3.0]
const MIN_WEALTH  = 5_000.0

# Load data
println("\nLoading HRS population...")
hrs_path = joinpath(@__DIR__, "..", "data", "processed", "lockwood_hrs_sample.csv")
hrs_raw = readdlm(hrs_path, ',', Any; skipstart=1)
n_pop = size(hrs_raw, 1)
population = zeros(n_pop, 4)
population[:, 1] = Float64.(hrs_raw[:, 1])
population[:, 2] .= 0.0                      # SS enters via ss_func, not A grid
population[:, 3] = Float64.(hrs_raw[:, 3])
if size(hrs_raw, 2) >= 4
    population[:, 4] = Float64.(hrs_raw[:, 4])  # observed health (1=Good, 2=Fair, 3=Poor)
else
    population[:, 4] .= 2.0
end

p_base = ModelParams(age_start=AGE_START, age_end=AGE_END)
base_surv = build_lockwood_survival(p_base)

ss_zero(age, p) = 0.0

base_kw = Dict{Symbol,Any}(
    :gamma => GAMMA, :beta => BETA, :r => R_RATE,
    :theta => THETA_DFJ, :kappa => KAPPA_DFJ,
    :c_floor => C_FLOOR,
    :mwr_loaded => MWR_LOADED,
    :fixed_cost_val => FIXED_COST,
    :inflation_val => INFLATION,
    :W_max => W_MAX, :n_quad => N_QUAD,
    :age_start => AGE_START, :age_end => AGE_END,
    :annuity_grid_power => A_GRID_POW,
    :hazard_mult => HAZARD_MULT,
    :min_wealth => MIN_WEALTH,
    :verbose => false,
)

function run_model(; overrides...)
    kw = copy(base_kw)
    for (k, v) in overrides
        kw[k] = v
    end
    result = run_decomposition(base_surv, population; kw...)
    return result.steps[end].ownership_rate
end

# ===================================================================
# Test 1: Vary n_wealth independently (hold n_annuity=20, n_alpha=51)
# ===================================================================
println("\n" * "=" ^ 70)
println("  TEST 1: WEALTH GRID REFINEMENT (n_annuity=20, n_alpha=51)")
println("=" ^ 70)

nw_vals = [30, 40, 50, 60, 80, 100]
@printf("\n  %-20s  %12s  %8s\n", "n_wealth", "Ownership", "Time")
println("  " * "-" ^ 44)

for nw in nw_vals
    t0 = time()
    rate = run_model(n_wealth=nw, n_annuity=20, n_alpha=51)
    elapsed = time() - t0
    @printf("  %-20d  %10.1f%%  %6.0fs\n", nw, rate * 100, elapsed)
end

# ===================================================================
# Test 2: Vary n_annuity independently (hold n_wealth=60, n_alpha=51)
# ===================================================================
println("\n" * "=" ^ 70)
println("  TEST 2: ANNUITY GRID REFINEMENT (n_wealth=60, n_alpha=51)")
println("=" ^ 70)

na_vals = [10, 15, 20, 25, 30, 40]
@printf("\n  %-20s  %12s  %8s\n", "n_annuity", "Ownership", "Time")
println("  " * "-" ^ 44)

for na in na_vals
    t0 = time()
    rate = run_model(n_wealth=60, n_annuity=na, n_alpha=51)
    elapsed = time() - t0
    @printf("  %-20d  %10.1f%%  %6.0fs\n", na, rate * 100, elapsed)
end

# ===================================================================
# Test 3: Vary n_alpha independently (hold n_wealth=60, n_annuity=20)
# ===================================================================
println("\n" * "=" ^ 70)
println("  TEST 3: ALPHA GRID REFINEMENT (n_wealth=60, n_annuity=20)")
println("=" ^ 70)

nalpha_vals = [21, 51, 101, 201]
@printf("\n  %-20s  %12s  %8s\n", "n_alpha", "Ownership", "Time")
println("  " * "-" ^ 44)

for na in nalpha_vals
    t0 = time()
    rate = run_model(n_wealth=60, n_annuity=20, n_alpha=na)
    elapsed = time() - t0
    @printf("  %-20d  %10.1f%%  %6.0fs\n", na, rate * 100, elapsed)
end

# ===================================================================
# Test 4: Full 2D grid (replicate + extend)
# ===================================================================
println("\n" * "=" ^ 70)
println("  TEST 4: FULL 2D GRID TABLE (n_alpha=51)")
println("=" ^ 70)

grid_specs = [
    (30, 10), (30, 20),
    (60, 10), (60, 20), (60, 30),
    (100, 20), (100, 30),
]

@printf("\n  %-20s  %12s  %8s\n", "Grid (nW x nA)", "Ownership", "Time")
println("  " * "-" ^ 44)

for (nw, na) in grid_specs
    t0 = time()
    rate = run_model(n_wealth=nw, n_annuity=na, n_alpha=51)
    elapsed = time() - t0
    @printf("  %3d × %-14d  %10.1f%%  %6.0fs\n", nw, na, rate * 100, elapsed)
end

println("\n" * "=" ^ 70)
println("  GRID CONVERGENCE TESTS COMPLETE")
println("=" ^ 70)
