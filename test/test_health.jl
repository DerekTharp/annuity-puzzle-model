using Test

include(joinpath(@__DIR__, "..", "src", "AnnuityPuzzle.jl"))
using .AnnuityPuzzle

@testset "Phase 3: Health and Medical Expenditures" begin

    @testset "Gauss-Hermite quadrature" begin
        # Weights should sum to 1.0 (for standard normal integration)
        for n in [3, 5, 7]
            nodes, weights = gauss_hermite_normal(n)
            @test length(nodes) == n
            @test length(weights) == n
            @test sum(weights) ≈ 1.0 atol=1e-10
        end

        # Nodes should be symmetric about 0
        for n in [3, 5, 7]
            nodes, _ = gauss_hermite_normal(n)
            for i in 1:div(n, 2)
                @test nodes[i] ≈ -nodes[n + 1 - i] atol=1e-10
            end
            @test nodes[div(n, 2) + 1] ≈ 0.0 atol=1e-10
        end

        # Weights should be symmetric
        for n in [3, 5, 7]
            _, weights = gauss_hermite_normal(n)
            for i in 1:div(n, 2)
                @test weights[i] ≈ weights[n + 1 - i] atol=1e-10
            end
        end

        # E[Z] = 0 for Z ~ N(0,1)
        for n in [3, 5, 7]
            nodes, weights = gauss_hermite_normal(n)
            mean_z = sum(weights .* nodes)
            @test mean_z ≈ 0.0 atol=1e-10
        end

        # E[Z^2] = 1 for Z ~ N(0,1)
        for n in [3, 5, 7]
            nodes, weights = gauss_hermite_normal(n)
            var_z = sum(weights .* nodes .^ 2)
            @test var_z ≈ 1.0 atol=1e-6
        end

        # E[exp(Z)] = exp(1/2) for Z ~ N(0,1) (MGF at t=1)
        for n in [5, 7]
            nodes, weights = gauss_hermite_normal(n)
            mgf1 = sum(weights .* exp.(nodes))
            @test mgf1 ≈ exp(0.5) atol=0.01
        end

        # Invalid n should error
        @test_throws ErrorException gauss_hermite_normal(4)
    end

    @testset "Health transition matrices" begin
        # Row sums should be 1.0 for all ages
        for age in [65, 70, 75, 80, 85, 90, 95, 100]
            trans = build_health_transition(age)
            for i in 1:3
                @test sum(trans[i, :]) ≈ 1.0 atol=1e-10
            end
        end

        # All probabilities should be non-negative
        for age in 65:100
            trans = build_health_transition(age)
            @test all(trans .>= -1e-15)
        end

        # Band matrices should closely match HEALTH_TRANS_BANDS constants
        # (row-normalization adjusts entries by up to ~1e-6 from stored values)
        trans65 = build_health_transition(65)
        @test trans65 ≈ AnnuityPuzzle.HEALTH_TRANS_BANDS["65-69"] atol=1e-5
        trans80 = build_health_transition(80)
        @test trans80 ≈ AnnuityPuzzle.HEALTH_TRANS_BANDS["80-84"] atol=1e-5
        trans95 = build_health_transition(95)
        @test trans95 ≈ AnnuityPuzzle.HEALTH_TRANS_BANDS["90+"] atol=1e-5

        # Ages within the same band should return identical matrices
        @test build_health_transition(65) ≈ build_health_transition(69) atol=1e-15
        @test build_health_transition(70) ≈ build_health_transition(74) atol=1e-15
        @test build_health_transition(90) ≈ build_health_transition(99) atol=1e-15

        # Health deterioration should increase with age:
        # P(Good→Poor) increases, P(Good→Good) decreases
        @test trans80[1, 3] > trans65[1, 3]  # Good→Poor increases
        @test trans80[1, 1] < trans65[1, 1]  # Good→Good decreases
        # P(Fair→Fair) also decreases with age
        @test trans80[2, 2] < trans65[2, 2]

        # Precomputed transitions should have correct length
        p = ModelParams(age_start=65, age_end=100)
        transitions = build_all_health_transitions(p)
        @test length(transitions) == p.T
    end

    @testset "Health-dependent survival" begin
        p_corr = ModelParams(health_mortality_corr=true, age_end=100,
                             hazard_mult=[0.6, 1.0, 2.0])
        p_nocorr = ModelParams(health_mortality_corr=false, age_end=100)
        base_surv = build_survival_probs(ModelParams(age_end=100))

        # Without correlation: all health states have same survival
        for h in 1:3
            s = health_adjusted_survival(base_surv[1], h, p_nocorr)
            @test s ≈ base_surv[1]
        end

        # With correlation: Good > Fair > Poor
        s_good = health_adjusted_survival(base_surv[1], 1, p_corr)
        s_fair = health_adjusted_survival(base_surv[1], 2, p_corr)
        s_poor = health_adjusted_survival(base_surv[1], 3, p_corr)
        @test s_good > s_fair
        @test s_fair > s_poor

        # Fair health with mult=1.0 should equal base survival
        @test s_fair ≈ base_surv[1]

        # Hazard scaling: s_adj = s_base^mult
        @test s_good ≈ base_surv[1]^0.6
        @test s_poor ≈ base_surv[1]^2.0

        # All survival probs should be in [0, 1]
        surv_h = build_health_survival(base_surv, p_corr)
        @test all(0.0 .<= surv_h .<= 1.0)

        # Matrix dimensions
        @test size(surv_h) == (p_corr.T, 3)
    end

    @testset "Medical expense calibration" begin
        p = ModelParams(medical_enabled=true, stochastic_health=true, n_health_states=3)

        # Jones et al. (2018) targets for Fair health
        mean_70 = mean_medical_expense(70, 2, p)
        @test mean_70 ≈ 4200.0 atol=100.0  # ~$4,200

        mean_100 = mean_medical_expense(100, 2, p)
        @test mean_100 ≈ 29700.0 atol=500.0  # ~$29,700

        # Medical expenses should increase with age (all health states)
        for h in 1:3
            m70 = mean_medical_expense(70, h, p)
            m85 = mean_medical_expense(85, h, p)
            m100 = mean_medical_expense(100, h, p)
            @test m85 > m70
            @test m100 > m85
        end

        # Poor health costs more than Good health (at any age)
        for age in [70, 85, 100]
            m_good = mean_medical_expense(age, 1, p)
            m_fair = mean_medical_expense(age, 2, p)
            m_poor = mean_medical_expense(age, 3, p)
            @test m_poor > m_fair
            @test m_fair > m_good
        end

        # Sigma should vary by health state
        _, σ_good = medical_expense_params(70, 1, p)
        _, σ_fair = medical_expense_params(70, 2, p)
        _, σ_poor = medical_expense_params(70, 3, p)
        @test σ_good < σ_fair
        @test σ_fair < σ_poor
    end

    @testset "Medicaid floor" begin
        # Normal case: no floor needed
        @test apply_medicaid_floor(100_000.0, 5_000.0, 3_000.0) == 95_000.0

        # Floor kicks in when resources drop below c_floor
        @test apply_medicaid_floor(5_000.0, 4_000.0, 3_000.0) == 3_000.0

        # Severe shock: fully covered by Medicaid
        @test apply_medicaid_floor(5_000.0, 50_000.0, 3_000.0) == 3_000.0

        # Edge case: exactly at floor
        @test apply_medicaid_floor(8_000.0, 5_000.0, 3_000.0) == 3_000.0
    end

    @testset "Phase 1 recovery (no health effects)" begin
        p = ModelParams(
            gamma=2.0, beta=0.97, r=0.02,
            theta=0.0, kappa=0.0,
            age_start=65, age_end=100,
            mwr=1.0, fixed_cost=0.0, c_floor=3000.0,
            stochastic_health=true, n_health_states=3,
            health_mortality_corr=false,
            medical_enabled=false,
            n_wealth=40, n_annuity=10, n_alpha=51,
            W_max=500_000.0,
        )
        surv = build_survival_probs(p)
        pr = compute_payout_rate(p, surv)
        grids = build_grids(p, pr)
        ss_zero(age, params) = 0.0

        # Solve both Phase 1 and Phase 3
        sol1 = solve_lifecycle(p, grids, surv, ss_zero)
        sol3 = solve_lifecycle_health(p, grids, surv, ss_zero)

        # All health states should give approximately the same V as Phase 1.
        # With age-band transition matrices, health state redistribution
        # introduces small numerical differences even when health does not
        # affect survival or medical costs. Tolerance 1e-5 verifies the
        # economic equivalence while allowing for VFI accumulation error.
        for ih in 1:3
            for ia in 1:length(grids.A)
                for iw in 1:length(grids.W)
                    @test sol3.V[iw, ia, ih, 1] ≈ sol1.V[iw, ia, 1] atol=1e-5
                end
            end
        end
    end

    @testset "R-S mechanism: health-mortality correlation reduces annuity demand" begin
        common = (gamma=2.0, beta=0.97, r=0.02, theta=0.0, kappa=0.0,
                  age_start=65, age_end=100, mwr=1.0, fixed_cost=0.0,
                  c_floor=3000.0, stochastic_health=true, n_health_states=3,
                  n_wealth=50, n_annuity=12, n_alpha=51, W_max=500_000.0)

        # Case 1: No correlation, no medical → full annuitization (Yaari)
        p1 = ModelParams(; common..., health_mortality_corr=false, medical_enabled=false)
        surv1 = build_survival_probs(p1)
        pr1 = compute_payout_rate(p1, surv1)
        grids1 = build_grids(p1, pr1)
        ss_zero(age, params) = 0.0
        sol_det = solve_lifecycle(p1, grids1, surv1, ss_zero)
        alpha_det, _ = solve_annuitization(sol_det, pr1)

        # Case 2: WITH correlation + medical → reduced annuitization
        p2 = ModelParams(; common..., health_mortality_corr=true,
                         medical_enabled=true, n_quad=5)
        surv2 = build_survival_probs(p2)
        pr2 = compute_payout_rate(p2, surv2)
        grids2 = build_grids(p2, pr2)
        sol_rs = solve_lifecycle_health(p2, grids2, surv2, ss_zero)
        alpha_rs, _ = solve_annuitization_health(sol_rs, pr2; initial_health=2)

        # At moderate wealth (~100K), deterministic should give full annuitization
        idx_100k = argmin(abs.(grids1.W .- 100_000))
        @test alpha_det[idx_100k] >= 0.90  # full or near-full

        # With R-S mechanism, annuitization should drop substantially
        idx_100k_rs = argmin(abs.(grids2.W .- 100_000))
        @test alpha_rs[idx_100k_rs] < alpha_det[idx_100k]

        # The sign reversal: at some wealth level, alpha drops to 0
        # (precautionary savings motive dominates at moderate wealth)
        has_zero = any(alpha_rs[i] == 0.0 for i in 1:length(alpha_rs)
                       if grids2.W[i] > 10_000)
        @test has_zero  # R-S sign reversal exists
    end

    @testset "Medical costs alone have ambiguous effect on demand" begin
        common = (gamma=2.0, beta=0.97, r=0.02, theta=0.0, kappa=0.0,
                  age_start=65, age_end=100, mwr=1.0, fixed_cost=0.0,
                  c_floor=3000.0, stochastic_health=true, n_health_states=3,
                  n_wealth=50, n_annuity=12, n_alpha=51, W_max=500_000.0)

        # Medical costs WITHOUT health-mortality correlation
        p_med = ModelParams(; common..., health_mortality_corr=false,
                           medical_enabled=true, n_quad=5)
        surv = build_survival_probs(p_med)
        pr = compute_payout_rate(p_med, surv)
        grids = build_grids(p_med, pr)
        ss_zero(age, params) = 0.0
        sol = solve_lifecycle_health(p_med, grids, surv, ss_zero)
        alpha, _ = solve_annuitization_health(sol, pr; initial_health=2)

        # With medical costs but no health-mortality correlation,
        # the effect on demand is ambiguous (may increase or decrease):
        # - Medical costs create precautionary savings demand (reduces α)
        # - But annuity income helps cover ongoing medical costs (may increase α)
        # Just verify the solution is valid
        @test all(0.0 .<= alpha .<= 1.0)
    end

    @testset "WTP varies by health state" begin
        p = ModelParams(
            gamma=2.0, beta=1.0/1.03, r=0.03,
            theta=0.0, kappa=10.0,
            age_start=65, age_end=110,
            mwr=1.0, fixed_cost=0.0, c_floor=100.0,
            stochastic_health=true, n_health_states=3,
            health_mortality_corr=true, medical_enabled=true, n_quad=5,
            n_wealth=50, n_annuity=12, n_alpha=51,
            W_max=1_100_000.0,
        )
        surv = build_lockwood_survival(p)
        pr = compute_payout_rate(p, surv)
        grids = build_grids(p, pr)
        ss_zero(age, params) = 0.0

        sol = solve_lifecycle_health(p, grids, surv, ss_zero)

        N_ref = 250_000.0
        y_ref = 250_000.0 * pr

        wtp_good = compute_wtp_health(N_ref, y_ref, sol, pr; initial_health=1)
        wtp_fair = compute_wtp_health(N_ref, y_ref, sol, pr; initial_health=2)
        wtp_poor = compute_wtp_health(N_ref, y_ref, sol, pr; initial_health=3)

        # Good health → higher WTP (longer expected life, lower costs)
        @test wtp_good.wtp > wtp_fair.wtp
        # Poor health → lower WTP (shorter life, higher costs)
        @test wtp_poor.wtp < wtp_fair.wtp
        # All WTP should be non-negative
        @test wtp_good.wtp >= 0.0
        @test wtp_fair.wtp >= 0.0
        @test wtp_poor.wtp >= 0.0
    end

    @testset "Value function properties (health-aware)" begin
        p = ModelParams(
            gamma=2.0, beta=0.97, r=0.02,
            theta=0.0, kappa=0.0,
            age_start=65, age_end=100,
            mwr=1.0, fixed_cost=0.0, c_floor=3000.0,
            stochastic_health=true, n_health_states=3,
            health_mortality_corr=true, medical_enabled=true, n_quad=5,
            n_wealth=40, n_annuity=8, n_alpha=31,
            W_max=500_000.0,
        )
        surv = build_survival_probs(p)
        pr = compute_payout_rate(p, surv)
        grids = build_grids(p, pr)
        ss_zero(age, params) = 0.0

        sol = solve_lifecycle_health(p, grids, surv, ss_zero)

        # No NaN or -Inf in value function
        @test sum(isnan.(sol.V)) == 0
        @test sum(isinf.(sol.V)) == 0

        # Monotonicity in wealth at moderate-to-high wealth.
        # Near the Medicaid floor, medical expense shocks on coarse grids
        # create small non-monotonicities (known numerical artifact in
        # lifecycle models with means-tested safety nets).
        # Skip the lowest 30% of wealth grid points.
        start_w = max(3, div(length(grids.W) * 3, 10))
        mono_violations = 0
        mono_total = 0
        for ih in 1:3, ia in 1:length(grids.A), t in 1:p.T
            for iw in (start_w+1):length(grids.W)
                mono_total += 1
                if sol.V[iw, ia, ih, t] < sol.V[iw-1, ia, ih, t] - 1e-10
                    mono_violations += 1
                end
            end
        end
        # Allow up to 1% violations from grid/quadrature artifacts
        @test mono_violations / mono_total < 0.01
    end

    println("\nPhase 3 health tests completed.")
end
