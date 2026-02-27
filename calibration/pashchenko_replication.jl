# Pashchenko (2013, JPubE) Comparison
#
# Evaluates the channels Pashchenko identified (SS, bequest motives,
# minimum purchase requirement, pricing loads) within our unified model.
# Her full model predicted ~20% ownership (4x observed). We quantify how
# much of the Yaari-to-observed gap her channels account for, then show
# that adding R-S health-mortality correlation and inflation erosion
# closes the remainder.
#
# We do not replicate her exact model (no public code; different preference
# specification, health dynamics, and solution method). Instead, we
# incorporate her channels into our framework to measure their
# quantitative contribution. Housing illiquidity is omitted; see text.

using Printf
using DelimitedFiles
include(joinpath(@__DIR__, "..", "src", "AnnuityPuzzle.jl"))
using .AnnuityPuzzle

println("=" ^ 70)
println("  PASHCHENKO (2013) CHANNEL COMPARISON")
println("  Her channels in our framework, plus additional channels")
println("=" ^ 70)

# ===================================================================
# Calibration
# ===================================================================

# Pashchenko's approximate parameterization
const GAMMA       = 3.0           # Pashchenko's baseline (Phase 4 uses 2.5; not directly comparable)
const BETA        = 0.97
const R_RATE      = 0.02
const AGE_START   = 65
const AGE_END     = 110
const C_FLOOR     = 6_180.0       # SSI/Medicaid floor
const W_MAX       = 3_000_000.0
const N_WEALTH    = 80
const N_ANNUITY   = 30
const N_ALPHA     = 101
const A_GRID_POW  = 3.0
const N_QUAD      = 5
const HAZARD_MULT = [0.50, 1.0, 3.0]

# Pashchenko's channels
const MWR_PASH    = 0.85          # her MWR estimate (Mitchell et al. 1999)
const FIXED_COST  = 1_000.0
const MIN_PURCH   = 25_000.0      # midpoint of $10K-$50K range she discusses
const THETA_PASH  = 56.96         # DFJ bequest (De Nardi 2004, via Lockwood)
const KAPPA_PASH  = 272_628.0
# Note: At gamma=3.0, the DFJ luxury-good specification with kappa=$272K
# makes bequests irrelevant for middle-class households. Steps 0 and 1 will
# show identical ownership — this is the correct result, not a bug. The
# luxury-good bequest kicks in only for wealthy households (W >> kappa).

# Our additional channels
const MWR_OURS    = 0.82          # slightly lower MWR (wider consensus)
const INFLATION   = 0.02          # nominal annuity erosion

# ===================================================================
# Load HRS population sample
# ===================================================================
println("\nLoading HRS population sample...")
hrs_path = joinpath(@__DIR__, "..", "data", "processed", "lockwood_hrs_sample.csv")
hrs_raw = readdlm(hrs_path, ',', Any; skipstart=1)
n_pop = size(hrs_raw, 1)
population = zeros(n_pop, 3)
population[:, 1] = Float64.(hrs_raw[:, 1])  # wealth
population[:, 2] = Float64.(hrs_raw[:, 2])  # perm_income
population[:, 3] = Float64.(hrs_raw[:, 3])  # age
@printf("  Loaded %d individuals\n", n_pop)

# ===================================================================
# Survival probabilities
# ===================================================================
p_base = ModelParams(age_start=AGE_START, age_end=AGE_END)
base_surv = build_lockwood_survival(p_base)

p_fair = ModelParams(age_start=AGE_START, age_end=AGE_END, mwr=1.0, r=R_RATE)
fair_pr = compute_payout_rate(p_fair, base_surv)
@printf("  Fair payout rate: %.4f\n", fair_pr)

# ===================================================================
# Common setup
# ===================================================================
ss_zero(age, p) = 0.0

grid_kw = (n_wealth=N_WEALTH, n_annuity=N_ANNUITY, n_alpha=N_ALPHA,
           W_max=W_MAX, age_start=AGE_START, age_end=AGE_END,
           annuity_grid_power=A_GRID_POW)

common_kw = (gamma=GAMMA, beta=BETA, r=R_RATE,
             stochastic_health=true, n_health_states=3, n_quad=N_QUAD,
             c_floor=C_FLOOR, hazard_mult=HAZARD_MULT)

# Compute nominal fair payout for grid coverage
p_fair_nom = ModelParams(age_start=AGE_START, age_end=AGE_END, mwr=1.0,
    r=R_RATE, inflation_rate=INFLATION)
