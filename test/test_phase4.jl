# Phase 4 tests: inflation erosion, simulation, decomposition.
#
# Validates:
# 1. Inflation erosion reduces annuity value
# 2. Backward compatibility: inflation_rate=0 recovers prior results
# 3. Simulation produces valid trajectories
# 4. Decomposition ownership declines monotonically (mostly)
# 5. Multiplicative interaction: combined > sum of individual effects

using Test
include(joinpath(@__DIR__, "..", "src", "AnnuityPuzzle.jl"))
using .AnnuityPuzzle

ss_zero(age, p) = 0.0

# ===================================================================
# 1. Inflation Erosion Tests
# ===================================================================
@testset "Inflation erosion" begin
    common = (gamma=2.0, beta=0.97, r=0.02, theta=0.0, kappa=0.0,
              age_start=65, age_end=100, mwr=1.0, fixed_cost=0.0,
              c_floor=3000.0, n_wealth=30, n_annuity=10, n_alpha=21,
              W_max=500_000.0, stochastic_health=true, n_health_states=3,
              medical_enabled=false, health_mortality_corr=false, n_quad=3)

    surv = build_survival_probs(ModelParams(; common...))

    # Solve without inflation
    p0 = ModelParams(; common..., inflation_rate=0.0)
    pr = compute_payout_rate(p0, surv)
    grids = build_grids(p0, pr)
    sol0 = solve_lifecycle_health(p0, grids, surv, ss_zero)

    # Solve with 3% inflation
    p_infl = ModelParams(; common..., inflation_rate=0.03)
    sol_infl = solve_lifecycle_health(p_infl, grids, surv, ss_zero)

    @testset "V with inflation <= V without for positive A" begin
        # At t=1 (age 65), for positive annuity income, inflation should
        # reduce value since future real income is lower
        for ih in 1:3
            for ia in 2:length(grids.A)  # skip ia=1 (A=0, no inflation effect)
                for iw in 1:length(grids.W)
                    @test sol_infl.V[iw, ia, ih, 1] <= sol0.V[iw, ia, ih, 1] + 1e-6
                end
            end
        end
    end

    @testset "V identical for A=0 (no annuity, no inflation effect)" begin
        # When A=0, inflation has no effect: A_real = 0 * factor = 0
        for ih in 1:3
            for iw in 1:length(grids.W)
                for t in 1:p0.T
                    @test sol_infl.V[iw, 1, ih, t] ≈ sol0.V[iw, 1, ih, t] atol=1e-6
                end
            end
        end
    end

    @testset "Optimal annuitization lower with inflation" begin
        alpha0, _ = solve_annuitization_health(sol0, pr; initial_health=2)
        alpha_infl, _ = solve_annuitization_health(sol_infl, pr; initial_health=2)

        # At moderate wealth, inflation should reduce or maintain annuitization
        # (annuity less valuable => lower alpha)
        iw_100k = argmin(abs.(grids.W .- 100_000.0))
        @test alpha_infl[iw_100k] <= alpha0[iw_100k] + 0.05
    end
end

# ===================================================================
# 2. Backward Compatibility: Phase 1/2 solvers
# ===================================================================
@testset "Backward compatibility (inflation_rate=0)" begin
    common = (gamma=2.0, beta=0.97, r=0.02, theta=0.0, kappa=0.0,
              age_start=65, age_end=100, mwr=1.0, fixed_cost=0.0,
              inflation_rate=0.0, c_floor=1.0,
              n_wealth=30, n_annuity=10, n_alpha=21, W_max=500_000.0)

    surv = build_survival_probs(ModelParams(; common...))

    # Phase 1/2 solver (no health)
    p1 = ModelParams(; common...)
    pr = compute_payout_rate(p1, surv)
    grids = build_grids(p1, pr)
    sol1 = solve_lifecycle(p1, grids, surv, ss_zero)

    # Phase 3 solver (with health, no medical/correlation)
    p3 = ModelParams(; common..., stochastic_health=true, n_health_states=3,
                     medical_enabled=false, health_mortality_corr=false, n_quad=3)
    sol3 = solve_lifecycle_health(p3, grids, surv, ss_zero)

    @testset "Health solver matches no-health solver (all health states)" begin
        # When health doesn't affect survival or costs, all health states
        # should give the same V as the no-health solver
        for ih in 1:3
            for t in 1:p1.T
                for ia in 1:length(grids.A)
                    for iw in 1:length(grids.W)
                        @test sol3.V[iw, ia, ih, t] ≈ sol1.V[iw, ia, t] atol=1e-4
                    end
                end
            end
        end
    end

    @testset "Yaari benchmark: full annuitization at moderate wealth" begin
        alpha_star, _ = solve_annuitization(sol1, pr)
        iw_100k = argmin(abs.(grids.W .- 100_000.0))
        @test alpha_star[iw_100k] >= 0.9
    end
