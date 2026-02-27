# Phase 4: Monte Carlo Simulation Validation
#
# Simulates lifecycle trajectories under the full model (all channels on)
# and compares aggregate moments to HRS data targets:
#   - Wealth decumulation profiles
#   - Bequest distribution
#   - Survival curve
#
# Calibration aligned with Lockwood (2012) DFJ specification:
#   gamma=2, age_end=110, c_floor=$6,180 (Lockwood sim code),
#   DFJ bequests (theta=56.96, kappa=$272,628), hazard_mult=[0.50,1.0,3.0]

using Printf
include(joinpath(@__DIR__, "..", "src", "AnnuityPuzzle.jl"))
using .AnnuityPuzzle

include(joinpath(@__DIR__, "config.jl"))

println("=" ^ 70)
println("  PHASE 4: MONTE CARLO SIMULATION VALIDATION")
println("=" ^ 70)

# ===================================================================
# Setup
# ===================================================================
ss_zero(age, p) = 0.0

p_base = ModelParams(age_start=AGE_START, age_end=AGE_END)
base_surv = build_lockwood_survival(p_base)
p_fair = ModelParams(age_start=AGE_START, age_end=AGE_END, mwr=1.0, r=R_RATE)
fair_pr = compute_payout_rate(p_fair, base_surv)

# Full model parameters (all channels on, DFJ bequests)
p = ModelParams(
    gamma=GAMMA, beta=BETA, r=R_RATE,
    theta=THETA_DFJ, kappa=KAPPA_DFJ,
    mwr=MWR_LOADED, fixed_cost=FIXED_COST, inflation_rate=INFLATION,
    medical_enabled=true, health_mortality_corr=true,
    stochastic_health=true, n_health_states=3, n_quad=N_QUAD,
    c_floor=C_FLOOR, hazard_mult=HAZARD_MULT,
    survival_pessimism=SURVIVAL_PESSIMISM,
    n_wealth=N_WEALTH, n_annuity=N_ANNUITY, n_alpha=N_ALPHA,
    W_max=W_MAX, annuity_grid_power=A_GRID_POW,
    age_start=AGE_START, age_end=AGE_END,
)

grids = build_grids(p, fair_pr)
loaded_pr = MWR_LOADED * fair_pr

@printf("\nFair payout rate: %.4f\n", fair_pr)
@printf("Loaded payout rate (MWR=%.2f): %.4f\n", MWR_LOADED, loaded_pr)
@printf("DFJ bequest theta: %.2f, kappa: \$%s\n", THETA_DFJ, string(round(Int, KAPPA_DFJ)))
@printf("gamma=%.1f, c_floor=\$%.0f, age_end=%d\n", GAMMA, C_FLOOR, AGE_END)

# ===================================================================
# Solve the full model
# ===================================================================
println("\nSolving full model (all channels on)...")
@time sol = solve_lifecycle_health(p, grids, base_surv, ss_zero)

# ===================================================================
# Optimal annuitization by wealth level
# ===================================================================
println("\n" * "=" ^ 70)
println("  OPTIMAL ANNUITIZATION BY WEALTH AND HEALTH")
println("=" ^ 70)

wealth_levels = [25_000.0, 50_000.0, 100_000.0, 250_000.0, 500_000.0]
w_labels = ["\$25K", "\$50K", "\$100K", "\$250K", "\$500K"]
health_labels = ["Good", "Fair", "Poor"]

# Pre-existing annuity income: median SS quartile level
y_preexisting = SS_QUARTILE_LEVELS[2]  # $17,000 (Q2 median)

@printf("\n  Pre-existing annuity income: \$%s/yr\n\n", string(round(Int, y_preexisting)))
@printf("  %-8s", "Health")
for l in w_labels
    @printf("  %-8s", l)
end
println()
println("  " * "-" ^ (8 + 10 * length(wealth_levels)))

for ih in 1:3
    alpha_star, _ = solve_annuitization_health(sol, loaded_pr; initial_health=ih)
    @printf("  %-8s", health_labels[ih])
    for w in wealth_levels
        iw = argmin(abs.(grids.W .- w))
        @printf("  %-8.2f", alpha_star[iw])
    end
    println()
end

# ===================================================================
# Monte Carlo Simulation: representative agents by wealth quartile
# ===================================================================
println("\n" * "=" ^ 70)
println("  SIMULATED LIFECYCLE TRAJECTORIES")
println("=" ^ 70)

n_sim = 10_000
quartile_wealth = [25_000.0, 100_000.0, 250_000.0, 500_000.0]
quartile_labels = ["Q1 (\$25K)", "Q2 (\$100K)", "Q3 (\$250K)", "Q4 (\$500K)"]
quartile_income = SS_QUARTILE_LEVELS

for (qi, (W_0, y_0, qlabel)) in enumerate(zip(quartile_wealth, quartile_income, quartile_labels))
    println(@sprintf("\n  --- Wealth quartile %s, pre-existing income \$%s ---",
        qlabel, string(round(Int, y_0))))

    # Find optimal annuitization under full model
    iw = argmin(abs.(grids.W .- W_0))
    alpha_star, _ = solve_annuitization_health(sol, loaded_pr; initial_health=2)
    alpha_opt = alpha_star[iw]

    A_purchased = alpha_opt * W_0 * loaded_pr
    A_total = y_0 + A_purchased
    W_remaining = W_0 * (1.0 - alpha_opt)
    if alpha_opt > 0.0
        W_remaining -= p.fixed_cost
    end
    W_remaining = max(W_remaining, 0.0)

    @printf("  Optimal alpha: %.2f (annuity income: \$%s/yr)\n",
        alpha_opt, string(round(Int, A_purchased)))
    @printf("  Remaining wealth: \$%s, total annuity: \$%s/yr\n",
        string(round(Int, W_remaining)), string(round(Int, A_total)))

    # Simulate
    batch = simulate_batch(
        sol, W_remaining, A_total, 2, base_surv, ss_zero, p;
        n_sim=n_sim, rng_seed=42 + qi,
    )

    # Report key ages
    report_ages = [65, 70, 75, 80, 85, 90, 95, 100, 105, 110]
    @printf("  %-6s  %-12s  %-12s  %-8s\n", "Age", "Mean Wealth", "Mean Cons.", "Alive %")
    println("  " * "-" ^ 42)
    for age in report_ages
        t = age - p.age_start + 1
        t > p.T && continue
        @printf("  %-6d  \$%-11s  \$%-11s  %6.1f%%\n",
            age,
            string(round(Int, batch.mean_wealth_by_age[t])),
            string(round(Int, batch.mean_consumption_by_age[t])),
            batch.alive_fraction[t] * 100)
    end

    # Bequest statistics
    pos_beq = filter(b -> b > 0, batch.bequests)
    @printf("\n  Bequest: mean \$%s, frac>0: %.1f%%, conditional mean \$%s\n",
        string(round(Int, batch.mean_bequest)),
        batch.frac_positive_bequest * 100,
        string(round(Int, length(pos_beq) > 0 ? sum(pos_beq) / length(pos_beq) : 0)))
end

# ===================================================================
# HRS Validation Targets
# ===================================================================
println("\n" * "=" ^ 70)
println("  HRS VALIDATION TARGETS")
println("=" ^ 70)
println("\n  Wealth decumulation rate (ages 75-85): target ~3-5%/yr")
println("  Bequest distribution: 60-75% positive, mean \$50K-\$200K by quartile")
println("  Annuity ownership rate: ~3.6% (Lockwood 2012)")

println("\n" * "=" ^ 70)
println("  SIMULATION COMPLETE")
println("=" ^ 70)
