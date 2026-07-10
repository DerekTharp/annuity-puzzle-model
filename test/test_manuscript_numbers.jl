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

include(joinpath(@__DIR__, "..", "scripts", "config.jl"))  # parse_csv_row for quoted CSVs

const TEST_DIR = @__DIR__
const REPO_ROOT = dirname(TEST_DIR)
const NUMBERS_TEX = joinpath(REPO_ROOT, "paper", "numbers.tex")
const CSV_DIR = joinpath(REPO_ROOT, "tables", "csv")

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
    for (i, line) in enumerate(eachline(path))
        i == 1 && continue
        isempty(strip(line)) && continue
        f = parse_csv_row(line)
        length(f) >= 7 && f[1] == scenario || continue
        return parse(Float64, f[7])  # ownership_pct
    end
    error("scenario $(repr(scenario)) not in welfare_counterfactuals.csv")
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
    # Loads-split and blended-mortality macros must match their CSVs.
    @testset "loads-split + blended-mortality locks" begin
        sp = joinpath(CSV_DIR, "shapley_loads_split.csv")
        bp = joinpath(CSV_DIR, "shapley_male_mortality.csv")
        if !isfile(sp) || !isfile(bp)
            @test_skip "batch Shapley CSVs absent (stages 10d/10e not yet run)"
        else
            sraw, _ = readdlm(sp, ',', Any; header=true)
            sv = Dict(String(sraw[r, 1]) => Float64(sraw[r, 2]) for r in 1:size(sraw, 1))
            @test macros["splitMWRWedge"]    == fmt_num(sv["MWR wedge"];    digits=1)
            @test macros["splitFixedCost"]   == fmt_num(sv["Fixed cost"];   digits=1)
            @test macros["splitMinPurchase"] == fmt_num(sv["Min purchase"]; digits=1)
            @test macros["splitBequests"]    == fmt_num(sv["Bequests"];     digits=1)
            @test macros["splitFullOwn"]     == fmt_pct(Float64(sraw[1, 4]); digits=1)
            # Full coalition must reproduce the nine-channel headline level
            # exactly at common rounding (strict equality; substring matches
            # can accept coincidences like 7.9% inside 17.9%).
            @test macros["splitFullOwn"] == macros["ownNineChannelLTC"]
            # The wedge must remain the largest suppressor among positives
            pos = [v for (k, v) in sv if v > 0]
            @test sv["MWR wedge"] == maximum(pos)

            braw, _ = readdlm(bp, ',', Any; header=true)
            bv = Dict(String(braw[r, 1]) => Float64(braw[r, 2]) for r in 1:size(braw, 1))
            @test macros["maleTableLoads"]    == fmt_num(bv["Loads"];    digits=1)
            @test macros["maleTableBequests"] == fmt_num(bv["Bequests"]; digits=1)
            @test macros["maleTableOwn"]      == fmt_pct(Float64(braw[1, 4]); digits=1)
            bpos = [v for (k, v) in bv if v > 0]
            @test bv["Loads"] == maximum(bpos)
        end
    end

    # Period-certain pricing macros must match period_certain_pricing.csv.
    @testset "period-certain pricing lock" begin
        path = joinpath(CSV_DIR, "period_certain_pricing.csv")
        if !isfile(path)
            @test_skip "period_certain_pricing.csv absent"
        else
            for line in eachline(path)
                startswith(line, "convention") && continue
                f = split(line, ',')
                red = parse(Float64, f[4])
                key = f[1] == "nominal" ? "pctPeriodCertainCutNom" : "pctPeriodCertainCutReal"
                @test macros[key] == fmt_pct(red; digits=1)
            end
        end
    end

    @testset "HRS observed ownership" begin
        for k in ("pctHRSIannPooled", "pctHRSLifetime")
            @test haskey(macros, k)
        end

        # Value locks: point estimates from the person-wave POOLED row; CIs
        # are Wilson intervals at the person-wave rate evaluated at the
        # person-level effective sample size (unique persons from the by-band
        # CSV). Mirrors the export logic so numbers.tex cannot silently
        # desync from the CSVs.
        life_csv = joinpath(REPO_ROOT, "data", "processed", "hrs_lifetime_ownership.csv")
        band_csv = joinpath(REPO_ROOT, "data", "processed", "hrs_lifetime_ownership_by_band.csv")
        if !isfile(life_csv) || !isfile(band_csv)
            @test_skip "HRS ownership CSVs absent"
        else
            n_life_persons = 0
            for (i, line) in enumerate(eachline(band_csv))
                i == 1 && continue
                isempty(strip(line)) && continue
                f = split(line, ',')
                n_life_persons += parse(Int, f[10])
            end
            pooled = ""
            for line in eachline(life_csv)
                startswith(line, "POOLED,") && (pooled = line)
            end
            toks = split(chopprefix(pooled, "POOLED,"), ',')
            n_elig = parse(Int, toks[1])
            n_iann = parse(Int, toks[2])
            n_lifetime = parse(Int, toks[4])
            n_persons = parse(Int, toks[8])
            kish_neff = parse(Float64, toks[9])

            function wilson(phat, n; z=1.96)
                denom = 1 + z^2 / n
                center = (phat + z^2 / (2n)) / denom
                hw = z * sqrt(phat * (1 - phat) / n + z^2 / (4 * n^2)) / denom
                return (center - hw, center + hw)
            end
            lo_l, hi_l = wilson(n_lifetime / n_elig, kish_neff)
            lo_i, hi_i = wilson(n_iann / n_elig, kish_neff)
            @test macros["pctHRSLifetime"] == fmt_pct(100 * n_lifetime / n_elig; digits=2)
            @test macros["pctHRSIannPooled"] == fmt_pct(100 * n_iann / n_elig; digits=2)
            @test macros["pctHRSLifetimeCILow"]  == fmt_pct(100 * lo_l; digits=2)
            @test macros["pctHRSLifetimeCIHigh"] == fmt_pct(100 * hi_l; digits=2)
            @test macros["pctHRSIannCILow"]  == fmt_pct(100 * lo_i; digits=2)
            @test macros["pctHRSIannCIHigh"] == fmt_pct(100 * hi_i; digits=2)
            @test macros["nHRSPersons"] == "1,502"
            @test macros["nHRSLifetimeOwnersPersons"] == string(n_life_persons)
            @test macros["pctHRSLifetimePersonLevel"] == fmt_pct(100 * n_life_persons / n_persons; digits=2)
        end
    end

    # Extensive-margin gate F* macros must match fstar_distribution.csv exactly
    # (guards against numbers.tex/CSV divergence; mirrors the export logic).
    @testset "extensive-margin gate F* distribution" begin
        fpath = joinpath(CSV_DIR, "fstar_distribution.csv")
        if !isfile(fpath)
            @test_skip "fstar_distribution.csv absent"
        else
            rows, hdr = readdlm(fpath, ',', Any; header=true)
            hdr = vec(hdr); col(n) = findfirst(==(n), hdr)
            band = strip.(string.(rows[:, col("band")])); bi(l) = findfirst(==(l), band)
            fz = Float64.(rows[:, col("frac_fstar_zero")])
            fmid = Float64.(rows[:, col("frac_fstar_below_fc")])
            for (name, frac) in (("gateFstarZeroBandOne",   fz[bi("<30k")]),
                                 ("gateFstarZeroBandTwo",   fz[bi("30-120k")]),
                                 ("gateFstarZeroBandThree", fz[bi("120-350k")]),
                                 ("gateFstarSliverBandTwo", fmid[bi("30-120k")]))
                @test haskey(macros, name)
                @test macros[name] == fmt_pct(frac * 100; digits=0)
            end
            if col("frac_value_destroying") !== nothing
                fvd  = Float64.(rows[:, col("frac_value_destroying")])
                finf = Float64.(rows[:, col("frac_infeasible")])
                @test macros["gateValDestrBandOne"] == fmt_pct(fvd[bi("<30k")] * 100; digits=0)
                @test macros["gateInfeasBandOne"]   == fmt_pct(finf[bi("<30k")] * 100; digits=0)
            end
        end
    end

    # Baseline MWR pulled from welfare_counterfactuals "Baseline" row
    @testset "baseline MWR" begin
        path = joinpath(CSV_DIR, "welfare_counterfactuals.csv")
        mwr = nothing
        for (i, line) in enumerate(eachline(path))
            i == 1 && continue
            f = parse_csv_row(line)
            length(f) >= 2 && f[1] == "Baseline" || continue
            mwr = parse(Float64, f[2])  # mwr column
            break
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

    # Bracket-hostage assertion: the JRI headline ownership prediction (the
    # 9-channel structural baseline, ownNoBehavioralBaseline) is expected to land
    # in a plausible range. If a future recalibration silently moves it outside
    # the range, this fires loudly so the manuscript prose can be updated to match
    # (rather than the prose drifting while the headline silently re-anchors).
    #
    # NOTE (Stage 5): the bracket below is provisional, keyed to the pre-re-solve
    # 9-channel structural baseline (~6.8%). Re-tighten to the re-solved
    # structural ownership after the production AWS run.
    @testset "headline bracket-hostage assertion" begin
        # JRI headline: 9-channel structural baseline (no behavioral channels).
        # NOT ownModelOne (the 11-channel full model is ~0% under PED annihilation).
        headline_keys = ("ownNoBehavioralBaseline",)
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

