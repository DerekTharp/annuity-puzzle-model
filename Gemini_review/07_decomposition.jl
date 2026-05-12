# =============================================================================
# 07_decomposition.jl — Channel decomposition machinery and pipeline scripts.
#
# This file consolidates:
#   src/decomposition.jl                channel-toggle harness and ModelParams overrides
#   scripts/run_decomposition.jl        sequential decomposition (rational + preference + behavioral)
#   scripts/run_subset_enumeration.jl   1024-subset enumeration for Shapley
#   scripts/run_shapley_decomposition.jl Shapley value computation from subset table
#
# This is where the 10-channel decomposition is operationalized. The Shapley
# stage is the largest single computational cost (1024 full-model solves).
# =============================================================================

#=============================================================================
# ORIGINAL FILE: src/decomposition.jl
#=============================================================================

# Sequential decomposition of predicted annuity ownership.
# The core contribution: add channels one at a time from the Yaari benchmark
# (100% annuitization) and measure how each reduces predicted ownership.
# Also computes multiplicative interaction metrics.

using Printf

struct DecompositionStep
    name::String
    ownership_rate::Float64
    mean_alpha::Float64
    delta::Float64
    solve_time::Float64
end

struct DecompositionResult
    steps::Vector{DecompositionStep}
end

# Default SS levels by wealth quartile (income.jl breakpoints)
const SS_QUARTILE_LEVELS = [14_000.0, 17_000.0, 20_000.0, 25_000.0]
const SS_QUARTILE_BREAKS = [30_000.0, 120_000.0, 350_000.0]

"""
Filter population matrix to agents in a given wealth quartile.
Q1 = W < breaks[1], Q2 = breaks[1] <= W < breaks[2], etc.
"""
function _filter_quartile(pop::Matrix{Float64}, q::Int, breaks::Vector{Float64})
    n = size(pop, 1)
    mask = falses(n)
    for i in 1:n
        w = pop[i, 1]
        if q == 1
            mask[i] = w < breaks[1]
        elseif q == 2
            mask[i] = w >= breaks[1] && w < breaks[2]
        elseif q == 3
            mask[i] = w >= breaks[2] && w < breaks[3]
        else
            mask[i] = w >= breaks[3]
        end
    end
    return pop[mask, :]
end

"""
Solve the lifecycle model under a given configuration and evaluate
ownership rate on a population sample.

Returns (sol, ownership, solve_time).
"""
function solve_and_evaluate(
    p::ModelParams,
    grids::Grids,
    base_surv::Vector{Float64},
    ss_func::Function,
    population::Matrix{Float64},
    payout_rate::Float64;
    step_name::String="",
    verbose::Bool=true,
)
    t0 = time()
    sol = solve_lifecycle_health(p, grids, base_surv, ss_func)
    solve_time = time() - t0

    result = compute_ownership_rate_health(
        sol, population, payout_rate; base_surv=base_surv,
    )
    ownership = result.ownership_rate
    mean_alpha = result.mean_alpha

    if verbose
        @printf("  %-50s  %6.1f%%  (a=%.3f)  (%.1fs)\n",
            step_name, ownership * 100, mean_alpha, solve_time)
    end

    return (sol=sol, ownership=ownership, mean_alpha=mean_alpha, solve_time=solve_time)
end

"""
Solve per SS quartile and aggregate ownership.

When all ss_levels are equal (including all zeros), solves once.
Otherwise solves 4 times (one per wealth quartile with different SS).
"""
function solve_and_evaluate(
    p::ModelParams,
    grids::Grids,
    base_surv::Vector{Float64},
    ss_levels::Vector{Float64},
    population::Matrix{Float64},
    payout_rate::Float64;
    step_name::String="",
    verbose::Bool=true,
)
    t0 = time()

    if all(x -> x == ss_levels[1], ss_levels)
        # All quartiles identical: solve once
        ss_val = ss_levels[1]
        ss_func_uniform = (age, p) -> ss_val
        sol = solve_lifecycle_health(p, grids, base_surv, ss_func_uniform)
        result = compute_ownership_rate_health(
            sol, population, payout_rate; base_surv=base_surv,
        )
        ownership = result.ownership_rate
        mean_alpha = result.mean_alpha
    else
        # Solve per quartile and aggregate (parallel when workers available)
        quartile_tasks = collect(1:4)
        _p = p; _grids = grids; _bs = base_surv; _pop = population; _pr = payout_rate

        quartile_results = parallel_solve(quartile_tasks) do q
            ss_val_q = ss_levels[q]
            ss_func_q = (age, p) -> ss_val_q
            sol_q = solve_lifecycle_health(_p, _grids, _bs, ss_func_q)

            pop_q = _filter_quartile(_pop, q, SS_QUARTILE_BREAKS)
            n_q = size(pop_q, 1)
            if n_q == 0
                return (ownership=0.0, mean_alpha=0.0, n=0.0)
            end

            result_q = compute_ownership_rate_health(
                sol_q, pop_q, _pr; base_surv=_bs,
            )
            (ownership=result_q.ownership_rate, mean_alpha=result_q.mean_alpha, n=Float64(n_q))
        end

        total_owners = sum(r.ownership * r.n for r in quartile_results)
        total_alpha = sum(r.mean_alpha * r.n for r in quartile_results)
        total_n = sum(r.n for r in quartile_results)

        ownership = total_n > 0 ? total_owners / total_n : 0.0
        mean_alpha = total_n > 0 ? total_alpha / total_n : 0.0
    end

    solve_time = time() - t0

    if verbose
        @printf("  %-50s  %6.1f%%  (a=%.3f)  (%.1fs)\n",
            step_name, ownership * 100, mean_alpha, solve_time)
    end

    return (sol=nothing, ownership=ownership, mean_alpha=mean_alpha, solve_time=solve_time)
end

