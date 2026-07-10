# Stage-1 config-lock gate. Pins the production calibration constants, the
# observed SS+DB income floor identity, and the legacy ss_benefit() mirror.
# Also guards that ModelParams struct defaults stay at their neutral/off state:
# the Lockwood and Pashchenko replications rely on bare constructors inheriting
# health_utility=[1,1,1] and chi_ltc=1.0, so flipping a default to a production
# value would silently activate a channel and break those replications.
#
# Run standalone (module re-include conflicts otherwise):
#   julia --project=. test/test_config_consistency.jl

using Test

include(joinpath(@__DIR__, "..", "src", "AnnuityPuzzle.jl"))
using .AnnuityPuzzle
include(joinpath(@__DIR__, "..", "scripts", "config.jl"))

@testset "Production calibration constants (config.jl)" begin
    @test CHI_LTC == 0.49
    @test C_FLOOR == 6_180.0
    @test HEALTH_UTILITY == [1.0, 0.92, 0.82]
    @test MWR_LOADED == 0.87
    @test GAMMA == 2.5
    @test HAZARD_NORMALIZE == true
    @test HAZARD_MULT == [0.50, 1.0, 3.75]
    @test BETA == 0.97
    @test R_RATE == 0.02
    @test SURVIVAL_PESSIMISM == 0.96
    @test CONSUMPTION_DECLINE == 0.02
    @test LAMBDA_W == 0.625
    @test PSI_PURCHASE == 0.05
end

@testset "Observed SS + DB income floor (2014 dollars)" begin
    @test SS_OBS == [13_018.0, 13_648.0, 14_517.0, 14_896.0]
    @test DB_OBS == [5_266.0, 7_540.0, 11_407.0, 11_977.0]
    # SS_QUARTILE_LEVELS is defined once as SS_OBS + DB_OBS (no hardcoded sum).
    @test SS_QUARTILE_LEVELS == SS_OBS .+ DB_OBS
    @test SS_QUARTILE_LEVELS == [18_284.0, 21_188.0, 25_924.0, 26_873.0]
    @test SS_QUARTILE_BREAKS == [30_000.0, 120_000.0, 350_000.0]
    # Constants must match the regenerated calibration CSV.
    csv = readlines(joinpath(@__DIR__, "..", "data", "processed", "ss_income_profile.csv"))
    @test length(csv) == 5  # header + 4 bins
    for b in 1:4
        toks = split(csv[b + 1], ',')
        @test round(parse(Float64, toks[6])) == SS_OBS[b]   # obs_ss_claimers
        @test round(parse(Float64, toks[8])) == DB_OBS[b]   # obs_db_ipen
    end
end

@testset "Legacy ss_benefit() mirrors SS_QUARTILE_LEVELS" begin
    p = ModelParams()
    @test [ss_benefit(q, p) for q in 1:4] == SS_QUARTILE_LEVELS
end

@testset "Struct defaults stay neutral (replication-integrity guard)" begin
    d = ModelParams()
    @test d.chi_ltc == 1.0                       # public-care aversion off
    @test d.health_utility == [1.0, 1.0, 1.0]    # state-dependent utility off
    @test d.lambda_w == 1.0                      # SDU off
    @test d.psi_purchase == 0.0                  # PED off
    @test d.consumption_decline == 0.0           # age-varying needs off
    @test d.c_floor == 3_000.0                   # NOT the production 6180; bare
                                                 # callers (survival/grid builders,
                                                 # Lockwood/Pashchenko) must keep
                                                 # the legacy default.
end

@testset "No fabricated public-care-aversion citation in config.jl" begin
    cfg_text = read(joinpath(@__DIR__, "..", "scripts", "config.jl"), String)
    @test !occursin("ECMA", cfg_text)
    @test !occursin("CI roughly", cfg_text)
    @test !occursin("central estimate is 0.5", cfg_text)
    @test !occursin("2011 QJE", cfg_text)
end

println("\nAll config-consistency assertions passed.")
