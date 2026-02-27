# Euler equation residual diagnostics.
# Solves the full model at baseline parameters and computes normalized
# Euler residuals at every interior grid point. Reports summary statistics
# and checks convergence across grid densities.
#
# Output: tables/csv/euler_residuals.csv

using Printf, DelimitedFiles

include(joinpath(@__DIR__, "..", "src", "AnnuityPuzzle.jl"))
using .AnnuityPuzzle

include(joinpath(@__DIR__, "config.jl"))

println("=" ^ 70); flush(stdout)
println("  EULER EQUATION RESIDUAL DIAGNOSTICS"); flush(stdout)
println("=" ^ 70); flush(stdout)

hrs_raw = readdlm(HRS_PATH,
                   ',', Any; skipstart=1)
n_pop = size(hrs_raw, 1)
println("Data loaded ($n_pop obs)"); flush(stdout)

p_base = ModelParams(age_start=AGE_START, age_end=AGE_END)
base_surv = build_lockwood_survival(p_base)

ss_mean_val = sum(SS_QUARTILE_LEVELS) / length(SS_QUARTILE_LEVELS)
ss_func(age, p) = ss_mean_val

results = Tuple{String,Float64,Float64,Float64,Float64,Float64,Int,Int}[]

function run_euler_check(label, base_surv, ss_func; kw...)
    kw_dict = Dict{Symbol,Any}(kw...)
    nw = get(kw_dict, :n_wealth, N_WEALTH)
    na = get(kw_dict, :n_annuity, N_ANNUITY)
    nq = get(kw_dict, :n_quad, N_QUAD)
    gamma = get(kw_dict, :gamma, GAMMA)

    grid_kw = (n_wealth=nw, n_annuity=na, n_alpha=N_ALPHA,
               W_max=W_MAX, age_start=AGE_START, age_end=AGE_END,
               annuity_grid_power=A_GRID_POW)

    p_fair = ModelParams(; gamma=gamma, beta=BETA, r=R_RATE, mwr=1.0, grid_kw...)
    fair_pr = compute_payout_rate(p_fair, base_surv)
    p_fair_nom = ModelParams(; gamma=gamma, beta=BETA, r=R_RATE, mwr=1.0,
                               inflation_rate=INFLATION, grid_kw...)
    fair_pr_nom = compute_payout_rate(p_fair_nom, base_surv)
    grids = build_grids(p_fair, max(fair_pr, fair_pr_nom))

    p_full = ModelParams(; gamma=gamma, beta=BETA, r=R_RATE,
        theta=THETA_DFJ, kappa=KAPPA_DFJ,
        stochastic_health=true, n_health_states=3, n_quad=nq,
        c_floor=C_FLOOR, hazard_mult=HAZARD_MULT,
        mwr=MWR_LOADED, fixed_cost=FIXED_COST, inflation_rate=INFLATION,
        medical_enabled=true, health_mortality_corr=true,
        survival_pessimism=SURVIVAL_PESSIMISM,
        grid_kw...)

    t0 = time()
    sol = solve_lifecycle_health(p_full, grids, base_surv, ss_func)
    solve_time = time() - t0

    t1 = time()
    euler = compute_euler_residuals(sol, base_surv, ss_func)
    diag_time = time() - t1

    @printf("  %-30s  max=%.4f  mean=%.4f  med=%.4f  >1%%=%.1f%%  >5%%=%.1f%%  (solve %.0fs, diag %.0fs)\n",
            label, euler.max_residual, euler.mean_residual, euler.median_residual,
            euler.pct_above_1pct, euler.pct_above_5pct, solve_time, diag_time)
    flush(stdout)

    push!(results, (label, euler.max_residual, euler.mean_residual, euler.median_residual,
                    euler.pct_above_1pct, euler.pct_above_5pct, euler.n_interior, euler.n_total))
    return euler
end

# --- 1. Baseline (80x30, 9-node GH) ---
println("\n--- BASELINE ---"); flush(stdout)
run_euler_check("Baseline 80x30 (9-node)", base_surv, ss_func)

# --- 2. Grid convergence ---
println("\n--- GRID CONVERGENCE ---"); flush(stdout)
for (nw, na) in [(40, 15), (60, 20), (100, 40)]
    label = @sprintf("Grid %dx%d (9-node)", nw, na)
    run_euler_check(label, base_surv, ss_func; n_wealth=nw, n_annuity=na)
end

# --- 3. Quadrature sensitivity ---
println("\n--- QUADRATURE SENSITIVITY ---"); flush(stdout)
for nq in [5, 7, 11]
    label = @sprintf("80x30, %d-node GH", nq)
    run_euler_check(label, base_surv, ss_func; n_quad=nq)
end

# Save CSV
csv_path = joinpath(@__DIR__, "..", "tables", "csv", "euler_residuals.csv")
mkpath(dirname(csv_path))
open(csv_path, "w") do f
    println(f, "specification,max_residual,mean_residual,median_residual,pct_above_1pct,pct_above_5pct,n_interior,n_total")
    for (label, mx, mn, md, p1, p5, ni, nt) in results
        @printf(f, "%s,%.6f,%.6f,%.6f,%.2f,%.2f,%d,%d\n", label, mx, mn, md, p1, p5, ni, nt)
    end
end
println("\nCSV written: $csv_path"); flush(stdout)

println("\n" * "=" ^ 70); flush(stdout)
println("  EULER DIAGNOSTICS COMPLETE"); flush(stdout)
println("=" ^ 70); flush(stdout)