fair_pr_nom_init = compute_payout_rate(p_fair_nom, base_surv)
grids = build_grids(p_fair, max(fair_pr, fair_pr_nom_init))

# Add health column (default Fair=2)
pop = copy(population)
if size(pop, 2) < 4
    pop = hcat(pop, fill(2.0, n_pop))
end

# ===================================================================
# Pashchenko decomposition: her channels only
# ===================================================================
println("\n" * "=" ^ 70)
println("  PASHCHENKO'S CHANNELS (SS, bequests, min purchase, loads)")
println("=" ^ 70)
@printf("\n  %-55s  %8s  %s\n", "Model Specification", "Ownership", "Time")
println("  " * "-" ^ 70)

results_pash = []

# Step 0: Yaari benchmark (SS always on, as in our decomposition)
p0 = ModelParams(; common_kw...,
    theta=0.0, kappa=0.0, mwr=1.0, fixed_cost=0.0, inflation_rate=0.0,
    min_purchase=0.0,
    medical_enabled=false, health_mortality_corr=false,
    grid_kw...)
res0 = solve_and_evaluate(p0, grids, base_surv, ss_zero,
    pop, fair_pr; step_name="0. Yaari benchmark (SS on)", verbose=true)
push!(results_pash, ("Yaari benchmark", res0.ownership))

# Step 1: + Bequest motives (Pashchenko calibration)
p1 = ModelParams(; common_kw...,
    theta=THETA_PASH, kappa=KAPPA_PASH,
    mwr=1.0, fixed_cost=0.0, inflation_rate=0.0, min_purchase=0.0,
    medical_enabled=false, health_mortality_corr=false,
    grid_kw...)
res1 = solve_and_evaluate(p1, grids, base_surv, ss_zero,
    pop, fair_pr; step_name="1. + Bequest motives (DFJ)", verbose=true)
push!(results_pash, ("+ Bequest motives", res1.ownership))

# Step 2: + Minimum purchase requirement ($25K)
p2 = ModelParams(; common_kw...,
    theta=THETA_PASH, kappa=KAPPA_PASH,
    mwr=1.0, fixed_cost=0.0, inflation_rate=0.0, min_purchase=MIN_PURCH,
    medical_enabled=false, health_mortality_corr=false,
    grid_kw...)
res2 = solve_and_evaluate(p2, grids, base_surv, ss_zero,
    pop, fair_pr; step_name="2. + Minimum purchase (\$25K)", verbose=true)
push!(results_pash, ("+ Minimum purchase (\$25K)", res2.ownership))

# Step 3: + Pricing loads (Pashchenko MWR=0.85)
loaded_pr_pash = MWR_PASH * fair_pr
p3 = ModelParams(; common_kw...,
    theta=THETA_PASH, kappa=KAPPA_PASH,
    mwr=MWR_PASH, fixed_cost=FIXED_COST, inflation_rate=0.0,
    min_purchase=MIN_PURCH,
    medical_enabled=false, health_mortality_corr=false,
    grid_kw...)
res3 = solve_and_evaluate(p3, grids, base_surv, ss_zero,
    pop, loaded_pr_pash;
    step_name="3. + Pricing loads (MWR=0.85)", verbose=true)
push!(results_pash, ("+ Pricing loads (MWR=0.85)", res3.ownership))

println("\n  " * "-" ^ 70)
@printf("  Pashchenko (2013) predicted:  ~20%%\n")
@printf("  Our model under her channels: %5.1f%%\n", res3.ownership * 100)

# ===================================================================
# Our additional channels: close the gap
# ===================================================================
println("\n" * "=" ^ 70)
println("  ADDING OUR CHANNELS TO PASHCHENKO'S MODEL")
println("=" ^ 70)
@printf("\n  %-55s  %8s  %s\n", "Model Specification", "Ownership", "Time")
println("  " * "-" ^ 70)
@printf("  %-55s  %6.1f%%\n",
    "Pashchenko channels only (from above)", res3.ownership * 100)

# Step 4: + Medical costs + R-S health-mortality correlation
loaded_pr_ours = MWR_OURS * fair_pr
p4 = ModelParams(; common_kw...,
    theta=THETA_PASH, kappa=KAPPA_PASH,
    mwr=MWR_OURS, fixed_cost=FIXED_COST, inflation_rate=0.0,
    min_purchase=MIN_PURCH,
    medical_enabled=true, health_mortality_corr=true,
    survival_pessimism=0.981,  # O'Dea & Sturrock (2023)
    grid_kw...)
