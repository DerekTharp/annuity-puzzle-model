# Policy Welfare Counterfactuals
#
# Computes predicted ownership and CEV under alternative policy scenarios.
# Uses solve_and_evaluate() directly (all channels on) for efficiency —
# one solve per counterfactual instead of the full 8-step decomposition.
#
# Counterfactuals:
#   1. Pricing reform (MWR = 0.90, 0.95)
#   2. Real annuity (inflation = 0%, at TIPS-backed and nominal-equivalent pricing)
#   3. Combined supply-side (fair + real)
#   4. SS trust fund depletion (22% benefit cut, 2026 Trustees)
#   5. Survival pessimism correction (psi = 1.0)
#   6. Pricing + belief correction (MWR = 0.90, psi = 1.0)
#   7. Medicaid means test relaxation (c_floor doubled)
#   8. Best feasible package (MWR = 0.90, real, psi = 1.0)
#
# Usage: julia --project=. -p 8 scripts/run_welfare_counterfactuals.jl

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
println("  POLICY WELFARE COUNTERFACTUALS")
println("  Predicted Ownership + CEV Under Alternative Scenarios")
println("=" ^ 70)
flush(stdout)

# ===================================================================
# Load HRS population sample
# ===================================================================
println("\nLoading HRS population sample...")
flush(stdout)
population = load_hrs_population(HRS_PATH; zero_ss=true)
n_pop = size(population, 1)

# Filter to eligible
mask = population[:, 1] .>= MIN_WEALTH
pop = population[mask, :]
n_eligible = size(pop, 1)
@printf("  Loaded %d individuals, %d eligible (W >= \$%s)\n",
    n_pop, n_eligible, string(round(Int, MIN_WEALTH)))
flush(stdout)

# ===================================================================
# Build survival probabilities and grids (shared across counterfactuals)
# ===================================================================
println("\nBuilding survival probabilities and grids...")
flush(stdout)

grid_kw = (n_wealth=N_WEALTH, n_annuity=N_ANNUITY, n_alpha=N_ALPHA,
           W_max=W_MAX, age_start=AGE_START, age_end=AGE_END,
           annuity_grid_power=A_GRID_POW)

common_kw = (gamma=GAMMA, beta=BETA, r=R_RATE,
             stochastic_health=true, n_health_states=3, n_quad=N_QUAD,
             c_floor=C_FLOOR, hazard_mult=HAZARD_MULT, hazard_normalize=HAZARD_NORMALIZE)

p_base = ModelParams(age_start=AGE_START, age_end=AGE_END)
base_surv = production_base_survival(p_base)

# Fair payout rates (real and nominal)
p_fair = ModelParams(; gamma=GAMMA, beta=BETA, r=R_RATE, mwr=1.0, grid_kw...)
fair_pr = compute_payout_rate(p_fair, base_surv)

p_fair_nom = ModelParams(; gamma=GAMMA, beta=BETA, r=R_RATE, mwr=1.0,
                          inflation_rate=INFLATION, grid_kw...)
fair_pr_nom = compute_payout_rate(p_fair_nom, base_surv)

# Grids cover the full A range (use max of real and nominal fair rates)
grids = build_grids(p_fair, max(fair_pr, fair_pr_nom))

@printf("  Fair payout rate (real):    %.4f (%.1f%%/yr)\n", fair_pr, fair_pr * 100)
@printf("  Fair payout rate (nominal): %.4f (%.1f%%/yr)\n", fair_pr_nom, fair_pr_nom * 100)
flush(stdout)

# ===================================================================
# Define counterfactual configurations
# ===================================================================
# Each config: (label, mwr, inflation, psi, c_floor, ss_scale, description)

struct CounterfactualConfig
    label::String
    mwr::Float64
    inflation::Float64
    psi::Float64
    c_floor::Float64
    ss_scale::Float64       # multiplier on the Social Security component only
                            # (1.0 = baseline). DB pension income survives an SS
                            # cut: ss_lvls = ss_scale*SS_OBS + DB_OBS, matching
                            # run_ss_robustness.jl.
    description::String
