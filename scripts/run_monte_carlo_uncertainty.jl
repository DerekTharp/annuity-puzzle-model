# Conditional Monte Carlo: Robustness of Baseline Prediction (10-channel model)
#
# Fixes gamma at the baseline and draws all empirically uncertain parameters
# from plausible distributions to show that the headline ownership result
# is robust to joint calibration uncertainty.
#
# Parameter distributions (gamma FIXED at baseline):
#   hazard_poor   ~ U(2.0, 3.5)       (HRS to R-S range)
#   inflation     ~ U(0.015, 0.025)   (near-term CPI uncertainty)
#   MWR           ~ U(0.83, 0.91)     (Mitchell 1999 / Wettstein 2021 range)
#   pessimism psi ~ U(0.97, 1.0)      (O'Dea-Sturrock CI)
#   delta_c       ~ U(0.01, 0.03)     (Aguiar-Hurst sensitivity)
#   psi_purchase  ~ U(0.005, 0.030)   (UK 2015 single-anchor SMM range
#                                      [0.014, 0.028] with modest headroom)
#
# Output: tables/csv/monte_carlo_ownership.csv
#         tables/tex/monte_carlo_summary.tex
#
# Run: julia --project=. -p 32 scripts/run_monte_carlo_uncertainty.jl

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
println("  CONDITIONAL MONTE CARLO: CALIBRATION ROBUSTNESS (10-channel)")
println("  gamma fixed at $GAMMA, joint draws over six nuisance parameters")
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

draws = Vector{NamedTuple{(:hazard_poor, :inflation, :mwr, :pessimism, :delta_c, :psi_purchase), NTuple{6, Float64}}}(undef, N_DRAWS)
for i in 1:N_DRAWS
    hp     = 2.0   + (3.5   - 2.0  ) * rand(rng)
    pi_    = 0.015 + (0.025 - 0.015) * rand(rng)
    m      = 0.83  + (0.91  - 0.83 ) * rand(rng)
    psi    = 0.97  + (1.00  - 0.97 ) * rand(rng)
    dc     = 0.01  + (0.03  - 0.01 ) * rand(rng)
    psi_p  = 0.005 + (0.030 - 0.005) * rand(rng)
    draws[i] = (hazard_poor=hp, inflation=pi_, mwr=m,
                pessimism=psi, delta_c=dc, psi_purchase=psi_p)
end

@printf("\n  Draws: %d (gamma fixed at %.1f)\n", N_DRAWS, GAMMA_FIXED)
for (lab, fn) in [("hazard_poor", d -> d.hazard_poor),
                  ("inflation",   d -> d.inflation),
                  ("MWR",         d -> d.mwr),
                  ("pessimism",   d -> d.pessimism),
                  ("delta_c",     d -> d.delta_c),
                  ("psi_purchase",d -> d.psi_purchase)]
    vals = [fn(d) for d in draws]
    @printf("  %-13s mean=%.3f, range=[%.3f, %.3f]\n",
            lab, mean(vals), minimum(vals), maximum(vals))
end
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
_min_purchase = MIN_PURCHASE
_lambda_w = LAMBDA_W
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

    # Full 10-channel model: rational + age-varying needs + state-dep utility
    # + behavioral purchase friction.
    p_full = ModelParams(; common_kw...,
        theta=_theta, kappa=_kappa,
        mwr=d.mwr, fixed_cost=_fixed_cost, min_purchase=_min_purchase,
        inflation_rate=d.inflation,
        medical_enabled=true, health_mortality_corr=true,
        survival_pessimism=d.pessimism,
        consumption_decline=d.delta_c,
        health_utility=[1.0, 0.90, 0.75],
        lambda_w=_lambda_w,
        psi_purchase=d.psi_purchase,
        grid_kw...)

    sol = solve_lifecycle_health(p_full, grids, _bs, ss_mean_func)
    own_result = compute_ownership_rate_health(sol, _pop, loaded_pr_nom; base_surv=_bs)
    own = own_result.ownership_rate * 100

    (hazard_poor=d.hazard_poor, inflation=d.inflation, mwr=d.mwr,
     pessimism=d.pessimism, delta_c=d.delta_c, psi_purchase=d.psi_purchase,
     ownership_pct=own)