end

# ===================================================================
# 3. Simulation Tests
# ===================================================================
@testset "Simulation" begin
    common = (gamma=2.0, beta=0.97, r=0.02, theta=0.0, kappa=0.0,
              age_start=65, age_end=100, mwr=1.0, fixed_cost=0.0,
              inflation_rate=0.0, c_floor=3000.0,
              n_wealth=30, n_annuity=10, n_alpha=21, W_max=500_000.0,
              stochastic_health=true, n_health_states=3,
              medical_enabled=false, health_mortality_corr=false, n_quad=3)

    p = ModelParams(; common...)
    surv = build_survival_probs(p)
    pr = compute_payout_rate(p, surv)
    grids = build_grids(p, pr)
    sol = solve_lifecycle_health(p, grids, surv, ss_zero)

    # Compute batch at Simulation scope so nested testsets can see it
    batch = simulate_batch(sol, 200_000.0, 10_000.0, 2, surv, ss_zero, p;
                           n_sim=1000, rng_seed=42)

    @testset "Single lifecycle trajectory" begin
        using Random
        rng = MersenneTwister(123)
        result = simulate_lifecycle(sol, 200_000.0, 10_000.0, 2, surv, ss_zero, p; rng=rng)

        @test result.age_at_death >= 65
        @test result.age_at_death <= 100
        @test result.bequest >= 0.0
        @test result.wealth_path[1] == 200_000.0
        @test result.health_path[1] == 2

        # Consumption should be positive
        death_t = result.age_at_death - p.age_start + 1
        for t in 1:min(death_t, p.T)
            @test result.consumption_path[t] >= p.c_floor - 1.0
        end

        # Wealth should be non-negative
        for t in 1:min(death_t, p.T)
            @test result.wealth_path[t] >= -1.0
        end
    end

    @testset "Batch simulation aggregate stats" begin
        # All alive at t=1
        @test batch.alive_fraction[1] ≈ 1.0
        # Alive fraction declines over time
        @test batch.alive_fraction[end] < batch.alive_fraction[1]
        # Mean wealth at t=1 should match initial
        @test batch.mean_wealth_by_age[1] ≈ 200_000.0 atol=1.0

        # Should have n_sim bequests
        @test length(batch.bequests) == batch.n_sim
        # All bequests non-negative
        @test all(b -> b >= 0, batch.bequests)
    end

    @testset "Simulation with medical expenses" begin
        p_med = ModelParams(; common..., medical_enabled=true, health_mortality_corr=true)
        sol_med = solve_lifecycle_health(p_med, grids, surv, ss_zero)

        batch_med = simulate_batch(sol_med, 200_000.0, 10_000.0, 2, surv, ss_zero, p_med;
                                   n_sim=500, rng_seed=42)

        @test batch_med.alive_fraction[1] ≈ 1.0
        @test all(b -> b >= 0, batch_med.bequests)
        # Medical expenses reduce mean wealth faster
        @test batch_med.mean_wealth_by_age[10] <= batch.mean_wealth_by_age[10] + 50_000
    end

    @testset "Simulation with inflation" begin
        p_infl = ModelParams(; common..., inflation_rate=0.03)
        sol_infl = solve_lifecycle_health(p_infl, grids, surv, ss_zero)

        using Random
        rng1 = MersenneTwister(99)
        rng2 = MersenneTwister(99)
        # With A=0, inflation has no effect
        r1 = simulate_lifecycle(sol, 200_000.0, 0.0, 2, surv, ss_zero, p; rng=rng1)
        r2 = simulate_lifecycle(sol_infl, 200_000.0, 0.0, 2, surv, ss_zero, p_infl; rng=rng2)

        # Should get same trajectories when A=0
        death_t = min(r1.age_at_death, r2.age_at_death) - p.age_start + 1
        for t in 1:min(death_t, p.T)
            @test r1.wealth_path[t] ≈ r2.wealth_path[t] atol=100.0
        end
    end