end

configs = [
    CounterfactualConfig(
        "Baseline", MWR_LOADED, INFLATION, SURVIVAL_PESSIMISM, C_FLOOR, 1.0,
        "Full structural model at production calibration"),
    CounterfactualConfig(
        "Group pricing (MWR=0.90)", 0.90, INFLATION, SURVIVAL_PESSIMISM, C_FLOOR, 1.0,
        "TSP/employer plan annuity pricing (James et al. 2006)"),
    CounterfactualConfig(
        "Public option (MWR=0.95)", 0.95, INFLATION, SURVIVAL_PESSIMISM, C_FLOOR, 1.0,
        "Government-offered annuity at administrative cost"),
    CounterfactualConfig(
        "Actuarially fair (MWR=1.0)", 1.0, INFLATION, SURVIVAL_PESSIMISM, C_FLOOR, 1.0,
        "Eliminate all pricing loads (theoretical benchmark)"),
    CounterfactualConfig(
        "Real annuity, TIPS-backed", 0.78, 0.0, SURVIVAL_PESSIMISM, C_FLOOR, 1.0,
        "Inflation-indexed annuity at TIPS-backed pricing (Brown et al. 2002)"),
    CounterfactualConfig(
        "Real annuity, nominal-equiv", MWR_LOADED, 0.0, SURVIVAL_PESSIMISM, C_FLOOR, 1.0,
        "Inflation-indexed at production MWR — isolates pure inflation channel"),
    CounterfactualConfig(
        "Fair + real", 1.0, 0.0, SURVIVAL_PESSIMISM, C_FLOOR, 1.0,
        "Eliminate both loads and inflation (supply-side upper bound)"),
    CounterfactualConfig(
        "SS cut 22%", MWR_LOADED, INFLATION, SURVIVAL_PESSIMISM, C_FLOOR, 0.78,
        "Trust fund depletion late 2032 (2026 Trustees, current-law default)"),
    CounterfactualConfig(
        "Correct pessimism (psi=1.0)", MWR_LOADED, INFLATION, 1.0, C_FLOOR, 1.0,
        "Eliminate survival pessimism (information/disclosure intervention)"),
    CounterfactualConfig(
        "Group + correct pessimism", 0.90, INFLATION, 1.0, C_FLOOR, 1.0,
        "MWR=0.90 + veridical survival beliefs — test interaction"),
    CounterfactualConfig(
        "Public consumption floor doubled", MWR_LOADED, INFLATION, SURVIVAL_PESSIMISM,
        C_FLOOR * 2.0, 1.0,
        "Double the public consumption floor (c_floor); proxy for SSI/Medicaid expansion"),
    CounterfactualConfig(
        "Best feasible package", 0.90, 0.0, 1.0, C_FLOOR, 1.0,
        "Group pricing + real annuity + correct pessimism (supply + information package)"),
]

# ===================================================================
# PART 1: Predicted Ownership Under Each Counterfactual
# ===================================================================
println("\n" * "=" ^ 70)
println("  PART 1: PREDICTED OWNERSHIP UNDER POLICY COUNTERFACTUALS")
println("=" ^ 70)
flush(stdout)

# Results storage
struct CounterfactualResult
    label::String
    ownership::Float64
    mean_alpha::Float64
    solve_time::Float64
    description::String
end

results = CounterfactualResult[]

