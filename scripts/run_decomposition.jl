# Phase 4: Sequential Decomposition of Predicted Annuity Ownership
#
# Generates Table 1 (the core result):
#   Starting from Yaari's 100% benchmark, add channels one at a time
#   and measure how each reduces predicted ownership.
# Also computes multiplicative interaction analysis.
#
# Parameters loaded from scripts/config.jl (gamma=2.5, hazard_mult=[0.50,1.0,3.0])

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
println("  PHASE 4: FULL MODEL AND DECOMPOSITION")
println("  Sequential Channel Analysis — Table 1")
println("=" ^ 70)

# ===================================================================
# Load HRS population sample
# ===================================================================
println("\nLoading HRS population sample...")
hrs_path = HRS_PATH
hrs_raw = readdlm(hrs_path, ',', Any; skipstart=1)
n_pop = size(hrs_raw, 1)
# Columns: wealth, purchased annuity income (zero at entry; SS enters via ss_func), age.
# SS income enters through ss_func in the Bellman equation (COLA-protected),
# not through the A grid.
population = zeros(n_pop, 4)
population[:, 1] = Float64.(hrs_raw[:, 1])  # wealth
population[:, 2] .= 0.0                      # A grid = purchased annuity only (SS via ss_func)
population[:, 3] = Float64.(hrs_raw[:, 3])  # age
if size(hrs_raw, 2) >= 4
    population[:, 4] = Float64.(hrs_raw[:, 4])  # observed health (1=Good, 2=Fair, 3=Poor)
else
    population[:, 4] .= 2.0  # default Fair if health not in CSV
end
n_eligible = count(population[:, 1] .>= MIN_WEALTH)
@printf("  Loaded %d individuals. Median wealth: \$%s\n",
    n_pop,
    string(round(Int, sort(population[:, 1])[div(n_pop, 2)])))
@printf("  Eligible (W >= \$%s): %d of %d (%.1f%%)\n",
    string(round(Int, MIN_WEALTH)), n_eligible, n_pop, n_eligible / n_pop * 100)

# ===================================================================
# Build survival probabilities
# ===================================================================
p_base = ModelParams(age_start=AGE_START, age_end=AGE_END)
base_surv = build_lockwood_survival(p_base)

# Fair payout rate for bequest calibration
p_fair = ModelParams(age_start=AGE_START, age_end=AGE_END, mwr=1.0, r=R_RATE)
fair_pr = compute_payout_rate(p_fair, base_surv)
@printf("\n  Fair payout rate (MWR=1.0): %.4f (%.1f%% per year)\n",
    fair_pr, fair_pr * 100)

# ===================================================================
# Bequest parameters: DFJ luxury good specification (Lockwood BAP_sim2.m)
# Use Lockwood's original theta at all gamma values. The DFJ theta was
# estimated at sigma=2, but simulation-based checks show <14% divergence
# in bequest-to-wealth ratio across gamma in [1.5, 5.0], below the
# threshold warranting recalibration.
# ===================================================================
@printf("  DFJ bequest theta: %.2f (Lockwood BAP_sim2.m, used at all gamma)\n", THETA_DFJ)
@printf("  DFJ bequest kappa: \$%s (De Nardi 2004 luxury good)\n",
    string(round(Int, KAPPA_DFJ)))
@printf("  Hazard multipliers: [%.2f, %.1f, %.1f]\n",
    HAZARD_MULT[1], HAZARD_MULT[2], HAZARD_MULT[3])
println("    (HRS SRH: [0.57,1.0,2.70]; R-S functional: [0.45,1.0,3.5])")

# ===================================================================
# Run Sequential Decomposition
# ===================================================================
# SS enters through ss_func in the Bellman equation (COLA-protected).
# Step 0 is a true Yaari benchmark (no SS). Step 1 adds SS as a channel.
const SS_LEVELS = SS_QUARTILE_LEVELS  # [14K, 17K, 20K, 25K] by wealth quartile

