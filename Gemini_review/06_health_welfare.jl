# =============================================================================
# 06_health_welfare.jl — Health/mortality dynamics and welfare metrics.
#
# This file consolidates:
#   src/health.jl     3-state health Markov, hazard multipliers, medical-cost process,
#                     Medicaid floor, age-band hazard ratios from RAND HRS
#   src/welfare.jl    Consumption-equivalent variation (CEV) computation
#   src/wtp.jl        Willingness-to-pay metrics, population WTP, force-decomposition WTP
# =============================================================================

#=============================================================================
# ORIGINAL FILE: src/health.jl
#=============================================================================

# Health dynamics and mortality.
# Phase 1: deterministic survival with a single health state.
# Phase 3: stochastic health with 3-state Markov process,
# health-dependent mortality (Reichling-Smetters mechanism),
# and lognormal medical expenditure shocks.

# ===================================================================
# Phase 1: Deterministic survival (no health states)
# ===================================================================

"""
Deterministic survival probability by age.
Uses approximate US population life table (SSA 2020 period table, male).
Returns probability of surviving from age t to t+1.
"""
function survival_prob_deterministic(age::Int)
    # Gompertz hazard: μ(t) = (1/b) exp((t - M) / b)
    # One-year survival: s(t) = exp(-∫_t^{t+1} μ(x) dx)
    #                         = exp(- exp((t-M)/b) * (exp(1/b) - 1))
    # M ≈ 86, b ≈ 9.5 calibrated to SSA 2020 male period life table.
    # Produces approximately: s(65)≈0.985, s(75)≈0.968, s(85)≈0.905, s(95)≈0.68
    M = 86.0
    b = 9.5
    cumhaz = exp((age - M) / b) * (exp(1.0 / b) - 1.0)
    s = exp(-cumhaz)
    return clamp(s, 0.0, 1.0)
end

"""
Build vector of survival probabilities for ages age_start to age_end-1.
Index i corresponds to age = age_start + i - 1.
"""
function build_survival_probs(p::ModelParams)
    T = p.T
    surv = Vector{Float64}(undef, T)
    for i in 1:T
        age = p.age_start + i - 1
        if age >= p.age_end
            surv[i] = 0.0  # certain death at age_end
        else
            surv[i] = survival_prob_deterministic(age)
        end
    end
    return surv
end

"""
Cumulative survival from age_start to age t (for annuity pricing).
"""
function cumulative_survival(age_start::Int, age_target::Int, surv::Vector{Float64})
    age_target <= age_start && return 1.0
    cum = 1.0
    for age in age_start:(age_target - 1)
        idx = age - age_start + 1
        cum *= surv[idx]
    end
    return cum
end


# ===================================================================
# Phase 3: Gauss-Hermite Quadrature
# ===================================================================

# Hardcoded GH nodes and weights for ∫ f(x) exp(-x^2) dx.
# To integrate over standard normal: E[f(Z)] = (1/√π) Σ w_i f(√2 x_i)
const GH_NODES_3 = [-1.2247448713916, 0.0, 1.2247448713916]
const GH_WEIGHTS_3 = [0.2954089751509, 1.1816359006037, 0.2954089751509]

const GH_NODES_5 = [-2.0201828704561, -0.9585724646139, 0.0, 0.9585724646139, 2.0201828704561]
const GH_WEIGHTS_5 = [0.0199532420590, 0.3936193231522, 0.9453087204829, 0.3936193231522, 0.0199532420590]

const GH_NODES_7 = [-2.6519613568352, -1.6735516287675, -0.8162878828589, 0.0,
                     0.8162878828589, 1.6735516287675, 2.6519613568352]
const GH_WEIGHTS_7 = [0.0009717812451, 0.0545155828191, 0.4256072526101, 0.8102646175568,
                      0.4256072526101, 0.0545155828191, 0.0009717812451]

# 9-node GH: nodes and weights for ∫ f(x) exp(-x^2) dx
const GH_NODES_9 = [-3.1909932017815, -2.2665805845318, -1.4685532892167, -0.7235510187528, 0.0,
                     0.7235510187528, 1.4685532892167, 2.2665805845318, 3.1909932017815]
const GH_WEIGHTS_9 = [3.960697726326e-5, 0.0049436242755370, 0.0884745273943772, 0.4326515590025536,
                      0.7202352156060539, 0.4326515590025536, 0.0884745273943772, 0.0049436242755370,
                      3.960697726326e-5]

# 11-node GH: nodes and weights for ∫ f(x) exp(-x^2) dx
const GH_NODES_11 = [-3.6684708465596, -2.7832900997817, -2.0259480158258, -1.3265570844949,
                      -0.6568095668821, 0.0, 0.6568095668821, 1.3265570844949,
                      2.0259480158258, 2.7832900997817, 3.6684708465596]
const GH_WEIGHTS_11 = [1.439560393714e-6, 3.468194663233e-4, 0.0119113954449115, 0.1172278751677091,
                       0.4293597523561230, 0.6547592869145944, 0.4293597523561230, 0.1172278751677091,
                       0.0119113954449115, 3.468194663233e-4, 1.439560393714e-6]

# 13-node and 15-node tables, used only for convergence diagnostics beyond
# the 11-node production rule. Computed via FastGaussQuadrature.gausshermite.
const GH_NODES_13 = [-4.1013375961786, -3.2466089783724, -2.5197356856782, -1.8531076516015,
                      -1.2200550365908, -0.6057638791711, 0.0, 0.6057638791711,
                      1.2200550365908, 1.8531076516015, 2.5197356856782, 3.2466089783724,
                      4.1013375961786]
const GH_WEIGHTS_13 = [4.8257319e-8, 2.0430360403e-5, 0.001207459992719, 0.02086277529617,
                       0.140323320687024, 0.42161629689854, 0.604393187921165,
                       0.42161629689854, 0.140323320687024, 0.02086277529617,
                       0.001207459992719, 2.0430360403e-5, 4.8257319e-8]

const GH_NODES_15 = [-4.4999907073094, -3.6699503734045, -2.9671669279056, -2.3257324861739,
                      -1.7199925751865, -1.1361155852109, -0.5650695832556, 0.0,
                      0.5650695832556, 1.1361155852109, 1.7199925751865, 2.3257324861739,
                      2.9671669279056, 3.6699503734045, 4.4999907073094]
const GH_WEIGHTS_15 = [1.522476e-9, 1.059115548e-6, 0.000100004441233, 0.002778068842913,
                       0.030780033872546, 0.158488915795936, 0.412028687498898,
                       0.564100308726418, 0.412028687498898, 0.158488915795936,
                       0.030780033872546, 0.002778068842913, 0.000100004441233,
                       1.059115548e-6, 1.522476e-9]

"""
Return (nodes, weights) for Gauss-Hermite quadrature adapted to standard
normal integration: E[f(Z)] ≈ Σ weights[i] × f(nodes[i]) where Z ~ N(0,1).

Supports n ∈ {3, 5, 7, 9, 11, 13, 15}.
"""
function gauss_hermite_normal(n::Int)
    if n == 3
        raw_x, raw_w = GH_NODES_3, GH_WEIGHTS_3
    elseif n == 5
        raw_x, raw_w = GH_NODES_5, GH_WEIGHTS_5
    elseif n == 7
        raw_x, raw_w = GH_NODES_7, GH_WEIGHTS_7
    elseif n == 9
        raw_x, raw_w = GH_NODES_9, GH_WEIGHTS_9
    elseif n == 11
        raw_x, raw_w = GH_NODES_11, GH_WEIGHTS_11
    elseif n == 13
        raw_x, raw_w = GH_NODES_13, GH_WEIGHTS_13
    elseif n == 15
        raw_x, raw_w = GH_NODES_15, GH_WEIGHTS_15
    else
        error("Gauss-Hermite quadrature only implemented for n ∈ {3, 5, 7, 9, 11, 13, 15}, got n=$n")
    end
    # Transform: z_i = √2 × x_i (standard normal nodes)
    # Weights: w_i / √π (normalized for ∫ f(z) φ(z) dz)
    nodes = sqrt(2.0) .* raw_x
    weights = raw_w ./ sqrt(π)
    return (nodes, weights)
