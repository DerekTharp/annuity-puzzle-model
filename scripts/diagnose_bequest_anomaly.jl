# Diagnose why homothetic bequest (theta=56.96, kappa=$10) gives 63.8% ownership
# when no bequests gives 23.3%.
#
# Hypothesis: theta=56.96 was calibrated jointly with kappa=$272K (DFJ luxury).
# Using it with kappa=$10 creates an unintended utility shape that does not
# correspond to any published "homothetic bequest" specification.

using Printf
using DelimitedFiles
include(joinpath(@__DIR__, "..", "src", "AnnuityPuzzle.jl"))
using .AnnuityPuzzle

println("=" ^ 70)
println("  BEQUEST ANOMALY DIAGNOSIS")
println("=" ^ 70)

# Common setup
const AGE_START   = 65
const AGE_END     = 110
const C_FLOOR     = 6_180.0
const W_MAX       = 3_000_000.0
const N_WEALTH    = 60
const N_ANNUITY   = 20
const N_ALPHA     = 51
const A_GRID_POW  = 3.0
const N_QUAD      = 9
const GAMMA       = 2.5
const BETA        = 0.97
const R_RATE      = 0.02
const MWR_LOADED  = 0.82
const FIXED_COST  = 1_000.0
const INFLATION   = 0.02
const HAZARD_MULT = [0.50, 1.0, 3.0]
const MIN_WEALTH  = 5_000.0
const THETA_DFJ   = 56.96
const KAPPA_DFJ   = 272_628.0

# Load population
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

common_kw = (gamma=GAMMA, beta=BETA, r=R_RATE,
             stochastic_health=true, n_health_states=3, n_quad=N_QUAD,
             c_floor=C_FLOOR, hazard_mult=HAZARD_MULT)
grid_kw = (n_wealth=N_WEALTH, n_annuity=N_ANNUITY, n_alpha=N_ALPHA,
           W_max=W_MAX, age_start=AGE_START, age_end=AGE_END,
           annuity_grid_power=A_GRID_POW)

# Build grids once (use fair payout for max A range)
p_fair = ModelParams(; common_kw..., mwr=1.0, grid_kw...)
fair_pr = compute_payout_rate(p_fair, base_surv)
grids = build_grids(p_fair, fair_pr)
loaded_pr = MWR_LOADED * fair_pr

# Prepare population with health column
pop_h = copy(population)
mask = pop_h[:, 1] .>= MIN_WEALTH
pop_h = pop_h[mask, :]
if size(pop_h, 2) < 4
    pop_h = hcat(pop_h, fill(2.0, size(pop_h, 1)))
end

function run_and_report(label, theta, kappa)
    p = ModelParams(; common_kw...,
        theta=theta, kappa=kappa,
        mwr=MWR_LOADED, fixed_cost=FIXED_COST, inflation_rate=INFLATION,
        medical_enabled=true, health_mortality_corr=true,
        grid_kw...)
    sol = solve_lifecycle_health(p, grids, base_surv, ss_zero)
    rate = compute_ownership_rate_health(sol, pop_h, loaded_pr; base_surv=base_surv).ownership_rate
    @printf("  %-45s  %10.1f%%\n", label, rate * 100)

    # Also look at alpha* for a few wealth levels
    alpha_star, _ = solve_annuitization_health(sol, loaded_pr; initial_health=2)
    w_idx = [10, 20, 30, 40, 50]
    for wi in w_idx
        if wi <= length(grids.W)
            @printf("    W=\$%8s → alpha*=%.2f\n",
                string(round(Int, grids.W[wi])), alpha_star[wi])
        end
    end
    return rate
end

# 1. Bequest utility shape comparison
println("\n--- Bequest utility shape at selected wealth levels ---")
@printf("  %-15s  %12s  %12s  %12s\n", "W at death",
    "No bequest", "Homo(k=10)", "DFJ(k=272K)")
println("  " * "-" ^ 55)

for b in [0.0, 1000.0, 10000.0, 50000.0, 100000.0, 500000.0, 1000000.0]
    u_none = 0.0  # theta=0
    # Homothetic: theta * (b + kappa)^(1-gamma) / (1-gamma)
    u_homo = THETA_DFJ * (b + 10.0)^(1.0 - GAMMA) / (1.0 - GAMMA)
    u_dfj  = THETA_DFJ * (b + KAPPA_DFJ)^(1.0 - GAMMA) / (1.0 - GAMMA)
    @printf("  \$%-14s  %12.2f  %12.2f  %12.2f\n",
        string(round(Int, b)), u_none, u_homo, u_dfj)
end

# 2. Run bequest comparison
println("\n--- Ownership by bequest specification ---")
@printf("  %-45s  %12s\n", "Bequest specification", "Ownership")
println("  " * "-" ^ 59)

bequest_specs = [
    ("No bequests",                0.0,       0.0),
    ("Homothetic (theta=1, k=10)", 1.0,       10.0),
    ("Homothetic (theta=5, k=10)", 5.0,       10.0),
    ("Homothetic (theta=56.96, k=10)", THETA_DFJ, 10.0),
    ("DFJ luxury (theta=56.96, k=272K)", THETA_DFJ, KAPPA_DFJ),
]

for (label, theta, kappa) in bequest_specs
    run_and_report(label, theta, kappa)
    println()
end

# 3. Key diagnostic: marginal bequest utility at low wealth
println("\n--- Marginal bequest utility v'(b) = theta * (b+kappa)^(-gamma) ---")
@printf("  %-15s  %12s  %12s\n", "b", "Homo(k=10)", "DFJ(k=272K)")
println("  " * "-" ^ 42)

for b in [0.0, 1000.0, 10000.0, 100000.0, 500000.0]
    mb_homo = THETA_DFJ * (b + 10.0)^(-GAMMA)
    mb_dfj  = THETA_DFJ * (b + KAPPA_DFJ)^(-GAMMA)
    @printf("  \$%-14s  %12.6f  %12.6f\n", string(round(Int, b)), mb_homo, mb_dfj)
end

println("\n" * "=" ^ 70)
println("  DIAGNOSIS COMPLETE")
println("=" ^ 70)