"""
Run the sequential decomposition from the Yaari benchmark to the full model.

When `ss_levels` is provided (non-empty), SS enters through the Bellman equation
via ss_func (COLA-protected, not inflation-eroded) and is included as Step 1.
Population column 2 should be zero in this mode. Produces up to 10 steps.

When `ss_levels` is empty (default), SS stays on the A grid via population[:,2]
for backward compatibility. Produces up to 9 steps.

Steps (with ss_levels):
  0. True Yaari benchmark (no SS, no bequests, fair pricing, no medical)
  1. + Social Security pre-annuitization
  2. + Bequest motives
  3. + Medical expenditure risk (uncorrelated with survival)
  4. + Health-mortality correlation (Reichling-Smetters)
  5. + Survival pessimism (O'Dea & Sturrock 2023)
  6. + State-dependent utility (FLN 2013, optional)
  7. + Age-varying consumption needs (Aguiar-Hurst, optional)
  8. + Realistic pricing loads (MWR < 1, fixed cost)
  9. + Inflation erosion (nominal annuity)

Steps 6 and 7 are skipped when their parameters are at neutral defaults
(health_utility=[1,1,1] and consumption_decline=0.0).

Returns DecompositionResult with ownership rates at each step.
"""
function run_decomposition(
    base_surv::Vector{Float64},
    population_full::Matrix{Float64};
    gamma::Float64=3.0,
    beta::Float64=0.97,
    r::Float64=0.02,
    theta::Float64=2.0,
    kappa::Float64=10.0,
    c_floor::Float64=3000.0,
    mwr_loaded::Float64=0.87,
    fixed_cost_val::Float64=1000.0,
    inflation_val::Float64=0.03,
    n_wealth::Int=50,
    n_annuity::Int=15,
    n_alpha::Int=51,
    W_max::Float64=1_000_000.0,
    n_quad::Int=5,
    age_start::Int=65,
    age_end::Int=100,
    annuity_grid_power::Float64=2.0,
    hazard_mult::Vector{Float64}=[0.6, 1.0, 2.0],
    hazard_mult_by_age::Union{Nothing,Matrix{Float64}}=nothing,
    hazard_mult_age_midpoints::Union{Nothing,Vector{Float64}}=nothing,
    survival_pessimism::Float64=1.0,
    min_wealth::Float64=0.0,
    ss_levels::Vector{Float64}=Float64[],
    consumption_decline_val::Float64=0.0,
    health_utility_vals::Vector{Float64}=[1.0, 1.0, 1.0],
    psi_purchase_val::Float64=0.0,
    lambda_w_val::Float64=1.0,
    min_purchase_val::Float64=0.0,
    verbose::Bool=true,
)
    ss_zero(age, p) = 0.0
    ss_enabled = !isempty(ss_levels)
    ss_levels_zero = [0.0, 0.0, 0.0, 0.0]

    # Common grid parameters
    grid_kw = (n_wealth=n_wealth, n_annuity=n_annuity, n_alpha=n_alpha,
               W_max=W_max, age_start=age_start, age_end=age_end,
               annuity_grid_power=annuity_grid_power)

    # Common model parameters (passed to all ModelParams constructors).
    # Age-band hazard support: when hazard_mult_by_age and
    # hazard_mult_age_midpoints are set, the model interpolates hazard
    # multipliers across age bands rather than using a constant vector.
    common_kw = if hazard_mult_by_age !== nothing && hazard_mult_age_midpoints !== nothing
        (gamma=gamma, beta=beta, r=r,
         stochastic_health=true, n_health_states=3, n_quad=n_quad,
         c_floor=c_floor, hazard_mult=hazard_mult,
         hazard_mult_by_age=hazard_mult_by_age,
         hazard_mult_age_midpoints=hazard_mult_age_midpoints)
    else
        (gamma=gamma, beta=beta, r=r,
         stochastic_health=true, n_health_states=3, n_quad=n_quad,
         c_floor=c_floor, hazard_mult=hazard_mult)
    end

    # Payout rates: real (Steps 0-5) and nominal (Step 6/7)
    p_fair = ModelParams(; gamma=gamma, beta=beta, r=r, mwr=1.0, grid_kw...)
    fair_pr = compute_payout_rate(p_fair, base_surv)

    # Nominal fair payout rate (higher initial payout, eroded by inflation)
    p_fair_nom = ModelParams(; gamma=gamma, beta=beta, r=r, mwr=1.0,
                              inflation_rate=inflation_val, grid_kw...)
    fair_pr_nom = inflation_val > 0 ? compute_payout_rate(p_fair_nom, base_surv) : fair_pr

    # Build grids using the LARGER payout rate to cover full A range
    grids = build_grids(p_fair, max(fair_pr, fair_pr_nom))

    # Filter population to agents with sufficient wealth
    pop = copy(population_full)
    if min_wealth > 0.0
        mask = pop[:, 1] .>= min_wealth
        pop = pop[mask, :]
    end
    n_pop = size(pop, 1)

    # Ensure health column exists (default to Fair=2)
    if size(pop, 2) < 4
        pop = hcat(pop, fill(2.0, n_pop))
    end

    steps = DecompositionStep[]

    if verbose
        println("=" ^ 70)
        println("  SEQUENTIAL DECOMPOSITION OF PREDICTED ANNUITY OWNERSHIP")
        println("=" ^ 70)
        if min_wealth > 0.0
            @printf("\n  Population: %d agents with W >= \$%s (of %d total)\n",
                n_pop, string(round(Int, min_wealth)), size(population_full, 1))
        end
        @printf("\n  %-50s  %8s  %8s  %s\n", "Model Specification", "Ownership", "Mean a", "Time")
        println("  " * "-" ^ 78)
    end

    prev_rate = 1.0  # Yaari benchmark
    step_num = 0

    # --- Step 0: True Yaari Benchmark (no SS) ---
    p0 = ModelParams(; common_kw...,
        theta=0.0, kappa=0.0, mwr=1.0, fixed_cost=0.0, inflation_rate=0.0,
        medical_enabled=false, health_mortality_corr=false,
        grid_kw...)
    if ss_enabled
        res0 = solve_and_evaluate(p0, grids, base_surv, ss_levels_zero,
            pop, fair_pr; step_name="$step_num. Yaari benchmark (no SS)", verbose=verbose)
    else
        res0 = solve_and_evaluate(p0, grids, base_surv, ss_zero,
            pop, fair_pr; step_name="$step_num. Yaari benchmark (SS on)", verbose=verbose)
    end
    push!(steps, DecompositionStep("Yaari benchmark", res0.ownership,
        res0.mean_alpha, res0.ownership - prev_rate, res0.solve_time))
    prev_rate = res0.ownership
    step_num += 1

    # --- Step 1: + Social Security pre-annuitization (only when ss_levels provided) ---
    if ss_enabled
        p_ss = ModelParams(; common_kw...,
            theta=0.0, kappa=0.0, mwr=1.0, fixed_cost=0.0, inflation_rate=0.0,
            medical_enabled=false, health_mortality_corr=false,
            grid_kw...)
        res_ss = solve_and_evaluate(p_ss, grids, base_surv, ss_levels,
            pop, fair_pr;
            step_name="$step_num. + Social Security pre-annuitization", verbose=verbose)
        push!(steps, DecompositionStep("+ Social Security",
            res_ss.ownership, res_ss.mean_alpha, res_ss.ownership - prev_rate, res_ss.solve_time))
        prev_rate = res_ss.ownership
        step_num += 1
    end

    # Current SS for remaining steps
    ss_arg = ss_enabled ? ss_levels : ss_zero

    # --- + Bequest motives ---
    p_beq = ModelParams(; common_kw...,
        theta=theta, kappa=kappa, mwr=1.0, fixed_cost=0.0, inflation_rate=0.0,
        medical_enabled=false, health_mortality_corr=false,
        grid_kw...)
    res_beq = solve_and_evaluate(p_beq, grids, base_surv, ss_arg,
        pop, fair_pr;
        step_name="$step_num. + Bequest motives", verbose=verbose)
    push!(steps, DecompositionStep("+ Bequest motives",
        res_beq.ownership, res_beq.mean_alpha, res_beq.ownership - prev_rate, res_beq.solve_time))
    prev_rate = res_beq.ownership
    step_num += 1

    # --- + Medical expenditure risk (uncorrelated) ---
    p_med = ModelParams(; common_kw...,
        theta=theta, kappa=kappa, mwr=1.0, fixed_cost=0.0, inflation_rate=0.0,
        medical_enabled=true, health_mortality_corr=false,
        grid_kw...)
    res_med = solve_and_evaluate(p_med, grids, base_surv, ss_arg,
        pop, fair_pr;
        step_name="$step_num. + Medical expenditure risk (uncorrelated)", verbose=verbose)
    push!(steps, DecompositionStep("+ Medical expenditure risk (uncorrelated)",
        res_med.ownership, res_med.mean_alpha, res_med.ownership - prev_rate, res_med.solve_time))
    prev_rate = res_med.ownership
    step_num += 1

    # --- + Health-mortality correlation (Reichling-Smetters) ---
    p_rs = ModelParams(; common_kw...,
        theta=theta, kappa=kappa, mwr=1.0, fixed_cost=0.0, inflation_rate=0.0,
        medical_enabled=true, health_mortality_corr=true,
        grid_kw...)
    res_rs = solve_and_evaluate(p_rs, grids, base_surv, ss_arg,
        pop, fair_pr;
        step_name="$step_num. + Health-mortality correlation (R-S)", verbose=verbose)
    push!(steps, DecompositionStep("+ Health-mortality correlation (R-S)",
        res_rs.ownership, res_rs.mean_alpha, res_rs.ownership - prev_rate, res_rs.solve_time))
    prev_rate = res_rs.ownership
    step_num += 1

    # --- + Survival pessimism (O'Dea & Sturrock 2023) ---
    p_pess = ModelParams(; common_kw...,
        theta=theta, kappa=kappa, mwr=1.0, fixed_cost=0.0, inflation_rate=0.0,
        medical_enabled=true, health_mortality_corr=true,
        survival_pessimism=survival_pessimism,
        grid_kw...)
    res_pess = solve_and_evaluate(p_pess, grids, base_surv, ss_arg,
        pop, fair_pr;
        step_name="$step_num. + Survival pessimism (psi=$(survival_pessimism))", verbose=verbose)
    push!(steps, DecompositionStep("+ Survival pessimism",
        res_pess.ownership, res_pess.mean_alpha, res_pess.ownership - prev_rate, res_pess.solve_time))
    prev_rate = res_pess.ownership
    step_num += 1

    # Track cumulative preference-channel overrides
    cur_health_utility = [1.0, 1.0, 1.0]
    cur_consumption_decline = 0.0

    # --- + State-dependent utility (FLN 2013, optional) ---
    health_utility_active = !all(x -> x == 1.0, health_utility_vals)
    if health_utility_active
        cur_health_utility = health_utility_vals
        p_hu = ModelParams(; common_kw...,
            theta=theta, kappa=kappa, mwr=1.0, fixed_cost=0.0, inflation_rate=0.0,
            medical_enabled=true, health_mortality_corr=true,
            survival_pessimism=survival_pessimism,
            health_utility=cur_health_utility,
            consumption_decline=cur_consumption_decline,
            grid_kw...)
        res_hu = solve_and_evaluate(p_hu, grids, base_surv, ss_arg,
            pop, fair_pr;
            step_name="$step_num. + State-dependent utility (FLN)", verbose=verbose)
        push!(steps, DecompositionStep("+ State-dependent utility",
            res_hu.ownership, res_hu.mean_alpha, res_hu.ownership - prev_rate, res_hu.solve_time))
        prev_rate = res_hu.ownership
        step_num += 1
    end

    # --- + Age-varying consumption needs (Aguiar-Hurst, optional) ---
    consumption_decline_active = consumption_decline_val > 0.0
    if consumption_decline_active
        cur_consumption_decline = consumption_decline_val
        p_cd = ModelParams(; common_kw...,
            theta=theta, kappa=kappa, mwr=1.0, fixed_cost=0.0, inflation_rate=0.0,
            medical_enabled=true, health_mortality_corr=true,
            survival_pessimism=survival_pessimism,
            health_utility=cur_health_utility,
            consumption_decline=cur_consumption_decline,
            grid_kw...)
        res_cd = solve_and_evaluate(p_cd, grids, base_surv, ss_arg,
            pop, fair_pr;
            step_name="$step_num. + Age-varying consumption needs (dc=$(consumption_decline_val))", verbose=verbose)
        push!(steps, DecompositionStep("+ Age-varying consumption needs",
            res_cd.ownership, res_cd.mean_alpha, res_cd.ownership - prev_rate, res_cd.solve_time))
        prev_rate = res_cd.ownership
        step_num += 1
    end

    # --- + Realistic pricing loads ---
    # Channel 8 stacks the three supply-side institutional frictions Pashchenko
    # (2013) identified: proportional load (1-MWR), fixed admin cost, and
    # minimum-purchase requirement. Setting min_purchase activates the
    # is_feasible_purchase filter in the alpha search — agents with
    # alpha*W_0 < min_purchase are forced to alpha=0.
    loaded_pr = mwr_loaded * fair_pr
    p_loads = ModelParams(; common_kw...,
        theta=theta, kappa=kappa, mwr=mwr_loaded, fixed_cost=fixed_cost_val,
        min_purchase=min_purchase_val,
        inflation_rate=0.0,
        medical_enabled=true, health_mortality_corr=true,
        survival_pessimism=survival_pessimism,
        health_utility=cur_health_utility,
        consumption_decline=cur_consumption_decline,
        grid_kw...)
    loads_label = min_purchase_val > 0 ?
        "$step_num. + Pricing frictions (MWR=$mwr_loaded, min \$$(Int(min_purchase_val/1000))K)" :
        "$step_num. + Realistic pricing loads (MWR=$mwr_loaded)"
    res_loads = solve_and_evaluate(p_loads, grids, base_surv, ss_arg,
        pop, loaded_pr;
        step_name=loads_label, verbose=verbose)
    push!(steps, DecompositionStep("+ Realistic pricing loads",
        res_loads.ownership, res_loads.mean_alpha, res_loads.ownership - prev_rate, res_loads.solve_time))
    prev_rate = res_loads.ownership
    step_num += 1

    # --- + Inflation erosion ---
    # Nominal annuity: insurer discounts at r_nom = r + pi, producing higher
    # initial payout whose real value then erodes via annuity_income_real().
    # SS income is COLA-protected (enters via ss_func, not A grid).
    loaded_pr_nom = mwr_loaded * fair_pr_nom
    p_infl = ModelParams(; common_kw...,
        theta=theta, kappa=kappa, mwr=mwr_loaded, fixed_cost=fixed_cost_val,
        min_purchase=min_purchase_val,
        inflation_rate=inflation_val,
        medical_enabled=true, health_mortality_corr=true,
        survival_pessimism=survival_pessimism,
        health_utility=cur_health_utility,
        consumption_decline=cur_consumption_decline,
        grid_kw...)
    res_infl = solve_and_evaluate(p_infl, grids, base_surv, ss_arg,
        pop, loaded_pr_nom;
        step_name="$step_num. + Inflation erosion ($(inflation_val*100)%)", verbose=verbose)
    push!(steps, DecompositionStep("+ Inflation erosion",
        res_infl.ownership, res_infl.mean_alpha, res_infl.ownership - prev_rate, res_infl.solve_time))
    prev_rate = res_infl.ownership
    step_num += 1

    # --- + Source-dependent utility (Force A; FPR companion, Blanchett-Finke 2024-25) ---
    # Effective consumption c_eff = c_income + lambda_w * c_portfolio.
    # When lambda_w < 1, portfolio drawdowns yield strictly less effective
    # consumption per dollar; converting portfolio wealth into income flow via
    # annuitization unlocks "license to spend." Mental accounting interpretation
    # (Shefrin-Thaler 1988; Thaler 1999).
    sdu_active = lambda_w_val < 1.0
    cur_lambda_w = sdu_active ? lambda_w_val : 1.0
    if sdu_active
        p_sdu = ModelParams(; common_kw...,
            theta=theta, kappa=kappa, mwr=mwr_loaded, fixed_cost=fixed_cost_val,
            min_purchase=min_purchase_val,
            inflation_rate=inflation_val,
            medical_enabled=true, health_mortality_corr=true,
            survival_pessimism=survival_pessimism,
            health_utility=cur_health_utility,
            consumption_decline=cur_consumption_decline,
            lambda_w=lambda_w_val,
            grid_kw...)
        res_sdu = solve_and_evaluate(p_sdu, grids, base_surv, ss_arg,
            pop, loaded_pr_nom;
            step_name="$step_num. + Source-dependent utility (lambda_w=$(lambda_w_val))",
            verbose=verbose)
        push!(steps, DecompositionStep("+ Source-dependent utility",
            res_sdu.ownership, res_sdu.mean_alpha, res_sdu.ownership - prev_rate, res_sdu.solve_time))
        prev_rate = res_sdu.ownership
        step_num += 1
    end

    # --- + Purchase disutility (Force B; narrow framing under loss aversion;
    #     Barberis-Huang 2009 narrow framing in finance; Tversky-Kahneman 1992
    #     loss aversion). The penalty is proportional to the underwater amount
    #     (premium minus cumulative payouts) at each period and vanishes at
    #     breakeven — the household experiences ongoing felt cost of the
    #     irreversible purchase until the payouts fully recoup the premium. ---
    psi_purchase_active = psi_purchase_val > 0.0
    if psi_purchase_active
        p_psi = ModelParams(; common_kw...,
            theta=theta, kappa=kappa, mwr=mwr_loaded, fixed_cost=fixed_cost_val,
            min_purchase=min_purchase_val,
            inflation_rate=inflation_val,
            medical_enabled=true, health_mortality_corr=true,
            survival_pessimism=survival_pessimism,
            health_utility=cur_health_utility,
            consumption_decline=cur_consumption_decline,
            lambda_w=cur_lambda_w,
            psi_purchase=psi_purchase_val,
            grid_kw...)
        res_psi = solve_and_evaluate(p_psi, grids, base_surv, ss_arg,
            pop, loaded_pr_nom;
            step_name="$step_num. + Purchase disutility (psi=$(psi_purchase_val))", verbose=verbose)
        push!(steps, DecompositionStep("+ Purchase disutility",
            res_psi.ownership, res_psi.mean_alpha, res_psi.ownership - prev_rate, res_psi.solve_time))
        prev_rate = res_psi.ownership
        step_num += 1
    end

    if verbose
        println("\n  " * "-" ^ 78)
        @printf("  %-50s  %6.1f%%\n",
            "Observed (HRS sample, single retirees 65-69)", 3.4)
    end

    return DecompositionResult(steps)
end

