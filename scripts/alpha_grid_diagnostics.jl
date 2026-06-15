# Annuitization-grid (alpha) convergence diagnostic.
# Ownership is the discontinuous indicator alpha* > 0, so the resolution of the
# age-65 annuitization grid (n_alpha points on [0,1]) can in principle shift
# marginal households across the participation threshold. This holds the wealth
# grid (80x30) and quadrature (9-node GH) at production resolution and sweeps
# n_alpha, on the same mean-SS diagnostic used by grid_convergence_full.jl.
#
# Output: tables/csv/alpha_grid_diagnostics.csv
# Kept separate from convergence_diagnostics.csv so this sweep does not
# regenerate (and risk perturbing) the production-locked grid/quadrature rows.

using Printf, DelimitedFiles

include(joinpath(@__DIR__, "..", "src", "AnnuityPuzzle.jl"))
using .AnnuityPuzzle

println("=" ^ 70); flush(stdout)
println("  ANNUITIZATION-GRID (ALPHA) CONVERGENCE DIAGNOSTIC"); flush(stdout)
println("=" ^ 70); flush(stdout)

const THETA_DFJ = 56.96
const KAPPA_DFJ = 272_628.0

hrs_raw = readdlm(joinpath(@__DIR__, "..", "data", "processed", "lockwood_hrs_sample.csv"),
                   ',', Any; skipstart=1)
n_pop = size(hrs_raw, 1)
population = zeros(n_pop, 4)
population[:, 1] = Float64.(hrs_raw[:, 1])
population[:, 2] .= 0.0                      # SS enters via ss_func, not the A grid
population[:, 3] = Float64.(hrs_raw[:, 3])
population[:, 4] = size(hrs_raw, 2) >= 4 ? Float64.(hrs_raw[:, 4]) : fill(2.0, n_pop)

p_base = ModelParams(age_start=65, age_end=110)
base_surv = build_lockwood_survival(p_base)
println("Data loaded ($n_pop obs)"); flush(stdout)

results = Tuple{String,Float64,Float64}[]  # (spec, ownership_pct, mean_alpha)

# Production diagnostic configuration (matches grid_convergence_full.jl's
# 80x30, 9-node GH "Grid (9-node)" production row); only n_alpha varies.
function solve_alpha(nalpha)
    t0 = time()
    grid_kw = (n_wealth=80, n_annuity=30, n_alpha=nalpha,
               W_max=3_000_000.0, age_start=65, age_end=110,
               annuity_grid_power=3.0)

    p_fair_nom = ModelParams(; gamma=2.5, beta=0.97, r=0.02, mwr=1.0,
                               inflation_rate=0.02, grid_kw...)
    fair_pr_nom = compute_payout_rate(p_fair_nom, base_surv)
    loaded_pr_nom = 0.87 * fair_pr_nom

    p_fair = ModelParams(; gamma=2.5, beta=0.97, r=0.02, mwr=1.0, grid_kw...)
    fair_pr = compute_payout_rate(p_fair, base_surv)
    grids = build_grids(p_fair, max(fair_pr, fair_pr_nom))

    p_full = ModelParams(; gamma=2.5, beta=0.97, r=0.02,
        theta=THETA_DFJ, kappa=KAPPA_DFJ,
        stochastic_health=true, n_health_states=3, n_quad=9,
        c_floor=6180.0, hazard_mult=[0.50, 1.0, 3.75],
        mwr=0.87, fixed_cost=2500.0, inflation_rate=0.02,
        medical_enabled=true, health_mortality_corr=true,
        survival_pessimism=0.96,
        grid_kw...)

    ss_mean_val = sum(SS_QUARTILE_LEVELS) / length(SS_QUARTILE_LEVELS)
    ss_func(age, p) = ss_mean_val

    pop_filt = population[population[:, 1] .>= 5000.0, :]

    sol = solve_lifecycle_health(p_full, grids, base_surv, ss_func)
    result = compute_ownership_rate_health(sol, pop_filt, loaded_pr_nom; base_surv=base_surv)

    own, mean_a = result.ownership_rate, result.mean_alpha
    @printf("  n_alpha=%-4d (smallest positive share %.4f)  own=%6.2f%%  mean_α=%.5f  (%5.1fs)\n",
            nalpha, 1 / (nalpha - 1), own * 100, mean_a, time() - t0)
    flush(stdout)
    push!(results, (@sprintf("n_alpha=%d", nalpha), own * 100, mean_a))
end

println("\n--- ALPHA-GRID SWEEP (80x30 grid, 9-node GH) ---"); flush(stdout)
for nalpha in [51, 101, 201, 401]   # 101 is the production resolution
    solve_alpha(nalpha)
end

csv_path = joinpath(@__DIR__, "..", "tables", "csv", "alpha_grid_diagnostics.csv")
mkpath(dirname(csv_path))
open(csv_path, "w") do f
    println(f, "specification,ownership_pct,mean_alpha")
    for (spec, own, ma) in results
        @printf(f, "%s,%.2f,%.6f\n", spec, own, ma)
    end
end
println("\nCSV written: $csv_path"); flush(stdout)
println("=" ^ 70); flush(stdout)
println("  ALPHA-GRID DIAGNOSTIC COMPLETE"); flush(stdout)
println("=" ^ 70); flush(stdout)