for (i, cfg) in enumerate(configs)
    @printf("\n  [%d/%d] %s\n", i, length(configs), cfg.label)
    @printf("         %s\n", cfg.description)
    flush(stdout)

    # Compute payout rate for this counterfactual
    if cfg.inflation > 0
        # Nominal annuity: higher initial payout, eroded by inflation
        p_nom = ModelParams(; gamma=GAMMA, beta=BETA, r=R_RATE, mwr=1.0,
                             inflation_rate=cfg.inflation, grid_kw...)
        this_fair_nom = compute_payout_rate(p_nom, base_surv)
        payout = cfg.mwr * this_fair_nom
    else
        # Real annuity: payout based on real rate only
        payout = cfg.mwr * fair_pr
    end

    # Build ModelParams with the rational + preference + structural channels on.
    # The two behavioral channels (SDU lambda_w, PED psi_purchase) are left off
    # in the welfare counterfactuals; they are exercised separately as robustness.
    model_common = (gamma=GAMMA, beta=BETA, r=R_RATE,
                    stochastic_health=true, n_health_states=3, n_quad=N_QUAD,
                    c_floor=cfg.c_floor, hazard_mult=HAZARD_MULT, hazard_normalize=HAZARD_NORMALIZE)

    p_model = ModelParams(; model_common...,
        theta=THETA_DFJ, kappa=KAPPA_DFJ,
        mwr=cfg.mwr, fixed_cost=FIXED_COST,
        min_purchase=MIN_PURCHASE,
        inflation_rate=cfg.inflation,
        medical_enabled=true, health_mortality_corr=true,
        survival_pessimism=cfg.psi,
        consumption_decline=CONSUMPTION_DECLINE,
        health_utility=Float64.(HEALTH_UTILITY),
        chi_ltc=CHI_LTC,
        grid_kw...)

    # SS levels for this counterfactual. The scale hits Social Security only;
    # DB pension income is untouched by a trust-fund shortfall. At
    # ss_scale=1.0 this reproduces SS_QUARTILE_LEVELS = SS_OBS + DB_OBS.
    ss_lvls = cfg.ss_scale .* Float64.(SS_OBS) .+ Float64.(DB_OBS)

    t0 = time()
    res = solve_and_evaluate(p_model, grids, base_surv, ss_lvls,
        pop, payout; step_name=cfg.label, verbose=false)
    elapsed = time() - t0

    push!(results, CounterfactualResult(
        cfg.label, res.ownership, res.mean_alpha, elapsed, cfg.description))

    @printf("         Ownership: %6.1f%%  Mean alpha: %.3f  (%.0fs)\n",
        res.ownership * 100, res.mean_alpha, elapsed)
    flush(stdout)
end

# ===================================================================
# Print summary table
# ===================================================================
println("\n" * "=" ^ 70)
println("  SUMMARY: POLICY COUNTERFACTUAL RESULTS")
println("=" ^ 70)

baseline_own = results[1].ownership

@printf("\n  %-35s  %10s  %8s  %10s\n",
    "Policy Scenario", "Ownership", "Mean a", "vs Baseline")
println("  " * "-" ^ 70)

for r in results
    delta = r.ownership - baseline_own
    delta_str = r.label == "Baseline" ? "---" : @sprintf("%+.1f pp", delta * 100)
    @printf("  %-35s  %9.1f%%  %7.3f  %10s\n",
        r.label, r.ownership * 100, r.mean_alpha, delta_str)
end
println("  " * "-" ^ 70)
@printf("  %-35s  %9.1f%%\n", "Observed (Lockwood 2012)", 3.6)
flush(stdout)

# ===================================================================
# PART 2: CEV GRID FOR TOP COUNTERFACTUALS
# ===================================================================
println("\n" * "=" ^ 70)
println("  PART 2: CEV WELFARE ANALYSIS BY HOUSEHOLD TYPE")
println("=" ^ 70)
flush(stdout)

# CEV configs: baseline + top 3 counterfactuals.
# Each row: (label, mwr, infl, surv_pessimism).
cev_configs = [
    ("Baseline",      MWR_LOADED, INFLATION, SURVIVAL_PESSIMISM),
    ("Group pricing", 0.90,       INFLATION, SURVIVAL_PESSIMISM),
    ("Real annuity",  MWR_LOADED, 0.0,       SURVIVAL_PESSIMISM),
    ("Best feasible", 0.90,       0.0,       1.0),
]

bequest_specs = [
    (name="No bequest",     theta=0.0,   kappa=0.0),
    (name="Moderate (DFJ)", theta=THETA_DFJ, kappa=KAPPA_DFJ),
]