"""
Compute multiplicative interaction effects.

Solves each channel in ISOLATION (only that channel active, all others off)
and compares the sum of individual ownership drops to the combined drop.

When ss_levels is provided, SS is included as a channel and the baseline
has no SS. Otherwise SS stays on the A grid (backward compat).
"""
function run_multiplicative_analysis(
    base_surv::Vector{Float64},
    population_full::Matrix{Float64};
    gamma::Float64=3.0,
    beta::Float64=0.97,
    r::Float64=0.02,
    theta::Float64=2.0,
    kappa::Float64=10.0,
    c_floor::Float64=3000.0,
    mwr_loaded::Float64=0.82,
    fixed_cost_val::Float64=1000.0,
    inflation_val::Float64=0.03,
    n_wealth::Int=50,
    n_annuity::Int=15,
    n_alpha::Int=51,
    W_max::Float64=1_000_000.0,
    n_quad::Int=5,
    age_start::Int=65,
    age_end::Int=100,
    annuity_grid_power::Float64=2.0,
    hazard_mult::Vector{Float64}=[0.6, 1.0, 2.0],
    survival_pessimism::Float64=1.0,
    min_wealth::Float64=0.0,
    ss_levels::Vector{Float64}=Float64[],
    consumption_decline_val::Float64=0.0,
    health_utility_vals::Vector{Float64}=[1.0, 1.0, 1.0],
    verbose::Bool=true,
)
    ss_zero(age, p) = 0.0
    ss_enabled = !isempty(ss_levels)
    ss_levels_zero = [0.0, 0.0, 0.0, 0.0]

    grid_kw = (n_wealth=n_wealth, n_annuity=n_annuity, n_alpha=n_alpha,
               W_max=W_max, age_start=age_start, age_end=age_end,
               annuity_grid_power=annuity_grid_power)

    common_kw = (gamma=gamma, beta=beta, r=r,
                 stochastic_health=true, n_health_states=3, n_quad=n_quad,
                 c_floor=c_floor, hazard_mult=hazard_mult)

    p_fair = ModelParams(; gamma=gamma, beta=beta, r=r, mwr=1.0, grid_kw...)
    fair_pr = compute_payout_rate(p_fair, base_surv)

    # Nominal fair payout rate for inflation channel
    p_fair_nom = ModelParams(; gamma=gamma, beta=beta, r=r, mwr=1.0,
                              inflation_rate=inflation_val, grid_kw...)
    fair_pr_nom = inflation_val > 0 ? compute_payout_rate(p_fair_nom, base_surv) : fair_pr

    grids = build_grids(p_fair, max(fair_pr, fair_pr_nom))

    # Filter population to agents with sufficient wealth
    pop = copy(population_full)
    if min_wealth > 0.0
        mask = pop[:, 1] .>= min_wealth
        pop = pop[mask, :]
    end
    n_pop = size(pop, 1)

    if size(pop, 2) < 4
        pop = hcat(pop, fill(2.0, n_pop))
    end

    # Baseline: all channels off (including SS when ss_enabled)
    p_base = ModelParams(; common_kw...,
        theta=0.0, kappa=0.0, mwr=1.0, fixed_cost=0.0, inflation_rate=0.0,
        medical_enabled=false, health_mortality_corr=false,
        grid_kw...)
    if ss_enabled
        res_base = solve_and_evaluate(p_base, grids, base_surv, ss_levels_zero,
            pop, fair_pr; step_name="Baseline (Yaari, no SS)", verbose=verbose)
    else
        res_base = solve_and_evaluate(p_base, grids, base_surv, ss_zero,
            pop, fair_pr; step_name="Baseline (Yaari, SS on)", verbose=verbose)
    end
    baseline_rate = res_base.ownership

    channel_names = String[]
    individual_drops = Float64[]

    if verbose
        println("\n  MULTIPLICATIVE INTERACTION ANALYSIS")
        println("  " * "-" ^ 60)
        @printf("  %-40s  %8s  %8s\n", "Channel (isolated)", "Ownership", "Drop")
        println("  " * "-" ^ 60)
        base_label = ss_enabled ? "Baseline (Yaari, no SS)" : "Baseline (Yaari, SS on)"
        @printf("  %-40s  %7.1f%%\n", base_label, baseline_rate * 100)
    end

    # Helper: evaluate a channel in isolation
    # When ss_enabled, isolated channels (other than SS) use no SS
    ss_arg_off = ss_enabled ? ss_levels_zero : ss_zero

    function _eval_channel(name, p_ch, pr, ss_arg_ch)
        if ss_enabled
            res = solve_and_evaluate(p_ch, grids, base_surv, ss_arg_ch,
                pop, pr; step_name=name, verbose=false)
        else
            res = solve_and_evaluate(p_ch, grids, base_surv, ss_zero,
                pop, pr; step_name=name, verbose=false)
        end
        push!(channel_names, name)
        push!(individual_drops, baseline_rate - res.ownership)
        if verbose
            @printf("  %-40s  %7.1f%%  %7.1f pp\n",
                name, res.ownership * 100, (baseline_rate - res.ownership) * 100)
        end
    end

    # SS channel (only when ss_levels provided)
    if ss_enabled
        p_ss = ModelParams(; common_kw...,
            theta=0.0, kappa=0.0, mwr=1.0, fixed_cost=0.0, inflation_rate=0.0,
            medical_enabled=false, health_mortality_corr=false,
            grid_kw...)
        _eval_channel("SS pre-annuitization", p_ss, fair_pr, ss_levels)
    end

    # Bequests only
    p_beq = ModelParams(; common_kw...,
        theta=theta, kappa=kappa, mwr=1.0, fixed_cost=0.0, inflation_rate=0.0,
        medical_enabled=false, health_mortality_corr=false,
        grid_kw...)
    _eval_channel("Bequest motives", p_beq, fair_pr, ss_arg_off)

    # R-S (medical + correlation) only
    p_rs = ModelParams(; common_kw...,
        theta=0.0, kappa=0.0, mwr=1.0, fixed_cost=0.0, inflation_rate=0.0,
        medical_enabled=true, health_mortality_corr=true,
        grid_kw...)
    _eval_channel("Health-mortality correlation (R-S)", p_rs, fair_pr, ss_arg_off)

    # Survival pessimism only
    if survival_pessimism < 1.0
        p_pess = ModelParams(; common_kw...,
            theta=0.0, kappa=0.0, mwr=1.0, fixed_cost=0.0, inflation_rate=0.0,
            medical_enabled=false, health_mortality_corr=false,
            survival_pessimism=survival_pessimism,
            grid_kw...)
        _eval_channel("Survival pessimism", p_pess, fair_pr, ss_arg_off)
    end

    # State-dependent utility only (when active)
    if !all(x -> x == 1.0, health_utility_vals)
        p_hu = ModelParams(; common_kw...,
            theta=0.0, kappa=0.0, mwr=1.0, fixed_cost=0.0, inflation_rate=0.0,
            medical_enabled=false, health_mortality_corr=false,
            health_utility=health_utility_vals,
            grid_kw...)
        _eval_channel("State-dependent utility", p_hu, fair_pr, ss_arg_off)
    end

    # Age-varying consumption needs only (when active)
    if consumption_decline_val > 0.0
        p_cd = ModelParams(; common_kw...,
            theta=0.0, kappa=0.0, mwr=1.0, fixed_cost=0.0, inflation_rate=0.0,
            medical_enabled=false, health_mortality_corr=false,
            consumption_decline=consumption_decline_val,
            grid_kw...)
        _eval_channel("Age-varying consumption needs", p_cd, fair_pr, ss_arg_off)
    end

    # Pricing loads only
    loaded_pr = mwr_loaded * fair_pr
    p_load = ModelParams(; common_kw...,
        theta=0.0, kappa=0.0, mwr=mwr_loaded, fixed_cost=fixed_cost_val,
        inflation_rate=0.0,
        medical_enabled=false, health_mortality_corr=false,
        grid_kw...)
    _eval_channel("Pricing loads", p_load, loaded_pr, ss_arg_off)

    # Inflation only (use nominal payout rate)
    p_infl_ch = ModelParams(; common_kw...,
        theta=0.0, kappa=0.0, mwr=1.0, fixed_cost=0.0,
        inflation_rate=inflation_val,
        medical_enabled=false, health_mortality_corr=false,
        grid_kw...)
    _eval_channel("Inflation erosion", p_infl_ch, fair_pr_nom, ss_arg_off)

    sum_of_individual = sum(individual_drops)

    # Full model with all channels
    loaded_pr_nom = mwr_loaded * fair_pr_nom
    ss_arg_full = ss_enabled ? ss_levels : ss_zero
    p_full = ModelParams(; common_kw...,
        theta=theta, kappa=kappa, mwr=mwr_loaded, fixed_cost=fixed_cost_val,
        inflation_rate=inflation_val,
        medical_enabled=true, health_mortality_corr=true,
        survival_pessimism=survival_pessimism,
        health_utility=health_utility_vals,
        consumption_decline=consumption_decline_val,
        grid_kw...)
    if ss_enabled
        res_full = solve_and_evaluate(p_full, grids, base_surv, ss_levels,
            pop, loaded_pr_nom; step_name="All channels combined", verbose=false)
    else
        res_full = solve_and_evaluate(p_full, grids, base_surv, ss_zero,
            pop, loaded_pr_nom; step_name="All channels combined", verbose=false)
    end
    combined_drop = baseline_rate - res_full.ownership

    if verbose
        println("  " * "-" ^ 60)
        @printf("  %-40s  %7.1f pp\n", "Sum of individual drops",
            sum_of_individual * 100)
        @printf("  %-40s  %7.1f pp\n", "Combined drop (all channels)",
            combined_drop * 100)
        @printf("  %-40s  %7.2fx\n", "Multiplicative ratio",
            combined_drop / max(sum_of_individual, 1e-6))
        println("\n  Channels interact multiplicatively when ratio > 1.0.")
    end

    return (
        channel_names=channel_names,
        individual_drops=individual_drops,
        sum_of_individual=sum_of_individual,
        combined_drop=combined_drop,
        combined_ownership=res_full.ownership,
        baseline_ownership=baseline_rate,
        ratio=combined_drop / max(sum_of_individual, 1e-6),
    )
end


"""
Compute all pairwise channel interactions.

For each pair of channels (A, B), computes:
  - ownership with A alone
  - ownership with B alone
  - ownership with A+B together
  - additive prediction = baseline - drop_A - drop_B
  - interaction = ownership_AB - additive_prediction

When ss_levels is provided, SS is included as a channel. Returns a NamedTuple
with the interaction matrix and channel labels.
"""
function run_pairwise_interactions(
    base_surv::Vector{Float64},
    population_full::Matrix{Float64};
    gamma::Float64=3.0,
    beta::Float64=0.97,
    r::Float64=0.02,
    theta::Float64=2.0,
    kappa::Float64=10.0,
    c_floor::Float64=3000.0,
    mwr_loaded::Float64=0.82,
    fixed_cost_val::Float64=1000.0,
    inflation_val::Float64=0.03,
    n_wealth::Int=50,
    n_annuity::Int=15,
    n_alpha::Int=51,
    W_max::Float64=1_000_000.0,
    n_quad::Int=5,
    age_start::Int=65,
    age_end::Int=100,
    annuity_grid_power::Float64=2.0,
    hazard_mult::Vector{Float64}=[0.6, 1.0, 2.0],
    survival_pessimism::Float64=1.0,
    min_wealth::Float64=0.0,
    ss_levels::Vector{Float64}=Float64[],
    consumption_decline_val::Float64=0.0,
    health_utility_vals::Vector{Float64}=[1.0, 1.0, 1.0],
    verbose::Bool=true,
)
    ss_zero(age, p) = 0.0
    ss_enabled = !isempty(ss_levels)
    ss_levels_zero = [0.0, 0.0, 0.0, 0.0]

    grid_kw = (n_wealth=n_wealth, n_annuity=n_annuity, n_alpha=n_alpha,
               W_max=W_max, age_start=age_start, age_end=age_end,
               annuity_grid_power=annuity_grid_power)

    common_kw = (gamma=gamma, beta=beta, r=r,
                 stochastic_health=true, n_health_states=3, n_quad=n_quad,
                 c_floor=c_floor, hazard_mult=hazard_mult)

    p_fair = ModelParams(; gamma=gamma, beta=beta, r=r, mwr=1.0, grid_kw...)
    fair_pr = compute_payout_rate(p_fair, base_surv)

    p_fair_nom = ModelParams(; gamma=gamma, beta=beta, r=r, mwr=1.0,
                              inflation_rate=inflation_val, grid_kw...)
    fair_pr_nom = inflation_val > 0 ? compute_payout_rate(p_fair_nom, base_surv) : fair_pr

    grids = build_grids(p_fair, max(fair_pr, fair_pr_nom))

    pop = copy(population_full)
    if min_wealth > 0.0
        mask = pop[:, 1] .>= min_wealth
        pop = pop[mask, :]
    end
    if size(pop, 2) < 4
        pop = hcat(pop, fill(2.0, size(pop, 1)))
    end

    loaded_pr = mwr_loaded * fair_pr
    loaded_pr_nom = mwr_loaded * fair_pr_nom

    # Channel definitions: (name, param_overrides, payout_rate, ss_on)
    # ss_on=true means this channel uses real SS levels; false means no SS.
    # All overrides include survival_pessimism=1.0 for uniform NamedTuple type.
    channel_specs = Tuple{String, NamedTuple, Float64, Bool}[]

    # SS channel (when ss_levels provided)
    if ss_enabled
        push!(channel_specs,
            ("SS",
             (theta=0.0, kappa=0.0, mwr=1.0, fixed_cost=0.0, inflation_rate=0.0,
              medical_enabled=false, health_mortality_corr=false, survival_pessimism=1.0),
             fair_pr, true))
    end

    push!(channel_specs,
        ("Bequests",
         (theta=theta, kappa=kappa, mwr=1.0, fixed_cost=0.0, inflation_rate=0.0,
          medical_enabled=false, health_mortality_corr=false, survival_pessimism=1.0),
         fair_pr, false))
    push!(channel_specs,
        ("Medical+R-S",
         (theta=0.0, kappa=0.0, mwr=1.0, fixed_cost=0.0, inflation_rate=0.0,
          medical_enabled=true, health_mortality_corr=true, survival_pessimism=1.0),
         fair_pr, false))
    push!(channel_specs,
        ("Loads",
         (theta=0.0, kappa=0.0, mwr=mwr_loaded, fixed_cost=fixed_cost_val,
          inflation_rate=0.0, medical_enabled=false, health_mortality_corr=false,
          survival_pessimism=1.0),
         loaded_pr, false))
    push!(channel_specs,
        ("Inflation",
         (theta=0.0, kappa=0.0, mwr=1.0, fixed_cost=0.0,
          inflation_rate=inflation_val, medical_enabled=false,
          health_mortality_corr=false, survival_pessimism=1.0),
         fair_pr_nom, false))

    if survival_pessimism < 1.0
        push!(channel_specs,
            ("Pessimism",
             (theta=0.0, kappa=0.0, mwr=1.0, fixed_cost=0.0, inflation_rate=0.0,
              medical_enabled=false, health_mortality_corr=false,
              survival_pessimism=survival_pessimism),
             fair_pr, false))
    end

    if !all(x -> x == 1.0, health_utility_vals)
        push!(channel_specs,
            ("HealthUtil",
             (theta=0.0, kappa=0.0, mwr=1.0, fixed_cost=0.0, inflation_rate=0.0,
              medical_enabled=false, health_mortality_corr=false,
              survival_pessimism=1.0, health_utility=health_utility_vals,
              consumption_decline=0.0),
             fair_pr, false))
    end

    if consumption_decline_val > 0.0
        push!(channel_specs,
            ("AgeNeeds",
             (theta=0.0, kappa=0.0, mwr=1.0, fixed_cost=0.0, inflation_rate=0.0,
              medical_enabled=false, health_mortality_corr=false,
              survival_pessimism=1.0, health_utility=[1.0, 1.0, 1.0],
              consumption_decline=consumption_decline_val),
             fair_pr, false))
    end

    n_ch = length(channel_specs)
    channel_names = [c[1] for c in channel_specs]

    # Helper to evaluate with appropriate SS arg
    function _pw_eval(p_ch, pr, use_ss; label="")
        if ss_enabled
            ss_arg = use_ss ? ss_levels : ss_levels_zero
            return solve_and_evaluate(p_ch, grids, base_surv, ss_arg,
                pop, pr; step_name=label, verbose=false)
        else
            return solve_and_evaluate(p_ch, grids, base_surv, ss_zero,
                pop, pr; step_name=label, verbose=false)
        end
    end

    # Baseline: all channels off
    p_base = ModelParams(; common_kw...,
        theta=0.0, kappa=0.0, mwr=1.0, fixed_cost=0.0, inflation_rate=0.0,
        medical_enabled=false, health_mortality_corr=false,
        grid_kw...)
    res_base = _pw_eval(p_base, fair_pr, false; label="Baseline")
    base_own = res_base.ownership

    # Solve each channel in isolation
    iso_own = zeros(n_ch)
    for (i, (name, overrides, pr, ss_on)) in enumerate(channel_specs)
        p_i = ModelParams(; common_kw..., overrides..., grid_kw...)
        res_i = _pw_eval(p_i, pr, ss_on; label=name)
        iso_own[i] = res_i.ownership
    end

    # Pairwise combinations (parallel when workers available)
    interaction_matrix = fill(NaN, n_ch, n_ch)
    pair_ownership = fill(NaN, n_ch, n_ch)

    # Build list of all (i,j) pairs
    pair_indices = Tuple{Int,Int}[]
    for i in 1:n_ch
        for j in (i+1):n_ch
            push!(pair_indices, (i, j))
        end
    end

    # Capture for closure serialization
    _cs = channel_specs
    _ckw = common_kw
    _gkw = grid_kw
    _lpr = loaded_pr
    _lprn = loaded_pr_nom
    _fpr = fair_pr
    _fprn = fair_pr_nom
    _bs_pw = base_surv
    _pop_pw = pop
    _ssl = ss_enabled ? ss_levels : Float64[]
    _sslz = ss_levels_zero
    _mw = min_wealth

    pair_results = parallel_solve(pair_indices) do (i, j)
        ov_i = _cs[i][2]
        ov_j = _cs[j][2]
        ss_on_i = _cs[i][4]
        ss_on_j = _cs[j][4]
        pair_ss_on = ss_on_i || ss_on_j

        merged = Dict{Symbol,Any}()
        for (k, v) in Base.pairs(ov_i)
            merged[k] = v
        end
        for (k, v) in Base.pairs(ov_j)
            if k == :theta && v > 0
                merged[:theta] = v
            elseif k == :kappa && v > 0
                merged[:kappa] = v
            elseif k == :mwr && v < 1.0
                merged[:mwr] = v
            elseif k == :fixed_cost && v > 0
                merged[:fixed_cost] = v
            elseif k == :inflation_rate && v > 0
                merged[:inflation_rate] = v
            elseif k == :medical_enabled && v == true
                merged[:medical_enabled] = true
            elseif k == :health_mortality_corr && v == true
                merged[:health_mortality_corr] = true
            elseif k == :survival_pessimism && v < 1.0
                merged[:survival_pessimism] = v
            elseif k == :health_utility && v != [1.0, 1.0, 1.0]
                merged[:health_utility] = v
            elseif k == :consumption_decline && v > 0
                merged[:consumption_decline] = v
            end
        end

        has_loads = get(merged, :mwr, 1.0) < 1.0
        has_infl = get(merged, :inflation_rate, 0.0) > 0
        pr_pair = if has_loads && has_infl
            _lprn
        elseif has_loads
            _lpr
        elseif has_infl
            _fprn
        else
            _fpr
        end

        p_pair = ModelParams(; _ckw..., merged..., _gkw...)

        # Inline evaluation (same logic as _pw_eval)
        ss_arg = pair_ss_on ? _ssl : _sslz
        local_pop = copy(_pop_pw)
        if _mw > 0.0
            mask = local_pop[:, 1] .>= _mw
            local_pop = local_pop[mask, :]
        end
        if size(local_pop, 2) < 4
            local_pop = hcat(local_pop, fill(2.0, size(local_pop, 1)))
        end

        if !isempty(ss_arg) && !all(x -> x == ss_arg[1], ss_arg)
            # Per-quartile SS
            tot_own = 0.0; tot_n = 0.0
            for q in 1:4
                sv = ss_arg[q]
                sf = (age, p) -> sv
                sol = solve_lifecycle_health(p_pair, build_grids(ModelParams(; _ckw..., _gkw..., mwr=1.0), max(_fpr, _fprn)), _bs_pw, sf)
                pq = _filter_quartile(local_pop, q, SS_QUARTILE_BREAKS)
                nq = size(pq, 1)
                nq == 0 && continue
                rq = compute_ownership_rate_health(sol, pq, pr_pair; base_surv=_bs_pw)
                tot_own += rq.ownership_rate * nq
                tot_n += nq
            end
            own = tot_n > 0 ? tot_own / tot_n : 0.0
        else
            sv = isempty(ss_arg) ? 0.0 : ss_arg[1]
            sf = (age, p) -> sv
            sol = solve_lifecycle_health(p_pair, build_grids(ModelParams(; _ckw..., _gkw..., mwr=1.0), max(_fpr, _fprn)), _bs_pw, sf)
            r = compute_ownership_rate_health(sol, local_pop, pr_pair; base_surv=_bs_pw)
            own = r.ownership_rate
        end

        (i=i, j=j, ownership=own)
    end

    for r in pair_results
        i, j = r.i, r.j
        pair_ownership[i, j] = r.ownership
        pair_ownership[j, i] = r.ownership

        drop_i = base_own - iso_own[i]
        drop_j = base_own - iso_own[j]
        additive_pred = base_own - drop_i - drop_j
        interaction_matrix[i, j] = r.ownership - additive_pred
        interaction_matrix[j, i] = interaction_matrix[i, j]
    end
    for i in 1:n_ch
        interaction_matrix[i, i] = 0.0
        pair_ownership[i, i] = iso_own[i]
    end

    if verbose
        println("\n  PAIRWISE CHANNEL INTERACTIONS")
        println("  " * "-" ^ 70)
        @printf("  %-15s", "")
        for name in channel_names
            @printf("  %12s", name)
        end
        println()
        println("  " * "-" ^ (15 + 14 * n_ch))
        for i in 1:n_ch
            @printf("  %-15s", channel_names[i])
            for j in 1:n_ch
                if i == j
                    @printf("  %12s", "---")
                elseif j > i
                    @printf("  %+11.1f pp", interaction_matrix[i, j] * 100)
                else
                    @printf("  %12s", "")
                end
            end
            println()
        end
        println("\n  Negative = channels reinforce (super-additive demand reduction)")
    end

    return (
        channel_names=channel_names,
        baseline_ownership=base_own,
        isolated_ownership=iso_own,
        pair_ownership=pair_ownership,
        interaction_matrix=interaction_matrix,
    )
