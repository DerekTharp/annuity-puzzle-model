# =============================================================================
# 04_model_core.jl — Concatenated model module and structural primitives.
#
# This file consolidates the following original source files (in order):
#   src/AnnuityPuzzle.jl       module entry point and exports
#   src/parameters.jl          ModelParams struct and defaults
#   src/utility.jl             CRRA, bequest, source-dependent utility, narrow-framing penalty
#   src/income.jl              Social Security income profile
#   src/lockwood_lifetable.jl  SSA administrative life table builder
#   src/grids.jl               Wealth/annuity/health grid construction + clamp audit
#   src/annuity.jl             Annuity payout-rate computation, MWR loading
#
# To restore the working repository layout, split each banner-delimited
# section back into its original path under src/.
# =============================================================================

#=============================================================================
# ORIGINAL FILE: src/AnnuityPuzzle.jl
#=============================================================================

module AnnuityPuzzle

using Parameters
using Printf
using TOML
using Interpolations
using Optim
using Random
using Distributed
using DelimitedFiles

include("parameters.jl")
include("utility.jl")
include("grids.jl")
include("income.jl")
include("health.jl")
include("annuity.jl")
include("bellman.jl")
include("solve.jl")
include("lockwood_lifetable.jl")
include("wtp.jl")
include("simulation.jl")
include("decomposition.jl")
include("welfare.jl")
include("diagnostics.jl")

export ModelParams, load_params
export utility, bequest_utility, marginal_utility
export flow_utility, consumption_weight, health_utility_weight, purchase_penalty
export build_wealth_grid, build_annuity_grid, build_alpha_grid, build_grids, Grids
export clamp_audit, reset_clamp_audit!, report_clamp_audit
export ss_benefit, ss_benefit_by_wealth, ss_benefit_zero
export survival_prob_deterministic, build_survival_probs, cumulative_survival
export gauss_hermite_normal
export build_health_transition, build_all_health_transitions
export health_adjusted_survival, build_health_survival
export medical_expense_params, mean_medical_expense, apply_medicaid_floor
export compute_payout_rate, annuity_income, post_purchase_wealth
export is_feasible_purchase, annuity_income_real, compute_payout_rate_deferred
export compute_payout_rate_period_certain
export solve_consumption, terminal_value
export Solution, solve_lifecycle, solve_annuitization
export HealthSolution, solve_lifecycle_health, solve_annuitization_health
export LOCKWOOD_CUM_DEATH_PROBS, build_lockwood_survival
export compute_wtp, compute_wtp_lockwood, calibrate_theta, recalibrate_theta_dfj, compute_ownership_rate
export compute_wtp_health, compute_ownership_rate_health
export SimulationResult, simulate_lifecycle, simulate_batch
export DecompositionStep, DecompositionResult
export solve_and_evaluate, run_decomposition, run_multiplicative_analysis
export run_pairwise_interactions
export SS_QUARTILE_LEVELS, SS_QUARTILE_BREAKS
export CEVResult, compute_cev, compute_cev_population, compute_cev_grid
export simulate_welfare_comparison
export parallel_solve
export compute_euler_residuals
export load_hrs_population

"""
    parallel_solve(specs; worker_func)

Apply `worker_func` to each element of `specs`. Uses `pmap` when distributed
workers are available (julia -p N) and we're on the master process. Falls back
to serial `map` if either no workers exist OR we're already executing on a
worker process — the latter avoids nested-pmap deadlocks (each outer worker
would otherwise try to schedule onto the same workers it lives on).
"""
function parallel_solve(worker_func, specs)
    if nworkers() > 1 && Distributed.myid() == 1
        return pmap(worker_func, specs)
    else
        return map(worker_func, specs)
    end
end

"""
    load_hrs_population(path; zero_ss=true, min_wealth=0.0)

Load HRS population sample from CSV. Returns an n x K matrix where K >= 3.
Columns: [wealth, annuity_income, age] at minimum, plus [health] if present
in the CSV (column 4 when CSV has 6+ columns: wealth, perm_income, age,
health, own_life_ann, weight).

When `zero_ss=true` (default), column 2 is zeroed because SS enters via
ss_func in the Bellman equation, not through the A grid.
When `min_wealth > 0`, filters to agents with wealth >= threshold.
"""
function load_hrs_population(path::String; zero_ss::Bool=true, min_wealth::Float64=0.0)
    hrs_raw = readdlm(path, ',', Any; skipstart=1)
    n_pop = size(hrs_raw, 1)
    n_cols_raw = size(hrs_raw, 2)

    # Detect CSV layout by column count:
    #   5 cols: wealth, perm_income, age, own_life_ann, weight (old format)
    #   6 cols: wealth, perm_income, age, health, own_life_ann, weight (new format)
    has_health = n_cols_raw >= 6

    n_out = has_health ? 4 : 3
    population = zeros(n_pop, n_out)
    population[:, 1] = Float64.(hrs_raw[:, 1])                          # wealth
    population[:, 2] = zero_ss ? zeros(n_pop) : Float64.(hrs_raw[:, 2]) # perm_income / A
    population[:, 3] = Float64.(hrs_raw[:, 3])                          # age
    if has_health
        population[:, 4] = Float64.(hrs_raw[:, 4])                      # health (1/2/3)
    end

    if min_wealth > 0.0
        mask = population[:, 1] .>= min_wealth
        population = population[mask, :]
    end
    return population
