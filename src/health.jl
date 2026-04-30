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

"""
Return (nodes, weights) for Gauss-Hermite quadrature adapted to standard
normal integration: E[f(Z)] ≈ Σ weights[i] × f(nodes[i]) where Z ~ N(0,1).

Supports n ∈ {3, 5, 7, 9, 11}.
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
    else
        error("Gauss-Hermite quadrature only implemented for n ∈ {3, 5, 7, 9, 11}, got n=$n")
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
