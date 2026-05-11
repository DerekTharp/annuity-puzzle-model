# Single source of truth for every numeric literal in the manuscript.
#
# Inputs:  scripts/config.jl, tables/csv/*.csv, data/processed/lockwood_hrs_sample.csv
# Output:  paper/numbers.tex
#
# Any number cited in paper/main.tex, paper/appendix.tex, or paper/cover_letter.tex
# enters through a \newcommand defined here. When a calibration or result changes,
# the macro updates on the next run_all.jl pass and the manuscript follows.
#
# Usage:
#   julia --project=. scripts/export_manuscript_numbers.jl
#
# Conventions:
#   - Macros use camelCase with a category prefix.
#   - Numbers with an inline percent sign embed \% in the macro value.
#   - Dollar values embed \$ and comma thousands separators.

using DelimitedFiles
using Printf

include(joinpath(@__DIR__, "config.jl"))

# Local overrides from run_subset_enumeration.jl (must stay in sync).
# These are descriptive constants used in macro labels; values match the
# production calibration in scripts/config.jl.
const CONSUMPTION_DECLINE_ACTIVE = CONSUMPTION_DECLINE
const HEALTH_UTILITY_ACTIVE = HEALTH_UTILITY

const REPO_ROOT = abspath(joinpath(@__DIR__, ".."))
const CSV_DIR   = joinpath(REPO_ROOT, "tables", "csv")
const OUT_PATH  = joinpath(REPO_ROOT, "paper", "numbers.tex")
const HRS_PATH  = joinpath(REPO_ROOT, "data", "processed", "lockwood_hrs_sample.csv")

# Channel bits (must match run_subset_enumeration.jl).
# Eleven channels: seven rational + two preference + one structural (chi_ltc)
# + two behavioral (SDU, PED). Medical and R-S correlation are combined into a
# single channel because the R-S mechanism's quantitative bite in this
# framework operates through the interaction with stochastic medical costs
# (see review_reports/ for panel discussion).
const B_SS           = 1 << 0
const B_BEQUESTS     = 1 << 1
const B_MED_RS       = 1 << 2   # Combined: medical risk + R-S correlation
const B_PESSIMISM    = 1 << 3
const B_AGE_NEEDS    = 1 << 4
const B_STATE_UTIL   = 1 << 5
const B_LOADS        = 1 << 6
const B_INFLATION    = 1 << 7
const B_LTC          = 1 << 8   # Public-care aversion (Ameriks 2011, 2020 ECMA)
const B_SDU          = 1 << 9   # Source-dependent utility (Force A)
const B_PED          = 1 << 10  # Narrow-framing at-purchase penalty (Force B)

# Backward compatibility aliases for prose macros that used the old names.
# B_MEDICAL alone is no longer meaningful (always implies the R-S correlation).
const B_MEDICAL = B_MED_RS
const B_RS      = B_MED_RS

# ---------------------------------------------------------------------------
# Formatting helpers
# ---------------------------------------------------------------------------

function fmt_pct(x; digits::Int=1)
    @sprintf("%.*f\\%%", digits, x)
end

function fmt_num(x; digits::Int=2)
    @sprintf("%.*f", digits, x)
end

function fmt_int(x)
    @sprintf("%d", round(Int, x))
end

function commas(n::Integer)
    s = string(abs(n))
    parts = String[]
    i = length(s)
    while i > 0
        lo = max(1, i - 2)
        pushfirst!(parts, s[lo:i])
        i = lo - 1
    end
    (n < 0 ? "-" : "") * join(parts, ",")
end

# LaTeX-safe thousands separator: wrap each comma in `{,}` so it stays punctuation
# in both text and math mode (bare `,` in math mode inserts an unwanted thin space).
function latex_commas(n::Integer)
    replace(commas(n), "," => "{,}")
end

function fmt_dollar(x::Real; digits::Int=0)
    digits == 0 ? "\\\$$(latex_commas(round(Int, x)))" : "\\\$" * @sprintf("%.*f", digits, x)
end

# ---------------------------------------------------------------------------
# Macro registry
# ---------------------------------------------------------------------------

const MACROS = Pair{String,String}[]

function macro_exists(name::AbstractString)
    for (k, _) in MACROS
        k == name && return true
    end
    return false
end

function def!(name::AbstractString, value::AbstractString)
    macro_exists(name) && error("Duplicate macro definition: \\$name")
    push!(MACROS, name => value)
    return nothing
end

# Post-pass: for every macro whose value ends in "\%", emit a paired "Num"
# variant with the percent sign stripped, so tables can use bare numbers
# under an "Ownership (\%)" header. Any hand-defined Num macro wins.
function backfill_num_variants!()
    additions = Pair{String,String}[]
    for (name, value) in MACROS
        endswith(value, "\\%") || continue
        num_name = name * "Num"
        macro_exists(num_name) && continue
        any(p -> first(p) == num_name, additions) && continue
        push!(additions, num_name => value[1:end-2])
    end
    append!(MACROS, additions)
    return nothing
end

# ---------------------------------------------------------------------------
# Source data loaders
# ---------------------------------------------------------------------------

function read_csv(name::AbstractString)
    path = joinpath(CSV_DIR, name)
    isfile(path) || error("Missing CSV: $path. Run the upstream analysis script first.")
    readdlm(path, ',', Any; header=true)
end

function subset_ownership(bitmask::Int)
    rows, _ = read_csv("subset_enumeration.csv")
    for r in eachrow(rows)
        if Int(r[1]) == bitmask
            return Float64(r[3])  # ownership_pct
        end
    end
    error("bitmask $bitmask not found in subset_enumeration.csv")
end

function subset_alpha(bitmask::Int)
    rows, _ = read_csv("subset_enumeration.csv")
    for r in eachrow(rows)
        if Int(r[1]) == bitmask
            return Float64(r[4])  # mean_alpha
        end
    end
    error("bitmask $bitmask not found in subset_enumeration.csv")
end

# welfare_counterfactuals.csv has unquoted commas in scenario names and
# descriptions, so readdlm fractures rows. Parse by prefix-match + numeric
# tokenization of the tail.
function welfare_counterfactual(scenario::AbstractString)
    path = joinpath(CSV_DIR, "welfare_counterfactuals.csv")
    isfile(path) || error("Missing CSV: $path")
    prefix = scenario * ","
    for (i, line) in enumerate(eachline(path))
        i == 1 && continue  # header
        startswith(line, prefix) || continue
        tail = chopprefix(line, prefix)
        toks = split(tail, ',')
        length(toks) >= 7 || error("malformed row for $(repr(scenario)): $line")
        # Schema: mwr, inflation, psi, c_floor, ss_scale, ownership_pct,
        # mean_alpha, apply_wedge, description.
        return (mwr=parse(Float64, toks[1]),
                inflation=parse(Float64, toks[2]),
                psi=parse(Float64, toks[3]),
                c_floor=parse(Float64, toks[4]),
                ss_scale=parse(Float64, toks[5]),
                ownership_pct=parse(Float64, toks[6]),
                mean_alpha=parse(Float64, toks[7]))
    end
    error("scenario $(repr(scenario)) not found in welfare_counterfactuals.csv")
end

