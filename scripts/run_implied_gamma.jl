# Implied Gamma Monte Carlo
#
# Instead of drawing gamma and reporting ownership (which produces a
# wide distribution driven by gamma sensitivity), flip the question:
# for each draw of (hazard_poor, inflation, MWR), find the gamma that
# matches 3.6% observed ownership via bisection.
#
# This converts the gamma sensitivity from a weakness into a finding:
# "what risk aversion is implied by observed behavior, given parameter
# uncertainty in other channels?"
#
# Parameter distributions (excluding gamma):
#   hazard_poor ~ U(2.0, 3.5)    (HRS to R-S range)
#   inflation   ~ U(0.01, 0.03)  (plausible Fed target range)
#   MWR         ~ U(0.75, 0.89)  (recentered at 0.82; Mitchell 1999)
#
# Output: tables/csv/implied_gamma.csv

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
println("  IMPLIED GAMMA MONTE CARLO")
println("  Bisect gamma to match 3.6% observed ownership")
println("=" ^ 70)
flush(stdout)

# ===================================================================
# Script-specific parameters
# ===================================================================
# Coarser grids for speed (convergence verified at these resolutions)
const _NW         = 60
const _NA         = 20
const _NALPHA     = 51
const SURV_PESSIMISM = SURVIVAL_PESSIMISM
const TARGET_OWN  = 0.036      # Lockwood (2012) observed ownership
const GAMMA_LO    = 1.5
const GAMMA_HI    = 5.0
const GAMMA_TOL   = 0.01       # bisection tolerance on gamma
const N_DRAWS     = 300

# ===================================================================
# Load HRS population sample
# ===================================================================
hrs_path = HRS_PATH
hrs_raw = readdlm(hrs_path, ',', Any; skipstart=1)
n_pop = size(hrs_raw, 1)
population = zeros(n_pop, 4)
population[:, 1] = Float64.(hrs_raw[:, 1])
population[:, 2] .= 0.0   # SS via ss_func, not A grid
population[:, 3] = Float64.(hrs_raw[:, 3])
if size(hrs_raw, 2) >= 4
    population[:, 4] = Float64.(hrs_raw[:, 4])  # observed health (1=Good, 2=Fair, 3=Poor)
else
    population[:, 4] .= 2.0
end

# Pre-filter population
pop_filtered = copy(population)
mask = pop_filtered[:, 1] .>= MIN_WEALTH
pop_filtered = pop_filtered[mask, :]
if size(pop_filtered, 2) < 4
    pop_filtered = hcat(pop_filtered, fill(2.0, size(pop_filtered, 1)))
end

# Survival probabilities
p_base = ModelParams(age_start=AGE_START, age_end=AGE_END)
base_surv = build_lockwood_survival(p_base)

@printf("  Population: %d total, %d eligible (W >= \$%s)\n",
    n_pop, size(pop_filtered, 1), string(round(Int, MIN_WEALTH)))
flush(stdout)

# ===================================================================
# Draw parameter vectors (everything except gamma)
# ===================================================================
rng = Random.MersenneTwister(54321)

draws = Vector{NamedTuple{(:hazard_poor, :inflation, :mwr), NTuple{3, Float64}}}(undef, N_DRAWS)
for i in 1:N_DRAWS
    hp = 2.0 + (3.5 - 2.0) * rand(rng)
    pi = 0.01 + (0.03 - 0.01) * rand(rng)
    m  = 0.75 + (0.89 - 0.75) * rand(rng)
    draws[i] = (hazard_poor=hp, inflation=pi, mwr=m)
end

@printf("\n  Draws: %d\n", N_DRAWS)
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

# ===================================================================
# Solve: bisect gamma for each draw
# ===================================================================
println("\nSolving $(N_DRAWS) draws via bisection...")
flush(stdout)
t0 = time()

# Capture references for closure serialization
_bs = base_surv
_pop = pop_filtered
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
_psi = SURV_PESSIMISM
_target = TARGET_OWN
_glo = GAMMA_LO
_ghi = GAMMA_HI
_gtol = GAMMA_TOL

