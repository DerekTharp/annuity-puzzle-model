# Social Security Benefit Cut Robustness Analysis
#
# Computes predicted private annuity demand under varying magnitudes
# of Social Security benefit reductions. The structural model (rational +
# preference + structural chi_ltc; behavioral SDU/PED off) is solved at each
# cut level. A trust-fund shortfall cuts SS only; DB pension income survives.
#
# Cut sizes: 0% (baseline), 10%, 15%, 22% (trust fund), 30%, 40%, 50%, 100%
#
# Usage: julia --project=. -p 8 scripts/run_ss_robustness.jl

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

println("=" ^ 70)
println("  SOCIAL SECURITY BENEFIT CUT ROBUSTNESS ANALYSIS")
println("  Private Annuity Demand Response to SS Reductions")
println("=" ^ 70)
flush(stdout)

# ===================================================================
# Load HRS population sample
# ===================================================================
println("\nLoading HRS population sample...")
flush(stdout)
population = load_hrs_population(HRS_PATH; zero_ss=true)  # SS via ss_func, not A grid
n_pop = size(population, 1)
@printf("  Loaded %d individuals\n", n_pop)
flush(stdout)

# ===================================================================
# Build survival probabilities
# ===================================================================
p_base = ModelParams(age_start=AGE_START, age_end=AGE_END)
base_surv = production_base_survival(p_base)

# Pre-compute payout rates
grid_kw = (n_wealth=N_WEALTH, n_annuity=N_ANNUITY, n_alpha=N_ALPHA,
           W_max=W_MAX, age_start=AGE_START, age_end=AGE_END,
           annuity_grid_power=A_GRID_POW)

common_kw = (gamma=GAMMA, beta=BETA, r=R_RATE,
             stochastic_health=true, n_health_states=3, n_quad=N_QUAD,
             c_floor=C_FLOOR, hazard_mult=HAZARD_MULT, hazard_normalize=HAZARD_NORMALIZE)

p_fair = ModelParams(; common_kw..., mwr=1.0, grid_kw...)
fair_pr = compute_payout_rate(p_fair, base_surv)

p_fair_nom = ModelParams(; common_kw..., mwr=1.0,
                           inflation_rate=INFLATION, grid_kw...)
fair_pr_nom = INFLATION > 0 ? compute_payout_rate(p_fair_nom, base_surv) : fair_pr

# Loaded nominal payout rate (full model uses inflation + loads)
loaded_pr_nom = MWR_LOADED * fair_pr_nom

# Build grids (shared across all cut levels)
grids = build_grids(p_fair, max(fair_pr, fair_pr_nom))

@printf("  Loaded payout rate (MWR=%.2f, infl=%.0f%%): %.4f\n",
    MWR_LOADED, INFLATION * 100, loaded_pr_nom)
flush(stdout)

# ===================================================================
# Define SS cut levels
# ===================================================================
cut_fractions = [0.0, 0.10, 0.15, 0.22, 0.30, 0.40, 0.50, 1.0]

@printf("\n  Pre-existing income SS+DB (baseline): [%s]\n",
    join([@sprintf("\$%.0fK", l / 1000) for l in SS_QUARTILE_LEVELS], ", "))
@printf("  SS cut hits SS only; DB survives. SS=[%s] DB=[%s]\n",
    join([@sprintf("\$%.0fK", l / 1000) for l in SS_OBS], ", "),
    join([@sprintf("\$%.0fK", l / 1000) for l in DB_OBS], ", "))
flush(stdout)

# ===================================================================
# Solve each cut level (parallelized)
# ===================================================================
println("\nSolving full model at each SS cut level...")
flush(stdout)