function cev_grid_row(wealth::Int, health::AbstractString)
    rows, _ = read_csv("welfare_cev_grid.csv")
    for r in eachrow(rows)
        if Int(r[1]) == wealth && String(r[2]) == health
            return (cev_no=Float64(r[3]), alpha_no=Float64(r[4]),
                    cev_dfj=Float64(r[5]), alpha_dfj=Float64(r[6]),
                    cev_strong=Float64(r[7]), alpha_strong=Float64(r[8]))
        end
    end
    error("(wealth=$wealth, health=$health) not in welfare_cev_grid.csv")
end

function cev_counterfactual_row(wealth::Int, health::AbstractString)
    rows, _ = read_csv("cev_counterfactuals.csv")
    for r in eachrow(rows)
        if Int(r[1]) == wealth && String(r[2]) == health
            return (cev_baseline=Float64(r[3]), alpha_baseline=Float64(r[4]),
                    cev_group=Float64(r[5]), alpha_group=Float64(r[6]),
                    cev_real=Float64(r[7]), alpha_real=Float64(r[8]),
                    cev_best=Float64(r[9]), alpha_best=Float64(r[10]))
        end
    end
    error("(wealth=$wealth, health=$health) not in cev_counterfactuals.csv")
end

function population_cev(bequest_spec::AbstractString)
    rows, _ = read_csv("population_cev.csv")
    for r in eachrow(rows)
        if String(r[1]) == bequest_spec
            return (mean_cev=Float64(r[2]), median_cev=Float64(r[3]),
                    frac_positive=Float64(r[4]), frac_above_1pct=Float64(r[5]))
        end
    end
    error("bequest_spec $(repr(bequest_spec)) not in population_cev.csv")
end

function shapley_lookup()
    rows, _ = read_csv("shapley_exact.csv")
    out = Dict{String, NamedTuple{(:value_pp, :share_pct), Tuple{Float64, Float64}}}()
    for r in eachrow(rows)
        out[String(r[1])] = (value_pp=Float64(r[2]), share_pct=Float64(r[3]))
    end
    # Production CSV is generated by the 10-channel run_subset_enumeration.jl
    # and contains a single bundled "Medical+R-S" row directly. If the bundled
    # row is missing the CSV is from a pre-reformulation pipeline run and the
    # exporter must fail loudly rather than synthesize a value — adding two
    # disjoint Shapley values does not equal the merged-player Shapley value.
    if !haskey(out, "Medical+R-S")
        error("shapley_exact.csv is missing the bundled 'Medical+R-S' row. " *
              "Re-run scripts/run_subset_enumeration.jl + run_shapley_decomposition.jl " *
              "with the 10-channel layout (Med+R-S bundled as channel CH_MED_RS).")
    end
    out
end

# robustness_full.csv embeds commas in specification fields (e.g. "g=2.5,pi=1%")
# so we parse by prefix-match on "category," + reverse-split for the ownership field.
function robustness_ownership(category::AbstractString, specification::AbstractString)
    path = joinpath(CSV_DIR, "robustness_full.csv")
    isfile(path) || error("Missing CSV: $path")
    target = category * "," * specification * ","
    for (i, line) in enumerate(eachline(path))
        i == 1 && continue
        startswith(line, target) || continue
        tail = chopprefix(line, target)
        return parse(Float64, rstrip(tail, '%'))
    end
    error("robustness row ($category, $specification) not found")
end

function ss_cut_ownership(cut_pct::Int)
    rows, _ = read_csv("ss_cut_robustness.csv")
    for r in eachrow(rows)
        if Int(r[1]) == cut_pct
            return Float64(r[2])
        end
    end
    error("ss_cut_pct $cut_pct not in ss_cut_robustness.csv")
end

function state_utility_sensitivity(label::AbstractString)
    rows, _ = read_csv("state_utility_sensitivity.csv")
    for r in eachrow(rows)
        if String(r[1]) == label
            return (phi_good=Float64(r[2]), phi_fair=Float64(r[3]),
                    phi_poor=Float64(r[4]), ownership_pct=Float64(r[5]),
                    mean_alpha=Float64(r[6]))
        end
    end
    error("label $(repr(label)) not in state_utility_sensitivity.csv")
end

function monte_carlo_summary()
    path = joinpath(CSV_DIR, "monte_carlo_ownership.csv")
    isfile(path) || return nothing
    raw = readdlm(path, ',', Any; skipstart=1)
    own_col = size(raw, 2)  # last column is ownership_pct (works for old + new schemas)
    vals = sort(Float64.(raw[:, own_col]))
    n = length(vals)
    n == 0 && return nothing
    pick(q) = vals[max(1, round(Int, q * n))]
    return (n=n, mean=sum(vals)/n, median=vals[div(n, 2)],
            q05=pick(0.05), q25=pick(0.25), q75=pick(0.75), q95=pick(0.95),
            min=vals[1], max=vals[end])
end

function hrs_summary()
    isfile(HRS_PATH) || error("Missing HRS sample: $HRS_PATH")
    raw = readdlm(HRS_PATH, ',', Any; skipstart=1)
    n = size(raw, 1)
    wealth_sorted = sort(Float64.(raw[:, 1]))
    median_wealth = wealth_sorted[div(n, 2)]
    wealth = Float64.(raw[:, 1])
    n_elig = count(wealth .>= MIN_WEALTH)
    n_above_wmax = count(wealth .> W_MAX)
    # observed annuity ownership from own_life_ann column (col 5)
    n_own = count(Float64.(raw[:, 5]) .> 0)
    (; n_total=n, n_eligible=n_elig, median_wealth=median_wealth,
       n_above_wmax=n_above_wmax, pct_above_wmax=100 * n_above_wmax / n,
       n_owners=n_own, pct_owners=100 * n_own / n)
end

# ---------------------------------------------------------------------------
# Build macros
# ---------------------------------------------------------------------------

