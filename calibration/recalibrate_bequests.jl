# Bequest parameter portability check.
#
# Lockwood (2012) estimated theta=56.96 and kappa=$272,628 at sigma=2.
# We use gamma=2.5 as baseline. This script checks whether the implied
# bequest-to-wealth ratio shifts materially, and if so, recalibrates
# theta at gamma=2.5 to match the same HRS target.
#
# Method: forward simulation with simulate_batch(), comparing mean
# bequest / mean initial wealth across gamma values.

using Printf
using DelimitedFiles
using Optim

include(joinpath(@__DIR__, "..", "src", "AnnuityPuzzle.jl"))
using .AnnuityPuzzle

println("=" ^ 70)
println("  BEQUEST PARAMETER PORTABILITY CHECK")
println("  Lockwood theta=56.96, kappa=\$272,628 at sigma=2 vs gamma=2.5")
println("=" ^ 70)

# Common parameters
const AGE_START  = 65
const AGE_END    = 110
const BETA       = 0.97
const R_RATE     = 0.02
const C_FLOOR    = 6_180.0
const W_MAX      = 3_000_000.0
const N_WEALTH   = 80
const N_ANNUITY  = 30
const N_ALPHA    = 101
const A_GRID_POW = 3.0
const N_QUAD     = 9
const THETA_DFJ  = 56.96
const KAPPA_DFJ  = 272_628.0
const HAZARD_MULT = [0.50, 1.0, 3.75]
const MWR_LOADED = 0.87
const FIXED_COST = 2_500.0
const INFLATION  = 0.02

const W_0_TEST   = 250_000.0  # representative initial wealth
const N_SIM      = 50_000

grid_kw = (n_wealth=N_WEALTH, n_annuity=N_ANNUITY, n_alpha=N_ALPHA,
           W_max=W_MAX, age_start=AGE_START, age_end=AGE_END,
           annuity_grid_power=A_GRID_POW)

p_base = ModelParams(age_start=AGE_START, age_end=AGE_END)
base_surv = build_lockwood_survival(p_base)
ss_zero(age, p) = 0.0

function compute_bequest_ratio(gamma_val, theta_val, kappa_val)
    common_kw = (gamma=gamma_val, beta=BETA, r=R_RATE,
                 stochastic_health=true, n_health_states=3, n_quad=N_QUAD,
                 c_floor=C_FLOOR, hazard_mult=HAZARD_MULT)

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

    # Simulate with no annuity purchase (alpha=0)
    result = simulate_batch(sol, W_0_TEST, 0.0, 2, base_surv, ss_zero, p;
                            n_sim=N_SIM, rng_seed=42)

    bequest_ratio = result.mean_bequest / W_0_TEST
    return (bequest_ratio=bequest_ratio, mean_bequest=result.mean_bequest,
            median_bequest=result.median_bequest)
end

# --- Compare across the full gamma-stability sweep range ---
# The gamma-stability exhibit (run_shapley_gamma_stability.jl) sweeps gamma
# 2.0-3.0 holding theta fixed, so portability must be measured over the same
# range, not just at the production gamma.
const GAMMA_CHECK = [2.0, 2.5, 2.75, 3.0]

println("\nComputing bequest-to-wealth ratios...")
ratios = NamedTuple[]
for g in GAMMA_CHECK
    label = g == 2.0 ? "(Lockwood's sigma=2)" : g == 2.5 ? "(production)" : "(sweep)"
    @printf("\n  gamma=%.2f %s:\n", g, label)
    t0 = time()
    r = compute_bequest_ratio(g, THETA_DFJ, KAPPA_DFJ)
    @printf("    Bequest/Wealth: %.3f  Mean bequest: \$%s  (%.0fs)\n",
        r.bequest_ratio, string(round(Int, r.mean_bequest)), time() - t0)
    push!(ratios, (gamma=g, bequest_ratio=r.bequest_ratio, mean_bequest=r.mean_bequest))
end

base_ratio = ratios[1].bequest_ratio
println("\n  Divergence from gamma=2.0 baseline:")
divs = Float64[]
for r in ratios
    d = abs(r.bequest_ratio - base_ratio) / max(base_ratio, 1e-6)
    push!(divs, d)
    @printf("    gamma=%.2f: %.1f%%\n", r.gamma, d * 100)
end
divergence = divs[2]        # production gamma=2.5 drives the retarget decision
max_divergence = maximum(divs)
r20 = ratios[1]
r25 = ratios[2]