end


# ===================================================================
# Phase 3: Health Transition Matrices
# ===================================================================

# 3-state Markov health: 1=Good, 2=Fair, 3=Poor.
# Annual transition matrices by age band, estimated from RAND HRS panel data.
# Waves 5-12 (2000-2014), 7 consecutive-wave pairs, N=66,226 transitions.
# 2-year rates converted to annual via matrix square root (eigendecomposition).
# See calibration/estimate_health_transitions.jl for estimation code.
const HEALTH_TRANS_BANDS = Dict{String, Matrix{Float64}}(
    "65-69" => [0.835104 0.143644 0.021252; 0.146943 0.721875 0.131182; 0.025948 0.131965 0.842087],
    "70-74" => [0.817002 0.155458 0.027540; 0.149467 0.701249 0.149283; 0.023415 0.123746 0.852839],
    "75-79" => [0.783266 0.181404 0.035330; 0.140268 0.689135 0.170597; 0.025688 0.132405 0.841907],
    "80-84" => [0.750361 0.193290 0.056349; 0.139786 0.670101 0.190114; 0.032341 0.127677 0.839983],
    "85-89" => [0.723996 0.201431 0.074573; 0.149710 0.623234 0.227055; 0.036294 0.133314 0.830392],
    "90+"   => [0.671720 0.212755 0.115525; 0.178696 0.580609 0.240695; 0.039664 0.172591 0.787745],
)

# Ordered list of band labels and their lower age bounds
const HEALTH_BAND_ORDER = ["65-69", "70-74", "75-79", "80-84", "85-89", "90+"]
const HEALTH_BAND_LOWER = [65, 70, 75, 80, 85, 90]

# Previous two-anchor interpolation (superseded by age-band estimates):
# const HEALTH_TRANS_65 = [0.88 0.10 0.02; 0.10 0.75 0.15; 0.02 0.13 0.85]
# const HEALTH_TRANS_100 = [0.55 0.30 0.15; 0.03 0.50 0.47; 0.00 0.07 0.93]
# function build_health_transition(age::Int)
#     if age <= 65; return copy(HEALTH_TRANS_65)
#     elseif age >= 100; return copy(HEALTH_TRANS_100)
#     else
#         frac = (age - 65) / (100 - 65)
#         trans = (1.0 - frac) .* HEALTH_TRANS_65 .+ frac .* HEALTH_TRANS_100
#         for i in 1:3; trans[i, :] ./= sum(trans[i, :]); end
#         return trans
#     end
# end

"""
Return the age-band label for a given age.
Ages below 65 map to "65-69"; ages 90+ map to "90+".
"""
function _health_band_label(age::Int)
    age >= 90 && return "90+"
    age >= 85 && return "85-89"
    age >= 80 && return "80-84"
    age >= 75 && return "75-79"
    age >= 70 && return "70-74"
    return "65-69"
end

"""
Build the 3x3 health transition matrix for a given age.
Step function: returns the matrix for the age band containing `age`.
Ages below 65 use the 65-69 band; ages 90+ use the 90+ band.

Rows are current health state, columns are next-period health state.
Each row sums to 1.0. Health states: 1=Good, 2=Fair, 3=Poor.
"""
function build_health_transition(age::Int)
    band = _health_band_label(age)
    trans = copy(HEALTH_TRANS_BANDS[band])
    # Row-normalize to ensure exact stochasticity (guards against rounding
    # in the hardcoded 6-decimal-place entries)
    for i in 1:3
        trans[i, :] ./= sum(trans[i, :])
    end
    return trans
end

"""
Precompute health transition matrices for all ages in the model.
Returns a vector of 3x3 matrices, indexed by time period (1-indexed).
"""
function build_all_health_transitions(p::ModelParams)
    T = p.T
    transitions = Vector{Matrix{Float64}}(undef, T)
    for t in 1:T
        age = p.age_start + t - 1
        transitions[t] = build_health_transition(age)
    end
    return transitions
end


# ===================================================================
# Phase 3: Health-Dependent Survival
# ===================================================================

"""
Compute health-adjusted survival probability.

Uses hazard rate scaling: s(t, H) = s_base(t)^mult(H)
where mult(H) is the hazard multiplier for health state H.

When health_mortality_corr is false, returns the base survival rate
(no health-mortality correlation).

When p.hazard_mult_by_age is set, linearly interpolates the multiplier
from the age-band data (HRS empirical estimates). Otherwise uses
constant p.hazard_mult.
"""
function health_adjusted_survival(base_surv::Float64, health_state::Int,
                                   age::Int, p::ModelParams)
    if !p.health_mortality_corr
        return base_surv
    end
    # Hazard scaling: s_base = exp(-μ), s_adj = exp(-mult × μ) = s_base^mult
    mult = _get_hazard_mult(health_state, age, p)
    return clamp(base_surv^mult, 0.0, 1.0)
end

# Backward-compatible 3-argument form (uses constant multipliers)
function health_adjusted_survival(base_surv::Float64, health_state::Int, p::ModelParams)
    return health_adjusted_survival(base_surv, health_state, 0, p)
end

"""
Look up hazard multiplier for a given health state and age.
With age-varying multipliers, linearly interpolates between age-band
midpoints; flat extrapolation beyond the data range.
"""
function _get_hazard_mult(health_state::Int, age::Int, p::ModelParams)
    if p.hazard_mult_by_age === nothing || age <= 0
        return p.hazard_mult[health_state]
    end

    midpoints = p.hazard_mult_age_midpoints
    n = length(midpoints)
    age_f = Float64(age)

    # Flat extrapolation below/above data range
    if age_f <= midpoints[1]
        return p.hazard_mult_by_age[1, health_state]
    elseif age_f >= midpoints[end]
        return p.hazard_mult_by_age[end, health_state]
    end

    # Linear interpolation between adjacent midpoints
    for i in 1:(n-1)
        if age_f <= midpoints[i+1]
            frac = (age_f - midpoints[i]) / (midpoints[i+1] - midpoints[i])
            lo = p.hazard_mult_by_age[i, health_state]
            hi = p.hazard_mult_by_age[i+1, health_state]
            return lo + frac * (hi - lo)
        end
    end
    return p.hazard_mult_by_age[end, health_state]
end

"""
Build a matrix of health-adjusted survival probabilities.
Returns surv_health[t, h] for t=1..T, h=1..3.

When p.survival_pessimism < 1.0, scales each one-year subjective survival
probability downward: s_subj(t) = psi * s_obj(t). This only affects the
Bellman equation (the agent's decisions), not annuity pricing (the insurer
uses objective survival from base_surv directly).

Calibration: O'Dea and Sturrock (2023, AER) find subjective P(75|65) is
~15pp below actuarial (~71% vs 86%). The per-year factor that matches this
10-year cumulative gap is psi = (0.71/0.86)^(1/10) = 0.981.
"""
function build_health_survival(base_surv::Vector{Float64}, p::ModelParams;
                                psi_override::Union{Nothing,Float64}=nothing)
    T = p.T
    nH = 3
    surv_health = Matrix{Float64}(undef, T, nH)
    psi = psi_override === nothing ? p.survival_pessimism : psi_override
    for t in 1:T
        age = p.age_start + t - 1
        for h in 1:nH
            s = health_adjusted_survival(base_surv[t], h, age, p)
            if psi < 1.0
                s = clamp(s * psi, 0.0, 1.0)
            end
            surv_health[t, h] = s
        end
    end
    return surv_health
