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
export load_hrs_population, assert_hrs_schema

"""
    assert_hrs_schema(hrs_raw, path::String="<unknown>")

Strict schema gate for raw HRS sample data. Accepts only:
- 5-column legacy: wealth, perm_income, age, own_life_ann, weight
- 6-column current: wealth, perm_income, age, health, own_life_ann, weight

Raises an error otherwise. Use this in any script that reads the raw HRS
CSV inline (rather than via load_hrs_population). The assertion prevents
the silent-mistake failure mode where `if size(hrs_raw, 2) >= 4` would
mis-assign the 5-col layout's column 4 (ownership indicator) to health.

Returns `has_health::Bool` indicating whether column 4 should be treated
as the health state.
"""
function assert_hrs_schema(hrs_raw::AbstractMatrix, path::String="<unknown>")
    n_cols = size(hrs_raw, 2)
    if !(n_cols == 5 || n_cols == 6)
        error("HRS CSV at $path has $n_cols columns; expected 5 (legacy: " *
              "wealth, perm_income, age, own_life_ann, weight) or 6 (current: " *
              "wealth, perm_income, age, health, own_life_ann, weight). Refusing " *
              "to silently mis-assign columns.")
    end
    return n_cols == 6  # has_health
end

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

Strict schema enforcement: only 5-column legacy
    (wealth, perm_income, age, own_life_ann, weight)
or 6-column current
    (wealth, perm_income, age, health, own_life_ann, weight)
layouts are accepted. Any other column count errors out. This prevents the
silent-mistake failure mode where an analysis script using
`if size(hrs_raw, 2) >= 4 then column 4 = health` would mis-assign the
ownership indicator (column 4 in the 5-col layout) to the health column.
"""
function load_hrs_population(path::String; zero_ss::Bool=true, min_wealth::Float64=0.0)
    hrs_raw = readdlm(path, ',', Any; skipstart=1)
    n_pop = size(hrs_raw, 1)
    n_cols_raw = size(hrs_raw, 2)

    # Strict schema gate.
    if !(n_cols_raw == 5 || n_cols_raw == 6)
        error("HRS CSV at $path has $n_cols_raw columns; expected 5 (legacy: " *
              "wealth, perm_income, age, own_life_ann, weight) or 6 (current: " *
              "wealth, perm_income, age, health, own_life_ann, weight). Refusing " *
              "to silently mis-assign columns.")
    end

    # Detect CSV layout by column count:
    #   5 cols: wealth, perm_income, age, own_life_ann, weight (legacy)
    #   6 cols: wealth, perm_income, age, health, own_life_ann, weight (current)
    has_health = n_cols_raw >= 6

    n_out = has_health ? 4 : 3
    population = zeros(n_pop, n_out)
    population[:, 1] = Float64.(hrs_raw[:, 1])                          # wealth
    population[:, 2] = zero_ss ? zeros(n_pop) : Float64.(hrs_raw[:, 2]) # perm_income / A
    population[:, 3] = Float64.(hrs_raw[:, 3])                          # age
    if has_health
        population[:, 4] = Float64.(hrs_raw[:, 4])                      # health (1/2/3)
        # Validate health values are in expected range.
        h_vals = unique(population[:, 4])
        bad = setdiff(h_vals, [1.0, 2.0, 3.0])
        if !isempty(bad)
            error("HRS CSV health column contains values outside {1,2,3}: $bad. " *
                  "Expected: 1=Good, 2=Fair, 3=Poor. Refusing to proceed.")
        end
    end

    if min_wealth > 0.0
        mask = population[:, 1] .>= min_wealth
        population = population[mask, :]
    end
    return population
end

end