wealth_eval = [50_000.0, 100_000.0, 200_000.0, 500_000.0, 1_000_000.0]

# SS is wired through the welfare model's ss_func at the representative level
# (midpoint of the two middle wealth-bin floors of SS_QUARTILE_LEVELS).
# y_existing is reserved for non-SS pre-existing annuity income, ~zero in HRS.
y_existing_for_grid = 0.0
ss_rep_display = (SS_QUARTILE_LEVELS[2] + SS_QUARTILE_LEVELS[3]) / 2
@printf("\n  y_existing = \$%s (SS via ss_func at \$%s/year)\n",
    string(round(Int, y_existing_for_grid)), string(round(Int, ss_rep_display)))
flush(stdout)

cev_results = Dict{String, Any}()

for (label, mwr, infl, surv_pess) in cev_configs
    @printf("\n  --- CEV Grid: %s (MWR=%.2f, infl=%.1f%%, surv_pess=%.3f) ---\n",
        label, mwr, infl * 100, surv_pess)
    flush(stdout)

    # Pass the same MIN_WEALTH-eligible sample (pop) used in PART 1 so the
    # population-level CEV statistics (PART 4) are computed over the same
    # population as the ownership counterfactuals. The grid-CEV cells use the
    # fixed wealth_points and are unaffected by this choice.
    cev_out = compute_cev_grid(
        base_surv, pop;
        bequest_specs=bequest_specs,
        wealth_points=wealth_eval,
        y_existing=y_existing_for_grid,
        gamma=GAMMA, beta=BETA, r=R_RATE,
        c_floor=C_FLOOR,
        mwr_loaded=mwr,
        fixed_cost_val=FIXED_COST,
        min_purchase_val=MIN_PURCHASE,
        inflation_val=infl,
        n_wealth=N_WEALTH, n_annuity=N_ANNUITY, n_alpha=N_ALPHA,
        W_max=W_MAX, n_quad=N_QUAD,
        age_start=AGE_START, age_end=AGE_END,
        annuity_grid_power=A_GRID_POW,
        hazard_mult=HAZARD_MULT, hazard_normalize=HAZARD_NORMALIZE,
        survival_pessimism=surv_pess,
        consumption_decline=CONSUMPTION_DECLINE,
        health_utility=Float64.(HEALTH_UTILITY),
        chi_ltc=CHI_LTC,
        verbose=true,
    )

    cev_results[label] = cev_out

    # Print compact table (DFJ bequests only, Good health)
    println()
    @printf("  %-12s", "Wealth")
    for bname in cev_out.bequest_names
        @printf("  %16s", bname)
    end
    @printf("  %8s", "alpha*")
    println()
    println("  " * "-" ^ 56)

    for (iw, w) in enumerate(wealth_eval)
        W_str = string("\$", round(Int, w / 1000), "K")
        @printf("  %-12s", W_str)
        for ib in 1:length(bequest_specs)
            r = cev_out.grid[iw, ib, 1]  # Good health
            @printf("  %15.2f%%", r.cev * 100)
        end
        r_dfj = cev_out.grid[iw, 2, 1]  # DFJ, Good health
        @printf("  %7.0f%%", r_dfj.alpha_star * 100)
        println()
    end
    println("  " * "-" ^ 56)
    println("  (Good health only; DFJ bequests for alpha*)")
    flush(stdout)
end

# ===================================================================
# PART 3: CEV Comparison Across Counterfactuals
# ===================================================================
println("\n" * "=" ^ 70)
println("  PART 3: CEV COMPARISON ACROSS COUNTERFACTUALS")
println("  (DFJ bequests, Good health)")
println("=" ^ 70)

@printf("\n  %-12s", "Wealth")
for (label, _, _, _) in cev_configs
    @printf("  %16s", label)
end
println()
println("  " * "-" ^ (12 + 18 * length(cev_configs)))

