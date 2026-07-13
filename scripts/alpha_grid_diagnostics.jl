# Annuitization-grid (alpha) convergence diagnostic.
# Ownership is the discontinuous indicator alpha* > 0, so the resolution of the
# age-65 annuitization grid (n_alpha points on [0,1]) can in principle shift
# marginal households across the participation threshold. This holds the wealth
# grid (80x30) and quadrature (N_QUAD nodes) at production resolution and sweeps
# n_alpha, on the headline per-quartile configuration used by
# grid_convergence_full.jl (so the n_alpha=101 cell matches the headline level).
#
# Output: tables/csv/alpha_grid_diagnostics.csv
# Kept separate from convergence_diagnostics.csv so this sweep does not
# regenerate (and risk perturbing) the production-locked grid/quadrature rows.

using Printf, DelimitedFiles
using Distributed

if nworkers() > 1
    @everywhere include(joinpath(@__DIR__, "..", "src", "AnnuityPuzzle.jl"))
    @everywhere using .AnnuityPuzzle
else
    include(joinpath(@__DIR__, "..", "src", "AnnuityPuzzle.jl"))
    using .AnnuityPuzzle
end
include(joinpath(@__DIR__, "config.jl"))  # production constants (THETA_DFJ, KAPPA_DFJ, CHI_LTC, ...)

println("=" ^ 70); flush(stdout)
println("  ANNUITIZATION-GRID (ALPHA) CONVERGENCE DIAGNOSTIC"); flush(stdout)
println("=" ^ 70); flush(stdout)

population = load_hrs_population(
    joinpath(@__DIR__, "..", "data", "processed", "lockwood_hrs_sample.csv");
    zero_ss=true)
n_pop = size(population, 1)

p_base = ModelParams(age_start=65, age_end=110)
base_surv = production_base_survival(p_base)
println("Data loaded ($n_pop obs)"); flush(stdout)

results = Tuple{String,Float64,Float64}[]  # (spec, ownership_pct, mean_alpha)

# Production diagnostic configuration (matches grid_convergence_full.jl's
# 80x30 production row at N_QUAD-node quadrature); only n_alpha varies.
function solve_alpha(nalpha)
    t0 = time()
    grid_kw = (n_wealth=80, n_annuity=30, n_alpha=nalpha,
               W_max=3_000_000.0, age_start=65, age_end=110,
               annuity_grid_power=3.0)

    p_fair_nom = ModelParams(; gamma=2.5, beta=0.97, r=0.02, mwr=1.0,
                               inflation_rate=0.02, grid_kw...)
    fair_pr_nom = compute_payout_rate(p_fair_nom, base_surv)
    loaded_pr_nom = MWR_LOADED * fair_pr_nom

    p_fair = ModelParams(; gamma=2.5, beta=0.97, r=0.02, mwr=1.0, grid_kw...)
    fair_pr = compute_payout_rate(p_fair, base_surv)
    grids = build_grids(p_fair, max(fair_pr, fair_pr_nom))

    p_full = ModelParams(; gamma=2.5, beta=0.97, r=0.02,
        theta=THETA_DFJ, kappa=KAPPA_DFJ,
        stochastic_health=true, n_health_states=3, n_quad=N_QUAD,
        c_floor=C_FLOOR, hazard_mult=Float64.(HAZARD_MULT), hazard_normalize=HAZARD_NORMALIZE,
        mwr=MWR_LOADED, fixed_cost=FIXED_COST, min_purchase=MIN_PURCHASE, inflation_rate=0.02,
        medical_enabled=true, health_mortality_corr=true,
        survival_pessimism=SURVIVAL_PESSIMISM,
        consumption_decline=CONSUMPTION_DECLINE,
        health_utility=Float64.(HEALTH_UTILITY),
        chi_ltc=CHI_LTC,
        grid_kw...)

    pop_filt = population[population[:, 1] .>= MIN_WEALTH, :]

    # Per-quartile SS assignment (the headline production configuration), matching
    # grid_convergence_full.jl: the model is solved separately per wealth bin with
    # its own SS level and aggregated.
    result = solve_and_evaluate(p_full, grids, base_surv,
                                Float64.(SS_QUARTILE_LEVELS), pop_filt, loaded_pr_nom;
                                verbose=false, db_levels=Float64.(DB_OBS))

    own, mean_a = result.ownership, result.mean_alpha
    @printf("  n_alpha=%-4d (smallest positive share %.4f)  own=%6.2f%%  mean_α=%.5f  (%5.1fs)\n",
            nalpha, 1 / (nalpha - 1), own * 100, mean_a, time() - t0)
    flush(stdout)
    push!(results, (@sprintf("n_alpha=%d", nalpha), own * 100, mean_a))
end

println("\n--- ALPHA-GRID SWEEP (80x30 grid, $(N_QUAD)-node GH) ---"); flush(stdout)
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