# ---------------------------------------------------------------------------
# New-exhibit integrity: the three tables added in the 2026-07 revision carry
# baked-in inferential statistics and endpoint values. Recompute each from its
# CSV inputs and require the emitted .tex to contain the same rendered value.
# ---------------------------------------------------------------------------
using Distributions: Normal, Hypergeometric, cdf, pdf

@testset "new-exhibit statistics integrity" begin
    tex_dir = joinpath(REPO_ROOT, "tables", "tex")
    csv_dir = joinpath(REPO_ROOT, "tables", "csv")

    @testset "model_vs_data_band: person-level CA/Wilson/Fisher" begin
        path = joinpath(REPO_ROOT, "data", "processed", "hrs_lifetime_ownership_by_band.csv")
        tex  = read(joinpath(tex_dir, "model_vs_data_band.tex"), String)
        raw, hdr = readdlm(path, ',', Any; header=true)
        c(name) = findfirst(==(name), vec(hdr))
        np = Int.(raw[:, c("n_persons")]); op = Int.(raw[:, c("n_lifetime_persons")])
        # Cochran-Armitage trend
        t = Float64.(1:4); N = sum(np); pbar = sum(op) / N; tbar = sum(t .* np) / N
        z = sum(t[i] * (op[i] - np[i] * pbar) for i in 1:4) /
            sqrt(pbar * (1 - pbar) * sum(np[i] * (t[i] - tbar)^2 for i in 1:4))
        @test occursin("z=$(round(z, digits=2))", replace(tex, "\$" => ""))
        # Pooled interior Wilson CI
        k = sum(op[1:3]); n = sum(np[1:3]); zc = 1.96; ph = k / n
        ctr = (ph + zc^2 / (2n)) / (1 + zc^2 / n)
        hw  = (zc / (1 + zc^2 / n)) * sqrt(ph * (1 - ph) / n + zc^2 / (4n^2))
        lo = round(100 * (ctr - hw), digits=2); hi = round(100 * (ctr + hw), digits=2)
        @test occursin("[$(lo)\\%, $(hi)\\%]", tex)
    end

    @testset "band_value_destruction endpoints" begin
        raw, _ = readdlm(joinpath(csv_dir, "band_value_destruction_diagnostic.csv"), ',', Any; header=true)
        tex = read(joinpath(tex_dir, "band_value_destruction.tex"), String)
        vals = Dict((strip(String(raw[r, 1])), Int(raw[r, 2])) => Float64(raw[r, 3]) for r in 1:size(raw, 1))
        for (cfg, b) in [("Full structural", 3), ("- Pricing loads (MWR)", 3), ("- Survival pessimism", 3)]
            v = round(vals[(cfg, b)], digits=1)
            @test occursin("$(v)\\%", tex)
        end
        # The note's causal claim requires loads to be the largest band-3 lift
        base3 = vals[("Full structural", 3)]
        lifts = [(cfg, v - base3) for ((cfg, b), v) in vals if b == 3 && cfg != "Full structural"]
        @test argmax(last, lifts)[1] == "- Pricing loads (MWR)"
    end

    @testset "partition_robustness: loads top suppressor in both panels" begin
        tex = read(joinpath(tex_dir, "partition_robustness.tex"), String)
        for panel in split(tex, "Panel ")[2:end]
            rows = [m for m in eachmatch(r"([A-Za-z+\-\\ ]+) & ([+\-][0-9.]+) & (\d+)", panel)]
            isempty(rows) && continue
            top = argmax(r -> parse(Float64, r.captures[2]), rows)
            @test occursin("Loads", top.captures[1])
        end
    end