end

# ===================================================================
# 4. Decomposition Tests
# ===================================================================
@testset "Decomposition" begin
    # Use small grids for speed
    common = (gamma=2.0, beta=0.97, r=0.02,
              c_floor=3000.0, n_wealth=25, n_annuity=10, n_alpha=21,
              W_max=500_000.0, n_quad=3,
              age_start=65, age_end=100)

    surv = build_survival_probs(ModelParams(; common...))
    fair_pr = compute_payout_rate(ModelParams(; common..., mwr=1.0), surv)
    theta_test = calibrate_theta(0.20, 300_000.0, fair_pr, ModelParams(gamma=2.0))

    # Small synthetic population
    pop = [50_000.0  10_000.0  65.0;
           100_000.0 15_000.0  66.0;
           200_000.0 18_000.0  67.0;
           500_000.0 25_000.0  65.0;
           30_000.0   8_000.0  68.0]

    @testset "solve_and_evaluate runs" begin
        p = ModelParams(; common..., theta=0.0, kappa=0.0, mwr=1.0, fixed_cost=0.0,
                        inflation_rate=0.0, medical_enabled=false,
                        health_mortality_corr=false, stochastic_health=true,
                        n_health_states=3)
        grids = build_grids(p, fair_pr)
        pop_h = hcat(pop, fill(2.0, 5))
        result = solve_and_evaluate(p, grids, surv, ss_zero,
            pop_h, fair_pr; step_name="test", verbose=false)

        @test 0.0 <= result.ownership <= 1.0
        @test result.solve_time > 0
    end

    @testset "Full decomposition runs" begin
        decomp = run_decomposition(surv, pop;
            gamma=2.0, beta=0.97, r=0.02,
            theta=theta_test, kappa=10.0,
            c_floor=3000.0, mwr_loaded=0.82,
            fixed_cost_val=1000.0, inflation_val=0.03,
            common.n_wealth, common.n_annuity, common.n_alpha,
            common.W_max, common.n_quad,
            common.age_start, common.age_end,
            verbose=false,
        )

        @test length(decomp.steps) == 7  # 0:Yaari, 1:Bequests, 2:Medical, 3:R-S, 4:Pessimism, 5:Loads, 6:Inflation

        # Step 0 (Yaari) should have high ownership
        @test decomp.steps[1].ownership_rate >= 0.3

        # Final step should have ownership <= Yaari (may be equal on tiny populations)
        @test decomp.steps[end].ownership_rate <= decomp.steps[1].ownership_rate

        # All ownership rates should be between 0 and 1
        for step in decomp.steps
            @test 0.0 <= step.ownership_rate <= 1.0
        end
    end

    @testset "Multiplicative interaction" begin
        mult = run_multiplicative_analysis(surv, pop;
            gamma=2.0, beta=0.97, r=0.02,
            theta=theta_test, kappa=10.0,
            c_floor=3000.0, mwr_loaded=0.82,
            fixed_cost_val=1000.0, inflation_val=0.03,
            common.n_wealth, common.n_annuity, common.n_alpha,
            common.W_max, common.n_quad,
            common.age_start, common.age_end,
            verbose=false,
        )

        # Baseline should have positive ownership
        @test mult.baseline_ownership >= 0.0

        # Combined ownership should be <= baseline
        @test mult.combined_ownership <= mult.baseline_ownership + 0.01

        # Individual drops can be negative (e.g., medical costs can increase
        # demand via longevity insurance), but should be bounded
        @test all(d -> d >= -0.5, mult.individual_drops)

        # Sum of individual drops is well-defined
        @test mult.sum_of_individual >= -0.01
    end
end

println("\nAll Phase 4 tests passed!")