end


# ===================================================================
# Phase 3: Medical Expenditure Process
# ===================================================================

"""
Return (mu, sigma) for the lognormal medical expenditure distribution
at a given age and health state.

ln(m) = mu + sigma × epsilon, epsilon ~ N(0,1)
E[m] = exp(mu + sigma^2/2)

Calibrated to Jones et al. (2018):
  - Mean OOP at age 70: ~4200
  - Mean OOP at age 100: ~29700
  - 95th percentile at age 100: ~111200

Health states: 1=Good, 2=Fair, 3=Poor.
"""
function medical_expense_params(age::Int, health_state::Int, p::ModelParams)
    mu = p.medical_mu_base + p.medical_mu_growth * (age - 65)
    mu += p.medical_cost_shift[health_state]
    sigma = p.medical_sigma + p.medical_sigma_shift[health_state]
    return (mu, sigma)
end

"""
Compute the mean medical expense at a given age and health state.
E[m] = exp(mu + sigma^2/2) for lognormal.
"""
function mean_medical_expense(age::Int, health_state::Int, p::ModelParams)
    mu, sigma = medical_expense_params(age, health_state, p)
    return exp(mu + sigma^2 / 2.0)
end

"""
Apply Medicaid floor: if resources after medical expenses fall below
c_floor, government covers the shortfall.

Returns effective cash available after medical expenses (>= c_floor).
"""
function apply_medicaid_floor(cash_before_medical::Float64, medical_expense::Float64,
                               c_floor::Float64)
    cash_after = cash_before_medical - medical_expense
    return max(cash_after, c_floor)
end

#=============================================================================
# ORIGINAL FILE: src/welfare.jl
#=============================================================================

# Consumption-equivalent variation (CEV) welfare calculations.
# CEV = percentage increase in consumption at all dates/states that makes
# the individual indifferent between having and not having annuity access.
#
# For CRRA utility U(c) = c^(1-gamma)/(1-gamma):
#   lambda = (V_with / V_without)^(1/(1-gamma)) - 1
#
# Positive CEV means the individual benefits from annuity market access.

using Interpolations
using Printf

struct CEVResult
    cev::Float64          # consumption-equivalent variation (fraction)
    alpha_star::Float64   # optimal annuity fraction
    V_no_ann::Float64     # value without annuity access
    V_with_ann::Float64   # value with optimal annuity
    excluded::Bool        # true if W_0 outside grid bounds (CEV not estimable)
end

# Backward-compatible constructor — defaults excluded=false.
CEVResult(cev, alpha_star, V_no_ann, V_with_ann) =
    CEVResult(cev, alpha_star, V_no_ann, V_with_ann, false)

"""
Compute CEV for a single individual.

Given a solved HealthSolution, evaluate the welfare gain from annuity
market access for an individual with initial state (W_0, y_existing, H_0).

The CEV formula for CRRA:
  lambda = (V_with / V_without)^(1/(1-gamma)) - 1

With DFJ bequests (kappa > 0) the formula is approximate but standard
in the literature (Lockwood 2012, Reichling-Smetters 2015).
"""
function compute_cev(
    sol::HealthSolution,
    W_0::Float64,
    y_existing::Float64,
    H_0::Int,
    payout_rate::Float64,
)
    p = sol.params
    g = sol.grids

    # Trivial case: no wealth to annuitize
    if W_0 < 1.0
        return CEVResult(0.0, 0.0, 0.0, 0.0)
    end

    # 2D interpolation of V(W, A, H=H_0, t=1)
    V_t1 = sol.V[:, :, H_0, 1]
    V_interp = linear_interpolation(
        (g.W, g.A), V_t1,
        extrapolation_bc=Interpolations.Flat(),
    )

    W_c = clamp(W_0, g.W[1], g.W[end])
    y_c = clamp(y_existing, g.A[1], g.A[end])

    # V without annuity purchase
    V_no_ann = V_interp(W_c, y_c)

    # Search over alpha grid for best V with annuity purchase. Apply the
    # behavioral purchase penalty when psi_purchase > 0 — must mirror the
    # solver's treatment in src/solve.jl, otherwise CEV with the behavioral
    # channel active overstates the welfare gain (the agent would not
    # actually choose this alpha given the friction).
    best_V = V_no_ann
    best_alpha = 0.0
    for alpha in g.alpha
        alpha <= 0.0 && continue
        is_feasible_purchase(alpha, W_0, p) || continue
        pi = alpha * W_0
        W_rem = W_0 - pi
        if p.fixed_cost > 0.0
            W_rem -= p.fixed_cost
        end
        W_rem < 0.0 && continue

        # Age-65 purchase: nominal_premium = pi (inflation_factor = 1).
        # Convention matches wtp.jl/welfare.jl elsewhere: pass nominal_premium
        # to purchase_penalty so the dollar amount is unambiguous.
        nominal_premium = pi
        A_new = nominal_premium * payout_rate
        A_total = y_existing + A_new
        W_rc = clamp(W_rem, g.W[1], g.W[end])
        A_tc = clamp(A_total, g.A[1], g.A[end])
        V_val = V_interp(W_rc, A_tc)
        if p.psi_purchase > 0.0
            V_val -= purchase_penalty(nominal_premium, payout_rate, p.gamma,
                p.psi_purchase, p.psi_purchase_c_ref, p.beta, sol.base_surv)
        end
        if V_val > best_V
            best_V = V_val
            best_alpha = alpha
        end
    end

    V_with_ann = best_V

    # Compute CEV
    # Both V values must be finite and V_with > V_without for positive CEV
    if !isfinite(V_no_ann) || !isfinite(V_with_ann)
        return CEVResult(0.0, best_alpha, V_no_ann, V_with_ann)
    end
    if V_with_ann <= V_no_ann + 1e-12
        return CEVResult(0.0, 0.0, V_no_ann, V_no_ann)
    end

    # CRRA value-ratio CEV approximation: lambda = (V_with / V_without)^(1/(1-gamma)) - 1.
    #
    # NOTE: This is an APPROXIMATION when the model includes non-CRRA value
    # contributions — specifically the bequest shifter kappa (V_bequest is
    # CRRA in (b + kappa), not CRRA in c), the consumption floor c_floor (a
    # kink), source-dependent utility (lambda_W reweights consumption by
    # source), and the Force B purchase-event disutility (additive
    # adjustment to V at the purchase moment, not a flow). The exact CEV
    # would solve V_no_access(c * (1 + lambda)) = V_access for lambda. The
    # closed-form ratio is exact only in the pure CRRA + Yaari special case
    # and is reported here as a tractable approximation; see appendix
    # discussion of welfare interpretation. The ranking of CEV across
    # scenarios (and signs) is preserved by the approximation.
    gamma = p.gamma
    if gamma == 1.0
        # Log utility: V = log(c) + ..., CEV = exp(V_with - V_without) - 1
        cev = exp(V_with_ann - V_no_ann) - 1.0
    else
        # V = c^(1-gamma)/(1-gamma), V < 0 for gamma > 1
        ratio = V_with_ann / V_no_ann
        # For gamma > 1: both V negative, ratio > 0.
        # V_with > V_without (less negative) => ratio < 1
        # (1-gamma) < 0 => exponent 1/(1-gamma) < 0 => ratio^(neg) > 1 => cev > 0
        if ratio <= 0.0
            return CEVResult(0.0, best_alpha, V_no_ann, V_with_ann)
        end
        cev = ratio^(1.0 / (1.0 - gamma)) - 1.0
    end

    # Sanity bound: CEV shouldn't exceed 200% (numerical artifact)
    cev = clamp(cev, -1.0, 2.0)

    return CEVResult(cev, best_alpha, V_no_ann, V_with_ann)
