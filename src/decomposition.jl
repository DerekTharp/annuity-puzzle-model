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
