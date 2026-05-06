# Compute ownership under age-varying HRS hazard multipliers.
# Uses solve_lifecycle_health + compute_ownership_rate_health directly.

using Printf, DelimitedFiles

include(joinpath(@__DIR__, "..", "src", "AnnuityPuzzle.jl"))
using .AnnuityPuzzle

include(joinpath(@__DIR__, "config.jl"))

println("Loading data...")
flush(stdout)

p_base = ModelParams(age_start=AGE_START, age_end=AGE_END)
base_surv = build_lockwood_survival(p_base)

hrs_raw = readdlm(HRS_PATH, ',', Any; skipstart=1)
assert_hrs_schema(hrs_raw, HRS_PATH)
n_pop = size(hrs_raw, 1)
population = zeros(n_pop, 4)
population[:, 1] = Float64.(hrs_raw[:, 1])
population[:, 2] .= 0.0
population[:, 3] = Float64.(hrs_raw[:, 3])
population[:, 4] = size(hrs_raw, 2) >= 4 ? Float64.(hrs_raw[:, 4]) : fill(2.0, n_pop)

# HRS empirical hazard multipliers by age band
hm_by_age = [0.49 1.0 3.29;   # 65-74
             0.60 1.0 2.77;   # 75-84
             0.74 1.0 1.82]   # 85+
hm_midpoints = [70.0, 80.0, 90.0]

println("Building model with age-varying hazard multipliers...")
flush(stdout)
t0 = time()

# Full model with all channels + age-varying hazard
p_model = ModelParams(
    gamma=GAMMA, beta=BETA, r=R_RATE, c_floor=C_FLOOR,
    mwr=MWR_LOADED, fixed_cost=FIXED_COST, inflation_rate=INFLATION,
    theta=THETA_DFJ, kappa=KAPPA_DFJ,
    stochastic_health=true, n_health_states=3, n_quad=N_QUAD,
    medical_enabled=true, health_mortality_corr=true,
    hazard_mult_by_age=hm_by_age, hazard_mult_age_midpoints=hm_midpoints,
    survival_pessimism=SURVIVAL_PESSIMISM,
    n_wealth=N_WEALTH, n_annuity=N_ANNUITY, n_alpha=N_ALPHA,
    W_max=W_MAX, age_start=AGE_START, age_end=AGE_END,
    annuity_grid_power=A_GRID_POW,
)

# Payout rate
fair_pr_nom = compute_payout_rate(
    ModelParams(gamma=GAMMA, beta=BETA, r=R_RATE, mwr=1.0,
                inflation_rate=INFLATION,
                n_wealth=N_WEALTH, n_annuity=N_ANNUITY, n_alpha=N_ALPHA,
                W_max=W_MAX, age_start=AGE_START, age_end=AGE_END,
                annuity_grid_power=A_GRID_POW),
    base_surv)
loaded_pr = MWR_LOADED * fair_pr_nom
grids = build_grids(p_model, fair_pr_nom)

# SS function
function ss_func(age, p)
    # Use the same quartile-based SS as the decomposition
    return 0.0  # Will be handled via population income column
end

println("Solving lifecycle model...")
flush(stdout)
sol = solve_lifecycle_health(p_model, grids, base_surv, ss_func)

println("Computing ownership rate...")
flush(stdout)

# Set population income to SS levels by wealth quartile
pop_with_ss = copy(population)
wealth_col = pop_with_ss[:, 1]
sorted_w = sort(wealth_col)
q25 = sorted_w[max(1, div(length(sorted_w), 4))]
q50 = sorted_w[max(1, div(length(sorted_w), 2))]
q75 = sorted_w[max(1, div(3 * length(sorted_w), 4))]

ss_levels = [14_000.0, 17_000.0, 20_000.0, 25_000.0]
for i in 1:size(pop_with_ss, 1)
    w = pop_with_ss[i, 1]
    if w <= q25
        pop_with_ss[i, 2] = ss_levels[1]
    elseif w <= q50
        pop_with_ss[i, 2] = ss_levels[2]
    elseif w <= q75
        pop_with_ss[i, 2] = ss_levels[3]
    else
        pop_with_ss[i, 2] = ss_levels[4]
    end
end

result = compute_ownership_rate_health(sol, pop_with_ss, loaded_pr)
elapsed = time() - t0

@printf("\n  Age-varying HRS (3 bands): %.1f%% ownership (%.0fs)\n", result.ownership_rate * 100, elapsed)
@printf("  Compare baseline [0.50, 1.0, 3.0]: 18.3%%\n")
flush(stdout)

# Append to robustness CSV
csv_path = joinpath(@__DIR__, "..", "tables", "csv", "robustness_full.csv")
if isfile(csv_path)
    open(csv_path, "a") do io
        @printf(io, "Hazard mult,Age-varying HRS (3 bands),%.1f%%\n", result.ownership_rate * 100)
    end
    println("  Appended to $csv_path")
end
println("Done.")
flush(stdout)