end

@testset "two-product extension integrity" begin
    csv_dir2 = joinpath(REPO_ROOT, "tables", "csv")
    g, gh = readdlm(joinpath(csv_dir2, "two_product_gradient.csv"), ',', Any; header=true)
    c, ch = readdlm(joinpath(csv_dir2, "two_product_ss_cut.csv"), ',', Any; header=true)
    gc(n) = findfirst(==(n), vec(gh)); cc2(n) = findfirst(==(n), vec(ch))
    # Mixture identity: mixture = access*group + (1-access)*retail, per band
    for b in 1:4
        acc = Float64(g[b, gc("access_pct")]) / 100
        mixv = acc * Float64(g[b, gc("group_pct")]) + (1 - acc) * Float64(g[b, gc("retail_pct")])
        @test isapprox(mixv, Float64(g[b, gc("mixture_pct")]); atol=0.01)
    end
    # Cut-table baseline consistency with the gradient table
    for b in 1:4
        @test isapprox(Float64(c[b, cc2("mixture_base_pct")]),
                       Float64(g[b, gc("mixture_pct")]); atol=0.01)
    end
    # Emitted tex carries the CSV values
    tex2 = read(joinpath(REPO_ROOT, "tables", "tex", "two_product.tex"), String)
    for b in 1:4
        @test occursin(@sprintf("%.2f", Float64(g[b, gc("mixture_pct")])), tex2)
        @test occursin(@sprintf("%+.2f", Float64(c[b, cc2("response_pp")])), tex2)
    end
    # Access rates match the committed coverage calibration
    acc_c, ah = readdlm(joinpath(REPO_ROOT, "data", "processed", "group_access_by_band.csv"),
                        ',', Any; header=true)
    for b in 1:4
        @test isapprox(Float64(g[b, gc("access_pct")]),
                       100 * Float64(acc_c[b, findfirst(==("access_unw"), vec(ah))]); atol=0.01)
    end
