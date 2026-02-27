using Test

include(joinpath(@__DIR__, "..", "src", "AnnuityPuzzle.jl"))
using .AnnuityPuzzle

# Small grids for fast testing
const TEST_NW = 15
const TEST_NA = 8
const TEST_NALPHA = 11
const TEST_NQUAD = 3

@testset "Phase 5: Welfare Analysis (CEV)" begin

    # ===================================================================
    # Test Group 1: CEV Formula Verification
    # ===================================================================
    @testset "CEV formula direct verification" begin
        # For CRRA with gamma > 1, V < 0.
        # If V_with/V_without = R, CEV = R^(1/(1-gamma)) - 1

        # gamma = 3, V_with = -0.05, V_without = -0.06
        # R = -0.05 / -0.06 = 5/6
        # CEV = (5/6)^(1/(1-3)) - 1 = (5/6)^(-0.5) - 1
        gamma = 3.0
        V_with = -0.05
        V_without = -0.06
        R = V_with / V_without
        expected = R^(1.0 / (1.0 - gamma)) - 1.0
        @test expected > 0.0  # V_with > V_without => positive CEV

        # gamma = 2, V_with = -1.0, V_without = -1.2
        gamma2 = 2.0
        V_with2 = -1.0
        V_without2 = -1.2
        R2 = V_with2 / V_without2
        expected2 = R2^(1.0 / (1.0 - gamma2)) - 1.0
        @test expected2 > 0.0

        # If V_with = V_without, CEV = 0
        R3 = 1.0
        expected3 = R3^(1.0 / (1.0 - gamma)) - 1.0
        @test expected3 ≈ 0.0 atol=1e-12
    end

    # ===================================================================
    # Test Group 2: Limiting Cases
    # ===================================================================
    @testset "CEV limiting cases" begin
        p_base = ModelParams(age_start=65, age_end=110)
        base_surv = build_lockwood_survival(p_base)
        ss_zero(age, p) = 0.0

        # --- Yaari benchmark: fair pricing, no bequests, no medical, no inflation ---
        # Annuities should have high value => large positive CEV
        p_yaari = ModelParams(
            gamma=2.5, beta=0.97, r=0.02,
            theta=0.0, kappa=0.0,
            mwr=1.0, fixed_cost=0.0, inflation_rate=0.0,
            medical_enabled=false, health_mortality_corr=false,
            stochastic_health=true, n_health_states=3, n_quad=TEST_NQUAD,
            c_floor=6_180.0, hazard_mult=[0.50, 1.0, 3.0],
            n_wealth=TEST_NW, n_annuity=TEST_NA, n_alpha=TEST_NALPHA,
            W_max=1_100_000.0, age_start=65, age_end=110,
            annuity_grid_power=3.0,
        )
        fair_pr = compute_payout_rate(p_yaari, base_surv)
        grids = build_grids(p_yaari, fair_pr)
        sol_yaari = solve_lifecycle_health(p_yaari, grids, base_surv, ss_zero)

        # Moderate wealth, good health: CEV should be positive
        cev_yaari = compute_cev(sol_yaari, 200_000.0, 0.0, 1, fair_pr)
        @test cev_yaari.cev > 0.0
        @test cev_yaari.alpha_star > 0.0

        # Zero wealth: CEV = 0
        cev_zero = compute_cev(sol_yaari, 0.0, 0.0, 1, fair_pr)
        @test cev_zero.cev == 0.0
        @test cev_zero.alpha_star == 0.0

        # --- Full model with strong bequests: CEV should be near zero ---
        p_strong = ModelParams(
            gamma=2.5, beta=0.97, r=0.02,
            theta=200.0, kappa=272_628.0,
            mwr=0.82, fixed_cost=1_000.0, inflation_rate=0.02,
            medical_enabled=true, health_mortality_corr=true,
            stochastic_health=true, n_health_states=3, n_quad=TEST_NQUAD,
            c_floor=6_180.0, hazard_mult=[0.50, 1.0, 3.0],
            n_wealth=TEST_NW, n_annuity=TEST_NA, n_alpha=TEST_NALPHA,
            W_max=1_100_000.0, age_start=65, age_end=110,
            annuity_grid_power=3.0,
        )
        loaded_pr = 0.82 * fair_pr
        sol_strong = solve_lifecycle_health(p_strong, grids, base_surv, ss_zero)

        # Strong bequests + loads + inflation: CEV should be small
        cev_strong = compute_cev(sol_strong, 100_000.0, 0.0, 1, loaded_pr)
        @test cev_strong.cev < 0.10  # less than 10% (likely 0)
    end

    # ===================================================================
    # Test Group 3: Monotonicity
    # ===================================================================
    @testset "CEV monotonicity" begin
        p_base = ModelParams(age_start=65, age_end=110)
        base_surv = build_lockwood_survival(p_base)
        ss_zero(age, p) = 0.0

        # Solve two models: no bequests and moderate bequests
        p_no_beq = ModelParams(
            gamma=2.5, beta=0.97, r=0.02,
            theta=0.0, kappa=0.0,
            mwr=0.82, fixed_cost=1_000.0, inflation_rate=0.02,
            medical_enabled=true, health_mortality_corr=true,
            stochastic_health=true, n_health_states=3, n_quad=TEST_NQUAD,
            c_floor=6_180.0, hazard_mult=[0.50, 1.0, 3.0],
            n_wealth=TEST_NW, n_annuity=TEST_NA, n_alpha=TEST_NALPHA,
            W_max=1_100_000.0, age_start=65, age_end=110,
            annuity_grid_power=3.0,
        )
        p_fair_grid = ModelParams(gamma=2.5, beta=0.97, r=0.02, mwr=1.0,
            n_wealth=TEST_NW, n_annuity=TEST_NA, n_alpha=TEST_NALPHA,
            W_max=1_100_000.0, age_start=65, age_end=110,
            annuity_grid_power=3.0)
        fair_pr = compute_payout_rate(p_fair_grid, base_surv)
        grids = build_grids(p_fair_grid, fair_pr)
        loaded_pr = 0.82 * fair_pr

        sol_no_beq = solve_lifecycle_health(p_no_beq, grids, base_surv, ss_zero)

        p_mod_beq = ModelParams(
            gamma=2.5, beta=0.97, r=0.02,
            theta=56.96, kappa=272_628.0,
            mwr=0.82, fixed_cost=1_000.0, inflation_rate=0.02,
            medical_enabled=true, health_mortality_corr=true,
            stochastic_health=true, n_health_states=3, n_quad=TEST_NQUAD,
            c_floor=6_180.0, hazard_mult=[0.50, 1.0, 3.0],
            n_wealth=TEST_NW, n_annuity=TEST_NA, n_alpha=TEST_NALPHA,
            W_max=1_100_000.0, age_start=65, age_end=110,
            annuity_grid_power=3.0,
        )
        sol_mod_beq = solve_lifecycle_health(p_mod_beq, grids, base_surv, ss_zero)

        # CEV decreases with bequest intensity (at moderate wealth)
        W_test = 200_000.0
        cev_nb = compute_cev(sol_no_beq, W_test, 0.0, 1, loaded_pr)
        cev_mb = compute_cev(sol_mod_beq, W_test, 0.0, 1, loaded_pr)
        @test cev_nb.cev >= cev_mb.cev - 1e-6  # no bequests >= moderate bequests

        # CEV higher for Good health than Poor health (longer payout horizon)
        # Use the no-bequest model to isolate the health effect
        cev_good = compute_cev(sol_no_beq, W_test, 0.0, 1, loaded_pr)
        cev_poor = compute_cev(sol_no_beq, W_test, 0.0, 3, loaded_pr)
        @test cev_good.cev >= cev_poor.cev - 1e-6

        # CEV higher for fair pricing than loaded pricing
        p_fair_model = ModelParams(
            gamma=2.5, beta=0.97, r=0.02,
            theta=0.0, kappa=0.0,
            mwr=1.0, fixed_cost=0.0, inflation_rate=0.02,
            medical_enabled=true, health_mortality_corr=true,
            stochastic_health=true, n_health_states=3, n_quad=TEST_NQUAD,
            c_floor=6_180.0, hazard_mult=[0.50, 1.0, 3.0],
            n_wealth=TEST_NW, n_annuity=TEST_NA, n_alpha=TEST_NALPHA,
            W_max=1_100_000.0, age_start=65, age_end=110,
            annuity_grid_power=3.0,
        )
        sol_fair = solve_lifecycle_health(p_fair_model, grids, base_surv, ss_zero)

        cev_fair = compute_cev(sol_fair, W_test, 0.0, 1, fair_pr)
        cev_loaded = compute_cev(sol_no_beq, W_test, 0.0, 1, loaded_pr)
        @test cev_fair.cev >= cev_loaded.cev - 1e-6
    end

    # ===================================================================
    # Test Group 4: compute_cev_population Consistency
    # ===================================================================
    @testset "Population CEV consistency" begin
        p_base = ModelParams(age_start=65, age_end=110)
        base_surv = build_lockwood_survival(p_base)
        ss_zero(age, p) = 0.0

        p_test = ModelParams(
            gamma=2.5, beta=0.97, r=0.02,
            theta=56.96, kappa=272_628.0,
            mwr=0.82, fixed_cost=1_000.0, inflation_rate=0.02,
            medical_enabled=true, health_mortality_corr=true,
            stochastic_health=true, n_health_states=3, n_quad=TEST_NQUAD,
            c_floor=6_180.0, hazard_mult=[0.50, 1.0, 3.0],
            n_wealth=TEST_NW, n_annuity=TEST_NA, n_alpha=TEST_NALPHA,
            W_max=1_100_000.0, age_start=65, age_end=110,
            annuity_grid_power=3.0,
        )
        p_fair_grid = ModelParams(gamma=2.5, beta=0.97, r=0.02, mwr=1.0,
            n_wealth=TEST_NW, n_annuity=TEST_NA, n_alpha=TEST_NALPHA,
            W_max=1_100_000.0, age_start=65, age_end=110,
            annuity_grid_power=3.0)
        fair_pr = compute_payout_rate(p_fair_grid, base_surv)
        grids = build_grids(p_fair_grid, fair_pr)
        loaded_pr = 0.82 * fair_pr

        sol = solve_lifecycle_health(p_test, grids, base_surv, ss_zero)

        # Small test population
        test_pop = [
            50_000.0  10_000.0  65.0  1.0;   # moderate wealth, good health
            200_000.0 15_000.0  70.0  2.0;   # higher wealth, fair health
            10_000.0  8_000.0   75.0  3.0;   # low wealth, poor health
            500_000.0 20_000.0  65.0  1.0;   # high wealth, good health
            0.0       5_000.0   65.0  2.0;   # zero wealth
        ]

        result = compute_cev_population(sol, test_pop, loaded_pr; base_surv=base_surv)

        @test length(result.results) == 5

        # All CEVs should be finite and bounded
        for r in result.results
            @test isfinite(r.cev)
            @test r.cev >= -1.0
            @test r.cev <= 2.0
        end

        # Zero-wealth agent should have CEV = 0
        @test result.results[5].cev == 0.0

        # Agents with alpha_star = 0 should have CEV = 0
        for r in result.results
            if r.alpha_star == 0.0
                @test r.cev == 0.0
            end
        end

        # Agents with positive CEV should have alpha_star > 0
        for r in result.results
            if r.cev > 1e-6
                @test r.alpha_star > 0.0
            end
        end

        # Summary stats should be reasonable
        @test result.mean_cev >= -1.0
        @test result.mean_cev <= 2.0
        @test result.frac_positive >= 0.0
        @test result.frac_positive <= 1.0
        @test result.frac_above_1pct >= 0.0
        @test result.frac_above_1pct <= result.frac_positive + 1e-10
    end

    # ===================================================================
    # Test Group 5: simulate_welfare_comparison
    # ===================================================================
    @testset "Welfare simulation comparison" begin
        p_base = ModelParams(age_start=65, age_end=110)
        base_surv = build_lockwood_survival(p_base)
        ss_zero(age, p) = 0.0

        p_test = ModelParams(
            gamma=2.5, beta=0.97, r=0.02,
            theta=56.96, kappa=272_628.0,
            mwr=0.82, fixed_cost=1_000.0, inflation_rate=0.02,
            medical_enabled=true, health_mortality_corr=true,
            stochastic_health=true, n_health_states=3, n_quad=TEST_NQUAD,
            c_floor=6_180.0, hazard_mult=[0.50, 1.0, 3.0],
            n_wealth=TEST_NW, n_annuity=TEST_NA, n_alpha=TEST_NALPHA,
            W_max=1_100_000.0, age_start=65, age_end=110,
            annuity_grid_power=3.0,
        )
        p_fair_grid = ModelParams(gamma=2.5, beta=0.97, r=0.02, mwr=1.0,
            n_wealth=TEST_NW, n_annuity=TEST_NA, n_alpha=TEST_NALPHA,
            W_max=1_100_000.0, age_start=65, age_end=110,
            annuity_grid_power=3.0)
        fair_pr = compute_payout_rate(p_fair_grid, base_surv)
        grids = build_grids(p_fair_grid, fair_pr)
        loaded_pr = 0.82 * fair_pr

        sol = solve_lifecycle_health(p_test, grids, base_surv, ss_zero)

        comp = simulate_welfare_comparison(
            sol, 200_000.0, 1, base_surv, p_test;
            payout_rate=loaded_pr, n_sim=500, rng_seed=42,
        )

        @test comp.alpha_star >= 0.0
        @test comp.alpha_star <= 1.0

        # Consumption and wealth paths should be positive at age 65
        @test comp.with_annuity.mean_consumption_by_age[1] > 0.0
        @test comp.without_annuity.mean_consumption_by_age[1] > 0.0
        @test comp.with_annuity.mean_wealth_by_age[1] >= 0.0
        @test comp.without_annuity.mean_wealth_by_age[1] > 0.0

        # Without annuity should start with full wealth
        @test comp.without_annuity.mean_wealth_by_age[1] ≈ 200_000.0 atol=1.0
    end

end  # testset
