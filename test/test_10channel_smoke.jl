# Smoke test: solve the full 10-channel model once on a coarse grid and confirm
# the solver runs end-to-end with psi_purchase active. NOT a regression test —
# just verifies the build hasn't regressed when extending from 9 to 10 channels.

using Test
using DelimitedFiles

include(joinpath(@__DIR__, "..", "src", "AnnuityPuzzle.jl"))
using .AnnuityPuzzle
include(joinpath(@__DIR__, "..", "scripts", "config.jl"))

@testset "10-channel build smoke test" begin
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

    # Full 10-channel model
    p_model = ModelParams(; common_kw...,
        theta=THETA_DFJ, kappa=KAPPA_DFJ,
        mwr=MWR_LOADED, fixed_cost=FIXED_COST,
        inflation_rate=INFLATION,
        medical_enabled=true, health_mortality_corr=true,
        survival_pessimism=SURVIVAL_PESSIMISM,
        consumption_decline=CONSUMPTION_DECLINE,
        health_utility=Float64.(HEALTH_UTILITY),
        lambda_w=LAMBDA_W,
        psi_purchase=PSI_PURCHASE,
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

    # Sanity check vs psi_purchase=0 (rational + SDU benchmark; Force A still on)
    p_rational = ModelParams(; common_kw...,
        theta=THETA_DFJ, kappa=KAPPA_DFJ,
        mwr=MWR_LOADED, fixed_cost=FIXED_COST,
        inflation_rate=INFLATION,
        medical_enabled=true, health_mortality_corr=true,
        survival_pessimism=SURVIVAL_PESSIMISM,
        consumption_decline=CONSUMPTION_DECLINE,
        health_utility=Float64.(HEALTH_UTILITY),
        lambda_w=LAMBDA_W,
        psi_purchase=0.0,
        grid_kw...)

    res_rational = solve_and_evaluate(p_rational, grids, base_surv,
        Float64.(SS_QUARTILE_LEVELS), pop, loaded_pr_nom;
        step_name="", verbose=false)

    # Behavioral friction can only reduce or leave unchanged the annuitization rate
    @test res.ownership <= res_rational.ownership + 1e-9
    println("  psi=$(PSI_PURCHASE): ownership=$(round(res.ownership * 100, digits=2))%")
    println("  psi=0.0 (rational): ownership=$(round(res_rational.ownership * 100, digits=2))%")
end
