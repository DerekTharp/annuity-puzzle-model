using Test

include(joinpath(@__DIR__, "..", "src", "AnnuityPuzzle.jl"))
using .AnnuityPuzzle
using Interpolations

@testset "Lockwood (2012) Replication" begin

    # Common setup: Lockwood's exact parameters
    surv = build_lockwood_survival(ModelParams(age_end=110))

    @testset "SSA life table matches Lockwood" begin
        cdp = LOCKWOOD_CUM_DEATH_PROBS
        # Conditional survival at age 65
        s65 = (1.0 - cdp[2]) / (1.0 - cdp[1])
        @test s65 ≈ 1.0 - 0.018740306  atol=1e-8

        # Life table has 46 entries (ages 65-110)
        @test length(cdp) == 46
        @test cdp[1] == 0.0
        @test cdp[end] ≈ 0.999987286

        # Survival probs are generally decreasing (allow small violations
        # at extreme ages due to life table discretization)
        surv_test = build_lockwood_survival(ModelParams(age_end=110))
        @test length(surv_test) == 46
        for i in 2:40  # ages 66-104: strictly decreasing
            @test surv_test[i] <= surv_test[i-1] + 1e-6
        end
        @test surv_test[46] == 0.0  # certain death at max age
    end

    @testset "Fair payout rate matches Lockwood" begin
        p = ModelParams(gamma=2.0, beta=1/1.03, r=0.03, age_end=110)
        pr = compute_payout_rate(p, surv)
        # Lockwood: p_unit_ann ≈ 12.82, so payout ≈ 0.0780
        @test pr ≈ 0.077995  atol=0.0001
    end

    @testset "WTP without bequests ≈ 25% (fair, 50% pre-ann)" begin
        p = ModelParams(
            gamma=2.0, beta=1.0/1.03, r=0.03,
            theta=0.0, kappa=10.0,
            age_start=65, age_end=110,
            mwr=1.0, fixed_cost=0.0, c_floor=100.0,
            n_wealth=80, n_annuity=25, n_alpha=101,
            W_max=1_100_000.0,
        )
        pr = compute_payout_rate(p, surv)
        grids = build_grids(p, pr)
        ss_zero(age, params) = 0.0
        sol = solve_lifecycle(p, grids, surv, ss_zero)

        # Lockwood setup: $500K total, 50% pre-annuitized
        N_ref = 250_000.0
        y_ref = 250_000.0 * pr  # pre-existing annuity income

        result = compute_wtp_lockwood(N_ref, y_ref, sol, pr)

        # Lockwood's WTP ≈ 25.3%, tolerance ±5pp
        @test result.wtp > 0.20
        @test result.wtp < 0.30
        # Full annuitization without bequests
        @test result.alpha_star >= 0.90
    end

    @testset "WTP declines with pre-annuitized fraction" begin
        p = ModelParams(
            gamma=2.0, beta=1.0/1.03, r=0.03,
            theta=0.0, kappa=10.0,
            age_start=65, age_end=110,
            mwr=1.0, fixed_cost=0.0, c_floor=100.0,
            n_wealth=80, n_annuity=25, n_alpha=101,
            W_max=1_100_000.0,
        )
        pr = compute_payout_rate(p, surv)
        grids = build_grids(p, pr)
        ss_zero(age, params) = 0.0
        sol = solve_lifecycle(p, grids, surv, ss_zero)

        tot_W = 500_000.0
        prev_wtp = 1.0
        for f in [0.0, 0.25, 0.50, 0.75]
            N_ref = tot_W * (1.0 - f)
            y_ref = tot_W * f * pr
            result = compute_wtp_lockwood(N_ref, y_ref, sol, pr)
            @test result.wtp < prev_wtp  # monotonically declining
            prev_wtp = result.wtp
        end
    end

    @testset "WTP collapses with bequest motives" begin
        pr_fair = compute_payout_rate(ModelParams(gamma=2.0, r=0.03, age_end=110), surv)
        N_ref = 250_000.0
        y_ref = 250_000.0 * pr_fair

        # Compute WTP at different bequest intensities
        wtp_values = Float64[]
        for bsn in [0.0, 0.10, 0.20, 0.30, 0.50]
            theta = bsn > 0.0 ? calibrate_theta(bsn, N_ref, pr_fair,
                ModelParams(gamma=2.0, r=0.03, age_end=110)) : 0.0
            p = ModelParams(
                gamma=2.0, beta=1.0/1.03, r=0.03,
                theta=theta, kappa=10.0,
                age_start=65, age_end=110,
                mwr=1.0, fixed_cost=0.0, c_floor=100.0,
                n_wealth=80, n_annuity=25, n_alpha=101,
                W_max=1_100_000.0,
            )
            grids = build_grids(p, pr_fair)
            ss_zero(age, params) = 0.0
            sol = solve_lifecycle(p, grids, surv, ss_zero)
            result = compute_wtp_lockwood(N_ref, y_ref, sol, pr_fair)
            push!(wtp_values, result.wtp)
        end

        # WTP should be monotonically decreasing
        for i in 2:length(wtp_values)
            @test wtp_values[i] <= wtp_values[i-1] + 0.01
        end

        # No bequest: WTP > 20%
        @test wtp_values[1] > 0.20

        # Moderate bequest (b*/N=0.20): WTP drops substantially (< 15%)
        @test wtp_values[3] < 0.15

        # Strong bequest (b*/N=0.50): WTP near zero (< 5%)
        @test wtp_values[5] < 0.05
    end

    @testset "Loaded annuities reduce WTP" begin
        N_ref = 250_000.0

        wtp_fair = 0.0
        wtp_loaded = 0.0

        for (mwr, label) in [(1.0, "fair"), (0.90, "loaded")]
            p = ModelParams(
                gamma=2.0, beta=1.0/1.03, r=0.03,
                theta=0.0, kappa=10.0,
                age_start=65, age_end=110,
                mwr=mwr, fixed_cost=0.0, c_floor=100.0,
                n_wealth=80, n_annuity=25, n_alpha=101,
                W_max=1_100_000.0,
            )
            pr = compute_payout_rate(p, surv)
            pr_fair = compute_payout_rate(ModelParams(p; mwr=1.0), surv)
            y_ref = 250_000.0 * pr_fair
            grids = build_grids(p, pr)
            ss_zero(age, params) = 0.0
            sol = solve_lifecycle(p, grids, surv, ss_zero)
            result = compute_wtp_lockwood(N_ref, y_ref, sol, pr)

            if mwr == 1.0
                wtp_fair = result.wtp
            else
                wtp_loaded = result.wtp
            end
        end

        # Loaded annuities should reduce WTP
        @test wtp_loaded < wtp_fair
        # But WTP still positive without bequests
        @test wtp_loaded > 0.05
    end

    @testset "Bequest calibration" begin
        p = ModelParams(gamma=2.0, r=0.03, age_end=110)
        pr = compute_payout_rate(p, surv)

        # theta should increase with b*/N
        theta_10 = calibrate_theta(0.10, 250_000.0, pr, p)
        theta_20 = calibrate_theta(0.20, 250_000.0, pr, p)
        theta_50 = calibrate_theta(0.50, 250_000.0, pr, p)

        @test theta_10 > 0.0
        @test theta_20 > theta_10
        @test theta_50 > theta_20

        # No bequest when b*/N = 0
        @test calibrate_theta(0.0, 250_000.0, pr, p) == 0.0
    end

    @testset "Value function properties (Lockwood params)" begin
        p = ModelParams(
            gamma=2.0, beta=1.0/1.03, r=0.03,
            theta=0.0, kappa=10.0,
            age_start=65, age_end=110,
            mwr=1.0, fixed_cost=0.0, c_floor=100.0,
            n_wealth=60, n_annuity=15, n_alpha=51,
            W_max=1_100_000.0,
        )
        pr = compute_payout_rate(p, surv)
        grids = build_grids(p, pr)
        ss_zero(age, params) = 0.0
        sol = solve_lifecycle(p, grids, surv, ss_zero)

        # No NaN or -Inf in value function
        @test sum(isnan.(sol.V)) == 0
        @test sum(isinf.(sol.V)) == 0

        # Monotonicity in wealth
        for ia in 1:length(grids.A), t in 1:p.T, iw in 2:length(grids.W)
            @test sol.V[iw, ia, t] >= sol.V[iw-1, ia, t] - 1e-10
        end
    end

    println("\nLockwood replication tests completed.")
end