end

"""
Compute CEV for each individual in a population sample.

Population columns: [wealth, income, age, health_state].
If health column is missing, defaults to Fair (2).

Returns (results, mean_cev, median_cev, frac_positive, frac_above_1pct).
"""
function compute_cev_population(
    sol::HealthSolution,
    population::Matrix{Float64},
    payout_rate_age65::Float64;
    base_surv::Union{Vector{Float64}, Nothing}=nothing,
)
    p = sol.params
    g = sol.grids
    n_individuals = size(population, 1)
    has_age = size(population, 2) >= 3
    has_health = size(population, 2) >= 4

    results = CEVResult[]
    sizehint!(results, n_individuals)

    # Precompute interpolation objects keyed by (health, time)
    interp_cache = Dict{Tuple{Int,Int}, typeof(linear_interpolation(
        (g.W, g.A), sol.V[:, :, 1, 1],
        extrapolation_bc=Interpolations.Flat(),
    ))}()

    for i in 1:n_individuals
        W_0 = population[i, 1]
        y_0 = population[i, 2]
        age = has_age ? Int(population[i, 3]) : p.age_start
        ih = has_health ? Int(population[i, 4]) : 2

        # Flag agents with wealth outside grid bounds — CEV is not well-defined
        # because boundary extrapolation produces unreliable values.
        if W_0 < 1.0 || W_0 > g.W[end]
            push!(results, CEVResult(0.0, 0.0, 0.0, 0.0, true))
            continue
        end

        t = age - p.age_start + 1
        if t < 1 || t > p.T
            push!(results, CEVResult(0.0, 0.0, 0.0, 0.0, true))
            continue
        end

        # Age-specific payout rate
        if base_surv !== nothing && age > p.age_start
            remaining_T = p.T - t + 1
            r_discount = p.inflation_rate > 0 ? (1 + p.r) * (1 + p.inflation_rate) - 1 : p.r
            pv = 1.0
            for s in 1:(remaining_T - 1)
                cum_s = 1.0
                for k in t:(t + s - 1)
                    k > length(base_surv) && break
                    cum_s *= base_surv[k]
                end
                pv += cum_s / (1.0 + r_discount)^s
            end
            payout_rate = p.mwr / pv
        else
            payout_rate = payout_rate_age65
        end

        # Use cached interpolation for this (health, time) pair
        V_interp = get!(interp_cache, (ih, t)) do
            linear_interpolation(
                (g.W, g.A), sol.V[:, :, ih, t],
                extrapolation_bc=Interpolations.Flat(),
            )
        end

        W_c = clamp(W_0, g.W[1], g.W[end])
        y_c = clamp(y_0, g.A[1], g.A[end])

        V_no_ann = V_interp(W_c, y_c)

        # Optimal annuity search
        best_V = V_no_ann
        best_alpha = 0.0
        for alpha in g.alpha
            alpha <= 0.0 && continue
            is_feasible_purchase(alpha, W_0, p) || continue
            pi = alpha * W_0
            W_rem = W_0 - pi
            if p.fixed_cost > 0.0
                W_rem -= p.fixed_cost
            end
            W_rem < 0.0 && continue

            # Convert real premium pi (age-65 dollars) to nominal at purchase
            # age. A_state stores the constant nominal annual payment; the
            # Bellman deflates via A_real(t) = A * (1+π)^-(t-1).
            inflation_factor = (1.0 + p.inflation_rate)^(t - 1)
            nominal_premium = pi * inflation_factor
            A_new = nominal_premium * payout_rate
            A_total = y_0 + A_new
            W_rc = clamp(W_rem, g.W[1], g.W[end])
            A_tc = clamp(A_total, g.A[1], g.A[end])
            V_val = V_interp(W_rc, A_tc)
            if p.psi_purchase > 0.0
                # purchase_period=t passes the survival clock starting at the
                # actual purchase age (period t), not period 1. Default
                # purchase_period=1 was wrong for any age-of-purchase > 65.
                V_val -= purchase_penalty(nominal_premium, payout_rate, p.gamma,
                    p.psi_purchase, p.psi_purchase_c_ref, p.beta, sol.base_surv;
                    purchase_period=t)
            end
            if V_val > best_V
                best_V = V_val
                best_alpha = alpha
            end
        end

        # CEV calculation
        gamma = p.gamma
        if !isfinite(V_no_ann) || !isfinite(best_V) || best_V <= V_no_ann + 1e-12
            push!(results, CEVResult(0.0, 0.0, V_no_ann, V_no_ann))
            continue
        end

        if gamma == 1.0
            cev = exp(best_V - V_no_ann) - 1.0
        else
            ratio = best_V / V_no_ann
            if ratio <= 0.0
                push!(results, CEVResult(0.0, best_alpha, V_no_ann, best_V))
                continue
            end
            cev = ratio^(1.0 / (1.0 - gamma)) - 1.0
        end
        cev = clamp(cev, -1.0, 2.0)

        push!(results, CEVResult(cev, best_alpha, V_no_ann, best_V))
    end

    # Summary statistics — exclude out-of-grid agents from aggregates so they
    # don't bias mean/median downward toward zero. Report n_excluded separately
    # so the manuscript can flag the small affected subpopulation.
    n_excluded = count(r -> r.excluded, results)
    included = [r.cev for r in results if !r.excluded]
    mean_cev = length(included) > 0 ? sum(included) / length(included) : 0.0
    sorted = sort(included)
    median_cev = length(sorted) > 0 ? sorted[div(length(sorted) + 1, 2)] : 0.0
    frac_positive = count(c -> c > 0.0, included) / max(length(included), 1)
    frac_above_1pct = count(c -> c > 0.01, included) / max(length(included), 1)

    return (
        results=results,
        mean_cev=mean_cev,
        median_cev=median_cev,
        frac_positive=frac_positive,
        frac_above_1pct=frac_above_1pct,
        n_total=n_individuals,
        n_excluded=n_excluded,
        n_included=n_individuals - n_excluded,
    )
end

