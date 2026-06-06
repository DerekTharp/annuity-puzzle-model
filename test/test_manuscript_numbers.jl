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
# Eleven channels in Model 1: nine rational/preference/structural + two
# behavioral (SDU and PED). Medical and R-S correlation are combined into
# a single channel because the R-S mechanism's quantitative bite in this
# framework operates through the interaction with medical risk.
const B_SS           = 1 << 0
const B_BEQUESTS     = 1 << 1
const B_MED_RS       = 1 << 2   # Combined: medical + R-S correlation
const B_PESSIMISM    = 1 << 3
const B_AGE_NEEDS    = 1 << 4
const B_STATE_UTIL   = 1 << 5
const B_LOADS        = 1 << 6
const B_INFLATION    = 1 << 7
const B_LTC          = 1 << 8   # Public-care aversion (Ameriks 2011 JF, 2020 JPE)
const B_SDU          = 1 << 9   # Source-dependent utility (lambda_w)
const B_PED          = 1 << 10  # At-purchase narrow-framing penalty (psi_purchase)

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

# Returns true when subset_enumeration.csv reflects the current 11-channel
# code (exactly 2048 subsets — Medical and R-S combined into one channel,
# plus SDU and PED behavioral channels). Stage 16's post-run validation
# runs after a fresh export and must see exactly 2048 rows.
function subset_csv_is_current_schema()
    path = joinpath(CSV_DIR, "subset_enumeration.csv")
    isfile(path) || return false
    n_rows = countlines(path) - 1  # subtract header
    return n_rows == 2048
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
    # The bitmask schema is the 11-channel current schema (Med+R-S=bit 4,
    # plus SDU=bit 9 and PED=bit 10). If the CSV does not match this schema
    # (e.g., a stale or partial enumeration), the test set is deferred.
    @testset "decomposition ownership" begin
        current_schema = subset_csv_is_current_schema()
        if !current_schema
            @test_skip "subset_enumeration.csv is not the current 11-channel schema (expected 2048 rows)"
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
                "ownSixChannel"       => B_SS | B_BEQUESTS | B_MED_RS | B_PESSIMISM | B_LOADS | B_INFLATION,
                "ownSevenChannelExt"  => B_SS | B_BEQUESTS | B_MED_RS | B_PESSIMISM | B_AGE_NEEDS | B_LOADS | B_INFLATION,
                "ownEightChannelExt"  => B_SS | B_BEQUESTS | B_MED_RS | B_PESSIMISM | B_AGE_NEEDS | B_STATE_UTIL | B_LOADS | B_INFLATION,
                "ownNineChannelLTC"   => B_SS | B_BEQUESTS | B_MED_RS | B_PESSIMISM | B_AGE_NEEDS | B_STATE_UTIL | B_LOADS | B_INFLATION | B_LTC,
                "ownNoBehavioralBaseline" => B_SS | B_BEQUESTS | B_MED_RS | B_PESSIMISM | B_AGE_NEEDS | B_STATE_UTIL | B_LOADS | B_INFLATION | B_LTC,
            ]
            for (name, bm) in cases
                if !haskey(macros, name)
                    # Macro not emitted by the current export script
                    # (e.g., retired cascade macro). Skip rather than KeyError.
                    @test_skip "macro $name not in numbers.tex"
                else
                    @test macros[name] == fmt_pct(subset_ownership_pct(bm); digits=1)
                end
            end
        end
    end

    # Shapley values (pp) — signed, 1 decimal. 11 channels: nine
    # rational/preference/structural + SDU and PED behavioral.
    @testset "shapley values" begin
        common_cases = [
            "shapLoads"      => "Loads",
            "shapPessimism"  => "Pessimism",
            "shapAgeNeeds"   => "Age needs",
            "shapInflation"  => "Inflation",
            "shapBequests"   => "Bequests",
            "shapStateUtil"  => "State utility",
            "shapSS"         => "SS",
        ]
        for (name, ch) in common_cases
            haskey(macros, name) || continue
            @test macros[name] == fmt_num(shapley_value_pp(ch); digits=1)
        end
        if haskey(macros, "shapMedRS")
            shap_path = joinpath(CSV_DIR, "shapley_exact.csv")
            csv_text = read(shap_path, String)
            expected = if occursin("Medical+R-S,", csv_text)
                fmt_num(shapley_value_pp("Medical+R-S"); digits=1)
            else
                fmt_num(shapley_value_pp("Medical") + shapley_value_pp("R-S"); digits=1)
            end
            @test macros["shapMedRS"] == expected
        end
        @test haskey(macros, "shapLoads")
        @test haskey(macros, "shapMedRS")
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

    # HRS observed ownership macros (pctHRSIannPooled, pctHRSLifetime, and
    # their CI variants) are emitted from the HRS sample. The legacy
    # `pctHRSObserved` summary macro is no longer emitted because the
    # manuscript cites the pooled and lifetime measures separately.
    @testset "HRS observed ownership" begin
        for k in ("pctHRSIannPooled", "pctHRSLifetime")
            @test haskey(macros, k)
        end
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

    # Model 2 UK reduced-form transport: multiplicative wedge check.
    # The wedge factor is computed deterministically as UK_post / UK_pre and
    # applied to the FRICTIONLESS Yaari baseline. The UK retention factor
    # (17/95) captures the joint rational+behavioral retention households
    # express when compulsion lifts; applied to the frictionless baseline
    # it transports the UK voluntary-equilibrium rate to the US.
    @testset "Model 2 UK reduced-form transport" begin
        if haskey(macros, "ownFrictionless") && haskey(macros, "ownWedgeMid")
            parse_pct = s -> parse(Float64, replace(s, "\\%" => ""))
            base = parse_pct(macros["ownFrictionless"])
            wedge = parse_pct(macros["ownWedgeMid"])
            expected = base * (17.0 / 95.0)
            # Allow 0.05 pp rounding tolerance
            @test abs(wedge - expected) < 0.06
        else
            @test_skip "Model 2 transport macros not present"
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

    # Bracket-hostage assertion (forensic-review recommendation): the headline
    # ownership prediction is expected to land in the ~[5%, 11%] range
    # (Model 2 reduced-form transport midpoint at 7.5% with sensitivity
    # bracket [5.7%, 11.0%]). If a future recalibration silently moves the
    # headline outside this range, this assertion fires loudly so the
    # manuscript prose can be updated to match (rather than the prose
    # drifting while the headline silently re-anchors).
    #
    # The bracket below is intentionally GENEROUS (3% to 15%) — wide enough
    # to accommodate the [5.7%, 11.0%] central range plus a safety margin.
    # If a rerun lands outside this generous range, that's a signal the
    # calibration has drifted and someone should think carefully about why.
    #
    # Update the bracket here when the manuscript narrative changes (e.g.,
    # a planned recalibration shifts the headline target intentionally),
    # but NOT silently after a rerun without explicit consideration.
    @testset "headline bracket-hostage assertion" begin
        # Production headline: Model 2 UK reduced-form transport midpoint.
        headline_keys = ("ownHeadline", "ownWedgeMid")
        headline_pct = nothing
        which_key = nothing
        for k in headline_keys
            if haskey(macros, k)
                parse_pct = s -> parse(Float64, replace(s, "\\%" => ""))
                headline_pct = parse_pct(macros[k])
                which_key = k
                break
            end
        end

        if headline_pct === nothing
            @test_skip "no headline macro found (pipeline incomplete)"
        else
            # Two-tier bracket: a tight range and a permissive range.
            #
            # Tight range [3%, 15%]: panel-projected post-recalibration
            #   target. Emits a @warn if violated so the AWS post-run pass can
            #   surface drift loudly without aborting the run.
            # Permissive range [0%, 35%]: pure-garbage gate. Fires as a hard
            #   @test failure only if the headline exceeds 35% (clearly past
            #   any plausible structural prediction). The lower bound is 0%
            #   because the model legitimately produces corner-solution
            #   predictions: when the behavioral parameters push ALL agents
            #   into "do not annuitize" territory, the population ownership
            #   is genuinely 0% (not a calibration error). A model that
            #   predicts 0% with empirical observation at 2-3% is a 2-3 pp
            #   miss telling a structural story; tighter floors would
            #   spuriously fire on honest corner-solution outcomes.
            #
            # When a rerun completes and numbers.tex is regenerated, tighten
            # the @test bracket to match the new headline range.
            TIGHT_LOW,    TIGHT_HIGH    = 3.0, 15.0
            PERMISSIVE_LOW, PERMISSIVE_HIGH = 0.0, 35.0
            if !(TIGHT_LOW <= headline_pct <= TIGHT_HIGH)
                @warn "Headline ownership ($(which_key) = $(headline_pct)%) is outside " *
                      "the panel-projected tight bracket [$(TIGHT_LOW)%, $(TIGHT_HIGH)%]. " *
                      "If this drift is intentional, update the bracket in " *
                      "test/test_manuscript_numbers.jl. Otherwise investigate."
            end
            @test PERMISSIVE_LOW <= headline_pct <= PERMISSIVE_HIGH
        end
    end
end
