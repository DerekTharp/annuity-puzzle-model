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
# Eleven channels: six rational + three preference/structural + two behavioral.
# Medical and R-S correlation are combined into a single channel because the
# R-S mechanism's quantitative bite operates through the interaction with
# stochastic medical costs.
const B_SS           = 1 << 0
const B_BEQUESTS     = 1 << 1
const B_MED_RS       = 1 << 2   # Combined: medical risk + R-S correlation
const B_PESSIMISM    = 1 << 3
const B_AGE_NEEDS    = 1 << 4
const B_STATE_UTIL   = 1 << 5
const B_LOADS        = 1 << 6
const B_INFLATION    = 1 << 7
const B_LTC          = 1 << 8   # Public-care aversion (Ameriks 2011 JF, 2020 JPE)
const B_SDU          = 1 << 9   # Source-dependent utility
const B_PED          = 1 << 10  # Narrow-framing at-purchase penalty

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

# welfare_counterfactuals.csv is RFC-4180 quoted; scenario names and descriptions
# embed commas. Schema: scenario, mwr, inflation, psi, c_floor, ss_scale,
# ownership_pct, mean_alpha, description.
function welfare_counterfactual(scenario::AbstractString)
    path = joinpath(CSV_DIR, "welfare_counterfactuals.csv")
    isfile(path) || error("Missing CSV: $path")
    for (i, line) in enumerate(eachline(path))
        i == 1 && continue  # header
        isempty(strip(line)) && continue
        f = parse_csv_row(line)
        length(f) >= 8 && f[1] == scenario || continue
        return (mwr=parse(Float64, f[2]),
                inflation=parse(Float64, f[3]),
                psi=parse(Float64, f[4]),
                c_floor=parse(Float64, f[5]),
                ss_scale=parse(Float64, f[6]),
                ownership_pct=parse(Float64, f[7]),
                mean_alpha=parse(Float64, f[8]))
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
    # Production CSV contains a single bundled "Medical+R-S" row. If absent,
    # the exporter fails loudly: adding two disjoint Shapley values does not
    # equal the merged-player Shapley value, so synthesis is incorrect.
    if !haskey(out, "Medical+R-S")
        error("shapley_exact.csv is missing the bundled 'Medical+R-S' row. " *
              "Re-run scripts/run_subset_enumeration.jl.")
    end
    out
end

# Compute the 9-channel Shapley headline by restricting the 11-channel
# subset enumeration to subsets where SDU (bit 9) and PED (bit 10) are off.
# This is the structural (rational + preference + chi_LTC) attribution
# without the exploratory behavioral channels muddying the contribution
# magnitudes. Returns Dict{channel_name => Shapley value in pp} where
# pp is signed (negative for boosters).
function shapley_nine_channel()
    rows, _ = read_csv("subset_enumeration.csv")
    lookup = Dict{Int, Float64}()
    for r in eachrow(rows)
        bm = Int(r[1])
        # Restrict to subsets with SDU (bit 9) and PED (bit 10) OFF.
        ((bm >> 9) & 1 == 0) && ((bm >> 10) & 1 == 0) || continue
        lookup[bm] = Float64(r[3])  # ownership_pct
    end
    haskey(lookup, 0) || error("Empty subset (bitmask 0) missing from subset_enumeration.csv")
    yaari = lookup[0]
    full_mask_9 = (1 << 9) - 1  # 511 with all 9 non-behavioral channels on
    haskey(lookup, full_mask_9) || error("9-channel full subset (bitmask 511) missing")
    total_drop = yaari - lookup[full_mask_9]

    n = 9
    # Precompute factorials for the Shapley weights
    fact = zeros(Int, n + 1)
    fact[1] = 1
    for k in 1:n
        fact[k + 1] = fact[k] * k
    end

    # Channel names in bitmask order (matches run_subset_enumeration.jl)
    names = ["SS", "Bequests", "Medical+R-S", "Pessimism", "Age needs",
             "State utility", "Loads", "Inflation", "Public-care aversion (LTC)"]

    out = Dict{String, NamedTuple{(:value_pp, :share_pct), Tuple{Float64, Float64}}}()
    for i in 1:n
        bit_i = 1 << (i - 1)
        phi = 0.0
        for s_mask in 0:full_mask_9
            (s_mask & bit_i) != 0 && continue  # skip if i is in S
            s_size = count_ones(s_mask)
            s_union_i = s_mask | bit_i
            # Marginal contribution of i to coalition S, expressed as drop:
            #   mc = ownership(S) - ownership(S ∪ {i})
            mc = lookup[s_mask] - lookup[s_union_i]
            weight = Float64(fact[s_size + 1]) * Float64(fact[n - s_size]) / Float64(fact[n + 1])
            phi += weight * mc
        end
        share = total_drop > 0 ? phi / total_drop * 100 : 0.0
        out[names[i]] = (value_pp=phi, share_pct=share)
    end
    return out
end