"""
Compute CEV across a wealth x bequest x health grid.

This produces the "heterogeneous welfare map" — the key Phase 5 output.
For each bequest specification, solves the full model (all channels on)
then evaluates CEV at each (wealth, health) point.

Returns a NamedTuple with:
- grid: 3D array (n_wealth x n_bequest x n_health) of CEVResult
- wealth_points, bequest_names, health_names: labels
- population_cev: per-bequest population-level CEV stats
"""
function compute_cev_grid(
    base_surv::Vector{Float64},
    population_full::Matrix{Float64};
    bequest_specs::Union{Vector{<:NamedTuple}, Nothing}=nothing,
    wealth_points::Vector{Float64}=[10_000.0, 25_000.0, 50_000.0, 100_000.0,
                                     200_000.0, 500_000.0, 1_000_000.0],
    y_existing::Float64=0.0,
    gamma::Float64=2.5,
    beta::Float64=0.97,
    r::Float64=0.02,
    c_floor::Float64=6_180.0,
    mwr_loaded::Float64=0.82,
    fixed_cost_val::Float64=1_000.0,
    min_purchase_val::Float64=0.0,
    inflation_val::Float64=0.02,
    n_wealth::Int=60,
    n_annuity::Int=20,
    n_alpha::Int=51,
    W_max::Float64=3_000_000.0,
    n_quad::Int=5,
    age_start::Int=65,
    age_end::Int=110,
    annuity_grid_power::Float64=3.0,
    hazard_mult::Vector{Float64}=[0.50, 1.0, 3.0],
    survival_pessimism::Float64=1.0,
    consumption_decline::Float64=0.0,
    health_utility::Vector{Float64}=[1.0, 1.0, 1.0],
    psi_purchase::Float64=0.0,
    psi_purchase_c_ref::Float64=18_000.0,
    lambda_w::Float64=1.0,
    verbose::Bool=true,
)
    # Default bequest specs using Lockwood's original DFJ theta (no recalibration)
    if bequest_specs === nothing
        bequest_specs = [
            (name="No bequest",     theta=0.0,    kappa=0.0),
            (name="Moderate (DFJ)", theta=56.96,  kappa=272_628.0),
            (name="Strong bequest",  theta=200.0, kappa=272_628.0),
        ]
    end

    # SS function for the welfare model. The production decomposition solves
    # per quartile and aggregates; here we solve once with a representative
    # level (median across quartiles, $18,500). This aligns the welfare CEV's
    # baseline with production rather than treating retirees as having zero
    # SS, which previously inflated the marginal value of annuitization. A
    # per-quartile dispatch is left as a future tightening.
    ss_func_welfare(age, p) = 18_500.0

    grid_kw = (n_wealth=n_wealth, n_annuity=n_annuity, n_alpha=n_alpha,
               W_max=W_max, age_start=age_start, age_end=age_end,
               annuity_grid_power=annuity_grid_power)

    # Common keyword args: include preference + behavioral channels so the
    # CEV computation uses the same model the production solve uses. Without
    # these the CEV table would silently report six-channel values while
    # the rest of the pipeline is ten-channel.
    common_kw = (gamma=gamma, beta=beta, r=r,
                 stochastic_health=true, n_health_states=3, n_quad=n_quad,
                 c_floor=c_floor, hazard_mult=hazard_mult,
                 survival_pessimism=survival_pessimism,
                 consumption_decline=consumption_decline,
                 health_utility=health_utility,
                 psi_purchase=psi_purchase,
                 psi_purchase_c_ref=psi_purchase_c_ref)

    # Payout rates: real (for grid sizing) and nominal (for pricing when inflation active)
    p_fair = ModelParams(; gamma=gamma, beta=beta, r=r, mwr=1.0, grid_kw...)
    fair_pr = compute_payout_rate(p_fair, base_surv)

    # Nominal payout rate (higher initial payout, eroded by inflation)
    p_fair_nom = ModelParams(; gamma=gamma, beta=beta, r=r, mwr=1.0,
                               inflation_rate=inflation_val, grid_kw...)
    fair_pr_nom = inflation_val > 0 ? compute_payout_rate(p_fair_nom, base_surv) : fair_pr

    # Build grids using the LARGER payout rate to cover full A range
    grids = build_grids(p_fair, max(fair_pr, fair_pr_nom))

    # Loaded payout rate: use nominal when inflation active (matches model solve)
    loaded_pr = mwr_loaded * (inflation_val > 0 ? fair_pr_nom : fair_pr)

    n_w = length(wealth_points)
    n_b = length(bequest_specs)
    n_h = 3
    health_names = ["Good", "Fair", "Poor"]

    cev_grid = Array{CEVResult}(undef, n_w, n_b, n_h)
    population_cev = []

    # Ensure population has health column
    pop = copy(population_full)
    if size(pop, 2) < 4
        pop = hcat(pop, fill(2.0, size(pop, 1)))
    end

    for (ib, bspec) in enumerate(bequest_specs)
        if verbose
            @printf("  Solving model: %s (theta=%.1f, kappa=\$%s)...\n",
                bspec.name, bspec.theta, string(round(Int, bspec.kappa)))
        end

        p_model = ModelParams(; common_kw...,
            theta=bspec.theta, kappa=bspec.kappa,
            mwr=mwr_loaded, fixed_cost=fixed_cost_val, min_purchase=min_purchase_val,
            lambda_w=lambda_w,
            inflation_rate=inflation_val,
            medical_enabled=true, health_mortality_corr=true,
            grid_kw...)

        t0 = time()
        sol = solve_lifecycle_health(p_model, grids, base_surv, ss_func_welfare)
        solve_time = time() - t0

        if verbose
            @printf("    Solved in %.1fs\n", solve_time)
        end

        # CEV at each grid point
        for ih in 1:n_h
            for iw in 1:n_w
                cev_grid[iw, ib, ih] = compute_cev(
                    sol, wealth_points[iw], y_existing, ih, loaded_pr,
                )
            end
        end

        # Population-level CEV
        pop_result = compute_cev_population(
            sol, pop, loaded_pr; base_surv=base_surv,
        )
        push!(population_cev, (
            name=bspec.name,
            mean_cev=pop_result.mean_cev,
            median_cev=pop_result.median_cev,
            frac_positive=pop_result.frac_positive,
            frac_above_1pct=pop_result.frac_above_1pct,
            n_total=pop_result.n_total,
            n_excluded=pop_result.n_excluded,
            n_included=pop_result.n_included,
            results=pop_result.results,
        ))
    end

    return (
        grid=cev_grid,
        wealth_points=wealth_points,
        bequest_names=[b.name for b in bequest_specs],
        health_names=health_names,
        population_cev=population_cev,
    )
end

"""
Compare lifecycle paths with and without optimal annuity purchase.

Simulates n_sim paths under both regimes (same random seeds) and
reports consumption, wealth, and bequest differences.

y_existing: pre-existing annuity income (e.g., from SS). The agent
receives this regardless; the alpha search adds annuity income on top.
"""
function simulate_welfare_comparison(
    sol::HealthSolution,
    W_0::Float64,
    H_0::Int,
    base_surv::Vector{Float64},
    p::ModelParams;
    payout_rate::Float64,
    y_existing::Float64=0.0,
    n_sim::Int=10_000,
    rng_seed::Int=42,
)
    g = sol.grids
    # Match the SS function used by compute_cev_grid for internal consistency.
    ss_func_welfare(age, p) = 18_500.0

    # Find optimal alpha (same logic as compute_cev)
    V_t1 = sol.V[:, :, H_0, 1]
    V_interp = linear_interpolation(
        (g.W, g.A), V_t1,
        extrapolation_bc=Interpolations.Flat(),
    )

    W_c = clamp(W_0, g.W[1], g.W[end])
    y_c = clamp(y_existing, g.A[1], g.A[end])

    best_V = V_interp(W_c, y_c)
    best_alpha = 0.0
    for alpha in g.alpha
        alpha <= 0.0 && continue
        is_feasible_purchase(alpha, W_0, p) || continue
        pi = alpha * W_0
        W_rem = W_0 - pi
        if p.fixed_cost > 0.0
            W_rem -= p.fixed_cost
        end
        W_rem < 0.0 && continue
        # Age-65 purchase: nominal_premium = pi (inflation_factor = 1).
        nominal_premium = pi
        A_new = nominal_premium * payout_rate
        A_total = y_existing + A_new
        W_rc = clamp(W_rem, g.W[1], g.W[end])
        A_tc = clamp(A_total, g.A[1], g.A[end])
        V_val = V_interp(W_rc, A_tc)
        if p.psi_purchase > 0.0
            V_val -= purchase_penalty(nominal_premium, payout_rate, p.gamma,
                p.psi_purchase, p.psi_purchase_c_ref, p.beta, sol.base_surv)
        end
        if V_val > best_V
            best_V = V_val
            best_alpha = alpha
        end
    end

    # Simulate WITH optimal annuity
    A_opt = y_existing + best_alpha * W_0 * payout_rate
    W_rem_opt = W_0 * (1.0 - best_alpha)
    if best_alpha > 0.0
        W_rem_opt -= p.fixed_cost
    end
    W_rem_opt = max(W_rem_opt, 0.0)

    batch_with = simulate_batch(
        sol, W_rem_opt, A_opt, H_0, base_surv, ss_func_welfare, p;
        n_sim=n_sim, rng_seed=rng_seed,
    )

    # Simulate WITHOUT annuity (same seed for paired comparison)
    batch_without = simulate_batch(
        sol, W_0, y_existing, H_0, base_surv, ss_func_welfare, p;
        n_sim=n_sim, rng_seed=rng_seed,
    )

    return (
        alpha_star=best_alpha,
        with_annuity=batch_with,
        without_annuity=batch_without,
    )