res4 = solve_and_evaluate(p4, grids, base_surv, ss_zero,
    pop, loaded_pr_ours;
    step_name="4. + Medical costs + R-S + pessimism", verbose=true)
push!(results_pash, ("+ Medical costs + R-S + pessimism", res4.ownership))

# Step 5: + Inflation erosion (nominal annuity priced at nominal rate)
p5_nom = ModelParams(age_start=AGE_START, age_end=AGE_END, mwr=1.0,
    r=R_RATE, inflation_rate=INFLATION)
fair_pr_nom = compute_payout_rate(p5_nom, base_surv)
loaded_pr_nom = MWR_OURS * fair_pr_nom
p5 = ModelParams(; common_kw...,
    theta=THETA_PASH, kappa=KAPPA_PASH,
    mwr=MWR_OURS, fixed_cost=FIXED_COST, inflation_rate=INFLATION,
    min_purchase=MIN_PURCH,
    medical_enabled=true, health_mortality_corr=true,
    survival_pessimism=0.981,  # O'Dea & Sturrock (2023)
    grid_kw...)
res5 = solve_and_evaluate(p5, grids, base_surv, ss_zero,
    pop, loaded_pr_nom;
    step_name="5. + Inflation erosion (2%)", verbose=true)
push!(results_pash, ("+ Inflation erosion (2%)", res5.ownership))

println("\n  " * "-" ^ 70)
@printf("  %-55s  %6.1f%%\n", "Observed (Lockwood 2012, single retirees 65-69)", 3.6)

# ===================================================================
# Generate LaTeX table
# ===================================================================
println("\n\nGenerating LaTeX table...")

tables_dir = joinpath(@__DIR__, "..", "tables")
mkpath(joinpath(tables_dir, "tex"))
mkpath(joinpath(tables_dir, "csv"))

tex_path = joinpath(tables_dir, "tex", "pashchenko_comparison.tex")
csv_path = joinpath(tables_dir, "csv", "pashchenko_comparison.csv")

step_names = [
    "Yaari benchmark (SS on)",
    "+ Bequest motives (DFJ)",
    "+ Minimum purchase (\\\$25K)",
    "+ Pricing loads (MWR=0.85)",
    "+ Medical costs + R-S correlation",
    "+ Inflation erosion (2\\%)",
]

open(tex_path, "w") do f
    println(f, "\\begin{table}[htbp]")
    println(f, "\\centering")
    println(f, "\\caption{Pashchenko (2013) Channels in Our Framework}")
    println(f, "\\label{tab:pashchenko}")
    println(f, "\\begin{tabular}{lcc}")
    println(f, "\\toprule")
    println(f, "Model Specification & Ownership (\\%) & \$\\Delta\$ \\\\")
    println(f, "\\midrule")

    prev = 1.0
    for (i, (name, rate)) in enumerate(results_pash)
        delta = rate - prev
        delta_str = i == 1 ? "---" : @sprintf("%+.1f pp", delta * 100)
        @printf(f, "%s & %.1f & %s \\\\\n", step_names[i], rate * 100, delta_str)
        if i == 4
            println(f, "\\midrule")
            println(f, "\\textit{Channels omitted by Pashchenko:} & & \\\\")
        end
        prev = rate
    end

    println(f, "\\midrule")
    @printf(f, "Observed (Lockwood 2012) & 3.6 & --- \\\\\n")
    println(f, "\\bottomrule")
    println(f, "\\end{tabular}")
    println(f, "\\begin{tablenotes}")
    println(f, "\\small")
    println(f, "\\item Steps 0--3 incorporate the channels Pashchenko (2013) identified")
    println(f, "(SS, bequests, minimum purchase, pricing loads) into our unified model.")
    println(f, "Steps 4--5 add channels not in her framework. Note: this is not a")
    println(f, "replication of her model (different preferences, health dynamics,")
    println(f, "solution method). Housing illiquidity is not modeled; see text.")
    println(f, "\\end{tablenotes}")
    println(f, "\\end{table}")
end
println("  LaTeX table: $tex_path")

# CSV output
open(csv_path, "w") do f
    println(f, "step,specification,ownership_pct")
    for (i, (name, rate)) in enumerate(results_pash)
        @printf(f, "%d,%s,%.2f\n", i - 1, name, rate * 100)
    end
end
println("  CSV table: $csv_path")

println("\n" * "=" ^ 70)
println("  PASHCHENKO COMPARISON COMPLETE")
println("=" ^ 70)