# robustness_full.csv is RFC-4180 quoted; specification fields embed commas
# (e.g. "g=2.5,pi=1%"). parse_csv_row splits each row into (category, spec, rate).
function robustness_ownership(category::AbstractString, specification::AbstractString)
    path = joinpath(CSV_DIR, "robustness_full.csv")
    isfile(path) || error("Missing CSV: $path")
    for (i, line) in enumerate(eachline(path))
        i == 1 && continue
        isempty(strip(line)) && continue
        f = parse_csv_row(line)
        length(f) == 3 && f[1] == category && f[2] == specification || continue
        return parse(Float64, rstrip(f[3], '%'))
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
    wealth = Float64.(raw[:, 1])
    n_elig = count(wealth .>= MIN_WEALTH)
    n_above_wmax = count(wealth .> W_MAX)
    (; n_total=n, n_eligible=n_elig,
       pct_above_wmax=100 * n_above_wmax / n)
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
    def!("pMinPurchase",        fmt_dollar(MIN_PURCHASE))
    def!("pChiLTC",             fmt_num(CHI_LTC; digits=2))
    def!("pLambdaW",            fmt_num(LAMBDA_W; digits=3))
    def!("pPsiPurchase",        fmt_num(PSI_PURCHASE; digits=2))
    def!("pPsiPurchaseCRef",    latex_commas(Int(PSI_PURCHASE_C_REF)))
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
    def!("pHazardPoor",         fmt_num(HAZARD_MULT[3]; digits=2))

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
    def!("pctHRSAboveWmax",     fmt_pct(hrs.pct_above_wmax; digits=1))

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
    # + Medical risk + R-S correlation (combined channel)
    def!("ownAddMedRS",         fmt_pct(subset_ownership(B_SS | B_BEQUESTS | B_MED_RS); digits=1))
    # + Pessimism
    def!("ownAddPessimism",     fmt_pct(subset_ownership(B_SS | B_BEQUESTS | B_MED_RS | B_PESSIMISM); digits=1))
    # + Loads (skip age needs / state utility — these come in the extension table)
    def!("ownAddLoads",         fmt_pct(subset_ownership(B_SS | B_BEQUESTS | B_MED_RS | B_PESSIMISM | B_LOADS); digits=1))
    # Sequential decomposition macros under the eleven-channel structure.
    # Layer 1 (rational): SS, Bequests, MedRS, Pessimism, Loads, Inflation
    # Layer 2 (preference): Age needs, State utility, LTC (chi_ltc structural)
    # Layer 3 (behavioral, exploratory): SDU, PED
    #
    # 6-channel rational (SS+Bequests+MedRS+Pessimism+Loads+Inflation; bitmask 207)
    def!("ownSixChannel",       fmt_pct(subset_ownership(B_SS | B_BEQUESTS | B_MED_RS | B_PESSIMISM | B_LOADS | B_INFLATION); digits=1))
    # 7-channel: + age-varying consumption needs (bitmask 223)
    def!("ownSevenChannelExt",  fmt_pct(subset_ownership(B_SS | B_BEQUESTS | B_MED_RS | B_PESSIMISM | B_AGE_NEEDS | B_LOADS | B_INFLATION); digits=1))
    # 8-channel: + state-dependent utility (bitmask 255)
    def!("ownEightChannelExt",  fmt_pct(subset_ownership(B_SS | B_BEQUESTS | B_MED_RS | B_PESSIMISM | B_AGE_NEEDS | B_STATE_UTIL | B_LOADS | B_INFLATION); digits=1))
    # 9-channel: + LTC / public-care aversion (bitmask 511). This is the
    # no-behavioral baseline that anchors the structural Model 1 build.
    own_no_behavioral_pct = NaN
    try
        own_no_behavioral_pct = subset_ownership(B_SS | B_BEQUESTS | B_MED_RS | B_PESSIMISM | B_AGE_NEEDS | B_STATE_UTIL | B_LOADS | B_INFLATION | B_LTC)
        def!("ownNineChannelLTC", fmt_pct(own_no_behavioral_pct; digits=1))
        def!("ownNoBehavioralBaseline", fmt_pct(own_no_behavioral_pct; digits=1))
    catch e
        @warn "Skipping ownNineChannelLTC / ownNoBehavioralBaseline (pipeline not yet run)" exception=e
    end

    # 10-channel: + SDU (bitmask 1023)
    own_ten_sdu_pct = NaN
    try
        own_ten_sdu_pct = subset_ownership(B_SS | B_BEQUESTS | B_MED_RS | B_PESSIMISM | B_AGE_NEEDS | B_STATE_UTIL | B_LOADS | B_INFLATION | B_LTC | B_SDU)
        def!("ownTenChannelSDU", fmt_pct(own_ten_sdu_pct; digits=1))
    catch e
        @warn "Skipping ownTenChannelSDU" exception=e
    end

    # 11-channel: + PED (bitmask 2047). Full Model 1 structural headline.
    own_model1_pct = NaN
    try
        own_model1_pct = subset_ownership(B_SS | B_BEQUESTS | B_MED_RS | B_PESSIMISM | B_AGE_NEEDS | B_STATE_UTIL | B_LOADS | B_INFLATION | B_LTC | B_SDU | B_PED)
        def!("ownElevenChannelFull", fmt_pct(own_model1_pct; digits=1))
        def!("ownModelOne", fmt_pct(own_model1_pct; digits=1))
        def!("ownModelOneStructural", fmt_pct(own_model1_pct; digits=1))
    catch e
        @warn "Skipping ownElevenChannelFull / ownModelOne" exception=e
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

    # Combined Medical + R-S correlation delta. The channels are coupled
    # (R-S's quantitative bite operates through the interaction with
    # medical risk), so they enter as a single bundle.
    own_pre_med_rs = subset_ownership(B_SS | B_BEQUESTS)
    own_post_med_rs = subset_ownership(B_SS | B_BEQUESTS | B_MED_RS)
    def!("deltaMedRS",          fmt_num(own_post_med_rs - own_pre_med_rs; digits=1))
    def!("magDeltaMedRS",       fmt_num(abs(own_post_med_rs - own_pre_med_rs); digits=1))
    def!("retentionMedRS",      fmt_pct(own_post_med_rs / own_pre_med_rs * 100; digits=1))

    # ======================================================================
    # Section E — Extension path
    # 6-channel rational (SS, Bequests, Med+R-S, Pessimism, Loads, Inflation)
    # → +Age needs → +State utility = 8-channel.
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
    # Combined Medical + R-S correlation channel.
    def!("shapMedRS",           fmt_num(sh["Medical+R-S"].value_pp; digits=1))
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
        def!("shapPED",            fmt_num(sh["Narrow-framing penalty (PED)"].value_pp; digits=1))
        def!("shapNarrowFraming",  fmt_num(sh["Narrow-framing penalty (PED)"].value_pp; digits=1))
    end

    def!("shapShareSS",         fmt_pct(sh["SS"].share_pct; digits=0))
    def!("shapShareBequests",   fmt_pct(sh["Bequests"].share_pct; digits=0))
    def!("shapShareMedRS",      fmt_pct(sh["Medical+R-S"].share_pct; digits=0))
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

    # ----------------------------------------------------------------------
    # Section F2 — Nine-channel Shapley (headline structural attribution)
    # The eleven-channel Shapley above mixes the exploratory behavioral
    # parameters (SDU, PED) with the structural channels. The nine-channel
    # Shapley restricts the cooperative game to subsets where SDU and PED
    # are off (bits 9 and 10 of the bitmask), giving an order-independent
    # attribution among the rational, preference, and structural-LTC
    # channels alone. This is the disciplined Model 1 attribution; the
    # eleven-channel Shapley is reported as the exploratory extension.
    # ----------------------------------------------------------------------
    sh9 = shapley_nine_channel()
    for (key, name) in [
        ("NineSS",         "SS"),
        ("NineBequests",   "Bequests"),
        ("NineMedRS",      "Medical+R-S"),
        ("NinePessimism",  "Pessimism"),
        ("NineAgeNeeds",   "Age needs"),
        ("NineStateUtil",  "State utility"),
        ("NineLoads",      "Loads"),
        ("NineInflation",  "Inflation"),
        ("NineLTC",        "Public-care aversion (LTC)"),
    ]
        def!("shap" * key,       fmt_num(sh9[name].value_pp; digits=1))
        # One decimal for sub-half-percent shares so a small negative share
        # renders as "-0.4\%" rather than the confusing "-0\%".
        def!("shapShare" * key,  abs(sh9[name].share_pct) < 0.5 ?
             fmt_pct(sh9[name].share_pct; digits=1) : fmt_pct(sh9[name].share_pct; digits=0))
    end
    # Share of the summed positive (suppressing) contributions, alongside the
    # net-drop shares above: the net-drop denominator includes offsetting
    # negative components (SS, LTC), which can make single-channel shares read
    # larger than the suppressor pool supports.
    let pos = sum(v.value_pp for v in values(sh9) if v.value_pp > 0)
        def!("shapPosShareNineLoads", fmt_pct(100 * sh9["Loads"].value_pp / pos; digits=0))
    end
    # Net drop the nine-channel game attributes (frictionless floor-inclusive
    # benchmark minus the full model), and the grand-coalition Med+R-S marginal
    # used for the duality discussion (bitmask 507 = 511 with bit 2 off).
    def!("shapNineTotalDrop", fmt_num(sum(v.value_pp for v in values(sh9)); digits=1) * "~pp")
    def!("ownGrandNoMedRS", fmt_pct(subset_ownership(511 & ~(1 << 2)); digits=1))

    # ======================================================================
    # Section F3 — Ranking robustness sub-games (post-processed, no solves):
    # grid_robustness_shapley.csv (512-subset game at finer grids) and
    # subgame7_shapley.csv (weighted-utility channels removed as players).
    # ======================================================================
    let path = joinpath(CSV_DIR, "grid_robustness_shapley.csv")
        if isfile(path)
            raw, _ = readdlm(path, ',', Any; header=true)  # grid, channel, shapley_pp, abs_rank, full_own_pct
            g = Dict{Tuple{String,String},Float64}(
                (String(raw[r, 1]), String(raw[r, 2])) => Float64(raw[r, 3]) for r in 1:size(raw, 1))
            fo = Dict{String,Float64}(String(raw[r, 1]) => Float64(raw[r, 5]) for r in 1:size(raw, 1))
            def!("gridShapLoadsHundred",        fmt_num(g[("g100x40", "Loads")]; digits=1))
            def!("gridShapBequestsHundred",     fmt_num(g[("g100x40", "Bequests")]; digits=1))
            def!("gridShapLoadsHundredTwenty",  fmt_num(g[("g120x50", "Loads")]; digits=1))
            def!("gridShapBequestsHundredTwenty", fmt_num(g[("g120x50", "Bequests")]; digits=1))
            def!("gridOwnHundred",              fmt_pct(fo["g100x40"]; digits=1))
            def!("gridOwnHundredTwenty",        fmt_pct(fo["g120x50"]; digits=1))
        end
    end
    let path = joinpath(CSV_DIR, "subgame7_shapley.csv")
        if isfile(path)
            raw, _ = readdlm(path, ',', Any; header=true)  # channel, shapley_pp (ownership convention), full_own_pct
            s = Dict{String,Float64}(String(raw[r, 1]) => -Float64(raw[r, 2]) for r in 1:size(raw, 1))  # flip to drop convention
            def!("subgameLoads",     fmt_num(s["Loads"]; digits=1))
            def!("subgameBequests",  fmt_num(s["Bequests"]; digits=1))
            def!("subgameMedRS",     fmt_num(s["Medical+R-S"]; digits=1))
            def!("subgamePessimism", fmt_num(s["Pessimism"]; digits=1))
        end
    end

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
    # Section H2 — Referee-proofing recomputations (run_referee_proofing.jl):
    # alternative-baseline Shapley games and by-band ownership at policy MWRs.
    # ======================================================================
    let path = joinpath(CSV_DIR, "referee_proofing_shapley.csv")
        if isfile(path)
            raw, _ = readdlm(path, ',', Any; header=true)  # game, channel, shapley_value_pp, abs_rank
            shp = Dict{Tuple{String,String},Float64}(
                (String(raw[r, 1]), String(raw[r, 2])) => Float64(raw[r, 3])
                for r in 1:size(raw, 1))
            def!("rpLoadsAtMwrEightyFive", fmt_num(shp[("mwr085", "Loads")]; digits=1))
            def!("rpBequestsAtMwrEightyFive", fmt_num(shp[("mwr085", "Bequests")]; digits=1))
            def!("rpLoadsAtMwrNinety", fmt_num(shp[("mwr090", "Loads")]; digits=1))
            def!("rpBequestsAtMwrNinety", fmt_num(shp[("mwr090", "Bequests")]; digits=1))
            def!("rpLoadsAtGammaLow", fmt_num(shp[("gamma15", "Loads")]; digits=1))
            def!("rpBequestsAtGammaLow", fmt_num(shp[("gamma15", "Bequests")]; digits=1))
        end
    end
    let path = joinpath(CSV_DIR, "referee_proofing_byband.csv")
        if isfile(path)
            raw, hdr = readdlm(path, ',', Any; header=true)
            for r in 1:size(raw, 1)
                key = Float64(raw[r, 1]) == 0.90 ? "Ninety" : "NinetyFive"
                def!("bybandMwr" * key * "Agg",   fmt_pct(Float64(raw[r, 2]); digits=1))
                def!("bybandMwr" * key * "Qtwo",  fmt_pct(Float64(raw[r, 4]); digits=1))
                def!("bybandMwr" * key * "Qthree", fmt_pct(Float64(raw[r, 5]); digits=1))
                def!("bybandMwr" * key * "Qfour", fmt_pct(Float64(raw[r, 6]); digits=1))
            end
        end
    end

    # ======================================================================
    # Section I — Robustness (gamma, inflation, psi sweeps)
    # ======================================================================
    for (key, spec) in [
        ("OnePointFive",  "gamma=1.50"),
        ("Two",           "gamma=2.00"),
        ("TwoPointTwo",   "gamma=2.20"),
        ("TwoPointThree", "gamma=2.30"),
        ("TwoPointFour",  "gamma=2.40"),
        ("TwoPointFive",  "gamma=2.50"),
        ("TwoPointSix",   "gamma=2.60"),
        ("Three",         "gamma=3.00"),
        ("ThreePointFive","gamma=3.50"),
        ("Four",          "gamma=4.00"),
        ("Five",          "gamma=5.00"),
    ]
        def!("ownGamma" * key, fmt_pct(robustness_ownership("Gamma sweep", spec); digits=1))
    end

    # Pairwise channel interactions (pp), from pairwise_interactions.csv
    let prows = read_csv("pairwise_interactions.csv")[1]
        pairwise(c1, c2) = begin
            for r in eachrow(prows)
                if strip(string(r[1])) == c1 && strip(string(r[2])) == c2
                    return Float64(r[end])
                end
            end
            error("pairwise interaction $c1 x $c2 not found")
        end
        def!("pairwiseSSLoads",    fmt_num(pairwise("SS", "Loads"); digits=1))
        def!("pairwiseMedRSLoads", fmt_num(pairwise("Medical+R-S", "Loads"); digits=1))
    end

    # Multi-gamma decomposition ownership at the R-S and survival-pessimism steps
    # (columns: 1=step, 2=own_gamma2.0, 5=own_gamma2.5, 8=own_gamma3.0)
    let mrows = read_csv("multigamma_decomposition.csv")[1]
        mg(step, col) = begin
            for r in eachrow(mrows)
                if occursin(step, string(r[1]))
                    return Float64(r[col])
                end
            end
            error("multigamma step $step not found")
        end
        def!("mgRSGammaTwo",       fmt_pct(mg("Health-mortality", 2); digits=1))
        def!("mgRSGammaThree",     fmt_pct(mg("Health-mortality", 8); digits=1))
        def!("mgPessGammaTwo",     fmt_pct(mg("Survival pessimism", 2); digits=1))
        def!("mgPessGammaTwoFive", fmt_pct(mg("Survival pessimism", 5); digits=1))
        def!("mgPessGammaThree",   fmt_pct(mg("Survival pessimism", 8); digits=1))
    end

    # Grid/quadrature convergence summary stats for prose (per-quartile headline config).
    let crows = read_csv("convergence_diagnostics.csv")[1]
        cg(spec) = begin
            for r in eachrow(crows)
                strip(string(r[1])) == "Grid (9-node)" && occursin(spec, string(r[2])) && return Float64(r[3])
            end
            error("conv grid $spec")
        end
        cq(n) = begin
            for r in eachrow(crows)
                strip(string(r[1])) == "Quadrature" && occursin("n_quad=$n", string(r[2])) && return Float64(r[3])
            end
            error("conv quad $n")
        end
        cref = begin
            v = 0.0
            for r in eachrow(crows); strip(string(r[1])) == "Reference" && (v = Float64(r[3])); end
            v
        end
        prod, med, fine, vfine = cg("80x30"), cg("60x20"), cg("100x40"), cg("120x50")
        def!("gridConvProd",     fmt_pct(prod; digits=1))
        def!("gridConvMed",      fmt_pct(med; digits=1))
        def!("gridConvFine",     fmt_pct(fine; digits=1))
        def!("gridConvVeryFine", fmt_pct(vfine; digits=1))
        def!("gridConvRef",      fmt_pct(cref; digits=1))
        def!("gridConvFineStep", fmt_num(abs(vfine - fine); digits=1))
        def!("gridConvBias",     fmt_num(abs(vfine - prod); digits=1))
        def!("gridConvTotalUnc", fmt_num(abs(cref - prod); digits=1))
        def!("quadThree",    fmt_pct(cq(3); digits=1))
        def!("quadNine",     fmt_pct(cq(9); digits=1))
        def!("quadEleven",   fmt_pct(cq(11); digits=1))
        def!("quadThirteen", fmt_pct(cq(13); digits=1))
        def!("quadFifteen",  fmt_pct(cq(15); digits=1))
        def!("quadBand",     fmt_num(cq(15) - cq(9); digits=1))
    end

    # Annuitization-grid (alpha) convergence macros for prose.
    let apath = joinpath(CSV_DIR, "alpha_grid_diagnostics.csv")
        if isfile(apath)
            arows = read_csv("alpha_grid_diagnostics.csv")[1]
            av(spec) = begin
                for r in eachrow(arows)
                    strip(string(r[1])) == spec && return Float64(r[2])
                end
                error("alpha $spec")
            end
            vals = [av("n_alpha=$n") for n in (51, 101, 201, 401)]
            def!("alphaGridCoarse",   fmt_pct(vals[1]; digits=1))
            def!("alphaGridProd",     fmt_pct(vals[2]; digits=1))
            def!("alphaGridFine",     fmt_pct(vals[3]; digits=1))
            def!("alphaGridVeryFine", fmt_pct(vals[4]; digits=1))
            def!("alphaGridBand",     fmt_num(maximum(vals) - minimum(vals); digits=1))
        else
            @warn "Skipping alpha-grid macros (alpha_grid_diagnostics.csv not present)"
        end
    end

    # Euler-residual summary stats for prose.
    let erows = read_csv("euler_residuals.csv")[1]
        eb(label, col) = begin
            for r in eachrow(erows)
                strip(string(r[1])) == label && return Float64(r[col])
            end
            error("euler $label")
        end
        def!("eulerMeanPct",      fmt_pct(eb("Baseline 80x30 (9-node)", 3) * 100; digits=1))
        def!("eulerPctAboveOne",  fmt_pct(eb("Baseline 80x30 (9-node)", 5); digits=1))
        def!("eulerPctAboveFive", fmt_pct(eb("Baseline 80x30 (9-node)", 6); digits=1))
        def!("eulerPctOneCoarse", fmt_pct(eb("Grid 40x15 (9-node)", 5); digits=1))
        def!("eulerPctOneFine",   fmt_pct(eb("Grid 100x40 (9-node)", 5); digits=1))
    end

    # Medical-expenditure moment fits: analytic implications of the calibrated
    # lognormal process, deterministic given the medical params in parameters.jl.
    let ptext = read(joinpath(@__DIR__, "..", "src", "parameters.jl"), String)
        getp(nm) = parse(Float64, match(Regex("$(nm)::Float64 = ([0-9.]+)"), ptext).captures[1])
        mu0, gr, sig = getp("medical_mu_base"), getp("medical_mu_growth"), getp("medical_sigma")
        muT(t) = mu0 + gr * (t - 65)
        def!("medMeanSeventy", fmt_dollar(exp(muT(70) + sig^2 / 2)))
        def!("medMeanHundred", fmt_dollar(exp(muT(100) + sig^2 / 2)))
        def!("medPctNinetyFive", fmt_dollar(exp(muT(100) + 1.6449 * sig)))
    end

    # Inflation is reported via the combined Gamma×Inflation sweep
    for (key, spec) in [
        ("One",   "g=2.5,pi=1%"),
        ("Two",   "g=2.5,pi=2%"),
        ("Three", "g=2.5,pi=3%"),
    ]
        def!("ownInflation" * key, fmt_pct(robustness_ownership("Gamma×Inflation", spec); digits=1))
    end

    # Survival pessimism sweep. Baseline = the production SURVIVAL_PESSIMISM
    # (0.96); 0.981 is the O'Dea-Sturrock implied scalar, a sweep point only.
    for (key, spec) in [
        ("Objective",     "psi=1.000"),
        ("Baseline",      "psi=0.960"),
        ("NinetySeven",   "psi=0.970"),
        ("NinetyEightOne","psi=0.981"),
        ("NinetyNine",    "psi=0.990"),
    ]
        def!("ownPsi" * key, fmt_pct(robustness_ownership("Survival pessimism", spec); digits=1))
    end

    # MWR sweep — feeds the MWR sensitivity table in main.tex. The lower
    # end of the sweep deliberately includes the Mitchell et al. 1999
    # population-mortality estimate as a sensitivity anchor; production
    # MWR is 0.87 (Wettstein 2021) defined in config.jl.
    for (key, spec) in [
        ("EightyTwo",    "MWR=0.82"),  # ALLOWLIST: sensitivity-sweep anchor, not the production MWR
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
    # Section J — SS cut robustness (from ss_cut_robustness.csv)
    # and ss_cut_robustness.csv if finer grid needed
    # ======================================================================
    def!("ownSSCutZero",       fmt_pct(ss_cut_ownership(0);   digits=1))
    def!("ownSSCutTen",        fmt_pct(ss_cut_ownership(10);  digits=1))
    def!("ownSSCutFifteen",    fmt_pct(ss_cut_ownership(15);  digits=1))
    def!("ownSSCutTwentyTwo",  fmt_pct(ss_cut_ownership(22);  digits=1))
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

    # FLN raw endpoint [1, 0.90, 0.75]: state-utility sensitivity lower bound.
    # The production calibration is the FLN central midpoint (ownEightChannelExt).
    def!("ownNineChannelFLN",  fmt_pct(fln.ownership_pct; digits=1))

    # Reichling-Smetters softer mapping (robustness case)
    def!("pHealthUtilFairRS",  fmt_num(rs.phi_fair;  digits=2))
    def!("pHealthUtilPoorRS",  fmt_num(rs.phi_poor;  digits=2))
    def!("ownNineChannelRS",   fmt_pct(rs.ownership_pct; digits=1))

    # Difference between the two state-utility mappings.
    def!("deltaNineChannelRSmFLN", fmt_num(rs.ownership_pct - fln.ownership_pct; digits=1))

    # ======================================================================
    # Section L — Monte Carlo parameter uncertainty
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

    # ======================================================================
    # Section M — Reframe exhibits: gamma-stability concordance, by-wealth
    # Shapley, SS-cut incidence, and empirical-gradient validation. Each
    # block is guarded so a partial pipeline run still produces numbers.tex.
    # ======================================================================
    colof(hdr, name) = findfirst(==(name), vec(hdr))

    # Gamma-stability of the channel ranking (Class 1 / Class 5).
    gs_path = joinpath(CSV_DIR, "shapley_gamma_stability_summary.csv")
    if isfile(gs_path)
        gs, gh = read_csv("shapley_gamma_stability_summary.csv")
        gam   = Float64.(gs[:, colof(gh, "gamma")])
        top1  = strip.(string.(gs[:, colof(gh, "top1_ownership")]))
        spsup = Float64.(gs[:, colof(gh, "spearman_suppressors")])
        fullo = Float64.(gs[:, colof(gh, "full_ownership_pct")])
        i25   = findfirst(g -> isapprox(g, 2.5; atol=1e-6), gam)
        i25 === nothing && (i25 = 1)
        def!("gammaStabTopOne",      String(top1[i25]))
        def!("gammaStabSpearmanSup", fmt_num(spsup[i25]; digits=2))
        def!("gammaStabTopOneCount", string(count(==(top1[i25]), top1)))
        def!("gammaStabNGamma",      string(length(gam)))
        def!("ownGammaSweepLow",     fmt_pct(minimum(fullo); digits=1))
        def!("ownGammaSweepHigh",    fmt_pct(maximum(fullo); digits=1))
    end

    # By-wealth 9-channel Shapley: Loads rank across bins (Class 3).
    bw_path = joinpath(CSV_DIR, "shapley_by_wealth.csv")
    if isfile(bw_path)
        bw, bh = read_csv("shapley_by_wealth.csv")
        chan = strip.(string.(bw[:, colof(bh, "channel")]))
        li = findfirst(==("Loads"), chan)
        if li !== nothing
            lr = [Int(bw[li, colof(bh, "rank_q$q")]) for q in 1:4]
            def!("shapByWealthLoadsTopBins", string(count(==(1), lr)))
            def!("shapByWealthNBins", "4")
        end
    end

    # Ownership concentration in the top wealth bin (full 9-channel, mask 511).
    se, sh = read_csv("subset_enumeration.csv")
    if colof(sh, "own_q4") !== nothing
        bm = Int.(se[:, colof(sh, "bitmask")])
        r511 = findfirst(==(511), bm)
        if r511 !== nothing
            def!("ownFullQone",  fmt_pct(Float64(se[r511, colof(sh, "own_q1")]); digits=1))
            def!("ownFullQfour", fmt_pct(Float64(se[r511, colof(sh, "own_q4")]); digits=1))
        end
    end

    # SS-cut incidence by wealth (Class 4).
    sc_path = joinpath(CSV_DIR, "ss_cut_by_wealth.csv")
    if isfile(sc_path)
        sc, sch = read_csv("ss_cut_by_wealth.csv")
        qv  = Int.(sc[:, colof(sch, "quartile")])
        cv  = Float64.(sc[:, colof(sch, "cut_pct")])
        ov  = Float64.(sc[:, colof(sch, "ownership_pct")])
        cell(qq, cc) = (k = findfirst(i -> qv[i] == qq && isapprox(cv[i], cc; atol=1e-6), eachindex(qv));
                        k === nothing ? NaN : ov[k])
        def!("ssCutWealthQfourBase",  fmt_pct(cell(4, 0.0);  digits=1))
        def!("ssCutWealthQfourTrust", fmt_pct(cell(4, 22.0); digits=1))
        def!("ssCutWealthBottomResp", fmt_pct(cell(1, 22.0); digits=1))
    end

    # Empirical-gradient validation: predicted-sign concordance (Class 1 test).
    eg_path = joinpath(CSV_DIR, "empirical_gradients_logit.csv")
    if isfile(eg_path)
        eg, egh = read_csv("empirical_gradients_logit.csv")
        ps = strip.(string.(eg[:, colof(egh, "predicted_sign")]))
        sm = strip.(string.(eg[:, colof(egh, "sign_match")]))
        def!("empSignMatch", string(count(==("yes"), sm)))
        def!("empSignTotal", string(count(x -> x != "", ps)))
    end

    # Extensive-margin gate: F*=0 rational-exclusion finding (Result 1).
    fd_path = joinpath(CSV_DIR, "fstar_distribution.csv")
    if isfile(fd_path)
        fd, fdh = read_csv("fstar_distribution.csv")
        band = strip.(string.(fd[:, colof(fdh, "band")]))
        fz   = Float64.(fd[:, colof(fdh, "frac_fstar_zero")])
        fmid = Float64.(fd[:, colof(fdh, "frac_fstar_below_fc")])
        bi(lbl) = findfirst(==(lbl), band)
        def!("gateFstarZeroBandOne",   fmt_pct(fz[bi("<30k")] * 100;     digits=0))
        def!("gateFstarZeroBandTwo",   fmt_pct(fz[bi("30-120k")] * 100;  digits=0))
        def!("gateFstarZeroBandThree", fmt_pct(fz[bi("120-350k")] * 100; digits=0))
        def!("gateFstarSliverBandTwo", fmt_pct(fmid[bi("30-120k")] * 100; digits=0))
        # Band-1 F*=0 split: value-destroying vs minimum-purchase-infeasible.
        cvd = colof(fdh, "frac_value_destroying"); cinf = colof(fdh, "frac_infeasible")
        if cvd !== nothing && cinf !== nothing
            fvd = Float64.(fd[:, cvd]); finf = Float64.(fd[:, cinf])
            def!("gateValDestrBandOne", fmt_pct(fvd[bi("<30k")] * 100; digits=0))
            def!("gateInfeasBandOne",   fmt_pct(finf[bi("<30k")] * 100; digits=0))
        end
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
# Auto-generate the extension_path.tex table from the current subset
# enumeration. Skips silently if any required bitmask is missing.
# ---------------------------------------------------------------------------

function write_extension_path_table()
    # Sequential channel decomposition.
    #   Layer 1 (rational): SS, Bequests, Medical+R-S, Pessimism, Loads, Inflation
    #   Layer 2 (preference): Age needs, State-dependent utility, chi_LTC
    #   Layer 3 (behavioral): SDU (Force A), PED (Force B)
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

    out = joinpath(REPO_ROOT, "tables", "tex", "extension_path.tex")
    open(out, "w") do f
        println(f, raw"\begin{table}[htbp]")
        println(f, raw"\centering")
        println(f, raw"\caption{Sequential Channel Decomposition}")
        println(f, raw"\label{tab:extension_path}")
        println(f, raw"\begin{threeparttable}")
        println(f, raw"\begin{tabular}{lcc}")
        println(f, raw"\toprule")
        println(f, "Specification & Ownership (\\%) & \$\\Delta\$ (pp) \\\\")
        println(f, raw"\midrule")
        @printf(f, "Six rational channels                        & %.1f & --- \\\\\n", own[bm7])
        @printf(f, "+ Age-varying consumption needs              & %.1f & %+.1f \\\\\n",
                own[bm8], own[bm8] - own[bm7])
        @printf(f, "+ State-dependent utility                    & %.1f & %+.1f \\\\\n",
                own[bm9], own[bm9] - own[bm8])
        @printf(f, "+ Public-care aversion \$\\chi_{\\text{LTC}}\$ (nine-channel baseline) & %.1f & %+.1f \\\\\n",
                own[bm9_ltc], own[bm9_ltc] - own[bm9])
        @printf(f, "+ Source-dependent utility (exploratory)     & %.1f & %+.1f \\\\\n",
                own[bm10_sdu], own[bm10_sdu] - own[bm9_ltc])
        @printf(f, "+ Narrow-framing penalty (exploratory; eleven-channel) & %.1f & %+.1f \\\\\n",
                own[bm11_full], own[bm11_full] - own[bm10_sdu])
        println(f, raw"\bottomrule")
        println(f, raw"\end{tabular}")
        println(f, raw"\begin{tablenotes}")
        println(f, raw"\small")
        println(f, raw"\item Sequential extension path from the six rational channels through")
        println(f, raw"the nine-channel structural baseline to the exploratory eleven-channel")
        println(f, raw"specification; the two behavioral channels (SDU and the narrow-framing")
        println(f, raw"penalty) are un-identified and reported with sensitivity ranges.")
        println(f, raw"\end{tablenotes}")
        println(f, raw"\end{threeparttable}")
        println(f, raw"\end{table}")
    end
    println("Wrote $(out)")
end

write_extension_path_table()


# ---------------------------------------------------------------------------
# Auto-generate the nine-channel Shapley table. This is the headline
# attribution displayed in main.tex Section 5.6; the eleven-channel table
# (shapley_exact.tex, written by run_subset_enumeration.jl) is the
# exploratory extension reported alongside.
# ---------------------------------------------------------------------------

function write_shapley_nine_table()
    sh9 = try
        shapley_nine_channel()
    catch
        return  # subset enumeration incomplete; skip
    end

    # Order channels by signed Shapley value (most-suppressing first, then
    # boosters at the end). Matches the structural narrative: Loads and
    # Medical+R-S as the two largest suppressors; SS as the dominant booster.
    ordered = sort(collect(sh9); by = kv -> -kv[2].value_pp)

    own_frictionless_pct = try
        subset_ownership(0)
    catch
        return
    end
    full_mask_9 = (1 << 9) - 1
    own_full_pct = try
        subset_ownership(full_mask_9)
    catch
        return
    end
    total_drop_pp = own_frictionless_pct - own_full_pct

    out = joinpath(REPO_ROOT, "tables", "tex", "shapley_nine.tex")
    open(out, "w") do f
        println(f, raw"\begin{table}[htbp]")
        println(f, raw"\centering")
        println(f, raw"\caption{Nine-Channel Structural Shapley Decomposition (Headline)}")
        println(f, raw"\label{tab:shapley_nine}")
        println(f, raw"\begin{threeparttable}")
        println(f, raw"\begin{tabular}{lcc}")
        println(f, raw"\toprule")
        println(f, "Channel & Shapley (pp) & Share (\\%) \\\\")
        println(f, raw"\midrule")
        for (name, val) in ordered
            display = name == "SS" ? "Pre-existing income (SS+DB)" : name
            @printf(f, "%s & %+.2f & %+.1f \\\\\n",
                    display, val.value_pp, val.share_pct)
        end
        println(f, raw"\midrule")
        @printf(f, "Total demand drop & %+.2f & 100.0 \\\\\n", total_drop_pp)
        println(f, raw"\bottomrule")
        println(f, raw"\end{tabular}")
        println(f, raw"\begin{tablenotes}")
        println(f, raw"\small")
        @printf(f, "\\item Exact Shapley values over all \$2^9 = 512\$ subsets of the nine structural channels (SDU and PED held off). Positive values are demand-suppressing contributions; negative values are demand-boosting averaged across channel configurations (pre-existing Social Security and DB income raises annuitization on average by providing the income floor, though at the fully-loaded grand coalition it substitutes for private annuities; see text).\n")
        @printf(f, "\\item Frictionless baseline: %.1f\\%%. Nine-channel structural prediction: %.1f\\%%. Total demand drop: %.1f pp.\n",
                own_frictionless_pct, own_full_pct, total_drop_pp)
        println(f, raw"\item The eleven-channel exploratory Shapley (Table~\ref{A-tab:shapley_exact}, appendix) layers the two behavioral channels (SDU, PED) and is reported as a sensitivity exercise rather than the disciplined attribution.")
        println(f, raw"\end{tablenotes}")
        println(f, raw"\end{threeparttable}")
        println(f, raw"\end{table}")
    end
    println("Wrote $(out)")
end

write_shapley_nine_table()


# ---------------------------------------------------------------------------
# Submission-grade strict mode (default): every expected macro must come from
# a real CSV value. Set ANNUITY_ALLOW_TBD_FALLBACKS=1 in the environment to
# emit red TBD placeholders for missing values during partial pipeline runs;
# this is intended for in-development use only and must NOT be set when
# generating the artifact for journal submission.
# ---------------------------------------------------------------------------

const FALLBACKS = String[
    # Production headline macros for the structural decomposition
    # (ownModelOne / ownElevenChannelFull = full structural model).
    "ownNoBehavioralBaseline",
    "ownTenChannelSDU",
    "ownElevenChannelFull",
    "ownModelOne", "ownModelOneStructural",
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
