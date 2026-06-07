# Verify the frac_at_kink diagnostic threads from compute_ownership_rate_health
# through both solve_and_evaluate signatures and lands in [0,1]. frac_at_kink is
# the share of owners whose optimum sits at the minimum-purchase floor; the
# gamma-oscillation kill-criterion (diagnose_gamma_oscillation.jl) reads it.
#
# Coarse grid + tiny synthetic population for speed. Run standalone:
#   julia --project=. test/test_frac_at_kink.jl

using Test
using Printf

include(joinpath(@__DIR__, "..", "src", "AnnuityPuzzle.jl"))
using .AnnuityPuzzle
include(joinpath(@__DIR__, "..", "scripts", "config.jl"))

gk = (n_wealth=40, n_annuity=12, n_alpha=51, W_max=W_MAX,
      age_start=AGE_START, age_end=AGE_END, annuity_grid_power=A_GRID_POW)
ck = (gamma=GAMMA, beta=BETA, r=R_RATE, stochastic_health=true,
      n_health_states=3, n_quad=N_QUAD, c_floor=C_FLOOR,
      hazard_mult=Float64.(HAZARD_MULT))

p_base = ModelParams(age_start=AGE_START, age_end=AGE_END)
base_surv = build_lockwood_survival(p_base)
p_fair = ModelParams(; ck..., mwr=1.0, gk...)
fair_pr = compute_payout_rate(p_fair, base_surv)
grids = build_grids(p_fair, fair_pr)
loaded_pr = MWR_LOADED * fair_pr

# Full structural model with loads active so the $10k minimum-purchase kink can bind.
p = ModelParams(; ck...,
    theta=THETA_DFJ, kappa=KAPPA_DFJ,
    mwr=MWR_LOADED, fixed_cost=FIXED_COST, min_purchase=MIN_PURCHASE,
    inflation_rate=INFLATION, medical_enabled=true, health_mortality_corr=true,
    survival_pessimism=SURVIVAL_PESSIMISM, consumption_decline=CONSUMPTION_DECLINE,
    health_utility=Float64.(HEALTH_UTILITY), chi_ltc=CHI_LTC, gk...)

# Synthetic population spanning the wealth quartile breaks: [wealth, A=0, age, health].
pop = [ 50_000.0 0.0 66.0 1.0;
       150_000.0 0.0 67.0 2.0;
       400_000.0 0.0 65.0 1.0;
       800_000.0 0.0 68.0 3.0;
     1_200_000.0 0.0 66.0 2.0]

@testset "frac_at_kink threads through solve_and_evaluate" begin
    # Uniform SS -> single-solve branch.
    res_u = solve_and_evaluate(p, grids, base_surv,
        [15_000.0, 15_000.0, 15_000.0, 15_000.0], pop, loaded_pr; verbose=false)
    @test haskey(res_u, :frac_at_kink)
    @test 0.0 <= res_u.frac_at_kink <= 1.0
    @test 0.0 <= res_u.ownership <= 1.0

    # Per-quartile SS -> quartile-aggregation branch.
    res_q = solve_and_evaluate(p, grids, base_surv,
        Float64.(SS_QUARTILE_LEVELS), pop, loaded_pr; verbose=false)
    @test haskey(res_q, :frac_at_kink)
    @test 0.0 <= res_q.frac_at_kink <= 1.0

    # Direct call exposes the same field.
    sol = solve_lifecycle_health(p, grids, base_surv, (age, pp) -> 15_000.0)
    r = compute_ownership_rate_health(sol, pop, loaded_pr; base_surv=base_surv)
    @test haskey(r, :frac_at_kink)
    @test 0.0 <= r.frac_at_kink <= 1.0

    @printf("\n  uniform : ownership=%.1f%%  frac_at_kink=%.2f\n",
        res_u.ownership * 100, res_u.frac_at_kink)
    @printf("  quartile: ownership=%.1f%%  frac_at_kink=%.2f\n",
        res_q.ownership * 100, res_q.frac_at_kink)
end

println("\nfrac_at_kink verification passed.")