results = parallel_solve(draws) do d
    # Mean SS across quartiles (avoids 4x per-quartile solving overhead)
    _ss_mean_val = sum(SS_QUARTILE_LEVELS) / length(SS_QUARTILE_LEVELS)
    ss_mean_func(age, p) = _ss_mean_val

    # Solve ownership at a given gamma
    function _solve_own(gamma)
        hm = [0.50, 1.0, d.hazard_poor]

        grid_kw = (n_wealth=_nw, n_annuity=_na, n_alpha=_nalpha,
                   W_max=_wmax, age_start=_age_s, age_end=_age_e,
                   annuity_grid_power=_agp)

        common_kw = (gamma=gamma, beta=_beta, r=_r,
                     stochastic_health=true, n_health_states=3, n_quad=_nq,
                     c_floor=_c_floor, hazard_mult=hm)

        p_fair_nom = ModelParams(; gamma=gamma, beta=_beta, r=_r, mwr=1.0,
                                   inflation_rate=d.inflation, grid_kw...)
        fair_pr_nom = compute_payout_rate(p_fair_nom, _bs)
        loaded_pr_nom = d.mwr * fair_pr_nom

        p_fair = ModelParams(; gamma=gamma, beta=_beta, r=_r, mwr=1.0, grid_kw...)
        fair_pr = compute_payout_rate(p_fair, _bs)
        grids = build_grids(p_fair, max(fair_pr, fair_pr_nom))

        p_full = ModelParams(; common_kw...,
            theta=_theta, kappa=_kappa,
            mwr=d.mwr, fixed_cost=_fixed_cost, min_purchase=_min_purchase,
            inflation_rate=d.inflation,
            medical_enabled=true, health_mortality_corr=true,
            survival_pessimism=_psi,
            lambda_w=_lambda_w,
            grid_kw...)

        sol = solve_lifecycle_health(p_full, grids, _bs, ss_mean_func)
        result = compute_ownership_rate_health(sol, _pop, loaded_pr_nom; base_surv=_bs)
        return result.ownership_rate
    end

    # Bisection: find gamma such that ownership(gamma, d) ≈ target
    lo = _glo
    hi = _ghi
    n_iter = 0

    own_hi = _solve_own(hi)
    n_iter += 1
    if own_hi < _target
        return (hazard_poor=d.hazard_poor, inflation=d.inflation, mwr=d.mwr,
                implied_gamma=hi, converged=false, n_iter=n_iter)
    end

    own_lo = _solve_own(lo)
    n_iter += 1
    if own_lo > _target
        return (hazard_poor=d.hazard_poor, inflation=d.inflation, mwr=d.mwr,
                implied_gamma=lo, converged=false, n_iter=n_iter)
    end

    while (hi - lo) > _gtol
        mid = (lo + hi) / 2.0
        own_mid = _solve_own(mid)
        n_iter += 1

        if own_mid > _target
            hi = mid
        else
            lo = mid
        end

        if n_iter >= 30
            break
        end
    end

    implied_gamma = (lo + hi) / 2.0
    return (hazard_poor=d.hazard_poor, inflation=d.inflation, mwr=d.mwr,
            implied_gamma=implied_gamma, converged=true, n_iter=n_iter)
end

elapsed = time() - t0
@printf("\n  Completed %d draws in %.0f seconds (%.1f sec/draw)\n",
    N_DRAWS, elapsed, elapsed / N_DRAWS)
flush(stdout)

# ===================================================================
# Summary statistics
# ===================================================================
converged = filter(r -> r.converged, results)
n_conv = length(converged)
n_total = length(results)

gammas = [r.implied_gamma for r in converged]
sort!(gammas)

