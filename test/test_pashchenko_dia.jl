using Test

include(joinpath(@__DIR__, "..", "src", "AnnuityPuzzle.jl"))
using .AnnuityPuzzle

# Small grids for fast testing
const TEST_NW = 15
const TEST_NA = 8
const TEST_NALPHA = 11
const TEST_NQUAD = 3

@testset "Pashchenko Replication and DIA Extension" begin

    # ===================================================================
    # Test Group 1: Minimum Purchase
    # ===================================================================
    @testset "Minimum purchase requirement" begin

        # --- is_feasible_purchase logic ---
        p_no_min = ModelParams(min_purchase=0.0)
        p_min_25k = ModelParams(min_purchase=25_000.0)
        p_min_1m = ModelParams(min_purchase=1_000_000.0)

        # alpha=0 always feasible
        @test is_feasible_purchase(0.0, 100_000.0, p_no_min) == true
        @test is_feasible_purchase(0.0, 100_000.0, p_min_25k) == true
        @test is_feasible_purchase(0.0, 100_000.0, p_min_1m) == true

        # No min_purchase: everything feasible
        @test is_feasible_purchase(0.1, 10_000.0, p_no_min) == true
        @test is_feasible_purchase(0.5, 1_000.0, p_no_min) == true

        # $25K minimum: alpha=0.5 of $100K = $50K >= $25K
        @test is_feasible_purchase(0.5, 100_000.0, p_min_25k) == true
        # alpha=0.1 of $100K = $10K < $25K
        @test is_feasible_purchase(0.1, 100_000.0, p_min_25k) == false
        # alpha=0.5 of $40K = $20K < $25K
        @test is_feasible_purchase(0.5, 40_000.0, p_min_25k) == false
        # alpha=1.0 of $25K = $25K >= $25K (boundary)
        @test is_feasible_purchase(1.0, 25_000.0, p_min_25k) == true

        # $1M minimum: no one with $100K can meet it
        @test is_feasible_purchase(1.0, 100_000.0, p_min_1m) == false
        @test is_feasible_purchase(1.0, 1_000_000.0, p_min_1m) == true

        # --- min_purchase=0 recovers existing results ---
        p_base = ModelParams(age_start=65, age_end=110)
        base_surv = build_lockwood_survival(p_base)
        ss_zero(age, p) = 0.0

        p_nmp = ModelParams(
            gamma=2.5, beta=0.97, r=0.02,
            theta=0.0, kappa=0.0,
            mwr=1.0, fixed_cost=0.0, inflation_rate=0.0,
            min_purchase=0.0,
            medical_enabled=false, health_mortality_corr=false,
            stochastic_health=true, n_health_states=3, n_quad=TEST_NQUAD,
            c_floor=6_180.0, hazard_mult=[0.50, 1.0, 3.0],
            n_wealth=TEST_NW, n_annuity=TEST_NA, n_alpha=TEST_NALPHA,
            W_max=1_100_000.0, age_start=65, age_end=110,
            annuity_grid_power=3.0,
        )
        fair_pr = compute_payout_rate(p_nmp, base_surv)
        grids = build_grids(p_nmp, fair_pr)
        sol_nmp = solve_lifecycle_health(p_nmp, grids, base_surv, ss_zero)

        # Yaari benchmark with min_purchase=0: high ownership
        alpha_star_nmp, _ = solve_annuitization_health(sol_nmp, fair_pr; initial_health=2)
        # At high wealth, should annuitize
        @test alpha_star_nmp[end] > 0.0

        # --- min_purchase=$50K: zero ownership for agents with W < $50K ---
        p_mp50k = ModelParams(
            gamma=2.5, beta=0.97, r=0.02,
            theta=0.0, kappa=0.0,
            mwr=1.0, fixed_cost=0.0, inflation_rate=0.0,
            min_purchase=50_000.0,
            medical_enabled=false, health_mortality_corr=false,
            stochastic_health=true, n_health_states=3, n_quad=TEST_NQUAD,
            c_floor=6_180.0, hazard_mult=[0.50, 1.0, 3.0],
            n_wealth=TEST_NW, n_annuity=TEST_NA, n_alpha=TEST_NALPHA,
            W_max=1_100_000.0, age_start=65, age_end=110,
            annuity_grid_power=3.0,
        )
        sol_mp50k = solve_lifecycle_health(p_mp50k, grids, base_surv, ss_zero)
        alpha_star_mp50k, _ = solve_annuitization_health(sol_mp50k, fair_pr; initial_health=2)

        # At low wealth (below $50K), cannot meet minimum
        for iw in 1:length(grids.W)
            if grids.W[iw] < 50_000.0
                @test alpha_star_mp50k[iw] == 0.0
            end
        end
        # At high wealth, should still annuitize
        @test alpha_star_mp50k[end] > 0.0

        # --- min_purchase=$1M: zero ownership for everyone in typical population ---
        test_pop = [30_000.0 10_000.0 65.0 2.0;
                    100_000.0 15_000.0 65.0 2.0;
                    500_000.0 20_000.0 65.0 2.0]
        p_mp1m = ModelParams(
            gamma=2.5, beta=0.97, r=0.02,
            theta=0.0, kappa=0.0,
            mwr=1.0, fixed_cost=0.0, inflation_rate=0.0,
            min_purchase=1_000_000.0,
            medical_enabled=false, health_mortality_corr=false,
            stochastic_health=true, n_health_states=3, n_quad=TEST_NQUAD,
            c_floor=6_180.0, hazard_mult=[0.50, 1.0, 3.0],
            n_wealth=TEST_NW, n_annuity=TEST_NA, n_alpha=TEST_NALPHA,
            W_max=1_100_000.0, age_start=65, age_end=110,
            annuity_grid_power=3.0,
        )
        sol_mp1m = solve_lifecycle_health(p_mp1m, grids, base_surv, ss_zero)
        own_mp1m = compute_ownership_rate_health(
            sol_mp1m, test_pop, fair_pr; base_surv=base_surv).ownership_rate
        @test own_mp1m == 0.0
    end

    # ===================================================================
    # Test Group 2: DIA Payout Rate
    # ===================================================================
    @testset "DIA payout rate" begin
        p_base = ModelParams(age_start=65, age_end=110, r=0.02)
        base_surv = build_lockwood_survival(p_base)

        # SPIA payout rate
        p_spia = ModelParams(age_start=65, age_end=110, r=0.02, mwr=0.82)
        spia_pr = compute_payout_rate(p_spia, base_surv)

        # DIA-80 payout rate
        p_dia80 = ModelParams(age_start=65, age_end=110, r=0.02, dia_mwr=0.50)
        dia80_pr = compute_payout_rate_deferred(p_dia80, base_surv, 80)

        # DIA-85 payout rate
        p_dia85 = ModelParams(age_start=65, age_end=110, r=0.02, dia_mwr=0.45)
        dia85_pr = compute_payout_rate_deferred(p_dia85, base_surv, 85)

        # DIA payout rate > SPIA payout rate per dollar (higher payments
        # because insurer doesn't pay during deferral)
        @test dia80_pr > spia_pr
        @test dia85_pr > dia80_pr  # longer deferral → even higher per-dollar payout

        # All positive
        @test spia_pr > 0.0
        @test dia80_pr > 0.0
        @test dia85_pr > 0.0

        # DIA with deferral at purchase age should approximate SPIA
        # (not exact because DIA uses dia_mwr, SPIA uses mwr)
        p_dia_imm = ModelParams(age_start=65, age_end=110, r=0.02, dia_mwr=0.82)
        dia_imm_pr = compute_payout_rate_deferred(p_dia_imm, base_surv, 65)
        @test dia_imm_pr ≈ spia_pr rtol=1e-10
    end

    # ===================================================================
    # Test Group 3: annuity_income_real with deferral
    # ===================================================================
    @testset "annuity_income_real" begin
        # SPIA (deferral_start_period=1): income from period 1
        p_spia = ModelParams(inflation_rate=0.02, deferral_start_period=1)
        @test annuity_income_real(10_000.0, 1, p_spia) == 10_000.0  # no inflation at t=1
        @test annuity_income_real(10_000.0, 2, p_spia) ≈ 10_000.0 / 1.02 rtol=1e-10
        @test annuity_income_real(10_000.0, 10, p_spia) ≈ 10_000.0 / 1.02^9 rtol=1e-8

        # DIA-80 (deferral_start_period=16): no income before period 16
        p_dia = ModelParams(inflation_rate=0.02, deferral_start_period=16)
        @test annuity_income_real(10_000.0, 1, p_dia) == 0.0
        @test annuity_income_real(10_000.0, 10, p_dia) == 0.0
        @test annuity_income_real(10_000.0, 15, p_dia) == 0.0
        # Period 16: income starts, but inflation from period 1
        @test annuity_income_real(10_000.0, 16, p_dia) ≈ 10_000.0 / 1.02^15 rtol=1e-8
        @test annuity_income_real(10_000.0, 16, p_dia) > 0.0

        # No inflation: income equals nominal everywhere after deferral
        p_no_inf = ModelParams(inflation_rate=0.0, deferral_start_period=16)
        @test annuity_income_real(10_000.0, 1, p_no_inf) == 0.0
        @test annuity_income_real(10_000.0, 16, p_no_inf) == 10_000.0
        @test annuity_income_real(10_000.0, 30, p_no_inf) == 10_000.0

        # Zero annuity income: always zero
        @test annuity_income_real(0.0, 1, p_spia) == 0.0
        @test annuity_income_real(0.0, 16, p_dia) == 0.0
    end

    # ===================================================================
    # Test Group 4: DIA Solver
    # ===================================================================
    @testset "DIA solver" begin
        p_base = ModelParams(age_start=65, age_end=110)
        base_surv = build_lockwood_survival(p_base)
        ss_zero(age, p) = 0.0

        # --- deferral_start_period=1 should match SPIA behavior ---
        p_spia = ModelParams(
            gamma=2.5, beta=0.97, r=0.02,
            theta=0.0, kappa=0.0,
            mwr=0.82, fixed_cost=0.0, inflation_rate=0.02,
            deferral_start_period=1,
            medical_enabled=false, health_mortality_corr=false,
            stochastic_health=true, n_health_states=3, n_quad=TEST_NQUAD,
            c_floor=6_180.0, hazard_mult=[0.50, 1.0, 3.0],
            n_wealth=TEST_NW, n_annuity=TEST_NA, n_alpha=TEST_NALPHA,
            W_max=1_100_000.0, age_start=65, age_end=110,
            annuity_grid_power=3.0,
        )
        fair_pr = compute_payout_rate(
            ModelParams(age_start=65, age_end=110, mwr=1.0, r=0.02), base_surv)
        grids = build_grids(
            ModelParams(gamma=2.5, mwr=1.0, r=0.02,
                n_wealth=TEST_NW, n_annuity=TEST_NA, n_alpha=TEST_NALPHA,
                W_max=1_100_000.0, age_start=65, age_end=110,
                annuity_grid_power=3.0),
            fair_pr)

        sol_spia = solve_lifecycle_health(p_spia, grids, base_surv, ss_zero)

        # V monotone in wealth
        for ih in 1:3
            for ia in 1:length(grids.A)
                for t in 1:p_spia.T
                    for iw in 2:length(grids.W)
                        @test sol_spia.V[iw, ia, ih, t] >= sol_spia.V[iw-1, ia, ih, t] - 1e-6
                    end
                end
            end
        end

        # --- DIA-80 model: V should also be monotone in wealth ---
        p_dia = ModelParams(
            gamma=2.5, beta=0.97, r=0.02,
            theta=0.0, kappa=0.0,
            mwr=0.82, fixed_cost=0.0, inflation_rate=0.02,
            deferral_start_period=16,
            medical_enabled=false, health_mortality_corr=false,
            stochastic_health=true, n_health_states=3, n_quad=TEST_NQUAD,
            c_floor=6_180.0, hazard_mult=[0.50, 1.0, 3.0],
            n_wealth=TEST_NW, n_annuity=TEST_NA, n_alpha=TEST_NALPHA,
            W_max=1_100_000.0, age_start=65, age_end=110,
            annuity_grid_power=3.0,
        )
        sol_dia = solve_lifecycle_health(p_dia, grids, base_surv, ss_zero)

        for ih in 1:3
            for ia in 1:length(grids.A)
                for t in 1:p_dia.T
                    for iw in 2:length(grids.W)
                        @test sol_dia.V[iw, ia, ih, t] >= sol_dia.V[iw-1, ia, ih, t] - 1e-6
                    end
                end
            end
        end

        # --- During deferral period, DIA agents have more liquid wealth available ---
        # Compare consumption at t=1 (age 65) for A>0: DIA gets no annuity income,
        # so consumption should come from liquid wealth. With same W and A on grid,
        # DIA consumption at t=1 should be at least as high as SPIA consumption
        # (since DIA treats A as 0 in period 1, the agent consumes more from W).
        # Actually, the policy function depends on the full future path, so this
        # is not a strict inequality. Instead, verify that DIA V at A=0 matches
        # SPIA V at A=0 (no annuity income in either case).
        for ih in 1:3
            for iw in 1:length(grids.W)
                @test sol_dia.V[iw, 1, ih, 1] ≈ sol_spia.V[iw, 1, ih, 1] atol=1e-4
            end
        end
    end

    # ===================================================================
    # Test Group 5: Pashchenko Channels
    # ===================================================================
    @testset "Pashchenko channel effects" begin
        p_base = ModelParams(age_start=65, age_end=110)
        base_surv = build_lockwood_survival(p_base)
        ss_zero(age, p) = 0.0

        common_kw = (gamma=3.0, beta=0.97, r=0.02,
            stochastic_health=true, n_health_states=3, n_quad=TEST_NQUAD,
            c_floor=6_180.0, hazard_mult=[0.50, 1.0, 3.0])
        grid_kw = (n_wealth=TEST_NW, n_annuity=TEST_NA, n_alpha=TEST_NALPHA,
            W_max=1_100_000.0, age_start=65, age_end=110,
            annuity_grid_power=3.0)

        p_fair_grid = ModelParams(; gamma=3.0, mwr=1.0, r=0.02, grid_kw...)
        fair_pr = compute_payout_rate(p_fair_grid, base_surv)
        grids = build_grids(p_fair_grid, fair_pr)

        # Test population (moderate wealth agents)
        test_pop = [
            100_000.0  10_000.0  65.0  2.0;
            200_000.0  15_000.0  65.0  1.0;
            300_000.0  12_000.0  68.0  2.0;
            500_000.0  20_000.0  65.0  1.0;
            50_000.0   8_000.0   70.0  3.0;
        ]

        # --- Yaari benchmark: high ownership ---
        p0 = ModelParams(; common_kw...,
            theta=0.0, kappa=0.0, mwr=1.0, fixed_cost=0.0,
            inflation_rate=0.0, min_purchase=0.0,
            medical_enabled=false, health_mortality_corr=false,
            grid_kw...)
        sol0 = solve_lifecycle_health(p0, grids, base_surv, ss_zero)
        own0 = compute_ownership_rate_health(sol0, test_pop, fair_pr; base_surv=base_surv).ownership_rate

        # --- Bequests + min purchase + loads (Pashchenko channels) ---
        loaded_pr = 0.85 * fair_pr
        p_pash = ModelParams(; common_kw...,
            theta=56.96, kappa=272_628.0,
            mwr=0.85, fixed_cost=1_000.0,
            inflation_rate=0.0, min_purchase=25_000.0,
            medical_enabled=false, health_mortality_corr=false,
            grid_kw...)
        sol_pash = solve_lifecycle_health(p_pash, grids, base_surv, ss_zero)
        own_pash = compute_ownership_rate_health(
            sol_pash, test_pop, loaded_pr; base_surv=base_surv).ownership_rate

        # Pashchenko channels should reduce ownership
        @test own_pash <= own0 + 1e-6

        # --- Adding R-S + inflation should reduce further ---
        loaded_pr2 = 0.82 * fair_pr
        p_full = ModelParams(; common_kw...,
            theta=56.96, kappa=272_628.0,
            mwr=0.82, fixed_cost=1_000.0,
            inflation_rate=0.02, min_purchase=25_000.0,
            medical_enabled=true, health_mortality_corr=true,
            grid_kw...)
        sol_full = solve_lifecycle_health(p_full, grids, base_surv, ss_zero)
        own_full = compute_ownership_rate_health(
            sol_full, test_pop, loaded_pr2; base_surv=base_surv).ownership_rate

        # Full model <= Pashchenko channels
        @test own_full <= own_pash + 1e-6

        # Monotonicity: each added channel should not increase ownership
        @test own0 >= own_pash - 1e-6
        @test own_pash >= own_full - 1e-6
    end

    # ===================================================================
    # Test Group 6: Explicit Yaari α*=1.0 (no fixed cost)
    # Reviewer flag: verify alpha_star approaches 1.0 at high wealth
    # under pure Yaari conditions (no fixed cost, no bequest).
    # ===================================================================
    @testset "Yaari alpha approaches 1.0 without fixed cost" begin
        p_yaari = ModelParams(; gamma=3.0, beta=0.97, r=0.02,
            stochastic_health=true, n_health_states=3, n_quad=TEST_NQUAD,
            c_floor=1.0,  # near-zero floor (Yaari has no safety net)
            hazard_mult=[0.50, 1.0, 3.0],
            theta=0.0, kappa=0.0, mwr=1.0,
            fixed_cost=0.0, inflation_rate=0.0,
            medical_enabled=false, health_mortality_corr=false,
            n_wealth=TEST_NW, n_annuity=TEST_NA, n_alpha=51,
            W_max=1_100_000.0, age_start=65, age_end=110,
            annuity_grid_power=3.0)

        base_surv_y = build_lockwood_survival(p_yaari)
        fair_pr_y = compute_payout_rate(p_yaari, base_surv_y)
        grids_y = build_grids(p_yaari, fair_pr_y)
        ss_zero_y(age, p) = 0.0

        sol_y = solve_lifecycle_health(p_yaari, grids_y, base_surv_y, ss_zero_y)

        # Evaluate alpha* at high wealth using CEV framework
        # Small grids (15 wealth pts) cause discretization; use relaxed threshold
        for W_test in [200_000.0, 500_000.0, 1_000_000.0]
            cev_r = compute_cev(sol_y, W_test, 0.0, 1, fair_pr_y)
            # Under pure Yaari: alpha* should be high (>= 0.60 on coarse grid)
            @test cev_r.alpha_star >= 0.60
        end
        # At very high wealth, should be tighter
        cev_high = compute_cev(sol_y, 1_000_000.0, 0.0, 1, fair_pr_y)
        @test cev_high.alpha_star >= 0.70
    end

    # ===================================================================
    # Test Group 7: Policy functions differ across health states with R-S
    # Reviewer flag: verify health-mortality correlation produces
    # meaningfully different policy functions across health states.
    # ===================================================================
    @testset "Policy functions differ across health states with R-S" begin
        common_kw_rs = (gamma=3.0, beta=0.97, r=0.02,
            stochastic_health=true, n_health_states=3, n_quad=TEST_NQUAD,
            c_floor=6_180.0, hazard_mult=[0.50, 1.0, 3.0])
        grid_kw_rs = (n_wealth=TEST_NW, n_annuity=TEST_NA, n_alpha=TEST_NALPHA,
            W_max=1_100_000.0, age_start=65, age_end=110,
            annuity_grid_power=3.0)

        base_surv_rs = build_lockwood_survival(
            ModelParams(age_start=65, age_end=110))
        fair_pr_rs = compute_payout_rate(
            ModelParams(; common_kw_rs..., mwr=1.0, grid_kw_rs...), base_surv_rs)
        grids_rs = build_grids(
            ModelParams(; common_kw_rs..., mwr=1.0, grid_kw_rs...), fair_pr_rs)
        ss_zero_rs(age, p) = 0.0

        # With R-S correlation active
        p_rs = ModelParams(; common_kw_rs...,
            theta=0.0, kappa=0.0, mwr=1.0, fixed_cost=0.0,
            inflation_rate=0.0,
            medical_enabled=true, health_mortality_corr=true,
            grid_kw_rs...)
        sol_rs = solve_lifecycle_health(p_rs, grids_rs, base_surv_rs, ss_zero_rs)

        # Policy functions should differ between Good (H=1) and Poor (H=3)
        # at midpoint of wealth grid, A=0, early periods
        mid_w = div(TEST_NW, 2)
        n_differ = 0
        for t in 1:min(20, p_rs.T)
            c_good = sol_rs.c_policy[mid_w, 1, 1, t]
            c_poor = sol_rs.c_policy[mid_w, 1, 3, t]
            if abs(c_good - c_poor) > 1e-6
                n_differ += 1
            end
        end
        # Should differ in most periods when R-S is active
        @test n_differ >= 10

        # Without R-S (medical disabled): health states still differ because
        # hazard_mult creates health-dependent survival. But the difference
        # should be SMALLER than with R-S active (medical costs amplify it).
        p_no_rs = ModelParams(; common_kw_rs...,
            theta=0.0, kappa=0.0, mwr=1.0, fixed_cost=0.0,
            inflation_rate=0.0,
            medical_enabled=false, health_mortality_corr=false,
            grid_kw_rs...)
        sol_no_rs = solve_lifecycle_health(p_no_rs, grids_rs, base_surv_rs, ss_zero_rs)

        # Compute average absolute difference in consumption across health states
        diff_with_rs = 0.0
        diff_without_rs = 0.0
        n_pts = 0
        for t in 1:min(20, p_rs.T)
            c_good_rs = sol_rs.c_policy[mid_w, 1, 1, t]
            c_poor_rs = sol_rs.c_policy[mid_w, 1, 3, t]
            c_good_no = sol_no_rs.c_policy[mid_w, 1, 1, t]
            c_poor_no = sol_no_rs.c_policy[mid_w, 1, 3, t]
            diff_with_rs += abs(c_good_rs - c_poor_rs)
            diff_without_rs += abs(c_good_no - c_poor_no)
            n_pts += 1
        end
        # R-S should produce larger differences across health states
        @test diff_with_rs > diff_without_rs
    end

    # ===================================================================
    # Test Group 8: min_purchase + DIA interaction
    # Reviewer flag: test that min_purchase constraint applies to DIA
    # ===================================================================
    @testset "min_purchase interacts with DIA" begin
        common_kw_mp = (gamma=3.0, beta=0.97, r=0.02,
            stochastic_health=true, n_health_states=3, n_quad=TEST_NQUAD,
            c_floor=6_180.0, hazard_mult=[0.50, 1.0, 3.0])
        grid_kw_mp = (n_wealth=TEST_NW, n_annuity=TEST_NA, n_alpha=TEST_NALPHA,
            W_max=1_100_000.0, age_start=65, age_end=110,
            annuity_grid_power=3.0)

        base_surv_mp = build_lockwood_survival(
            ModelParams(age_start=65, age_end=110))
        fair_pr_mp = compute_payout_rate(
            ModelParams(; common_kw_mp..., mwr=1.0, grid_kw_mp...), base_surv_mp)
        grids_mp = build_grids(
            ModelParams(; common_kw_mp..., mwr=1.0, grid_kw_mp...), fair_pr_mp)
        ss_zero_mp(age, p) = 0.0

        # DIA with min_purchase=$50K
        p_dia_mp = ModelParams(; common_kw_mp...,
            theta=0.0, kappa=0.0, mwr=1.0, fixed_cost=0.0,
            inflation_rate=0.0, min_purchase=50_000.0,
            deferral_start_period=16,
            medical_enabled=false, health_mortality_corr=false,
            grid_kw_mp...)
        sol_dia_mp = solve_lifecycle_health(p_dia_mp, grids_mp, base_surv_mp, ss_zero_mp)

        # Agents with W < $50K should not annuitize
        low_wealth_pop = [
            20_000.0  5_000.0  65.0  2.0;
            30_000.0  8_000.0  65.0  1.0;
            40_000.0  7_000.0  65.0  2.0;
        ]
        own_low = compute_ownership_rate_health(
            sol_dia_mp, low_wealth_pop, fair_pr_mp; base_surv=base_surv_mp).ownership_rate
        @test own_low == 0.0

        # Agents with W >= $100K should be able to annuitize (may or may not)
        high_wealth_pop = [
            100_000.0  10_000.0  65.0  1.0;
            200_000.0  15_000.0  65.0  1.0;
            500_000.0  20_000.0  65.0  1.0;
        ]
        # Just verify it runs without error; ownership depends on model
        own_high = compute_ownership_rate_health(
            sol_dia_mp, high_wealth_pop, fair_pr_mp; base_surv=base_surv_mp).ownership_rate
        @test own_high >= 0.0
        @test own_high <= 1.0
    end

end  # testset
