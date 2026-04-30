# State-dependent utility sensitivity: solve the full 9-channel model under both
# candidate φ(H) mappings and save the ownership predictions.
#
# Motivation: Finkelstein-Luttmer-Notowidigdo (2013) estimate that marginal utility
# of consumption is 10–25% lower in poor health. The literature uses two mappings:
#
#   Raw FLN central:            φ = [1.0, 0.90, 0.75]   (10%/25% reductions)
#   Reichling-Smetters (2015):  φ = [1.0, 0.95, 0.85]   (5%/15% reductions)
#
# Both are defensible. This script solves the full 9-channel model under each so
# the manuscript can report the sensitivity.
#
# Output: tables/csv/state_utility_sensitivity.csv
# Runtime: ~2–5 minutes (2 full-model solves).

using Printf
using DelimitedFiles
using Distributed

# Load module on all workers when running with -p N
if nworkers() > 1
    @everywhere include(joinpath(@__DIR__, "..", "src", "AnnuityPuzzle.jl"))
    @everywhere using .AnnuityPuzzle
else
    include(joinpath(@__DIR__, "..", "src", "AnnuityPuzzle.jl"))
    using .AnnuityPuzzle
end
include(joinpath(@__DIR__, "config.jl"))

const MAPPINGS = [
    ("FLN",             [1.0, 0.90, 0.75]),
    ("ReichlingSmetters",[1.0, 0.95, 0.85]),
]
const CONSUMPTION_DECLINE_ACTIVE = 0.02

const OUT_CSV = joinpath(@__DIR__, "..", "tables", "csv", "state_utility_sensitivity.csv")

# Mirror whatever MWR was used when the production CSVs were generated. We read
# the "Baseline" row of welfare_counterfactuals.csv so results stay comparable
# with the rest of tables/csv/ even if config.jl MWR_LOADED has since drifted.
function csv_baseline_mwr()
    path = joinpath(@__DIR__, "..", "tables", "csv", "welfare_counterfactuals.csv")
    for (i, line) in enumerate(eachline(path))
        i == 1 && continue
        if startswith(line, "Baseline,")
            toks = split(chopprefix(line, "Baseline,"), ',')
            return parse(Float64, toks[1])
        end
    end
    error("welfare_counterfactuals.csv: no Baseline row")
end
const MWR_FOR_RUN = csv_baseline_mwr()
@printf("MWR used for this sensitivity: %.2f  (from welfare_counterfactuals.csv)\n", MWR_FOR_RUN)

# ---------------------------------------------------------------------------
# Load HRS population sample (same filter as run_subset_enumeration.jl)
# ---------------------------------------------------------------------------

println("Loading HRS population sample...")
hrs_raw = readdlm(HRS_PATH, ',', Any; skipstart=1)
n_pop = size(hrs_raw, 1)
population = zeros(n_pop, 4)
population[:, 1] = Float64.(hrs_raw[:, 1])
population[:, 2] .= 0.0
population[:, 3] = Float64.(hrs_raw[:, 3])
if size(hrs_raw, 2) >= 4
    population[:, 4] = Float64.(hrs_raw[:, 4])
else
    population[:, 4] .= 2.0
end
@printf("  Loaded %d individuals\n", n_pop)

# ---------------------------------------------------------------------------
# Payout rates and survival (shared across solves)
# ---------------------------------------------------------------------------

p_base = ModelParams(age_start=AGE_START, age_end=AGE_END)
base_surv = build_lockwood_survival(p_base)

grid_kw = (n_wealth=N_WEALTH, n_annuity=N_ANNUITY, n_alpha=N_ALPHA,
           W_max=W_MAX, age_start=AGE_START, age_end=AGE_END,
           annuity_grid_power=A_GRID_POW)

p_fair = ModelParams(; gamma=GAMMA, beta=BETA, r=R_RATE, mwr=1.0, grid_kw...)
fair_pr = compute_payout_rate(p_fair, base_surv)

p_fair_nom = ModelParams(; gamma=GAMMA, beta=BETA, r=R_RATE, mwr=1.0,
                           inflation_rate=INFLATION, grid_kw...)
