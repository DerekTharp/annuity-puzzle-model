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
# Eleven channels: nine rational + two behavioral (SDU + narrow-framing PED).
const B_SS         = 1 << 0
const B_BEQUESTS   = 1 << 1
const B_MEDICAL    = 1 << 2
const B_RS         = 1 << 3
const B_PESSIMISM  = 1 << 4
const B_AGE_NEEDS  = 1 << 5
const B_STATE_UTIL = 1 << 6
const B_LOADS      = 1 << 7
const B_INFLATION  = 1 << 8
const B_SDU          = 1 << 9    # Force A: source-dependent utility
const B_PSI_PURCHASE = 1 << 10   # Force B: narrow-framing purchase penalty

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

# Returns true when subset_enumeration.csv reflects the current 11-channel
# code (2048 subsets). When the CSV is stale (1024 subsets, pre-SDU build),
# tests that assume the new bit layout skip cleanly. Stage 16's post-run
# validation runs AFTER a fresh export and will see 2048 rows, so strict
# checks always run on fresh state.
function subset_csv_is_eleven_channel()
    path = joinpath(CSV_DIR, "subset_enumeration.csv")
    isfile(path) || return false
    n_rows = countlines(path) - 1  # subtract header
    return n_rows >= 2048
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

    # Sequential decomposition: bitmask → ownership percent
    @testset "decomposition ownership" begin
        cases = [
            "ownFrictionless"     => 0,
            "ownAddSS"            => B_SS,
            "ownAddBequests"      => B_SS | B_BEQUESTS,
            "ownAddMedical"       => B_SS | B_BEQUESTS | B_MEDICAL,
            "ownAddRS"            => B_SS | B_BEQUESTS | B_MEDICAL | B_RS,
            "ownAddPessimism"     => B_SS | B_BEQUESTS | B_MEDICAL | B_RS | B_PESSIMISM,
            "ownAddLoads"         => B_SS | B_BEQUESTS | B_MEDICAL | B_RS | B_PESSIMISM | B_LOADS,
            "ownSevenChannel"     => B_SS | B_BEQUESTS | B_MEDICAL | B_RS | B_PESSIMISM | B_LOADS | B_INFLATION,
            "ownEightChannel"     => B_SS | B_BEQUESTS | B_MEDICAL | B_RS | B_PESSIMISM | B_AGE_NEEDS | B_LOADS | B_INFLATION,
            "ownNineChannel"      => B_SS | B_BEQUESTS | B_MEDICAL | B_RS | B_PESSIMISM | B_AGE_NEEDS | B_STATE_UTIL | B_LOADS | B_INFLATION,
            "ownTenChannel"       => B_SS | B_BEQUESTS | B_MEDICAL | B_RS | B_PESSIMISM | B_AGE_NEEDS | B_STATE_UTIL | B_LOADS | B_INFLATION | B_SDU,
            "ownElevenChannel"    => B_SS | B_BEQUESTS | B_MEDICAL | B_RS | B_PESSIMISM | B_AGE_NEEDS | B_STATE_UTIL | B_LOADS | B_INFLATION | B_SDU | B_PSI_PURCHASE,
        ]
        # The two final-layer cases (ownTenChannel = +SDU, ownElevenChannel =
        # +PED) require subset_enumeration.csv to have 2048 rows. Skip them
        # when running pre-pipeline against stale 1024-row CSVs; Stage 16
        # post-run validation will see fresh state and check strictly.
        eleven_ch = subset_csv_is_eleven_channel()
        for (name, bm) in cases
            if !eleven_ch && (name == "ownTenChannel" || name == "ownElevenChannel")
                continue
            end
            @test haskey(macros, name)
            @test macros[name] == fmt_pct(subset_ownership_pct(bm); digits=1)
        end
    end

    # Shapley values (pp) — signed, 1 decimal. Eleven channels: nine
    # rational + Force A (SDU) + Force B (narrow-framing PED).
    @testset "shapley values" begin
        cases = [
            "shapLoads"      => "Loads",
            "shapRS"         => "R-S",
            "shapPessimism"  => "Pessimism",
            "shapAgeNeeds"   => "Age needs",
            "shapInflation"  => "Inflation",
            "shapBequests"   => "Bequests",
            "shapMedical"    => "Medical",
            "shapStateUtil"  => "State utility",
            "shapSS"         => "SS",
            "shapSDU"        => "SDU (Force A)",
            "shapNarrowFraming" => "Narrow framing (Force B)",
        ]
        for (name, ch) in cases
            haskey(macros, name) || continue  # macros for missing channels skip silently
            @test macros[name] == fmt_num(shapley_value_pp(ch); digits=1)
        end
        # Critical channels MUST be present, but the two behavioral channels
        # (shapSDU, shapNarrowFraming) only appear after the 11-channel pipeline
        # has run. Skip when subset CSV is stale; Stage 16 will check strictly.
        eleven_ch = subset_csv_is_eleven_channel()
        for required in ("shapLoads", "shapRS")
            @test haskey(macros, required)
        end
        if eleven_ch
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
            cases = [
                "ownTenChannelPsiRational"          => "Rational benchmark",
                "ownTenChannelPsiLight"             => "Light friction",
                "ownTenChannelPsiBlanchettFinke"    => "Blanchett-Finke",
                "ownTenChannelPsiChalmersReuterMid" => "Chalmers-Reuter mid",
                "ownTenChannelPsiChalmersReuterFull"=> "Chalmers-Reuter full",
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