if n_conv > 0
    med = gammas[max(1, div(n_conv, 2))]
    q25 = gammas[max(1, round(Int, 0.25 * n_conv))]
    q75 = gammas[max(1, round(Int, 0.75 * n_conv))]
    mn = sum(gammas) / n_conv
    frac_chetty = count(g -> 1.5 <= g <= 3.0, gammas) / n_conv * 100
    frac_narrow = count(g -> 2.0 <= g <= 2.5, gammas) / n_conv * 100

    println("\n" * "=" ^ 70)
    println("  IMPLIED GAMMA RESULTS")
    println("=" ^ 70)
    @printf("\n  Converged: %d / %d (%.0f%%)\n", n_conv, n_total, n_conv / n_total * 100)
    @printf("  Median implied gamma: %.2f\n", med)
    @printf("  Mean implied gamma:   %.2f\n", mn)
    @printf("  IQR: [%.2f, %.2f]\n", q25, q75)
    @printf("  Min: %.2f, Max: %.2f\n", gammas[1], gammas[end])
    @printf("  Fraction in [1.5, 3.0] (Chetty 2006 range): %.0f%%\n", frac_chetty)
    @printf("  Fraction in [2.0, 2.5] (narrow range):      %.0f%%\n", frac_narrow)
    flush(stdout)
else
    println("\n  WARNING: No draws converged!")
    flush(stdout)
end

# ===================================================================
# Save CSV
# ===================================================================
tables_dir = joinpath(@__DIR__, "..", "tables", "csv")
mkpath(tables_dir)

csv_path = joinpath(tables_dir, "implied_gamma.csv")
open(csv_path, "w") do f
    println(f, "hazard_poor,inflation,mwr,implied_gamma,converged,n_iter")
    for r in results
        @printf(f, "%.4f,%.4f,%.4f,%.4f,%s,%d\n",
            r.hazard_poor, r.inflation, r.mwr, r.implied_gamma,
            r.converged ? "true" : "false", r.n_iter)
    end
end
println("\n  Results saved: $csv_path")
flush(stdout)

# ===================================================================
# Save summary LaTeX table
# ===================================================================
if n_conv > 0
    tex_dir = joinpath(@__DIR__, "..", "tables", "tex")
    mkpath(tex_dir)
    tex_path = joinpath(tex_dir, "implied_gamma.tex")
    open(tex_path, "w") do f
        println(f, raw"\begin{table}[htbp]")
        println(f, raw"\centering")
        println(f, raw"\caption{Implied Risk Aversion from Monte Carlo Parameter Uncertainty}")
        println(f, raw"\label{tab:implied_gamma}")
        println(f, raw"\begin{tabular}{lc}")
        println(f, raw"\toprule")
        println(f, "Statistic & Value \\\\")
        println(f, raw"\midrule")
        println(f, "Number of draws & $n_conv \\\\")
        println(f, "Target ownership & $(round(TARGET_OWN * 100, digits=1))\\% \\\\")
        println(f, "Median implied \$\\gamma\$ & $(round(med, digits=2)) \\\\")
        println(f, "Mean implied \$\\gamma\$ & $(round(mn, digits=2)) \\\\")
        println(f, "Interquartile range & [$(round(q25, digits=2)), $(round(q75, digits=2))] \\\\")
        println(f, "Min / Max & $(round(gammas[1], digits=2)) / $(round(gammas[end], digits=2)) \\\\")
        println(f, "Fraction in [1.5, 3.0] & $(round(Int, frac_chetty))\\% \\\\")
        println(f, raw"\bottomrule")
        println(f, raw"\end{tabular}")
        println(f, raw"\begin{tablenotes}")
        println(f, raw"\small")
        println(f, raw"\item For each draw of nuisance parameters ($\mu_P$, $\pi$, MWR),")
        println(f, raw"we bisect over $\gamma$ to find the value that generates 3.6\%")
        println(f, raw"predicted ownership (Lockwood 2012 observed rate).")
        println(f, raw"Draws: $\mu_P \sim U(2.0, 3.5)$, $\pi \sim U(0.01, 0.03)$, MWR $\sim U(0.75, 0.89)$.")
        println(f, raw"Survival pessimism $\psi = 0.981$ (O'Dea \& Sturrock 2023).")
        println(f, raw"\end{tablenotes}")
        println(f, raw"\end{table}")
    end
    println("  Summary LaTeX saved: $tex_path")
    flush(stdout)
end

println("\n" * "=" ^ 70)
println("  IMPLIED GAMMA COMPLETE")
println("=" ^ 70)
flush(stdout)