end

#=============================================================================
# ORIGINAL FILE: scripts/run_decomposition.jl
#=============================================================================

# Phase 4: Sequential Decomposition of Predicted Annuity Ownership
#
# Generates Table 1 (the core result):
#   Starting from Yaari's 100% benchmark, add channels one at a time
#   and measure how each reduces predicted ownership.
# Also computes multiplicative interaction analysis.
#
# Parameters loaded from scripts/config.jl (gamma=2.5, hazard_mult=[0.50,1.0,3.0])

using Printf
using DelimitedFiles
using Distributed

if nworkers() > 1
    @everywhere include(joinpath(@__DIR__, "..", "src", "AnnuityPuzzle.jl"))
    @everywhere using .AnnuityPuzzle
else
    include(joinpath(@__DIR__, "..", "src", "AnnuityPuzzle.jl"))
    using .AnnuityPuzzle
end

include(joinpath(@__DIR__, "config.jl"))

println("=" ^ 70)
println("  PHASE 4: FULL MODEL AND DECOMPOSITION")
println("  Sequential Channel Analysis — Table 1")
println("=" ^ 70)

# ===================================================================
# Load HRS population sample
# ===================================================================
println("\nLoading HRS population sample...")
hrs_path = HRS_PATH
hrs_raw = readdlm(hrs_path, ',', Any; skipstart=1)
n_pop = size(hrs_raw, 1)
# Columns: wealth, purchased annuity income (zero at entry; SS enters via ss_func), age.
# SS income enters through ss_func in the Bellman equation (COLA-protected),
# not through the A grid.
population = zeros(n_pop, 4)
population[:, 1] = Float64.(hrs_raw[:, 1])  # wealth
population[:, 2] .= 0.0                      # A grid = purchased annuity only (SS via ss_func)
population[:, 3] = Float64.(hrs_raw[:, 3])  # age
if size(hrs_raw, 2) >= 4
    population[:, 4] = Float64.(hrs_raw[:, 4])  # observed health (1=Good, 2=Fair, 3=Poor)
else
    population[:, 4] .= 2.0  # default Fair if health not in CSV
end
n_eligible = count(population[:, 1] .>= MIN_WEALTH)
@printf("  Loaded %d individuals. Median wealth: \$%s\n",
    n_pop,
    string(round(Int, sort(population[:, 1])[div(n_pop, 2)])))
@printf("  Eligible (W >= \$%s): %d of %d (%.1f%%)\n",
    string(round(Int, MIN_WEALTH)), n_eligible, n_pop, n_eligible / n_pop * 100)

# ===================================================================
# Build survival probabilities
# ===================================================================
p_base = ModelParams(age_start=AGE_START, age_end=AGE_END)
base_surv = build_lockwood_survival(p_base)

# Fair payout rate for bequest calibration
p_fair = ModelParams(age_start=AGE_START, age_end=AGE_END, mwr=1.0, r=R_RATE)
fair_pr = compute_payout_rate(p_fair, base_surv)
@printf("\n  Fair payout rate (MWR=1.0): %.4f (%.1f%% per year)\n",
    fair_pr, fair_pr * 100)

# ===================================================================
# Bequest parameters: DFJ luxury good specification (Lockwood BAP_sim2.m)
# Use Lockwood's original theta at all gamma values. The DFJ theta was
# estimated at sigma=2, but simulation-based checks show <14% divergence
# in bequest-to-wealth ratio across gamma in [1.5, 5.0], below the
# threshold warranting recalibration.
# ===================================================================
@printf("  DFJ bequest theta: %.2f (Lockwood BAP_sim2.m, used at all gamma)\n", THETA_DFJ)
@printf("  DFJ bequest kappa: \$%s (De Nardi 2004 luxury good)\n",
    string(round(Int, KAPPA_DFJ)))
@printf("  Hazard multipliers: [%.2f, %.1f, %.1f]\n",
    HAZARD_MULT[1], HAZARD_MULT[2], HAZARD_MULT[3])
println("    (HRS SRH: [0.57,1.0,2.70]; R-S functional: [0.45,1.0,3.5])")

# ===================================================================
# Run Sequential Decomposition
# ===================================================================
# SS enters through ss_func in the Bellman equation (COLA-protected).
# Step 0 is a true Yaari benchmark (no SS). Step 1 adds SS as a channel.
const SS_LEVELS = SS_QUARTILE_LEVELS  # [14K, 17K, 20K, 25K] by wealth quartile

println()
decomp = run_decomposition(
    base_surv, population;
    gamma=GAMMA, beta=BETA, r=R_RATE,
    theta=THETA_DFJ, kappa=KAPPA_DFJ,
    c_floor=C_FLOOR,
    mwr_loaded=MWR_LOADED,
    fixed_cost_val=FIXED_COST,
    min_purchase_val=MIN_PURCHASE,
    inflation_val=INFLATION,
    n_wealth=N_WEALTH, n_annuity=N_ANNUITY, n_alpha=N_ALPHA,
    W_max=W_MAX, n_quad=N_QUAD,
    age_start=AGE_START, age_end=AGE_END,
    annuity_grid_power=A_GRID_POW,
    hazard_mult=HAZARD_MULT,
    survival_pessimism=SURVIVAL_PESSIMISM,
    min_wealth=MIN_WEALTH,
    ss_levels=SS_LEVELS,
    consumption_decline_val=CONSUMPTION_DECLINE,
    health_utility_vals=Float64.(HEALTH_UTILITY),
    psi_purchase_val=PSI_PURCHASE,
    lambda_w_val=LAMBDA_W,
    verbose=true,
)

# ===================================================================
# Multiplicative Interaction Analysis (diagnostic-only, skipped by default
# because the same information is in pairwise_interactions.csv from this
# script's later section + the Shapley decomposition. ~9 solves * 280s each.)
# ===================================================================
const RUN_MULTIPLICATIVE = get(ENV, "ANNUITY_RUN_MULTIPLICATIVE", "0") == "1"
if RUN_MULTIPLICATIVE
    println("\n" * "=" ^ 70)
    mult = run_multiplicative_analysis(
        base_surv, population;
        gamma=GAMMA, beta=BETA, r=R_RATE,
        theta=THETA_DFJ, kappa=KAPPA_DFJ,
        c_floor=C_FLOOR,
        mwr_loaded=MWR_LOADED,
        fixed_cost_val=FIXED_COST,
        inflation_val=INFLATION,
        n_wealth=N_WEALTH, n_annuity=N_ANNUITY, n_alpha=N_ALPHA,
        W_max=W_MAX, n_quad=N_QUAD,
        age_start=AGE_START, age_end=AGE_END,
        annuity_grid_power=A_GRID_POW,
        hazard_mult=HAZARD_MULT,
        survival_pessimism=SURVIVAL_PESSIMISM,
        min_wealth=MIN_WEALTH,
        ss_levels=SS_LEVELS,
        verbose=true,
    )
else
    println("\nSkipping multiplicative interaction analysis (set ANNUITY_RUN_MULTIPLICATIVE=1 to enable).")
end

# ===================================================================
# Retention-Rate Decomposition (geometric compounding metric)
# ===================================================================
println("\n" * "=" ^ 70)
println("  RETENTION-RATE DECOMPOSITION")
println("  Each channel acts as a multiplicative filter on ownership")
println("=" ^ 70)

rates = [s.ownership_rate for s in decomp.steps]
@printf("\n  %-50s  %8s  %10s\n", "Channel", "Ownership", "Retention")
println("  " * "-" ^ 70)
@printf("  %-50s  %7.1f%%\n", decomp.steps[1].name, rates[1] * 100)

let cum_retention = 1.0
    for i in 2:length(rates)
        retention = rates[i] / max(rates[i-1], 1e-10)
        cum_retention *= retention
        @printf("  %-50s  %7.1f%%  %8.1f%%\n",
            decomp.steps[i].name, rates[i] * 100, retention * 100)
    end
    println("  " * "-" ^ 70)
    @printf("  Cumulative retention product: %.4f\n", cum_retention)
    @printf("  Predicted via geometric compounding: %.1f%%\n",
        rates[1] * cum_retention * 100)
end

# ===================================================================
# Robustness sweep + full-sample comparison (diagnostic-only, skipped by default
# because Stage 12 (run_robustness.jl) writes a comparable CSV with parallel
# execution. The internal sweep here is single-threaded and would take ~9 hours
# at MWR=0.87. Set ANNUITY_RUN_DIAG_ROBUSTNESS=1 to re-enable.)
# ===================================================================
const RUN_DIAG_ROBUSTNESS = get(ENV, "ANNUITY_RUN_DIAG_ROBUSTNESS", "0") == "1"
if RUN_DIAG_ROBUSTNESS
    println("\n" * "=" ^ 70)
    println("  ROBUSTNESS: SENSITIVITY TO KEY PARAMETERS")
    println("=" ^ 70)

    robustness_configs = [
        ("gamma=1.5",      (gamma=1.5,)),
        ("gamma=2.0",      (gamma=2.0,)),
        ("gamma=2.2",      (gamma=2.2,)),
        ("gamma=2.4",      (gamma=2.4,)),
        ("gamma=2.6",      (gamma=2.6,)),
        ("gamma=2.8",      (gamma=2.8,)),
        ("gamma=3.0",      (gamma=3.0,)),
        ("gamma=4.0",      (gamma=4.0,)),
        ("beta=0.95",      (beta=0.95,)),
        ("beta=0.99",      (beta=0.99,)),
        ("MWR=0.85",       (mwr_loaded=0.85,)),
        ("MWR=0.90",       (mwr_loaded=0.90,)),
        ("inflation=1%",   (inflation_val=0.01,)),
        ("inflation=3%",   (inflation_val=0.03,)),
    ]

    @printf("\n  %-20s  %10s\n", "Configuration", "Final Ownership")
    println("  " * "-" ^ 34)

    for (label, overrides) in robustness_configs
        kw = Dict{Symbol,Any}(
            :gamma => GAMMA, :beta => BETA, :r => R_RATE,
            :theta => THETA_DFJ, :kappa => KAPPA_DFJ,
            :c_floor => C_FLOOR,
            :mwr_loaded => MWR_LOADED,
            :fixed_cost_val => FIXED_COST,
            :inflation_val => INFLATION,
            :n_wealth => N_WEALTH, :n_annuity => N_ANNUITY, :n_alpha => N_ALPHA,
            :W_max => W_MAX, :n_quad => N_QUAD,
            :age_start => AGE_START, :age_end => AGE_END,
            :annuity_grid_power => A_GRID_POW,
            :hazard_mult => HAZARD_MULT,
            :survival_pessimism => SURVIVAL_PESSIMISM,
            :min_wealth => MIN_WEALTH,
            :ss_levels => SS_LEVELS,
            :verbose => false,
        )
        for (k, v) in pairs(overrides)
            kw[k] = v
        end

        result = run_decomposition(base_surv, population; kw...)
        final_rate = result.steps[end].ownership_rate
        @printf("  %-20s  %9.1f%%\n", label, final_rate * 100)
    end

    # Full-sample comparison
    println("\n" * "=" ^ 70)
    println("  FULL-SAMPLE COMPARISON (all agents, no wealth filter)")
    println("=" ^ 70)

    full_sample = run_decomposition(
        base_surv, population;
        gamma=GAMMA, beta=BETA, r=R_RATE,
        theta=THETA_DFJ, kappa=KAPPA_DFJ,
        c_floor=C_FLOOR,
        mwr_loaded=MWR_LOADED,
        fixed_cost_val=FIXED_COST,
        inflation_val=INFLATION,
        n_wealth=N_WEALTH, n_annuity=N_ANNUITY, n_alpha=N_ALPHA,
        W_max=W_MAX, n_quad=N_QUAD,
        age_start=AGE_START, age_end=AGE_END,
        annuity_grid_power=A_GRID_POW,
        hazard_mult=HAZARD_MULT,
        survival_pessimism=SURVIVAL_PESSIMISM,
        min_wealth=0.0,
        ss_levels=SS_LEVELS,
        verbose=false,
    )
    full_rate = full_sample.steps[end].ownership_rate
    @printf("\n  Full model (all %d agents, min_wealth=0):  %6.1f%%\n", n_pop, full_rate * 100)
    @printf("  Lockwood (2012) observed:                    %6.1f%%\n", 3.6)