for (iw, w) in enumerate(wealth_eval)
    W_str = string("\$", round(Int, w / 1000), "K")
    @printf("  %-12s", W_str)
    for (label, _, _, _) in cev_configs
        r = cev_results[label].grid[iw, 2, 1]  # DFJ bequests, Good health
        @printf("  %15.2f%%", r.cev * 100)
    end
    println()
end
println("  " * "-" ^ (12 + 18 * length(cev_configs)))

# Same for Fair health
println("\n  (DFJ bequests, Fair health)")
@printf("  %-12s", "Wealth")
for (label, _, _, _) in cev_configs
    @printf("  %16s", label)
end
println()
println("  " * "-" ^ (12 + 18 * length(cev_configs)))

for (iw, w) in enumerate(wealth_eval)
    W_str = string("\$", round(Int, w / 1000), "K")
    @printf("  %-12s", W_str)
    for (label, _, _, _) in cev_configs
        r = cev_results[label].grid[iw, 2, 2]  # DFJ bequests, Fair health
        @printf("  %15.2f%%", r.cev * 100)
    end
    println()
end
println("  " * "-" ^ (12 + 18 * length(cev_configs)))
flush(stdout)

# ===================================================================
# PART 4: Population CEV Statistics
# ===================================================================
println("\n" * "=" ^ 70)
println("  PART 4: POPULATION-LEVEL CEV STATISTICS")
println("=" ^ 70)

@printf("\n  %-20s  %-16s  %9s  %9s  %8s  %8s\n",
    "Counterfactual", "Bequest Spec", "Mean CEV", "Med CEV", "CEV>0", "CEV>1%")
println("  " * "-" ^ 78)

for (label, _, _, _) in cev_configs
    cev_out = cev_results[label]
    for pcev in cev_out.population_cev
        @printf("  %-20s  %-16s  %8.2f%%  %8.2f%%  %7.1f%%  %7.1f%%\n",
            label, pcev.name,
            pcev.mean_cev * 100, pcev.median_cev * 100,
            pcev.frac_positive * 100, pcev.frac_above_1pct * 100)
    end
end
flush(stdout)

# ===================================================================
# Save results to CSV
# ===================================================================
tables_dir = joinpath(@__DIR__, "..", "tables")
mkpath(joinpath(tables_dir, "csv"))
mkpath(joinpath(tables_dir, "tex"))

# Ownership counterfactuals CSV. Scenario labels and descriptions can contain
# commas (e.g. "Real annuity, TIPS-backed"), so fields are RFC-4180 quoted;
# scripts/export_manuscript_numbers.jl reads them positionally with parse_csv_row.
csv_path = joinpath(tables_dir, "csv", "welfare_counterfactuals.csv")
open(csv_path, "w") do f
    println(f, csv_row("scenario", "mwr", "inflation", "psi", "c_floor",
                       "ss_scale", "ownership_pct", "mean_alpha", "description"))
    for (i, r) in enumerate(results)
        cfg = configs[i]
        println(f, csv_row(r.label,
            @sprintf("%.2f", cfg.mwr), @sprintf("%.3f", cfg.inflation),
            @sprintf("%.3f", cfg.psi), @sprintf("%.0f", cfg.c_floor),
            @sprintf("%.2f", cfg.ss_scale), @sprintf("%.2f", r.ownership * 100),
            @sprintf("%.4f", r.mean_alpha), r.description))
    end
end
println("\n  Ownership CSV saved: ", csv_path)

# CEV comparison CSV (DFJ bequests and no-bequest specs, all health states,
# so every printed panel of tab:cev_counterfactuals has a machine-readable
# artifact: bequest_spec column = dfj | none)
cev_csv_path = joinpath(tables_dir, "csv", "cev_counterfactuals.csv")
open(cev_csv_path, "w") do f
    print(f, "bequest_spec,wealth,health")
    for (label, _, _, _) in cev_configs
        @printf(f, ",cev_%s,alpha_%s",
            replace(lowercase(label), " " => "_"),
            replace(lowercase(label), " " => "_"))
    end
    println(f)
    health_names = ["Good", "Fair", "Poor"]
    for (spec_name, ib) in [("dfj", 2), ("none", 1)]
        for (iw, w) in enumerate(wealth_eval)
            for ih in 1:3
                @printf(f, "%s,%.0f,%s", spec_name, w, health_names[ih])
                for (label, _, _, _) in cev_configs
                    r = cev_results[label].grid[iw, ib, ih]
                    @printf(f, ",%.4f,%.4f", r.cev, r.alpha_star)
                end
                println(f)
            end
        end
    end
