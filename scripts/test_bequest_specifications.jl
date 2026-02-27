# Test alternative bequest specifications.
#
# The DFJ luxury-good specification (kappa=$272K) makes bequests irrelevant
# for middle-class households. This script tests whether alternative kappa
# values change the decomposition story.
#
# For each kappa, theta is calibrated via simulation to match the DFJ
# bequest-to-wealth ratio (~17%), then the full decomposition is run.

using Printf
using DelimitedFiles
using Optim

include(joinpath(@__DIR__, "..", "src", "AnnuityPuzzle.jl"))
using .AnnuityPuzzle

println("=" ^ 70)
println("  BEQUEST SPECIFICATION SENSITIVITY ANALYSIS")
println("=" ^ 70)

# Common parameters (matching production run_decomposition.jl)
const AGE_START  = 65
const AGE_END    = 110
const BETA       = 0.97
const R_RATE     = 0.02
const C_FLOOR    = 6_180.0
const W_MAX      = 3_000_000.0
const MWR_LOADED = 0.82
const FIXED_COST = 1_000.0
const INFLATION  = 0.02
const HAZARD_MULT = [0.50, 1.0, 3.0]
const N_QUAD      = 9
const MIN_WEALTH = 5_000.0
const SURVIVAL_PESSIMISM = 0.981
const SS_LEVELS  = SS_QUARTILE_LEVELS

# Coarser grid for speed (convergence verified at these levels)
const N_WEALTH   = 60
const N_ANNUITY  = 20
const N_ALPHA    = 51
const A_GRID_POW = 3.0

const GAMMA      = 2.5
const THETA_DFJ  = 56.96
const KAPPA_DFJ  = 272_628.0
# Use Lockwood's original theta at all gamma values (no recalibration)

# Load HRS population
hrs_path = joinpath(@__DIR__, "..", "data", "processed", "lockwood_hrs_sample.csv")
hrs_raw = readdlm(hrs_path, ',', Any; skipstart=1)
n_pop = size(hrs_raw, 1)
population = zeros(n_pop, 4)
population[:, 1] = Float64.(hrs_raw[:, 1])
population[:, 2] .= 0.0                      # SS via ss_func, not A grid
population[:, 3] = Float64.(hrs_raw[:, 3])
if size(hrs_raw, 2) >= 4
    population[:, 4] = Float64.(hrs_raw[:, 4])  # observed health (1=Good, 2=Fair, 3=Poor)
else
    population[:, 4] .= 2.0
end

p_base = ModelParams(age_start=AGE_START, age_end=AGE_END)
base_surv = build_lockwood_survival(p_base)

grid_kw = (n_wealth=N_WEALTH, n_annuity=N_ANNUITY, n_alpha=N_ALPHA,
           W_max=W_MAX, age_start=AGE_START, age_end=AGE_END,
           annuity_grid_power=A_GRID_POW)

common_kw = (gamma=GAMMA, beta=BETA, r=R_RATE,
             stochastic_health=true, n_health_states=3, n_quad=N_QUAD,
             c_floor=C_FLOOR, hazard_mult=HAZARD_MULT)

ss_zero(age, p) = 0.0

# ===================================================================
# Step 1: Compute DFJ baseline bequest-to-wealth ratio
# ===================================================================
println("\n--- Step 1: DFJ baseline bequest-to-wealth ratio ---\n")

const W_0_TEST = 250_000.0
const N_SIM    = 20_000  # enough for stable ratios

function compute_bequest_ratio(theta_val, kappa_val)
    p = ModelParams(; common_kw...,
        theta=theta_val, kappa=kappa_val,
        mwr=MWR_LOADED, fixed_cost=FIXED_COST, inflation_rate=INFLATION,
        medical_enabled=true, health_mortality_corr=true,
        grid_kw...)

    p_fair = ModelParams(; common_kw..., mwr=1.0,
        inflation_rate=INFLATION, grid_kw...)
    pr = compute_payout_rate(p_fair, base_surv)
    grids = build_grids(p_fair, pr)

    sol = solve_lifecycle_health(p, grids, base_surv, ss_zero)
    result = simulate_batch(sol, W_0_TEST, 0.0, 2, base_surv, ss_zero, p;
                            n_sim=N_SIM, rng_seed=42)
    return result.mean_bequest / W_0_TEST
end

t0 = time()
dfj_ratio = compute_bequest_ratio(THETA_DFJ, KAPPA_DFJ)
@printf("  DFJ (theta=%.1f, kappa=\$%s): bequest/wealth = %.3f  (%.0fs)\n",
    THETA_DFJ, string(round(Int, KAPPA_DFJ)), dfj_ratio, time() - t0)

# ===================================================================
# Step 2: Calibrate theta at alternative kappa values
# ===================================================================
println("\n--- Step 2: Calibrate theta at alternative kappa values ---\n")

target_ratio = dfj_ratio
kappa_tests = [100_000.0, 50_000.0, 25_000.0, 10_000.0, 0.0]

calibrated_specs = [(theta=THETA_DFJ, kappa=KAPPA_DFJ, label="DFJ luxury (\$272K)")]

