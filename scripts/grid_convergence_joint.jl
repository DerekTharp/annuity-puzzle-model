# Joint grid convergence test.
# Test 1-3 showed annuity grid and alpha grid pull in opposite directions.
# This script refines both together to find the converged ownership rate.

using Printf
using DelimitedFiles
include(joinpath(@__DIR__, "..", "src", "AnnuityPuzzle.jl"))
using .AnnuityPuzzle

println("=" ^ 70)
println("  JOINT GRID CONVERGENCE TESTS")
println("=" ^ 70)

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
# Test 1: Joint refinement (scale all grids proportionally)
# ===================================================================
println("\n" * "=" ^ 70)
println("  TEST 1: JOINT REFINEMENT (nW, nA, nAlpha scaled together)")
println("=" ^ 70)

joint_specs = [
    # (nW, nA, nAlpha)
    (30,  10,  21),   # coarse
    (40,  15,  31),   # medium-coarse
    (60,  20,  51),   # current baseline
    (60,  25,  51),   # more annuity
    (60,  25,  101),  # more annuity + more alpha
    (80,  30,  101),  # fine
    (80,  30,  201),  # fine + very fine alpha
    (100, 40,  101),  # very fine
    (100, 40,  201),  # very fine + very fine alpha
]

@printf("\n  %-30s  %12s  %8s\n", "Grid (nW × nA × nα)", "Ownership", "Time")
println("  " * "-" ^ 54)

for (nw, na, nalpha) in joint_specs
    t0 = time()
    rate = run_model(n_wealth=nw, n_annuity=na, n_alpha=nalpha)
    elapsed = time() - t0
    @printf("  %3d × %2d × %-15d  %10.1f%%  %6.0fs\n",
        nw, na, nalpha, rate * 100, elapsed)
    flush(stdout)
end

# ===================================================================
# Test 2: Fixed fine wealth grid, vary annuity+alpha jointly
# ===================================================================
println("\n" * "=" ^ 70)
println("  TEST 2: ANNUITY+ALPHA JOINT (nW=80 fixed)")
println("=" ^ 70)

aa_specs = [
    (20, 51),
    (20, 101),
    (20, 201),
    (30, 51),
    (30, 101),
    (30, 201),
    (40, 101),
    (40, 201),
]

@printf("\n  %-30s  %12s  %8s\n", "Grid (nA × nα, nW=80)", "Ownership", "Time")
println("  " * "-" ^ 54)

for (na, nalpha) in aa_specs
    t0 = time()
    rate = run_model(n_wealth=80, n_annuity=na, n_alpha=nalpha)
    elapsed = time() - t0
    @printf("  %2d × %-22d  %10.1f%%  %6.0fs\n",
        na, nalpha, rate * 100, elapsed)
    flush(stdout)
end

println("\n" * "=" ^ 70)
println("  JOINT CONVERGENCE TESTS COMPLETE")
println("=" ^ 70)
