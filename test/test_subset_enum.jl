# Unit tests for the shared subset-enumeration / Shapley machinery
# (src/subset_enum.jl), extracted so run_subset_enumeration.jl and
# run_shapley_gamma_stability.jl share one implementation.
#
# Run standalone:
#   julia --project=. test/test_subset_enum.jl

using Test

include(joinpath(@__DIR__, "..", "src", "AnnuityPuzzle.jl"))
using .AnnuityPuzzle

@testset "bitmask_to_channels" begin
    @test bitmask_to_channels(0) == Set{Int}()
    @test bitmask_to_channels(1) == Set([1])          # bit 0 -> channel 1
    @test bitmask_to_channels(5) == Set([1, 3])       # bits 0,2 -> channels 1,3
    @test bitmask_to_channels(2047) == Set(1:11)      # all 11 channels
    @test bitmask_to_channels(511) == Set(1:9)        # 9-channel structural subset
end

@testset "build_subset_config toggling" begin
    kw = (theta_dfj=56.96, kappa_dfj=272_628.0, mwr_loaded=0.87,
          fixed_cost=2_500.0, min_purchase=10_000.0, inflation_val=0.02,
          survival_pessimism=0.96, ss_quartile_levels=[12_917.0, 15_747.0, 19_298.0, 19_335.0],
          consumption_decline=0.02, health_utility=[1.0, 0.92, 0.82], chi_ltc_val=0.49,
          lambda_w_val=0.625, psi_purchase_val=0.05, psi_purchase_c_ref_val=18_000.0,
          fair_pr=0.065)

    # Empty coalition: every channel off / neutral.
    off = build_subset_config(Set{Int}(); kw...)
    @test off.ss_levels == [0.0, 0.0, 0.0, 0.0]
    # SS off: its actuarial PV is commuted to an equal-PV liquid endowment
    # (ss_quartile_levels / fair_pr), so the SS player is a share-shift.
    @test off.w_commuted ≈ [12_917.0, 15_747.0, 19_298.0, 19_335.0] ./ 0.065
    @test off.theta == 0.0 && off.kappa == 0.0
    @test off.medical_enabled == false && off.health_mortality_corr == false
    @test off.survival_pessimism == 1.0
    @test off.mwr == 1.0 && off.fixed_cost == 0.0 && off.min_purchase == 0.0
    @test off.inflation_rate == 0.0
    @test off.chi_ltc == 1.0 && off.lambda_w == 1.0 && off.psi_purchase == 0.0
    @test off.consumption_decline == 0.0 && off.health_utility == [1.0, 1.0, 1.0]

    # SS only (channel 1). SS on => annuitized income present, no wealth
    # commutation.
    ss = build_subset_config(Set([1]); kw...)
    @test ss.ss_levels == [12_917.0, 15_747.0, 19_298.0, 19_335.0]
    @test ss.w_commuted == [0.0, 0.0, 0.0, 0.0]
    @test ss.theta == 0.0

    # fair_pr is required for the commuted-PV counterfactual.
    @test_throws UndefKeywordError build_subset_config(Set{Int}();
        theta_dfj=56.96, kappa_dfj=272_628.0, mwr_loaded=0.87, fixed_cost=2_500.0,
        min_purchase=10_000.0, inflation_val=0.02, survival_pessimism=0.96,
        ss_quartile_levels=[12_917.0, 15_747.0, 19_298.0, 19_335.0],
        consumption_decline=0.02, health_utility=[1.0, 0.92, 0.82], chi_ltc_val=0.49,
        lambda_w_val=0.625, psi_purchase_val=0.05, psi_purchase_c_ref_val=18_000.0)

    # Bequests only (channel 2).
    beq = build_subset_config(Set([2]); kw...)
    @test beq.theta == 56.96 && beq.kappa == 272_628.0

    # Combined medical + R-S (channel 3) flips both flags.
    med = build_subset_config(Set([3]); kw...)
    @test med.medical_enabled == true && med.health_mortality_corr == true

    # Full coalition: all channels on at calibration values.
    full = build_subset_config(Set(1:11); kw...)
    @test full.theta == 56.96
    @test full.mwr == 0.87 && full.fixed_cost == 2_500.0 && full.min_purchase == 10_000.0
    @test full.inflation_rate == 0.02
    @test full.survival_pessimism == 0.96
    @test full.consumption_decline == 0.02 && full.health_utility == [1.0, 0.92, 0.82]
    @test full.chi_ltc == 0.49 && full.lambda_w == 0.625 && full.psi_purchase == 0.05
end

@testset "exact_shapley on known games" begin
    # Additive 2-channel game: channel 1 drops 0.3, channel 2 drops 0.2, no
    # interaction. Each channel's Shapley equals its own drop.
    add = Dict(0 => 1.0, 1 => 0.7, 2 => 0.8, 3 => 0.5)
    sh = exact_shapley(2, add)
    @test isapprox(sh[1], 0.3; atol=1e-12)
    @test isapprox(sh[2], 0.2; atol=1e-12)
    @test isapprox(sum(sh), add[0] - add[3]; atol=1e-12)  # efficiency

    # Super-additive game: combined drop (0.6) exceeds the sum of singles (0.5).
    sup = Dict(0 => 1.0, 1 => 0.7, 2 => 0.8, 3 => 0.4)
    sh2 = exact_shapley(2, sup)
    @test isapprox(sh2[1], 0.35; atol=1e-12)
    @test isapprox(sh2[2], 0.25; atol=1e-12)
    @test isapprox(sum(sh2), sup[0] - sup[3]; atol=1e-12)  # efficiency holds
end

println("\nAll subset_enum unit tests passed.")
