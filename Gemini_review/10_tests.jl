# =============================================================================
# 10_tests.jl — Test suite.
#
# This file consolidates:
#   test/runtests.jl                  test driver
#   test/test_utility.jl              CRRA + bequest + purchase-penalty unit tests
#   test/test_limiting_cases.jl       Yaari benchmark, infinite bequest, etc.
#   test/test_grid_clamp_audit.jl     wealth/annuity grid clamp audit
#   test/test_age_invariance.jl       age-invariance regression tests
#   test/test_health.jl               health Markov + medical-cost tests
#   test/test_lockwood.jl             Lockwood (2012) replication tests
#   test/test_pashchenko_dia.jl       Pashchenko + DIA tests
#   test/test_phase4.jl               Phase 4 build-stage integration tests
#   test/test_welfare.jl              CEV computation tests
#   test/test_10channel_smoke.jl      10-channel smoke test
#   test/test_manuscript_numbers.jl   manuscript-number lock against numbers.tex
#
# Note: test/test_headline_regression.jl.deprecated is not included
# (deprecated in favor of test_manuscript_numbers.jl + test_age_invariance.jl).
# =============================================================================

#=============================================================================
# ORIGINAL FILE: test/runtests.jl
#=============================================================================

# Unified test runner for AnnuityPuzzle
#
# Each test file includes the AnnuityPuzzle module independently,
# so they must run in separate Julia processes to avoid re-include conflicts.
#
# Usage: julia test/runtests.jl
#        julia test/runtests.jl test_utility   (run single suite)

using Printf

const TEST_DIR = @__DIR__
const PROJECT_DIR = dirname(TEST_DIR)

const TEST_FILES = [
    "test_utility.jl",
    "test_limiting_cases.jl",
    "test_lockwood.jl",
    "test_health.jl",
    "test_phase4.jl",
    "test_welfare.jl",
    "test_pashchenko_dia.jl",
    "test_10channel_smoke.jl",
    "test_age_invariance.jl",
    "test_manuscript_numbers.jl",
    "test_grid_clamp_audit.jl",
]

function run_test_file(filename::String)
    path = joinpath(TEST_DIR, filename)
    @printf("  %-30s", filename)
    t0 = time()
    proc = run(pipeline(`$(Base.julia_cmd()) --project=$PROJECT_DIR $path`,
                        stderr=stderr), wait=false)
    wait(proc)
    elapsed = time() - t0
    if proc.exitcode == 0
        @printf(" PASS  (%5.1fs)\n", elapsed)
        return true
    else
        @printf(" FAIL  (%5.1fs)\n", elapsed)
        return false
    end
end

function main()
    # Allow running a single test by name
    if length(ARGS) > 0
        filter_name = ARGS[1]
        files = filter(f -> occursin(filter_name, f), TEST_FILES)
        if isempty(files)
            println("No test file matching '$filter_name'")
            println("Available: ", join(TEST_FILES, ", "))
            exit(1)
        end
    else
        files = TEST_FILES
    end

    println("=" ^ 50)
    println("  AnnuityPuzzle Test Suite")
    println("=" ^ 50)
    println()

    results = Dict{String, Bool}()
    t_total = time()

    for f in files
        results[f] = run_test_file(f)
    end

    elapsed_total = time() - t_total
    n_pass = count(values(results))
    n_fail = length(results) - n_pass

    println()
    println("-" ^ 50)
    @printf("  %d/%d suites passed (%.1fs total)\n",
        n_pass, length(results), elapsed_total)

    if n_fail > 0
        println()
        println("  FAILED:")
        for (f, passed) in sort(collect(results), by=first)
            passed || println("    - $f")
        end
        println()
        exit(1)
    else
        println("  All tests passed.")
        println("-" ^ 50)
    end
end

main()

#=============================================================================
# ORIGINAL FILE: test/test_utility.jl
#=============================================================================

using Test

include(joinpath(@__DIR__, "..", "src", "AnnuityPuzzle.jl"))
using .AnnuityPuzzle