else
    println("\nSkipping diagnostic robustness sweep + full-sample comparison.")
    println("(Stage 12 run_robustness.jl produces a parallel-executed CSV with the same data.)")
end

# ===================================================================
# Save decomposition results to CSV
# ===================================================================
tables_dir = joinpath(@__DIR__, "..", "tables")
mkpath(joinpath(tables_dir, "csv"))
mkpath(joinpath(tables_dir, "tex"))

csv_path = joinpath(tables_dir, "csv", "decomposition.csv")
open(csv_path, "w") do f
    println(f, "step,ownership_pct,mean_alpha,delta_pp,solve_time_s")
    for step in decomp.steps
        @printf(f, "%s,%.2f,%.4f,%.2f,%.1f\n",
            step.name, step.ownership_rate * 100,
            step.mean_alpha, step.delta * 100, step.solve_time)
    end
end
println("\n  Decomposition CSV saved: $csv_path")

# Retention rate table (Table 1 in manuscript)
ds = '\$'
tex_path = joinpath(tables_dir, "tex", "retention_rates.tex")
open(tex_path, "w") do f
    println(f, raw"\begin{table}[htbp]")
    println(f, raw"\centering")
    println(f, raw"\caption{Sequential Decomposition of Predicted Voluntary Annuity Ownership}")
    println(f, raw"\label{tab:retention}")
    println(f, raw"\begin{tabular}{lcccc}")
    println(f, raw"\toprule")
    println(f, "Channel & Ownership (\\%) & $(ds)\\Delta$(ds) (pp) & Retention & Cumulative \\\\")
    println(f, raw"\midrule")

    cum_retention = 1.0
    for (i, step) in enumerate(decomp.steps)
        own = step.ownership_rate * 100
        if i == 1
            @printf(f, "%s & %.1f & --- & --- & --- \\\\\n", step.name, own)
        else
            prev_own = decomp.steps[i-1].ownership_rate * 100
            delta = own - prev_own
            retention = prev_own > 0 ? own / prev_own : 0.0
            cum_retention *= retention
            @printf(f, "%s & %.1f & %+.1f & %.1f\\%% & %.4f \\\\\n",
                step.name, own, delta, retention * 100, cum_retention)
        end
    end

    println(f, raw"\midrule")
    println(f, "Observed (Lockwood 2012) & 3.6 & --- & --- & --- \\\\")
    println(f, raw"\bottomrule")
    println(f, raw"\end{tabular}")
    println(f, raw"\begin{tablenotes}")
    println(f, raw"\small")
    println(f, raw"\item Retention rate = ownership after channel / ownership before channel.")
    println(f, "Cumulative product of retention rates tracks geometric compounding.")
    println(f, raw"\end{tablenotes}")
    println(f, raw"\end{table}")
end
println("  Retention rates TeX saved: $tex_path")

# ===================================================================
# Pairwise Channel Interactions
# ===================================================================
println("\n" * "=" ^ 70)
println("  PAIRWISE CHANNEL INTERACTIONS")
println("=" ^ 70)

pw = run_pairwise_interactions(
    base_surv, population;
    gamma=GAMMA, beta=BETA, r=R_RATE,
    theta=THETA_DFJ, kappa=KAPPA_DFJ,
    c_floor=C_FLOOR,
    mwr_loaded=MWR_LOADED,
    fixed_cost_val=FIXED_COST,
    inflation_val=INFLATION,
    n_wealth=N_WEALTH, n_annuity=N_ANNUITY, n_alpha=N_ALPHA,
    W_max=W_MAX, n_quad=N_QUAD,
    age_start=AGE_START, age_end=AGE_END,
    annuity_grid_power=A_GRID_POW,
    hazard_mult=HAZARD_MULT,
    survival_pessimism=SURVIVAL_PESSIMISM,
    min_wealth=MIN_WEALTH,
    ss_levels=SS_LEVELS,
    consumption_decline_val=CONSUMPTION_DECLINE,
    health_utility_vals=Float64.(HEALTH_UTILITY),
    verbose=true,
)

# Save pairwise CSV
pw_csv_path = joinpath(tables_dir, "csv", "pairwise_interactions.csv")
open(pw_csv_path, "w") do f
    n_ch = length(pw.channel_names)
    print(f, "channel_A,channel_B,own_A,own_B,own_AB,interaction_pp")
    println(f)
    for i in 1:n_ch
        for j in (i+1):n_ch
            @printf(f, "%s,%s,%.2f,%.2f,%.2f,%.2f\n",
                pw.channel_names[i], pw.channel_names[j],
                pw.isolated_ownership[i] * 100, pw.isolated_ownership[j] * 100,
                pw.pair_ownership[i, j] * 100,
                pw.interaction_matrix[i, j] * 100)
        end
    end
end
println("  Pairwise CSV saved: $pw_csv_path")

# Save pairwise LaTeX table
pw_tex_path = joinpath(tables_dir, "tex", "pairwise_interactions.tex")
n_ch = length(pw.channel_names)
open(pw_tex_path, "w") do f
    println(f, raw"\begin{table}[htbp]")
    println(f, raw"\centering")
    println(f, raw"\caption{Pairwise Interaction Strengths, Rational and Preference Channels (pp)}")
    println(f, raw"\label{tab:pairwise}")
    println(f, raw"\begin{tabular}{l" * "c" ^ n_ch * "}")
    println(f, raw"\toprule")
    # Header row
    print(f, " ")
    for name in pw.channel_names
        print(f, " & ", name)
    end
    println(f, " \\\\")
    println(f, raw"\midrule")
    # Data rows (upper triangle only)
    for i in 1:n_ch
        print(f, pw.channel_names[i])
        for j in 1:n_ch
            if j <= i
                print(f, " & ---")
            else
                @printf(f, " & %+.1f", pw.interaction_matrix[i, j] * 100)
            end
        end
        println(f, " \\\\")
    end
    println(f, raw"\bottomrule")
    println(f, raw"\end{tabular}")
    println(f, raw"\begin{tablenotes}")
    println(f, raw"\small")
    println(f, raw"\item Each cell shows the interaction: ownership with both channels minus")
    println(f, raw"the additive prediction from individual effects. Negative values indicate")
    println(f, raw"super-additive demand reduction (channels reinforce each other).")
    println(f, raw"\end{tablenotes}")
    println(f, raw"\end{table}")
end
println("  Pairwise LaTeX saved: $pw_tex_path")

println("\n" * "=" ^ 70)
println("  DECOMPOSITION COMPLETE")
println("=" ^ 70)

#=============================================================================
# ORIGINAL FILE: scripts/run_subset_enumeration.jl
#=============================================================================

# Full subset enumeration of annuity ownership channels.
#
# Precomputes the ownership rate for every combination of 10 channels
# (2^10 = 1024 subsets), then reconstructs any decomposition ordering,
# exact Shapley values, and pairwise interactions from the lookup table.
#
# Channels:
#   1. SS            — Social Security pre-annuitization
#   2. Bequests      — DFJ luxury good bequest motive
#   3. Medical       — medical expenditure risk (uncorrelated)
#   4. R-S           — health-mortality correlation (requires Medical)
#   5. Pessimism     — survival pessimism (O'Dea & Sturrock 2023)
#   6. Age needs     — front-loaded spending preferences (Aguiar-Hurst)
#   7. State utility — health-varying marginal utility (FLN 2013)
#   8. Loads         — realistic pricing (MWR < 1, fixed cost)
#   9. Inflation     — nominal annuity erosion
#  10. Behavioral    — purchase-event disutility (Chalmers-Reuter 2012,
#                       Blanchett-Finke 2025); calibrated externally
#
# R-S depends on Medical: when R-S is active but Medical is not,
# Medical is forced on (standard treatment for complementary channels).
#
# Usage: julia --project=. -p 90 scripts/run_subset_enumeration.jl

using Printf
using DelimitedFiles
using Distributed
using Random

if nworkers() > 1
    @everywhere include(joinpath(@__DIR__, "..", "src", "AnnuityPuzzle.jl"))
    @everywhere using .AnnuityPuzzle
else
    include(joinpath(@__DIR__, "..", "src", "AnnuityPuzzle.jl"))
    using .AnnuityPuzzle
end

include(joinpath(@__DIR__, "config.jl"))

# Channel-specific calibration values (kept in this file because they apply only
# when the corresponding channel is active in a subset).
#
# HEALTH_UTILITY: two defensible mappings from Finkelstein-Luttmer (2013) exist.
#   [1.0, 0.90, 0.75]  — raw FLN central estimates (production)
#   [1.0, 0.95, 0.85]  — Reichling-Smetters (2015) softer translation
# scripts/export_manuscript_numbers.jl must mirror whichever value is active here.
const CONSUMPTION_DECLINE = 0.02
const HEALTH_UTILITY = [1.0, 0.90, 0.75]

# PSI_PURCHASE_VAL: narrow-framing purchase-event disutility, applied only when
# Channel 11 (Force B) is active. Production value sourced from config.jl
# (calibrated by single-moment SMM to UK 2015 behavioral elasticity, Anchor C-mid).
# Sensitivity interval across alternative anchors: [0.014, 0.028]; see appendix.
const PSI_PURCHASE_VAL = PSI_PURCHASE

# ===================================================================
# Channel index definitions
# ===================================================================
# 10-channel structure: medical-expense risk and the Reichling-Smetters
# health-mortality correlation are combined into a single "R-S correlation
# (incl. medical risk)" channel, because R-S has no economic content
# without stochastic medical costs to correlate against. Following the
# Owen (1977) coalition-structure value, this is the cleanest mathematical
# treatment for two players that cannot be separated. See review_reports/
# for the panel discussion that motivated this reformulation.
@everywhere const CH_SS            = 1
@everywhere const CH_BEQUESTS      = 2
@everywhere const CH_MED_RS        = 3   # Combined: medical risk + R-S correlation
@everywhere const CH_PESSIMISM     = 4
@everywhere const CH_AGE_NEEDS     = 5
@everywhere const CH_STATE_UTIL    = 6
@everywhere const CH_LOADS         = 7
@everywhere const CH_INFLATION     = 8
@everywhere const CH_SDU           = 9   # Source-dependent utility (Force A)
@everywhere const CH_PSI_PURCHASE  = 10  # Narrow-framing penalty (Force B)

const N_CHANNELS = 10
const N_SUBSETS = 2^N_CHANNELS  # 1024
const CHANNEL_NAMES = [
    "SS", "Bequests", "Medical+R-S", "Pessimism", "Age needs",
    "State utility", "Loads", "Inflation",
    "SDU (Force A)", "Narrow framing (Force B)",
]

println("=" ^ 70)
println("  FULL SUBSET ENUMERATION: 2^$N_CHANNELS = $N_SUBSETS CHANNEL SUBSETS")
println("=" ^ 70)
flush(stdout)

# ===================================================================
# Load HRS population sample
# ===================================================================
println("\nLoading HRS population sample...")
flush(stdout)
hrs_raw = readdlm(HRS_PATH, ',', Any; skipstart=1)
n_pop = size(hrs_raw, 1)
population = zeros(n_pop, 4)
population[:, 1] = Float64.(hrs_raw[:, 1])  # wealth
population[:, 2] .= 0.0                      # SS via ss_func, not A grid
population[:, 3] = Float64.(hrs_raw[:, 3])  # age
if size(hrs_raw, 2) >= 4
    population[:, 4] = Float64.(hrs_raw[:, 4])  # health (1=Good, 2=Fair, 3=Poor)
else
    population[:, 4] .= 2.0
end
@printf("  Loaded %d individuals\n", n_pop)
flush(stdout)

# ===================================================================
# Build survival probabilities and payout rates
# ===================================================================
p_base = ModelParams(age_start=AGE_START, age_end=AGE_END)
base_surv = build_lockwood_survival(p_base)

grid_kw = (n_wealth=N_WEALTH, n_annuity=N_ANNUITY, n_alpha=N_ALPHA,
           W_max=W_MAX, age_start=AGE_START, age_end=AGE_END,
           annuity_grid_power=A_GRID_POW)

p_fair = ModelParams(; gamma=GAMMA, beta=BETA, r=R_RATE, mwr=1.0, grid_kw...)
fair_pr = compute_payout_rate(p_fair, base_surv)

p_fair_nom = ModelParams(; gamma=GAMMA, beta=BETA, r=R_RATE, mwr=1.0,
                           inflation_rate=INFLATION, grid_kw...)
fair_pr_nom = INFLATION > 0 ? compute_payout_rate(p_fair_nom, base_surv) : fair_pr

@printf("  Fair payout rate (real):    %.4f\n", fair_pr)
@printf("  Fair payout rate (nominal): %.4f\n", fair_pr_nom)
flush(stdout)

# ===================================================================
# Build channel config from bitmask
# ===================================================================
# Convert an integer bitmask (0 to 1023) to the set of active channel indices.
# Bit i (0-indexed) corresponds to channel i+1. Ten channels: bits 0-9.
@everywhere function bitmask_to_channels(mask::Int)
    active = Set{Int}()
    for i in 0:9  # 10 channels: bits 0-9
        if (mask >> i) & 1 == 1
            push!(active, i + 1)
        end
    end
    return active