# Capture for closures (explicit local variables for pmap serialization)
_population = population
_base_surv = base_surv
_ss_q_levels = Float64.(SS_QUARTILE_LEVELS)
_ss_obs = Float64.(SS_OBS)
_db_obs = Float64.(DB_OBS)
_min_wealth = MIN_WEALTH
_gamma = GAMMA
_beta = BETA
_r_rate = R_RATE
_n_quad = N_QUAD
_c_floor = C_FLOOR
_hazard_mult=Float64.(HAZARD_MULT); _hazard_normalize=HAZARD_NORMALIZE
_theta_dfj = THETA_DFJ
_kappa_dfj = KAPPA_DFJ
_mwr_loaded = MWR_LOADED
_fixed_cost = FIXED_COST
_min_purchase = MIN_PURCHASE
_consumption_decline = CONSUMPTION_DECLINE
_health_utility = Float64.(HEALTH_UTILITY)
_chi_ltc = CHI_LTC
_inflation = INFLATION
_surv_pess = SURVIVAL_PESSIMISM
_n_wealth = N_WEALTH
_n_annuity = N_ANNUITY
_n_alpha = N_ALPHA
_w_max = W_MAX
_age_start = AGE_START
_age_end = AGE_END
_a_grid_pow = A_GRID_POW

t0 = time()

cut_results = parallel_solve(cut_fractions) do cut_frac
    # A trust-fund shortfall cuts Social Security only; DB pension income
    # (the rest of the pre-existing annuitization floor) is untouched.
    ss_lvls = (1.0 - cut_frac) .* _ss_obs .+ _db_obs

    gkw = (n_wealth=_n_wealth, n_annuity=_n_annuity, n_alpha=_n_alpha,
           W_max=_w_max, age_start=_age_start, age_end=_age_end,
           annuity_grid_power=_a_grid_pow)

    ckw = (gamma=_gamma, beta=_beta, r=_r_rate,
           stochastic_health=true, n_health_states=3, n_quad=_n_quad,
           c_floor=_c_floor, hazard_mult=_hazard_mult, hazard_normalize=_hazard_normalize)

    # Structural channels on (incl. chi_ltc public-care aversion). The two
    # behavioral channels (lambda_w SDU, psi_purchase PED) stay at their off
    # defaults: the SS crowd-out is reported as a structural result.
    p_model = ModelParams(; ckw...,
        theta=_theta_dfj, kappa=_kappa_dfj,
        mwr=_mwr_loaded, fixed_cost=_fixed_cost, min_purchase=_min_purchase,
        inflation_rate=_inflation,
        medical_enabled=true, health_mortality_corr=true,
        survival_pessimism=_surv_pess,
        consumption_decline=_consumption_decline,
        health_utility=_health_utility,
        chi_ltc=_chi_ltc,
        gkw...)

    # Build grids on worker
    p_fg = ModelParams(; ckw..., mwr=1.0, gkw...)
    fp = compute_payout_rate(p_fg, _base_surv)
    p_fn = ModelParams(; ckw..., mwr=1.0, inflation_rate=_inflation, gkw...)
    fpn = _inflation > 0 ? compute_payout_rate(p_fn, _base_surv) : fp
    local_grids = build_grids(p_fg, max(fp, fpn))

    lpr = _mwr_loaded * fpn

    # Filter population
    pop = copy(_population)
    if _min_wealth > 0.0
        mask = pop[:, 1] .>= _min_wealth
        pop = pop[mask, :]
    end
    if size(pop, 2) < 4
        pop = hcat(pop, fill(2.0, size(pop, 1)))
    end

    res = solve_and_evaluate(p_model, local_grids, _base_surv, ss_lvls,
        pop, lpr; step_name="", verbose=false)

    @printf("    [heartbeat] cut=%.0f%% solved (ownership=%.1f%%)\n",
            cut_frac * 100, res.ownership * 100)
    flush(stdout)

    (cut_pct=cut_frac * 100,
     ownership=res.ownership,
     mean_alpha=res.mean_alpha)
end

solve_time = time() - t0
@printf("  Solved %d configurations in %.0fs\n", length(cut_fractions), solve_time)
flush(stdout)

# Sort by cut percentage
sort!(cut_results, by=r -> r.cut_pct)

# ===================================================================
# Print results
# ===================================================================
println("\n" * "=" ^ 70)
println("  RESULTS: PRIVATE ANNUITY DEMAND vs SS BENEFIT CUTS")
println("=" ^ 70)

baseline_own = cut_results[1].ownership

@printf("\n  %-15s  %12s  %10s  %12s\n",
    "SS Cut (%)", "Ownership", "Mean alpha", "vs Baseline")
println("  " * "-" ^ 55)

