# Behavioral channel sensitivity: solve the full 10-channel model under multiple
# values of psi_purchase to bracket the empirical literature.
#
# Calibration anchors are derived from the UK 2015 pension freedoms reform.
# Two evidence streams provide drop-magnitude estimates:
#   - ABI aggregate (75pp total drop): industry data on annuity vs drawdown sales
#   - ELSA microdata (87-89pp total drop): wave 6 (2012-13) pre-freedoms baseline
#     vs waves 8-11 (2016-2024) post-freedoms disposition; n=869 DC pot holders,
#     subgroup-robust across age, sex, education, health.
#
# The "behavioral" anchors strip the rational tax-removal component (~15-25pp)
# from the total drop. ELSA microdata implies a behavioral excess of ~62-74pp
# (vs ABI's 50-60pp), reflecting that aggregate sales data understates the
# decision-level shift in disposition.
#
# Calibration anchors (psi → behavioral-pp via single-moment SMM mapping):
#   psi = 0       : rational benchmark (no behavioral friction)
#   psi = 0.0142  : Anchor C-low  (55pp behavioral)
#   psi = 0.0163  : Anchor C-mid  (60pp behavioral, current production)
#   psi = 0.0194  : Anchor C-high (65pp behavioral)
#   psi = 0.0220  : ELSA strip-low  (~70pp behavioral, microdata-anchored)
#   psi = 0.0240  : ELSA strip-high (~74pp behavioral, microdata-anchored)
#   psi = 0.0281  : Anchor B-low (75pp total drop, ABI aggregate)
#   psi = 0.0335  : ELSA total mid (88pp total drop, microdata)
#   psi = 0.0400+ : above-sensitivity range
#
# Output: tables/csv/psi_sensitivity.csv (one row per psi value)
# Runtime: ~9 full-model solves; ~30-40 minutes parallel on 32+ vCPU.

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
const HEALTH_UTILITY_ACTIVE = [1.0, 0.90, 0.75]

const PSI_VALUES = [
    ("No PED (rational + SDU only)",          0.000),
    ("UK low (55pp behavioral)",              0.0142),  # Anchor C-low (ABI strip)
    ("UK mid (60pp behavioral)",              0.0163),  # Anchor C-mid (production)
    ("UK high (65pp behavioral)",             0.0194),  # Anchor C-high (ABI strip)
    ("UK ELSA strip-low (70pp behavioral)",   0.0220),  # ELSA microdata, low strip
    ("UK ELSA strip-high (74pp behavioral)",  0.0240),  # ELSA microdata, high strip
    ("UK low total (75pp drop)",              0.0281),  # Anchor B-low (ABI aggregate)
    ("UK ELSA total (88pp drop)",             0.0335),  # ELSA microdata total drop
    ("Above sensitivity range",                0.040),
    ("Corner-bound region",                    0.075),
]

const OUT_CSV = joinpath(@__DIR__, "..", "tables", "csv", "psi_sensitivity.csv")

# ---------------------------------------------------------------------------
# Load HRS sample
# ---------------------------------------------------------------------------

println("Loading HRS sample...")
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

# Filter to eligible
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
# Solve the full 10-channel model at each psi value
# ---------------------------------------------------------------------------

# Parallel dispatch — each psi value is an independent full-model solve.
# With N workers, wall-clock is approximately the longest single solve
# (~25 min for the full 10-channel model) instead of N × 25 min serial.
# Capture closures-friendly locals before pmap.
const _common_kw = common_kw
const _grid_kw = grid_kw
const _grids = grids
const _base_surv = base_surv
const _pop = pop
const _loaded_pr_nom = loaded_pr_nom

println("\nDispatching $(length(PSI_VALUES)) psi solves across $(max(nworkers(), 1)) workers...")
flush(stdout)
t0_dispatch = time()

results_raw = parallel_solve(PSI_VALUES) do (label, psi_val)
    p_model = ModelParams(; _common_kw...,
        theta=THETA_DFJ, kappa=KAPPA_DFJ,
        mwr=MWR_LOADED, fixed_cost=FIXED_COST,
        min_purchase=MIN_PURCHASE,
        inflation_rate=INFLATION,
        medical_enabled=true,
        health_mortality_corr=true,
        survival_pessimism=SURVIVAL_PESSIMISM,
        consumption_decline=CONSUMPTION_DECLINE_ACTIVE,
        health_utility=HEALTH_UTILITY_ACTIVE,
        lambda_w=LAMBDA_W,
        psi_purchase=psi_val,
        _grid_kw...)
    t0 = time()
    res = solve_and_evaluate(p_model, _grids, _base_surv,
        Float64.(SS_QUARTILE_LEVELS), _pop, _loaded_pr_nom;
        step_name="", verbose=false)
    return (label=label, psi=psi_val,
            ownership_pct=res.ownership * 100, mean_alpha=res.mean_alpha,
            solve_time=time() - t0)
end
elapsed_dispatch = time() - t0_dispatch
@printf("\nMaster dispatch wall-clock: %.0fs (%.1f min)\n",
        elapsed_dispatch, elapsed_dispatch / 60)

# Render per-spec output in original format
rows = NamedTuple[]
for r in results_raw
    @printf("\n=== psi_purchase = %.2f (%s) ===\n", r.psi, r.label)
    @printf("  Ownership: %.4f%%  |  Mean alpha: %.4f  |  %.1fs\n",
            r.ownership_pct, r.mean_alpha, r.solve_time)
    push!(rows, r)
end

# ---------------------------------------------------------------------------
# Default-architecture analog: rational baseline gives implicit "default" gap
# ---------------------------------------------------------------------------

own_default = rows[1].ownership_pct  # psi=0
println("\n=== Default-architecture analog ===")
@printf("  Ownership at psi=0 (default-annuitize analog):  %.2f%%\n", own_default)
for r in rows[2:end]
    gap = own_default - r.ownership_pct
    @printf("  Default-vs-opt-in gap at psi=%.2f (%s): %+.1f pp\n",
            r.psi, r.label, gap)
end
println("  (Chalmers-Reuter (2012) Oregon PERS gap: 35 pp)")

# ---------------------------------------------------------------------------
# Save CSV
# ---------------------------------------------------------------------------

mkpath(dirname(OUT_CSV))
open(OUT_CSV, "w") do f
    println(f, "label,psi,ownership_pct,mean_alpha,solve_time,default_gap_pp")
    own_def = rows[1].ownership_pct
    for r in rows
        gap = own_def - r.ownership_pct
        @printf(f, "%s,%.4f,%.4f,%.6f,%.1f,%.4f\n",
                r.label, r.psi, r.ownership_pct, r.mean_alpha, r.solve_time, gap)
    end
end
@printf("\nWrote %s\n", OUT_CSV)
