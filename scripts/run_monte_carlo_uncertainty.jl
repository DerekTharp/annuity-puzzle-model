# Conditional Monte Carlo: Robustness of Baseline Prediction
#
# Fixes gamma at 2.5 (baseline) and draws nuisance parameters from
# empirically plausible distributions to show the 3.2% headline result
# is robust to calibration uncertainty in health-mortality correlation,
# inflation, and annuity pricing.
#
# Parameter distributions (gamma FIXED at 2.5):
#   hazard_poor ~ U(2.0, 3.5)     (HRS to R-S range — genuine calibration uncertainty)
#   inflation   ~ U(0.015, 0.025) (near-term CPI uncertainty)
#   MWR         ~ U(0.80, 0.86)   (measurement uncertainty in current pricing)
#
# Output: tables/csv/monte_carlo_ownership.csv
#         tables/tex/monte_carlo_summary.tex
#
# Run: julia --project=. -p 14 scripts/run_monte_carlo_uncertainty.jl

using Printf
using DelimitedFiles
using Random
using Statistics
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
println("  CONDITIONAL MONTE CARLO: CALIBRATION ROBUSTNESS")
println("  gamma fixed at 2.5, varying nuisance parameters")
println("=" ^ 70)
flush(stdout)

# Script-specific parameters
const GAMMA_FIXED = GAMMA
# Coarser grids for speed (convergence verified at these resolutions)
const _NW         = 60
const _NA         = 20
const _NALPHA     = 51
const N_DRAWS     = 1000

# Load HRS population
hrs_path = HRS_PATH
hrs_raw = readdlm(hrs_path, ',', Any; skipstart=1)
n_pop = size(hrs_raw, 1)
population = zeros(n_pop, 4)
population[:, 1] = Float64.(hrs_raw[:, 1])
population[:, 2] .= 0.0  # SS via ss_func, not A grid
population[:, 3] = Float64.(hrs_raw[:, 3])
if size(hrs_raw, 2) >= 4
    population[:, 4] = Float64.(hrs_raw[:, 4])  # observed health (1=Good, 2=Fair, 3=Poor)
else
    population[:, 4] .= 2.0
end

p_base = ModelParams(age_start=AGE_START, age_end=AGE_END)
base_surv = build_lockwood_survival(p_base)

# Draw nuisance parameters (gamma fixed)
rng = Random.MersenneTwister(12345)

draws = Vector{NamedTuple{(:hazard_poor, :inflation, :mwr), NTuple{3, Float64}}}(undef, N_DRAWS)
for i in 1:N_DRAWS
    hp = 2.0 + (3.5 - 2.0) * rand(rng)
    pi = 0.015 + (0.025 - 0.015) * rand(rng)
    m = 0.80 + (0.86 - 0.80) * rand(rng)
    draws[i] = (hazard_poor=hp, inflation=pi, mwr=m)
end

@printf("\n  Draws: %d (gamma fixed at %.1f)\n", N_DRAWS, GAMMA_FIXED)
@printf("  hazard_poor: mean=%.2f, range=[%.2f, %.2f]\n",
    mean(d.hazard_poor for d in draws),
    minimum(d.hazard_poor for d in draws), maximum(d.hazard_poor for d in draws))
@printf("  inflation:   mean=%.3f, range=[%.3f, %.3f]\n",
    mean(d.inflation for d in draws),
    minimum(d.inflation for d in draws), maximum(d.inflation for d in draws))
@printf("  MWR:         mean=%.3f, range=[%.3f, %.3f]\n",
    mean(d.mwr for d in draws),
    minimum(d.mwr for d in draws), maximum(d.mwr for d in draws))
flush(stdout)

# Solve for each draw
println("\nSolving $(N_DRAWS) parameterizations...")
flush(stdout)
t0 = time()

# Pre-filter population
pop_filtered = copy(population)
mask = pop_filtered[:, 1] .>= MIN_WEALTH
pop_filtered = pop_filtered[mask, :]
if size(pop_filtered, 2) < 4
    pop_filtered = hcat(pop_filtered, fill(2.0, size(pop_filtered, 1)))
end

# Capture for closure serialization
_bs = base_surv
_pop = pop_filtered
_gamma = GAMMA_FIXED
_theta = THETA_DFJ
_kappa = KAPPA_DFJ
_beta = BETA
_r = R_RATE
_c_floor = C_FLOOR
_fixed_cost = FIXED_COST
_nw = _NW
_na = _NA
_nalpha = _NALPHA
_wmax = W_MAX
_nq = N_QUAD
_age_s = AGE_START
_age_e = AGE_END
_agp = A_GRID_POW

