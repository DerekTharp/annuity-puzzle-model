# Forced-age-65 ranking check (referee response).
#
# The headline evaluates each HRS respondent's annuitization decision at their
# observed age (65-69). This script recomputes the nine-channel structural
# Shapley with every respondent forced to age 65, to confirm that the channel
# RANKING is unchanged even though the predicted level falls (~7.9% -> ~6.0%).
# Grid 60x20x101; pricing follows the production four-branch convention.
# Output: tables/csv/forced_age65_shapley.csv
#
# Usage: julia --project=. -p 8 scripts/check_forced_age65_shapley.jl

using Distributed, DelimitedFiles, Printf
if nworkers() > 1
    @everywhere include(joinpath(@__DIR__, "..", "src", "AnnuityPuzzle.jl"))
    @everywhere using .AnnuityPuzzle
else
    include(joinpath(@__DIR__, "..", "src", "AnnuityPuzzle.jl"))
    using .AnnuityPuzzle
end
include(joinpath(@__DIR__, "config.jl"))

# 60x20x101: the coarsest grid the deposited convergence table places within
# ~1pp of production; alpha grid at the production resolution.
const NW = 60; const NA = 20; const NAL = 101

hrs_raw = readdlm(HRS_PATH, ',', Any; skipstart=1)
has_health = assert_hrs_schema(hrs_raw, HRS_PATH)
n_pop = size(hrs_raw, 1)
pop = zeros(n_pop, 4)
pop[:, 1] = Float64.(hrs_raw[:, 1])
pop[:, 2] .= 0.0
pop[:, 3] = Float64.(hrs_raw[:, 3])
pop[:, 4] = has_health ? Float64.(hrs_raw[:, 4]) : fill(2.0, n_pop)
pop = pop[pop[:, 1] .>= MIN_WEALTH, :]
pop65 = copy(pop); pop65[:, 3] .= AGE_START   # force everyone to age 65

p_base = ModelParams(age_start=AGE_START, age_end=AGE_END)
base_surv = build_lockwood_survival(p_base)

gkw = (n_wealth=NW, n_annuity=NA, n_alpha=NAL, W_max=W_MAX,
       age_start=AGE_START, age_end=AGE_END, annuity_grid_power=A_GRID_POW)
p_fair = ModelParams(; gamma=GAMMA, beta=BETA, r=R_RATE, mwr=1.0, gkw...)
fair_pr = compute_payout_rate(p_fair, base_surv)
p_fair_nom = ModelParams(; gamma=GAMMA, beta=BETA, r=R_RATE, mwr=1.0,
                         inflation_rate=INFLATION, gkw...)
fair_pr_nom = compute_payout_rate(p_fair_nom, base_surv)
grids = build_grids(ModelParams(; gamma=GAMMA, beta=BETA, r=R_RATE,
    stochastic_health=true, n_health_states=3, n_quad=N_QUAD, c_floor=C_FLOOR,
    hazard_mult=Float64.(HAZARD_MULT), mwr=1.0, gkw...), max(fair_pr, fair_pr_nom))