end

end

#=============================================================================
# ORIGINAL FILE: src/parameters.jl
#=============================================================================

using Parameters
using TOML

# Model parameters for the lifecycle annuitization problem.
# All values either from config file or published calibrations with citations.

@with_kw struct ModelParams
    # Preferences
    gamma::Float64 = 3.0          # CRRA (Lockwood 2012)
    beta::Float64 = 0.97          # discount factor
    theta::Float64 = 0.0          # bequest intensity
    kappa::Float64 = 0.0          # bequest shifter (Lockwood 2018)
    consumption_decline::Float64 = 0.0  # age-varying consumption needs (Aguiar-Hurst)
    health_utility::Vector{Float64} = [1.0, 1.0, 1.0]  # state-dependent utility [G,F,P] (FLN 2013)
    psi_purchase::Float64 = 0.0       # purchase event disutility (Chalmers-Reuter 2012, Blanchett-Finke 2025); 0 = off
    psi_purchase_c_ref::Float64 = 18_000.0  # reference consumption (\$/yr) for converting dollar premium to utility units
    lambda_w::Float64 = 1.0           # source-dependent utility (FPR / Blanchett-Finke 2024-25)
                                       # 1.0 = off; 0.625 = portfolio dollars worth 62.5% of income dollars
                                       # Implementation: c_eff = c_income + lambda_w * c_portfolio

    # Demographics
    age_start::Int = 65
    age_end::Int = 110
    T::Int = age_end - age_start + 1  # 46 periods

    # Income
    r::Float64 = 0.02             # real risk-free rate
    ss_mean::Float64 = 18_000.0   # mean annual SS benefit (2014$)
    ss_quartile_shares::Vector{Float64} = [0.90, 0.75, 0.60, 0.40]

    # Annuity
    mwr::Float64 = 1.0            # money's worth ratio (1.0 = fair)
    fixed_cost::Float64 = 0.0     # fixed purchase cost ($)
    inflation_rate::Float64 = 0.0 # nominal annuity erosion
    min_purchase::Float64 = 0.0   # minimum annuity premium ($)
    deferral_start_period::Int = 1 # period when annuity payments begin (1=SPIA)
    dia_mwr::Float64 = 0.50       # DIA money's worth ratio (Wettstein et al. 2021)

    # Medical expenditures (Phase 3)
    medical_enabled::Bool = false
    medical_mu_base::Float64 = 7.037      # log mean OOP at age 65 (Fair health)
    medical_mu_growth::Float64 = 0.0652   # annual growth in log mean
    medical_sigma::Float64 = 1.4          # base log std of medical expenses
    medical_cost_shift::Vector{Float64} = [-0.5, 0.0, 0.7]  # log shift by health [G,F,P]
    medical_sigma_shift::Vector{Float64} = [-0.2, 0.0, 0.2] # sigma shift by health [G,F,P]

    # Health dynamics (Phase 3)
    stochastic_health::Bool = false
    n_health_states::Int = 1
    health_mortality_corr::Bool = false    # survival depends on health (R-S mechanism)
    hazard_mult::Vector{Float64} = [0.50, 1.0, 3.0]  # hazard multipliers [Good,Fair,Poor]; HRS: [0.57,1.0,2.70]
    # Age-varying multipliers: Matrix{Float64} with columns [Good, Fair, Poor]
    # and rows corresponding to age band midpoints in hazard_mult_age_midpoints.
    # When nothing, uses constant hazard_mult vector (backward compatible).
    hazard_mult_by_age::Union{Nothing, Matrix{Float64}} = nothing
    hazard_mult_age_midpoints::Union{Nothing, Vector{Float64}} = nothing
    survival_pessimism::Float64 = 1.0     # 1.0 = objective; 0.981 = O'Dea & Sturrock (2023) 15pp gap at 10yr
    n_quad::Int = 9                       # Gauss-Hermite quadrature nodes

    # Grids
    n_wealth::Int = 50
    n_annuity::Int = 15
    W_max::Float64 = 1_000_000.0
    W_min::Float64 = 0.0
    wealth_grid_power::Float64 = 2.0
    annuity_grid_power::Float64 = 2.0  # power mapping for A grid (use 3.0 for fine near-zero)
    n_alpha::Int = 51

    # Solver
    tol::Float64 = 1e-8
    max_iter::Int = 1000

    # Simulation
    n_histories::Int = 10_000
    seed::Int = 42

    # Consumption
    c_floor::Float64 = 3_000.0    # minimum consumption floor ($)