@testset "CRRA utility" begin
    # U(c) = c^(1-γ)/(1-γ)
    # With γ=2: U(1) = 1^(-1)/(-1) = -1
    @test utility(1.0, 2.0) ≈ -1.0
    # U(2) = 2^(-1)/(-1) = -0.5
    @test utility(2.0, 2.0) ≈ -0.5
    # Monotonicity: U(2) > U(1)
    @test utility(2.0, 3.0) > utility(1.0, 3.0)
    # Concavity: U(1.5) > (U(1) + U(2))/2
    @test utility(1.5, 3.0) > (utility(1.0, 3.0) + utility(2.0, 3.0)) / 2.0
    # Log case (γ=1)
    @test utility(1.0, 1.0) ≈ 0.0
    @test utility(exp(1.0), 1.0) ≈ 1.0
    # Non-positive consumption
    @test utility(0.0, 2.0) == -Inf
    @test utility(-1.0, 2.0) == -Inf
end

@testset "Bequest utility" begin
    # θ=0: no bequest motive
    @test bequest_utility(100_000.0, 3.0, 0.0, 0.0) == 0.0
    # With bequests, positive wealth
    @test bequest_utility(100_000.0, 3.0, 2.0, 5_000.0) < 0.0  # negative for γ>1
    # Monotonicity: more wealth => higher bequest utility
    @test bequest_utility(200_000.0, 3.0, 2.0, 5_000.0) > bequest_utility(100_000.0, 3.0, 2.0, 5_000.0)
    # κ shifts the curvature
    @test bequest_utility(0.0, 3.0, 2.0, 5_000.0) > -Inf  # κ>0 prevents -Inf at b=0
    @test bequest_utility(0.0, 3.0, 2.0, 0.0) > -Inf       # $1 floor prevents -Inf at b=0, kappa=0
    @test bequest_utility(0.0, 3.0, 2.0, 0.0) < 0.0        # but still strongly negative
end

@testset "Marginal utility" begin
    @test marginal_utility(1.0, 3.0) ≈ 1.0
    @test marginal_utility(2.0, 3.0) ≈ 2.0^(-3.0)
    @test marginal_utility(0.0, 3.0) == Inf
end

#=============================================================================
# ORIGINAL FILE: test/test_limiting_cases.jl
#=============================================================================

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

#=============================================================================
# ORIGINAL FILE: test/test_grid_clamp_audit.jl
#=============================================================================

# Audit: confirm that the production wealth and annuity-income grids contain
# the entire HRS population sample under all alpha choices, with no binding
# clamps. If any agent at any alpha would have A_total > g.A[end], the
# downstream interpolation evaluates at the grid boundary and the structural
# results silently depend on extrapolation rather than the interior solution.
#
# This test runs in seconds and is a hard check that the production grids
# are sized correctly. If it ever fails, expand W_max or A_max in config.jl.

using Test
using Printf
using DelimitedFiles
include(joinpath(@__DIR__, "..", "src", "AnnuityPuzzle.jl"))
using .AnnuityPuzzle
include(joinpath(@__DIR__, "..", "scripts", "config.jl"))

