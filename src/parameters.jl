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
    lambda_w::Float64 = 1.0           # source-dependent utility (Blanchett-Finke 2024-25, partialled)
                                       # 1.0 = off; 0.85 = production residual after netting medical/bequest/tax channels
                                       # Implementation: c_eff = c_income + lambda_w * c_portfolio
    chi_ltc::Float64 = 1.0            # public-care aversion (Ameriks 2011 QJE; 2020 ECMA)
                                       # 1.0 = channel off
                                       # 0.5 = production: utility multiplied by chi_ltc when
                                       #       consumption floor binds AND health = Poor
                                       #       (Medicaid-LTC binding state). Captures retiree
                                       #       aversion to publicly-financed long-term care.

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
        "behavioral" => [:psi_purchase, :psi_purchase_c_ref, :lambda_w, :chi_ltc],
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