results = parallel_solve(draws) do d
    _ss_mean_val = sum(SS_QUARTILE_LEVELS) / length(SS_QUARTILE_LEVELS)
    ss_mean_func(age, p) = _ss_mean_val

    hm = [0.50, 1.0, d.hazard_poor]

    grid_kw = (n_wealth=_nw, n_annuity=_na, n_alpha=_nalpha,
               W_max=_wmax, age_start=_age_s, age_end=_age_e,
               annuity_grid_power=_agp)

    common_kw = (gamma=_gamma, beta=_beta, r=_r,
                 stochastic_health=true, n_health_states=3, n_quad=_nq,
                 c_floor=_c_floor, hazard_mult=hm)

    # Nominal loaded payout rate
    p_fair_nom = ModelParams(; gamma=_gamma, beta=_beta, r=_r, mwr=1.0,
                               inflation_rate=d.inflation, grid_kw...)
    fair_pr_nom = compute_payout_rate(p_fair_nom, _bs)
    loaded_pr_nom = d.mwr * fair_pr_nom

    # Build grids
    p_fair = ModelParams(; gamma=_gamma, beta=_beta, r=_r, mwr=1.0, grid_kw...)
    fair_pr = compute_payout_rate(p_fair, _bs)
    grids = build_grids(p_fair, max(fair_pr, fair_pr_nom))

    # Full model (all channels on)
    p_full = ModelParams(; common_kw...,
        theta=_theta, kappa=_kappa,
        mwr=d.mwr, fixed_cost=_fixed_cost, inflation_rate=d.inflation,
        medical_enabled=true, health_mortality_corr=true,
        survival_pessimism=SURVIVAL_PESSIMISM,
        grid_kw...)

    sol = solve_lifecycle_health(p_full, grids, _bs, ss_mean_func)
    own_result = compute_ownership_rate_health(sol, _pop, loaded_pr_nom; base_surv=_bs)
    own = own_result.ownership_rate * 100

    (hazard_poor=d.hazard_poor, inflation=d.inflation,
     mwr=d.mwr, ownership_pct=own)
end

elapsed = time() - t0
@printf("\n  Completed %d solves in %.0f seconds (%.1f sec/solve)\n",
    N_DRAWS, elapsed, elapsed / N_DRAWS)
flush(stdout)

# Summary statistics
ownership_vals = [r.ownership_pct for r in results]
sort!(ownership_vals)
n = length(ownership_vals)
med = ownership_vals[div(n, 2)]
q25 = ownership_vals[max(1, round(Int, 0.25 * n))]
q75 = ownership_vals[max(1, round(Int, 0.75 * n))]
frac_1_10 = count(x -> 1.0 <= x <= 10.0, ownership_vals) / n * 100
frac_3_6 = count(x -> 3.0 <= x <= 6.0, ownership_vals) / n * 100

println("\n" * "=" ^ 70)
println("  CONDITIONAL MONTE CARLO RESULTS (gamma = $GAMMA_FIXED)")
println("=" ^ 70)
@printf("\n  Median predicted ownership: %.1f%%\n", med)
@printf("  IQR: [%.1f%%, %.1f%%]\n", q25, q75)
@printf("  Mean: %.1f%%\n", sum(ownership_vals) / n)
@printf("  Min: %.1f%%, Max: %.1f%%\n", ownership_vals[1], ownership_vals[end])
@printf("  Fraction in [1%%, 10%%]: %.0f%%\n", frac_1_10)
@printf("  Fraction in [3%%, 6%%] (observed range): %.0f%%\n", frac_3_6)
flush(stdout)

# Save CSV
tables_dir = joinpath(@__DIR__, "..", "tables", "csv")
mkpath(tables_dir)
csv_path = joinpath(tables_dir, "monte_carlo_ownership.csv")
open(csv_path, "w") do f
    println(f, "gamma,hazard_poor,inflation,mwr,ownership_pct")
    for r in results
        @printf(f, "%.1f,%.4f,%.4f,%.4f,%.2f\n",
            GAMMA_FIXED, r.hazard_poor, r.inflation, r.mwr, r.ownership_pct)
    end
end
println("\n  Results saved: $csv_path")

# Save summary LaTeX table
ds = '\$'
tex_dir = joinpath(@__DIR__, "..", "tables", "tex")
mkpath(tex_dir)
tex_path = joinpath(tex_dir, "monte_carlo_summary.tex")
open(tex_path, "w") do f
    println(f, raw"\begin{table}[htbp]")
    println(f, raw"\centering")
    println(f, "\\caption{Conditional Monte Carlo: Predicted Ownership at $(ds)\\gamma = $(GAMMA_FIXED)$(ds)}")
    println(f, raw"\label{tab:monte_carlo}")
    println(f, raw"\begin{tabular}{lc}")
    println(f, raw"\toprule")
    println(f, raw"Statistic & Value \\")
    println(f, raw"\midrule")
    @printf(f, "Number of draws & %d %s\n", N_DRAWS, "\\\\")
    @printf(f, "Median predicted ownership & %.1f\\%% %s\n", med, "\\\\")
    @printf(f, "Interquartile range & [%.1f\\%%, %.1f\\%%] %s\n", q25, q75, "\\\\")
    @printf(f, "Mean & %.1f\\%% %s\n", sum(ownership_vals) / n, "\\\\")
    @printf(f, "Min / Max & %.1f\\%% / %.1f\\%% %s\n", ownership_vals[1], ownership_vals[end], "\\\\")
    @printf(f, "Fraction in [1\\%%, 10\\%%] & %.0f\\%% %s\n", frac_1_10, "\\\\")
    @printf(f, "Fraction in [3\\%%, 6\\%%] (observed range) & %.0f\\%% %s\n", frac_3_6, "\\\\")
    println(f, raw"\bottomrule")
    println(f, raw"\end{tabular}")
    println(f, raw"\begin{tablenotes}")
    println(f, raw"\small")
    println(f, "\\item Risk aversion fixed at $(ds)\\gamma = $(GAMMA_FIXED)$(ds). Calibration uncertainty ranges:")
    println(f, raw"$\mu_P \sim U(2.0, 3.5)$, $\pi \sim U(0.015, 0.025)$, MWR $\sim U(0.80, 0.86)$.")
    println(f, raw"\end{tablenotes}")
    println(f, raw"\end{table}")
end
println("  Summary LaTeX saved: $tex_path")

println("\n" * "=" ^ 70)
println("  CONDITIONAL MONTE CARLO COMPLETE")
println("=" ^ 70)
flush(stdout)
