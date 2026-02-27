# Pashchenko (2013) Comparison
#
# Evaluates the channels Pashchenko identified (bequests, min purchase, loads)
# within our unified framework, then adds the channels she omitted
# (medical+R-S, pessimism, inflation).
#
# Starting point: Yaari + SS = 100% (our Step 1).
# This is NOT a replication—different preferences, health dynamics, solution.
#
# Usage: julia --project=. scripts/run_pashchenko_comparison.jl

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
println("  PASHCHENKO (2013) COMPARISON")
println("=" ^ 70)

# Script-specific constants (differ from baseline)
const MIN_PURCHASE = 25_000.0  # Pashchenko's minimum purchase threshold
const MWR_PASH   = 0.85        # Pashchenko uses ~0.85 MWR
const MWR_FULL   = MWR_LOADED  # Our baseline

# Load data
hrs_path = HRS_PATH
hrs_raw = readdlm(hrs_path, ',', Any; skipstart=1)
n_pop = size(hrs_raw, 1)
population = zeros(n_pop, 4)
population[:, 1] = Float64.(hrs_raw[:, 1])
population[:, 2] .= 0.0
population[:, 3] = Float64.(hrs_raw[:, 3])
if size(hrs_raw, 2) >= 4
    population[:, 4] = Float64.(hrs_raw[:, 4])  # observed health (1=Good, 2=Fair, 3=Poor)
else
    population[:, 4] .= 2.0
end
n_eligible = count(population[:, 1] .>= MIN_WEALTH)
@printf("Data loaded (%d obs, %d eligible)\n\n", n_pop, n_eligible)

# Survival and payout rates
p_base = ModelParams(age_start=AGE_START, age_end=AGE_END)
base_surv = build_lockwood_survival(p_base)
p_fair = ModelParams(age_start=AGE_START, age_end=AGE_END, mwr=1.0, r=R_RATE)
fair_pr = compute_payout_rate(p_fair, base_surv)

# Nominal payout rate for inflation step
p_fair_nom = ModelParams(age_start=AGE_START, age_end=AGE_END, mwr=1.0,
                         r=R_RATE, inflation_rate=INFLATION)
fair_pr_nom = compute_payout_rate(p_fair_nom, base_surv)

# Common parameters
grid_kw = (n_wealth=N_WEALTH, n_annuity=N_ANNUITY, n_alpha=N_ALPHA,
           W_max=W_MAX, age_start=AGE_START, age_end=AGE_END,
           annuity_grid_power=A_GRID_POW)
common_kw = (gamma=GAMMA, beta=BETA, r=R_RATE,
             stochastic_health=true, n_health_states=3, n_quad=N_QUAD,
             c_floor=C_FLOOR, hazard_mult=HAZARD_MULT)

# Build grids
p_grid = ModelParams(; common_kw..., mwr=1.0, grid_kw...)
grids = build_grids(p_grid, max(fair_pr, fair_pr_nom))

# Filter population
pop = copy(population)
mask = pop[:, 1] .>= MIN_WEALTH
pop = pop[mask, :]
n = size(pop, 1)
if size(pop, 2) < 4
    pop = hcat(pop, fill(2.0, n))  # health = Fair
end

const SS_LEVELS = SS_QUARTILE_LEVELS

@printf("  %-55s  %8s  %8s  %s\n", "Model Specification", "Own(%)", "Mean a", "Time")
println("  " * "-" ^ 85)

# Step 0: Yaari + SS (our baseline starting point = 100%)
p0 = ModelParams(; common_kw..., theta=0.0, kappa=0.0, mwr=1.0,
    fixed_cost=0.0, inflation_rate=0.0,
    medical_enabled=false, health_mortality_corr=false, grid_kw...)
res0 = solve_and_evaluate(p0, grids, base_surv, SS_LEVELS, pop, fair_pr;
    step_name="0. Yaari benchmark (SS on)", verbose=true)
flush(stdout)

# Step 1: + Bequest motives (DFJ)
p1 = ModelParams(; common_kw..., theta=THETA_DFJ, kappa=KAPPA_DFJ,
    mwr=1.0, fixed_cost=0.0, inflation_rate=0.0,
    medical_enabled=false, health_mortality_corr=false, grid_kw...)
res1 = solve_and_evaluate(p1, grids, base_surv, SS_LEVELS, pop, fair_pr;
    step_name="1. + Bequest motives (DFJ)", verbose=true)
flush(stdout)

# Step 2: + Minimum purchase ($25K)
# Apply min purchase by zeroing out alpha for agents with alpha*W < $25K
p2 = ModelParams(; common_kw..., theta=THETA_DFJ, kappa=KAPPA_DFJ,
    mwr=1.0, fixed_cost=0.0, inflation_rate=0.0,
    medical_enabled=false, health_mortality_corr=false,
    min_purchase=MIN_PURCHASE, grid_kw...)
res2 = solve_and_evaluate(p2, grids, base_surv, SS_LEVELS, pop, fair_pr;
    step_name="2. + Minimum purchase (\$25K)", verbose=true)
flush(stdout)

# Step 3: + Pricing loads (MWR=0.85, Pashchenko's estimate)
loaded_pr_pash = MWR_PASH * fair_pr
p3 = ModelParams(; common_kw..., theta=THETA_DFJ, kappa=KAPPA_DFJ,
    mwr=MWR_PASH, fixed_cost=FIXED_COST, inflation_rate=0.0,
    medical_enabled=false, health_mortality_corr=false,
    min_purchase=MIN_PURCHASE, grid_kw...)