end

"""
Load parameters from a TOML config file, overriding defaults.
"""
function load_params(config_path::String)
    cfg = TOML.parsefile(config_path)
    kwargs = Dict{Symbol, Any}()

    # Map TOML sections to struct fields. Whenever a new ModelParams field
    # is added the corresponding entry MUST go here, otherwise TOML configs
    # silently fall back to defaults for that field (e.g. omitting
    # psi_purchase from a "behavioral" section would silently disable the
    # behavioral channel for any TOML-driven run).
    section_map = Dict(
        "preferences" => [:gamma, :beta, :theta, :kappa,
                          :consumption_decline, :health_utility],
        "behavioral" => [:psi_purchase, :psi_purchase_c_ref, :lambda_w],
        "demographics" => [:age_start, :age_end],
        "income" => [:r, :ss_mean, :ss_quartile_shares],
        "annuity" => [:mwr, :fixed_cost, :inflation_rate, :min_purchase,
                      :deferral_start_period, :dia_mwr],
        "medical" => [:medical_enabled, :medical_mu_base, :medical_mu_growth,
                      :medical_sigma, :medical_cost_shift, :medical_sigma_shift],
        "health" => [:stochastic_health, :n_health_states,
                     :health_mortality_corr, :hazard_mult,
                     :hazard_mult_by_age, :hazard_mult_age_midpoints,
                     :survival_pessimism, :n_quad],
        "grids" => [:n_wealth, :n_annuity, :W_max, :W_min, :wealth_grid_power,
                    :annuity_grid_power, :n_alpha],
        "solver" => [:tol, :max_iter],
        "simulation" => [:n_histories, :seed],
        "consumption" => [:c_floor],
    )

    for (section, fields) in section_map
        if haskey(cfg, section)
            for f in fields
                key = string(f)
                if haskey(cfg[section], key)
                    kwargs[f] = cfg[section][key]
                end
            end
        end
    end

    # Recompute T if demographics changed
    age_start = get(kwargs, :age_start, 65)
    age_end = get(kwargs, :age_end, 110)
    kwargs[:T] = age_end - age_start + 1

    # Convert hazard_mult_by_age from array-of-arrays to Matrix
    if haskey(kwargs, :hazard_mult_by_age) && kwargs[:hazard_mult_by_age] !== nothing
        rows = kwargs[:hazard_mult_by_age]
        mat = Matrix{Float64}(undef, length(rows), length(rows[1]))
        for (i, row) in enumerate(rows)
            mat[i, :] = Float64.(row)
        end
        kwargs[:hazard_mult_by_age] = mat
    end

    ModelParams(; kwargs...)
end

#=============================================================================
# ORIGINAL FILE: src/utility.jl
#=============================================================================

# CRRA utility and bequest utility functions.
# Follows Lockwood (2012) parameterization.

"""
CRRA utility: U(c) = c^(1-γ) / (1-γ) for γ ≠ 1, log(c) for γ = 1.
Returns -Inf for c <= 0.
"""
function utility(c::Float64, gamma::Float64)
    c <= 0.0 && return -Inf
    if gamma == 1.0
        return log(c)
    else
        return c^(1.0 - gamma) / (1.0 - gamma)
    end
end

"""
Bequest utility: V(b) = θ * (b + κ)^(1-γ) / (1-γ).
κ > 0 makes bequests a luxury good (Lockwood 2018).
Returns 0 when θ = 0 (no bequest motive).
"""
function bequest_utility(b::Float64, gamma::Float64, theta::Float64, kappa::Float64)
    theta == 0.0 && return 0.0
    # Floor at $1 to prevent -Inf when kappa=0 and b=0 (warm-glow specification).
    # With kappa>0 (luxury good), (b+kappa) is bounded away from zero and this
    # floor never binds. With kappa=0, the floor avoids numerical instability
    # at boundary states while preserving the economic incentive to save.
    arg = max(b + kappa, 1.0)
    if gamma == 1.0
        return theta * log(arg)
    else
        return theta * arg^(1.0 - gamma) / (1.0 - gamma)
    end
