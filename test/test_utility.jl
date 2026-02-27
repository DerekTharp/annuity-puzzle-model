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