println()
decomp = run_decomposition(
    base_surv, population;
    gamma=GAMMA, beta=BETA, r=R_RATE,
    theta=THETA_DFJ, kappa=KAPPA_DFJ,
    c_floor=C_FLOOR,
    mwr_loaded=MWR_LOADED,
    fixed_cost_val=FIXED_COST,
    min_purchase_val=MIN_PURCHASE,
    inflation_val=INFLATION,
    n_wealth=N_WEALTH, n_annuity=N_ANNUITY, n_alpha=N_ALPHA,
    W_max=W_MAX, n_quad=N_QUAD,
    age_start=AGE_START, age_end=AGE_END,
    annuity_grid_power=A_GRID_POW,
    hazard_mult=HAZARD_MULT,
    survival_pessimism=SURVIVAL_PESSIMISM,
    min_wealth=MIN_WEALTH,
    ss_levels=SS_LEVELS,
    consumption_decline_val=CONSUMPTION_DECLINE,
    health_utility_vals=Float64.(HEALTH_UTILITY),
    psi_purchase_val=PSI_PURCHASE,
    lambda_w_val=LAMBDA_W,
    verbose=true,
)

# ===================================================================
# Multiplicative Interaction Analysis (diagnostic-only, skipped by default
# because the same information is in pairwise_interactions.csv from this
# script's later section + the Shapley decomposition. ~9 solves * 280s each.)
# ===================================================================
const RUN_MULTIPLICATIVE = get(ENV, "ANNUITY_RUN_MULTIPLICATIVE", "0") == "1"
if RUN_MULTIPLICATIVE
    println("\n" * "=" ^ 70)
    mult = run_multiplicative_analysis(
        base_surv, population;
        gamma=GAMMA, beta=BETA, r=R_RATE,
        theta=THETA_DFJ, kappa=KAPPA_DFJ,
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
else
    println("\nSkipping multiplicative interaction analysis (set ANNUITY_RUN_MULTIPLICATIVE=1 to enable).")
end

# ===================================================================
# Retention-Rate Decomposition (geometric compounding metric)
# ===================================================================
println("\n" * "=" ^ 70)
println("  RETENTION-RATE DECOMPOSITION")
println("  Each channel acts as a multiplicative filter on ownership")
println("=" ^ 70)

rates = [s.ownership_rate for s in decomp.steps]
@printf("\n  %-50s  %8s  %10s\n", "Channel", "Ownership", "Retention")
println("  " * "-" ^ 70)
@printf("  %-50s  %7.1f%%\n", decomp.steps[1].name, rates[1] * 100)

let cum_retention = 1.0
    for i in 2:length(rates)
        retention = rates[i] / max(rates[i-1], 1e-10)
        cum_retention *= retention
        @printf("  %-50s  %7.1f%%  %8.1f%%\n",
            decomp.steps[i].name, rates[i] * 100, retention * 100)
    end
    println("  " * "-" ^ 70)
    @printf("  Cumulative retention product: %.4f\n", cum_retention)
    @printf("  Predicted via geometric compounding: %.1f%%\n",
        rates[1] * cum_retention * 100)
end

# ===================================================================
# Robustness sweep + full-sample comparison (diagnostic-only, skipped by default
# because Stage 12 (run_robustness.jl) writes a comparable CSV with parallel
# execution. The internal sweep here is single-threaded and would take ~9 hours
# at MWR=0.87. Set ANNUITY_RUN_DIAG_ROBUSTNESS=1 to re-enable.)
# ===================================================================
const RUN_DIAG_ROBUSTNESS = get(ENV, "ANNUITY_RUN_DIAG_ROBUSTNESS", "0") == "1"
if RUN_DIAG_ROBUSTNESS
    println("\n" * "=" ^ 70)
    println("  ROBUSTNESS: SENSITIVITY TO KEY PARAMETERS")
    println("=" ^ 70)

    robustness_configs = [
        ("gamma=1.5",      (gamma=1.5,)),
        ("gamma=2.0",      (gamma=2.0,)),
        ("gamma=2.2",      (gamma=2.2,)),
        ("gamma=2.4",      (gamma=2.4,)),
        ("gamma=2.6",      (gamma=2.6,)),
        ("gamma=2.8",      (gamma=2.8,)),
        ("gamma=3.0",      (gamma=3.0,)),
        ("gamma=4.0",      (gamma=4.0,)),
        ("beta=0.95",      (beta=0.95,)),
        ("beta=0.99",      (beta=0.99,)),
        ("MWR=0.85",       (mwr_loaded=0.85,)),
        ("MWR=0.90",       (mwr_loaded=0.90,)),
        ("inflation=1%",   (inflation_val=0.01,)),
        ("inflation=3%",   (inflation_val=0.03,)),
    ]

    @printf("\n  %-20s  %10s\n", "Configuration", "Final Ownership")
    println("  " * "-" ^ 34)

    for (label, overrides) in robustness_configs
        kw = Dict{Symbol,Any}(
            :gamma => GAMMA, :beta => BETA, :r => R_RATE,
            :theta => THETA_DFJ, :kappa => KAPPA_DFJ,
            :c_floor => C_FLOOR,
            :mwr_loaded => MWR_LOADED,
            :fixed_cost_val => FIXED_COST,
            :inflation_val => INFLATION,
            :n_wealth => N_WEALTH, :n_annuity => N_ANNUITY, :n_alpha => N_ALPHA,
            :W_max => W_MAX, :n_quad => N_QUAD,
            :age_start => AGE_START, :age_end => AGE_END,
            :annuity_grid_power => A_GRID_POW,
            :hazard_mult => HAZARD_MULT,
            :survival_pessimism => SURVIVAL_PESSIMISM,
            :min_wealth => MIN_WEALTH,
            :ss_levels => SS_LEVELS,
            :verbose => false,
        )
        for (k, v) in pairs(overrides)
            kw[k] = v
        end

        result = run_decomposition(base_surv, population; kw...)
        final_rate = result.steps[end].ownership_rate
        @printf("  %-20s  %9.1f%%\n", label, final_rate * 100)
    end

    # Full-sample comparison
    println("\n" * "=" ^ 70)
    println("  FULL-SAMPLE COMPARISON (all agents, no wealth filter)")
    println("=" ^ 70)

    full_sample = run_decomposition(
        base_surv, population;
        gamma=GAMMA, beta=BETA, r=R_RATE,
        theta=THETA_DFJ, kappa=KAPPA_DFJ,
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
        min_wealth=0.0,
        ss_levels=SS_LEVELS,
        verbose=false,
    )
    full_rate = full_sample.steps[end].ownership_rate
    @printf("\n  Full model (all %d agents, min_wealth=0):  %6.1f%%\n", n_pop, full_rate * 100)
    @printf("  Lockwood (2012) observed:                    %6.1f%%\n", 3.6)
else
    println("\nSkipping diagnostic robustness sweep + full-sample comparison.")
    println("(Stage 12 run_robustness.jl produces a parallel-executed CSV with the same data.)")
end

# ===================================================================
# Save decomposition results to CSV
# ===================================================================
tables_dir = joinpath(@__DIR__, "..", "tables")
mkpath(joinpath(tables_dir, "csv"))
mkpath(joinpath(tables_dir, "tex"))

csv_path = joinpath(tables_dir, "csv", "decomposition.csv")
open(csv_path, "w") do f
    println(f, "step,ownership_pct,mean_alpha,delta_pp,solve_time_s")
    for step in decomp.steps
        @printf(f, "%s,%.2f,%.4f,%.2f,%.1f\n",
            step.name, step.ownership_rate * 100,
            step.mean_alpha, step.delta * 100, step.solve_time)
    end
end
println("\n  Decomposition CSV saved: $csv_path")

# Retention rate table (Table 1 in manuscript)
ds = '\$'
tex_path = joinpath(tables_dir, "tex", "retention_rates.tex")
open(tex_path, "w") do f
    println(f, raw"\begin{table}[htbp]")
    println(f, raw"\centering")
    println(f, raw"\caption{Sequential Decomposition of Predicted Voluntary Annuity Ownership}")
    println(f, raw"\label{tab:retention}")
    println(f, raw"\begin{tabular}{lcccc}")
    println(f, raw"\toprule")
    println(f, "Channel & Ownership (\\%) & $(ds)\\Delta$(ds) (pp) & Retention & Cumulative \\\\")
    println(f, raw"\midrule")

    cum_retention = 1.0
    for (i, step) in enumerate(decomp.steps)
        own = step.ownership_rate * 100
        if i == 1
            @printf(f, "%s & %.1f & --- & --- & --- \\\\\n", step.name, own)
        else
            prev_own = decomp.steps[i-1].ownership_rate * 100
            delta = own - prev_own
            retention = prev_own > 0 ? own / prev_own : 0.0
            cum_retention *= retention
            @printf(f, "%s & %.1f & %+.1f & %.1f\\%% & %.4f \\\\\n",
                step.name, own, delta, retention * 100, cum_retention)
        end
    end

    println(f, raw"\midrule")
    println(f, "Observed (Lockwood 2012) & 3.6 & --- & --- & --- \\\\")
    println(f, raw"\bottomrule")
    println(f, raw"\end{tabular}")
    println(f, raw"\begin{tablenotes}")
    println(f, raw"\small")
    println(f, raw"\item Retention rate = ownership after channel / ownership before channel.")
    println(f, "Cumulative product of retention rates tracks geometric compounding.")
    println(f, raw"\end{tablenotes}")
    println(f, raw"\end{table}")
end
println("  Retention rates TeX saved: $tex_path")

# ===================================================================
# Pairwise Channel Interactions
# ===================================================================
println("\n" * "=" ^ 70)
println("  PAIRWISE CHANNEL INTERACTIONS")
println("=" ^ 70)

pw = run_pairwise_interactions(
    base_surv, population;
    gamma=GAMMA, beta=BETA, r=R_RATE,
    theta=THETA_DFJ, kappa=KAPPA_DFJ,
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
    consumption_decline_val=CONSUMPTION_DECLINE,
    health_utility_vals=Float64.(HEALTH_UTILITY),
    verbose=true,
)

# Save pairwise CSV
pw_csv_path = joinpath(tables_dir, "csv", "pairwise_interactions.csv")
open(pw_csv_path, "w") do f
    n_ch = length(pw.channel_names)
    print(f, "channel_A,channel_B,own_A,own_B,own_AB,interaction_pp")
    println(f)
    for i in 1:n_ch
        for j in (i+1):n_ch
            @printf(f, "%s,%s,%.2f,%.2f,%.2f,%.2f\n",
                pw.channel_names[i], pw.channel_names[j],
                pw.isolated_ownership[i] * 100, pw.isolated_ownership[j] * 100,
                pw.pair_ownership[i, j] * 100,
                pw.interaction_matrix[i, j] * 100)
        end
    end
end
println("  Pairwise CSV saved: $pw_csv_path")

# Save pairwise LaTeX table
pw_tex_path = joinpath(tables_dir, "tex", "pairwise_interactions.tex")
n_ch = length(pw.channel_names)
open(pw_tex_path, "w") do f
    println(f, raw"\begin{table}[htbp]")
    println(f, raw"\centering")
    println(f, raw"\caption{Pairwise Interaction Strengths, Rational and Preference Channels (pp)}")
    println(f, raw"\label{tab:pairwise}")
    println(f, raw"\begin{tabular}{l" * "c" ^ n_ch * "}")
    println(f, raw"\toprule")
    # Header row
    print(f, " ")
    for name in pw.channel_names
        print(f, " & ", name)
    end
    println(f, " \\\\")
    println(f, raw"\midrule")
    # Data rows (upper triangle only)
    for i in 1:n_ch
        print(f, pw.channel_names[i])
        for j in 1:n_ch
            if j <= i
                print(f, " & ---")
            else
                @printf(f, " & %+.1f", pw.interaction_matrix[i, j] * 100)
            end
        end
        println(f, " \\\\")
    end
    println(f, raw"\bottomrule")
    println(f, raw"\end{tabular}")
    println(f, raw"\begin{tablenotes}")
    println(f, raw"\small")
    println(f, raw"\item Each cell shows the interaction: ownership with both channels minus")
    println(f, raw"the additive prediction from individual effects. Negative values indicate")
    println(f, raw"super-additive demand reduction (channels reinforce each other).")
    println(f, raw"\end{tablenotes}")
    println(f, raw"\end{table}")
end
println("  Pairwise LaTeX saved: $pw_tex_path")

println("\n" * "=" ^ 70)
println("  DECOMPOSITION COMPLETE")
println("=" ^ 70)