# --- Recalibrate if the PRODUCTION-gamma divergence > 20% ---
if divergence > 0.20
    println("\n  Production divergence exceeds 20% threshold. Recalibrating theta at gamma=2.5...")

    target_ratio = r20.bequest_ratio

    function objective(theta_trial)
        r = compute_bequest_ratio(2.5, theta_trial, KAPPA_DFJ)
        return (r.bequest_ratio - target_ratio)^2
    end

    result = optimize(objective, 1.0, 200.0, Brent())
    theta_recal = Optim.minimizer(result)

    r25_recal = compute_bequest_ratio(2.5, theta_recal, KAPPA_DFJ)
    @printf("\n  Recalibrated theta: %.2f (original: %.2f)\n", theta_recal, THETA_DFJ)
    @printf("  Bequest/Wealth at recalibrated theta: %.3f (target: %.3f)\n",
        r25_recal.bequest_ratio, target_ratio)
else
    println("\n  Production divergence within 20% threshold. No recalibration needed.")
    @printf("  Lockwood's theta=%.2f is portable to gamma=2.5.\n", THETA_DFJ)
end
if max_divergence > 0.20
    @printf("\n  NOTE: drift reaches %.1f%% at the sweep endpoint — past the 20%%\n", max_divergence * 100)
    println("  threshold. The gamma-stability exhibit must caveat that the bequest")
    println("  channel strengthens toward gamma=3.0 rather than claim constancy.")
end

# --- Save results ---
tables_csv = joinpath(@__DIR__, "..", "tables", "csv")
tables_tex = joinpath(@__DIR__, "..", "tables", "tex")
mkpath(tables_csv)
mkpath(tables_tex)

csv_path = joinpath(tables_csv, "bequest_recalibration.csv")
open(csv_path, "w") do f
    println(f, "gamma,theta,kappa,bequest_wealth_ratio,mean_bequest,divergence_vs_gamma20")
    for (r, d) in zip(ratios, divs)
        @printf(f, "%.2f,%.2f,%.0f,%.4f,%.0f,%.4f\n", r.gamma, THETA_DFJ, KAPPA_DFJ,
            r.bequest_ratio, r.mean_bequest, d)
    end
end
println("\n  CSV saved: $csv_path")

tex_path = joinpath(tables_tex, "bequest_recalibration.tex")
ds = '\$'  # LaTeX math delimiter (avoids Julia @printf parse issues)
kappa_str = string(round(Int, KAPPA_DFJ))
# Insert comma: "272628" → "272,628"
if length(kappa_str) > 3
    kappa_str = kappa_str[1:end-3] * "," * kappa_str[end-2:end]
end
open(tex_path, "w") do f
    println(f, "% Generated by calibration/recalibrate_bequests.jl")
    println(f, "\\begin{table}[htbp]")
    println(f, "\\centering")
    println(f, "\\caption{Bequest Parameter Portability Across the Risk-Aversion Sweep}")
    println(f, "\\label{tab:bequest_recal}")
    println(f, "\\begin{tabular}{l" * "c"^length(ratios) * "}")
    println(f, "\\toprule")
    print(f, " ")
    for r in ratios
        @printf(f, "& %s\\gamma = %.2f%s ", ds, r.gamma, ds)
    end
    println(f, "\\\\")
    println(f, "\\midrule")
    print(f, "$(ds)\\theta$(ds) (bequest intensity) ")
    for _ in ratios
        @printf(f, "& %.2f ", THETA_DFJ)
    end
    println(f, "\\\\")
    print(f, "Bequest / initial wealth ")
    for r in ratios
        @printf(f, "& %.3f ", r.bequest_ratio)
    end
    println(f, "\\\\")
    print(f, "Divergence vs $(ds)\\gamma=2.0$(ds) ")
    for d in divs
        @printf(f, "& %.1f\\%% ", d * 100)
    end
    println(f, "\\\\")
    println(f, "\\bottomrule")
    println(f, "\\end{tabular}")
    println(f, "\\begin{tablenotes}")
    println(f, "\\small")
    @printf(f, "\\item All columns use original %s\\theta = %.2f%s, %s\\kappa = \\%s%s%s from\n",
        ds, THETA_DFJ, ds, ds, ds, kappa_str, ds)
    println(f, "Lockwood (2012), estimated at $(ds)\\sigma = 2$(ds). The production calibration")
    @printf(f, "(%s\\gamma = 2.5%s) diverges %.1f\\%%; the sweep endpoint diverges %.1f\\%%.\n",
        ds, ds, divergence * 100, max_divergence * 100)
    w_str = string(round(Int, W_0_TEST))
    println(f, "Simulated $(N_SIM) trajectories, initial wealth \\$(ds)$(w_str), Fair health.")
    println(f, "\\end{tablenotes}")
    println(f, "\\end{table}")
end
println("  TeX saved: $tex_path")

println("\n" * "=" ^ 70)
println("  BEQUEST RECALIBRATION COMPLETE")
println("=" ^ 70)
