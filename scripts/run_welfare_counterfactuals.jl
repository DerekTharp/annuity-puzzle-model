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
#   4. SS trust fund exhaustion (23% benefit cut)
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
hrs_path = HRS_PATH
hrs_raw = readdlm(hrs_path, ',', Any; skipstart=1)
n_pop = size(hrs_raw, 1)
population = zeros(n_pop, 4)
population[:, 1] = Float64.(hrs_raw[:, 1])  # wealth
population[:, 2] .= 0.0                      # A grid = 0 (SS via ss_func)
population[:, 3] = Float64.(hrs_raw[:, 3])  # age
if size(hrs_raw, 2) >= 4
    population[:, 4] = Float64.(hrs_raw[:, 4])  # observed health (1=Good, 2=Fair, 3=Poor)
else
    population[:, 4] .= 2.0  # default Fair if health not in CSV
end

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
             c_floor=C_FLOOR, hazard_mult=HAZARD_MULT)

p_base = ModelParams(age_start=AGE_START, age_end=AGE_END)
base_surv = build_lockwood_survival(p_base)

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
    ss_scale::Float64       # multiplier on SS_QUARTILE_LEVELS (1.0 = baseline)
    psi_purchase::Float64   # behavioral purchase friction (0 = default architecture)
    description::String
end