end

# Build ModelParams overrides for a given set of active channels.
# Handles the R-S -> Medical dependency.
@everywhere function build_subset_config(active::Set{Int};
        theta_dfj, kappa_dfj, mwr_loaded, fixed_cost, min_purchase, inflation_val,
        survival_pessimism, ss_quartile_levels,
        consumption_decline, health_utility, lambda_w_val, psi_purchase_val)

    ss_levels = [0.0, 0.0, 0.0, 0.0]
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
    lam_w = 1.0
    psi_p = 0.0

    if CH_SS in active
        ss_levels = copy(ss_quartile_levels)
    end
    if CH_BEQUESTS in active
        theta = theta_dfj
        kappa = kappa_dfj
    end
    # Combined R-S + Medical channel: setting it activates both stochastic
    # medical-expense risk AND the health-mortality correlation. R-S has
    # no economic content without medical costs, so the two are not
    # separately switchable in our 10-channel structure.
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
    if CH_SDU in active
        lam_w = lambda_w_val
    end
    if CH_PSI_PURCHASE in active
        psi_p = psi_purchase_val
    end

    return (ss_levels=ss_levels,
            theta=theta, kappa=kappa,
            medical_enabled=medical_enabled,
            health_mortality_corr=health_mortality_corr,
            survival_pessimism=psi,
            consumption_decline=cd,
            health_utility=hu,
            mwr=mwr, fixed_cost=fc, min_purchase=min_p,
            inflation_rate=infl,
            lambda_w=lam_w,
            psi_purchase=psi_p)
end

# ===================================================================
# Solve all 1024 subsets
# ===================================================================
println("\nSolving all $N_SUBSETS channel subsets...")
flush(stdout)

# Capture config values for worker closures
_theta_dfj = THETA_DFJ
_kappa_dfj = KAPPA_DFJ
_mwr_loaded = MWR_LOADED
_fixed_cost = FIXED_COST
_min_purchase = MIN_PURCHASE
_inflation = INFLATION
_surv_pess = SURVIVAL_PESSIMISM
_ss_q_levels = Float64.(SS_QUARTILE_LEVELS)
_gamma = GAMMA
_beta = BETA
_r_rate = R_RATE
_c_floor = C_FLOOR
_hazard_mult = Float64.(HAZARD_MULT)
_n_wealth = N_WEALTH
_n_annuity = N_ANNUITY
_n_alpha = N_ALPHA
_w_max = W_MAX
_n_quad = N_QUAD
_age_start = AGE_START
_age_end = AGE_END
_a_grid_pow = A_GRID_POW
_min_wealth = MIN_WEALTH
_base_surv = base_surv
_population = population
_fair_pr = fair_pr
_fair_pr_nom = fair_pr_nom
_consumption_decline = CONSUMPTION_DECLINE
_health_utility = Float64.(HEALTH_UTILITY)
_lambda_w = LAMBDA_W
_psi_purchase_val = PSI_PURCHASE_VAL

subset_specs = [(bitmask=i,) for i in 0:(N_SUBSETS - 1)]

t0_solve = time()

results = parallel_solve(subset_specs) do spec
    mask = spec.bitmask
    active = bitmask_to_channels(mask)

    cfg = build_subset_config(active;
        theta_dfj=_theta_dfj, kappa_dfj=_kappa_dfj,
        mwr_loaded=_mwr_loaded, fixed_cost=_fixed_cost,
        min_purchase=_min_purchase,
        inflation_val=_inflation, survival_pessimism=_surv_pess,
        ss_quartile_levels=_ss_q_levels,
        consumption_decline=_consumption_decline,
        health_utility=_health_utility,
        lambda_w_val=_lambda_w,
        psi_purchase_val=_psi_purchase_val)

    gkw = (n_wealth=_n_wealth, n_annuity=_n_annuity, n_alpha=_n_alpha,
           W_max=_w_max, age_start=_age_start, age_end=_age_end,
           annuity_grid_power=_a_grid_pow)

    common_kw = (gamma=_gamma, beta=_beta, r=_r_rate,
                 stochastic_health=true, n_health_states=3, n_quad=_n_quad,
                 c_floor=_c_floor, hazard_mult=_hazard_mult)

    # Determine payout rate based on active channels
    has_loads = cfg.mwr < 1.0
    has_infl = cfg.inflation_rate > 0
    if has_loads && has_infl
        pr = cfg.mwr * _fair_pr_nom
    elseif has_loads
        pr = cfg.mwr * _fair_pr
    elseif has_infl
        pr = _fair_pr_nom
    else
        pr = _fair_pr
    end

    # Build grids using fair payout rate (covers full A range)
    p_grid = ModelParams(; common_kw..., mwr=1.0, gkw...)
    grids = build_grids(p_grid, max(_fair_pr, _fair_pr_nom))

    p_model = ModelParams(; common_kw...,
        theta=cfg.theta, kappa=cfg.kappa,
        mwr=cfg.mwr, fixed_cost=cfg.fixed_cost,
        min_purchase=cfg.min_purchase,
        inflation_rate=cfg.inflation_rate,
        medical_enabled=cfg.medical_enabled,
        health_mortality_corr=cfg.health_mortality_corr,
        survival_pessimism=cfg.survival_pessimism,
        consumption_decline=cfg.consumption_decline,
        health_utility=cfg.health_utility,
        lambda_w=cfg.lambda_w,
        psi_purchase=cfg.psi_purchase,
        gkw...)

    # Filter population
    pop = copy(_population)
    if _min_wealth > 0.0
        pop_mask = pop[:, 1] .>= _min_wealth
        pop = pop[pop_mask, :]
    end
    if size(pop, 2) < 4
        pop = hcat(pop, fill(2.0, size(pop, 1)))
    end

    t0 = time()
    res = solve_and_evaluate(p_model, grids, _base_surv, cfg.ss_levels,
        pop, pr; step_name="", verbose=false)
    st = time() - t0

    (bitmask=mask, ownership=res.ownership, mean_alpha=res.mean_alpha, solve_time=st)
end

total_solve_time = time() - t0_solve
@printf("  Solved %d subsets in %.0fs (%.1fs per subset)\n",
    N_SUBSETS, total_solve_time, total_solve_time / N_SUBSETS)
flush(stdout)

# ===================================================================
# Build lookup table
# ===================================================================
ownership_lookup = Dict{Int, Float64}()
alpha_lookup = Dict{Int, Float64}()
solvetime_lookup = Dict{Int, Float64}()
for r in results
    ownership_lookup[r.bitmask] = r.ownership
    alpha_lookup[r.bitmask] = r.mean_alpha
    solvetime_lookup[r.bitmask] = r.solve_time
end

yaari_own = ownership_lookup[0]
full_mask = (1 << N_CHANNELS) - 1  # 1023 with 10 channels
full_own = ownership_lookup[full_mask]
total_drop = yaari_own - full_own

println("\n  Yaari baseline (bitmask 0):   $(round(yaari_own * 100, digits=1))%")
println("  Full model (bitmask $full_mask):  $(round(full_own * 100, digits=1))%")
println("  Total drop:                   $(round(total_drop * 100, digits=1)) pp")
flush(stdout)

# ===================================================================
# Helper: channel names for a bitmask
# ===================================================================
function channels_active_str(mask::Int)
    names = String[]
    for i in 0:(N_CHANNELS - 1)
        if (mask >> i) & 1 == 1
            push!(names, CHANNEL_NAMES[i + 1])
        end
    end
    return isempty(names) ? "None" : join(names, "+")
end

# ===================================================================
# Save full enumeration CSV
# ===================================================================
tables_dir = joinpath(@__DIR__, "..", "tables")
mkpath(joinpath(tables_dir, "csv"))
mkpath(joinpath(tables_dir, "tex"))

enum_csv_path = joinpath(tables_dir, "csv", "subset_enumeration.csv")
open(enum_csv_path, "w") do f
    println(f, "bitmask,channel_names_active,ownership_pct,mean_alpha,solve_time")
    for mask in 0:(N_SUBSETS - 1)
        @printf(f, "%d,%s,%.4f,%.6f,%.1f\n",
            mask,
            channels_active_str(mask),
            ownership_lookup[mask] * 100,
            alpha_lookup[mask],
            solvetime_lookup[mask])
    end
end
println("\n  Enumeration CSV saved: $enum_csv_path")
flush(stdout)

# ===================================================================
# Sequential decomposition from the lookup table (any ordering)
# ===================================================================
println("\n" * "=" ^ 70)
println("  SEQUENTIAL DECOMPOSITION (from lookup table)")
println("=" ^ 70)

# Default ordering matches the manuscript decomposition (3-layer structure):
#   Layer 1 (rational): SS, Bequests, MED+R-S (combined), Pessimism, Loads, Inflation
#   Layer 2 (preferences): Age needs, State utility
#   Layer 3 (behavioral): Force A (SDU), Force B (narrow framing)
default_order = [CH_SS, CH_BEQUESTS, CH_MED_RS, CH_PESSIMISM,
                 CH_LOADS, CH_INFLATION,
                 CH_AGE_NEEDS, CH_STATE_UTIL,
                 CH_SDU, CH_PSI_PURCHASE]

"""
Reconstruct a sequential decomposition for any channel ordering
from the precomputed lookup table.
"""
function sequential_from_lookup(ordering::Vector{Int}, lookup::Dict{Int, Float64})
    steps = Tuple{String, Float64, Float64}[]
    mask = 0
    prev_own = lookup[0]
    push!(steps, ("Yaari benchmark", prev_own, 0.0))

    for ch in ordering
        # No coupling needed; CH_MED_RS is a single combined channel.
        mask |= (1 << (ch - 1))
        own = lookup[mask]
        delta = own - prev_own
        push!(steps, ("+ " * CHANNEL_NAMES[ch], own, delta))
        prev_own = own
    end
    return steps
end

steps = sequential_from_lookup(default_order, ownership_lookup)

@printf("\n  %-55s  %8s  %10s  %10s\n", "Model Specification", "Own (%)", "Delta (pp)", "Retention")
println("  " * "-" ^ 88)

for (i, (name, own, delta)) in enumerate(steps)
    if i == 1
        @printf("  %-55s  %7.1f%%\n", name, own * 100)
    else
        prev_own = steps[i - 1][2]
        retention = prev_own > 0 ? own / prev_own : 0.0
        @printf("  %-55s  %7.1f%%  %+9.1f pp  %8.1f%%\n",
            name, own * 100, delta * 100, retention * 100)
    end
end
println("  " * "-" ^ 88)
@printf("  %-55s  %7.1f%%\n", "Observed (Lockwood 2012, single retirees 65-69)", 3.6)
flush(stdout)

# ===================================================================
# Exact Shapley values
# ===================================================================
println("\n" * "=" ^ 70)
println("  EXACT SHAPLEY VALUES (from $N_SUBSETS precomputed subsets)")
println("=" ^ 70)
flush(stdout)

# v(S) = yaari_own - ownership(S) = total ownership drop caused by subset S.
# Using the cooperative game convention: v maps subsets to the total demand
# reduction they produce. Shapley decomposes the total drop across channels.

function exact_shapley(n::Int, lookup::Dict{Int, Float64})
    yaari = lookup[0]
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
        # Standard Shapley over the full power set 2^n with no coupling;
        # the prior R-S/Medical special case is no longer needed because
        # they are now a single combined channel (CH_MED_RS).
        for s_mask in 0:((1 << n) - 1)
            (s_mask & bit_i) != 0 && continue  # skip if i is in S

            s_size = count_ones(s_mask)
            s_union_i = s_mask | bit_i

            # Marginal contribution of channel i to coalition S:
            # v(S ∪ {i}) - v(S) where v(S) = yaari - ownership(S)
            # = (yaari - ownership(S ∪ {i})) - (yaari - ownership(S))
            # = ownership(S) - ownership(S ∪ {i})
            mc = lookup[s_mask] - lookup[s_union_i]

            # Shapley weight: |S|! * (N - |S| - 1)! / N!
            weight = Float64(fact[s_size + 1]) * Float64(fact[n - s_size]) / Float64(fact[n + 1])
            phi_i += weight * mc
        end

        shapley[i] = phi_i
    end

    return shapley
end

shapley = exact_shapley(N_CHANNELS, ownership_lookup)

@printf("\n  %-15s  %12s  %10s\n", "Channel", "Shapley (pp)", "Share (%)")
println("  " * "-" ^ 40)

for i in 1:N_CHANNELS
    share = total_drop > 0 ? shapley[i] / total_drop * 100 : 0.0
    @printf("  %-15s  %+11.2f  %9.1f\n",
        CHANNEL_NAMES[i], shapley[i] * 100, share)
end
println("  " * "-" ^ 40)
@printf("  %-15s  %+11.2f  %9.1f\n", "Total", sum(shapley) * 100,
    total_drop > 0 ? sum(shapley) / total_drop * 100 : 0.0)
@printf("\n  Verification: sum of Shapley = %.2f pp, total drop = %.2f pp\n",
    sum(shapley) * 100, total_drop * 100)
flush(stdout)

# ===================================================================
# Pairwise interactions from lookup table
# ===================================================================
println("\n" * "=" ^ 70)
println("  PAIRWISE INTERACTIONS (from lookup table)")
println("=" ^ 70)
flush(stdout)

# Interaction(i,j) = [v({i,j}) - v({i}) - v({j}) + v({})]
# where v(S) = yaari - ownership(S)
# = [ownership({i}) + ownership({j}) - ownership({i,j}) - yaari]
# Negative means channels reinforce (super-additive).

interaction_matrix = fill(NaN, N_CHANNELS, N_CHANNELS)

for i in 1:N_CHANNELS
    for j in (i+1):N_CHANNELS
        mask_i = 1 << (i - 1)
        mask_j = 1 << (j - 1)
        mask_ij = mask_i | mask_j

        # CH_MED_RS is now a single combined channel; no R-S/Medical
        # dependency handling needed.

        own_i = ownership_lookup[mask_i]
        own_j = ownership_lookup[mask_j]
        own_ij = ownership_lookup[mask_ij]

        # Additive prediction: yaari - drop_i - drop_j
        drop_i = yaari_own - own_i
        drop_j = yaari_own - own_j
        additive_pred = yaari_own - drop_i - drop_j
        interaction_matrix[i, j] = own_ij - additive_pred
        interaction_matrix[j, i] = interaction_matrix[i, j]
    end
    interaction_matrix[i, i] = 0.0
end

@printf("\n  %-15s", "")
for name in CHANNEL_NAMES
    @printf("  %9s", length(name) > 9 ? name[1:9] : name)
