# Axiom tests for the exact Shapley engine (src/subset_enum.jl exact_shapley),
# the order-independent channel-ranking machinery the paper's central claim rests
# on. The existing suite only exercised it on a 2-channel game; this verifies the
# four defining Shapley axioms on the production-size 9-channel game with several
# synthetic value functions.
#
# Convention note: exact_shapley uses the marginal contribution v(S) - v(S∪{i})
# (a channel's contribution to LOWERING ownership), so the efficiency identity is
# sum_i phi_i = v(empty) - v(grand), not v(grand) - v(empty).

using Test

include(joinpath(@__DIR__, "..", "src", "AnnuityPuzzle.jl"))
using .AnnuityPuzzle

const N = 9
bits_of(m) = [i for i in 1:N if (m & (1 << (i - 1))) != 0]
make_lookup(f) = Dict{Int, Float64}(m => f(m) for m in 0:((1 << N) - 1))

@testset "Exact Shapley axioms (9-channel game)" begin
    # A generic additive + pairwise value function (deterministic, no RNG).
    a = [0.1 * i for i in 1:N]
    b = [0.01 * (i + j) for i in 1:N, j in 1:N]
    f(m) = (isempty(bits_of(m)) ? 0.0 : sum(a[i] for i in bits_of(m))) +
           sum((i < j ? b[i, j] : 0.0) for i in bits_of(m) for j in bits_of(m); init = 0.0)
    lk = make_lookup(f)
    phi = exact_shapley(N, lk)

    # EFFICIENCY: sum of Shapley values telescopes to v(empty) - v(grand).
    @test sum(phi) ≈ (lk[0] - lk[(1 << N) - 1]) atol = 1e-9

    # NULL PLAYER: a channel whose marginal contribution is always zero gets 0.
    nbit = 1 << (N - 1)
    g(m) = f(m & ~nbit)                       # value ignores channel N entirely
    phi_null = exact_shapley(N, make_lookup(g))
    @test abs(phi_null[N]) < 1e-9

    # SYMMETRY: two interchangeable channels receive equal Shapley value.
    swap12(m) = (m & ~3) | (((m >> 0) & 1) << 1) | (((m >> 1) & 1) << 0)  # ~3 is Int64; ~0b11 would be UInt8(252) and clear bit 8
    h(m) = 0.5 * (f(m) + f(swap12(m)))       # symmetrize over channels 1 and 2
    phi_sym = exact_shapley(N, make_lookup(h))
    @test phi_sym[1] ≈ phi_sym[2] atol = 1e-9

    # ADDITIVITY / LINEARITY: phi(v + w) = phi(v) + phi(w).
    a2 = [0.07 * (N - i) for i in 1:N]
    f2(m) = isempty(bits_of(m)) ? 0.0 : sum(a2[i] for i in bits_of(m))
    lk2 = make_lookup(f2)
    lk_sum = Dict{Int, Float64}(m => lk[m] + lk2[m] for m in keys(lk))
    @test exact_shapley(N, lk_sum) ≈ (exact_shapley(N, lk) .+ exact_shapley(N, lk2)) atol = 1e-9

    # Shapley weights for a fixed channel sum to 1 (probability distribution over
    # coalition sizes): a pure additive game assigns each channel exactly its own
    # additive value.
    phi_add = exact_shapley(N, lk2)
    for i in 1:N
        # negated-marginal convention; atol absorbs FP accumulation over 256
        # factorial-weighted terms (the engine is exact, the sum is not bit-exact).
        @test phi_add[i] ≈ -a2[i] atol = 1e-7
    end

    println("Exact Shapley axioms passed.")
end
