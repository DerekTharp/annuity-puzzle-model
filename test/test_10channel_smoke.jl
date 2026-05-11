# Smoke test: solve the full Model 1 (11-channel) model once on a coarse
# grid and confirm the solver runs end-to-end with all rational, preference,
# structural, and behavioral channels active.

using Test
using DelimitedFiles

include(joinpath(@__DIR__, "..", "src", "AnnuityPuzzle.jl"))
using .AnnuityPuzzle
include(joinpath(@__DIR__, "..", "scripts", "config.jl"))

@testset "Full-model build smoke test" begin
    # Coarse grid for speed
    nw, na, nalpha = 30, 12, 51

    p_base = ModelParams(age_start=AGE_START, age_end=AGE_END)
    base_surv = build_lockwood_survival(p_base)

    grid_kw = (n_wealth=nw, n_annuity=na, n_alpha=nalpha,
               W_max=W_MAX, age_start=AGE_START, age_end=AGE_END,
               annuity_grid_power=A_GRID_POW)

    p_fair_nom = ModelParams(; gamma=GAMMA, beta=BETA, r=R_RATE, mwr=1.0,
                             inflation_rate=INFLATION, grid_kw...)
    fair_pr_nom = compute_payout_rate(p_fair_nom, base_surv)
    loaded_pr_nom = MWR_LOADED * fair_pr_nom

    common_kw = (gamma=GAMMA, beta=BETA, r=R_RATE,
                 stochastic_health=true, n_health_states=3, n_quad=N_QUAD,
                 c_floor=C_FLOOR, hazard_mult=Float64.(HAZARD_MULT))

    p_grid = ModelParams(; common_kw..., mwr=1.0, grid_kw...)
    grids = build_grids(p_grid, fair_pr_nom)

    # Full Model 1 (rational + preferences + structural + behavioral).
    p_model = ModelParams(; common_kw...,
        theta=THETA_DFJ, kappa=KAPPA_DFJ,
        mwr=MWR_LOADED, fixed_cost=FIXED_COST,
        inflation_rate=INFLATION,
        medical_enabled=true, health_mortality_corr=true,
        survival_pessimism=SURVIVAL_PESSIMISM,
        consumption_decline=CONSUMPTION_DECLINE,
        health_utility=Float64.(HEALTH_UTILITY),
        chi_ltc=CHI_LTC,
        lambda_w=LAMBDA_W,
        psi_purchase=PSI_PURCHASE,
        psi_purchase_c_ref=PSI_PURCHASE_C_REF,
        grid_kw...)

    # Synthetic small population
    pop = [50_000.0  0.0  65  2;
           150_000.0 0.0  65  2;
           500_000.0 0.0  65  1;]

    res = solve_and_evaluate(p_model, grids, base_surv,
        Float64.(SS_QUARTILE_LEVELS), pop, loaded_pr_nom;
        step_name="", verbose=false)

    # Sanity bounds
    @test 0.0 <= res.ownership <= 1.0
    @test 0.0 <= res.mean_alpha <= 1.0
    @test isfinite(res.mean_alpha)
    println("  Smoke test: ownership=$(round(res.ownership * 100, digits=2))%, mean_alpha=$(round(res.mean_alpha, digits=4))")
    println("  Model 1 full 11-channel solve produced cleanly.")
end