end
println()
println("  " * "-" ^ (15 + 11 * N_CHANNELS))

for i in 1:N_CHANNELS
    @printf("  %-15s", CHANNEL_NAMES[i])
    for j in 1:N_CHANNELS
        if i == j
            @printf("  %9s", "---")
        elseif j > i
            @printf("  %+8.1f", interaction_matrix[i, j] * 100)
        else
            @printf("  %9s", "")
        end
    end
    println()
end
println("\n  Negative = channels reinforce (super-additive demand reduction)")
flush(stdout)

# ===================================================================
# Save Shapley CSV
# ===================================================================
shapley_csv_path = joinpath(tables_dir, "csv", "shapley_exact.csv")
open(shapley_csv_path, "w") do f
    println(f, "channel,shapley_value_pp,share_pct")
    for i in 1:N_CHANNELS
        share = total_drop > 0 ? shapley[i] / total_drop * 100 : 0.0
        @printf(f, "%s,%.4f,%.2f\n", CHANNEL_NAMES[i], shapley[i] * 100, share)
    end
end
println("\n  Shapley CSV saved: $shapley_csv_path")
flush(stdout)

# ===================================================================
# Save Shapley LaTeX table
# ===================================================================
shapley_tex_path = joinpath(tables_dir, "tex", "shapley_exact.tex")
open(shapley_tex_path, "w") do f
    println(f, raw"\begin{table}[htbp]")
    println(f, raw"\centering")
    println(f, raw"\caption{Exact Shapley-Value Decomposition of Predicted Annuity Ownership}")
    println(f, raw"\label{tab:shapley_exact}")
    println(f, raw"\begin{tabular}{lcc}")
    println(f, raw"\toprule")
    println(f, "Channel & Shapley (pp) & Share (\\%) \\\\")
    println(f, raw"\midrule")

    for i in 1:N_CHANNELS
        share = total_drop > 0 ? shapley[i] / total_drop * 100 : 0.0
        @printf(f, "%s & %+.2f & %.1f \\\\\n",
            CHANNEL_NAMES[i], shapley[i] * 100, share)
    end

    println(f, raw"\midrule")
    @printf(f, "Total & %+.2f & 100.0 \\\\\n", sum(shapley) * 100)
    println(f, raw"\bottomrule")
    println(f, raw"\end{tabular}")
    println(f, raw"\begin{tablenotes}")
    println(f, raw"\small")
    @printf(f, "\\item Exact Shapley values computed from all %d channel subsets.\n", N_SUBSETS)
    println(f, "Each value represents the weighted average marginal ownership reduction (pp)")
    println(f, "across all coalition orderings.")
    @printf(f, "Yaari baseline: %.1f\\%%. Full model: %.1f\\%%.\n",
        yaari_own * 100, full_own * 100)
    println(f, raw"\end{tablenotes}")
    println(f, raw"\end{table}")
end
println("  Shapley LaTeX saved: $shapley_tex_path")
flush(stdout)

# ===================================================================
# Save pairwise interactions CSV
# ===================================================================
pw_csv_path = joinpath(tables_dir, "csv", "pairwise_interactions_exact.csv")
open(pw_csv_path, "w") do f
    println(f, "channel_A,channel_B,own_A_pct,own_B_pct,own_AB_pct,interaction_pp")
    for i in 1:N_CHANNELS
        for j in (i+1):N_CHANNELS
            mask_i = 1 << (i - 1)
            mask_j = 1 << (j - 1)
            mask_ij = mask_i | mask_j
            # CH_MED_RS is a single combined channel; no coupling adjustment.
            @printf(f, "%s,%s,%.2f,%.2f,%.2f,%.2f\n",
                CHANNEL_NAMES[i], CHANNEL_NAMES[j],
                ownership_lookup[mask_i] * 100,
                ownership_lookup[mask_j] * 100,
                ownership_lookup[mask_ij] * 100,
                interaction_matrix[i, j] * 100)
        end
    end
end
println("  Pairwise CSV saved: $pw_csv_path")
flush(stdout)

# ===================================================================
# Summary statistics
# ===================================================================
println("\n" * "=" ^ 70)
println("  SUMMARY STATISTICS")
println("=" ^ 70)

# Most/least effective single channels.
# CH_MED_RS is the combined R-S + Medical channel; no special handling needed.
single_drops = [(CHANNEL_NAMES[i], yaari_own - ownership_lookup[1 << (i - 1)]) for i in 1:N_CHANNELS]

sort!(single_drops, by=x -> -x[2])

println("\n  Single-channel effectiveness (demand reduction from Yaari):")
for (name, drop) in single_drops
    @printf("    %-15s  %+.1f pp\n", name, drop * 100)
end

# Count subsets that produce ownership <= 5%
low_own_count = count(v -> v <= 0.05, values(ownership_lookup))
@printf("\n  Subsets with ownership <= 5%%: %d of %d (%.1f%%)\n",
    low_own_count, N_SUBSETS, low_own_count / N_SUBSETS * 100)

# Minimum and maximum ownership across all subsets. Wrapped in `let` so the
# for-loop body sees the same scope as the accumulators (top-level `local`
# does not propagate into the for-loop's own scope under Julia 1.10).
let min_mask = 0, max_mask = 0, min_own_val = Inf, max_own_val = -Inf
    for (m, o) in ownership_lookup
        if o < min_own_val
            min_own_val = o
            min_mask = m
        end
        if o > max_own_val
            max_own_val = o
            max_mask = m
        end
    end
    @printf("  Min ownership: %.1f%% (%s)\n", min_own_val * 100, channels_active_str(min_mask))
    @printf("  Max ownership: %.1f%% (%s)\n", max_own_val * 100, channels_active_str(max_mask))
end

println("\n" * "=" ^ 70)
println("  SUBSET ENUMERATION COMPLETE")
@printf("  Total computation time: %.0fs\n", total_solve_time)
println("=" ^ 70)
flush(stdout)

#=============================================================================
# ORIGINAL FILE: scripts/run_shapley_decomposition.jl
#=============================================================================

# DEPRECATED — superseded by scripts/run_subset_enumeration.jl
# ============================================================
# This Monte Carlo permutation-based Shapley estimator was the original
# 7-channel decomposition tool. It has been replaced by the exact full
# enumeration (2^10 = 1024 subsets) in run_subset_enumeration.jl, which
# computes Shapley values exactly without permutation noise. The 10-channel
# reformulation also bundles Medical+R-S into a single channel, eliminating
# the special-case coupling logic this script implemented.
#
# This file is retained only for archival reference. Do not use for current
# results — pipeline output is generated by run_subset_enumeration.jl.
#
# Original docstring (7-channel structure):
# Shapley-value decomposition of annuity ownership channels.
#
# Addresses the order-dependence critique of sequential decomposition by
# computing each channel's average marginal contribution across random
# permutations of the 7 channels. With 7! = 5,040 orderings, exact
# computation is feasible but slow; Monte Carlo approximation with
# N_PERM random permutations suffices.
#
# Channels:
#   1. SS        — Social Security pre-annuitization
#   2. Bequests  — DFJ luxury good bequest motive
#   3. Medical   — medical expenditure risk (uncorrelated)
#   4. R-S       — health-mortality correlation (requires Medical)
#   5. Pessimism — survival pessimism (O'Dea & Sturrock 2023)
#   6. Loads     — realistic pricing (MWR < 1, fixed cost)
#   7. Inflation — nominal annuity erosion
#
# R-S depends on Medical: when R-S appears before Medical in a permutation,
# both activate together when R-S is reached (standard Shapley treatment
# for complementary channels).
#
# Usage: julia --project=. -p 8 scripts/run_shapley_decomposition.jl

using Printf
using DelimitedFiles
using Distributed
using Random

if nworkers() > 1
    @everywhere include(joinpath(@__DIR__, "..", "src", "AnnuityPuzzle.jl"))
    @everywhere using .AnnuityPuzzle
else
    include(joinpath(@__DIR__, "..", "src", "AnnuityPuzzle.jl"))
    using .AnnuityPuzzle
end

include(joinpath(@__DIR__, "config.jl"))

const N_PERM = 200  # number of random permutations (increase for tighter estimates)
const RNG_SEED = 42

println("=" ^ 70)
println("  SHAPLEY-VALUE DECOMPOSITION OF ANNUITY OWNERSHIP CHANNELS")
println("  N_PERM = $N_PERM random permutations")
println("=" ^ 70)
flush(stdout)

# ===================================================================
# Load HRS population sample
# ===================================================================
println("\nLoading HRS population sample...")
flush(stdout)
hrs_raw = readdlm(HRS_PATH, ',', Any; skipstart=1)
n_pop = size(hrs_raw, 1)
population = zeros(n_pop, 4)
population[:, 1] = Float64.(hrs_raw[:, 1])  # wealth
population[:, 2] .= 0.0                      # SS via ss_func, not A grid
population[:, 3] = Float64.(hrs_raw[:, 3])  # age
if size(hrs_raw, 2) >= 4
    population[:, 4] = Float64.(hrs_raw[:, 4])  # health (1=Good, 2=Fair, 3=Poor)
else
    population[:, 4] .= 2.0
end
@printf("  Loaded %d individuals\n", n_pop)
flush(stdout)

# ===================================================================
# Build survival probabilities
# ===================================================================
p_base = ModelParams(age_start=AGE_START, age_end=AGE_END)
base_surv = build_lockwood_survival(p_base)

# ===================================================================
# Channel definitions (available on all workers)
# ===================================================================
@everywhere const CH_SS          = 1
@everywhere const CH_BEQUESTS    = 2
@everywhere const CH_MEDICAL     = 3
@everywhere const CH_RS          = 4
@everywhere const CH_PESSIMISM   = 5
@everywhere const CH_HEALTHUTIL  = 6
@everywhere const CH_AGENEEDS    = 7
@everywhere const CH_LOADS       = 8
@everywhere const CH_INFLATION   = 9

# Determine active channel count based on config defaults
_ch_names = ["SS", "Bequests", "Medical", "R-S", "Pessimism"]
_ch_count = 5
_health_util_active = !all(x -> x == 1.0, HEALTH_UTILITY)
_cons_decline_active = CONSUMPTION_DECLINE > 0.0
if _health_util_active
    push!(_ch_names, "HealthUtil")
    _ch_count += 1
end
if _cons_decline_active
    push!(_ch_names, "AgeNeeds")
    _ch_count += 1
end
push!(_ch_names, "Loads")
push!(_ch_names, "Inflation")
_ch_count += 2

const N_CHANNELS = _ch_count
const CHANNEL_NAMES = _ch_names

# Build mapping from channel constants to active channel indices
const CH_INDEX = Dict{Int,Int}()
_idx = 1
for ch in [CH_SS, CH_BEQUESTS, CH_MEDICAL, CH_RS, CH_PESSIMISM]
    CH_INDEX[ch] = _idx; _idx += 1
end
if _health_util_active
    CH_INDEX[CH_HEALTHUTIL] = _idx; _idx += 1
end
if _cons_decline_active
    CH_INDEX[CH_AGENEEDS] = _idx; _idx += 1
end
CH_INDEX[CH_LOADS] = _idx; _idx += 1
CH_INDEX[CH_INFLATION] = _idx

# Active channel IDs (subset of 1:9 that are in use)
const ACTIVE_CHANNELS = sort(collect(keys(CH_INDEX)))

# Build ModelParams overrides and SS levels for a given set of active channels.
# Returns a NamedTuple suitable for constructing ModelParams and solve_and_evaluate().
@everywhere function build_channel_config(active::Set{Int};
        theta_dfj, kappa_dfj, mwr_loaded, fixed_cost, inflation_val,
        survival_pessimism, ss_quartile_levels,
        health_utility_vals=[1.0, 1.0, 1.0],
        consumption_decline_val=0.0)

    ss_levels = [0.0, 0.0, 0.0, 0.0]
    theta = 0.0
    kappa = 0.0
    medical_enabled = false
    health_mortality_corr = false
    psi = 1.0
    mwr = 1.0
    fc = 0.0
    infl = 0.0
    hu = [1.0, 1.0, 1.0]
    cd = 0.0

    if CH_SS in active
        ss_levels = copy(ss_quartile_levels)
    end
    if CH_BEQUESTS in active
        theta = theta_dfj
        kappa = kappa_dfj
    end
    # R-S requires Medical; if R-S is active, Medical must also be active
    if CH_MEDICAL in active || CH_RS in active
        medical_enabled = true
    end
    if CH_RS in active
        health_mortality_corr = true
    end
    if CH_PESSIMISM in active
        psi = survival_pessimism
    end
    if CH_HEALTHUTIL in active
        hu = copy(health_utility_vals)
    end
    if CH_AGENEEDS in active
        cd = consumption_decline_val
    end
    if CH_LOADS in active
        mwr = mwr_loaded
        fc = fixed_cost
    end
    if CH_INFLATION in active
        infl = inflation_val
    end

    return (ss_levels=ss_levels,
            theta=theta, kappa=kappa,
            medical_enabled=medical_enabled,
            health_mortality_corr=health_mortality_corr,
            survival_pessimism=psi,
            health_utility=hu,
            consumption_decline=cd,
            mwr=mwr, fixed_cost=fc,
            inflation_rate=infl)
end

# ===================================================================
# Generate random permutations
# ===================================================================
rng = MersenneTwister(RNG_SEED)
# Permute the active channel IDs (e.g., [1,2,3,4,5,8,9] for 7 channels)
perms = [ACTIVE_CHANNELS[randperm(rng, N_CHANNELS)] for _ in 1:N_PERM]
@printf("  Generated %d random permutations (seed=%d)\n", N_PERM, RNG_SEED)
flush(stdout)

# ===================================================================
# Evaluate all permutations
# ===================================================================
# For each permutation, we need to evaluate the model at each prefix
# (0 channels, 1 channel, ..., N channels). That's N+1 evaluations per
# permutation. However, many prefixes are shared across permutations,
# so we deduplicate by caching on the frozenset of active channels.
#
# Strategy: collect all unique channel subsets needed, solve each once,
# then reconstruct marginal contributions from the cache.

# Collect all subsets needed across all permutations
subset_set = Set{Set{Int}}()
push!(subset_set, Set{Int}())  # empty set (Yaari baseline)
for perm in perms
    active = Set{Int}()
    for ch in perm
        # R-S depends on Medical: when R-S is added, Medical comes along
        new_active = copy(active)
        push!(new_active, ch)
        if ch == CH_RS
            push!(new_active, CH_MEDICAL)
        end
        push!(subset_set, copy(new_active))
        active = new_active
    end
end