end

#=============================================================================
# ORIGINAL FILE: src/wtp.jl
#=============================================================================

# Willingness-to-pay (WTP) and annuity demand computations.
# Implements Lockwood (2012) WTP methodology:
#   WTP = fraction of non-annuity wealth agent would pay to access annuity markets.

using Interpolations

"""
Compute WTP for annuity market access at each wealth level.

WTP(W_0) = (W_0 - W*) / W_0
where W* is the wealth that, WITH optimal annuity access, yields the same
utility as W_0 WITHOUT annuity access.

`A_existing`: pre-existing annuity income (e.g., from Social Security or prior purchases).
If 0, the agent has no pre-existing annuity income.

Returns a vector of WTP values, one per wealth grid point.
"""
function compute_wtp(sol::Solution, payout_rate::Float64; A_existing::Float64=0.0)
    p = sol.params
    g = sol.grids
    nW = length(g.W)

    # 2D interpolation of V(W, A, t=1)
    V_t1 = sol.V[:, :, 1]
    V_interp = linear_interpolation(
        (g.W, g.A), V_t1,
        extrapolation_bc=Interpolations.Flat(),
    )

    # Clamp A_existing to grid
    A_exist_c = clamp(A_existing, g.A[1], g.A[end])

    wtp = Vector{Float64}(undef, nW)
    for iw in 1:nW
        W_0 = g.W[iw]

        if W_0 < 1.0
            wtp[iw] = 0.0
            continue
        end

        # V without additional annuities: V(W_0, A_existing, t=1)
        V_no_ann = V_interp(W_0, A_exist_c)

        # V with optimal annuitization of W_0 (on top of A_existing)
        best_V = V_no_ann
        for alpha in g.alpha
            alpha <= 0.0 && continue
            is_feasible_purchase(alpha, W_0, p) || continue
            A_new = alpha * W_0 * payout_rate
            W_rem = (1.0 - alpha) * W_0
            if alpha > 0.0 && p.fixed_cost > 0.0
                W_rem -= p.fixed_cost
            end
            W_rem < 0.0 && continue

            A_total = A_existing + A_new
            W_c = clamp(W_rem, g.W[1], g.W[end])
            A_c = clamp(A_total, g.A[1], g.A[end])
            V_val = V_interp(W_c, A_c)
            if V_val > best_V
                best_V = V_val
            end
        end

        # No gain from annuities
        if best_V <= V_no_ann + 1e-12
            wtp[iw] = 0.0
            continue
        end

        # Find W* such that V_with_ann(W*) = V_no_ann
        # V_with_ann(W) = max_alpha V((1-alpha)*W, A_exist + alpha*W*pr, t=1)
        # Use bisection on W
        W_lo = 0.0
        W_hi = W_0

        # Check boundary: if V_with_ann(0) >= V_no_ann, WTP = 100%
        V_ann_at_zero = V_interp(0.0, A_exist_c)  # no wealth, no new annuity
        if V_ann_at_zero >= V_no_ann
            wtp[iw] = 1.0
            continue
        end

        for _ in 1:100
            W_mid = (W_lo + W_hi) / 2.0

            # Compute V_with_ann(W_mid)
            V_best_mid = V_interp(W_mid, A_exist_c)  # alpha=0
            for alpha in g.alpha
                alpha <= 0.0 && continue
                is_feasible_purchase(alpha, W_mid, p) || continue
                A_new = alpha * W_mid * payout_rate
                W_rem = (1.0 - alpha) * W_mid
                if alpha > 0.0 && p.fixed_cost > 0.0
                    W_rem -= p.fixed_cost
                end
                W_rem < 0.0 && continue

                A_total = A_existing + A_new
                W_c = clamp(W_rem, g.W[1], g.W[end])
                A_c = clamp(A_total, g.A[1], g.A[end])
                V_val = V_interp(W_c, A_c)
                if V_val > V_best_mid
                    V_best_mid = V_val
                end
            end

            if V_best_mid < V_no_ann
                W_lo = W_mid
            else
                W_hi = W_mid
            end
            if (W_hi - W_lo) < 1e-6 * W_0
                break
            end
        end

        W_star = (W_lo + W_hi) / 2.0
        wtp[iw] = (W_0 - W_star) / W_0
        wtp[iw] = clamp(wtp[iw], 0.0, 1.0)
    end

    return wtp
end

"""
Compute WTP for a specific (N_ref, y_ref) pair, matching Lockwood's setup.

- N_ref: non-annuity (liquid) wealth
- y_ref: pre-existing annuity income per year
- sol: lifecycle solution on the full grid
- payout_rate: fair payout rate

Returns WTP as a fraction of N_ref.
"""
function compute_wtp_lockwood(
    N_ref::Float64,
    y_ref::Float64,
    sol::Solution,
    payout_rate::Float64,
)
    p = sol.params
    g = sol.grids

    V_t1 = sol.V[:, :, 1]
    V_interp = linear_interpolation(
        (g.W, g.A), V_t1,
        extrapolation_bc=Interpolations.Flat(),
    )

    N_c = clamp(N_ref, g.W[1], g.W[end])
    y_c = clamp(y_ref, g.A[1], g.A[end])

    # V without additional annuity purchase
    V_no_ann = V_interp(N_c, y_c)

    # V with optimal annuitization of N_ref
    best_V = V_no_ann
    best_alpha = 0.0
    for alpha in g.alpha
        alpha <= 0.0 && continue
        is_feasible_purchase(alpha, N_ref, p) || continue
        pi = alpha * N_ref  # premium
        W_rem = N_ref - pi
        if alpha > 0.0 && p.fixed_cost > 0.0
            W_rem -= p.fixed_cost
        end
        W_rem < 0.0 && continue

        A_new = pi * payout_rate  # fair pricing: MWR already in payout_rate
        A_total = y_ref + A_new
        W_c = clamp(W_rem, g.W[1], g.W[end])
        A_c = clamp(A_total, g.A[1], g.A[end])
        V_val = V_interp(W_c, A_c)
        if V_val > best_V
            best_V = V_val
            best_alpha = alpha
        end
    end

    if best_V <= V_no_ann + 1e-12
        return (wtp=0.0, alpha_star=0.0, V_no_ann=V_no_ann, V_ann=V_no_ann)
    end

    # Bisection: find N* such that V_with_ann(N*) = V_no_ann
    N_lo = 0.0
    N_hi = N_ref

    # Check if V_with_ann(0) already exceeds V_no_ann
    # (only if y_ref alone provides enough)
    V_at_zero = V_interp(0.0, y_c)
    if V_at_zero >= V_no_ann
        return (wtp=1.0, alpha_star=best_alpha, V_no_ann=V_no_ann, V_ann=best_V)
    end

    for _ in 1:100
        N_mid = (N_lo + N_hi) / 2.0

        # Optimal annuitization at N_mid
        V_best_mid = V_interp(clamp(N_mid, g.W[1], g.W[end]), y_c)
        for alpha in g.alpha
            alpha <= 0.0 && continue
            is_feasible_purchase(alpha, N_mid, p) || continue
            pi = alpha * N_mid
            W_rem = N_mid - pi
            if alpha > 0.0 && p.fixed_cost > 0.0
                W_rem -= p.fixed_cost
            end
            W_rem < 0.0 && continue

            A_new = pi * payout_rate
            A_total = y_ref + A_new
            W_c = clamp(W_rem, g.W[1], g.W[end])
            A_c = clamp(A_total, g.A[1], g.A[end])
            V_val = V_interp(W_c, A_c)
            if V_val > V_best_mid
                V_best_mid = V_val
            end
        end

        if V_best_mid < V_no_ann
            N_lo = N_mid
        else
            N_hi = N_mid
        end
        if (N_hi - N_lo) < 1.0  # $1 precision
            break
        end
    end

    N_star = (N_lo + N_hi) / 2.0
    wtp_val = (N_ref - N_star) / N_ref
    return (wtp=clamp(wtp_val, 0.0, 1.0), alpha_star=best_alpha,
            V_no_ann=V_no_ann, V_ann=best_V)