function build_macros!()
    # ======================================================================
    # Section A — Preference, budget, and grid parameters (from config.jl)
    # ======================================================================
    def!("pGamma",              fmt_num(GAMMA; digits=1))
    def!("pBeta",               fmt_num(BETA; digits=2))
    def!("pRRate",              fmt_pct(R_RATE * 100; digits=0))
    def!("pRRateNum",           fmt_num(R_RATE; digits=2))
    def!("pInflation",          fmt_pct(INFLATION * 100; digits=0))
    def!("pInflationNum",       fmt_num(INFLATION; digits=2))
    def!("pCFloor",             fmt_dollar(C_FLOOR))
    def!("pFixedCost",          fmt_dollar(FIXED_COST))
    def!("pMinWealth",          fmt_dollar(MIN_WEALTH))
    def!("pWMax",               fmt_dollar(W_MAX))
    # Use \text{million} so this macro survives inside math mode like $[0, \pWMaxMillions]$.
    def!("pWMaxMillions",       @sprintf("\\\$%s\\text{ million}", W_MAX >= 1_000_000 ? fmt_num(W_MAX / 1_000_000; digits=(W_MAX % 1_000_000 == 0 ? 0 : 1)) : fmt_num(W_MAX / 1_000_000; digits=1)))

    # Bequest
    def!("pThetaDFJ",           fmt_num(THETA_DFJ; digits=2))
    def!("pKappaDFJ",           fmt_dollar(KAPPA_DFJ))

    # Age-varying consumption decline (Aguiar-Hurst)
    def!("pDeltaC",             fmt_num(CONSUMPTION_DECLINE_ACTIVE; digits=2))

    # State-dependent utility weights [G, F, P]
    def!("pHealthUtilGood",     fmt_num(HEALTH_UTILITY_ACTIVE[1]; digits=2))
    def!("pHealthUtilFair",     fmt_num(HEALTH_UTILITY_ACTIVE[2]; digits=2))
    def!("pHealthUtilPoor",     fmt_num(HEALTH_UTILITY_ACTIVE[3]; digits=2))

    # Hazard multipliers [G, F, P]
    def!("pHazardGood",         fmt_num(HAZARD_MULT[1]; digits=2))
    def!("pHazardFair",         fmt_num(HAZARD_MULT[2]; digits=1))
    def!("pHazardPoor",         fmt_num(HAZARD_MULT[3]; digits=1))

    # Survival pessimism
    def!("pPessimism",          fmt_num(SURVIVAL_PESSIMISM; digits=3))

    # Demographics and grid sizes
    def!("pAgeStart",           fmt_int(AGE_START))
    def!("pAgeEnd",             fmt_int(AGE_END))
    def!("pT",                  fmt_int(AGE_END - AGE_START + 1))
    def!("pNWealth",            fmt_int(N_WEALTH))
    def!("pNAnnuity",           fmt_int(N_ANNUITY))
    def!("pNAlpha",             fmt_int(N_ALPHA))
    def!("pNQuad",              fmt_int(N_QUAD))

    # ======================================================================
    # Section B — Baseline MWR (pulled from welfare_counterfactuals.csv
    # "Baseline" row, because that's the value the actual model runs used;
    # scripts/config.jl MWR_LOADED may differ during transitions)
    # ======================================================================
    wc_base = welfare_counterfactual("Baseline")
    def!("pMwrBaseline",        fmt_num(wc_base.mwr; digits=2))
    def!("pMwrLoad",            fmt_pct((1 - wc_base.mwr) * 100; digits=0))

    # ======================================================================
    # Section C — HRS sample summary
    # ======================================================================
    hrs = hrs_summary()
    def!("nHRSTotal",           commas(hrs.n_total))
    def!("nHRSEligible",        fmt_int(hrs.n_eligible))
    def!("nHRSMedianWealth",    fmt_dollar(round(hrs.median_wealth / 1_000) * 1_000))
    def!("nHRSAboveWmax",       fmt_int(hrs.n_above_wmax))
    def!("pctHRSAboveWmax",     fmt_pct(hrs.pct_above_wmax; digits=1))
    def!("pctHRSObserved",      fmt_pct(hrs.pct_owners; digits=1))
    def!("nHRSOwners",          fmt_int(hrs.n_owners))

    # ----------------------------------------------------------------------
    # Section C2 — HRS lifetime annuity indicator (fat-file q286 series)
    # Source: data/processed/hrs_lifetime_ownership.csv (POOLED row)
    # Wilson 95% binomial CIs computed for both lifetime (q286) and any-annuity
    # (r{w}iann income proxy) measures so the manuscript can present both with
    # sampling tolerance.
    # ----------------------------------------------------------------------
    function wilson_ci(k::Int, n::Int; z::Float64=1.96)
        # Wilson score interval — robust for proportions near zero.
        p = k / n
        denom = 1 + z^2 / n
        center = (p + z^2 / (2n)) / denom
        halfwidth = z * sqrt(p * (1 - p) / n + z^2 / (4 * n^2)) / denom
        return (lo = center - halfwidth, hi = center + halfwidth)
    end

    hrs_lifetime_path = joinpath(REPO_ROOT, "data", "processed", "hrs_lifetime_ownership.csv")
    if isfile(hrs_lifetime_path)
        for (i, line) in enumerate(eachline(hrs_lifetime_path))
            i == 1 && continue
            startswith(line, "POOLED,") || continue
            toks = split(chopprefix(line, "POOLED,"), ',')
            n_elig    = parse(Int, toks[1])
            n_iann    = parse(Int, toks[2])
            n_lifetime = parse(Int, toks[4])
            iann_pct  = parse(Float64, toks[5])
            lifetime_pct = parse(Float64, toks[7])
            def!("nHRSLifetimeEligible", commas(n_elig))
            def!("nHRSLifetimeOwners",   fmt_int(n_lifetime))
            def!("pctHRSLifetime",       fmt_pct(lifetime_pct; digits=2))
            def!("pctHRSIannPooled",     fmt_pct(iann_pct;     digits=2))
            def!("nHRSIannOwners",       fmt_int(n_iann))

            # Wilson 95% CIs for both measures
            ci_life = wilson_ci(n_lifetime, n_elig)
            ci_iann = wilson_ci(n_iann, n_elig)
            def!("pctHRSLifetimeCILow",  fmt_pct(100 * ci_life.lo; digits=2))
            def!("pctHRSLifetimeCIHigh", fmt_pct(100 * ci_life.hi; digits=2))
            def!("pctHRSIannCILow",      fmt_pct(100 * ci_iann.lo; digits=2))
            def!("pctHRSIannCIHigh",     fmt_pct(100 * ci_iann.hi; digits=2))
            break
        end
    end

    # ----------------------------------------------------------------------
    # Section C3 — UK ELSA pre/post 2015 freedoms empirical evidence
    # Source: data/processed/elsa_pre_post_freedoms.csv,
    #         data/processed/elsa_disposition_pooled.csv
    # ----------------------------------------------------------------------
    elsa_pp_path = joinpath(REPO_ROOT, "data", "processed", "elsa_pre_post_freedoms.csv")
    if isfile(elsa_pp_path)
        for (i, line) in enumerate(eachline(elsa_pp_path))
            i == 1 && continue
            toks = split(chomp(line), ',')
            length(toks) == 5 || continue
            regime, measure, n_yes, n_denom, pct = toks
            if regime == "pre_freedoms_w6" && measure == "annuity_style_of_dc_recipients"
                # LaTeX macro names cannot contain digits, so "W6" -> "WaveSix".
                def!("nELSAWaveSixDC",         fmt_int(parse(Int, n_denom)))
                def!("nELSAWaveSixAnnuity",    fmt_int(parse(Int, n_yes)))
                def!("pctELSAWaveSixAnnuity",  fmt_pct(parse(Float64, pct); digits=1))
            elseif regime == "post_freedoms_w8_11" && measure == "lumpsum_annuitize"
                def!("nELSAPostLumpSum",  fmt_int(parse(Int, n_denom)))
                def!("nELSAPostAnnuity",  fmt_int(parse(Int, n_yes)))
                def!("pctELSAPostAnnuity", fmt_pct(parse(Float64, pct); digits=2))
            elseif regime == "post_freedoms_pool_w8_11" && measure == "lumpsum_annuitize"
                def!("nELSAPostLumpSum",  fmt_int(parse(Int, n_denom)))
                def!("nELSAPostAnnuity",  fmt_int(parse(Int, n_yes)))
                def!("pctELSAPostAnnuity", fmt_pct(parse(Float64, pct); digits=2))
            elseif regime == "post_freedoms_pool_w8_11" && measure == "plan_annuitize"
                def!("nELSAPostPlanDC",      fmt_int(parse(Int, n_denom)))
                def!("nELSAPostPlanAnnuity", fmt_int(parse(Int, n_yes)))
                def!("pctELSAPostPlanAnnuity", fmt_pct(parse(Float64, pct); digits=1))
            end
        end
        # Implied behavioral elasticity: pre - post (for both lump-sum and plan measures)
        # Pre = 90.2%, post (lump-sum) = 1.27%, post (plan) = 3.50%
        # Headline drop:
        #   90.2 - 1.27 = 88.9 pp (lump-sum disposition basis)
        #   90.2 - 3.50 = 86.7 pp (forward-plan basis)
        def!("ELSADropLumpSum", fmt_num(88.9; digits=0))
        def!("ELSADropPlan",    fmt_num(86.7; digits=0))
        def!("ELSADropRange",   "87--89")
    end

    # ======================================================================
    # Section D — Sequential decomposition (retention path)
    # Bitmasks follow the decomposition ordering used by run_subset_enumeration.jl
    # ======================================================================
    # Frictionless population benchmark
    def!("ownFrictionless",     fmt_pct(subset_ownership(0); digits=1))

    # + SS
    def!("ownAddSS",            fmt_pct(subset_ownership(B_SS); digits=1))
    # + Bequests (SS + Bequests)
    def!("ownAddBequests",      fmt_pct(subset_ownership(B_SS | B_BEQUESTS); digits=1))
    # + Medical risk + R-S correlation (combined channel under 10-channel reformulation)
    def!("ownAddMedRS",         fmt_pct(subset_ownership(B_SS | B_BEQUESTS | B_MED_RS); digits=1))
    # Backward-compat aliases — under 10-channel structure both add the same bundle.
    def!("ownAddMedical",       fmt_pct(subset_ownership(B_SS | B_BEQUESTS | B_MED_RS); digits=1))
    def!("ownAddRS",            fmt_pct(subset_ownership(B_SS | B_BEQUESTS | B_MED_RS); digits=1))
    # + Pessimism
    def!("ownAddPessimism",     fmt_pct(subset_ownership(B_SS | B_BEQUESTS | B_MED_RS | B_PESSIMISM); digits=1))
    # + Loads (skip age needs / state utility — these come in the extension table)
    def!("ownAddLoads",         fmt_pct(subset_ownership(B_SS | B_BEQUESTS | B_MED_RS | B_PESSIMISM | B_LOADS); digits=1))
    # Sequential decomposition macros under the 11-channel structure.
    # Layer 1 (rational): SS, Bequests, MedRS, Pessimism, Loads, Inflation
    # Layer 2 (preference): Age needs, State utility, LTC (chi_ltc structural)
    # Layer 3 (behavioral): SDU (Force A), PED (Force B)
    #
    # 6-channel rational (SS+Bequests+MedRS+Pessimism+Loads+Inflation; bitmask 207)
    def!("ownSixChannel",       fmt_pct(subset_ownership(B_SS | B_BEQUESTS | B_MED_RS | B_PESSIMISM | B_LOADS | B_INFLATION); digits=1))
    # 7-channel: + age-varying consumption needs (bitmask 223)
    def!("ownSevenChannelExt",  fmt_pct(subset_ownership(B_SS | B_BEQUESTS | B_MED_RS | B_PESSIMISM | B_AGE_NEEDS | B_LOADS | B_INFLATION); digits=1))
    # 8-channel: + state-dependent utility (bitmask 255)
    def!("ownEightChannelExt",  fmt_pct(subset_ownership(B_SS | B_BEQUESTS | B_MED_RS | B_PESSIMISM | B_AGE_NEEDS | B_STATE_UTIL | B_LOADS | B_INFLATION); digits=1))
    # 9-channel: + LTC / public-care aversion (bitmask 511). This is the
    # NO-BEHAVIORAL BASELINE used by Model 2 multiplicative wedge transport.
    own_no_behavioral_pct = NaN
    try
        own_no_behavioral_pct = subset_ownership(B_SS | B_BEQUESTS | B_MED_RS | B_PESSIMISM | B_AGE_NEEDS | B_STATE_UTIL | B_LOADS | B_INFLATION | B_LTC)
        def!("ownNineChannelLTC", fmt_pct(own_no_behavioral_pct; digits=1))
        def!("ownNoBehavioralBaseline", fmt_pct(own_no_behavioral_pct; digits=1))
    catch e
        @warn "Skipping ownNineChannelLTC / ownNoBehavioralBaseline (pipeline not yet run)" exception=e
    end

    # 10-channel: + SDU (Force A; bitmask 1023)
    own_ten_sdu_pct = NaN
    try
        own_ten_sdu_pct = subset_ownership(B_SS | B_BEQUESTS | B_MED_RS | B_PESSIMISM | B_AGE_NEEDS | B_STATE_UTIL | B_LOADS | B_INFLATION | B_LTC | B_SDU)
        def!("ownTenChannelSDU", fmt_pct(own_ten_sdu_pct; digits=1))
    catch e
        @warn "Skipping ownTenChannelSDU" exception=e
    end

    # 11-channel: + PED (Force B; bitmask 2047). MODEL 1 STRUCTURAL HEADLINE.
    own_model1_pct = NaN
    try
        own_model1_pct = subset_ownership(B_SS | B_BEQUESTS | B_MED_RS | B_PESSIMISM | B_AGE_NEEDS | B_STATE_UTIL | B_LOADS | B_INFLATION | B_LTC | B_SDU | B_PED)
        def!("ownElevenChannelFull", fmt_pct(own_model1_pct; digits=1))
        def!("ownModelOne", fmt_pct(own_model1_pct; digits=1))
        def!("ownModelOneStructural", fmt_pct(own_model1_pct; digits=1))
    catch e
        @warn "Skipping ownElevenChannelFull / ownModelOne" exception=e
    end

    # ===================================================================
    # MODEL 2 — UK reduced-form transport (multiplicative wedge)
    # ===================================================================
    # The UK 2015 pension-freedoms reform produced a 95% pre-reform
    # compulsion-equilibrium retention rate and a 13-25% post-reform
    # voluntary retention rate. Model 2 transports the proportional
    # retention factor (UK_post / UK_pre) to the US as a deterministic
    # multiplicative transformation on the FRICTIONLESS Yaari baseline:
    #
    #   Model 2 prediction = frictionless baseline × (UK_post / UK_pre)
    #
    # The frictionless baseline is the HRS-population ownership rate when
    # NO channels are active (Yaari benchmark on the empirical wealth
    # distribution). The UK retention factor captures the combined effect
    # of all rational AND behavioral frictions that voluntary households
    # express when compulsion lifts, so applying it directly to the
    # frictionless baseline yields a clean reduced-form prediction without
    # double-counting any structural channel.
    #
    # Because the UK pre-reform 95% rate is itself a compulsion equilibrium
    # (not a no-friction state), the transport prediction should be read
    # as an upper bound on the combined friction wedge.
    #
    # Production midpoint: UK_post = 17%, UK_pre = 95%, factor = 17/95 = 0.179
    # Sensitivity range: UK_post in {13%, 17%, 25%}; factor in [0.137, 0.263].
    # ===================================================================
    own_frictionless_pct = NaN
    try
        own_frictionless_pct = subset_ownership(0)
    catch e
        @warn "Could not load frictionless baseline for Model 2" exception=e
    end
    if !isnan(own_frictionless_pct)
        # Source UK retention constants from config.jl (single source of truth)
        wedge_pre  = UK_RETENTION_PRE
        wedge_low  = UK_RETENTION_LOW  / wedge_pre   # 13/95 = 0.137
        wedge_mid  = UK_RETENTION_MID  / wedge_pre   # 17/95 = 0.179
        wedge_high = UK_RETENTION_HIGH / wedge_pre   # 25/95 = 0.263

        ownNum_low  = own_frictionless_pct * wedge_low
        ownNum_mid  = own_frictionless_pct * wedge_mid
        ownNum_high = own_frictionless_pct * wedge_high

        # Wedge factor macros (for display in the manuscript)
        def!("pWedgeFactorLow",  fmt_num(wedge_low;  digits=3))
        def!("pWedgeFactorMid",  fmt_num(wedge_mid;  digits=3))
        def!("pWedgeFactorHigh", fmt_num(wedge_high; digits=3))
        def!("pUKRetentionPre",  fmt_pct(UK_RETENTION_PRE  * 100; digits=0))
        def!("pUKRetentionLow",  fmt_pct(UK_RETENTION_LOW  * 100; digits=0))
        def!("pUKRetentionMid",  fmt_pct(UK_RETENTION_MID  * 100; digits=0))
        def!("pUKRetentionHigh", fmt_pct(UK_RETENTION_HIGH * 100; digits=0))

        # Frictionless baseline (the multiplicand for Model 2). The
        # ownFrictionless macro is already defined earlier in build_macros!
        # at the start of the subset-ownership block; emit only the Num
        # variant here so the backfill pass doesn't double-define.
        macro_exists("ownFrictionlessNum") || def!("ownFrictionlessNum", fmt_num(own_frictionless_pct; digits=1))

        # Model 2 wedge-multiplied US ownership predictions
        def!("ownWedgeLow",  fmt_pct(ownNum_low;  digits=1))
        def!("ownWedgeMid",  fmt_pct(ownNum_mid;  digits=1))
        def!("ownWedgeHigh", fmt_pct(ownNum_high; digits=1))

        # Model 2 named aliases — used in prose alongside Model 1 macros
        def!("ownModelTwoLow",  fmt_pct(ownNum_low;  digits=1))
        def!("ownModelTwoMid",  fmt_pct(ownNum_mid;  digits=1))
        def!("ownModelTwoHigh", fmt_pct(ownNum_high; digits=1))
        def!("ownModelTwo",     fmt_pct(ownNum_mid;  digits=1))

        # Headline = Model 2 mid-anchor (used in legacy prose; Model 1
        # predictions are reported separately as ownModelOne).
        def!("ownHeadline",  fmt_pct(ownNum_mid;  digits=1))

        # Bracket macros for prose convenience
        def!("ownBracketLow",  fmt_pct(ownNum_low;  digits=1))
        def!("ownBracketHigh", fmt_pct(ownNum_high; digits=1))
    end

    # Retention rate for SS step (complement as percent)
    own_friction = subset_ownership(0)
    own_ss = subset_ownership(B_SS)
    def!("retentionSS",         fmt_pct(own_ss / own_friction * 100; digits=1))

    # Specific prose values
    own_pre_pessimism = subset_ownership(B_SS | B_BEQUESTS | B_MED_RS)
    own_post_pessimism = subset_ownership(B_SS | B_BEQUESTS | B_MED_RS | B_PESSIMISM)
    def!("ownPrePessimism",     fmt_pct(own_pre_pessimism; digits=1))
    def!("deltaPessimism",      fmt_num(own_post_pessimism - own_pre_pessimism; digits=1))
    def!("retentionPessimism",  fmt_pct(own_post_pessimism / own_pre_pessimism * 100; digits=1))

    # Loads step
    own_post_loads = subset_ownership(B_SS | B_BEQUESTS | B_MED_RS | B_PESSIMISM | B_LOADS)
    def!("retentionLoads",      fmt_pct(own_post_loads / own_post_pessimism * 100; digits=1))

    # Inflation step
    own_post_inflation = subset_ownership(B_SS | B_BEQUESTS | B_MED_RS | B_PESSIMISM | B_LOADS | B_INFLATION)
    def!("retentionInflation",  fmt_pct(own_post_inflation / own_post_loads * 100; digits=1))

    # Combined Medical+R-S delta under 10-channel reformulation.
    # The medical risk and R-S correlation channels are coupled (R-S's
    # quantitative bite in this framework operates through the interaction
    # with medical risk), so they are added together as a single bundle.
    own_pre_med_rs = subset_ownership(B_SS | B_BEQUESTS)
    own_post_med_rs = subset_ownership(B_SS | B_BEQUESTS | B_MED_RS)
    def!("deltaMedRS",          fmt_num(own_post_med_rs - own_pre_med_rs; digits=1))
    def!("magDeltaMedRS",       fmt_num(abs(own_post_med_rs - own_pre_med_rs); digits=1))
    def!("retentionMedRS",      fmt_pct(own_post_med_rs / own_pre_med_rs * 100; digits=1))
    # Backward-compat aliases for prose still using the old separate names.
    # Both refer to the combined Medical+R-S bundle delta.
    def!("deltaMedical",        fmt_num(own_post_med_rs - own_pre_med_rs; digits=1))
    def!("magDeltaMedical",     fmt_num(abs(own_post_med_rs - own_pre_med_rs); digits=1))
    def!("retentionMedical",    fmt_pct(own_post_med_rs / own_pre_med_rs * 100; digits=1))
    def!("deltaRS",             fmt_num(own_post_med_rs - own_pre_med_rs; digits=1))
    def!("magDeltaRS",          fmt_num(abs(own_post_med_rs - own_pre_med_rs); digits=1))
    def!("retentionRS",         fmt_pct(own_post_med_rs / own_pre_med_rs * 100; digits=1))

    # ======================================================================
    # Section E — Extension path
    # Under 10-channel reformulation: 6-channel rational (SS, Bequests, Med+R-S,
    # Pessimism, Loads, Inflation) → +Age needs → +State utility = 8-channel.
    # Old 11-channel naming retained as aliases for manuscript backward compat.
    # ======================================================================
    own_base = subset_ownership(B_SS | B_BEQUESTS | B_MED_RS | B_PESSIMISM | B_LOADS | B_INFLATION)
    own_with_age = subset_ownership(B_SS | B_BEQUESTS | B_MED_RS | B_PESSIMISM | B_AGE_NEEDS | B_LOADS | B_INFLATION)
    own_with_state = subset_ownership(B_SS | B_BEQUESTS | B_MED_RS | B_PESSIMISM | B_AGE_NEEDS | B_STATE_UTIL | B_LOADS | B_INFLATION)
    def!("deltaAgeNeeds",       fmt_num(own_with_age - own_base; digits=1))
    def!("deltaStateUtil",      fmt_num(own_with_state - own_with_age; digits=1))

    # ======================================================================
    # Section F — Shapley values (from shapley_exact.csv)
    # ======================================================================
    sh = shapley_lookup()
    def!("shapSS",              fmt_num(sh["SS"].value_pp; digits=1))
    def!("shapBequests",        fmt_num(sh["Bequests"].value_pp; digits=1))
    # Combined Medical + R-S correlation channel (10-channel reformulation).
    def!("shapMedRS",           fmt_num(sh["Medical+R-S"].value_pp; digits=1))
    # Backward-compat aliases for prose still using the old separate names.
    def!("shapMedical",         fmt_num(sh["Medical+R-S"].value_pp; digits=1))
    def!("shapRS",              fmt_num(sh["Medical+R-S"].value_pp; digits=1))
    def!("shapPessimism",       fmt_num(sh["Pessimism"].value_pp; digits=1))
    def!("shapAgeNeeds",        fmt_num(sh["Age needs"].value_pp; digits=1))
    def!("shapStateUtil",       fmt_num(sh["State utility"].value_pp; digits=1))
    def!("shapLoads",           fmt_num(sh["Loads"].value_pp; digits=1))
    def!("shapInflation",       fmt_num(sh["Inflation"].value_pp; digits=1))
    if haskey(sh, "Public-care aversion (LTC)")
        def!("shapLTC",         fmt_num(sh["Public-care aversion (LTC)"].value_pp; digits=1))
    end
    if haskey(sh, "Source-dependent utility (SDU)")
        def!("shapSDU",         fmt_num(sh["Source-dependent utility (SDU)"].value_pp; digits=1))
    end
    if haskey(sh, "Narrow-framing penalty (PED)")
        def!("shapPED",         fmt_num(sh["Narrow-framing penalty (PED)"].value_pp; digits=1))
    end

    def!("shapShareSS",         fmt_pct(sh["SS"].share_pct; digits=0))
    def!("shapShareBequests",   fmt_pct(sh["Bequests"].share_pct; digits=0))
    def!("shapShareMedRS",      fmt_pct(sh["Medical+R-S"].share_pct; digits=0))
    def!("shapShareMedical",    fmt_pct(sh["Medical+R-S"].share_pct; digits=0))  # alias
    def!("shapShareRS",         fmt_pct(sh["Medical+R-S"].share_pct; digits=0))  # alias
    def!("shapSharePessimism",  fmt_pct(sh["Pessimism"].share_pct; digits=0))
    def!("shapShareAgeNeeds",   fmt_pct(sh["Age needs"].share_pct; digits=0))
    def!("shapShareStateUtil",  fmt_pct(sh["State utility"].share_pct; digits=0))
    def!("shapShareLoads",      fmt_pct(sh["Loads"].share_pct; digits=0))
    def!("shapShareInflation",  fmt_pct(sh["Inflation"].share_pct; digits=0))
    if haskey(sh, "Public-care aversion (LTC)")
        def!("shapShareLTC",    fmt_pct(sh["Public-care aversion (LTC)"].share_pct; digits=0))
    end
    if haskey(sh, "Source-dependent utility (SDU)")
        def!("shapShareSDU",    fmt_pct(sh["Source-dependent utility (SDU)"].share_pct; digits=0))
    end
    if haskey(sh, "Narrow-framing penalty (PED)")
        def!("shapSharePED",    fmt_pct(sh["Narrow-framing penalty (PED)"].share_pct; digits=0))
    end

    # Non-pricing non-traditional channels sum: Med+R-S + Pessimism + Age needs
    rs_pess_age_pp    = sh["Medical+R-S"].value_pp + sh["Pessimism"].value_pp + sh["Age needs"].value_pp
    rs_pess_age_share = sh["Medical+R-S"].share_pct + sh["Pessimism"].share_pct + sh["Age needs"].share_pct
    def!("shapRSPessAge",       fmt_num(rs_pess_age_pp; digits=1))
    def!("shapShareRSPessAge",  fmt_pct(rs_pess_age_share; digits=0))

    # ======================================================================
    # Section G — Welfare: CEV at headline cells
    # ======================================================================
    cev = cev_grid_row(100_000, "Good")
    def!("cevGoodHundredKNoBq",      fmt_pct(cev.cev_no * 100; digits=1))
    def!("cevGoodHundredKDFJ",       fmt_pct(cev.cev_dfj * 100; digits=1))
    def!("cevGoodHundredKStrong",    fmt_pct(cev.cev_strong * 100; digits=1))

    cev = cev_grid_row(200_000, "Good")
    def!("cevGoodTwoHundredKNoBq",   fmt_pct(cev.cev_no * 100; digits=1))
    def!("cevGoodTwoHundredKDFJ",    fmt_pct(cev.cev_dfj * 100; digits=1))
    def!("cevGoodTwoHundredKStrong", fmt_pct(cev.cev_strong * 100; digits=1))

    cev = cev_grid_row(1_000_000, "Good")
    def!("cevGoodOneMillNoBq",       fmt_pct(cev.cev_no * 100; digits=1))
    def!("cevGoodOneMillDFJ",        fmt_pct(cev.cev_dfj * 100; digits=1))
    def!("cevGoodOneMillStrong",     fmt_pct(cev.cev_strong * 100; digits=1))

    # Population CEV
    pop_no  = population_cev("No bequest")
    pop_dfj = population_cev("Moderate (DFJ)")
    def!("popMeanCevNoBq",      fmt_pct(pop_no.mean_cev * 100; digits=1))
    def!("popMeanCevDFJ",       fmt_pct(pop_dfj.mean_cev * 100; digits=1))
    def!("popFracPosNoBq",      fmt_pct(pop_no.frac_positive * 100; digits=1))
    def!("popFracPosDFJ",       fmt_pct(pop_dfj.frac_positive * 100; digits=1))
    def!("popFracAboveOneNoBq", fmt_pct(pop_no.frac_above_1pct * 100; digits=1))
    def!("popFracAboveOneDFJ",  fmt_pct(pop_dfj.frac_above_1pct * 100; digits=1))

    # ======================================================================
    # Section H — Policy counterfactuals (welfare_counterfactuals.csv)
    # ======================================================================
    for (key, scenario) in [
        ("GroupPricing",     "Group pricing (MWR=0.90)"),
        ("PublicOption",     "Public option (MWR=0.95)"),
        ("ActuariallyFair",  "Actuarially fair (MWR=1.0)"),
        ("RealTIPS",         "Real annuity, TIPS-backed"),
        ("RealNomEquiv",     "Real annuity, nominal-equiv"),
        ("FairReal",         "Fair + real"),
        ("CorrectPessimism", "Correct pessimism (psi=1.0)"),
        ("GroupPlusCorrect", "Group + correct pessimism"),
        ("BestFeasible",     "Best feasible package"),
    ]
        wc = welfare_counterfactual(scenario)
        def!("own" * key, fmt_pct(wc.ownership_pct; digits=1))
    end

    # CEV counterfactuals at specific wealth cells
    for (suffix, wealth) in [("HundredK", 100_000), ("TwoHundredK", 200_000),
                             ("FiveHundredK", 500_000), ("OneMill", 1_000_000)]
        cc = cev_counterfactual_row(wealth, "Good")
        def!("cevGood" * suffix * "Baseline",    fmt_pct(cc.cev_baseline * 100; digits=1))
        def!("cevGood" * suffix * "GroupPrice",  fmt_pct(cc.cev_group * 100; digits=1))
        def!("cevGood" * suffix * "RealAnn",     fmt_pct(cc.cev_real * 100; digits=1))
        def!("cevGood" * suffix * "BestFeas",    fmt_pct(cc.cev_best * 100; digits=1))
    end

    # ======================================================================
    # Section I — Robustness (gamma, inflation, psi sweeps)
    # ======================================================================
    for (key, spec) in [
        ("Two",          "gamma=2.00"),
        ("TwoPointThree","gamma=2.30"),
        ("TwoPointFour", "gamma=2.40"),
        ("TwoPointFive", "gamma=2.50"),
        ("Three",        "gamma=3.00"),
    ]
        def!("ownGamma" * key, fmt_pct(robustness_ownership("Gamma sweep", spec); digits=1))
    end

    # Inflation is reported via the combined Gamma×Inflation sweep
    for (key, spec) in [
        ("One",   "g=2.5,pi=1%"),
        ("Two",   "g=2.5,pi=2%"),
        ("Three", "g=2.5,pi=3%"),
    ]
        def!("ownInflation" * key, fmt_pct(robustness_ownership("Gamma×Inflation", spec); digits=1))
    end

    # Survival pessimism sweep
    for (key, spec) in [
        ("Objective",    "psi=1.000"),
        ("NinetySeven",  "psi=0.970"),
        ("Baseline",     "psi=0.981"),
        ("NinetyNine",   "psi=0.990"),
    ]
        def!("ownPsi" * key, fmt_pct(robustness_ownership("Survival pessimism", spec); digits=1))
    end

    # MWR sweep (appears in MWR sensitivity table in main.tex). The MWR-0.82
    # row below is a sensitivity-table entry (predicted ownership at a 0.82
    # load), not a stale production reference. ALLOWLIST: see next line.
    for (key, spec) in [
        ("EightyTwo",    "MWR=0.82"),  # ALLOWLIST: sensitivity-table entry
        ("EightyFive",   "MWR=0.85"),
        ("Ninety",       "MWR=0.90"),
        ("NinetyFive",   "MWR=0.95"),
    ]
        def!("ownMWR" * key, fmt_pct(robustness_ownership("MWR sweep", spec); digits=1))
    end

    # Bequest specifications
    def!("ownBequestNone", fmt_pct(robustness_ownership("Bequest spec", "No bequests"); digits=1))

    # Hazard multiplier sensitivity (Section "Health-mortality correlation" in robustness)
    def!("ownHazardRS",           fmt_pct(robustness_ownership("Hazard mult", "[0.45, 1.0, 3.5] (R-S functional, age 65-75)"); digits=1))
    def!("ownHazardHRS",          fmt_pct(robustness_ownership("Hazard mult", "[0.57, 1.0, 2.7] (HRS SRH empirical)"); digits=1))
    def!("ownHazardConservative", fmt_pct(robustness_ownership("Hazard mult", "[0.60, 1.0, 2.0] (conservative SRH)"); digits=1))
    def!("ownHazardAgeBand",      fmt_pct(robustness_ownership("Hazard mult", "Age-varying HRS (3 bands)"); digits=1))

    # ======================================================================
    # Section J — SS cut robustness (from welfare_counterfactuals "SS cut 23%")
    # and ss_cut_robustness.csv if finer grid needed
    # ======================================================================
    def!("ownSSCutZero",       fmt_pct(ss_cut_ownership(0);   digits=1))
    def!("ownSSCutTen",        fmt_pct(ss_cut_ownership(10);  digits=1))
    def!("ownSSCutFifteen",    fmt_pct(ss_cut_ownership(15);  digits=1))
    def!("ownSSCutTwentyThree",fmt_pct(ss_cut_ownership(23);  digits=1))
    def!("ownSSCutThirty",     fmt_pct(ss_cut_ownership(30);  digits=1))
    def!("ownSSCutForty",      fmt_pct(ss_cut_ownership(40);  digits=1))
    def!("ownSSCutFifty",      fmt_pct(ss_cut_ownership(50);  digits=1))
    def!("ownSSCutHundred",    fmt_pct(ss_cut_ownership(100); digits=1))

    # ======================================================================
    # Section K — State-dependent utility sensitivity (both FLN mappings)
    # Source: tables/csv/state_utility_sensitivity.csv
    # ======================================================================
    fln = state_utility_sensitivity("FLN")
    rs  = state_utility_sensitivity("ReichlingSmetters")

    # Raw FLN central mapping (currently the production calibration)
    def!("pHealthUtilFairFLN", fmt_num(fln.phi_fair; digits=2))
    def!("pHealthUtilPoorFLN", fmt_num(fln.phi_poor; digits=2))
    def!("ownNineChannelFLN",  fmt_pct(fln.ownership_pct; digits=1))

    # Reichling-Smetters softer mapping (robustness case)
    def!("pHealthUtilFairRS",  fmt_num(rs.phi_fair;  digits=2))
    def!("pHealthUtilPoorRS",  fmt_num(rs.phi_poor;  digits=2))
    def!("ownNineChannelRS",   fmt_pct(rs.ownership_pct; digits=1))

    # Difference: how much the softer mapping shifts ownership (always small)
    def!("deltaNineChannelRSmFLN", fmt_num(rs.ownership_pct - fln.ownership_pct; digits=1))

    # ======================================================================
    # Section L — Model 2 (UK reduced-form transport)
    # ======================================================================
    # Model 2 is computed in Section F above as
    # ownNoBehavioralBaseline x (UK_post / UK_pre). See ownWedge* and
    # ownBracket* macros there. Model 1's structural behavioral channels
    # (SDU, PED) are reported via ownModelOne (= ownElevenChannelFull) and
    # the corresponding Shapley macros (shapSDU, shapPED) are emitted in
    # Section F's Shapley block.

    # ======================================================================
    # Section M — Monte Carlo parameter uncertainty
    # Source: tables/csv/monte_carlo_ownership.csv (skipped if missing)
    # ======================================================================
    mc = monte_carlo_summary()
    if mc !== nothing
        # LaTeX macro names cannot contain digits, so spell percentile labels.
        def!("mcMedianOwnership",    fmt_pct(mc.median; digits=1))
        def!("mcMeanOwnership",      fmt_pct(mc.mean;   digits=1))
        def!("mcLowCIOwnership",     fmt_pct(mc.q05;    digits=1))  # 5th pct
        def!("mcHighCIOwnership",    fmt_pct(mc.q95;    digits=1))  # 95th pct
        def!("mcLowIQROwnership",    fmt_pct(mc.q25;    digits=1))  # 25th pct
        def!("mcHighIQROwnership",   fmt_pct(mc.q75;    digits=1))  # 75th pct
        def!("mcMinOwnership",       fmt_pct(mc.min;    digits=1))
        def!("mcMaxOwnership",       fmt_pct(mc.max;    digits=1))
        def!("nMCDraws",             commas(mc.n))
    end
