# Quadrature and grid convergence diagnostics.
# Runs the full model at multiple quadrature node counts and grid resolutions,
# reporting both binary ownership rate and continuous metrics (mean alpha).
#
# Output: tables/csv/convergence_diagnostics.csv

using Printf, DelimitedFiles

include(joinpath(@__DIR__, "..", "src", "AnnuityPuzzle.jl"))
using .AnnuityPuzzle

println("=" ^ 70); flush(stdout)
println("  QUADRATURE & GRID CONVERGENCE DIAGNOSTICS"); flush(stdout)
println("=" ^ 70); flush(stdout)

# Setup
const THETA_DFJ = 56.96
const KAPPA_DFJ = 272_628.0

hrs_raw = readdlm(joinpath(@__DIR__, "..", "data", "processed", "lockwood_hrs_sample.csv"),
                   ',', Any; skipstart=1)
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

p_base = ModelParams(age_start=65, age_end=110)
base_surv = build_lockwood_survival(p_base)
println("Data loaded ($n_pop obs)"); flush(stdout)

results = Tuple{String,String,Float64,Float64}[]  # (category, spec, ownership, mean_alpha)

function solve_and_report(label, category, base_surv, population; kw...)
    t0 = time()

    kw_dict = Dict{Symbol,Any}(kw...)
    # Defaults
    gamma = get(kw_dict, :gamma, 2.5)
    beta = get(kw_dict, :beta, 0.97)
    r = get(kw_dict, :r, 0.02)
    nw = get(kw_dict, :n_wealth, 80)
    na = get(kw_dict, :n_annuity, 30)
    nalpha = get(kw_dict, :n_alpha, 101)
    wmax = get(kw_dict, :W_max, 3_000_000.0)
    agp = get(kw_dict, :annuity_grid_power, 3.0)
    nq = get(kw_dict, :n_quad, 5)
    mwr_loaded = get(kw_dict, :mwr_loaded, 0.82)
    inflation = get(kw_dict, :inflation_val, 0.02)
    psi = get(kw_dict, :survival_pessimism, 0.981)
    hm = get(kw_dict, :hazard_mult, [0.50, 1.0, 3.0])
    min_wealth = get(kw_dict, :min_wealth, 5000.0)

    grid_kw = (n_wealth=nw, n_annuity=na, n_alpha=nalpha,
               W_max=wmax, age_start=65, age_end=110,
               annuity_grid_power=agp)

    # Compute payout rates
    p_fair_nom = ModelParams(; gamma=gamma, beta=beta, r=r, mwr=1.0,
                               inflation_rate=inflation, grid_kw...)
    fair_pr_nom = compute_payout_rate(p_fair_nom, base_surv)
    loaded_pr_nom = mwr_loaded * fair_pr_nom

    p_fair = ModelParams(; gamma=gamma, beta=beta, r=r, mwr=1.0, grid_kw...)
    fair_pr = compute_payout_rate(p_fair, base_surv)
    grids = build_grids(p_fair, max(fair_pr, fair_pr_nom))

    # Full model params
    p_full = ModelParams(; gamma=gamma, beta=beta, r=r,
        theta=THETA_DFJ, kappa=KAPPA_DFJ,
        stochastic_health=true, n_health_states=3, n_quad=nq,
        c_floor=6180.0, hazard_mult=hm,
        mwr=mwr_loaded, fixed_cost=1000.0, inflation_rate=inflation,
        medical_enabled=true, health_mortality_corr=true,
        survival_pessimism=psi,
        grid_kw...)

    # Mean SS
    ss_mean_val = sum(SS_QUARTILE_LEVELS) / length(SS_QUARTILE_LEVELS)
    ss_func(age, p) = ss_mean_val

    # Filter population
    pop_filt = copy(population)
    mask = pop_filt[:, 1] .>= min_wealth
    pop_filt = pop_filt[mask, :]
    if size(pop_filt, 2) < 4
        pop_filt = hcat(pop_filt, fill(2.0, size(pop_filt, 1)))
    end

    sol = solve_lifecycle_health(p_full, grids, base_surv, ss_func)
    result = compute_ownership_rate_health(sol, pop_filt, loaded_pr_nom;
                                           base_surv=base_surv)

    own = result.ownership_rate
    mean_a = result.mean_alpha
    dt = time() - t0
    @printf("  %-45s  own=%6.2f%%  mean_α=%.5f  (%5.1fs)\n", label, own * 100, mean_a, dt)
    flush(stdout)
    push!(results, (category, label, own, mean_a))
    return (own, mean_a)
end

# --- 1. Quadrature convergence (fixed grid 80x30) ---
println("\n--- QUADRATURE CONVERGENCE (80x30 grid) ---"); flush(stdout)
for nq in [3, 5, 7, 9, 11, 13, 15]
    label = @sprintf("n_quad=%d", nq)
    solve_and_report(label, "Quadrature", base_surv, population; n_quad=nq)
end

# --- 2. Grid convergence (fixed 5-node GH) ---
println("\n--- GRID CONVERGENCE (5-node GH) ---"); flush(stdout)
for (nw, na) in [(40, 15), (60, 20), (80, 30), (100, 40), (120, 50)]
    label = @sprintf("Grid %dx%d (5-node)", nw, na)
    solve_and_report(label, "Grid (5-node)", base_surv, population; n_wealth=nw, n_annuity=na, n_quad=5)
end

# --- 3. Grid convergence with 9-node GH ---
println("\n--- GRID CONVERGENCE (9-node GH) ---"); flush(stdout)
for (nw, na) in [(60, 20), (80, 30), (100, 40), (120, 50)]
    label = @sprintf("Grid %dx%d (9-node)", nw, na)
    solve_and_report(label, "Grid (9-node)", base_surv, population; n_wealth=nw, n_annuity=na, n_quad=9)
end

# --- 4. Combined: finest grid + highest quadrature ---
println("\n--- REFERENCE (120x50, 11-node GH) ---"); flush(stdout)
solve_and_report("Grid 120x50 (11-node)", "Reference", base_surv, population;
                 n_wealth=120, n_annuity=50, n_quad=11)

println("\n" * "=" ^ 70); flush(stdout)
println("  CONVERGENCE DIAGNOSTICS COMPLETE"); flush(stdout)
println("=" ^ 70); flush(stdout)

# Save CSV
csv_path = joinpath(@__DIR__, "..", "tables", "csv", "convergence_diagnostics.csv")
mkpath(dirname(csv_path))
open(csv_path, "w") do f
    println(f, "category,specification,ownership_pct,mean_alpha")
    for (cat, spec, own, ma) in results
        @printf(f, "%s,%s,%.2f,%.6f\n", cat, spec, own * 100, ma)
    end
end
println("CSV written: $csv_path"); flush(stdout)