end

"""
Recalibrate DFJ bequest theta for a different gamma (risk aversion).

DFJ theta was estimated at gamma_ref (Lockwood sigma=2). The FOC at the
optimal bequest gives theta = ((b+kappa)/c)^gamma, so matching the same
optimal allocation at a new gamma requires:

    theta_new = theta_ref^(gamma_new / gamma_ref)

This preserves the marginal rate of substitution between consumption and
bequests at the optimum. At gamma_ref, returns theta_ref unchanged.
"""
function recalibrate_theta_dfj(theta_ref::Float64, gamma_new::Float64;
                                gamma_ref::Float64=2.0)
    gamma_new == gamma_ref && return theta_ref
    return theta_ref^(gamma_new / gamma_ref)
end

"""
Calibrate bequest intensity theta from a target bequest-to-wealth ratio.

From Lockwood (BAP_wtp.m line 206):
  theta = (b*/c*)^sigma
where b* = b_star_over_N * N and c* = (N - b*) / p_unit_ann.
"""
function calibrate_theta(
    b_star_over_N::Float64,
    W_0::Float64,
    payout_rate::Float64,
    p::ModelParams,
)
    N = W_0
    b_star = b_star_over_N * N

    # Present value of fair annuity = 1/payout_rate
    p_unit_ann = 1.0 / payout_rate

    # Fair annuity budget constraint: N = p_ann * c* + b*
    # (with PV bequest preferences, p_unit_b = 1)
    c_star = (N - b_star) / p_unit_ann
    c_star = max(c_star, 0.01)

    # From BAP_wtp.m: theta = (b*/c*)^sigma
    theta = (b_star / c_star)^p.gamma

    return theta
end

"""
Compute annuity ownership rate from a population of individuals.

For each individual (wealth, income, age), finds optimal annuity purchase
and counts as "owner" if optimal purchase > 0.

`population` is a matrix where each row is [wealth, income] or [wealth, income, age].
If age is provided, the annuitization decision uses V at the individual's age.
The payout rate is also age-adjusted when ages are provided.
"""
function compute_ownership_rate(
    sol::Solution,
    population::Matrix{Float64},
    payout_rate_age65::Float64;
    surv::Union{Vector{Float64}, Nothing}=nothing,
)
    p = sol.params
    g = sol.grids
    n_individuals = size(population, 1)
    has_age = size(population, 2) >= 3
    n_owners = 0
    n_evaluated = 0

    # Precompute interpolation objects keyed by time period
    interp_cache = Dict{Int, typeof(linear_interpolation(
        (g.W, g.A), sol.V[:, :, 1],
        extrapolation_bc=Interpolations.Flat(),
    ))}()

    n_above_grid = 0
    for i in 1:n_individuals
        raw_W = population[i, 1]
        # Skip agents above grid max (extrapolation unreliable)
        if raw_W > g.W[end]
            n_above_grid += 1
            continue
        end
        W_0 = max(raw_W, 0.0)
        y_0 = clamp(population[i, 2], g.A[1], g.A[end])
        age = has_age ? Int(population[i, 3]) : p.age_start

        W_0 < 1.0 && continue

        # Time period for this individual's age
        t = age - p.age_start + 1
        t < 1 && continue
        t > p.T && continue

        n_evaluated += 1

        # Age-specific payout rate (older => fewer expected payments => higher rate)
        if surv !== nothing && age > p.age_start
            r_discount = p.inflation_rate > 0 ? (1 + p.r) * (1 + p.inflation_rate) - 1 : p.r
            remaining_T = p.T - t + 1
            pv = 1.0
            for s in 1:(remaining_T - 1)
                cum_s = 1.0
                for k in t:(t + s - 1)
                    k > length(surv) && break
                    cum_s *= surv[k]
                end
                pv += cum_s / (1.0 + r_discount)^s
            end
            payout_rate = p.mwr / pv
        else
            payout_rate = payout_rate_age65
        end

        # Use cached interpolation for this time period
        V_interp = get!(interp_cache, t) do
            linear_interpolation(
                (g.W, g.A), sol.V[:, :, t],
                extrapolation_bc=Interpolations.Flat(),
            )
        end

        V_no_ann = V_interp(W_0, y_0)
        best_V = V_no_ann
        best_pi = 0.0

        for alpha in g.alpha
            alpha <= 0.0 && continue
            is_feasible_purchase(alpha, W_0, p) || continue
            pi = alpha * W_0
            W_rem = W_0 - pi
            if p.fixed_cost > 0.0
                W_rem -= p.fixed_cost
            end
            W_rem < 0.0 && continue

            # Convert real premium pi (age-65 dollars) to nominal at purchase
            # age. A_state stores the constant nominal annual payment; the
            # Bellman deflates via A_real(t) = A * (1+π)^-(t-1).
            inflation_factor = (1.0 + p.inflation_rate)^(t - 1)
            nominal_premium = pi * inflation_factor
            A_new = nominal_premium * payout_rate
            A_total = y_0 + A_new
            W_c = clamp(W_rem, g.W[1], g.W[end])
            A_c = clamp(A_total, g.A[1], g.A[end])
            V_val = V_interp(W_c, A_c)
            if V_val > best_V
                best_V = V_val
                best_pi = pi
            end
        end

        if best_pi > 0.0
            n_owners += 1
        end
    end

    return n_evaluated > 0 ? n_owners / n_evaluated : 0.0
end


# ===================================================================
# Phase 3: Health-Aware WTP and Ownership
# ===================================================================

