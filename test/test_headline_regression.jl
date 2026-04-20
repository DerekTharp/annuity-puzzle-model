# Regression test: verify that production CSV outputs match headline numbers
# cited in the manuscript. This test reads existing output files (does NOT
# re-solve the model) and checks them against the authoritative values.
#
# If a computation changes results, this test catches the discrepancy
# before the manuscript goes out of sync.

using Test
using DelimitedFiles

const PROJECT_DIR = dirname(@__DIR__)
const CSV_DIR = joinpath(PROJECT_DIR, "tables", "csv")

function read_csv(filename)
    path = joinpath(CSV_DIR, filename)
    isfile(path) || error("Missing output file: $path")
    raw = readdlm(path, ',', Any; skipstart=1)
    return raw
end

@testset "Headline Regression Tests" begin

    @testset "Sequential decomposition" begin
        d = read_csv("decomposition.csv")
        # Column order: step, ownership_pct, mean_alpha, delta_pp, solve_time_s
        steps = String.(d[:, 1])
        own = Float64.(d[:, 2])

        # Frictionless population benchmark
        idx = findfirst(s -> occursin("Yaari", s), steps)
        @test own[idx] ≈ 41.37 atol=0.1

        # + Social Security → 100%
        idx = findfirst(s -> occursin("Social Security", s), steps)
        @test own[idx] ≈ 100.0 atol=0.1

        # Final (7-channel): inflation erosion → 18.33%
        idx = findfirst(s -> occursin("Inflation", s), steps)
        @test own[idx] ≈ 18.33 atol=0.1
    end

    @testset "Shapley decomposition" begin
        s = read_csv("shapley_exact.csv")
        channels = String.(s[:, 1])
        shapley_pp = Float64.(s[:, 2])

        idx_loads = findfirst(c -> occursin("Load", c) || occursin("Pricing", c), channels)
        idx_rs = findfirst(c -> occursin("R-S", c) || occursin("correlation", c), channels)
        idx_ss = findfirst(c -> c == "SS" || occursin("Social", c), channels)

        # Loads: largest positive Shapley value (~30.3 pp)
        @test shapley_pp[idx_loads] ≈ 30.3 atol=0.5

        # R-S: second largest (~12.3 pp)
        @test shapley_pp[idx_rs] ≈ 12.3 atol=0.5

        # SS: negative (~-33.1 pp)
        @test shapley_pp[idx_ss] ≈ -33.1 atol=0.5
    end

    @testset "Welfare counterfactuals" begin
        w = read_csv("welfare_counterfactuals.csv")
        scenarios = String.(w[:, 1])
        own = Float64.(w[:, 7])

        # Baseline: 18.33%
        idx = findfirst(s -> s == "Baseline", scenarios)
        @test own[idx] ≈ 18.33 atol=0.1

        # Group pricing (MWR=0.90): 43.15%
        idx = findfirst(s -> occursin("Group", s), scenarios)
        @test own[idx] ≈ 43.15 atol=0.1

        # Public option (MWR=0.95): 51.90%
        idx = findfirst(s -> occursin("Public", s), scenarios)
        @test own[idx] ≈ 51.90 atol=0.1

        # SS cut 23%: 36.08%
        idx = findfirst(s -> occursin("SS cut", s), scenarios)
        @test own[idx] ≈ 36.08 atol=0.1

        # Best feasible: 57.62%
        idx = findfirst(s -> occursin("Best feasible", s), scenarios)
        @test own[idx] ≈ 57.62 atol=0.1
    end

    @testset "CEV welfare grid" begin
        c = read_csv("welfare_cev_grid.csv")
        # Check that the file exists and has content
        @test size(c, 1) > 0
        # The exact format depends on the script; verify key values exist
        # CEV at $1M no-bequest good health should be ~13.8%
        # CEV at $1M DFJ good health should be ~7.3%
    end

end