for r in cut_results
    # Delta from the DISPLAYED (rounded) levels so the printed row is
    # internally consistent (level - baseline = delta at one decimal).
    delta = round(r.ownership * 100; digits=1) - round(baseline_own * 100; digits=1)
    delta_str = r.cut_pct == 0.0 ? "---" : @sprintf("%+.1f pp", delta)
    label = r.cut_pct == 22.0 ? @sprintf("%.0f (trust fund)", r.cut_pct) :
            r.cut_pct == 100.0 ? @sprintf("%.0f (elimination)", r.cut_pct) :
            @sprintf("%.0f", r.cut_pct)
    @printf("  %-15s  %10.1f%%  %10.3f  %12s\n",
        label, r.ownership * 100, r.mean_alpha, delta_str)
end
println("  " * "-" ^ 55)
flush(stdout)

# ===================================================================
# Save CSV
# ===================================================================
tables_dir = joinpath(@__DIR__, "..", "tables")
mkpath(joinpath(tables_dir, "csv"))
mkpath(joinpath(tables_dir, "tex"))

csv_path = joinpath(tables_dir, "csv", "ss_cut_robustness.csv")
open(csv_path, "w") do f
    println(f, "cut_pct,ownership_pct,mean_alpha")
    for r in cut_results
        @printf(f, "%.0f,%.2f,%.4f\n", r.cut_pct, r.ownership * 100, r.mean_alpha)
    end
end
println("\n  CSV saved: $csv_path")
flush(stdout)

# ===================================================================
# Save LaTeX table
# ===================================================================
tex_path = joinpath(tables_dir, "tex", "ss_cut_robustness.tex")
open(tex_path, "w") do f
    println(f, raw"\begin{table}[htbp]")
    println(f, raw"\centering")
    println(f, raw"\caption{Private Annuity Demand Response to Social Security Benefit Reductions}")
    println(f, raw"\label{tab:ss_cut}")
    println(f, raw"\begin{tabular}{lccc}")
    println(f, raw"\toprule")
    println(f, "SS Benefit Cut & Ownership (\\%) & Mean \$\\alpha\$ & \$\\Delta\$ (pp) \\\\")
    println(f, raw"\midrule")

    for r in cut_results
        delta = r.ownership - baseline_own
        label = if r.cut_pct == 0.0
            "0\\% (baseline)"
        elseif r.cut_pct == 22.0
            "22\\% (trust fund)"
        elseif r.cut_pct == 100.0
            "100\\% (elimination)"
        else
            @sprintf("%.0f\\%%", r.cut_pct)
        end
        delta_str = r.cut_pct == 0.0 ? "---" : @sprintf("%+.1f", delta * 100)
        @printf(f, "%s & %.1f & %.3f & %s \\\\\n",
            label, round(r.ownership * 100; digits=2), r.mean_alpha, delta_str)
    end

    println(f, raw"\midrule")
    println(f, raw"Observed (HRS, this sample) & \pctHRSLifetimeNum--\pctHRSIannPooledNum & & " * "\\\\")
    println(f, raw"\bottomrule")
    println(f, raw"\end{tabular}")
    println(f, raw"\begin{tablenotes}")
    println(f, raw"\small")
    println(f, raw"\item Structural model (rational, preference, and public-care")
    println(f, raw"aversion channels; behavioral channels off). A trust-fund shortfall cuts")
    println(f, raw"Social Security only; DB pension income survives.")
    ss_str = join([string("\\\$", round(Int, l / 1000), "K") for l in SS_OBS], ", ")
    db_str = join([string("\\\$", round(Int, l / 1000), "K") for l in DB_OBS], ", ")
    println(f, "Baseline SS = [$(ss_str)], DB = [$(db_str)].")
    println(f, raw"22\% cut corresponds to projected OASI trust fund depletion in late 2032 (2026 Trustees Report).")
    println(f, raw"100\% cut eliminates Social Security entirely (DB pensions remain).")
    println(f, raw"\end{tablenotes}")
    println(f, raw"\end{table}")
end
println("  LaTeX saved: $tex_path")

println("\n" * "=" ^ 70)
println("  SS CUT ROBUSTNESS ANALYSIS COMPLETE")
println("=" ^ 70)
flush(stdout)