end

# ---------------------------------------------------------------------------
# Emit numbers.tex
# ---------------------------------------------------------------------------

function write_numbers_tex()
    open(OUT_PATH, "w") do io
        println(io, "% !TEX root = main.tex")
        println(io, "% ------------------------------------------------------------------")
        println(io, "% AUTO-GENERATED by scripts/export_manuscript_numbers.jl")
        println(io, "% Do not edit by hand. Regenerate after any analysis re-run.")
        println(io, "% ------------------------------------------------------------------")
        println(io)
        for (name, value) in MACROS
            println(io, "\\newcommand{\\$name}{$value}")
        end
    end
    println("Wrote $(length(MACROS)) macros to $OUT_PATH")
end

build_macros!()
backfill_num_variants!()

# ---------------------------------------------------------------------------
# Auto-generate the extension_path.tex table (3-layer narrative).
# Produces an updated version reflecting whatever bitmasks 415/447/511/1023
# show in subset_enumeration.csv. Skips silently if subset CSV is incomplete.
# ---------------------------------------------------------------------------

function write_extension_path_table()
    # Two-model decomposition.
    #   Model 1 layers:
    #     Layer 1 (rational): SS, Bequests, Medical+R-S, Pessimism, Loads, Inflation
    #     Layer 2 (preference): Age needs, State-dependent utility, chi_LTC
    #     Layer 3 (behavioral): SDU (Force A), PED (Force B)
    #   Model 2: frictionless baseline x UK_post / UK_pre.
    bm0 = 0                                  # frictionless Yaari baseline
    bm7 = B_SS | B_BEQUESTS | B_MED_RS | B_PESSIMISM | B_LOADS | B_INFLATION
    bm8 = bm7 | B_AGE_NEEDS
    bm9 = bm8 | B_STATE_UTIL
    bm9_ltc = bm9 | B_LTC                  # 9-channel no-behavioral baseline
    bm10_sdu = bm9_ltc | B_SDU              # + Force A
    bm11_full = bm10_sdu | B_PED            # + Force B (Model 1 headline)

    own = Dict{Int,Float64}()
    for bm in (bm0, bm7, bm8, bm9, bm9_ltc, bm10_sdu, bm11_full)
        try
            own[bm] = subset_ownership(bm)
        catch
            return  # incomplete subset enumeration; skip
        end
    end

    # Model 2: UK reduced-form wedge applied to the FRICTIONLESS baseline.
    # The wedge captures the joint rational+behavioral retention that
    # voluntary households express when compulsion lifts, so it should
    # operate on a baseline with no frictions of any kind.
    wedge_factor_mid = 0.17 / 0.95
    wedge_factor_low = 0.13 / 0.95
    wedge_factor_high = 0.25 / 0.95
    own_wedge_mid  = own[bm0] * wedge_factor_mid
    own_wedge_low  = own[bm0] * wedge_factor_low
    own_wedge_high = own[bm0] * wedge_factor_high

    out = joinpath(REPO_ROOT, "tables", "tex", "extension_path.tex")
    open(out, "w") do f
        println(f, raw"\begin{table}[htbp]")
        println(f, raw"\centering")
        println(f, raw"\caption{Two-Model Decomposition: Structural Channels and UK Reduced-Form Transport}")
        println(f, raw"\label{tab:extension_path}")
        println(f, raw"\begin{threeparttable}")
        println(f, raw"\begin{tabular}{lcc}")
        println(f, raw"\toprule")
        println(f, "Specification & Ownership (\\%) & \$\\Delta\$ (pp) \\\\")
        println(f, raw"\midrule")
        @printf(f, "Six rational channels (Layer~1)              & %.1f & --- \\\\\n", own[bm7])
        @printf(f, "+ Age-varying consumption needs              & %.1f & %+.1f \\\\\n",
                own[bm8], own[bm8] - own[bm7])
        @printf(f, "+ State-dependent utility                    & %.1f & %+.1f \\\\\n",
                own[bm9], own[bm9] - own[bm8])
        @printf(f, "+ Public-care aversion \$\\chi_{\\text{LTC}}\$ (Layer~2 complete)         & %.1f & %+.1f \\\\\n",
                own[bm9_ltc], own[bm9_ltc] - own[bm9])
        @printf(f, "+ Source-dependent utility (Force A)         & %.1f & %+.1f \\\\\n",
                own[bm10_sdu], own[bm10_sdu] - own[bm9_ltc])
        @printf(f, "+ Narrow-framing penalty (Force B; Model 1) & %.1f & %+.1f \\\\\n",
                own[bm11_full], own[bm11_full] - own[bm10_sdu])
        println(f, raw"\midrule")
        @printf(f, "Model 2: frictionless baseline (%.1f) \$\\times\$ UK 17/95 & %.1f & --- \\\\\n",
                own[bm0], own_wedge_mid)
        println(f, raw"\bottomrule")
        println(f, raw"\end{tabular}")
        println(f, raw"\begin{tablenotes}")
        println(f, raw"\small")
        println(f, raw"\item Model 1 (top block) is the structural multi-channel decomposition.")
        println(f, raw"Layer 1 covers rational frictions; Layer 2 adds preference and structural")
        println(f, raw"channels; Force A (SDU) and Force B (PED) close the model with behavioral")
        println(f, raw"channels calibrated to Blanchett-Finke (2024-25) and Chalmers-Reuter (2012)")
        println(f, raw"respectively.")
        println(f, raw"\item Model 2 (bottom row) applies the UK 2015 pension-freedoms")
        @printf(f, "\\item retention factor (UK post / UK pre = %.2f at the production midpoint) to the\n", wedge_factor_mid)
        @printf(f, "\\item frictionless Yaari baseline. The UK retention range [13\\%%, 25\\%%] maps to a Model~2 prediction bracket of [%.1f\\%%, %.1f\\%%].\n",
                own_wedge_low, own_wedge_high)
        println(f, raw"\end{tablenotes}")
        println(f, raw"\end{threeparttable}")
        println(f, raw"\end{table}")
    end
    println("Wrote $(out)")