for kappa_new in kappa_tests
    @printf("  Calibrating theta for kappa=\$%s (target ratio=%.3f)...\n",
        string(round(Int, kappa_new)), target_ratio)

    # Starting guess from MRS matching formula
    b_ref = target_ratio * W_0_TEST
    theta_guess = THETA_DFJ * ((b_ref + KAPPA_DFJ) / (b_ref + kappa_new))^GAMMA

    # Bounded search
    theta_lo = max(1.0, theta_guess * 0.1)
    theta_hi = min(50_000.0, theta_guess * 10.0)

    function objective(theta_trial)
        r = compute_bequest_ratio(theta_trial, kappa_new)
        return (r - target_ratio)^2
    end

    t0 = time()
    result = optimize(objective, theta_lo, theta_hi, Brent();
                      rel_tol=0.05, abs_tol=0.01)
    theta_cal = Optim.minimizer(result)
    ratio_check = compute_bequest_ratio(theta_cal, kappa_new)

    @printf("    theta=%.1f, bequest/wealth=%.3f (target=%.3f, %.0fs)\n",
        theta_cal, ratio_check, target_ratio, time() - t0)

    label = "\$$(string(round(Int, kappa_new/1000)))K"
    push!(calibrated_specs, (theta=theta_cal, kappa=kappa_new, label=label))
end

# ===================================================================
# Step 3: Run decomposition with each specification
# ===================================================================
println("\n--- Step 3: Decomposition with each bequest specification ---\n")

results = []

for spec in calibrated_specs
    @printf("\n  === Bequest spec: %s (theta=%.1f, kappa=\$%s) ===\n",
        spec.label, spec.theta, string(round(Int, spec.kappa)))

    decomp = run_decomposition(
        base_surv, population;
        gamma=GAMMA, beta=BETA, r=R_RATE,
        theta=spec.theta, kappa=spec.kappa,
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

    step_rates = [s.ownership_rate * 100 for s in decomp.steps]
    push!(results, (spec=spec, rates=step_rates, decomp=decomp))
end

# ===================================================================
# Summary comparison
# ===================================================================
println("\n" * "=" ^ 70)
println("  COMPARISON: BEQUEST SPECIFICATION SENSITIVITY")
println("=" ^ 70)

step_names = ["Yaari", "+ SS", "+ Bequests", "+ Medical", "+ R-S", "+ Pessimism", "+ Loads", "+ Inflation"]

# Header
@printf("\n  %-20s", "Step")
for r in results
    @printf("  %12s", r.spec.label)
end
println()
println("  " * "-" ^ (20 + 14 * length(results)))

# Data rows
for (i, name) in enumerate(step_names)
    @printf("  %-20s", name)
    for r in results
        @printf("  %11.1f%%", r.rates[i])
    end
    println()
end

# Bequest step contribution (step 3 = "+ Bequests", step 2 = "+ SS")
println()
@printf("  %-20s", "Bequest effect (pp)")
for r in results
    beq_effect = r.rates[3] - r.rates[2]
    @printf("  %+11.1f pp", beq_effect)
end
println()

@printf("  %-20s", "Full model effect (pp)")
for r in results
    full_effect = r.rates[end] - r.rates[1]
    @printf("  %+11.1f pp", full_effect)
end
println()

# Bequest share of total reduction
println()
@printf("  %-20s", "Bequest share (%)")
for r in results
    beq_eff = r.rates[3] - r.rates[2]
    total_eff = r.rates[end] - r.rates[1]
    share = total_eff != 0 ? (beq_eff / total_eff) * 100 : 0
    @printf("  %11.1f%%", share)
end
println()

# Full-model bequest contribution (with bequests vs without)
println("\n  Full-model bequest contribution (no-bequest rate - full rate):")
@printf("  %-20s", "Spec")
for r in results
    no_beq_rate = results[1].rates[end]  # all specs share the no-bequest baseline
    full_rate = r.rates[end]
    @printf("  %+11.1f pp", no_beq_rate - full_rate)
end
println()

# ===================================================================
# Wealth distribution context
# ===================================================================
println("\n--- HRS wealth distribution context ---")
wealth = population[:, 1]
mask = wealth .>= MIN_WEALTH
w_filt = wealth[mask]
sort!(w_filt)
n_f = length(w_filt)
@printf("  N (W >= \$%s): %d\n", string(round(Int, MIN_WEALTH)), n_f)
@printf("  Median wealth: \$%s\n", string(round(Int, w_filt[div(n_f,2)])))
@printf("  25th pctile:   \$%s\n", string(round(Int, w_filt[max(1,round(Int,0.25*n_f))])))
@printf("  75th pctile:   \$%s\n", string(round(Int, w_filt[max(1,round(Int,0.75*n_f))])))

for spec in calibrated_specs
    frac_above = count(w .> spec.kappa for w in w_filt) / n_f * 100
    @printf("  Fraction with W > kappa (\$%s): %.1f%%\n",
        string(round(Int, spec.kappa)), frac_above)
end

# ===================================================================
# Save results
# ===================================================================
tables_dir = joinpath(@__DIR__, "..", "tables", "csv")
mkpath(tables_dir)
csv_path = joinpath(tables_dir, "bequest_specification_sensitivity.csv")
open(csv_path, "w") do f
    println(f, "kappa,theta,step,ownership_pct")
    for r in results
        for (i, step) in enumerate(r.decomp.steps)
            @printf(f, "%.0f,%.2f,%s,%.2f\n",
                r.spec.kappa, r.spec.theta, step.name, step.ownership_rate * 100)
        end
    end
end
println("\n  Results saved: $csv_path")

println("\n" * "=" ^ 70)
println("  BEQUEST SPECIFICATION ANALYSIS COMPLETE")
println("=" ^ 70)