end

@testset "v1.6 artifacts: forced-65 + Panel C locks" begin
    fa_path = joinpath(REPO_ROOT, "tables", "csv", "forced_age65_shapley.csv")
    if !isfile(fa_path)
        @test_skip "forced_age65_shapley.csv absent (Stage 10g not yet run)"
    else
        fa, _ = readdlm(fa_path, ',', Any; header=true)
        @test macros["forcedAgeOwn"] == fmt_pct(Float64(fa[1, 4]); digits=1)
        v = Dict(String(fa[r, 1]) => Float64(fa[r, 2]) for r in 1:size(fa, 1))
        @test v["Loads"] > v["Bequests"]  # ranking preserved under forced age
        @test argmax(last, collect(v))[1] == "Loads"
    end
    cev, ch = readdlm(joinpath(REPO_ROOT, "tables", "csv", "cev_counterfactuals.csv"), ',', Any; header=true)
    @test String(ch[1]) == "bequest_spec"          # new schema present
    @test size(cev, 1) == 30                        # both specs, 15 rows each
    # Direct CSV read (the schema-aware helper lives in the export script)
    best_col = findfirst(==("cev_best_feasible"), vec(ch))
    row = findfirst(r -> String(cev[r, 1]) == "none" && Int(cev[r, 2]) == 1_000_000 &&
                         String(cev[r, 3]) == "Good", 1:size(cev, 1))
    @test row !== nothing
    @test macros["cevNoBqOneMillBestFeas"] == fmt_pct(Float64(cev[row, best_col]) * 100; digits=1)
end