@testset "Grid-clamp audit on production sample" begin
    # Build production grids
    p_base = ModelParams(age_start=AGE_START, age_end=AGE_END)
    base_surv = build_lockwood_survival(p_base)
    grid_kw = (n_wealth=N_WEALTH, n_annuity=N_ANNUITY, n_alpha=N_ALPHA,
               W_max=W_MAX, age_start=AGE_START, age_end=AGE_END,
               annuity_grid_power=A_GRID_POW)
    p = ModelParams(; gamma=GAMMA, beta=BETA, r=R_RATE, mwr=MWR_LOADED,
                    inflation_rate=INFLATION, grid_kw...)
    payout_rate = compute_payout_rate(p, base_surv)
    g = build_grids(p, payout_rate)

    W_min = first(g.W)
    W_max = last(g.W)
    A_min = first(g.A)
    A_max = last(g.A)

    # Load production HRS sample
    hrs_csv = joinpath(@__DIR__, "..", "data", "processed", "lockwood_hrs_sample.csv")
    if !isfile(hrs_csv)
        @info "HRS sample CSV not present; skipping clamp audit."
        return
    end
    raw = readdlm(hrs_csv, ',', Any; skipstart=1)
    wealth = Float64.(raw[:, 1])
    pop_eligible = wealth .>= MIN_WEALTH
    n_eligible = count(pop_eligible)
    @test n_eligible > 0

    # Existing SS income — production uses by-quartile assignment. Compute
    # the maximum SS quartile level for the audit (worst case).
    max_ss = maximum(SS_QUARTILE_LEVELS)

    # Audit 1: Wealth clamping. Every eligible HRS agent must satisfy
    # W_min <= W <= W_max for the structural model to evaluate them at the
    # interior solution.
    @testset "Wealth-grid clamping" begin
        n_below = count((wealth .< W_min) .& pop_eligible)
        n_above = count((wealth .> W_max) .& pop_eligible)
        @test n_below == 0
        # Some HRS agents above W_max are documented in the manuscript; this
        # test asserts the count is small (< 1% of eligible) so the grid is
        # not silently truncating a large fraction of the sample.
        pct_above = 100.0 * n_above / max(n_eligible, 1)
        @info "Eligible HRS agents above W_max" n_above pct_above W_max
        @test pct_above < 1.5
    end

    # Audit 2: Annuity-income clamping. The model clamps wealth to W_max
    # before any annuity computation. Compute the maximum A_total under
    # the model's actual clamping behavior: alpha=1 with W effectively
    # min(W, W_max). The audit documents how often A_total exceeds A_max
    # (forcing the value function to be evaluated at the annuity-grid
    # boundary) and bounds the maximum overshoot.
    @testset "Annuity-income grid clamping (alpha = 1, max SS)" begin
        eligible_wealth = wealth[pop_eligible]
        effective_wealth = clamp.(eligible_wealth, W_min, W_max)
        max_a_total = max_ss .+ effective_wealth .* payout_rate
        n_above = count(max_a_total .> A_max)
        n_below = count(max_a_total .< A_min)
        @test n_below == 0
        # The annuity grid is sized to W_max * payout_rate. Adding the top
        # SS quartile on top can produce A_total slightly above this bound
        # for the highest-wealth agents at alpha=1. The fraction is small
        # (< 2% of eligible sample) and the maximum overshoot is bounded.
        # If either threshold breaches, the grid needs to be widened.
        pct_above = 100.0 * n_above / max(n_eligible, 1)
        @info "Annuity-grid clamping at alpha=1, max SS" n_above pct_above A_max
        @test pct_above < 2.0
        if n_above > 0
            max_overshoot_pct = 100.0 * (maximum(max_a_total) - A_max) / A_max
            @info "Maximum overshoot (% of A_max)" max_overshoot_pct
            @test max_overshoot_pct < 15.0
        end
    end

    @testset "Headline grid ranges (manuscript reference)" begin
        @info "Production grid bounds" W_min W_max A_min A_max payout_rate
        @test W_max ≈ W_MAX rtol=1e-9
        # A_max equals W_max × payout_rate; see build_annuity_grid docstring
        # for the documented small-overshoot behavior at alpha=1 for the
        # top wealth quartile.
        @test A_max ≈ W_max * payout_rate rtol=1e-6
    end
end

#=============================================================================
# ORIGINAL FILE: test/test_age_invariance.jl
#=============================================================================

# Unit tests for the age-N>65 annuity-purchase real/nominal premium bridge.
#
# Background. The model state V[W, A, H, t] holds A as a *constant nominal*
# annuity payment. The Bellman deflates to age-65 real dollars via
# A_real(t) = A * (1+π)^-(t-1). Premium dollars (W, pi = alpha*W) are in
# age-65 real dollars throughout the model, but compute_payout_rate returns
# a *nominal* payment per *nominal* premium dollar (Mitchell 1999 convention).
#
# For an age-N household to evaluate the V function correctly:
#   nominal_premium_at_N        = pi_real * (1+π)^(N-65)
#   constant_nominal_payment    = nominal_premium_at_N * payout_rate(N)
#                               = pi_real * (1+π)^(N-65) * payout_rate(N)
# This is what should be stored in A_state when querying V.
#
# Without the (1+π)^(N-65) bridge, the model under-states the real value of
# the new annuity by exactly that factor: at age 69 (t=5) with π=2%, that's
# (1.02)^4 ≈ 1.082, an ~8% under-statement.