@everywhere function solve_one(mask, gkw, GAMMA, BETA, R_RATE, N_QUAD, C_FLOOR,
        HAZARD_MULT, THETA_DFJ, KAPPA_DFJ, MWR_LOADED, FIXED_COST, MIN_PURCHASE,
        INFLATION, SURVIVAL_PESSIMISM, SS_QUARTILE_LEVELS, CONSUMPTION_DECLINE,
        HEALTH_UTILITY, CHI_LTC, LAMBDA_W, PSI_PURCHASE, PSI_PURCHASE_C_REF,
        grids, base_surv, fair_pr, fair_pr_nom, pop65)
    cfg = build_subset_config(bitmask_to_channels(mask);
        theta_dfj=THETA_DFJ, kappa_dfj=KAPPA_DFJ, mwr_loaded=MWR_LOADED,
        fixed_cost=FIXED_COST, min_purchase=MIN_PURCHASE, inflation_val=INFLATION,
        survival_pessimism=SURVIVAL_PESSIMISM,
        ss_quartile_levels=Float64.(SS_QUARTILE_LEVELS),
        consumption_decline=CONSUMPTION_DECLINE,
        health_utility=Float64.(HEALTH_UTILITY), chi_ltc_val=CHI_LTC,
        lambda_w_val=LAMBDA_W, psi_purchase_val=PSI_PURCHASE,
        psi_purchase_c_ref_val=PSI_PURCHASE_C_REF)
    has_loads = cfg.mwr < 1.0; has_infl = cfg.inflation_rate > 0
    pr = has_loads && has_infl ? cfg.mwr * fair_pr_nom :
         has_loads              ? cfg.mwr * fair_pr :
         has_infl               ? fair_pr_nom : fair_pr
    p = ModelParams(; gamma=GAMMA, beta=BETA, r=R_RATE, stochastic_health=true,
        n_health_states=3, n_quad=N_QUAD, c_floor=C_FLOOR,
        hazard_mult=Float64.(HAZARD_MULT), theta=cfg.theta, kappa=cfg.kappa,
        mwr=cfg.mwr, fixed_cost=cfg.fixed_cost, min_purchase=cfg.min_purchase,
        inflation_rate=cfg.inflation_rate, medical_enabled=cfg.medical_enabled,
        health_mortality_corr=cfg.health_mortality_corr,
        survival_pessimism=cfg.survival_pessimism,
        consumption_decline=cfg.consumption_decline,
        health_utility=cfg.health_utility, chi_ltc=cfg.chi_ltc,
        lambda_w=cfg.lambda_w, psi_purchase=cfg.psi_purchase,
        psi_purchase_c_ref=cfg.psi_purchase_c_ref, gkw...)
    return mask => solve_and_evaluate(p, grids, base_surv, cfg.ss_levels, pop65, pr;
        verbose=false).ownership
end

println("Enumerating 512 nine-channel subsets at forced age 65 (coarse grid)...")
flush(stdout)
t0 = time()
pairs = pmap(m -> solve_one(m, gkw, GAMMA, BETA, R_RATE, N_QUAD, C_FLOOR,
        HAZARD_MULT, THETA_DFJ, KAPPA_DFJ, MWR_LOADED, FIXED_COST, MIN_PURCHASE,
        INFLATION, SURVIVAL_PESSIMISM, SS_QUARTILE_LEVELS, CONSUMPTION_DECLINE,
        HEALTH_UTILITY, CHI_LTC, LAMBDA_W, PSI_PURCHASE, PSI_PURCHASE_C_REF,
        grids, base_surv, fair_pr, fair_pr_nom, pop65), 0:511)
lookup = Dict{Int,Float64}(pairs)
shap = exact_shapley(9, lookup)
names = ["SS", "Bequests", "Med+R-S", "Pessimism", "Age needs", "State util",
         "Loads", "Inflation", "LTC"]
order = sortperm(shap; rev=true)
@printf("\nForced-age-65 nine-channel Shapley (full model own=%.2f%%, %.0fs):\n",
    lookup[511] * 100, time() - t0)
for (rank, i) in enumerate(order)
    @printf("  %2d. %-12s %+7.2f pp\n", rank, names[i], shap[i] * 100)
end

csv = joinpath(@__DIR__, "..", "tables", "csv", "forced_age65_shapley.csv")
open(csv, "w") do io
    println(io, "channel,shapley_value_pp,abs_rank,full_own_forced_pct")
    rk = zeros(Int, 9); for (k, i) in enumerate(sortperm(abs.(shap); rev=true)); rk[i] = k; end
    for i in 1:9
        @printf(io, "%s,%.4f,%d,%.4f\n", names[i], shap[i] * 100, rk[i], lookup[511] * 100)
    end
end
println("CSV: $csv")