"""
Compute WTP for annuity market access with health states (Phase 3).

For a given initial health state, computes the fraction of non-annuity
wealth the agent would pay to access annuity markets.

Arguments:
- N_ref: non-annuity (liquid) wealth
- y_ref: pre-existing annuity income per year
- sol: HealthSolution from solve_lifecycle_health
- payout_rate: annuity payout rate
- initial_health: 1=Good, 2=Fair, 3=Poor (default: 2=Fair)
"""
function compute_wtp_health(
    N_ref::Float64,
    y_ref::Float64,
    sol::HealthSolution,
    payout_rate::Float64;
    initial_health::Int=2,
)
    p = sol.params
    g = sol.grids

    V_t1 = sol.V[:, :, initial_health, 1]
    V_interp = linear_interpolation(
        (g.W, g.A), V_t1,
        extrapolation_bc=Interpolations.Flat(),
    )

    N_c = clamp(N_ref, g.W[1], g.W[end])
    y_c = clamp(y_ref, g.A[1], g.A[end])

    # V without additional annuity purchase
    V_no_ann = V_interp(N_c, y_c)

    # V with optimal annuitization of N_ref
    best_V = V_no_ann
    best_alpha = 0.0
    for alpha in g.alpha
        alpha <= 0.0 && continue
        is_feasible_purchase(alpha, N_ref, p) || continue
        pi = alpha * N_ref
        W_rem = N_ref - pi
        if alpha > 0.0 && p.fixed_cost > 0.0
            W_rem -= p.fixed_cost
        end
        W_rem < 0.0 && continue

        A_new = pi * payout_rate
        A_total = y_ref + A_new
        W_c = clamp(W_rem, g.W[1], g.W[end])
        A_c = clamp(A_total, g.A[1], g.A[end])
        V_val = V_interp(W_c, A_c)
        if V_val > best_V
            best_V = V_val
            best_alpha = alpha
        end
    end

    if best_V <= V_no_ann + 1e-12
        return (wtp=0.0, alpha_star=0.0, V_no_ann=V_no_ann, V_ann=V_no_ann)
    end

    # Bisection: find N* such that V_with_ann(N*) = V_no_ann
    N_lo = 0.0
    N_hi = N_ref

    V_at_zero = V_interp(0.0, y_c)
    if V_at_zero >= V_no_ann
        return (wtp=1.0, alpha_star=best_alpha, V_no_ann=V_no_ann, V_ann=best_V)
    end

    for _ in 1:100
        N_mid = (N_lo + N_hi) / 2.0

        V_best_mid = V_interp(clamp(N_mid, g.W[1], g.W[end]), y_c)
        for alpha in g.alpha
            alpha <= 0.0 && continue
            is_feasible_purchase(alpha, N_mid, p) || continue
            pi = alpha * N_mid
            W_rem = N_mid - pi
            if alpha > 0.0 && p.fixed_cost > 0.0
                W_rem -= p.fixed_cost
            end
            W_rem < 0.0 && continue

            A_new = pi * payout_rate
            A_total = y_ref + A_new
            W_c = clamp(W_rem, g.W[1], g.W[end])
            A_c = clamp(A_total, g.A[1], g.A[end])
            V_val = V_interp(W_c, A_c)
            if V_val > V_best_mid
                V_best_mid = V_val
            end
        end

        if V_best_mid < V_no_ann
            N_lo = N_mid
        else
            N_hi = N_mid
        end
        if (N_hi - N_lo) < 1.0
            break
        end
    end

    N_star = (N_lo + N_hi) / 2.0
    wtp_val = (N_ref - N_star) / N_ref
    return (wtp=clamp(wtp_val, 0.0, 1.0), alpha_star=best_alpha,
            V_no_ann=V_no_ann, V_ann=best_V)
end

"""
Compute annuity ownership rate with health states (Phase 3).

For each individual, uses the value function at their health state
to determine if annuity purchase is optimal.

`population` columns: [wealth, income, age, health_state].
If health_state column is missing, defaults to Fair (2).

Optional `weights` vector: if provided, computes weighted ownership rate
using HRS survey weights (one weight per row of `population`).
"""
function compute_ownership_rate_health(
    sol::HealthSolution,
    population::Matrix{Float64},
    payout_rate_age65::Float64;
    base_surv::Union{Vector{Float64}, Nothing}=nothing,
    weights::Union{Vector{Float64}, Nothing}=nothing,
)
    p = sol.params
    g = sol.grids
    n_individuals = size(population, 1)
    has_age = size(population, 2) >= 3
    has_health = size(population, 2) >= 4
    n_owners = 0.0
    n_evaluated = 0.0
    sum_alpha = 0.0

    # Precompute interpolation objects keyed by (health, time)
    interp_cache = Dict{Tuple{Int,Int}, typeof(linear_interpolation(
        (g.W, g.A), sol.V[:, :, 1, 1],
        extrapolation_bc=Interpolations.Flat(),
    ))}()

    n_above_grid = 0
    for i in 1:n_individuals
        raw_W = population[i, 1]
        # Skip agents above grid max (extrapolation unreliable)
        if raw_W > g.W[end]
            n_above_grid += 1
            continue
        end
        W_0 = max(raw_W, 0.0)
        y_0 = clamp(population[i, 2], g.A[1], g.A[end])
        age = has_age ? Int(population[i, 3]) : p.age_start
        ih = has_health ? Int(population[i, 4]) : 2  # default Fair

        W_0 < 1.0 && continue

        t = age - p.age_start + 1
        t < 1 && continue
        t > p.T && continue

        w_i = weights !== nothing ? weights[i] : 1.0
        n_evaluated += w_i

        # Age-specific payout rate
        if base_surv !== nothing && age > p.age_start
            r_discount = p.inflation_rate > 0 ? (1 + p.r) * (1 + p.inflation_rate) - 1 : p.r
            remaining_T = p.T - t + 1
            pv = 1.0
            for s in 1:(remaining_T - 1)
                cum_s = 1.0
                for k in t:(t + s - 1)
                    k > length(base_surv) && break
                    cum_s *= base_surv[k]
                end
                pv += cum_s / (1.0 + r_discount)^s
            end
            payout_rate = p.mwr / pv
        else
            payout_rate = payout_rate_age65
        end

        # Use cached interpolation for this (health, time) pair
        V_interp = get!(interp_cache, (ih, t)) do
            linear_interpolation(
                (g.W, g.A), sol.V[:, :, ih, t],
                extrapolation_bc=Interpolations.Flat(),
            )
        end

        V_no_ann = V_interp(W_0, y_0)
        best_V = V_no_ann
        best_pi = 0.0

        for alpha in g.alpha
            alpha <= 0.0 && continue
            is_feasible_purchase(alpha, W_0, p) || continue
            pi = alpha * W_0
            W_rem = W_0 - pi
            if p.fixed_cost > 0.0
                W_rem -= p.fixed_cost
            end
            W_rem < 0.0 && continue

            # Convert the real premium pi (in age-65 dollars) to a nominal
            # premium at the purchase age. compute_payout_rate returns nominal
            # payment per nominal premium, so we need a nominal-units bridge.
            inflation_factor = (1.0 + p.inflation_rate)^(t - 1)
            nominal_premium = pi * inflation_factor
            # A_state stores the constant nominal annuity payment. The Bellman
            # then converts to age-65 real dollars via A_real(t) = A * (1+π)^-(t-1).
            A_new = nominal_premium * payout_rate
            A_total = y_0 + A_new
            W_c = clamp(W_rem, g.W[1], g.W[end])
            A_c = clamp(A_total, g.A[1], g.A[end])
            V_val = V_interp(W_c, A_c)
            # Narrow-framing purchase penalty NPV: the agent's mental accounting
            # tracks nominal cumulative receipts vs nominal premium, so pass
            # the nominal premium (not the real one). purchase_period=t slices
            # the survival schedule conditional on being alive at the purchase
            # age (default purchase_period=1 was wrong for any age > 65).
            if p.psi_purchase > 0.0
                V_val -= purchase_penalty(nominal_premium, payout_rate, p.gamma,
                    p.psi_purchase, p.psi_purchase_c_ref, p.beta, sol.base_surv;
                    purchase_period=t)
            end
            if V_val > best_V
                best_V = V_val
                best_pi = pi
            end
        end

        best_alpha_i = W_0 > 0.0 ? best_pi / W_0 : 0.0
        sum_alpha += w_i * best_alpha_i
        if best_pi > 0.0
            n_owners += w_i
        end
    end

    if n_evaluated > 0.0
        return (ownership_rate = n_owners / n_evaluated,
                mean_alpha = sum_alpha / n_evaluated,
                n_above_grid = n_above_grid,
                n_evaluated = Int(round(n_evaluated)))
    else
        return (ownership_rate = 0.0, mean_alpha = 0.0,
                n_above_grid = n_above_grid,
                n_evaluated = 0)
    end
end