end

elapsed = time() - t0
@printf("\n  Completed %d solves in %.0f seconds (%.1f sec/solve)\n",
    N_DRAWS, elapsed, elapsed / N_DRAWS)
flush(stdout)

# Summary statistics
ownership_vals = [r.ownership_pct for r in results]
sort!(ownership_vals)
n = length(ownership_vals)
q05 = ownership_vals[max(1, round(Int, 0.05 * n))]
q25 = ownership_vals[max(1, round(Int, 0.25 * n))]
med = ownership_vals[div(n, 2)]
q75 = ownership_vals[max(1, round(Int, 0.75 * n))]
q95 = ownership_vals[max(1, round(Int, 0.95 * n))]
frac_1_10 = count(x -> 1.0 <= x <= 10.0, ownership_vals) / n * 100
frac_3_6 = count(x -> 3.0 <= x <= 6.0, ownership_vals) / n * 100

println("\n" * "=" ^ 70)
println("  CONDITIONAL MONTE CARLO RESULTS (gamma = $GAMMA_FIXED)")
println("=" ^ 70)
@printf("\n  Median predicted ownership: %.1f%%\n", med)
@printf("  90%% CI: [%.1f%%, %.1f%%]\n", q05, q95)
@printf("  IQR (50%% CI): [%.1f%%, %.1f%%]\n", q25, q75)
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
    println(f, "gamma,hazard_poor,inflation,mwr,pessimism,delta_c,psi_purchase,ownership_pct")
    for r in results
        @printf(f, "%.1f,%.4f,%.4f,%.4f,%.4f,%.4f,%.4f,%.2f\n",
            GAMMA_FIXED, r.hazard_poor, r.inflation, r.mwr,
            r.pessimism, r.delta_c, r.psi_purchase, r.ownership_pct)
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
    # raw"\\" emits a single backslash (closing-quote rule), so we use a
    # regular escaped string here to write two literal backslashes (LaTeX `\\`).
    println(f, "Statistic & Value \\\\")
    println(f, raw"\midrule")
    @printf(f, "Number of draws & %d %s\n", N_DRAWS, "\\\\")
    @printf(f, "Median predicted ownership & %.1f\\%% %s\n", med, "\\\\")
    @printf(f, "90\\%% CI & [%.1f\\%%, %.1f\\%%] %s\n", q05, q95, "\\\\")
    @printf(f, "Interquartile range (50\\%% CI) & [%.1f\\%%, %.1f\\%%] %s\n", q25, q75, "\\\\")
    @printf(f, "Mean & %.1f\\%% %s\n", sum(ownership_vals) / n, "\\\\")
    @printf(f, "Min / Max & %.1f\\%% / %.1f\\%% %s\n", ownership_vals[1], ownership_vals[end], "\\\\")
    @printf(f, "Fraction in [1\\%%, 10\\%%] & %.0f\\%% %s\n", frac_1_10, "\\\\")
    @printf(f, "Fraction in [3\\%%, 6\\%%] (observed range) & %.0f\\%% %s\n", frac_3_6, "\\\\")
    println(f, raw"\bottomrule")
    println(f, raw"\end{tabular}")
    println(f, raw"\begin{tablenotes}")
    println(f, raw"\small")
    println(f, "\\item Risk aversion fixed at $(ds)\\gamma = $(GAMMA_FIXED)$(ds). Joint draws over six")
    println(f, raw"calibration-uncertain parameters: $\mu_P \sim U(2.0, 3.5)$, $\pi \sim U(0.015, 0.025)$,")
    println(f, raw"MWR $\sim U(0.83, 0.91)$, $\psi \sim U(0.97, 1.0)$, $\delta_c \sim U(0.01, 0.03)$,")
    println(f, raw"$\psi_{\text{purchase}} \sim U(0.30, 1.00)$. Full ten-channel model.")
    println(f, raw"\end{tablenotes}")
    println(f, raw"\end{table}")
end
println("  Summary LaTeX saved: $tex_path")

println("\n" * "=" ^ 70)
println("  CONDITIONAL MONTE CARLO COMPLETE")
println("=" ^ 70)
flush(stdout)
