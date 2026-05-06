# Source-dependent utility (Force A) sensitivity: solve the full 11-channel
# model under multiple lambda_W values to bracket the empirical literature.
#
# Motivation: Blanchett-Finke (2024, 2025) document that retirees spend ~80%
# of guaranteed income but only ~50% of common portfolio benchmarks (e.g., the
# 4% rule). The 50/80 = 0.625 ratio is the implied utility weight on
# portfolio-financed consumption per dollar relative to income-financed
# consumption. This is the production calibration's UPPER BOUND — the raw
# differential conflates SDU with liquidity buffering, mental accounting,
# bequest preservation, tax timing, and adverse-selection internalization.
#
# Netting those channels (each captured separately in this model) yields a
# residual SDU loading of ~0.85 (the production value); sensitivity over the
# defensible range [0.625, 1.0] tests robustness of the headline ownership
# bracket to the lambda_W choice.
#
# Sweep:
#   lambda_w = 0.625  (raw Blanchett-Finke; SDU upper bound)
#   lambda_w = 0.70
#   lambda_w = 0.85   (production: residual after netting other channels)
#   lambda_w = 0.95
#   lambda_w = 1.00   (SDU off; rational + preferences only)
#
# Output: tables/csv/lambda_w_sensitivity.csv (one row per lambda_w value)
# Runtime: ~5 full-model solves; ~25-35 minutes parallel on 32+ vCPU.

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

const CONSUMPTION_DECLINE_ACTIVE = 0.02

const LAMBDA_W_VALUES = [
    ("Raw Blanchett-Finke (50/80, upper bound)", 0.625),
    ("Mid-range",                                0.70),
    ("Production (post-netting residual)",       0.85),
    ("Light SDU",                                0.95),
    ("SDU off (rational + preferences only)",    1.00),
]

const OUT_CSV = joinpath(@__DIR__, "..", "tables", "csv", "lambda_w_sensitivity.csv")

# ---------------------------------------------------------------------------
# Load HRS sample
# ---------------------------------------------------------------------------

println("Loading HRS sample...")
hrs_raw = readdlm(HRS_PATH, ',', Any; skipstart=1)
assert_hrs_schema(hrs_raw, HRS_PATH)
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

pop = population[population[:, 1] .>= MIN_WEALTH, :]
if size(pop, 2) < 4
    pop = hcat(pop, fill(2.0, size(pop, 1)))
end
@printf("  Eligible: %d\n", size(pop, 1))

# ---------------------------------------------------------------------------
# Survival, payout rates, grids (shared across solves)
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
loaded_pr_nom = MWR_LOADED * fair_pr_nom

common_kw = (gamma=GAMMA, beta=BETA, r=R_RATE,
             stochastic_health=true, n_health_states=3, n_quad=N_QUAD,
             c_floor=C_FLOOR, hazard_mult=Float64.(HAZARD_MULT))

p_grid = ModelParams(; common_kw..., mwr=1.0, grid_kw...)
grids = build_grids(p_grid, max(fair_pr, fair_pr_nom))

# ---------------------------------------------------------------------------
# Solve the full 11-channel model at each lambda_w value
# ---------------------------------------------------------------------------

const _common_kw = common_kw
const _grid_kw = grid_kw
const _grids = grids
const _base_surv = base_surv
const _pop = pop
const _loaded_pr_nom = loaded_pr_nom

println("\nDispatching $(length(LAMBDA_W_VALUES)) lambda_W solves across $(max(nworkers(), 1)) workers...")
flush(stdout)
t0_dispatch = time()

results_raw = parallel_solve(LAMBDA_W_VALUES) do (label, lam_val)
    p_model = ModelParams(; _common_kw...,
        theta=THETA_DFJ, kappa=KAPPA_DFJ,
        mwr=MWR_LOADED, fixed_cost=FIXED_COST,
        min_purchase=MIN_PURCHASE,
        inflation_rate=INFLATION,
        medical_enabled=true,
        health_mortality_corr=true,
        survival_pessimism=SURVIVAL_PESSIMISM,
        consumption_decline=CONSUMPTION_DECLINE_ACTIVE,
        health_utility=Float64.(HEALTH_UTILITY),
        lambda_w=lam_val,
        chi_ltc=CHI_LTC,
        psi_purchase=PSI_PURCHASE,
        _grid_kw...)
    t0 = time()
    res = solve_and_evaluate(p_model, _grids, _base_surv,
        Float64.(SS_QUARTILE_LEVELS), _pop, _loaded_pr_nom;
        step_name="", verbose=false)
    return (label=label, lambda_w=lam_val,
            ownership_pct=res.ownership * 100, mean_alpha=res.mean_alpha,
            solve_time=time() - t0)
end
elapsed_dispatch = time() - t0_dispatch
@printf("\nMaster dispatch wall-clock: %.0fs (%.1f min)\n",
        elapsed_dispatch, elapsed_dispatch / 60)

# Sort by lambda_w descending (high to low effect on ownership)
results = sort(results_raw, by = r -> -r.lambda_w)

# ---------------------------------------------------------------------------
# Print and save
# ---------------------------------------------------------------------------

println("\n" * "=" ^ 70)
println("  FORCE A (lambda_W) SENSITIVITY")
println("=" ^ 70)
@printf("\n  %-50s  %8s  %12s  %12s\n",
        "Specification", "lambda_W", "ownership %", "mean alpha")
println("  " * "-" ^ 90)
for r in results
    @printf("  %-50s  %8.3f  %11.2f%%  %12.4f\n",
            r.label, r.lambda_w, r.ownership_pct, r.mean_alpha)
end
println("  " * "-" ^ 90)

mkpath(dirname(OUT_CSV))
open(OUT_CSV, "w") do f
    println(f, "label,lambda_w,ownership_pct,mean_alpha,solve_time")
    for r in results
        @printf(f, "%s,%.4f,%.4f,%.6f,%.1f\n",
                r.label, r.lambda_w, r.ownership_pct, r.mean_alpha, r.solve_time)
    end
end
@printf("\nWrote %s\n", OUT_CSV)