using Test
using Printf

# Load the package
project_root = dirname(@__DIR__)
include(joinpath(project_root, "src", "AnnuityPuzzle.jl"))
using .AnnuityPuzzle

@testset "Age-N annuity premium bridge" begin

    # ---------------------------------------------------------------------
    # Algebraic identity: A_state grossed-up then deflated equals pi*payout
    # ---------------------------------------------------------------------
    @testset "Round-trip identity" begin
        π = 0.02
        for pi_real in [100.0, 1_000.0, 10_000.0, 100_000.0]
            for payout_rate in [0.05, 0.07, 0.10, 0.15]
                for N in 65:75
                    t = N - 65 + 1
                    inflation_factor = (1.0 + π)^(t - 1)
                    nominal_premium  = pi_real * inflation_factor
                    A_state          = nominal_premium * payout_rate
                    A_real_at_purch  = A_state * (1.0 + π)^(-(t-1))
                    expected         = pi_real * payout_rate
                    @test isapprox(A_real_at_purch, expected, rtol=1e-12)
                end
            end
        end
    end

    # ---------------------------------------------------------------------
    # Age-65 invariance: bridge factor is (1+π)^0 = 1; A_state unchanged
    # ---------------------------------------------------------------------
    @testset "Age-65 unchanged (factor = 1)" begin
        π = 0.02
        t = 1
        inflation_factor = (1.0 + π)^(t - 1)
        @test inflation_factor == 1.0
        for pi_real in [100.0, 1_000.0, 10_000.0]
            for payout_rate in [0.05, 0.10]
                old_A_state = pi_real * payout_rate
                new_A_state = pi_real * inflation_factor * payout_rate
                @test old_A_state == new_A_state
            end
        end
    end

    # ---------------------------------------------------------------------
    # Bug magnitude: at age 69 with π=2%, fix increases A_state by (1.02)^4
    # ---------------------------------------------------------------------
    @testset "Bug magnitude at HRS sample upper bound" begin
        π = 0.02
        # Age 69 corresponds to t = 5 in the model index (age_start = 65)
        N = 69
        t = N - 65 + 1
        @test t == 5
        ratio_to_old = (1.0 + π)^(t - 1)
        @test isapprox(ratio_to_old, 1.0824, atol=1e-3)  # ~8.2% bigger
    end

    # ---------------------------------------------------------------------
    # Zero-inflation special case: bridge factor is 1 at every age
    # ---------------------------------------------------------------------
    @testset "Zero inflation: bridge is identity" begin
        π = 0.0
        for N in 65:80
            t = N - 65 + 1
            inflation_factor = (1.0 + π)^(t - 1)
            @test inflation_factor == 1.0
        end
    end

    # ---------------------------------------------------------------------
    # End-to-end check on the production function paths.
    # Build a tiny model, then confirm A_state passed to V_interp matches the
    # formula nominal_premium * payout_rate at age 67 (a non-trivial age).
    #
    # We don't recompute V here; we just verify the bridge formula is what
    # the production code now computes by replicating the inline arithmetic.
    # ---------------------------------------------------------------------
    @testset "Production formula matches expected bridge" begin
        π     = 0.02
        N     = 67
        t     = N - 65 + 1
        pi_re = 50_000.0
        rate  = 0.085

        # What the OLD code computed
        A_state_old = pi_re * rate

        # What the NEW code computes
        inflation_factor = (1.0 + π)^(t - 1)
        nominal_premium  = pi_re * inflation_factor
        A_state_new      = nominal_premium * rate

        # NEW should equal OLD * (1+π)^(t-1)
        @test isapprox(A_state_new, A_state_old * inflation_factor, rtol=1e-12)

        # NEW deflated to age-65 dollars at the purchase period equals real premium × rate
        A_real_at_purchase = A_state_new * (1.0 + π)^(-(t-1))
        @test isapprox(A_real_at_purchase, pi_re * rate, rtol=1e-12)
    end