end

"""
Marginal utility: U'(c) = c^(-γ).
"""
function marginal_utility(c::Float64, gamma::Float64)
    c <= 0.0 && return Inf
    return c^(-gamma)
end

"""
Age-varying consumption weight: (1 - delta_c)^(t-1).
At t=1 (age 65), returns 1.0. Declines geometrically with age.
Returns 1.0 when delta_c == 0.0 (channel off).
"""
function consumption_weight(t::Int, delta_c::Float64)
    delta_c == 0.0 && return 1.0
    return (1.0 - delta_c)^(t - 1)
end

"""
Health-state-dependent utility weight.
ih: health state index (1=Good, 2=Fair, 3=Poor).
"""
function health_utility_weight(ih::Int, p::ModelParams)
    return p.health_utility[ih]
end

"""
Flow utility combining CRRA with age-varying needs and health-state weights.
With defaults (consumption_decline=0, health_utility=[1,1,1]), reduces to utility(c, gamma).
"""
function flow_utility(c::Float64, gamma::Float64, t::Int, ih::Int, p::ModelParams)
    w_age = consumption_weight(t, p.consumption_decline)
    w_health = health_utility_weight(ih, p)
    return w_age * w_health * utility(c, gamma)
end

"""
Source-dependent flow utility (Tharp FPR companion paper; Blanchett-Finke 2024,
2025; Shefrin-Thaler 1988 mental accounting).

Households experience consumption financed by income flows (Social Security,
annuity payouts) at full utility weight, and consumption financed by portfolio
drawdowns at a discount lambda_w in [0, 1]. The discount is applied at the
DOLLAR level (multiplicative on c) rather than at the utility level — this
avoids the sign-flip that would occur for gamma>1 if lambda_w multiplied a
negative CRRA value directly.

  c_income    = min(c, inc)            # dollars financed by income flow
  c_portfolio = max(0, c - inc)        # dollars financed by portfolio drawdown
  c_eff       = c_income + lambda_w * c_portfolio
  u           = w_age * w_health * U(c_eff, gamma)

When lambda_w = 1 (default), c_eff = c and this reduces to flow_utility above.
When lambda_w < 1, drawing from portfolio yields strictly less effective
consumption per dollar, which (i) discourages portfolio drawdown and
(ii) makes converting portfolio wealth into income (via annuitization) more
attractive on the consumption side.

Calibration: lambda_w = 0.625 from Blanchett-Finke (2024, 2025) — retirees
spend ~80% of guaranteed income but only ~50% of portfolio wealth, implying a
50/80 = 0.625 ratio in spending propensity. Same calibration as the FPR
companion paper.
"""
function flow_utility_sdu(c::Float64, inc::Float64, gamma::Float64, t::Int,
                          ih::Int, p::ModelParams)
    if p.lambda_w >= 1.0
        # SDU off: identical to flow_utility
        c_eff = c
    else
        c_income = min(c, inc)
        c_portfolio = max(0.0, c - inc)
        c_eff = c_income + p.lambda_w * c_portfolio
    end
    w_age = consumption_weight(t, p.consumption_decline)
    w_health = health_utility_weight(ih, p)
    return w_age * w_health * utility(c_eff, gamma)
end

