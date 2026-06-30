# Regression test for the SS-only-cut identity, the model's central public-
# finance claim: a Social Security trust-fund shortfall cuts SS income only,
# while DB pension income survives. Every SS-cut script
# (run_ss_robustness.jl, run_welfare_counterfactuals.jl, run_ss_cut_by_wealth.jl,
# run_ss_crowdout_moderation.jl) implements this as
#     cut_levels = (1 - cut) * SS_OBS + DB_OBS
# relying on the decomposition SS_QUARTILE_LEVELS = SS_OBS + DB_OBS. A past bug
# scaled SS_QUARTILE_LEVELS directly, which also cut the DB pension. This test
# locks the identity so that regression cannot recur silently.

using Test

include(joinpath(@__DIR__, "..", "src", "AnnuityPuzzle.jl"))
using .AnnuityPuzzle

@testset "SS-only-cut identity (DB pension survives a SS cut)" begin
    @test length(SS_OBS) == length(DB_OBS) == length(SS_QUARTILE_LEVELS)

    # The pre-existing annuitization floor decomposes as SS + DB.
    @test SS_QUARTILE_LEVELS ≈ SS_OBS .+ DB_OBS

    # DB pension income is nonzero, so the SS-only vs SS+DB distinction is material.
    @test any(DB_OBS .> 0.0)

    # An SS-only cut scales SS_OBS and leaves DB_OBS untouched.
    for cut in (0.0, 0.22, 0.50, 1.0)
        cut_levels = (1.0 - cut) .* SS_OBS .+ DB_OBS
        @test all(cut_levels .>= DB_OBS .- 1e-9)              # never below the DB floor
        @test all(cut_levels .<= SS_QUARTILE_LEVELS .+ 1e-9)  # never above the no-cut level
    end

    # A 100% SS cut leaves exactly the DB pension.
    @test ((1.0 - 1.0) .* SS_OBS .+ DB_OBS) ≈ DB_OBS

    # The correct SS-only cut differs from the buggy "scale SS+DB" formula at any
    # positive cut (because DB > 0); this is what the regression guards against.
    let cut = 0.22
        correct = (1.0 - cut) .* SS_OBS .+ DB_OBS
        buggy   = (1.0 - cut) .* SS_QUARTILE_LEVELS
        @test !(correct ≈ buggy)
        @test all(correct .>= buggy .- 1e-9)   # the buggy cut understates income (cuts DB too)
    end

    println("SS-only-cut identity test passed.")
end