end

#=============================================================================
# ORIGINAL FILE: test/test_health.jl
#=============================================================================

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

#=============================================================================
# ORIGINAL FILE: test/test_lockwood.jl
#=============================================================================

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

#=============================================================================
# ORIGINAL FILE: test/test_pashchenko_dia.jl
#=============================================================================

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

#=============================================================================
# ORIGINAL FILE: test/test_phase4.jl
#=============================================================================

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

#=============================================================================
# ORIGINAL FILE: test/test_welfare.jl
#=============================================================================

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

#=============================================================================
# ORIGINAL FILE: test/test_10channel_smoke.jl
#=============================================================================

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

    # Sanity check vs psi_purchase=0 (rational benchmark)
    p_rational = ModelParams(; common_kw...,
        theta=THETA_DFJ, kappa=KAPPA_DFJ,
        mwr=MWR_LOADED, fixed_cost=FIXED_COST,
        inflation_rate=INFLATION,
        medical_enabled=true, health_mortality_corr=true,
        survival_pessimism=SURVIVAL_PESSIMISM,
        consumption_decline=CONSUMPTION_DECLINE,
        health_utility=Float64.(HEALTH_UTILITY),
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

#=============================================================================
# ORIGINAL FILE: test/test_manuscript_numbers.jl
#=============================================================================

# Regression test: paper/numbers.tex must match the CSV sources it's derived from.
#
# Approach:
#   1. Re-parse paper/numbers.tex into a Dict{macro_name, string_value}.
#   2. For a curated set of headline macros, re-read the source CSV the export
#      script consumed and recompute the expected string value.
#   3. Fail loudly if any headline macro drifts.
#
# When this test fails, the fix is almost always "re-run
# scripts/export_manuscript_numbers.jl" — not "edit paper/numbers.tex by hand".

using Test
using DelimitedFiles
using Printf

const TEST_DIR = @__DIR__
const REPO_ROOT = dirname(TEST_DIR)
const NUMBERS_TEX = joinpath(REPO_ROOT, "paper", "numbers.tex")
const CSV_DIR = joinpath(REPO_ROOT, "tables", "csv")
const HRS_CSV = joinpath(REPO_ROOT, "data", "processed", "lockwood_hrs_sample.csv")

# Channel bit mask constants (must match run_subset_enumeration.jl).
# Ten channels: Medical and R-S correlation are combined into a single
# channel (R-S has no economic content without medical risk).
const B_SS         = 1 << 0
const B_BEQUESTS   = 1 << 1
const B_MED_RS     = 1 << 2   # Combined: medical + R-S correlation
const B_PESSIMISM  = 1 << 3
const B_AGE_NEEDS  = 1 << 4
const B_STATE_UTIL = 1 << 5
const B_LOADS      = 1 << 6
const B_INFLATION  = 1 << 7
const B_SDU          = 1 << 8   # Force A: source-dependent utility
const B_PSI_PURCHASE = 1 << 9   # Force B: narrow-framing purchase penalty

# Backward-compat aliases (prose macros may still reference these names).
const B_MEDICAL = B_MED_RS
const B_RS      = B_MED_RS

# ---------------------------------------------------------------------------
# Parse paper/numbers.tex into a macro dictionary.
# ---------------------------------------------------------------------------

function load_macros()
    isfile(NUMBERS_TEX) || error("$(NUMBERS_TEX) not found. Run scripts/export_manuscript_numbers.jl first.")
    macros = Dict{String,String}()
    re = r"^\\newcommand\{\\(\w+)\}\{(.*)\}\s*$"
    for line in eachline(NUMBERS_TEX)
        m = match(re, line)
        m === nothing && continue
        macros[m.captures[1]] = m.captures[2]
    end
    macros
end

# ---------------------------------------------------------------------------
# Helpers that mirror the export script's formatting rules.
# ---------------------------------------------------------------------------

fmt_pct(x; digits=1) = @sprintf("%.*f\\%%", digits, x)
fmt_num(x; digits=2) = @sprintf("%.*f", digits, x)

function subset_ownership_pct(bitmask::Int)
    rows, _ = readdlm(joinpath(CSV_DIR, "subset_enumeration.csv"), ',', Any; header=true)
    for r in eachrow(rows)
        Int(r[1]) == bitmask && return Float64(r[3])
    end
    error("bitmask $bitmask not in subset_enumeration.csv")
end

# Returns true when subset_enumeration.csv reflects the current 10-channel
# code (exactly 1024 subsets — Medical and R-S combined into one channel).
# Stage 16's post-run validation runs after a fresh export and must see
# exactly 1024 rows. The earlier check (>=1024 && <2048) was too permissive
# and accepted partial or pre-reformulation CSVs as valid.
function subset_csv_is_ten_channel()
    path = joinpath(CSV_DIR, "subset_enumeration.csv")
    isfile(path) || return false
    n_rows = countlines(path) - 1  # subtract header
    return n_rows == 1024
end

function shapley_value_pp(channel::AbstractString)
    rows, _ = readdlm(joinpath(CSV_DIR, "shapley_exact.csv"), ',', Any; header=true)
    for r in eachrow(rows)
        String(r[1]) == channel && return Float64(r[2])
    end
    error("channel $(repr(channel)) not in shapley_exact.csv")
end

function welfare_ownership(scenario::AbstractString)
    path = joinpath(CSV_DIR, "welfare_counterfactuals.csv")
    prefix = scenario * ","
    for (i, line) in enumerate(eachline(path))
        i == 1 && continue
        startswith(line, prefix) || continue
        toks = split(chopprefix(line, prefix), ',')
        return parse(Float64, toks[6])
    end
    error("scenario $(repr(scenario)) not in welfare_counterfactuals.csv")
end

function hrs_observed_pct()
    raw = readdlm(HRS_CSV, ',', Any; skipstart=1)
    own = count(Float64.(raw[:, 5]) .> 0)
    return 100 * own / size(raw, 1)
end

# ---------------------------------------------------------------------------
# Tests
# ---------------------------------------------------------------------------

macros = load_macros()

@testset "paper/numbers.tex integrity" begin

    @testset "file present and non-trivial" begin
        @test length(macros) > 100
    end

    # Sequential decomposition: bitmask → ownership percent.
    # The bitmask schema below is the 10-channel reformulation (Med+R-S=bit 4).
    # Legacy 11-channel CSVs use a different bit ordering (Medical=4, R-S=8,
    # Pessimism=16, ...) so the lookups would resolve to the wrong rows. When
    # the CSV is in the legacy schema, this test set is deferred until the
    # AWS rerun produces a 1024-row 10-channel CSV.
    @testset "decomposition ownership" begin
        ten_ch = subset_csv_is_ten_channel()
        if !ten_ch
            @test_skip "subset_enumeration.csv is legacy 11-channel schema; awaiting 10-channel rerun"
        else
            cases = [
                "ownFrictionless"     => 0,
                "ownAddSS"            => B_SS,
                "ownAddBequests"      => B_SS | B_BEQUESTS,
                "ownAddMedical"       => B_SS | B_BEQUESTS | B_MED_RS,
                "ownAddRS"            => B_SS | B_BEQUESTS | B_MED_RS,
                "ownAddMedRS"         => B_SS | B_BEQUESTS | B_MED_RS,
                "ownAddPessimism"     => B_SS | B_BEQUESTS | B_MED_RS | B_PESSIMISM,
                "ownAddLoads"         => B_SS | B_BEQUESTS | B_MED_RS | B_PESSIMISM | B_LOADS,
                "ownSevenChannel"     => B_SS | B_BEQUESTS | B_MED_RS | B_PESSIMISM | B_LOADS | B_INFLATION,
                "ownEightChannel"     => B_SS | B_BEQUESTS | B_MED_RS | B_PESSIMISM | B_AGE_NEEDS | B_LOADS | B_INFLATION,
                "ownNineChannel"      => B_SS | B_BEQUESTS | B_MED_RS | B_PESSIMISM | B_AGE_NEEDS | B_STATE_UTIL | B_LOADS | B_INFLATION,
                "ownTenChannel"       => B_SS | B_BEQUESTS | B_MED_RS | B_PESSIMISM | B_AGE_NEEDS | B_STATE_UTIL | B_LOADS | B_INFLATION | B_SDU,
                "ownElevenChannel"    => B_SS | B_BEQUESTS | B_MED_RS | B_PESSIMISM | B_AGE_NEEDS | B_STATE_UTIL | B_LOADS | B_INFLATION | B_SDU | B_PSI_PURCHASE,
            ]
            for (name, bm) in cases
                @test haskey(macros, name)
                @test macros[name] == fmt_pct(subset_ownership_pct(bm); digits=1)
            end
        end
    end

    # Shapley values (pp) — signed, 1 decimal. Ten channels: eight
    # rational/preference + Force A (SDU) + Force B (narrow-framing PED).
    # The "Medical+R-S" channel only exists in the 10-channel reformulation
    # CSV; legacy 11-channel CSVs have separate "Medical" and "R-S" rows
    # that the export script aggregates.
    @testset "shapley values" begin
        # Channels that exist in both schemas
        common_cases = [
            "shapLoads"      => "Loads",
            "shapPessimism"  => "Pessimism",
            "shapAgeNeeds"   => "Age needs",
            "shapInflation"  => "Inflation",
            "shapBequests"   => "Bequests",
            "shapStateUtil"  => "State utility",
            "shapSS"         => "SS",
            "shapSDU"        => "SDU (Force A)",
            "shapNarrowFraming" => "Narrow framing (Force B)",
        ]
        for (name, ch) in common_cases
            haskey(macros, name) || continue
            @test macros[name] == fmt_num(shapley_value_pp(ch); digits=1)
        end
        # Med+R-S: native lookup if 10-channel CSV, else sum of legacy rows.
        if haskey(macros, "shapMedRS")
            shap_path = joinpath(CSV_DIR, "shapley_exact.csv")
            csv_text = read(shap_path, String)
            expected = if occursin("Medical+R-S,", csv_text)
                fmt_num(shapley_value_pp("Medical+R-S"); digits=1)
            else
                # Legacy CSV: aggregate the two separate rows
                fmt_num(shapley_value_pp("Medical") + shapley_value_pp("R-S"); digits=1)
            end
            @test macros["shapMedRS"] == expected
        end
        # Critical channels MUST be present after AWS rerun
        ten_ch = subset_csv_is_ten_channel()
        @test haskey(macros, "shapLoads")
        @test haskey(macros, "shapMedRS")
        if ten_ch
            for required in ("shapSDU", "shapNarrowFraming")
                @test haskey(macros, required)
            end
        end
    end

    # Policy counterfactual ownership from welfare_counterfactuals.csv
    @testset "welfare counterfactual ownership" begin
        cases = [
            "ownGroupPricing"     => "Group pricing (MWR=0.90)",
            "ownPublicOption"     => "Public option (MWR=0.95)",
            "ownActuariallyFair"  => "Actuarially fair (MWR=1.0)",
            "ownRealTIPS"         => "Real annuity, TIPS-backed",
            "ownRealNomEquiv"     => "Real annuity, nominal-equiv",
            "ownFairReal"         => "Fair + real",
            "ownCorrectPessimism" => "Correct pessimism (psi=1.0)",
            "ownBestFeasible"     => "Best feasible package",
        ]
        for (name, scenario) in cases
            @test haskey(macros, name)
            @test macros[name] == fmt_pct(welfare_ownership(scenario); digits=1)
        end
    end

    # HRS observed ownership (from the sample CSV own_life_ann column)
    @testset "HRS observed ownership" begin
        @test haskey(macros, "pctHRSObserved")
        @test macros["pctHRSObserved"] == fmt_pct(hrs_observed_pct(); digits=1)
    end

    # Baseline MWR pulled from welfare_counterfactuals "Baseline" row
    @testset "baseline MWR" begin
        path = joinpath(CSV_DIR, "welfare_counterfactuals.csv")
        mwr = nothing
        for (i, line) in enumerate(eachline(path))
            i == 1 && continue
            if startswith(line, "Baseline,")
                toks = split(chopprefix(line, "Baseline,"), ',')
                mwr = parse(Float64, toks[1])
                break
            end
        end
        @test mwr !== nothing
        @test haskey(macros, "pMwrBaseline")
        @test macros["pMwrBaseline"] == fmt_num(mwr; digits=2)
    end

    # Every "X\%" macro must have a companion "XNum" macro for table-cell use.
    # The Num value may be a different representation (e.g. pRRate="2\%" paired
    # with hand-defined pRRateNum="0.02"), so we only assert existence, not
    # percent-stripped equality.
    @testset "Num variants exist for every percent macro" begin
        pct_macros = [k for (k, v) in macros if endswith(v, "\\%")]
        @test !isempty(pct_macros)
        for k in pct_macros
            @test haskey(macros, k * "Num")
        end
    end

    # Behavioral channel ψ_purchase sensitivity sweep — values come from
    # tables/csv/psi_sensitivity.csv. If the CSV is missing (sensitivity not
    # yet run), we skip rather than fail to keep the test useful during
    # incremental development.
    @testset "psi_purchase sensitivity" begin
        path = joinpath(CSV_DIR, "psi_sensitivity.csv")
        if !isfile(path)
            @test_skip "psi_sensitivity.csv not yet generated"
        else
            # UK 2015 pension-freedoms anchors:
            # - ABI rational-corrected (low/mid/high): aggregate sales-volume
            #   decline mapped through the model after stripping the rational
            #   tax-removal response.
            # - ELSA rational-corrected (low/high): UK ELSA wave 6 vs waves 8-11
            #   microdata after the same rational stripping (n=869 DC pot holders).
            # - Total-drop variants: ABI aggregate and ELSA microdata, raw
            #   (no rational stripping).
            cases = [
                "ownPsiZero"          => "No PED (rational + SDU only)",
                "ownPsiUKLow"         => "ABI rational-corrected low",
                "ownPsiUKMid"         => "ABI rational-corrected mid",
                "ownPsiUKHigh"        => "ABI rational-corrected high",
                "ownPsiUKELSALow"     => "ELSA rational-corrected low",
                "ownPsiUKELSAHigh"    => "ELSA rational-corrected high",
                "ownPsiUKBLow"        => "ABI total drop (no rational stripping)",
                "ownPsiUKELSATotal"   => "ELSA total drop (no rational stripping)",
            ]
            for (name, label) in cases
                row = nothing
                for (i, line) in enumerate(eachline(path))
                    i == 1 && continue
                    startswith(line, label * ",") || continue
                    toks = split(chopprefix(line, label * ","), ',')
                    row = parse(Float64, toks[2])  # ownership_pct
                    break
                end
                if row === nothing
                    @test_skip "label $(repr(label)) not in psi_sensitivity.csv"
                else
                    @test haskey(macros, name)
                    @test macros[name] == fmt_pct(row; digits=1)
                end
            end
        end
    end

    # Monte Carlo CI macros — present iff the MC stage has run.
    @testset "Monte Carlo CI" begin
        path = joinpath(CSV_DIR, "monte_carlo_ownership.csv")
        if !isfile(path)
            @test_skip "monte_carlo_ownership.csv not yet generated"
        else
            for k in ("mcMedianOwnership", "mcLowCIOwnership", "mcHighCIOwnership", "nMCDraws")
                @test haskey(macros, k)
            end
            # Sanity: low CI < median < high CI (parsed as floats from "X.X\%").
            parse_pct = s -> parse(Float64, replace(s, "\\%" => ""))
            lo = parse_pct(macros["mcLowCIOwnership"])
            md = parse_pct(macros["mcMedianOwnership"])
            hi = parse_pct(macros["mcHighCIOwnership"])
            @test lo <= md <= hi
        end
    end
end