configs = [
    CounterfactualConfig(
        "Baseline", MWR_LOADED, INFLATION, SURVIVAL_PESSIMISM, C_FLOOR, 1.0, PSI_PURCHASE,
        "Full eleven-channel model, production calibration"),
    CounterfactualConfig(
        "Group pricing (MWR=0.90)", 0.90, INFLATION, SURVIVAL_PESSIMISM, C_FLOOR, 1.0, PSI_PURCHASE,
        "TSP/employer plan annuity pricing (James et al. 2006)"),
    CounterfactualConfig(
        "Public option (MWR=0.95)", 0.95, INFLATION, SURVIVAL_PESSIMISM, C_FLOOR, 1.0, PSI_PURCHASE,
        "Government-offered annuity at administrative cost"),
    CounterfactualConfig(
        "Actuarially fair (MWR=1.0)", 1.0, INFLATION, SURVIVAL_PESSIMISM, C_FLOOR, 1.0, PSI_PURCHASE,
        "Eliminate all pricing loads (theoretical benchmark)"),
    CounterfactualConfig(
        "Real annuity, TIPS-backed", 0.78, 0.0, SURVIVAL_PESSIMISM, C_FLOOR, 1.0, PSI_PURCHASE,
        "Inflation-indexed annuity at TIPS-backed pricing (Brown et al. 2002)"),
    CounterfactualConfig(
        "Real annuity, nominal-equiv", MWR_LOADED, 0.0, SURVIVAL_PESSIMISM, C_FLOOR, 1.0, PSI_PURCHASE,
        "Inflation-indexed at production MWR — isolates pure inflation channel"),
    CounterfactualConfig(
        "Fair + real", 1.0, 0.0, SURVIVAL_PESSIMISM, C_FLOOR, 1.0, PSI_PURCHASE,
        "Eliminate both loads and inflation (supply-side upper bound)"),
    CounterfactualConfig(
        "SS cut 23%", MWR_LOADED, INFLATION, SURVIVAL_PESSIMISM, C_FLOOR, 0.77, PSI_PURCHASE,
        "Trust fund exhaustion ~2033 (current-law default)"),
    CounterfactualConfig(
        "Correct pessimism (psi=1.0)", MWR_LOADED, INFLATION, 1.0, C_FLOOR, 1.0, PSI_PURCHASE,
        "Eliminate survival pessimism (information/disclosure intervention)"),
    CounterfactualConfig(
        "Group + correct pessimism", 0.90, INFLATION, 1.0, C_FLOOR, 1.0, PSI_PURCHASE,
        "MWR=0.90 + veridical survival beliefs — test interaction"),
    CounterfactualConfig(
        "Public consumption floor doubled", MWR_LOADED, INFLATION, SURVIVAL_PESSIMISM,
        C_FLOOR * 2.0, 1.0, PSI_PURCHASE,
        "Double the public consumption floor (c_floor); proxy for SSI/Medicaid expansion"),
    CounterfactualConfig(
        "Best feasible package", 0.90, 0.0, 1.0, C_FLOOR, 1.0, PSI_PURCHASE,
        "Group pricing + real annuity + correct pessimism"),
    CounterfactualConfig(
        "Default architecture (psi=0)", MWR_LOADED, INFLATION, SURVIVAL_PESSIMISM, C_FLOOR, 1.0, 0.0,
        "Annuitization as default; removes behavioral friction (Chalmers-Reuter 2012)"),
    CounterfactualConfig(
        "Default + group pricing", 0.90, INFLATION, SURVIVAL_PESSIMISM, C_FLOOR, 1.0, 0.0,
        "Default architecture combined with group pricing"),
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

    # Build ModelParams with ALL TEN channels on (rational + preferences + behavioral)
    # Use cfg-specific c_floor for Medicaid counterfactual.
    # The behavioral channel (psi_purchase) inherits from cfg so demand-side
    # counterfactuals (e.g. default architecture, psi=0) can override it.
    model_common = (gamma=GAMMA, beta=BETA, r=R_RATE,
                    stochastic_health=true, n_health_states=3, n_quad=N_QUAD,
                    c_floor=cfg.c_floor, hazard_mult=HAZARD_MULT)

    p_model = ModelParams(; model_common...,
        theta=THETA_DFJ, kappa=KAPPA_DFJ,
        mwr=cfg.mwr, fixed_cost=FIXED_COST,
        min_purchase=MIN_PURCHASE,
        inflation_rate=cfg.inflation,
        medical_enabled=true, health_mortality_corr=true,
        survival_pessimism=cfg.psi,
        consumption_decline=CONSUMPTION_DECLINE,
        health_utility=Float64.(HEALTH_UTILITY),
        lambda_w=LAMBDA_W,
        psi_purchase=cfg.psi_purchase,
        grid_kw...)

    # SS levels for this counterfactual
    ss_lvls = cfg.ss_scale .* SS_QUARTILE_LEVELS

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
# Each row: (label, mwr, infl, surv_pessimism, psi_purchase).
# "Best feasible" combines supply-side reform (group pricing, real annuity)
# with the demand-side default architecture (psi_purchase = 0). Without the
# psi_purchase override the "Best feasible" CEV would understate the welfare
# gain by holding the narrow-framing penalty at the production value.
cev_configs = [
    ("Baseline",      MWR_LOADED, INFLATION, SURVIVAL_PESSIMISM, PSI_PURCHASE),
    ("Group pricing", 0.90,       INFLATION, SURVIVAL_PESSIMISM, PSI_PURCHASE),
    ("Real annuity",  MWR_LOADED, 0.0,       SURVIVAL_PESSIMISM, PSI_PURCHASE),
    ("Best feasible", 0.90,       0.0,       1.0,                0.0),
]

bequest_specs = [
    (name="No bequest",     theta=0.0,   kappa=0.0),
    (name="Moderate (DFJ)", theta=THETA_DFJ, kappa=KAPPA_DFJ),
]

wealth_eval = [50_000.0, 100_000.0, 200_000.0, 500_000.0, 1_000_000.0]

# SS is wired through the welfare model's ss_func at $18,500 (median quartile).
# y_existing is reserved for non-SS pre-existing annuity income, ~zero in HRS.
y_existing_for_grid = 0.0
@printf("\n  y_existing = \$%s (SS via ss_func at \$18,500/year)\n",
    string(round(Int, y_existing_for_grid)))
flush(stdout)

cev_results = Dict{String, Any}()

for (label, mwr, infl, surv_pess, psi_p) in cev_configs
    @printf("\n  --- CEV Grid: %s (MWR=%.2f, infl=%.1f%%, surv_pess=%.3f, psi_p=%.4f) ---\n",
        label, mwr, infl * 100, surv_pess, psi_p)
    flush(stdout)

    cev_out = compute_cev_grid(
        base_surv, population;
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
        hazard_mult=HAZARD_MULT,
        survival_pessimism=surv_pess,
        consumption_decline=CONSUMPTION_DECLINE,
        health_utility=Float64.(HEALTH_UTILITY),
        psi_purchase=psi_p,
        lambda_w=LAMBDA_W,
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
for (label, _, _, _, _) in cev_configs
    @printf("  %16s", label)
end
println()
println("  " * "-" ^ (12 + 18 * length(cev_configs)))

for (iw, w) in enumerate(wealth_eval)
    W_str = string("\$", round(Int, w / 1000), "K")
    @printf("  %-12s", W_str)
    for (label, _, _, _, _) in cev_configs
        r = cev_results[label].grid[iw, 2, 1]  # DFJ bequests, Good health
        @printf("  %15.2f%%", r.cev * 100)
    end
    println()
end
println("  " * "-" ^ (12 + 18 * length(cev_configs)))

# Same for Fair health
println("\n  (DFJ bequests, Fair health)")
@printf("  %-12s", "Wealth")
for (label, _, _, _, _) in cev_configs
    @printf("  %16s", label)
end
println()
println("  " * "-" ^ (12 + 18 * length(cev_configs)))

for (iw, w) in enumerate(wealth_eval)
    W_str = string("\$", round(Int, w / 1000), "K")
    @printf("  %-12s", W_str)
    for (label, _, _, _, _) in cev_configs
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

for (label, _, _, _, _) in cev_configs
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

# Ownership counterfactuals CSV
# NOTE: column order is FIXED — scripts/export_manuscript_numbers.jl parses
# this CSV positionally because some scenario labels contain unquoted commas
# (e.g. "Real annuity, TIPS-backed"). Add new fields at the end and update
# the parser when changing schema.
csv_path = joinpath(tables_dir, "csv", "welfare_counterfactuals.csv")
open(csv_path, "w") do f
    println(f, "scenario,mwr,inflation,psi,c_floor,ss_scale,ownership_pct,mean_alpha,psi_purchase,description")
    for (i, r) in enumerate(results)
        cfg = configs[i]
        @printf(f, "%s,%.2f,%.3f,%.3f,%.0f,%.2f,%.2f,%.4f,%.3f,%s\n",
            r.label, cfg.mwr, cfg.inflation, cfg.psi, cfg.c_floor, cfg.ss_scale,
            r.ownership * 100, r.mean_alpha, cfg.psi_purchase, r.description)
    end
end
println("\n  Ownership CSV saved: ", csv_path)

# CEV comparison CSV (DFJ bequests, all health states)
cev_csv_path = joinpath(tables_dir, "csv", "cev_counterfactuals.csv")
open(cev_csv_path, "w") do f
    print(f, "wealth,health")
    for (label, _, _, _, _) in cev_configs
        @printf(f, ",cev_%s,alpha_%s",
            replace(lowercase(label), " " => "_"),
            replace(lowercase(label), " " => "_"))
    end
    println(f)
    health_names = ["Good", "Fair", "Poor"]
    for (iw, w) in enumerate(wealth_eval)
        for ih in 1:3
            @printf(f, "%.0f,%s", w, health_names[ih])
            for (label, _, _, _, _) in cev_configs
                r = cev_results[label].grid[iw, 2, ih]  # DFJ bequests
                @printf(f, ",%.4f,%.4f", r.cev, r.alpha_star)
            end
            println(f)
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
        @printf(f, "%s & %s & %s & %.1f & %s \\\\\n",
            r.label, mwr_str, infl_str, r.ownership * 100, delta_str)
        # Add midrule after baseline
        if i == 1
            println(f, raw"\midrule")
        end
    end
    println(f, raw"\midrule")
    @printf(f, "Observed (Lockwood 2012) & & & 3.6 & \\\\\n")
    println(f, raw"\bottomrule")
    println(f, raw"\end{tabular}")
    println(f, raw"\begin{tablenotes}")
    println(f, raw"\small")
    println(f, raw"\item Baseline: $\gamma=2.5$, $\beta=0.97$, DFJ bequests")
    println(f, raw"($\theta=56.96$, $\kappa=\$272{,}628$), $\psi=0.981$.")
    println(f, raw"Population: HRS single retirees 65--69 with $W \geq \$5{,}000$ ($N=566$).")
    println(f, raw"Group pricing reflects TSP/employer plan MWR (James et al.\ 2006).")
    println(f, raw"SS cut: 23\% across-the-board (projected trust fund exhaustion).")
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
    for (label, _, _, _, _) in cev_configs
        @printf(f, " & %s", label)
    end
    println(f, " \\\\")
    println(f, raw"\midrule")
    # Panel A: Good health
    println(f, "\\multicolumn{" * string(nc + 1) * "}{l}{\\textit{Panel A: Good Health, DFJ Bequests}} \\\\")
    for (iw, w) in enumerate(wealth_eval)
        W_str = string("\\\$", round(Int, w / 1000), "K")
        print(f, W_str)
        for (label, _, _, _, _) in cev_configs
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
        for (label, _, _, _, _) in cev_configs
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
        for (label, _, _, _, _) in cev_configs
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
    println(f, raw"SS income (\$18{,}500/yr, median quartile). Baseline: MWR=0.87, 2\% inflation,")
    println(f, raw"$\psi=0.981$, $\psi_{\text{purchase}}=0.0163$. Group pricing: MWR=0.90.")
    println(f, raw"Real annuity: 0\% inflation, MWR=0.87. Best feasible combines group pricing,")
    println(f, raw"real annuity, no survival pessimism ($\psi=1.0$), and default architecture")
    println(f, raw"($\psi_{\text{purchase}}=0$).")
    println(f, raw"\end{tablenotes}")
    println(f, raw"\end{table}")
end
println("  CEV LaTeX table saved: ", cev_tex_path)

println("\n" * "=" ^ 70)
println("  WELFARE COUNTERFACTUAL ANALYSIS COMPLETE")
println("=" ^ 70)
flush(stdout)