"""
Narrow-framing purchase penalty NPV (Barberis-Huang 2009; Tversky-Kahneman
1992 loss aversion; Brown et al. 2008 framing evidence).

The household mentally brackets the annuity decision as a separate "investment"
with its own gain/loss tally — the cumulative annuity payout net of the premium
paid. While the household is "underwater" (cumulative payouts < premium), the
narrow-framing loss is salient and generates a per-period disutility flow
proportional to the unrecouped premium. Once cumulative payouts cross the
premium ("breakeven"), the loss tally turns positive and the penalty vanishes.

This captures the user-described two-part felt cost of annuitization:
(i) immediate "loss" of writing the check at age 65, and (ii) ongoing
discomfort of reduced portfolio plus reduced optionality until breakeven.

Per-period flow at period t (t=1 is age 65, before any payouts received):

    flow_t = psi_purchase * u'(c_ref) * max(0, premium - A * (t-1))

where A is the annual annuity income, payout_rate = A / premium, breakeven
period is t* = ceil(1/payout_rate) ≈ 14-15 for typical SPIA pricing, and
u'(c_ref) = c_ref^(-gamma) is the marginal utility at the reference
consumption (SS mean = 18,000 dollars/yr).

The total penalty entering the age-65 alpha search is the survival- and
discount-weighted NPV of the stream:

    penalty_NPV = sum_{t=1..t*} beta^(t-1) * S(t) * flow_t

where S(1) = 1 (alive at purchase) and S(t) = prod_{s=1..t-1} surv[s].

Reduces to zero when psi_purchase = 0 (channel off) or premium = 0
(no purchase). Returns the NPV in lifetime-utility units, ready to be
subtracted from the value-function at the alpha-search step.

Note on functional form: this replaces an earlier one-time linear-in-premium
penalty whose magnitude was insensitive to whether the household actually
recouped the premium. Multiple peer reviewers flagged the earlier form as
ad hoc (no axiomatic basis). The narrow-framing stream above is derivable
from prospect-theoretic narrow framing (Barberis-Huang 2009) plus
Tversky-Kahneman loss aversion applied to the annuity's running gain/loss
tally.
"""
function purchase_penalty(premium::Float64,
                          payout_rate::Float64,
                          gamma::Float64,
                          psi_purchase::Float64,
                          c_ref::Float64,
                          beta::Float64,
                          surv::Vector{Float64};
                          purchase_period::Int=1)
    # purchase_period: index into `surv` for the period of purchase. Defaults
    # to 1 (age-65 / period-1 purchase, which is the only call site in the
    # current pipeline). For purchases at later ages, pass purchase_period =
    # period-of-purchase so the cumulative survival starts conditional on
    # being alive at the purchase moment, not at age 65.
    psi_purchase <= 0.0 && return 0.0
    premium <= 0.0 && return 0.0
    payout_rate <= 0.0 && return 0.0

    A = premium * payout_rate
    mu_ref = c_ref^(-gamma)

    # Breakeven period: smallest t such that A * (t-1) >= premium → t-1 >= 1/payout_rate.
    # After breakeven, max(0, premium - A*(t-1)) = 0 and the stream contributes nothing.
    breakeven_t = ceil(Int, 1.0 / payout_rate) + 1  # +1 for the period at-which underwater hits 0

    # Slice survival schedule from the purchase period forward. surv[t] is the
    # one-period survival probability at age 65+t-1, so for a purchase at
    # period p_t we want surv[p_t], surv[p_t+1], ... as the conditional one-
    # period probabilities going forward.
    surv_offset = purchase_period - 1
    surv_remaining = surv_offset == 0 ? surv : @view surv[purchase_period:end]

    npv = 0.0
    cum_surv = 1.0  # alive at purchase by construction
    horizon = min(breakeven_t, length(surv_remaining) + 1)
    for t in 1:horizon
        underwater = max(0.0, premium - A * (t - 1))
        underwater <= 0.0 && break
        flow = psi_purchase * mu_ref * underwater
        discount = beta^(t - 1)
        npv += cum_surv * discount * flow
        # Update cumulative survival for next period (conditional on alive at
        # the purchase moment).
        if t <= length(surv_remaining)
            cum_surv *= surv_remaining[t]
        end
    end
    return npv
end

#=============================================================================
# ORIGINAL FILE: src/income.jl
#=============================================================================

# Social Security and pension income profiles.
# SS benefits are exogenous, real (inflation-indexed), and non-commutable.
# Calibrated to match distribution by wealth quartile (Dushi and Webb 2004;
# Poterba, Venti, and Wise 2011; Lockwood 2012).

"""
Annual Social Security benefit by wealth quartile (1-indexed).
Quartile 1 = lowest wealth, quartile 4 = highest.

Bottom quartile gets the highest SS replacement rate (~90% of wealth annuitized).
Top quartile has lowest replacement rate (~40%).
Absolute SS benefit rises with wealth quartile but at a decreasing rate,
reflecting the progressive benefit formula.

Benefits in 2014 dollars.
"""
function ss_benefit(quartile::Int, p::ModelParams)
    # Approximate SSA benefit schedule by quartile.
    # Mean benefit ~$18K; bottom quartile ~$14K, top quartile ~$25K.
    # Progressive formula: replacement rate falls with earnings.
    quartile_benefits = [14_000.0, 17_000.0, 20_000.0, 25_000.0]
    return quartile_benefits[quartile]
end

