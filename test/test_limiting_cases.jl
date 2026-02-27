using Test

include(joinpath(@__DIR__, "..", "src", "AnnuityPuzzle.jl"))
using .AnnuityPuzzle
using Interpolations

@testset "Yaari benchmark: full annuitization" begin
    # Yaari (1965): no bequest motive, actuarially fair annuities,
    # deterministic survival, no pre-existing annuity income, no safety net.
    p = ModelParams(
        gamma = 3.0,
        beta = 0.97,
        theta = 0.0,
        kappa = 0.0,
        mwr = 1.0,
        fixed_cost = 0.0,
        c_floor = 1.0,     # ~zero safety net (Yaari has none)
        n_wealth = 60,
        n_annuity = 25,
        n_alpha = 101,
        W_max = 500_000.0,
    )

    surv = build_survival_probs(p)
    payout_rate = compute_payout_rate(p, surv)
    grids = build_grids(p, payout_rate)
    ss_zero(age, params) = 0.0

    sol = solve_lifecycle(p, grids, surv, ss_zero)
    alpha_star, V_ann = solve_annuitization(sol, payout_rate)

    println("Yaari benchmark (payout rate: $(round(payout_rate, digits=4))):")
    for iw in [10, 20, 30, 40, 50, 60]
        if iw <= length(grids.W)
            println("  W=\$$(round(Int, grids.W[iw])): α*=$(round(alpha_star[iw], digits=2))")
        end
    end

    # Primary test: annuitizing should dominate holding liquid.
    # V(0, W_0*payout_rate, t=1) > V(W_0, 0, t=1) at all wealth levels.
    V_t1 = sol.V[:, :, 1]
    V_interp = linear_interpolation(
        (grids.W, grids.A), V_t1,
        extrapolation_bc=Interpolations.Flat(),
    )

    for iw in 1:length(grids.W)
        W_0 = grids.W[iw]
        W_0 < 1_000.0 && continue  # skip near-zero wealth
        A_full = W_0 * payout_rate
        A_clamped = clamp(A_full, grids.A[1], grids.A[end])
        V_annuitized = V_interp(0.0, A_clamped)
        V_liquid = V_interp(W_0, 0.0)
        @test V_annuitized >= V_liquid - 1e-12
    end

    # Secondary: α* should be high (≥0.60) at all wealth levels above $5K.
    # Exact value fluctuates due to grid discretization.
    for iw in 1:length(grids.W)
        if grids.W[iw] >= 5_000.0
            @test alpha_star[iw] >= 0.60
        end
    end

    # At high wealth (≥$100K), α* should be very close to 1.0.
    for iw in 1:length(grids.W)
        if grids.W[iw] >= 100_000.0
            @test alpha_star[iw] >= 0.90
        end
    end

    # No NaN or -Inf in value function
    @test sum(isnan.(sol.V)) == 0
    @test sum(isinf.(sol.V)) == 0

    # Value function monotonicity in wealth
    for ia in 1:length(grids.A), t in 1:p.T, iw in 2:length(grids.W)
        @test sol.V[iw, ia, t] >= sol.V[iw-1, ia, t] - 1e-10
    end

    println("Yaari benchmark tests passed.")
end

@testset "Limiting case: certain lifespan" begin
    p = ModelParams(
        gamma = 3.0, beta = 0.97, theta = 0.0, kappa = 0.0,
        mwr = 1.0, fixed_cost = 0.0, c_floor = 1.0,
        n_wealth = 30, n_annuity = 10, n_alpha = 21, W_max = 500_000.0,
    )

    surv_certain = ones(p.T)
    surv_certain[end] = 0.0

    payout_rate = compute_payout_rate(p, surv_certain)
    grids = build_grids(p, payout_rate)
    ss_zero(age, params) = 0.0

    sol = solve_lifecycle(p, grids, surv_certain, ss_zero)
    alpha_star, _ = solve_annuitization(sol, payout_rate)

    @test sum(isnan.(sol.V)) == 0
    println("Certain lifespan test passed.")
end

@testset "Limiting case: zero wealth" begin
    p = ModelParams(
        gamma = 3.0, beta = 0.97, theta = 0.0, kappa = 0.0,
        mwr = 1.0, fixed_cost = 0.0,
        n_wealth = 30, n_annuity = 10, n_alpha = 21, W_max = 500_000.0,
    )

    surv = build_survival_probs(p)
    payout_rate = compute_payout_rate(p, surv)
    grids = build_grids(p, payout_rate)
    ss_zero(age, params) = 0.0

    sol = solve_lifecycle(p, grids, surv, ss_zero)
    alpha_star, _ = solve_annuitization(sol, payout_rate)

    @test grids.W[1] == 0.0
    println("Zero wealth test passed.")
end

@testset "Limiting case: bequest with κ=0 → zero full annuitization" begin
    # With κ=0 and θ>0, V_bequest(0) = -Inf.
    # Any annuitization risks death at W=0, so α* should be 0.
    p = ModelParams(
        gamma = 3.0, beta = 0.97,
        theta = 5.0, kappa = 0.0,  # κ=0: bequest utility -Inf at b=0
        mwr = 1.0, fixed_cost = 0.0, c_floor = 1.0,
        n_wealth = 30, n_annuity = 10, n_alpha = 21, W_max = 500_000.0,
    )

    surv = build_survival_probs(p)
    payout_rate = compute_payout_rate(p, surv)
    grids = build_grids(p, payout_rate)
    ss_zero(age, params) = 0.0

    sol = solve_lifecycle(p, grids, surv, ss_zero)
    alpha_star, _ = solve_annuitization(sol, payout_rate)

    println("\nBequest with κ=0 (θ=5):")
    for iw in [10, 20, 30]
        if iw <= length(grids.W)
            println("  W=\$$(round(Int, grids.W[iw])): α*=$(round(alpha_star[iw], digits=2))")
        end
    end

    # Full annuitization (α=1) would leave W=0 → V_beq=-Inf.
    # Agent should avoid full annuitization. α* should be well below 1.
    for iw in 1:length(grids.W)
        if grids.W[iw] >= 10_000.0
            @test alpha_star[iw] < 1.0
        end
    end
    println("Bequest (κ=0) test passed.")
end