res3 = solve_and_evaluate(p3, grids, base_surv, SS_LEVELS, pop, loaded_pr_pash;
    step_name="3. + Pricing loads (MWR=0.85)", verbose=true)
flush(stdout)

println()
println("  " * "-" ^ 85)
println("  Channels omitted by Pashchenko (2013):")
println("  " * "-" ^ 85)

# Step 4: + Medical costs + R-S correlation
loaded_pr_pash2 = MWR_PASH * fair_pr  # same MWR
p4 = ModelParams(; common_kw..., theta=THETA_DFJ, kappa=KAPPA_DFJ,
    mwr=MWR_PASH, fixed_cost=FIXED_COST, inflation_rate=0.0,
    medical_enabled=true, health_mortality_corr=true,
    min_purchase=MIN_PURCHASE, grid_kw...)
res4 = solve_and_evaluate(p4, grids, base_surv, SS_LEVELS, pop, loaded_pr_pash;
    step_name="4. + Medical costs + R-S correlation", verbose=true)
flush(stdout)

# Step 5: + Survival pessimism
p5 = ModelParams(; common_kw..., theta=THETA_DFJ, kappa=KAPPA_DFJ,
    mwr=MWR_PASH, fixed_cost=FIXED_COST, inflation_rate=0.0,
    medical_enabled=true, health_mortality_corr=true,
    survival_pessimism=SURVIVAL_PESSIMISM,
    min_purchase=MIN_PURCHASE, grid_kw...)
res5 = solve_and_evaluate(p5, grids, base_surv, SS_LEVELS, pop, loaded_pr_pash;
    step_name="5. + Survival pessimism (psi=0.981)", verbose=true)
flush(stdout)

# Step 6: + Full loads (MWR=0.82) + Inflation (2%)
loaded_pr_full_nom = MWR_FULL * fair_pr_nom
p6 = ModelParams(; common_kw..., theta=THETA_DFJ, kappa=KAPPA_DFJ,
    mwr=MWR_FULL, fixed_cost=FIXED_COST, inflation_rate=INFLATION,
    medical_enabled=true, health_mortality_corr=true,
    survival_pessimism=SURVIVAL_PESSIMISM,
    min_purchase=MIN_PURCHASE, grid_kw...)
res6 = solve_and_evaluate(p6, grids, base_surv, SS_LEVELS, pop, loaded_pr_full_nom;
    step_name="6. + Full loads (MWR=0.82) + Inflation (2%)", verbose=true)
flush(stdout)

println()
println("  " * "-" ^ 85)
@printf("  Observed (Lockwood 2012, single retirees 65-69)        3.6%%\n")

# Write results
results = [
    ("Yaari benchmark (SS on)", res0.ownership),
    ("+ Bequest motives (DFJ)", res1.ownership),
    ("+ Minimum purchase (25K)", res2.ownership),
    ("+ Pricing loads (MWR=0.85)", res3.ownership),
    ("+ Medical costs + R-S correlation", res4.ownership),
    ("+ Survival pessimism", res5.ownership),
    ("+ Full loads + Inflation", res6.ownership),
]

# CSV
csv_path = joinpath(@__DIR__, "..", "tables", "csv", "pashchenko_comparison.csv")
open(csv_path, "w") do f
    println(f, "step,ownership")
    for (name, own) in results
        @printf(f, "%s,%.1f%%\n", name, own * 100)
    end
end
println("\nCSV written: $csv_path")

# LaTeX
tex_path = joinpath(@__DIR__, "..", "tables", "tex", "pashchenko_comparison.tex")
open(tex_path, "w") do f
    println(f, raw"\begin{table}[htbp]")
    println(f, raw"\centering")
    println(f, raw"\caption{Pashchenko (2013) Channels in Our Framework}")
    println(f, raw"\label{tab:pashchenko}")
    println(f, raw"\begin{tabular}{lcc}")
    println(f, raw"\toprule")
    println(f, "Model Specification & Ownership (\\%) & \$\\Delta\$ \\\\")
    println(f, raw"\midrule")

    prev = results[1][2]
    @printf(f, "Yaari benchmark (SS on) & %.1f & --- \\\\\n", results[1][2] * 100)
    for i in 2:4
        name, own = results[i]
        delta = own - prev
        @printf(f, "%s & %.1f & %+.1f pp \\\\\n", name, own * 100, delta * 100)
        prev = own
    end

    println(f, raw"\midrule")
    println(f, "\\textit{Channels omitted by Pashchenko:} & & \\\\")

    for i in 5:length(results)
        name, own = results[i]
        delta = own - prev
        @printf(f, "%s & %.1f & %+.1f pp \\\\\n", name, own * 100, delta * 100)
        prev = own
    end

    println(f, raw"\midrule")
    println(f, "Observed (Lockwood 2012) & 3.6 & --- \\\\")
    println(f, raw"\bottomrule")
    println(f, raw"\end{tabular}")
    println(f, raw"\begin{tablenotes}")
    println(f, raw"\small")
    println(f, raw"\item Steps 0--3 incorporate the channels Pashchenko (2013) identified")
    println(f, raw"(SS, bequests, minimum purchase, pricing loads) into our unified model.")
    println(f, raw"Steps 4--6 add channels not in her framework. Note: this is not a")
    println(f, raw"replication of her model (different preferences, health dynamics,")
    println(f, raw"solution method). Housing illiquidity is not modeled; see text.")
    println(f, raw"\end{tablenotes}")
    println(f, raw"\end{table}")
end
println("LaTeX written: $tex_path")

println("\n" * "=" ^ 70)
println("  PASHCHENKO COMPARISON COMPLETE")
println("=" ^ 70)
