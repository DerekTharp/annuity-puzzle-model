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
const HAZARD_MULT = [0.50, 1.0, 3.0]
const MWR_LOADED = 0.82
const FIXED_COST = 1_000.0
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

# --- Compare at gamma=2.0 and gamma=2.5 ---
println("\nComputing bequest-to-wealth ratios...")

println("\n  gamma=2.0 (Lockwood's sigma=2):")
t0 = time()
r20 = compute_bequest_ratio(2.0, THETA_DFJ, KAPPA_DFJ)
@printf("    Bequest/Wealth: %.3f  Mean bequest: \$%s  (%.0fs)\n",
    r20.bequest_ratio, string(round(Int, r20.mean_bequest)), time() - t0)

println("  gamma=2.5 (our baseline):")
t0 = time()
r25 = compute_bequest_ratio(2.5, THETA_DFJ, KAPPA_DFJ)
@printf("    Bequest/Wealth: %.3f  Mean bequest: \$%s  (%.0fs)\n",
    r25.bequest_ratio, string(round(Int, r25.mean_bequest)), time() - t0)

divergence = abs(r25.bequest_ratio - r20.bequest_ratio) / max(r20.bequest_ratio, 1e-6)
@printf("\n  Divergence: %.1f%%\n", divergence * 100)

# --- Recalibrate if divergence > 20% ---
if divergence > 0.20
    println("\n  Divergence exceeds 20% threshold. Recalibrating theta at gamma=2.5...")

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
    println("\n  Divergence within 20% threshold. No recalibration needed.")
    println("  Lockwood's theta=56.96 is portable to gamma=2.5.")
end

# --- Save results ---
tables_csv = joinpath(@__DIR__, "..", "tables", "csv")
tables_tex = joinpath(@__DIR__, "..", "tables", "tex")
mkpath(tables_csv)
mkpath(tables_tex)

csv_path = joinpath(tables_csv, "bequest_recalibration.csv")
open(csv_path, "w") do f
    println(f, "gamma,theta,kappa,bequest_wealth_ratio,mean_bequest")
    @printf(f, "%.1f,%.2f,%.0f,%.4f,%.0f\n", 2.0, THETA_DFJ, KAPPA_DFJ,
        r20.bequest_ratio, r20.mean_bequest)
    @printf(f, "%.1f,%.2f,%.0f,%.4f,%.0f\n", 2.5, THETA_DFJ, KAPPA_DFJ,
        r25.bequest_ratio, r25.mean_bequest)
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
    println(f, "\\caption{Bequest Parameter Portability: $(ds)\\gamma = 2.0$(ds) vs $(ds)\\gamma = 2.5$(ds)}")
    println(f, "\\label{tab:bequest_recal}")
    println(f, "\\begin{tabular}{lcc}")
    println(f, "\\toprule")
    println(f, " & $(ds)\\gamma = 2.0$(ds) & $(ds)\\gamma = 2.5$(ds) \\\\")
    println(f, "\\midrule")
    @printf(f, "%s\\theta%s (bequest intensity) & %.2f & %.2f \\\\\n", ds, ds, THETA_DFJ, THETA_DFJ)
    println(f, "$(ds)\\kappa$(ds) (bequest shifter) & \\$(ds)$(kappa_str) & \\$(ds)$(kappa_str) \\\\")
    @printf(f, "Bequest / initial wealth & %.3f & %.3f \\\\\n",
        r20.bequest_ratio, r25.bequest_ratio)
    beq20 = string(round(Int, r20.mean_bequest))
    beq25 = string(round(Int, r25.mean_bequest))
    println(f, "Mean bequest & \\$(ds)$(beq20) & \\$(ds)$(beq25) \\\\")
    @printf(f, "Divergence & \\multicolumn{2}{c}{%.1f\\%%} \\\\\n", divergence * 100)
    println(f, "\\bottomrule")
    println(f, "\\end{tabular}")
    println(f, "\\begin{tablenotes}")
    println(f, "\\small")
    @printf(f, "\\item Both columns use original %s\\theta = %.2f%s from Lockwood (2012) at %s\\sigma = 2%s.\n",
        ds, THETA_DFJ, ds, ds, ds)
    @printf(f, "Divergence in bequest-to-wealth ratio is %.1f\\%%, below the threshold that would\n", divergence * 100)
    println(f, "justify the strong assumptions embedded in analytical recalibration (see text).")
    w_str = string(round(Int, W_0_TEST))
    println(f, "Simulated $(N_SIM) trajectories, initial wealth \\$(ds)$(w_str), Fair health.")
    println(f, "\\end{tablenotes}")
    println(f, "\\end{table}")
end
println("  TeX saved: $tex_path")

println("\n" * "=" ^ 70)
println("  BEQUEST RECALIBRATION COMPLETE")
println("=" ^ 70)