"""
SS benefit as a function of initial wealth W_0, mapping wealth to quartile.
Uses quartile breakpoints from HRS/SCF data (approximate, 2014 dollars).
"""
function ss_benefit_by_wealth(W_0::Float64, p::ModelParams)
    # Wealth quartile breakpoints for single retirees 65-69 (HRS, approximate)
    if W_0 < 30_000.0
        return ss_benefit(1, p)
    elseif W_0 < 120_000.0
        return ss_benefit(2, p)
    elseif W_0 < 350_000.0
        return ss_benefit(3, p)
    else
        return ss_benefit(4, p)
    end
end

"""
For the Yaari benchmark: zero SS income.
"""
function ss_benefit_zero(t::Int, p::ModelParams)
    return 0.0
end

#=============================================================================
# ORIGINAL FILE: src/lockwood_lifetable.jl
#=============================================================================

# SSA administrative life table from Lockwood (2012) replication code.
# These are exact cumulative death probabilities for ages 66–111,
# from the perspective of a 65-year-old.
# Source: BAP_wtp.m, lines 51–96.

"""
SSA admin cumulative death probabilities from Lockwood (2012).
cum_death_probs[i] = Pr(dead before age 65+i) for i=1:46.
cum_death_probs[1] = 0.0 (alive at 65), cum_death_probs[46] = ~1.0 (dead by 111).
Max age = 110 (46 periods from age 65).
"""
const LOCKWOOD_CUM_DEATH_PROBS = [
    0.0,
    0.018740306,
    0.038815572,
    0.060225799,
    0.08304727,
    0.107305414,
    0.13310194,
    0.160538561,
    0.189602563,
    0.220281232,
    0.252561853,
    0.286520711,
    0.322170519,
    0.359320569,
    0.397703868,
    0.437129707,
    0.477483663,
    0.518651308,
    0.560441936,
    0.602563125,
    0.644658886,
    0.68624609,
    0.726765327,
    0.765669896,
    0.802387673,
    0.836397386,
    0.867254049,
    0.894652529,
    0.918376688,
    0.938401098,
    0.954802044,
    0.967795662,
    0.977712513,
    0.985023012,
    0.990223002,
    0.993782897,
    0.996160399,
    0.997698782,
    0.998665039,
    0.999262593,
    0.999605869,
    0.999796577,
    0.999898289,
    0.999949144,
    0.999974572,
    0.999987286,
]

"""
Build conditional survival probabilities from Lockwood's SSA life table.
Returns a vector of length T where surv[t] = Pr(survive from age 64+t to 65+t | alive at 64+t).
surv[T] = 0.0 (certain death at max age).

If the model's age range differs from Lockwood's (65–110), this extracts
the appropriate subset or pads with zeros.
"""
function build_lockwood_survival(p::ModelParams)
    T = p.T
    cdp = LOCKWOOD_CUM_DEATH_PROBS
    n_lockwood = length(cdp)  # 46 periods (ages 65–110)

    surv = Vector{Float64}(undef, T)
    for t in 1:T
        age = p.age_start + t - 1
        lockwood_idx = age - 65 + 1  # index into cdp (1-based, age 65 = index 1)

        if age >= p.age_end
            surv[t] = 0.0
        elseif lockwood_idx < 1 || lockwood_idx >= n_lockwood
            # Outside Lockwood's table range — use Gompertz fallback
            surv[t] = survival_prob_deterministic(age)
        else
            # Conditional survival: Pr(alive at age+1) / Pr(alive at age)
            surv[t] = (1.0 - cdp[lockwood_idx + 1]) / (1.0 - cdp[lockwood_idx])
        end
    end
    return surv
end

#=============================================================================
# ORIGINAL FILE: src/grids.jl
#=============================================================================

# Grid construction for the lifecycle model state space.
# Wealth grid uses power-function mapping for nonuniform spacing
# (denser at low wealth where value function has more curvature).

"""
Build nonuniform wealth grid: W_i = W_min + (W_max - W_min) * (i/N)^p
where p > 1 concentrates points near W_min.
"""
function build_wealth_grid(p::ModelParams)
    n = p.n_wealth
    raw = range(0.0, 1.0, length=n)
    # Power mapping: higher p => denser at low wealth
    grid = p.W_min .+ (p.W_max - p.W_min) .* (raw .^ p.wealth_grid_power)
    return collect(grid)
end

