# Shared subset-enumeration and Shapley machinery.
#
# Extracted from scripts/run_subset_enumeration.jl so the 2048-subset
# enumeration and the gamma-stability sweep (scripts/run_shapley_gamma_stability.jl)
# use one implementation. Loaded into the AnnuityPuzzle module; workers receive
# these via the standard `@everywhere using .AnnuityPuzzle` module load, so no
# per-definition @everywhere is needed.
#
# Channel indices (11-channel structure; medical risk and the Reichling-Smetters
# health-mortality correlation are a single combined channel CH_MED_RS, because
# the R-S mechanism's quantitative bite operates through its interaction with
# stochastic medical costs). These constants are module-internal (NOT exported)
# to avoid clashing with other channel-index schemes in the codebase;
# build_subset_config references them.
const CH_SS            = 1
const CH_BEQUESTS      = 2
const CH_MED_RS        = 3   # Combined: medical risk + R-S correlation
const CH_PESSIMISM     = 4
const CH_AGE_NEEDS     = 5
const CH_STATE_UTIL    = 6
const CH_LOADS         = 7
const CH_INFLATION     = 8
const CH_LTC           = 9   # Public-care aversion (Ameriks 2011 JF, 2020 JPE)
const CH_SDU           = 10  # Source-dependent utility (lambda_w)
const CH_PED           = 11  # Narrow-framing at-purchase penalty (psi_purchase)

"""
    bitmask_to_channels(mask::Int) -> Set{Int}

Convert an integer bitmask to the set of active channel indices. Bit i
(0-indexed) corresponds to channel i+1. Eleven channels: bits 0-10. A mask
below 512 (bits 9,10 off) encodes a 9-channel structural subset.
"""
function bitmask_to_channels(mask::Int)
    active = Set{Int}()
    for i in 0:10  # 11 channels: bits 0-10
        if (mask >> i) & 1 == 1
            push!(active, i + 1)
        end
    end
    return active
end

"""
    build_subset_config(active::Set{Int}; kwargs...) -> NamedTuple

Build ModelParams overrides for a given set of active channel indices. Each
channel, when present in `active`, switches its parameter from the off/neutral
value to the supplied calibration value.
"""
function build_subset_config(active::Set{Int};
        theta_dfj, kappa_dfj, mwr_loaded, fixed_cost, min_purchase, inflation_val,
        survival_pessimism, ss_quartile_levels,
        consumption_decline, health_utility, chi_ltc_val,
        lambda_w_val, psi_purchase_val, psi_purchase_c_ref_val,
        fair_pr::Float64)

    ss_levels = [0.0, 0.0, 0.0, 0.0]
    # When SS is OFF, its actuarial PV is returned as an equal-PV liquid
    # endowment so the SS player isolates the annuitized-vs-liquid form of
    # fixed lifetime resources (a clean pre-annuitization effect) rather than
    # an income effect. Commuted at the model's own fair real price
    # (1/fair_pr per dollar of annual income). Zero when SS is ON or when no
    # fair price is supplied (legacy callers).
    w_commuted = zeros(4)
    theta = 0.0
    kappa = 0.0
    medical_enabled = false
    health_mortality_corr = false
    psi = 1.0
    mwr = 1.0
    fc = 0.0
    min_p = 0.0
    infl = 0.0
    cd = 0.0
    hu = [1.0, 1.0, 1.0]
    chi_l = 1.0
    lw = 1.0
    psi_p = 0.0
    psi_p_cref = 18_000.0

    if CH_SS in active
        ss_levels = copy(ss_quartile_levels)
    else
        # SS off: commute its actuarial PV to an equal-PV liquid endowment.
        # fair_pr is the coalition's fair REAL payout rate (1/PV per $1/yr).
        fair_pr > 0.0 || error("build_subset_config: fair_pr must be > 0 for the commuted-PV SS counterfactual")
        w_commuted = collect(ss_quartile_levels) ./ fair_pr
    end
    if CH_BEQUESTS in active
        theta = theta_dfj
        kappa = kappa_dfj
    end
    # Combined R-S + Medical channel: setting it activates both stochastic
    # medical-expense risk AND the health-mortality correlation. R-S's
    # quantitative bite in this framework operates through the interaction
    # with medical risk, so the two are not separately switchable.
    if CH_MED_RS in active
        medical_enabled = true
        health_mortality_corr = true
    end
    if CH_PESSIMISM in active
        psi = survival_pessimism
    end
    if CH_AGE_NEEDS in active
        cd = consumption_decline
    end
    if CH_STATE_UTIL in active
        hu = copy(health_utility)
    end
    if CH_LOADS in active
        mwr = mwr_loaded
        fc = fixed_cost
        min_p = min_purchase
    end
    if CH_INFLATION in active
        infl = inflation_val
    end
    # Public-care aversion (Ameriks 2011 JF; 2020 JPE): activates the chi_ltc
    # utility multiplier when the consumption floor binds AND health is Poor
    # (Medicaid-LTC binding). Operationally meaningful only when medical risk is
    # also active; if CH_MED_RS is off, the consumption floor is rarely hit.
    if CH_LTC in active
        chi_l = chi_ltc_val
    end
    if CH_SDU in active
        lw = lambda_w_val
    end
    if CH_PED in active
        psi_p = psi_purchase_val
        psi_p_cref = psi_purchase_c_ref_val
    end

    return (ss_levels=ss_levels,
            w_commuted=w_commuted,
            theta=theta, kappa=kappa,
            medical_enabled=medical_enabled,
            health_mortality_corr=health_mortality_corr,
            survival_pessimism=psi,
            consumption_decline=cd,
            health_utility=hu,
            mwr=mwr, fixed_cost=fc, min_purchase=min_p,
            inflation_rate=infl,
            chi_ltc=chi_l,
            lambda_w=lw,
            psi_purchase=psi_p,
            psi_purchase_c_ref=psi_p_cref)
end

"""
    exact_shapley(n::Int, lookup::Dict{Int, Float64}) -> Vector{Float64}

Exact Shapley values over an `n`-channel cooperative game whose value is the
ownership drop a coalition produces: v(S) = lookup[0] - lookup[S]. `lookup`
must contain ownership for every subset bitmask 0 .. 2^n - 1. Returns the
per-channel Shapley value (in ownership-fraction units; multiply by 100 for pp).
"""
function exact_shapley(n::Int, lookup::Dict{Int, Float64})
    shapley = zeros(n)

    # Precompute factorials
    fact = zeros(Int, n + 1)
    fact[1] = 1  # 0! = 1
    for k in 1:n
        fact[k + 1] = fact[k] * k
    end

    for i in 1:n
        bit_i = 1 << (i - 1)
        phi_i = 0.0

        # Sum over all subsets S that do NOT contain channel i.
        for s_mask in 0:((1 << n) - 1)
            (s_mask & bit_i) != 0 && continue  # skip if i is in S

            s_size = count_ones(s_mask)
            s_union_i = s_mask | bit_i

            # Marginal contribution of channel i to coalition S:
            # v(S ∪ {i}) - v(S) = ownership(S) - ownership(S ∪ {i})
            mc = lookup[s_mask] - lookup[s_union_i]

            # Shapley weight: |S|! * (n - |S| - 1)! / n!
            weight = Float64(fact[s_size + 1]) * Float64(fact[n - s_size]) / Float64(fact[n + 1])
            phi_i += weight * mc
        end

        shapley[i] = phi_i
    end

    return shapley
end