end
println("  CEV CSV saved: ", cev_csv_path)

# ===================================================================
# Save LaTeX table: ownership counterfactuals
# ===================================================================
tex_path = joinpath(tables_dir, "tex", "welfare_counterfactuals.tex")
open(tex_path, "w") do f
    println(f, raw"\begin{table}[htbp]")
    println(f, raw"\centering")
    println(f, raw"\caption{Predicted Annuity Ownership Under Policy Counterfactuals}")
    println(f, raw"\label{tab:counterfactuals}")
    println(f, raw"\begin{tabular}{lcccc}")
    println(f, raw"\toprule")
    println(f, "Policy Scenario & MWR & Inflation & Ownership (\\%) & \$\\Delta\$ (pp) \\\\")
    println(f, raw"\midrule")
    for (i, r) in enumerate(results)
        cfg = configs[i]
        delta = r.ownership - baseline_own
        delta_str = i == 1 ? "---" : @sprintf("%+.1f", delta * 100)
        mwr_str = @sprintf("%.2f", cfg.mwr)
        infl_str = cfg.inflation > 0 ? @sprintf("%.0f\\%%", cfg.inflation * 100) : "0 (real)"
        label_tex = replace(r.label, "%" => "\\%")  # escape for LaTeX
        @printf(f, "%s & %s & %s & %.1f & %s \\\\\n",
            label_tex, mwr_str, infl_str, r.ownership * 100, delta_str)
        # Add midrule after baseline
        if i == 1
            println(f, raw"\midrule")
        end
    end
    println(f, raw"\midrule")
    # Normal (non-raw) string: a raw string ending in \\ collapses the trailing
    # backslashes (2 before the closing quote -> 1), breaking the LaTeX row end.
    println(f, "Observed (HRS, this sample) & & & \\pctHRSLifetimeNum--\\pctHRSIannPooledNum & \\\\")
    println(f, raw"\bottomrule")
    println(f, raw"\end{tabular}")
    println(f, raw"\begin{tablenotes}")
    println(f, raw"\small")
    @printf(f, "\\item Baseline: \$\\gamma=%.1f\$, \$\\beta=%.2f\$, DFJ bequests\n", GAMMA, BETA)
    @printf(f, "(\$\\theta=%.2f\$, \$\\kappa=\\\$%s\$), \$\\psi=%.3f\$.\n",
        THETA_DFJ, replace(@sprintf("%d", round(Int, KAPPA_DFJ)), r"(\d)(?=(\d{3})+$)" => s"\1{,}"), SURVIVAL_PESSIMISM)
    @printf(f, "Population: HRS single nonworking retirees 65--69 with \$W \\geq \\\$%s\$ (\$N=%s\$).\n",
        replace(@sprintf("%d", round(Int, MIN_WEALTH)), r"(\d)(?=(\d{3})+$)" => s"\1{,}"),
        replace(@sprintf("%d", size(pop, 1)), r"(\d)(?=(\d{3})+$)" => s"\1{,}"))
    println(f, raw"Group pricing reflects TSP/employer plan MWR (James et al.\ 2006).")
    println(f, raw"SS cut: 22\% reduction in Social Security benefits only; DB pension")
    println(f, raw"income is unaffected (projected OASI trust fund depletion in late 2032,")
    println(f, raw"2026 Trustees Report).")
    println(f, raw"\end{tablenotes}")
    println(f, raw"\end{table}")
end
println("  LaTeX table saved: ", tex_path)