fair_pr_nom = compute_payout_rate(p_fair_nom, base_surv)
loaded_pr_nom = MWR_FOR_RUN * fair_pr_nom

# ---------------------------------------------------------------------------
# Filter population to wealth >= MIN_WEALTH
# ---------------------------------------------------------------------------

pop = population[population[:, 1] .>= MIN_WEALTH, :]
if size(pop, 2) < 4
    pop = hcat(pop, fill(2.0, size(pop, 1)))
end
@printf("  Eligible (W >= \$%d): %d\n", round(Int, MIN_WEALTH), size(pop, 1))

# ---------------------------------------------------------------------------
# Solve full 9-channel model under each mapping
# ---------------------------------------------------------------------------

common_kw = (gamma=GAMMA, beta=BETA, r=R_RATE,
             stochastic_health=true, n_health_states=3, n_quad=N_QUAD,
             c_floor=C_FLOOR, hazard_mult=Float64.(HAZARD_MULT))

# Build grids once (fair payout for coverage)
p_grid = ModelParams(; common_kw..., mwr=1.0, grid_kw...)
grids = build_grids(p_grid, max(fair_pr, fair_pr_nom))

# Parallel dispatch — each mapping is an independent full-model solve.
# Capture closures-friendly locals before pmap.
const _su_common_kw = common_kw
const _su_grid_kw = grid_kw
const _su_grids = grids
const _su_base_surv = base_surv
const _su_pop = pop
const _su_loaded_pr_nom = loaded_pr_nom

println("\nDispatching $(length(MAPPINGS)) mapping solves across $(max(nworkers(), 1)) workers...")
flush(stdout)
t0_dispatch = time()

results_raw = parallel_solve(MAPPINGS) do (label, phi)
    p_model = ModelParams(; _su_common_kw...,
        theta=THETA_DFJ, kappa=KAPPA_DFJ,
        mwr=MWR_FOR_RUN, fixed_cost=FIXED_COST,
        min_purchase=MIN_PURCHASE,
        inflation_rate=INFLATION,
        medical_enabled=true,
        health_mortality_corr=true,
        survival_pessimism=SURVIVAL_PESSIMISM,
        consumption_decline=CONSUMPTION_DECLINE_ACTIVE,
        health_utility=phi,
        lambda_w=LAMBDA_W,
        _su_grid_kw...)
    t0 = time()
    res = solve_and_evaluate(p_model, _su_grids, _su_base_surv,
        Float64.(SS_QUARTILE_LEVELS), _su_pop, _su_loaded_pr_nom;
        step_name="", verbose=false)
    return (label=label, phi_good=phi[1], phi_fair=phi[2], phi_poor=phi[3],
            ownership_pct=res.ownership * 100, mean_alpha=res.mean_alpha,
            solve_time=time() - t0)
end
elapsed_dispatch = time() - t0_dispatch
@printf("\nMaster dispatch wall-clock: %.0fs (%.1f min)\n",
        elapsed_dispatch, elapsed_dispatch / 60)

# Render per-spec output in original format
rows = Vector{NamedTuple}()
for r in results_raw
    @printf("\n=== Mapping: %s  φ = [%.2f, %.2f, %.2f] ===\n",
            r.label, r.phi_good, r.phi_fair, r.phi_poor)
    @printf("  Ownership: %.4f%%  |  Mean alpha: %.4f  |  %.1fs\n",
            r.ownership_pct, r.mean_alpha, r.solve_time)
    push!(rows, r)
end

# ---------------------------------------------------------------------------
# Write CSV
# ---------------------------------------------------------------------------

mkpath(dirname(OUT_CSV))
open(OUT_CSV, "w") do f
    println(f, "label,phi_good,phi_fair,phi_poor,ownership_pct,mean_alpha,solve_time")
    for r in rows
        @printf(f, "%s,%.2f,%.2f,%.2f,%.4f,%.6f,%.1f\n",
                r.label, r.phi_good, r.phi_fair, r.phi_poor,
                r.ownership_pct, r.mean_alpha, r.solve_time)
    end
end
@printf("\nWrote %s\n", OUT_CSV)