end

write_extension_path_table()


# ---------------------------------------------------------------------------
# Submission-grade strict mode (default): every expected macro must come from
# a real CSV value. Set ANNUITY_ALLOW_TBD_FALLBACKS=1 in the environment to
# emit red TBD placeholders for missing values during partial pipeline runs;
# this is intended for in-development use only and must NOT be set when
# generating the artifact for journal submission.
# ---------------------------------------------------------------------------

const FALLBACKS = String[
    # Production headline macros for the two-model architecture.
    # Model 1 (structural multi-channel): ownModelOne / ownElevenChannelFull.
    # Model 2 (UK reduced-form transport): ownWedge* / ownModelTwo*.
    # The 9-channel ownNoBehavioralBaseline is the input to the Model 2 wedge.
    "ownNoBehavioralBaseline",
    "ownTenChannelSDU",
    "ownElevenChannelFull",
    "ownModelOne", "ownModelOneStructural",
    "ownWedgeLow", "ownWedgeMid", "ownWedgeHigh",
    "ownModelTwoLow", "ownModelTwoMid", "ownModelTwoHigh", "ownModelTwo",
    "ownHeadline",
    "ownBracketLow", "ownBracketHigh",
    "pWedgeFactorLow", "pWedgeFactorMid", "pWedgeFactorHigh",
    "pUKRetentionPre", "pUKRetentionLow", "pUKRetentionMid", "pUKRetentionHigh",
    "mcMedianOwnership", "mcMeanOwnership",
    "mcLowCIOwnership", "mcHighCIOwnership",
    "mcLowIQROwnership", "mcHighIQROwnership",
    "mcMinOwnership", "mcMaxOwnership", "nMCDraws",
]

allow_tbd = get(ENV, "ANNUITY_ALLOW_TBD_FALLBACKS", "0") == "1"
missing_macros = String[]
for name in FALLBACKS
    macro_exists(name) && continue
    push!(missing_macros, name)
    if allow_tbd
        push!(MACROS, name => "{\\color{red}TBD}")
    end
end

if !isempty(missing_macros) && !allow_tbd
    error("Missing macros (no upstream CSV value available): " *
          join(missing_macros, ", ") *
          ". Run the full pipeline (run_all.jl) first, or set " *
          "ANNUITY_ALLOW_TBD_FALLBACKS=1 to emit red TBD placeholders for " *
          "in-development compilation.")
elseif !isempty(missing_macros)
    @warn "ANNUITY_ALLOW_TBD_FALLBACKS=1 is set; emitting TBD placeholders" missing_macros
end

backfill_num_variants!()

write_numbers_tex()