# ===================================================================
# Save LaTeX table: CEV comparison (DFJ bequests, Good health)
# ===================================================================
cev_tex_path = joinpath(tables_dir, "tex", "cev_counterfactuals.tex")
open(cev_tex_path, "w") do f
    println(f, raw"\begin{table}[htbp]")
    println(f, raw"\centering")
    println(f, raw"\caption{Welfare Gain from Annuity Access Under Policy Counterfactuals (CEV, \%)}")
    println(f, raw"\label{tab:cev_counterfactuals}")
    nc = length(cev_configs)
    println(f, "\\begin{tabular}{l" * "c" ^ nc * "}")
    println(f, raw"\toprule")
    # Header
    print(f, "Wealth")
    for (label, _, _, _) in cev_configs
        @printf(f, " & %s", label)
    end
    println(f, " \\\\")
    println(f, raw"\midrule")
    # Panel A: Good health
    println(f, "\\multicolumn{" * string(nc + 1) * "}{l}{\\textit{Panel A: Good Health, DFJ Bequests}} \\\\")
    for (iw, w) in enumerate(wealth_eval)
        W_str = string("\\\$", round(Int, w / 1000), "K")
        print(f, W_str)
        for (label, _, _, _) in cev_configs
            r = cev_results[label].grid[iw, 2, 1]
            @printf(f, " & %.2f", r.cev * 100)
        end
        println(f, " \\\\")
    end
    println(f, raw"\midrule")
    # Panel B: Fair health
    println(f, "\\multicolumn{" * string(nc + 1) * "}{l}{\\textit{Panel B: Fair Health, DFJ Bequests}} \\\\")
    for (iw, w) in enumerate(wealth_eval)
        W_str = string("\\\$", round(Int, w / 1000), "K")
        print(f, W_str)
        for (label, _, _, _) in cev_configs
            r = cev_results[label].grid[iw, 2, 2]
            @printf(f, " & %.2f", r.cev * 100)
        end
        println(f, " \\\\")
    end
    println(f, raw"\midrule")
    # Panel C: No bequests, Good health
    println(f, "\\multicolumn{" * string(nc + 1) * "}{l}{\\textit{Panel C: Good Health, No Bequests}} \\\\")
    for (iw, w) in enumerate(wealth_eval)
        W_str = string("\\\$", round(Int, w / 1000), "K")
        print(f, W_str)
        for (label, _, _, _) in cev_configs
            r = cev_results[label].grid[iw, 1, 1]
            @printf(f, " & %.2f", r.cev * 100)
        end
        println(f, " \\\\")
    end
    println(f, raw"\bottomrule")
    println(f, raw"\end{tabular}")
    println(f, raw"\begin{tablenotes}")
    println(f, raw"\small")
    println(f, raw"\item CEV: consumption-equivalent variation (\% of lifetime consumption")
    println(f, raw"agent would pay for annuity market access). Welfare model uses representative")
    @printf(f, "SS income (\\\$%s/yr, midpoint of the middle wealth-bin floors).\n",
        replace(@sprintf("%d", round(Int, ss_rep_display)), r"(\d)(?=(\d{3})+$)" => s"\1{,}"))
    @printf(f, "Baseline: MWR=%.2f, %.0f\\%% inflation, \$\\psi=%.3f\$; behavioral channels off.\n",
        MWR_LOADED, INFLATION * 100, SURVIVAL_PESSIMISM)
    @printf(f, "Group pricing: MWR=0.90. Real annuity: 0\\%% inflation, MWR=%.2f.\n", MWR_LOADED)
    println(f, raw"Best feasible combines group pricing, real annuity, and no survival")
    println(f, raw"pessimism ($\psi=1.0$).")
    println(f, raw"\end{tablenotes}")
    println(f, raw"\end{table}")
end
println("  CEV LaTeX table saved: ", cev_tex_path)

println("\n" * "=" ^ 70)
println("  WELFARE COUNTERFACTUAL ANALYSIS COMPLETE")
println("=" ^ 70)
flush(stdout)