"""
Build nonuniform annuity income grid from 0 to maximum feasible annual payout.
Uses same power-function mapping as wealth grid to concentrate points
at low annuity income levels (where low-wealth agents' annuity values fall).

The grid upper bound is W_max × payout_rate, sized to the new annuity income
from a full alpha=1 purchase at maximum wealth. For agents with substantial
pre-existing SS income (top quartile, around 21K dollars), A_total = SS +
alpha * W * payout_rate can slightly exceed this bound at α=1; in that case
the value function is evaluated at the grid boundary and a small
interpolation imprecision results. The audit in
test/test_grid_clamp_audit.jl quantifies the affected fraction (~1% of the
HRS eligible sample, all in the top wealth quartile) and the maximum
overshoot (~9.5% above the bound).
"""
function build_annuity_grid(p::ModelParams, payout_rate::Float64)
    A_max = p.W_max * payout_rate
    n = p.n_annuity
    raw = range(0.0, 1.0, length=n)
    grid = A_max .* (raw .^ p.annuity_grid_power)
    return collect(grid)
end

"""
Build grid of annuitization fractions α ∈ [0, 1].
"""
function build_alpha_grid(p::ModelParams)
    return collect(range(0.0, 1.0, length=p.n_alpha))
end

struct Grids
    W::Vector{Float64}     # wealth grid
    A::Vector{Float64}     # annuity income grid
    alpha::Vector{Float64} # annuitization fraction grid
end

function build_grids(p::ModelParams, payout_rate::Float64)
    Grids(
        build_wealth_grid(p),
        build_annuity_grid(p, payout_rate),
        build_alpha_grid(p),
    )
end

# ---------------------------------------------------------------------------
# Grid-bound auditing
# ---------------------------------------------------------------------------
# Many evaluation routines call `clamp(A_total, g.A[1], g.A[end])` or
# `clamp(W, g.W[1], g.W[end])` to keep a state value inside the discretized
# grid. If the clamp binds materially often, the structural results may
# silently depend on grid-boundary extrapolation rather than on the
# interior solution.
#
# The audit counters below tally how often each clamp bound across a run.
# A run is "clean" if both counters report 0; otherwise the run prints a
# summary that the manuscript / referee can inspect.
#
# Usage:
#   reset_clamp_audit!()      # call once at the start of a run
#   x_c = clamp_audit(x, lo, hi, :wealth)   # instead of clamp(x, lo, hi)
#   report_clamp_audit()      # call once at the end of a run

const _CLAMP_AUDIT = Dict{Symbol, Tuple{Int, Int, Float64}}()  # :tag => (n_total, n_bound, max_overshoot)

function reset_clamp_audit!()
    empty!(_CLAMP_AUDIT)
    return nothing
end

@inline function clamp_audit(x::Real, lo::Real, hi::Real, tag::Symbol=:default)
    n_total, n_bound, max_over = get(_CLAMP_AUDIT, tag, (0, 0, 0.0))
    n_total += 1
    if x < lo
        n_bound += 1
        max_over = max(max_over, lo - x)
    elseif x > hi
        n_bound += 1
        max_over = max(max_over, x - hi)
    end
    _CLAMP_AUDIT[tag] = (n_total, n_bound, max_over)
    return clamp(x, lo, hi)
end

function report_clamp_audit(; threshold_pct::Float64=1.0, throw_on_breach::Bool=false)
    isempty(_CLAMP_AUDIT) && return nothing
    println("\n=== Grid-clamp audit ===")
    breach = false
    for (tag, (n_total, n_bound, max_over)) in sort(collect(_CLAMP_AUDIT), by=x->x[1])
        pct = 100.0 * n_bound / max(n_total, 1)
        marker = pct >= threshold_pct ? " ** BREACH **" : ""
        @printf("  %-15s: %d/%d clamped (%.3f%%), max overshoot = %.4g%s\n",
                tag, n_bound, n_total, pct, max_over, marker)
        if pct >= threshold_pct
            breach = true
        end
    end
    println("=========================")
    if breach && throw_on_breach
        error("clamp audit breached threshold of $threshold_pct% for at least one tag")
    end
    return nothing
end

#=============================================================================
# ORIGINAL FILE: src/annuity.jl
#=============================================================================

# Annuity pricing and payout rate calculations.
# Follows Mitchell et al. (1999) for MWR methodology.
# A SPIA converts a lump sum into a lifelong income stream;
# the payout rate depends on mortality assumptions and the discount rate.