# Convert to sorted tuples for stable indexing and serialization
subset_list = sort(collect(subset_set), by=s -> (length(s), sort(collect(s))))
subset_to_idx = Dict(s => i for (i, s) in enumerate(subset_list))
n_subsets = length(subset_list)
@printf("  Unique channel subsets to evaluate: %d (of %d total prefix evaluations)\n",
    n_subsets, N_PERM * (N_CHANNELS + 1))
flush(stdout)

# ===================================================================
# Solve each unique subset (parallelized)
# ===================================================================
println("\nSolving all unique channel subsets...")
flush(stdout)

# Capture config values for workers
_theta_dfj = THETA_DFJ
_kappa_dfj = KAPPA_DFJ
_mwr_loaded = MWR_LOADED
_fixed_cost = FIXED_COST
_inflation = INFLATION
_surv_pess = SURVIVAL_PESSIMISM
_ss_q_levels = Float64.(SS_QUARTILE_LEVELS)
_gamma = GAMMA
_beta = BETA
_r_rate = R_RATE
_c_floor = C_FLOOR
_hazard_mult = Float64.(HAZARD_MULT)
_n_wealth = N_WEALTH
_n_annuity = N_ANNUITY
_n_alpha = N_ALPHA
_w_max = W_MAX
_n_quad = N_QUAD
_age_start = AGE_START
_age_end = AGE_END
_a_grid_pow = A_GRID_POW
_min_wealth = MIN_WEALTH
_health_utility = Float64.(HEALTH_UTILITY)
_consumption_decline = CONSUMPTION_DECLINE
_base_surv = base_surv
_population = population

# Pre-compute payout rates on main process
grid_kw = (n_wealth=N_WEALTH, n_annuity=N_ANNUITY, n_alpha=N_ALPHA,
           W_max=W_MAX, age_start=AGE_START, age_end=AGE_END,
           annuity_grid_power=A_GRID_POW)
p_fair = ModelParams(; gamma=GAMMA, beta=BETA, r=R_RATE, mwr=1.0, grid_kw...)
fair_pr = compute_payout_rate(p_fair, base_surv)
p_fair_nom = ModelParams(; gamma=GAMMA, beta=BETA, r=R_RATE, mwr=1.0,
                           inflation_rate=INFLATION, grid_kw...)
fair_pr_nom = INFLATION > 0 ? compute_payout_rate(p_fair_nom, base_surv) : fair_pr

_fair_pr = fair_pr
_fair_pr_nom = fair_pr_nom

t0_solve = time()

# Convert subsets to serializable form for pmap
subset_specs = [(idx=i, channels=sort(collect(s))) for (i, s) in enumerate(subset_list)]

ownership_results = parallel_solve(subset_specs) do spec
    active = Set{Int}(spec.channels)

    cfg = build_channel_config(active;
        theta_dfj=_theta_dfj, kappa_dfj=_kappa_dfj,
        mwr_loaded=_mwr_loaded, fixed_cost=_fixed_cost,
        inflation_val=_inflation, survival_pessimism=_surv_pess,
        ss_quartile_levels=_ss_q_levels,
        health_utility_vals=_health_utility,
        consumption_decline_val=_consumption_decline)

    gkw = (n_wealth=_n_wealth, n_annuity=_n_annuity, n_alpha=_n_alpha,
           W_max=_w_max, age_start=_age_start, age_end=_age_end,
           annuity_grid_power=_a_grid_pow)

    common_kw = (gamma=_gamma, beta=_beta, r=_r_rate,
                 stochastic_health=true, n_health_states=3, n_quad=_n_quad,
                 c_floor=_c_floor, hazard_mult=_hazard_mult)

    # Determine payout rate
    has_loads = cfg.mwr < 1.0
    has_infl = cfg.inflation_rate > 0
    if has_loads && has_infl
        pr = cfg.mwr * _fair_pr_nom
    elseif has_loads
        pr = cfg.mwr * _fair_pr
    elseif has_infl
        pr = _fair_pr_nom
    else
        pr = _fair_pr
    end

    # Build grids using fair payout rate (covers full A range)
    p_grid = ModelParams(; common_kw..., mwr=1.0, gkw...)
    grids = build_grids(p_grid, max(_fair_pr, _fair_pr_nom))

    p_model = ModelParams(; common_kw...,
        theta=cfg.theta, kappa=cfg.kappa,
        mwr=cfg.mwr, fixed_cost=cfg.fixed_cost,
        inflation_rate=cfg.inflation_rate,
        medical_enabled=cfg.medical_enabled,
        health_mortality_corr=cfg.health_mortality_corr,
        survival_pessimism=cfg.survival_pessimism,
        health_utility=cfg.health_utility,
        consumption_decline=cfg.consumption_decline,
        gkw...)

    # Filter population
    pop = copy(_population)
    if _min_wealth > 0.0
        mask = pop[:, 1] .>= _min_wealth
        pop = pop[mask, :]
    end
    if size(pop, 2) < 4
        pop = hcat(pop, fill(2.0, size(pop, 1)))
    end

    # Solve with per-quartile SS
    res = solve_and_evaluate(p_model, grids, _base_surv, cfg.ss_levels,
        pop, pr; step_name="", verbose=false)

    (idx=spec.idx, ownership=res.ownership, mean_alpha=res.mean_alpha)
end

solve_time = time() - t0_solve
@printf("  Solved %d subsets in %.0fs (%.1fs per subset)\n",
    n_subsets, solve_time, solve_time / n_subsets)
flush(stdout)

# Build lookup from subset index to ownership
ownership_by_idx = Dict{Int, Float64}()
alpha_by_idx = Dict{Int, Float64}()
for r in ownership_results
    ownership_by_idx[r.idx] = r.ownership
    alpha_by_idx[r.idx] = r.mean_alpha
end

# ===================================================================
# Compute Shapley values from cached results
# ===================================================================
println("\nComputing Shapley values from permutation marginal contributions...")
flush(stdout)

# For each channel, collect its marginal contribution in each permutation.
# Use CH_INDEX to map channel IDs to array positions.
marginal_contributions = [Float64[] for _ in 1:N_CHANNELS]

for perm in perms
    active = Set{Int}()
    prev_ownership = ownership_by_idx[subset_to_idx[Set{Int}()]]

    for ch in perm
        new_active = copy(active)
        push!(new_active, ch)
        # R-S dependency: adding R-S also adds Medical
        if ch == CH_RS
            push!(new_active, CH_MEDICAL)
        end

        curr_ownership = ownership_by_idx[subset_to_idx[new_active]]
        marginal = prev_ownership - curr_ownership  # positive = demand reduction

        push!(marginal_contributions[CH_INDEX[ch]], marginal)

        active = new_active
        prev_ownership = curr_ownership
    end
end

# Helper: mean and std for Float64 vectors
function _mean(v::Vector{Float64})
    return sum(v) / length(v)
end
function _std(v::Vector{Float64})
    m = _mean(v)
    return sqrt(sum((x - m)^2 for x in v) / (length(v) - 1))
end

# Shapley value = mean marginal contribution
shapley_values = [_mean(mc) for mc in marginal_contributions]
shapley_std = [_std(mc) for mc in marginal_contributions]
shapley_min = [minimum(mc) for mc in marginal_contributions]
shapley_max = [maximum(mc) for mc in marginal_contributions]

# ===================================================================
# Print results
# ===================================================================
println("\n" * "=" ^ 70)
println("  SHAPLEY VALUE DECOMPOSITION RESULTS")
println("=" ^ 70)

# Yaari baseline and full model ownership
yaari_own = ownership_by_idx[subset_to_idx[Set{Int}()]]
full_own = ownership_by_idx[subset_to_idx[Set{Int}(ACTIVE_CHANNELS)]]
total_drop = yaari_own - full_own

@printf("\n  Yaari baseline ownership:  %6.1f%%\n", yaari_own * 100)
@printf("  Full model ownership:      %6.1f%%\n", full_own * 100)
@printf("  Total drop:                %6.1f pp\n", total_drop * 100)
@printf("  Sum of Shapley values:     %6.1f pp (should equal total drop)\n",
    sum(shapley_values) * 100)
flush(stdout)

@printf("\n  %-12s  %10s  %8s  %10s  %10s  %8s\n",
    "Channel", "Shapley", "Std Dev", "Min", "Max", "Share")
println("  " * "-" ^ 64)

for i in 1:N_CHANNELS
    share = total_drop > 0 ? shapley_values[i] / total_drop : 0.0
    @printf("  %-12s  %9.1f pp  %7.1f pp  %9.1f pp  %9.1f pp  %7.1f%%\n",
        CHANNEL_NAMES[i],
        shapley_values[i] * 100,
        shapley_std[i] * 100,
        shapley_min[i] * 100,
        shapley_max[i] * 100,
        share * 100)
end
println("  " * "-" ^ 64)
@printf("  %-12s  %9.1f pp\n", "Total", sum(shapley_values) * 100)
flush(stdout)

# ===================================================================
# Compare to sequential decomposition marginal contributions
# ===================================================================
# Run standard sequential decomposition for comparison
println("\n" * "=" ^ 70)
println("  COMPARISON: SHAPLEY vs SEQUENTIAL DECOMPOSITION")
println("=" ^ 70)
flush(stdout)

decomp = run_decomposition(
    base_surv, population;
    gamma=GAMMA, beta=BETA, r=R_RATE,
    theta=THETA_DFJ, kappa=KAPPA_DFJ,
    c_floor=C_FLOOR,
    mwr_loaded=MWR_LOADED,
    fixed_cost_val=FIXED_COST,
    min_purchase_val=MIN_PURCHASE,
    lambda_w_val=LAMBDA_W,
    inflation_val=INFLATION,
    n_wealth=N_WEALTH, n_annuity=N_ANNUITY, n_alpha=N_ALPHA,
    W_max=W_MAX, n_quad=N_QUAD,
    age_start=AGE_START, age_end=AGE_END,
    annuity_grid_power=A_GRID_POW,
    hazard_mult=HAZARD_MULT,
    survival_pessimism=SURVIVAL_PESSIMISM,
    min_wealth=MIN_WEALTH,
    ss_levels=Float64.(SS_QUARTILE_LEVELS),
    consumption_decline_val=CONSUMPTION_DECLINE,
    health_utility_vals=Float64.(HEALTH_UTILITY),
    verbose=false,
)

# Map decomposition step names to Shapley channel indices.
# The decomposition steps (after Yaari) have names that we match to Shapley channels.
seq_deltas = Dict{Int, Float64}()
decomp_name_to_ch = Dict(
    "+ Social Security" => CH_SS,
    "+ Bequest motives" => CH_BEQUESTS,
    "+ Medical expenditure risk (uncorrelated)" => CH_MEDICAL,
    "+ Health-mortality correlation (R-S)" => CH_RS,
    "+ Survival pessimism" => CH_PESSIMISM,
    "+ State-dependent utility" => CH_HEALTHUTIL,
    "+ Age-varying consumption needs" => CH_AGENEEDS,
    "+ Realistic pricing loads" => CH_LOADS,
    "+ Inflation erosion" => CH_INFLATION,
)
for step in decomp.steps
    ch_id = get(decomp_name_to_ch, step.name, nothing)
    if ch_id !== nothing && haskey(CH_INDEX, ch_id)
        seq_deltas[CH_INDEX[ch_id]] = abs(step.delta)
    end
end

@printf("\n  %-12s  %12s  %12s  %10s\n",
    "Channel", "Shapley (pp)", "Seq (pp)", "Difference")
println("  " * "-" ^ 50)
for i in 1:N_CHANNELS
    seq_val = get(seq_deltas, i, 0.0)
    diff = shapley_values[i] - seq_val
    @printf("  %-12s  %11.1f  %11.1f  %+9.1f\n",
        CHANNEL_NAMES[i],
        shapley_values[i] * 100,
        seq_val * 100,
        diff * 100)
end
flush(stdout)

# ===================================================================
# Save results
# ===================================================================
tables_dir = joinpath(@__DIR__, "..", "tables")
mkpath(joinpath(tables_dir, "csv"))
mkpath(joinpath(tables_dir, "tex"))

# CSV
csv_path = joinpath(tables_dir, "csv", "shapley_decomposition.csv")
open(csv_path, "w") do f
    println(f, "channel,shapley_value,std_dev,min_contribution,max_contribution")
    for i in 1:N_CHANNELS
        @printf(f, "%s,%.6f,%.6f,%.6f,%.6f\n",
            CHANNEL_NAMES[i],
            shapley_values[i],
            shapley_std[i],
            shapley_min[i],
            shapley_max[i])
    end
end
println("\n  CSV saved: $csv_path")
flush(stdout)

# LaTeX table
tex_path = joinpath(tables_dir, "tex", "shapley_decomposition.tex")
open(tex_path, "w") do f
    println(f, raw"\begin{table}[htbp]")
    println(f, raw"\centering")
    println(f, raw"\caption{Shapley-Value Decomposition of Predicted Annuity Ownership}")
    println(f, raw"\label{tab:shapley}")
    println(f, raw"\begin{tabular}{lccccc}")
    println(f, raw"\toprule")
    println(f, "Channel & Shapley (pp) & Std Dev & Min & Max & Share (\\%) \\\\")
    println(f, raw"\midrule")

    for i in 1:N_CHANNELS
        share = total_drop > 0 ? shapley_values[i] / total_drop * 100 : 0.0
        @printf(f, "%s & %.1f & %.1f & %.1f & %.1f & %.1f \\\\\n",
            CHANNEL_NAMES[i],
            shapley_values[i] * 100,
            shapley_std[i] * 100,
            shapley_min[i] * 100,
            shapley_max[i] * 100,
            share)
    end

    println(f, raw"\midrule")
    @printf(f, "Total & %.1f & & & & 100.0 \\\\\n", sum(shapley_values) * 100)
    println(f, raw"\bottomrule")
    println(f, raw"\end{tabular}")
    println(f, raw"\begin{tablenotes}")
    println(f, raw"\small")
    @printf(f, "\\item Shapley values computed from %d random permutations of %d channels.\n",
        N_PERM, N_CHANNELS)
    println(f, "Each value represents the average marginal ownership reduction (pp)")
    println(f, "when the channel is added, averaged across all orderings.")
    @printf(f, "Yaari baseline: %.1f\\%%. Full model: %.1f\\%%.\n",
        yaari_own * 100, full_own * 100)
    println(f, raw"\end{tablenotes}")
    println(f, raw"\end{table}")
end
println("  LaTeX saved: $tex_path")

println("\n" * "=" ^ 70)
println("  SHAPLEY DECOMPOSITION COMPLETE")
println("=" ^ 70)
flush(stdout)