"""
Compute actuarially fair annual payout per dollar of premium for a SPIA
purchased at `purchase_age`, using the given survival probabilities and
discount rate. Adjusted by the money's worth ratio.

Fair annuity value of \$1 = sum_{t=1}^{T} s(t) / (1+r)^t
Payout rate = MWR / fair_annuity_value

If MWR = 1.0, the annuity is actuarially fair.
If MWR = 0.82, the expected present value of payouts is 82 cents per dollar.
"""
function compute_payout_rate(p::ModelParams, surv::Vector{Float64})
    # Present value of \$1/year life annuity, including payment at purchase age.
    # PV = sum_{t=0}^{T-1} S(t) / (1+r_discount)^t
    # where S(0) = 1 (alive at purchase), S(t) = prod_{s=1}^{t} surv[s].
    #
    # Discount rate depends on product type:
    #   - Real annuity (inflation_rate=0): discount at r (real rate)
    #   - Nominal annuity (inflation_rate>0): discount at r_nom (exact Fisher)
    #     The insurer invests in nominal bonds yielding r_nom and pays nominal
    #     dollars; the higher discount rate produces a higher initial payout
    #     whose real value then erodes via annuity_income_real().
    r_discount = p.inflation_rate > 0 ? (1 + p.r) * (1 + p.inflation_rate) - 1 : p.r

    pv = 1.0  # t=0: alive at purchase, no discounting
    for t in 1:(p.T - 1)
        cum_surv = 1.0
        for s in 1:t
            cum_surv *= surv[s]
        end
        discount = 1.0 / (1.0 + r_discount)^t
        pv += cum_surv * discount
    end

    # Payout rate: annual income per dollar of premium
    # With fair pricing (MWR=1): premium = pv * payout => payout = 1/pv
    # With loads (MWR<1): consumer gets less => payout = MWR / pv
    payout_rate = p.mwr / pv
    return payout_rate
end

"""
Annuity income given initial wealth W_0 and annuitization fraction alpha.
A = alpha * W_0 * payout_rate
"""
function annuity_income(alpha::Float64, W_0::Float64, payout_rate::Float64)
    return alpha * W_0 * payout_rate
end

"""
Check whether an annuity purchase meets the minimum premium requirement.
Returns true if alpha is zero (no purchase) or if the premium exceeds min_purchase.
"""
function is_feasible_purchase(alpha::Float64, W_0::Float64, p::ModelParams)
    alpha == 0.0 && return true
    premium = alpha * W_0
    return premium >= p.min_purchase
end

"""
Inflation-adjusted annuity income at period t, with deferral support.
Returns 0 before the deferral start period (for DIA products).
Inflation erodes from purchase time (period 1), not payment start.
"""
function annuity_income_real(A_nominal::Float64, t::Int, p::ModelParams)
    if t < p.deferral_start_period
        return 0.0
    end
    return A_nominal * (1.0 / (1.0 + p.inflation_rate))^(t - 1)
end

"""
Compute payout rate for a deferred income annuity (DIA) purchased at age_start
with payments beginning at deferral_age. Uses dia_mwr for the money's worth ratio.
"""
function compute_payout_rate_deferred(p::ModelParams, surv::Vector{Float64}, deferral_age::Int)
    d_period = deferral_age - p.age_start  # 0-indexed period when first payment occurs
    r_discount = p.inflation_rate > 0 ? (1 + p.r) * (1 + p.inflation_rate) - 1 : p.r
    pv = 0.0
    for t in 0:(p.T - 1)
        t < d_period && continue
        cum_surv = 1.0
        for s in 1:t
            cum_surv *= surv[s]
        end
        discount = 1.0 / (1.0 + r_discount)^t
        pv += cum_surv * discount
    end
    pv < 1e-10 && return 0.0
    return p.dia_mwr / pv
end

"""
Compute payout rate for a period-certain life annuity.
Payments are guaranteed for the first `guarantee_years` regardless of
survival, then life-contingent thereafter. Partially offsets the bequest
penalty since the guaranteed period provides a quasi-bequest.
"""
function compute_payout_rate_period_certain(p::ModelParams, surv::Vector{Float64};
                                            guarantee_years::Int=10)
    r_discount = p.inflation_rate > 0 ? (1 + p.r) * (1 + p.inflation_rate) - 1 : p.r
    pv = 0.0
    for t in 0:(p.T - 1)
        if t < guarantee_years
            cum_surv = 1.0  # certain payment
        else
            cum_surv = 1.0
            for s in 1:t
                cum_surv *= surv[s]
            end
        end
        discount = 1.0 / (1.0 + r_discount)^t
        pv += cum_surv * discount
    end
    return p.mwr / pv
end

"""
Remaining liquid wealth after annuity purchase.
W_remaining = (1 - alpha) * W_0 - fixed_cost * (alpha > 0)
"""
function post_purchase_wealth(alpha::Float64, W_0::Float64, fixed_cost::Float64)
    W = (1.0 - alpha) * W_0
    if alpha > 0.0
        W -= fixed_cost
    end
    return W  # callers check W < 0 to reject infeasible purchases
end
