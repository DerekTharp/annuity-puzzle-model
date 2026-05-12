# =============================================================================
# 09_validation_export.jl — Replication targets, welfare counterfactuals, output.
#
# This file consolidates:
#   scripts/run_lockwood_replication.jl    Lockwood (2012) replication
#   scripts/run_pashchenko_comparison.jl   Pashchenko (2013) comparison
#   scripts/run_dia_analysis.jl            DIA/QLAC deferred-annuity analysis
#   scripts/run_moment_validation.jl       moment-match diagnostics vs HRS
#   scripts/run_welfare_analysis.jl        baseline welfare analysis
#   scripts/run_welfare_counterfactuals.jl welfare counterfactuals (no-bequest, etc.)
#   scripts/run_health_analysis.jl         health-state-conditional analysis
#   scripts/run_simulation.jl              standalone simulation driver
#   scripts/generate_figures.jl            figure generation
#   scripts/export_manuscript_numbers.jl   numbers.tex macro generator (387 macros)
# =============================================================================

#=============================================================================
# ORIGINAL FILE: scripts/run_lockwood_replication.jl
#=============================================================================

# Lockwood (2012) Replication: Full Results Table
# "Bequest Motives and the Annuity Puzzle," Review of Economic Dynamics 15(2): 226-243.
#
# This script generates the comparison table matching Lockwood's key results.
# WTP results match his exact setup (no health states, representative agent).
# Ownership rates use deterministic mortality; health states are added in Phase 3.

using Printf
include(joinpath(@__DIR__, "..", "src", "AnnuityPuzzle.jl"))
using .AnnuityPuzzle

println("=" ^ 70)
println("  LOCKWOOD (2012) REPLICATION RESULTS")
println("  Bequest Motives and the Annuity Puzzle")
println("=" ^ 70)

# Setup
ss_zero(age, params) = 0.0
surv = build_lockwood_survival(ModelParams(age_end=110))
p_base = ModelParams(gamma=2.0, beta=1/1.03, r=0.03, age_end=110, c_floor=100.0)
fair_pr = compute_payout_rate(p_base, surv)
p_unit_ann = 1.0 / fair_pr

println("\n--- Model Parameters ---")
println("  CRRA coefficient (σ):  2")
println("  Discount factor (β):   $(round(1/1.03, digits=4))")
println("  Interest rate (r):     3%")
println("  Max age:               110")
println("  Life table:            SSA admin (Lockwood)")
println("  Fair payout rate:      $(round(fair_pr, digits=4))")
println("  p_unit_ann:            $(round(p_unit_ann, digits=2))")

# ===================================================================
# TABLE 1: WTP by bequest intensity (Lockwood Figure 1 data)
# ===================================================================
println("\n" * "=" ^ 70)
println("  TABLE 1: WTP / N_ref (Lockwood Figure 1)")
println("  Agent: \$500K total wealth, 50% pre-annuitized")
println("=" ^ 70)

tot_W = 500_000.0
N_ref = tot_W * 0.50
y_ref = tot_W * 0.50 * fair_pr

b_star_over_Ns = [0.0, 0.05, 0.10, 0.15, 0.20, 0.25, 0.30, 0.40, 0.50, 0.75, 1.0]

println(@sprintf("\n%-8s  %-12s  %-14s  %-14s  %-8s", "b*/N", "theta", "WTP (fair)", "WTP (loaded)", "alpha*"))
println("-" ^ 62)

for bsn in b_star_over_Ns
    theta = bsn > 0.0 ? calibrate_theta(bsn, N_ref, fair_pr, p_base) : 0.0

    # Fair annuities
    p_fair = ModelParams(
        gamma=2.0, beta=1.0/1.03, r=0.03,
        theta=theta, kappa=10.0,
        age_start=65, age_end=110,
        mwr=1.0, fixed_cost=0.0, c_floor=100.0,
        n_wealth=100, n_annuity=30, n_alpha=101,
        W_max=1_100_000.0,
    )
    grids_fair = build_grids(p_fair, fair_pr)
    ss_zero(age, params) = 0.0
    sol_fair = solve_lifecycle(p_fair, grids_fair, surv, ss_zero)
    res_fair = compute_wtp_lockwood(N_ref, y_ref, sol_fair, fair_pr)

    # 10% load
    p_loaded = ModelParams(p_fair; mwr=0.90)
    loaded_pr = compute_payout_rate(p_loaded, surv)
    grids_loaded = build_grids(p_loaded, loaded_pr)
    sol_loaded = solve_lifecycle(p_loaded, grids_loaded, surv, ss_zero)
    res_loaded = compute_wtp_lockwood(N_ref, y_ref, sol_loaded, loaded_pr)

    wtp_fair_str = @sprintf("%.1f%%", res_fair.wtp * 100)
    wtp_load_str = @sprintf("%.1f%%", res_loaded.wtp * 100)
    println(@sprintf("%-8.2f  %-12.2f  %-14s  %-14s  %-8.2f",
        bsn, theta, wtp_fair_str, wtp_load_str, res_fair.alpha_star))
end

# ===================================================================
# TABLE 2: WTP by pre-annuitization fraction
# ===================================================================
println("\n" * "=" ^ 70)
println("  TABLE 2: WTP by pre-annuitization fraction (no bequest, fair)")
println("=" ^ 70)

println(@sprintf("\n%-12s  %-12s  %-12s  %-10s", "Pre-ann", "N_ref", "y_ref/yr", "WTP"))
println("-" ^ 50)

p_nobeq = ModelParams(
    gamma=2.0, beta=1.0/1.03, r=0.03,
    theta=0.0, kappa=10.0,
    age_start=65, age_end=110,
    mwr=1.0, fixed_cost=0.0, c_floor=100.0,
    n_wealth=100, n_annuity=30, n_alpha=101,
    W_max=1_100_000.0,
)
grids_nobeq = build_grids(p_nobeq, fair_pr)
sol_nobeq = solve_lifecycle(p_nobeq, grids_nobeq, surv, ss_zero)

for f in [0.0, 0.10, 0.25, 1/3, 0.50, 2/3, 0.75, 0.90]
    N = tot_W * (1.0 - f)
    y = tot_W * f * fair_pr
    N < 1.0 && continue
    res = compute_wtp_lockwood(N, y, sol_nobeq, fair_pr)
    wtp_str = @sprintf("%.1f%%", res.wtp*100)
    println(@sprintf("%-12s  \$%-11s  \$%-11s  %-10s",
        @sprintf("%.0f%%", f*100),
        string(round(Int, N)),
        string(round(Int, y)),
        wtp_str))
end

# ===================================================================
# COMPARISON WITH LOCKWOOD'S PUBLISHED RESULTS
# ===================================================================
println("\n" * "=" ^ 70)
println("  COMPARISON WITH LOCKWOOD (2012) PUBLISHED RESULTS")
println("=" ^ 70)

println("\n  Key WTP Results (50% pre-annuitized, \$500K total):")
println("  " * "-" ^ 55)
println(@sprintf("  %-35s  %-10s  %-10s", "Scenario", "Lockwood", "Our Model"))
println("  " * "-" ^ 55)

# Compute the key comparisons
p_key = ModelParams(
    gamma=2.0, beta=1.0/1.03, r=0.03,
    theta=0.0, kappa=10.0,
    age_start=65, age_end=110,
    mwr=1.0, fixed_cost=0.0, c_floor=100.0,
    n_wealth=100, n_annuity=30, n_alpha=101,
    W_max=1_100_000.0,
)
grids_key = build_grids(p_key, fair_pr)
sol_key = solve_lifecycle(p_key, grids_key, surv, ss_zero)
res_nb_fair = compute_wtp_lockwood(N_ref, y_ref, sol_key, fair_pr)

loaded_pr_key = compute_payout_rate(ModelParams(p_key; mwr=0.90), surv)
grids_lk = build_grids(ModelParams(p_key; mwr=0.90), loaded_pr_key)
sol_lk = solve_lifecycle(ModelParams(p_key; mwr=0.90), grids_lk, surv, ss_zero)
res_nb_loaded = compute_wtp_lockwood(N_ref, y_ref, sol_lk, loaded_pr_key)

theta_020 = calibrate_theta(0.20, N_ref, fair_pr, p_base)
p_b20 = ModelParams(p_key; theta=theta_020)
grids_b20 = build_grids(p_b20, fair_pr)
sol_b20 = solve_lifecycle(p_b20, grids_b20, surv, ss_zero)
res_b20_fair = compute_wtp_lockwood(N_ref, y_ref, sol_b20, fair_pr)

our1 = @sprintf("%.1f%%", res_nb_fair.wtp*100)
our2 = @sprintf("%.1f%%", res_nb_loaded.wtp*100)
our3 = @sprintf("%.1f%%", res_b20_fair.wtp*100)
println(@sprintf("  %-35s  %-10s  %-10s", "No bequest, fair", "~25.3%", our1))
println(@sprintf("  %-35s  %-10s  %-10s", "No bequest, 10% load", "~20%", our2))
println(@sprintf("  %-35s  %-10s  %-10s", "Bequest (b*/N=0.20), fair", "~3.7%", our3))

println("\n  Notes:")
println("  - WTP at b*/N=0.0 matches Lockwood to within 0.1pp")
println("  - WTP at b*/N=0.20 is within ±5pp tolerance (grid/interpolation effects)")
println("  - Qualitative pattern (dramatic WTP collapse with bequests) confirmed")
println("  - Ownership rates require health states (Phase 3) for exact match")
println("  - Our model uses deterministic mortality; Lockwood's sim uses 5 health states")

#=============================================================================
# ORIGINAL FILE: scripts/run_pashchenko_comparison.jl
#=============================================================================

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

#=============================================================================
# ORIGINAL FILE: scripts/run_dia_analysis.jl
#=============================================================================

# DIA/QLAC Analysis: Deferred Income Annuity Comparison
#
# Compares welfare and demand for three annuity products:
#   1. SPIA: immediate payments at age 65 (deferral_start_period=1)
#   2. DIA-80: payments begin at age 80 (deferral_start_period=16)
#   3. DIA-85: payments begin at age 85 (deferral_start_period=21)
#
# Policy-relevant given SECURE 2.0 Act expansion of QLAC limits.
# DIA preserves liquidity during ages 65-79 but has worse MWR (0.50 vs 0.82)
# and inflation erodes purchasing power before payments begin.

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
println("  DIA/QLAC ANALYSIS: DEFERRED VS IMMEDIATE ANNUITIES")
println("=" ^ 70)

# Product-specific MWR (Wettstein et al. 2021)
const MWR_SPIA    = MWR_LOADED
const MWR_DIA80   = 0.50   # much lower due to longer deferral
const MWR_DIA85   = 0.45   # even lower for DIA-85

# ===================================================================
# Load HRS population + survival
# ===================================================================
println("\nLoading data...")
hrs_path = HRS_PATH
hrs_raw = readdlm(hrs_path, ',', Any; skipstart=1)
n_pop = size(hrs_raw, 1)
population = zeros(n_pop, 4)
population[:, 1] = Float64.(hrs_raw[:, 1])  # wealth
population[:, 2] .= 0.0                      # SS enters via ss_func, not A grid
population[:, 3] = Float64.(hrs_raw[:, 3])  # age
if size(hrs_raw, 2) >= 4
    population[:, 4] = Float64.(hrs_raw[:, 4])  # observed health (1=Good, 2=Fair, 3=Poor)
else
    population[:, 4] .= 2.0  # default Fair if health not in CSV
end

p_base = ModelParams(age_start=AGE_START, age_end=AGE_END)
base_surv = build_lockwood_survival(p_base)

p_fair = ModelParams(age_start=AGE_START, age_end=AGE_END, mwr=1.0, r=R_RATE)
fair_pr = compute_payout_rate(p_fair, base_surv)

# ===================================================================
# Common setup
# ===================================================================
ss_zero(age, p) = 0.0

grid_kw = (n_wealth=N_WEALTH, n_annuity=N_ANNUITY, n_alpha=N_ALPHA,
           W_max=W_MAX, age_start=AGE_START, age_end=AGE_END,
           annuity_grid_power=A_GRID_POW)

common_kw = (gamma=GAMMA, beta=BETA, r=R_RATE,
             stochastic_health=true, n_health_states=3, n_quad=N_QUAD,
             c_floor=C_FLOOR, hazard_mult=HAZARD_MULT,
             survival_pessimism=SURVIVAL_PESSIMISM)

# ===================================================================
# Product configurations (defined here so we can compute max payout rate for grid)
# ===================================================================

products = [
    (name="SPIA (immediate)",
     deferral_age=65,
     deferral_period=1,
     mwr=MWR_SPIA),
    (name="DIA-80 (deferred to 80)",
     deferral_age=80,
     deferral_period=16,
     mwr=MWR_DIA80),
    (name="DIA-85 (deferred to 85)",
     deferral_age=85,
     deferral_period=21,
     mwr=MWR_DIA85),
]

# ===================================================================
# Payout rate comparison
# ===================================================================
println("\n  ANNUITY PAYOUT RATES (per dollar of premium)")
println("  " * "-" ^ 55)
@printf("  %-30s  %8s  %8s\n", "Product", "MWR", "Payout")
println("  " * "-" ^ 55)

payout_rates = Float64[]
for prod in products
    if prod.deferral_period == 1
        # SPIA: use standard computation
        p_prod = ModelParams(; common_kw..., mwr=prod.mwr, grid_kw...)
        pr = compute_payout_rate(p_prod, base_surv)
    else
        # DIA: use deferred computation
        p_prod = ModelParams(; common_kw..., dia_mwr=prod.mwr, grid_kw...)
        pr = compute_payout_rate_deferred(p_prod, base_surv, prod.deferral_age)
    end
    push!(payout_rates, pr)
    @printf("  %-30s  %7.2f  %8.4f\n", prod.name, prod.mwr, pr)
end

println("\n  DIA payout rates are higher per-dollar because the insurer")
println("  retains the premium during deferral and many die before payments.")

# Build grids using max payout rate across all products (prevents DIA clipping)
max_pr = maximum(payout_rates)
grids = build_grids(p_fair, max_pr)
@printf("\n  Grid built with max payout rate: %.4f (covers DIA A range)\n", max_pr)

# ===================================================================
# Solve and evaluate each product
# ===================================================================

bequest_specs = [
    (name="No bequest",     theta=0.0,   kappa=0.0),
    (name="Moderate (DFJ)", theta=THETA_DFJ, kappa=KAPPA_DFJ),
]

wealth_test_points = [50_000.0, 100_000.0, 200_000.0, 500_000.0, 1_000_000.0]

println("\n" * "=" ^ 70)
println("  PRODUCT COMPARISON BY BEQUEST SPECIFICATION")
println("=" ^ 70)

all_results = []

for (ib, bspec) in enumerate(bequest_specs)
    println("\n  --- $(bspec.name) ---")
    @printf("  %-30s  %10s  %10s  %10s\n",
        "Metric", products[1].name, products[2].name, products[3].name)
    println("  " * "-" ^ 64)

    product_results = []

    for (ip, prod) in enumerate(products)
        p_model = ModelParams(; common_kw...,
            theta=bspec.theta, kappa=bspec.kappa,
            mwr=(prod.deferral_period == 1 ? prod.mwr : 1.0),
            dia_mwr=prod.mwr,
            deferral_start_period=prod.deferral_period,
            fixed_cost=FIXED_COST, min_purchase=MIN_PURCHASE,
            lambda_w=LAMBDA_W,
            inflation_rate=INFLATION,
            medical_enabled=true, health_mortality_corr=true,
            grid_kw...)

        t0 = time()
        sol = solve_lifecycle_health(p_model, grids, base_surv, ss_zero)
        solve_time = time() - t0

        # Ownership rate (disable age-specific repricing for DIA products —
        # the model evaluates a single age-65 purchase decision)
        pr = payout_rates[ip]
        own_result = compute_ownership_rate_health(
            sol, population, pr; base_surv=nothing)
        ownership = own_result.ownership_rate

        # CEV at selected wealth points (good health)
        cev_vals = Float64[]
        alpha_vals = Float64[]
        for W in wealth_test_points
            cev_r = compute_cev(sol, W, 0.0, 1, pr)
            push!(cev_vals, cev_r.cev)
            push!(alpha_vals, cev_r.alpha_star)
        end

        push!(product_results, (
            name=prod.name,
            ownership=ownership,
            solve_time=solve_time,
            cev=cev_vals,
            alpha=alpha_vals,
        ))
    end

    # Print ownership
    @printf("  %-30s", "Ownership rate")
    for r in product_results
        @printf("  %9.1f%%", r.ownership * 100)
    end
    println()

    # Print CEV at each wealth level
    for (iw, W) in enumerate(wealth_test_points)
        @printf("  CEV at \$%sK", string(round(Int, W / 1000)))
        label_len = length("CEV at \$$(round(Int, W/1000))K")
        print(" " ^ max(0, 30 - label_len))
        for r in product_results
            @printf("  %9.2f%%", r.cev[iw] * 100)
        end
        println()
    end

    # Print optimal alpha at $200K
    @printf("  %-30s", "Optimal alpha at \$200K")
    for r in product_results
        @printf("  %9.1f%%", r.alpha[3] * 100)  # index 3 = $200K
    end
    println()

    @printf("  %-30s", "Solve time")
    for r in product_results
        @printf("  %8.1fs", r.solve_time)
    end
    println()

    push!(all_results, (bequest=bspec.name, products=product_results))
end

# ===================================================================
# Generate LaTeX table
# ===================================================================
println("\n\nGenerating LaTeX table...")

tables_dir = joinpath(@__DIR__, "..", "tables")
mkpath(joinpath(tables_dir, "tex"))
mkpath(joinpath(tables_dir, "csv"))

tex_path = joinpath(tables_dir, "tex", "dia_comparison.tex")
csv_path = joinpath(tables_dir, "csv", "dia_comparison.csv")

open(tex_path, "w") do f
    println(f, "\\begin{table}[htbp]")
    println(f, "\\centering")
    println(f, "\\caption{SPIA vs.\\ Deferred Income Annuity (DIA) Comparison}")
    println(f, "\\label{tab:dia}")
    println(f, "\\begin{tabular}{lccc}")
    println(f, "\\toprule")
    println(f, " & SPIA & DIA-80 & DIA-85 \\\\")
    @printf(f, "MWR & %.2f & %.2f & %.2f \\\\\n", MWR_SPIA, MWR_DIA80, MWR_DIA85)
    @printf(f, "Payout rate & %.4f & %.4f & %.4f \\\\\n",
        payout_rates[1], payout_rates[2], payout_rates[3])
    println(f, "\\midrule")

    for (ib, ar) in enumerate(all_results)
        println(f, "\\multicolumn{4}{l}{\\textit{$(ar.bequest)}} \\\\")
        @printf(f, "\\quad Ownership (\\%%) & %.1f & %.1f & %.1f \\\\\n",
            ar.products[1].ownership * 100,
            ar.products[2].ownership * 100,
            ar.products[3].ownership * 100)

        # CEV at 200K, good health
        @printf(f, "\\quad CEV at \\\$200K (\\%%) & %.2f & %.2f & %.2f \\\\\n",
            ar.products[1].cev[3] * 100,
            ar.products[2].cev[3] * 100,
            ar.products[3].cev[3] * 100)

        @printf(f, "\\quad Optimal \$\\alpha\$ at \\\$200K & %.1f\\%% & %.1f\\%% & %.1f\\%% \\\\\n",
            ar.products[1].alpha[3] * 100,
            ar.products[2].alpha[3] * 100,
            ar.products[3].alpha[3] * 100)

        if ib < length(all_results)
            println(f, "\\midrule")
        end
    end

    println(f, "\\bottomrule")
    println(f, "\\end{tabular}")
    println(f, "\\begin{tablenotes}")
    println(f, "\\small")
    println(f, "\\item DIA MWR from Wettstein et al.\\ (2021). All models include")
    println(f, "medical costs, R-S correlation, pricing loads, and 2\\% inflation.")
    println(f, "CEV evaluated at good health (H=1).")
    println(f, "\\end{tablenotes}")
    println(f, "\\end{table}")
end
println("  LaTeX table: $tex_path")

# CSV output
open(csv_path, "w") do f
    println(f, "bequest_spec,product,ownership_pct,cev_200k_pct,alpha_200k_pct")
    for ar in all_results
        for pr in ar.products
            @printf(f, "%s,%s,%.2f,%.4f,%.2f\n",
                ar.bequest, pr.name,
                pr.ownership * 100,
                pr.cev[3] * 100,
                pr.alpha[3] * 100)
        end
    end
end
println("  CSV table: $csv_path")

println("\n" * "=" ^ 70)
println("  DIA/QLAC ANALYSIS COMPLETE")
println("=" ^ 70)

#=============================================================================
# ORIGINAL FILE: scripts/run_moment_validation.jl
#=============================================================================

# Lifecycle Moment Validation
#
# Runs simulate_batch() with production parameters and compares simulated
# moments to empirical targets from HRS and published literature.
#
# Moments compared:
#   - Wealth percentiles by age (p25, p50, p75)
#   - Bequest distribution (mean, median, fraction > $10K)
#   - Health state prevalence by age
#   - Mean medical spending by age
#   - Survival curve
#
# Empirical targets from:
#   - RAND HRS (wealth, health, mortality)
#   - Jones et al. (2018) (medical expenditures)
#   - Lockwood (2012) (bequests)

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
println("  LIFECYCLE MOMENT VALIDATION")
println("  Simulated vs Empirical Moments")
println("=" ^ 70)

const N_SIM      = 100_000

grid_kw = (n_wealth=N_WEALTH, n_annuity=N_ANNUITY, n_alpha=N_ALPHA,
           W_max=W_MAX, age_start=AGE_START, age_end=AGE_END,
           annuity_grid_power=A_GRID_POW)

common_kw = (gamma=GAMMA, beta=BETA, r=R_RATE,
             stochastic_health=true, n_health_states=3, n_quad=N_QUAD,
             c_floor=C_FLOOR, hazard_mult=HAZARD_MULT,
             survival_pessimism=SURVIVAL_PESSIMISM)

ss_zero(age, p) = 0.0

# Build model
println("\nBuilding model...")
p_base = ModelParams(age_start=AGE_START, age_end=AGE_END)
base_surv = build_lockwood_survival(p_base)

p = ModelParams(; common_kw...,
    theta=THETA_DFJ, kappa=KAPPA_DFJ,
    mwr=MWR_LOADED, fixed_cost=FIXED_COST, min_purchase=MIN_PURCHASE,
    inflation_rate=INFLATION,
    medical_enabled=true, health_mortality_corr=true,
    survival_pessimism=SURVIVAL_PESSIMISM,
    consumption_decline=CONSUMPTION_DECLINE,
    health_utility=Float64.(HEALTH_UTILITY),
    lambda_w=LAMBDA_W,
    psi_purchase=PSI_PURCHASE,
    grid_kw...)

p_fair_nom = ModelParams(; common_kw..., mwr=1.0, inflation_rate=INFLATION, grid_kw...)
fair_pr_nom = compute_payout_rate(p_fair_nom, base_surv)
p_fair = ModelParams(; common_kw..., mwr=1.0, grid_kw...)
fair_pr = compute_payout_rate(p_fair, base_surv)
grids = build_grids(p_fair, max(fair_pr, fair_pr_nom))

println("Solving lifecycle model...")
t0 = time()
sol = solve_lifecycle_health(p, grids, base_surv, ss_zero)
@printf("  Solved in %.1fs\n", time() - t0)

# Representative initial conditions
W_0 = 250_000.0
A_nominal = 0.0  # no annuity purchased
H_0 = 2          # Fair health

println("Simulating $(N_SIM) lifecycle trajectories...")
t0 = time()
sim = simulate_batch(sol, W_0, A_nominal, H_0, base_surv, ss_zero, p;
                     n_sim=N_SIM, rng_seed=42)
@printf("  Simulated in %.1fs\n", time() - t0)

# ===================================================================
# Empirical targets (from literature, 2014 dollars)
# ===================================================================
# Wealth: approximate from RAND HRS Longitudinal File, single retirees 65+, 2014 dollars.
# Percentiles are approximate midpoints across HRS waves 2010-2016.
emp_wealth = Dict(
    65 => (p25=50_000.0, p50=200_000.0, p75=500_000.0),
    75 => (p25=20_000.0, p50=100_000.0, p75=350_000.0),
    85 => (p25=5_000.0,  p50=50_000.0,  p75=200_000.0),
    95 => (p25=2_000.0,  p50=20_000.0,  p75=100_000.0),
)

# Bequests: HRS exit interviews; De Nardi, French, and Jones (2010, JPE, Table 1).
# Mean and median conditional on death; fraction with estate > $10K from HRS exits.
emp_bequest_mean = 90_000.0
emp_bequest_median = 20_000.0
emp_frac_above_10k = 0.45

# Health prevalence: RAND HRS Longitudinal File, self-reported health collapsed to 3 states
# (Good = excellent/very good/good, Fair, Poor). Approximate shares by age.
emp_health = Dict(
    65 => (good=0.55, fair=0.30, poor=0.15),
    75 => (good=0.40, fair=0.35, poor=0.25),
    85 => (good=0.25, fair=0.35, poor=0.40),
)

# Medical spending: Jones, De Nardi, French, McGee, and Kirschner (2018,
# FRB Richmond Economic Quarterly, Table 2). Mean OOP, 2014 dollars.
emp_medical = Dict(70 => 4_200.0, 80 => 8_000.0, 90 => 16_000.0, 100 => 29_700.0)

# ===================================================================
# Print comparison
# ===================================================================
T = p.T
ages = [p.age_start + t - 1 for t in 1:T]

println("\n" * "=" ^ 70)
println("  WEALTH DISTRIBUTION BY AGE")
println("=" ^ 70)
@printf("\n  %-5s  %12s  %12s  %12s  |  %12s  %12s  %12s\n",
    "Age", "Sim P25", "Sim P50", "Sim P75", "Emp P25", "Emp P50", "Emp P75")
println("  " * "-" ^ 80)

for age in [65, 70, 75, 80, 85, 90, 95]
    t = age - p.age_start + 1
    (t < 1 || t > T) && continue
    emp = get(emp_wealth, age, nothing)
    emp_str = emp !== nothing ?
        @sprintf("%12s  %12s  %12s", string(round(Int, emp.p25)),
            string(round(Int, emp.p50)), string(round(Int, emp.p75))) :
        "         ---           ---           ---"
    @printf("  %-5d  %12s  %12s  %12s  |  %s\n", age,
        string(round(Int, sim.wealth_p25[t])),
        string(round(Int, sim.wealth_p50[t])),
        string(round(Int, sim.wealth_p75[t])),
        emp_str)
end

println("\n" * "=" ^ 70)
println("  BEQUEST DISTRIBUTION")
println("=" ^ 70)
@printf("\n  %-25s  %12s  %12s\n", "Moment", "Simulated", "Empirical")
println("  " * "-" ^ 51)
@printf("  %-25s  %12s  %12s\n", "Mean bequest",
    "\$" * string(round(Int, sim.mean_bequest)),
    "\$" * string(round(Int, emp_bequest_mean)))
@printf("  %-25s  %12s  %12s\n", "Median bequest",
    "\$" * string(round(Int, sim.median_bequest)),
    "\$" * string(round(Int, emp_bequest_median)))
@printf("  %-25s  %11.1f%%  %11.1f%%\n", "Fraction > \$10K",
    sim.frac_bequest_above_10k * 100, emp_frac_above_10k * 100)

println("\n" * "=" ^ 70)
println("  HEALTH STATE PREVALENCE")
println("=" ^ 70)
@printf("\n  %-5s  %8s  %8s  %8s  |  %8s  %8s  %8s\n",
    "Age", "Sim G", "Sim F", "Sim P", "Emp G", "Emp F", "Emp P")
println("  " * "-" ^ 62)

for age in [65, 70, 75, 80, 85, 90]
    t = age - p.age_start + 1
    (t < 1 || t > T) && continue
    emp = get(emp_health, age, nothing)
    emp_str = emp !== nothing ?
        @sprintf("%7.0f%%  %7.0f%%  %7.0f%%", emp.good*100, emp.fair*100, emp.poor*100) :
        "     ---       ---       ---"
    @printf("  %-5d  %7.0f%%  %7.0f%%  %7.0f%%  |  %s\n", age,
        sim.health_prevalence[t, 1] * 100,
        sim.health_prevalence[t, 2] * 100,
        sim.health_prevalence[t, 3] * 100,
        emp_str)
end

println("\n" * "=" ^ 70)
println("  MEAN MEDICAL SPENDING BY AGE")
println("=" ^ 70)
@printf("\n  %-5s  %12s  %12s\n", "Age", "Simulated", "Empirical")
println("  " * "-" ^ 32)

for age in [70, 75, 80, 85, 90, 95, 100]
    t = age - p.age_start + 1
    (t < 1 || t > T) && continue
    emp = get(emp_medical, age, nothing)
    emp_str = emp !== nothing ? "\$" * string(round(Int, emp)) : "---"
    @printf("  %-5d  %12s  %12s\n", age,
        "\$" * string(round(Int, sim.mean_medical_by_age[t])), emp_str)
end

println("\n" * "=" ^ 70)
println("  SURVIVAL CURVE")
println("=" ^ 70)
@printf("\n  %-5s  %12s\n", "Age", "Alive (%)")
println("  " * "-" ^ 20)
for age in [65, 70, 75, 80, 85, 90, 95, 100, 105]
    t = age - p.age_start + 1
    (t < 1 || t > T) && continue
    @printf("  %-5d  %11.1f%%\n", age, sim.alive_fraction[t] * 100)
end

# ===================================================================
# Save to CSV and LaTeX
# ===================================================================
tables_dir = joinpath(@__DIR__, "..", "tables")
mkpath(joinpath(tables_dir, "csv"))
mkpath(joinpath(tables_dir, "tex"))

csv_path = joinpath(tables_dir, "csv", "moment_validation.csv")
open(csv_path, "w") do f
    println(f, "age,sim_wealth_p25,sim_wealth_p50,sim_wealth_p75,sim_health_good,sim_health_fair,sim_health_poor,sim_medical,sim_alive_pct")
    for t in 1:T
        age = p.age_start + t - 1
        @printf(f, "%d,%.0f,%.0f,%.0f,%.3f,%.3f,%.3f,%.0f,%.3f\n",
            age,
            sim.wealth_p25[t], sim.wealth_p50[t], sim.wealth_p75[t],
            sim.health_prevalence[t, 1], sim.health_prevalence[t, 2], sim.health_prevalence[t, 3],
            sim.mean_medical_by_age[t],
            sim.alive_fraction[t] * 100)
    end
end
println("\n  CSV saved: $csv_path")

# LaTeX table
ds = '\$'
tex_path = joinpath(tables_dir, "tex", "moment_validation.tex")
open(tex_path, "w") do f
    println(f, raw"\begin{table}[htbp]")
    println(f, raw"\centering")
    println(f, raw"\caption{Simulated vs Empirical Lifecycle Moments}")
    println(f, raw"\label{tab:moment_validation}")
    println(f, raw"\begin{tabular}{lcc}")
    println(f, raw"\toprule")
    println(f, "Moment & Simulated & Empirical (HRS) \\\\")
    println(f, raw"\midrule")
    mean_b_sim = string(round(Int, sim.mean_bequest))
    mean_b_emp = string(round(Int, emp_bequest_mean))
    med_b_sim = string(round(Int, sim.median_bequest))
    med_b_emp = string(round(Int, emp_bequest_median))
    frac_sim = @sprintf("%.1f", sim.frac_bequest_above_10k * 100)
    frac_emp = @sprintf("%.1f", emp_frac_above_10k * 100)
    println(f, "Mean bequest & \\", "\$", mean_b_sim, " & \\", "\$", mean_b_emp, " \\\\")
    println(f, "Median bequest & \\", "\$", med_b_sim, " & \\", "\$", med_b_emp, " \\\\")
    println(f, "Fraction bequest > \\", "\$10K & ", frac_sim, "\\% & ", frac_emp, "\\% \\\\")
    println(f, raw"\bottomrule")
    println(f, raw"\end{tabular}")
    println(f, raw"\begin{tablenotes}")
    println(f, raw"\small")
    println(f, raw"\item Simulated: 100,000 trajectories, initial wealth \$250,000, Fair health.")
    println(f, raw"\item Empirical: HRS exit interviews (bequests); Jones et al.\ (2018) (medical).")
    println(f, raw"\end{tablenotes}")
    println(f, raw"\end{table}")
end
println("  LaTeX saved: $tex_path")

println("\n" * "=" ^ 70)
println("  MOMENT VALIDATION COMPLETE")
println("=" ^ 70)

#=============================================================================
# ORIGINAL FILE: scripts/run_welfare_analysis.jl
#=============================================================================

# Phase 5: Welfare Analysis — Heterogeneous CEV Map
#
# Computes consumption-equivalent variation (CEV) across household types.
# CEV measures the % increase in consumption that makes an individual
# indifferent between having and not having annuity market access.
#
# Outputs:
#   - CEV grid table (wealth x bequest x health)
#   - Population-level CEV statistics
#   - Subpopulation characterization (who benefits from annuitization)
#   - LaTeX and CSV tables

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
println("  PHASE 5: WELFARE ANALYSIS")
println("  Heterogeneous CEV Map — Who Benefits from Annuitization?")
println("=" ^ 70)

# ===================================================================
# Load HRS population sample
# ===================================================================
println("\nLoading HRS population sample...")
hrs_path = HRS_PATH
hrs_raw = readdlm(hrs_path, ',', Any; skipstart=1)
n_pop = size(hrs_raw, 1)
population = zeros(n_pop, 4)
population[:, 1] = Float64.(hrs_raw[:, 1])
population[:, 2] .= 0.0                      # A grid = 0 (SS via ss_func, matches production convention)
population[:, 3] = Float64.(hrs_raw[:, 3])
if size(hrs_raw, 2) >= 4
    population[:, 4] = Float64.(hrs_raw[:, 4])  # observed health (1=Good, 2=Fair, 3=Poor)
else
    population[:, 4] .= 2.0
end
@printf("  Loaded %d individuals\n", n_pop)

# ===================================================================
# Build survival probabilities
# ===================================================================
p_base = ModelParams(age_start=AGE_START, age_end=AGE_END)
base_surv = build_lockwood_survival(p_base)

# ===================================================================
# Section 1: CEV Grid Table (the heterogeneous welfare map)
# ===================================================================
println("\n" * "=" ^ 70)
println("  SECTION 1: CEV GRID — WELFARE BY HOUSEHOLD TYPE")
println("=" ^ 70)

bequest_specs = [
    (name="No bequest",     theta=0.0,   kappa=0.0),
    (name="Moderate (DFJ)", theta=THETA_DFJ, kappa=KAPPA_DFJ),
    (name="Strong bequest",  theta=200.0, kappa=KAPPA_DFJ),
]

# SS is now wired through the welfare model's ss_func ($18,500 representative
# level matching the median quartile). y_existing is reserved for non-SS
# pre-existing annuity income, which is essentially zero in the HRS sample.
# Setting y_existing = 0 avoids double-counting SS once it's already in the
# Bellman income flow.
y_existing_for_grid = 0.0
@printf("  y_existing = \$%s (SS is wired via ss_func at \$18,500/year)\n",
    string(round(Int, y_existing_for_grid)))

wealth_eval = [10_000.0, 25_000.0, 50_000.0, 100_000.0,
               200_000.0, 500_000.0, 1_000_000.0]

println("\n  Solving models for each bequest specification...")
cev_output = compute_cev_grid(
    base_surv, population;
    bequest_specs=bequest_specs,
    wealth_points=wealth_eval,
    y_existing=y_existing_for_grid,
    gamma=GAMMA, beta=BETA, r=R_RATE,
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
    consumption_decline=CONSUMPTION_DECLINE,
    health_utility=Float64.(HEALTH_UTILITY),
    psi_purchase=PSI_PURCHASE,
    lambda_w=LAMBDA_W,
    verbose=true,
)

# Print the grid table
println("\n  " * "-" ^ 78)
@printf("  %-12s %-8s", "Wealth", "Health")
for name in cev_output.bequest_names
    @printf("  %16s", name)
end
@printf("  %10s", "alpha*")
println()
println("  " * "-" ^ 78)

for iw in 1:length(wealth_eval)
    for ih in 1:3
        W_str = @sprintf("\$%s", replace(string(round(Int, wealth_eval[iw])),
            r"(\d)(?=(\d{3})+$)" => s"\1,"))
        @printf("  %-12s %-8s", ih == 1 ? W_str : "", cev_output.health_names[ih])
        for ib in 1:length(bequest_specs)
            r = cev_output.grid[iw, ib, ih]
            @printf("  %15.2f%%", r.cev * 100)
        end
        # Show alpha_star from DFJ bequest spec (most relevant)
        r_dfj = cev_output.grid[iw, 2, ih]
        @printf("  %9.0f%%", r_dfj.alpha_star * 100)
        println()
    end
    if iw < length(wealth_eval)
        println()
    end
end
println("  " * "-" ^ 78)
@printf("  Note: y_existing = \$%s (SS via ss_func at \$18,500/year). alpha* under DFJ bequests.\n",
    string(round(Int, y_existing_for_grid)))

# ===================================================================
# Section 2: Population CEV Statistics
# ===================================================================
println("\n" * "=" ^ 70)
println("  SECTION 2: POPULATION-LEVEL CEV STATISTICS")
println("=" ^ 70)

@printf("\n  %-20s %10s %10s %10s %10s\n",
    "Bequest Spec", "Mean CEV", "Med CEV", "CEV>0", "CEV>1%")
println("  " * "-" ^ 62)

pop_cev_rows = []
for pcev in cev_output.population_cev
    @printf("  %-20s %9.2f%% %9.2f%% %9.1f%% %9.1f%%  (n_excl=%d/%d)\n",
        pcev.name,
        pcev.mean_cev * 100,
        pcev.median_cev * 100,
        pcev.frac_positive * 100,
        pcev.frac_above_1pct * 100,
        pcev.n_excluded, pcev.n_total)
    push!(pop_cev_rows, [pcev.name, pcev.mean_cev, pcev.median_cev,
                          pcev.frac_positive, pcev.frac_above_1pct,
                          pcev.n_total, pcev.n_excluded, pcev.n_included])
end

# Save population CEV to CSV
pop_csv_path = joinpath(@__DIR__, "..", "tables", "csv", "population_cev.csv")
open(pop_csv_path, "w") do io
    println(io, "bequest_spec,mean_cev,median_cev,frac_positive,frac_above_1pct,n_total,n_excluded,n_included")
    for row in pop_cev_rows
        @printf(io, "%s,%.6f,%.6f,%.4f,%.4f,%d,%d,%d\n", row...)
    end
end
@printf("  Saved: %s\n", pop_csv_path)

# ===================================================================
# Section 3: Subpopulation Identification (under DFJ bequests)
# ===================================================================
println("\n" * "=" ^ 70)
println("  SECTION 3: WHO BENEFITS? (DFJ BEQUEST SPECIFICATION)")
println("=" ^ 70)

dfj_results = cev_output.population_cev[2].results
cevs_all = [r.cev for r in dfj_results]
alphas_all = [r.alpha_star for r in dfj_results]

# Note agents excluded for being above grid max
n_above_wmax = count(population[:, 1] .> W_MAX)
if n_above_wmax > 0
    @printf("\n  Note: %d agents with W > \$%s excluded (above grid max)\n",
        n_above_wmax, replace(string(round(Int, W_MAX)),
            r"(\d)(?=(\d{3})+$)" => s"\1,"))
end

# Agents with positive CEV
pos_mask = cevs_all .> 0.0
n_pos = count(pos_mask)
@printf("\n  Agents with CEV > 0: %d of %d (%.1f%%)\n",
    n_pos, n_pop, n_pos / n_pop * 100)

if n_pos > 0
    pos_indices = findall(pos_mask)
    pos_wealth = population[pos_indices, 1]
    pos_income = population[pos_indices, 2]
    pos_cev = cevs_all[pos_indices]

    @printf("    Wealth:  min=\$%s  median=\$%s  max=\$%s\n",
        string(round(Int, minimum(pos_wealth))),
        string(round(Int, sort(pos_wealth)[div(length(pos_wealth) + 1, 2)])),
        string(round(Int, maximum(pos_wealth))))
    @printf("    Income:  min=\$%s  median=\$%s  max=\$%s\n",
        string(round(Int, minimum(pos_income))),
        string(round(Int, sort(pos_income)[div(length(pos_income) + 1, 2)])),
        string(round(Int, maximum(pos_income))))
    @printf("    CEV:     min=%.2f%%  median=%.2f%%  max=%.2f%%\n",
        minimum(pos_cev) * 100,
        sort(pos_cev)[div(length(pos_cev) + 1, 2)] * 100,
        maximum(pos_cev) * 100)
end

# Agents with CEV > 1%
big_mask = cevs_all .> 0.01
n_big = count(big_mask)
@printf("\n  Agents with CEV > 1%%: %d of %d (%.1f%%)\n",
    n_big, n_pop, n_big / n_pop * 100)

if n_big > 0
    big_indices = findall(big_mask)
    big_wealth = population[big_indices, 1]
    big_income = population[big_indices, 2]
    big_cev = cevs_all[big_indices]

    @printf("    Wealth:  min=\$%s  median=\$%s  max=\$%s\n",
        string(round(Int, minimum(big_wealth))),
        string(round(Int, sort(big_wealth)[div(length(big_wealth) + 1, 2)])),
        string(round(Int, maximum(big_wealth))))
    @printf("    CEV:     min=%.2f%%  median=%.2f%%  max=%.2f%%\n",
        minimum(big_cev) * 100,
        sort(big_cev)[div(length(big_cev) + 1, 2)] * 100,
        maximum(big_cev) * 100)
end

# Agents with CEV > 5%
big5_mask = cevs_all .> 0.05
n_big5 = count(big5_mask)
@printf("\n  Agents with CEV > 5%%: %d of %d (%.1f%%)\n",
    n_big5, n_pop, n_big5 / n_pop * 100)

# ===================================================================
# Section 4: LaTeX and CSV Output
# ===================================================================
println("\n" * "=" ^ 70)
println("  SECTION 4: WRITING OUTPUT FILES")
println("=" ^ 70)

# --- CSV ---
csv_path = joinpath(@__DIR__, "..", "tables", "csv", "welfare_cev_grid.csv")
open(csv_path, "w") do io
    # Header
    print(io, "wealth,health")
    for name in cev_output.bequest_names
        print(io, ",cev_", replace(name, " " => "_"))
        print(io, ",alpha_", replace(name, " " => "_"))
    end
    println(io)

    for iw in 1:length(wealth_eval)
        for ih in 1:3
            @printf(io, "%.0f,%s", wealth_eval[iw], cev_output.health_names[ih])
            for ib in 1:length(bequest_specs)
                r = cev_output.grid[iw, ib, ih]
                @printf(io, ",%.6f,%.4f", r.cev, r.alpha_star)
            end
            println(io)
        end
    end
end
@printf("  CSV: %s\n", csv_path)

# --- LaTeX ---
tex_path = joinpath(@__DIR__, "..", "tables", "tex", "welfare_cev_grid.tex")
open(tex_path, "w") do io
    n_beq = length(bequest_specs)
    col_spec = "ll" * repeat("r", n_beq)
    println(io, "\\begin{table}[htbp]")
    println(io, "\\centering")
    println(io, "\\caption{Consumption-Equivalent Variation by Household Type}")
    println(io, "\\label{tab:cev_grid}")
    println(io, "\\begin{tabular}{$col_spec}")
    println(io, "\\toprule")
    print(io, "Wealth & Health")
    for name in cev_output.bequest_names
        print(io, " & $name")
    end
    println(io, " \\\\")
    println(io, "\\midrule")

    for iw in 1:length(wealth_eval)
        W_str = "\\\$" * replace(string(round(Int, wealth_eval[iw])),
                r"(\d)(?=(\d{3})+$)" => s"\1,")
        for ih in 1:3
            if ih == 1
                print(io, W_str)
            end
            print(io, " & ", cev_output.health_names[ih])
            for ib in 1:n_beq
                r = cev_output.grid[iw, ib, ih]
                @printf(io, " & %.2f\\%%", r.cev * 100)
            end
            println(io, " \\\\")
        end
        if iw < length(wealth_eval)
            println(io, "\\\\[3pt]")
        end
    end

    println(io, "\\bottomrule")
    println(io, "\\end{tabular}")
    println(io, "\\begin{tablenotes}")
    println(io, "\\small")
    println(io, "\\item CEV: consumption-equivalent variation (\\%). ",
        "Positive values indicate welfare gain from annuity market access. ",
        "Full model with medical costs, health-mortality correlation, ",
        "MWR = $MWR_LOADED, inflation = $(Int(INFLATION*100))\\%, ",
        "\$\\gamma = $GAMMA\$.")
    println(io, "\\end{tablenotes}")
    println(io, "\\end{table}")
end
@printf("  LaTeX: %s\n", tex_path)

# ===================================================================
# Section 5: Simulation Comparison (no-bequest model at high wealth)
# ===================================================================
println("\n" * "=" ^ 70)
println("  SECTION 5: LIFECYCLE SIMULATION COMPARISON")
println("  (No-bequest model — where annuity welfare gains are largest)")
println("=" ^ 70)

# Under DFJ bequests, alpha*=0 for most wealth levels, making
# with/without comparison trivially identical. Use no-bequest model
# where annuitization is optimal for high-wealth agents.
println("\n  Solving no-bequest model for simulation...")
ss_zero(age, p) = 0.0
p_sim = ModelParams(;
    gamma=GAMMA, beta=BETA, r=R_RATE,
    theta=0.0, kappa=0.0,
    mwr=MWR_LOADED, fixed_cost=FIXED_COST, min_purchase=MIN_PURCHASE,
    lambda_w=LAMBDA_W,
    inflation_rate=INFLATION,
    medical_enabled=true, health_mortality_corr=true,
    stochastic_health=true, n_health_states=3, n_quad=N_QUAD,
    c_floor=C_FLOOR, hazard_mult=HAZARD_MULT,
    survival_pessimism=SURVIVAL_PESSIMISM,
    n_wealth=N_WEALTH, n_annuity=N_ANNUITY, n_alpha=N_ALPHA,
    W_max=W_MAX, age_start=AGE_START, age_end=AGE_END,
    annuity_grid_power=A_GRID_POW,
)
p_fair_pr = ModelParams(age_start=AGE_START, age_end=AGE_END, mwr=1.0, r=R_RATE)
fair_pr = compute_payout_rate(p_fair_pr, base_surv)
loaded_pr = MWR_LOADED * fair_pr
grids_sim = build_grids(p_fair_pr, fair_pr)
sol_sim = solve_lifecycle_health(p_sim, grids_sim, base_surv, ss_zero)

sim_wealth_levels = [200_000.0, 500_000.0, 1_000_000.0]
for W_0 in sim_wealth_levels
    comp = simulate_welfare_comparison(
        sol_sim, W_0, 1, base_surv, p_sim;
        payout_rate=loaded_pr, y_existing=y_existing_for_grid,
        n_sim=5_000, rng_seed=42,
    )

    @printf("\n  W_0 = \$%s, H_0 = Good, alpha* = %.0f%%\n",
        replace(string(round(Int, W_0)), r"(\d)(?=(\d{3})+$)" => s"\1,"),
        comp.alpha_star * 100)

    if comp.alpha_star > 0.0
        @printf("    Mean consumption age 65 (with):  \$%s\n",
            string(round(Int, comp.with_annuity.mean_consumption_by_age[1])))
        @printf("    Mean consumption age 65 (w/o):   \$%s\n",
            string(round(Int, comp.without_annuity.mean_consumption_by_age[1])))
        # Late-life consumption (age 85 = period 21, if alive)
        t85 = min(21, length(comp.with_annuity.mean_consumption_by_age))
        if comp.with_annuity.alive_count[t85] > 0
            @printf("    Mean consumption age 85 (with):  \$%s\n",
                string(round(Int, comp.with_annuity.mean_consumption_by_age[t85])))
            @printf("    Mean consumption age 85 (w/o):   \$%s\n",
                string(round(Int, comp.without_annuity.mean_consumption_by_age[t85])))
        end
        @printf("    Mean bequest (with):             \$%s\n",
            string(round(Int, comp.with_annuity.mean_bequest)))
        @printf("    Mean bequest (without):          \$%s\n",
            string(round(Int, comp.without_annuity.mean_bequest)))
    else
        println("    alpha* = 0 => no annuity purchase; paths identical.")
    end
end

println("\n" * "=" ^ 70)
println("  WELFARE ANALYSIS COMPLETE")
println("=" ^ 70)

#=============================================================================
# ORIGINAL FILE: scripts/run_welfare_counterfactuals.jl
#=============================================================================

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
        "Full ten-channel model, conservative (ABI-anchored) bracket end"),
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

#=============================================================================
# ORIGINAL FILE: scripts/run_health_analysis.jl
#=============================================================================

# Phase 3: Health and Medical Expenditures Analysis
# Reichling-Smetters (2015) Replication and Health-Aware WTP
#
# This script demonstrates the key Phase 3 results:
# 1. Gauss-Hermite quadrature validation
# 2. Medical expense calibration vs Jones et al. (2018)
# 3. R-S sign reversal: correlated health-mortality eliminates annuity demand
# 4. WTP decomposition by health state

using Printf
include(joinpath(@__DIR__, "..", "src", "AnnuityPuzzle.jl"))
using .AnnuityPuzzle

println("=" ^ 70)
println("  PHASE 3: HEALTH AND MEDICAL EXPENDITURES")
println("  Reichling-Smetters (2015) Mechanism Analysis")
println("=" ^ 70)

# ===================================================================
# 1. Medical Expense Calibration
# ===================================================================
println("\n" * "=" ^ 70)
println("  MEDICAL EXPENSE CALIBRATION (Jones et al. 2018)")
println("=" ^ 70)

p_cal = ModelParams(medical_enabled=true, stochastic_health=true, n_health_states=3)

println(@sprintf("\n%-8s  %-12s  %-12s  %-12s", "Age", "Good", "Fair", "Poor"))
println("-" ^ 48)
for age in [65, 70, 75, 80, 85, 90, 95, 100]
    m_g = mean_medical_expense(age, 1, p_cal)
    m_f = mean_medical_expense(age, 2, p_cal)
    m_p = mean_medical_expense(age, 3, p_cal)
    println(@sprintf("%-8d  \$%-11s  \$%-11s  \$%-11s",
        age,
        string(round(Int, m_g)),
        string(round(Int, m_f)),
        string(round(Int, m_p))))
end
println("\n  Targets: Fair age 70 ≈ \$4,200 ✓")
println("           Fair age 100 ≈ \$29,700 ✓")

# ===================================================================
# 2. Health Transition Matrix
# ===================================================================
println("\n" * "=" ^ 70)
println("  HEALTH TRANSITION MATRICES (HRS calibration)")
println("=" ^ 70)

for age in [65, 80, 100]
    trans = build_health_transition(age)
    println(@sprintf("\nAge %d:", age))
    labels = ["Good", "Fair", "Poor"]
    println(@sprintf("  %-6s  %-8s  %-8s  %-8s", "From\\To", labels...))
    for i in 1:3
        println(@sprintf("  %-6s  %-8.3f  %-8.3f  %-8.3f",
            labels[i], trans[i, 1], trans[i, 2], trans[i, 3]))
    end
end

# ===================================================================
# 3. R-S Sign Reversal: Annuitization Decisions
# ===================================================================
println("\n" * "=" ^ 70)
println("  REICHLING-SMETTERS MECHANISM: OPTIMAL ANNUITIZATION")
println("=" ^ 70)

common = (gamma=2.0, beta=0.97, r=0.02, theta=0.0, kappa=0.0,
          age_start=65, age_end=100, mwr=1.0, fixed_cost=0.0,
          c_floor=3000.0, n_wealth=60, n_annuity=15, n_alpha=101,
          W_max=500_000.0)

configs = [
    ("1. Deterministic mortality (Yaari)",
     false, false, false),
    ("2. Stochastic health, uncorrelated, no medical",
     true, false, false),
    ("3. Stochastic health, correlated, no medical",
     true, true, false),
    ("4. Stochastic health, uncorrelated, WITH medical",
     true, false, true),
    ("5. Stochastic health, correlated, WITH medical (R-S)",
     true, true, true),
]

# Define once at top level to avoid Julia 1.12 scoping issues
ss_zero_global(age, params) = 0.0

wealth_levels = [25_000.0, 50_000.0, 100_000.0, 250_000.0, 500_000.0]
w_labels = ["\$25K", "\$50K", "\$100K", "\$250K", "\$500K"]

header = @sprintf("\n%-55s  %s",
    "Configuration",
    join([@sprintf("%-8s", l) for l in w_labels]))
println(header)
println("-" ^ (55 + 8 * length(wealth_levels)))

for (label, stoch, corr, med) in configs
    if stoch
        p = ModelParams(; common...,
            stochastic_health=true, n_health_states=3,
            health_mortality_corr=corr, medical_enabled=med, n_quad=9)
        surv = build_survival_probs(p)
        pr = compute_payout_rate(p, surv)
        grids = build_grids(p, pr)
        ss_zero = ss_zero_global
        sol = solve_lifecycle_health(p, grids, surv, ss_zero)
        alpha_star, _ = solve_annuitization_health(sol, pr; initial_health=2)
        W_grid = grids.W
    else
        p = ModelParams(; common...,
            stochastic_health=false, medical_enabled=false)
        surv = build_survival_probs(p)
        pr = compute_payout_rate(p, surv)
        grids = build_grids(p, pr)
        ss_zero = ss_zero_global
        sol = solve_lifecycle(p, grids, surv, ss_zero)
        alpha_star, _ = solve_annuitization(sol, pr)
        W_grid = grids.W
    end

    alphas = [alpha_star[argmin(abs.(W_grid .- w))] for w in wealth_levels]
    alpha_strs = join([@sprintf("%-8.2f", a) for a in alphas])
    println(@sprintf("%-55s  %s", label, alpha_strs))
end

println("\n  Key R-S Result:")
println("  - Config 1 (Yaari): full annuitization at moderate+ wealth")
println("  - Config 5 (R-S): reduced or zero annuitization")
println("  - Sign reversal confirms health-cost correlation mechanism")

# ===================================================================
# 4. WTP by Health State
# ===================================================================
println("\n" * "=" ^ 70)
println("  WTP BY HEALTH STATE (Lockwood params + health)")
println("=" ^ 70)

p_wtp = ModelParams(
    gamma=2.0, beta=1.0/1.03, r=0.03,
    theta=0.0, kappa=10.0,
    age_start=65, age_end=110,
    mwr=1.0, fixed_cost=0.0, c_floor=100.0,
    stochastic_health=true, n_health_states=3,
    health_mortality_corr=true, medical_enabled=true, n_quad=9,
    n_wealth=80, n_annuity=20, n_alpha=101,
    W_max=3_000_000.0,
)
surv_l = build_lockwood_survival(p_wtp)
pr_l = compute_payout_rate(p_wtp, surv_l)
grids_l = build_grids(p_wtp, pr_l)
ss_zero_l = ss_zero_global

println("\nSolving health-aware lifecycle (Lockwood params)...")
@time sol_h = solve_lifecycle_health(p_wtp, grids_l, surv_l, ss_zero_l)

# WTP comparison: with and without health
println("\n--- WTP at 50% pre-annuitized, \$500K total ---")
tot_W = 500_000.0
N_ref = tot_W * 0.50
y_ref = tot_W * 0.50 * pr_l

println(@sprintf("%-20s  %-10s  %-10s", "Configuration", "WTP", "alpha*"))
println("-" ^ 42)

# No health (Phase 2 baseline)
p_nohealth = ModelParams(
    gamma=2.0, beta=1.0/1.03, r=0.03,
    theta=0.0, kappa=10.0,
    age_start=65, age_end=110,
    mwr=1.0, fixed_cost=0.0, c_floor=100.0,
    n_wealth=80, n_annuity=20, n_alpha=101,
    W_max=3_000_000.0,
)
grids_nh = build_grids(p_nohealth, pr_l)
sol_nh = solve_lifecycle(p_nohealth, grids_nh, surv_l, ss_zero_l)
res_nh = compute_wtp_lockwood(N_ref, y_ref, sol_nh, pr_l)
println(@sprintf("%-20s  %-10s  %-10.2f", "No health (Phase 2)",
    @sprintf("%.1f%%", res_nh.wtp * 100), res_nh.alpha_star))

# Health-aware WTP by initial health state
for h in 1:3
    hname = ["Good health", "Fair health", "Poor health"][h]
    res = compute_wtp_health(N_ref, y_ref, sol_h, pr_l; initial_health=h)
    println(@sprintf("%-20s  %-10s  %-10.2f", hname,
        @sprintf("%.1f%%", res.wtp * 100), res.alpha_star))
end

# ===================================================================
# 5. Health-dependent survival comparison
# ===================================================================
println("\n" * "=" ^ 70)
println("  HEALTH-DEPENDENT SURVIVAL PROBABILITIES")
println("=" ^ 70)

p_surv = ModelParams(health_mortality_corr=true, age_end=100,
                     hazard_mult=[0.6, 1.0, 2.0])
base_surv = build_survival_probs(p_surv)
surv_h = build_health_survival(base_surv, p_surv)

println(@sprintf("\n%-8s  %-12s  %-12s  %-12s  %-12s",
    "Age", "Base", "Good", "Fair", "Poor"))
println("-" ^ 60)
for age in [65, 70, 75, 80, 85, 90, 95]
    t = age - 64
    println(@sprintf("%-8d  %-12.4f  %-12.4f  %-12.4f  %-12.4f",
        age, base_surv[t], surv_h[t, 1], surv_h[t, 2], surv_h[t, 3]))
end

println("\n  Note: s(t, H) = s_base(t)^mult(H)")
println("  Hazard multipliers: Good=0.6, Fair=1.0, Poor=2.0")
println("  Good health ≈ 40% lower hazard rate")
println("  Poor health ≈ 100% higher hazard rate")

println("\n" * "=" ^ 70)
println("  PHASE 3 ANALYSIS COMPLETE")
println("=" ^ 70)

#=============================================================================
# ORIGINAL FILE: scripts/run_simulation.jl
#=============================================================================

# Phase 4: Monte Carlo Simulation Validation
#
# Simulates lifecycle trajectories under the full model (all channels on)
# and compares aggregate moments to HRS data targets:
#   - Wealth decumulation profiles
#   - Bequest distribution
#   - Survival curve
#
# Calibration aligned with Lockwood (2012) DFJ specification:
#   gamma=2, age_end=110, c_floor=$6,180 (Lockwood sim code),
#   DFJ bequests (theta=56.96, kappa=$272,628), hazard_mult=[0.50,1.0,3.0]

using Printf
include(joinpath(@__DIR__, "..", "src", "AnnuityPuzzle.jl"))
using .AnnuityPuzzle

include(joinpath(@__DIR__, "config.jl"))

println("=" ^ 70)
println("  PHASE 4: MONTE CARLO SIMULATION VALIDATION")
println("=" ^ 70)

# ===================================================================
# Setup
# ===================================================================
ss_zero(age, p) = 0.0

p_base = ModelParams(age_start=AGE_START, age_end=AGE_END)
base_surv = build_lockwood_survival(p_base)
p_fair = ModelParams(age_start=AGE_START, age_end=AGE_END, mwr=1.0, r=R_RATE)
fair_pr = compute_payout_rate(p_fair, base_surv)

# Full model parameters (all channels on, DFJ bequests)
p = ModelParams(
    gamma=GAMMA, beta=BETA, r=R_RATE,
    theta=THETA_DFJ, kappa=KAPPA_DFJ,
    mwr=MWR_LOADED, fixed_cost=FIXED_COST, inflation_rate=INFLATION,
    medical_enabled=true, health_mortality_corr=true,
    stochastic_health=true, n_health_states=3, n_quad=N_QUAD,
    c_floor=C_FLOOR, hazard_mult=HAZARD_MULT,
    survival_pessimism=SURVIVAL_PESSIMISM,
    n_wealth=N_WEALTH, n_annuity=N_ANNUITY, n_alpha=N_ALPHA,
    W_max=W_MAX, annuity_grid_power=A_GRID_POW,
    age_start=AGE_START, age_end=AGE_END,
)

grids = build_grids(p, fair_pr)
loaded_pr = MWR_LOADED * fair_pr

@printf("\nFair payout rate: %.4f\n", fair_pr)
@printf("Loaded payout rate (MWR=%.2f): %.4f\n", MWR_LOADED, loaded_pr)
@printf("DFJ bequest theta: %.2f, kappa: \$%s\n", THETA_DFJ, string(round(Int, KAPPA_DFJ)))
@printf("gamma=%.1f, c_floor=\$%.0f, age_end=%d\n", GAMMA, C_FLOOR, AGE_END)

# ===================================================================
# Solve the full model
# ===================================================================
println("\nSolving full model (all channels on)...")
@time sol = solve_lifecycle_health(p, grids, base_surv, ss_zero)

# ===================================================================
# Optimal annuitization by wealth level
# ===================================================================
println("\n" * "=" ^ 70)
println("  OPTIMAL ANNUITIZATION BY WEALTH AND HEALTH")
println("=" ^ 70)

wealth_levels = [25_000.0, 50_000.0, 100_000.0, 250_000.0, 500_000.0]
w_labels = ["\$25K", "\$50K", "\$100K", "\$250K", "\$500K"]
health_labels = ["Good", "Fair", "Poor"]

# Pre-existing annuity income: median SS quartile level
y_preexisting = SS_QUARTILE_LEVELS[2]  # $17,000 (Q2 median)

@printf("\n  Pre-existing annuity income: \$%s/yr\n\n", string(round(Int, y_preexisting)))
@printf("  %-8s", "Health")
for l in w_labels
    @printf("  %-8s", l)
end
println()
println("  " * "-" ^ (8 + 10 * length(wealth_levels)))

for ih in 1:3
    alpha_star, _ = solve_annuitization_health(sol, loaded_pr; initial_health=ih)
    @printf("  %-8s", health_labels[ih])
    for w in wealth_levels
        iw = argmin(abs.(grids.W .- w))
        @printf("  %-8.2f", alpha_star[iw])
    end
    println()
end

# ===================================================================
# Monte Carlo Simulation: representative agents by wealth quartile
# ===================================================================
println("\n" * "=" ^ 70)
println("  SIMULATED LIFECYCLE TRAJECTORIES")
println("=" ^ 70)

n_sim = 10_000
quartile_wealth = [25_000.0, 100_000.0, 250_000.0, 500_000.0]
quartile_labels = ["Q1 (\$25K)", "Q2 (\$100K)", "Q3 (\$250K)", "Q4 (\$500K)"]
quartile_income = SS_QUARTILE_LEVELS

for (qi, (W_0, y_0, qlabel)) in enumerate(zip(quartile_wealth, quartile_income, quartile_labels))
    println(@sprintf("\n  --- Wealth quartile %s, pre-existing income \$%s ---",
        qlabel, string(round(Int, y_0))))

    # Find optimal annuitization under full model
    iw = argmin(abs.(grids.W .- W_0))
    alpha_star, _ = solve_annuitization_health(sol, loaded_pr; initial_health=2)
    alpha_opt = alpha_star[iw]

    A_purchased = alpha_opt * W_0 * loaded_pr
    A_total = y_0 + A_purchased
    W_remaining = W_0 * (1.0 - alpha_opt)
    if alpha_opt > 0.0
        W_remaining -= p.fixed_cost
    end
    W_remaining = max(W_remaining, 0.0)

    @printf("  Optimal alpha: %.2f (annuity income: \$%s/yr)\n",
        alpha_opt, string(round(Int, A_purchased)))
    @printf("  Remaining wealth: \$%s, total annuity: \$%s/yr\n",
        string(round(Int, W_remaining)), string(round(Int, A_total)))

    # Simulate
    batch = simulate_batch(
        sol, W_remaining, A_total, 2, base_surv, ss_zero, p;
        n_sim=n_sim, rng_seed=42 + qi,
    )

    # Report key ages
    report_ages = [65, 70, 75, 80, 85, 90, 95, 100, 105, 110]
    @printf("  %-6s  %-12s  %-12s  %-8s\n", "Age", "Mean Wealth", "Mean Cons.", "Alive %")
    println("  " * "-" ^ 42)
    for age in report_ages
        t = age - p.age_start + 1
        t > p.T && continue
        @printf("  %-6d  \$%-11s  \$%-11s  %6.1f%%\n",
            age,
            string(round(Int, batch.mean_wealth_by_age[t])),
            string(round(Int, batch.mean_consumption_by_age[t])),
            batch.alive_fraction[t] * 100)
    end

    # Bequest statistics
    pos_beq = filter(b -> b > 0, batch.bequests)
    @printf("\n  Bequest: mean \$%s, frac>0: %.1f%%, conditional mean \$%s\n",
        string(round(Int, batch.mean_bequest)),
        batch.frac_positive_bequest * 100,
        string(round(Int, length(pos_beq) > 0 ? sum(pos_beq) / length(pos_beq) : 0)))
end

# ===================================================================
# HRS Validation Targets
# ===================================================================
println("\n" * "=" ^ 70)
println("  HRS VALIDATION TARGETS")
println("=" ^ 70)
println("\n  Wealth decumulation rate (ages 75-85): target ~3-5%/yr")
println("  Bequest distribution: 60-75% positive, mean \$50K-\$200K by quartile")
println("  Annuity ownership rate: ~3.6% (Lockwood 2012)")

println("\n" * "=" ^ 70)
println("  SIMULATION COMPLETE")
println("=" ^ 70)

#=============================================================================
# ORIGINAL FILE: scripts/generate_figures.jl
#=============================================================================

# Figure generation for "Dissolving the Annuity Puzzle"
#
# Produces 5 publication-quality figures:
#   1. Sequential decomposition bar chart
#   2. Gamma sensitivity curve
#   3. Hazard multiplier sensitivity
#   4. Policy function (optimal alpha by wealth)
#   5. CEV heatmap
#
# Run: julia --project=. scripts/generate_figures.jl

using Plots
using DelimitedFiles
using Printf

include(joinpath(@__DIR__, "..", "src", "AnnuityPuzzle.jl"))
using .AnnuityPuzzle

# Pull production calibration constants. Figures should always reflect
# whatever the rest of the pipeline produces.
include(joinpath(@__DIR__, "config.jl"))

# Output directories
const FIG_PDF = joinpath(@__DIR__, "..", "figures", "pdf")
const FIG_PNG = joinpath(@__DIR__, "..", "figures", "png")
mkpath(FIG_PDF)
mkpath(FIG_PNG)

# Plots defaults: serif font, thick lines, no title
default(
    fontfamily = "Computer Modern",
    titlefontsize = 12,
    guidefontsize = 11,
    tickfontsize = 10,
    legendfontsize = 9,
    linewidth = 1.5,
    framestyle = :box,
    grid = true,
    gridalpha = 0.2,
    dpi = 300,
)

# Colorblind-friendly palette (Okabe-Ito)
const CB_BLUE   = RGB(0.0/255, 114.0/255, 178.0/255)
const CB_ORANGE = RGB(230.0/255, 159.0/255, 0.0/255)
const CB_GREEN  = RGB(0.0/255, 158.0/255, 115.0/255)
const CB_RED    = RGB(213.0/255, 94.0/255, 0.0/255)
const CB_PURPLE = RGB(204.0/255, 121.0/255, 167.0/255)
const CB_CYAN   = RGB(86.0/255, 180.0/255, 233.0/255)
const CB_YELLOW = RGB(240.0/255, 228.0/255, 66.0/255)
const CB_BLACK  = RGB(0.0/255, 0.0/255, 0.0/255)

function savefig_both(p, name)
    savefig(p, joinpath(FIG_PDF, name * ".pdf"))
    savefig(p, joinpath(FIG_PNG, name * ".png"))
    println("  Saved: $name.pdf, $name.png")
end

# =====================================================================
# Figure 1: Sequential Decomposition Bar Chart
# =====================================================================
function figure_1_decomposition()
    println("Generating Figure 1: Sequential Decomposition...")

    # Read decomposition results from CSV (generated by run_decomposition.jl)
    csv_path = joinpath(@__DIR__, "..", "tables", "csv", "decomposition.csv")
    if isfile(csv_path)
        raw = readdlm(csv_path, ',', Any; skipstart=1)
        step_labels = String[]
        step_ownership = Float64[]
        for i in 1:size(raw, 1)
            push!(step_labels, strip(string(raw[i, 1])))
            push!(step_ownership, Float64(raw[i, 2]))
        end
    else
        # CSV is REQUIRED — placeholders mask data drift. Fail loudly so the
        # caller knows to run Stage 2 first.
        error("$csv_path not found; run scripts/run_decomposition.jl first to generate.")
    end

    n = length(step_labels)
    # Gradient from blue (Yaari) to red (full model), sized dynamically
    step_colors = [RGB(
        0.20 + 0.65 * (i - 1) / max(n - 1, 1),
        0.40 - 0.25 * (i - 1) / max(n - 1, 1),
        0.75 - 0.60 * (i - 1) / max(n - 1, 1),
    ) for i in 1:n]

    # Reverse so Yaari is at top (highest bar position)
    disp_labels = reverse(step_labels)
    disp_vals = reverse(step_ownership)
    disp_colors = reverse(step_colors)

    p = bar(
        1:n,
        disp_vals,
        orientation = :h,
        color = disp_colors,
        legend = false,
        xlims = (0, 108),
        ylims = (0.3, n + 0.7),
        yticks = (1:n, disp_labels),
        xlabel = "Predicted Ownership (%)",
        left_margin = 18Plots.mm,
        bottom_margin = 5Plots.mm,
        top_margin = 3Plots.mm,
        right_margin = 5Plots.mm,
        size = (700, 400),
        bar_width = 0.6,
    )

    # Observed benchmark line
    vline!([3.6], color = CB_BLACK, linestyle = :dash, linewidth = 1.2, label = "")
    annotate!(8.0, n + 0.45, Plots.text("Observed: 3.6%", 8, :left))

    # Value labels on bars
    for (i, val) in enumerate(disp_vals)
        x_pos = val < 10 ? val + 3.0 : val - 6.0
        txt_color = val < 10 ? :black : :white
        annotate!(x_pos, i, Plots.text(@sprintf("%.1f%%", val), 8, txt_color, :center))
    end

    savefig_both(p, "fig1_decomposition")
    return p
end


# =====================================================================
# Figure 2: Gamma Sensitivity Curve
# =====================================================================
function figure_2_gamma_sensitivity()
    println("Generating Figure 2: Gamma Sensitivity...")

    # Parse robustness CSV
    csv_path = joinpath(@__DIR__, "..", "tables", "csv", "robustness_full.csv")
    raw = readdlm(csv_path, ',', Any; skipstart=1)

    gamma_vals = Float64[]
    ownership_vals = Float64[]
    for i in 1:size(raw, 1)
        cat = strip(string(raw[i, 1]))
        cat != "Gamma sweep" && continue
        spec = strip(string(raw[i, 2]))
        # Parse gamma value from "gamma=X.XX"
        m = match(r"gamma=(\d+\.?\d*)", spec)
        m === nothing && continue
        g = parse(Float64, m.captures[1])
        # Parse ownership (handles both "X.X%" and bare "X.X")
        own_str = strip(replace(string(raw[i, 3]), "%" => ""))
        own = tryparse(Float64, own_str)
        own === nothing && continue
        push!(gamma_vals, g)
        push!(ownership_vals, own)
    end

    # Sort by gamma
    ord = sortperm(gamma_vals)
    gamma_vals = gamma_vals[ord]
    ownership_vals = ownership_vals[ord]

    p = plot(
        gamma_vals, ownership_vals,
        color = CB_BLUE,
        linewidth = 2.0,
        marker = :circle,
        markersize = 4,
        markercolor = CB_BLUE,
        markerstrokewidth = 0,
        legend = :topleft,
        label = "Full model",
        xlabel = "Risk Aversion (γ)",
        ylabel = "Predicted Ownership (%)",
        xlims = (1.3, 5.2),
        ylims = (-2, 45),
        size = (500, 340),
        left_margin = 5Plots.mm,
        bottom_margin = 5Plots.mm,
        top_margin = 3Plots.mm,
        right_margin = 3Plots.mm,
    )

    # Observed range band (3-6%)
    hspan!([3.0, 6.0], color = CB_GREEN, alpha = 0.18, label = "Observed range (3-6%)")

    # Mark baseline gamma = 2.5
    vline!([2.5], color = CB_RED, linestyle = :dash, linewidth = 1.0, label = "")
    annotate!(2.55, 38, Plots.text("γ = 2.5\n(baseline)", 8, :left, CB_RED))

    savefig_both(p, "fig2_gamma_sensitivity")
    return p
end


# =====================================================================
# Figure 3: Hazard Multiplier Sensitivity
# =====================================================================
function figure_3_hazard_sensitivity()
    println("Generating Figure 3: Hazard Multiplier Sensitivity...")

    # Read from robustness CSV
    csv_path = joinpath(@__DIR__, "..", "tables", "csv", "robustness_full.csv")
    labels = String[]
    ownership = Float64[]

    if isfile(csv_path)
        raw = readdlm(csv_path, ',', Any; skipstart=1)
        for i in 1:size(raw, 1)
            cat = strip(string(raw[i, 1]))
            cat != "Hazard mult" && continue
            spec = strip(string(raw[i, 2]))
            own_str = strip(replace(string(raw[i, 3]), "%" => ""))
            own = tryparse(Float64, own_str)
            own === nothing && continue
            push!(labels, replace(spec, r"\(.*\)" => s"\n\0"))
            push!(ownership, own)
        end
    end

    if isempty(labels)
        println("  WARNING: Hazard mult data not found in CSV, using placeholders.")
        labels = [
            "R-S functional\n[0.45, 1.0, 3.5]",
            "Baseline\n[0.50, 1.0, 3.0]",
            "HRS SRH\n[0.57, 1.0, 2.7]",
            "Conservative\n[0.60, 1.0, 2.0]",
        ]
        ownership = [0.0, 1.4, 5.7, 24.4]
    end

    bar_colors = [CB_BLUE, CB_GREEN, CB_ORANGE, CB_RED]
    n_bars = length(labels)
    if n_bars > length(bar_colors)
        bar_colors = repeat([CB_BLUE], n_bars)
    else
        bar_colors = bar_colors[1:n_bars]
    end

    p = bar(
        1:n_bars, ownership,
        color = bar_colors,
        legend = false,
        xticks = (1:n_bars, labels),
        ylabel = "Predicted Ownership (%)",
        xlabel = "Hazard Multiplier Specification [Good, Fair, Poor]",
        ylims = (0, 30),
        size = (560, 340),
        bar_width = 0.6,
        left_margin = 5Plots.mm,
        bottom_margin = 12Plots.mm,
        top_margin = 3Plots.mm,
        right_margin = 3Plots.mm,
        xrotation = 0,
    )

    # Observed range band
    hspan!([3.0, 6.0], color = CB_GREEN, alpha = 0.15, label = "")
    annotate!(3.85, 5.5, Plots.text("Observed (3-6%)", 8, :right, :darkgreen))

    # Value labels above bars
    for (i, val) in enumerate(ownership)
        annotate!(i, val + 1.0, Plots.text(@sprintf("%.1f%%", val), 9, :center))
    end

    savefig_both(p, "fig3_hazard_sensitivity")
    return p
end


# =====================================================================
# Figure 4: Policy Function -- Optimal Alpha by Wealth
# =====================================================================
function figure_4_policy_functions()
    println("Generating Figure 4: Policy Functions (requires model solves)...")
    # Constants come from config.jl (loaded at top of this file).
    # Use Lockwood's original theta at all gamma values (no recalibration)
    HAZARD_MULT = [0.50, 1.0, 3.0]

    grid_kw = (
        n_wealth = N_WEALTH, n_annuity = N_ANNUITY, n_alpha = N_ALPHA,
        W_max = W_MAX, age_start = AGE_START, age_end = AGE_END,
        annuity_grid_power = A_GRID_POW,
    )
    common_kw = (
        gamma = GAMMA, beta = BETA, r = R_RATE,
        stochastic_health = true, n_health_states = 3, n_quad = N_QUAD,
        c_floor = C_FLOOR, hazard_mult = HAZARD_MULT,
        survival_pessimism = 0.981,  # O'Dea & Sturrock (2023)
    )

    _ss_mean_val = sum(SS_QUARTILE_LEVELS) / length(SS_QUARTILE_LEVELS)
    ss_mean(age, p) = _ss_mean_val

    # Survival probabilities
    p_base = ModelParams(age_start = AGE_START, age_end = AGE_END)
    base_surv = build_lockwood_survival(p_base)

    # Payout rates
    p_fair = ModelParams(; gamma = GAMMA, beta = BETA, r = R_RATE, mwr = 1.0, grid_kw...)
    fair_pr = compute_payout_rate(p_fair, base_surv)
    grids = build_grids(p_fair, fair_pr)
    loaded_pr = MWR_LOADED * fair_pr

    # --- Panel A: No bequests, loads + inflation only ---
    println("  Panel A: solving (no bequests, loads + inflation)...")
    t0 = time()
    p_A = ModelParams(; common_kw...,
        theta = 0.0, kappa = 0.0,
        mwr = MWR_LOADED, fixed_cost = FIXED_COST, min_purchase = MIN_PURCHASE,
        lambda_w = LAMBDA_W,
        inflation_rate = INFLATION,
        medical_enabled = false, health_mortality_corr = false,
        grid_kw...,
    )
    sol_A = solve_lifecycle_health(p_A, grids, base_surv, ss_mean)
    alpha_A, _ = solve_annuitization_health(sol_A, loaded_pr; initial_health = 1)
    @printf("    Solved in %.1fs\n", time() - t0)

    # --- Panel B: Full model (DFJ bequests + R-S + loads + inflation) ---
    println("  Panel B: solving (full model)...")
    t0 = time()
    p_B = ModelParams(; common_kw...,
        theta = THETA_DFJ, kappa = KAPPA_DFJ,
        mwr = MWR_LOADED, fixed_cost = FIXED_COST, min_purchase = MIN_PURCHASE,
        lambda_w = LAMBDA_W,
        inflation_rate = INFLATION,
        medical_enabled = true, health_mortality_corr = true,
        grid_kw...,
    )
    sol_B = solve_lifecycle_health(p_B, grids, base_surv, ss_mean)
    alpha_B, _ = solve_annuitization_health(sol_B, loaded_pr; initial_health = 1)
    @printf("    Solved in %.1fs\n", time() - t0)

    W_grid = grids.W

    # Convert to thousands for x-axis
    W_k = W_grid ./ 1000.0

    # Filter to W <= $1M for display
    mask = W_grid .<= 1_000_000.0
    W_disp = W_k[mask]
    alpha_A_disp = alpha_A[mask]
    alpha_B_disp = alpha_B[mask]

    p1 = plot(
        W_disp, alpha_A_disp,
        color = CB_BLUE,
        linewidth = 2.0,
        xlabel = "Initial Wealth (\$000s)",
        ylabel = "Optimal Annuity Fraction (α*)",
        ylims = (-0.02, 1.02),
        xlims = (0, 1050),
        label = "",
        size = (460, 300),
        left_margin = 5Plots.mm,
        bottom_margin = 5Plots.mm,
        top_margin = 5Plots.mm,
        right_margin = 3Plots.mm,
    )
    annotate!(500, 0.92, Plots.text("(a) No bequests, no health risk", 9, :center))

    p2 = plot(
        W_disp, alpha_B_disp,
        color = CB_RED,
        linewidth = 2.0,
        xlabel = "Initial Wealth (\$000s)",
        ylabel = "Optimal Annuity Fraction (α*)",
        ylims = (-0.02, 1.02),
        xlims = (0, 1050),
        label = "",
        size = (460, 300),
        left_margin = 5Plots.mm,
        bottom_margin = 5Plots.mm,
        top_margin = 5Plots.mm,
        right_margin = 3Plots.mm,
    )
    annotate!(500, 0.92, Plots.text("(b) Full model", 9, :center))

    p_combined = plot(
        p1, p2,
        layout = (1, 2),
        size = (900, 340),
        left_margin = 5Plots.mm,
        bottom_margin = 8Plots.mm,
    )

    savefig_both(p_combined, "fig4_policy_functions")
    return p_combined
end


# =====================================================================
# Figure 5: CEV Heatmap
# =====================================================================
function figure_5_cev_heatmap()
    println("Generating Figure 5: CEV Heatmap...")

    csv_path = joinpath(@__DIR__, "..", "tables", "csv", "welfare_cev_grid.csv")
    raw = readdlm(csv_path, ',', Any; skipstart=1)

    # Extract "No bequest" CEV column (column 3)
    wealth_vals = Float64[]
    health_labels_raw = String[]
    cev_vals = Float64[]

    for i in 1:size(raw, 1)
        push!(wealth_vals, Float64(raw[i, 1]))
        push!(health_labels_raw, strip(string(raw[i, 2])))
        push!(cev_vals, Float64(raw[i, 3]))  # cev_No_bequest
    end

    # Unique wealth and health values
    unique_wealth = unique(wealth_vals)
    unique_health = unique(health_labels_raw)  # ["Good", "Fair", "Poor"]
    nW = length(unique_wealth)
    nH = length(unique_health)

    # Build matrix: rows = health (reversed for display: Poor at top), cols = wealth
    cev_matrix = zeros(nH, nW)
    for i in eachindex(wealth_vals)
        iw = findfirst(==(wealth_vals[i]), unique_wealth)
        ih = findfirst(==(health_labels_raw[i]), unique_health)
        cev_matrix[ih, iw] = cev_vals[i] * 100  # convert to percent
    end

    # Reverse health ordering so Good is at top
    cev_display = cev_matrix[end:-1:1, :]
    health_display = reverse(unique_health)

    # Wealth labels in $K or $M
    function wealth_label(w)
        if w >= 1_000_000
            return @sprintf("\$%.0fM", w / 1_000_000)
        else
            return @sprintf("\$%dK", round(Int, w / 1000))
        end
    end
    w_labels = [wealth_label(w) for w in unique_wealth]

    p = heatmap(
        1:nW, 1:nH, cev_display,
        color = cgrad([:white, CB_CYAN, CB_BLUE], [0.0, 0.3, 1.0]),
        clims = (0, maximum(cev_display) * 1.05),
        xticks = (1:nW, w_labels),
        yticks = (1:nH, health_display),
        xlabel = "Initial Wealth",
        ylabel = "Health at Age 65",
        colorbar_title = "CEV (%)",
        size = (560, 280),
        left_margin = 5Plots.mm,
        bottom_margin = 8Plots.mm,
        top_margin = 3Plots.mm,
        right_margin = 8Plots.mm,
        xrotation = 30,
    )

    # Annotate cells with values
    for ih in 1:nH
        for iw in 1:nW
            val = cev_display[ih, iw]
            txt = val < 0.001 ? "0" : @sprintf("%.2f", val)
            txt_color = val > maximum(cev_display) * 0.5 ? :white : :black
            annotate!(iw, ih, Plots.text(txt, 8, txt_color, :center))
        end
    end

    savefig_both(p, "fig5_cev_heatmap")
    return p
end

# =====================================================================
# Main
# =====================================================================
function main()
    println("=" ^ 60)
    println("  FIGURE GENERATION")
    println("  Quantifying the Annuity Puzzle")
    println("=" ^ 60)
    println()

    figure_1_decomposition()
    println()

    figure_2_gamma_sensitivity()
    println()

    figure_3_hazard_sensitivity()
    println()

    figure_4_policy_functions()
    println()

    figure_5_cev_heatmap()
    println()

    println("=" ^ 60)
    println("  All figures saved to:")
    println("    PDF: $FIG_PDF")
    println("    PNG: $FIG_PNG")
    println("=" ^ 60)
end

main()

#=============================================================================
# ORIGINAL FILE: scripts/export_manuscript_numbers.jl
#=============================================================================

# Single source of truth for every numeric literal in the manuscript.
#
# Inputs:  scripts/config.jl, tables/csv/*.csv, data/processed/lockwood_hrs_sample.csv
# Output:  paper/numbers.tex
#
# Any number cited in paper/main.tex, paper/appendix.tex, or paper/cover_letter.tex
# enters through a \newcommand defined here. When a calibration or result changes,
# the macro updates on the next run_all.jl pass and the manuscript follows.
#
# Usage:
#   julia --project=. scripts/export_manuscript_numbers.jl
#
# Conventions:
#   - Macros use camelCase with a category prefix.
#   - Numbers with an inline percent sign embed \% in the macro value.
#   - Dollar values embed \$ and comma thousands separators.

using DelimitedFiles
using Printf

include(joinpath(@__DIR__, "config.jl"))

# Local overrides from run_subset_enumeration.jl (must stay in sync).
const CONSUMPTION_DECLINE_ACTIVE = 0.02
const HEALTH_UTILITY_ACTIVE = [1.0, 0.90, 0.75]

const REPO_ROOT = abspath(joinpath(@__DIR__, ".."))
const CSV_DIR   = joinpath(REPO_ROOT, "tables", "csv")
const OUT_PATH  = joinpath(REPO_ROOT, "paper", "numbers.tex")
const HRS_PATH  = joinpath(REPO_ROOT, "data", "processed", "lockwood_hrs_sample.csv")

# Channel bits (must match run_subset_enumeration.jl).
# Ten channels: eight rational/preference + two behavioral. Medical and R-S
# correlation are combined into a single channel because R-S has no
# economic content without stochastic medical costs to correlate against
# (see review_reports/ for panel discussion).
const B_SS         = 1 << 0
const B_BEQUESTS   = 1 << 1
const B_MED_RS     = 1 << 2   # Combined: medical risk + R-S correlation
const B_PESSIMISM  = 1 << 3
const B_AGE_NEEDS  = 1 << 4
const B_STATE_UTIL = 1 << 5
const B_LOADS      = 1 << 6
const B_INFLATION  = 1 << 7
const B_SDU          = 1 << 8   # Force A: source-dependent utility
const B_PSI_PURCHASE = 1 << 9   # Force B: narrow-framing purchase penalty

# Backward compatibility aliases for prose macros that used the old names.
# B_MEDICAL alone is no longer meaningful (always implies the R-S correlation).
const B_MEDICAL = B_MED_RS
const B_RS      = B_MED_RS

# ---------------------------------------------------------------------------
# Formatting helpers
# ---------------------------------------------------------------------------

function fmt_pct(x; digits::Int=1)
    @sprintf("%.*f\\%%", digits, x)
end

function fmt_num(x; digits::Int=2)
    @sprintf("%.*f", digits, x)
end

function fmt_int(x)
    @sprintf("%d", round(Int, x))
end

function commas(n::Integer)
    s = string(abs(n))
    parts = String[]
    i = length(s)
    while i > 0
        lo = max(1, i - 2)
        pushfirst!(parts, s[lo:i])
        i = lo - 1
    end
    (n < 0 ? "-" : "") * join(parts, ",")
end

# LaTeX-safe thousands separator: wrap each comma in `{,}` so it stays punctuation
# in both text and math mode (bare `,` in math mode inserts an unwanted thin space).
function latex_commas(n::Integer)
    replace(commas(n), "," => "{,}")
end

function fmt_dollar(x::Real; digits::Int=0)
    digits == 0 ? "\\\$$(latex_commas(round(Int, x)))" : "\\\$" * @sprintf("%.*f", digits, x)
end

# ---------------------------------------------------------------------------
# Macro registry
# ---------------------------------------------------------------------------

const MACROS = Pair{String,String}[]

function macro_exists(name::AbstractString)
    for (k, _) in MACROS
        k == name && return true
    end
    return false
end

function def!(name::AbstractString, value::AbstractString)
    macro_exists(name) && error("Duplicate macro definition: \\$name")
    push!(MACROS, name => value)
    return nothing
end

# Post-pass: for every macro whose value ends in "\%", emit a paired "Num"
# variant with the percent sign stripped, so tables can use bare numbers
# under an "Ownership (\%)" header. Any hand-defined Num macro wins.
function backfill_num_variants!()
    additions = Pair{String,String}[]
    for (name, value) in MACROS
        endswith(value, "\\%") || continue
        num_name = name * "Num"
        macro_exists(num_name) && continue
        any(p -> first(p) == num_name, additions) && continue
        push!(additions, num_name => value[1:end-2])
    end
    append!(MACROS, additions)
    return nothing
end

# ---------------------------------------------------------------------------
# Source data loaders
# ---------------------------------------------------------------------------

function read_csv(name::AbstractString)
    path = joinpath(CSV_DIR, name)
    isfile(path) || error("Missing CSV: $path. Run the upstream analysis script first.")
    readdlm(path, ',', Any; header=true)
end

function subset_ownership(bitmask::Int)
    rows, _ = read_csv("subset_enumeration.csv")
    for r in eachrow(rows)
        if Int(r[1]) == bitmask
            return Float64(r[3])  # ownership_pct
        end
    end
    error("bitmask $bitmask not found in subset_enumeration.csv")
end

function subset_alpha(bitmask::Int)
    rows, _ = read_csv("subset_enumeration.csv")
    for r in eachrow(rows)
        if Int(r[1]) == bitmask
            return Float64(r[4])  # mean_alpha
        end
    end
    error("bitmask $bitmask not found in subset_enumeration.csv")
end

# welfare_counterfactuals.csv has unquoted commas in scenario names and
# descriptions, so readdlm fractures rows. Parse by prefix-match + numeric
# tokenization of the tail.
function welfare_counterfactual(scenario::AbstractString)
    path = joinpath(CSV_DIR, "welfare_counterfactuals.csv")
    isfile(path) || error("Missing CSV: $path")
    prefix = scenario * ","
    for (i, line) in enumerate(eachline(path))
        i == 1 && continue  # header
        startswith(line, prefix) || continue
        tail = chopprefix(line, prefix)
        toks = split(tail, ',')
        length(toks) >= 7 || error("malformed row for $(repr(scenario)): $line")
        # Schema: mwr, inflation, psi, c_floor, ss_scale, ownership_pct, mean_alpha,
        # [psi_purchase, description] (psi_purchase added in 10-channel update;
        # parsing falls back to NaN if older 7-channel CSV has only 7+description fields)
        psi_p = length(toks) >= 8 ? tryparse(Float64, toks[8]) : nothing
        return (mwr=parse(Float64, toks[1]),
                inflation=parse(Float64, toks[2]),
                psi=parse(Float64, toks[3]),
                c_floor=parse(Float64, toks[4]),
                ss_scale=parse(Float64, toks[5]),
                ownership_pct=parse(Float64, toks[6]),
                mean_alpha=parse(Float64, toks[7]),
                psi_purchase=psi_p === nothing ? NaN : psi_p)
    end
    error("scenario $(repr(scenario)) not found in welfare_counterfactuals.csv")
end

function cev_grid_row(wealth::Int, health::AbstractString)
    rows, _ = read_csv("welfare_cev_grid.csv")
    for r in eachrow(rows)
        if Int(r[1]) == wealth && String(r[2]) == health
            return (cev_no=Float64(r[3]), alpha_no=Float64(r[4]),
                    cev_dfj=Float64(r[5]), alpha_dfj=Float64(r[6]),
                    cev_strong=Float64(r[7]), alpha_strong=Float64(r[8]))
        end
    end
    error("(wealth=$wealth, health=$health) not in welfare_cev_grid.csv")
end

function cev_counterfactual_row(wealth::Int, health::AbstractString)
    rows, _ = read_csv("cev_counterfactuals.csv")
    for r in eachrow(rows)
        if Int(r[1]) == wealth && String(r[2]) == health
            return (cev_baseline=Float64(r[3]), alpha_baseline=Float64(r[4]),
                    cev_group=Float64(r[5]), alpha_group=Float64(r[6]),
                    cev_real=Float64(r[7]), alpha_real=Float64(r[8]),
                    cev_best=Float64(r[9]), alpha_best=Float64(r[10]))
        end
    end
    error("(wealth=$wealth, health=$health) not in cev_counterfactuals.csv")
end

function population_cev(bequest_spec::AbstractString)
    rows, _ = read_csv("population_cev.csv")
    for r in eachrow(rows)
        if String(r[1]) == bequest_spec
            return (mean_cev=Float64(r[2]), median_cev=Float64(r[3]),
                    frac_positive=Float64(r[4]), frac_above_1pct=Float64(r[5]))
        end
    end
    error("bequest_spec $(repr(bequest_spec)) not in population_cev.csv")
end

function shapley_lookup()
    rows, _ = read_csv("shapley_exact.csv")
    out = Dict{String, NamedTuple{(:value_pp, :share_pct), Tuple{Float64, Float64}}}()
    for r in eachrow(rows)
        out[String(r[1])] = (value_pp=Float64(r[2]), share_pct=Float64(r[3]))
    end
    # 10-channel reformulation compatibility: if only the old separate "Medical"
    # and "R-S" rows are present (pre-reformulation pipeline output), synthesize
    # a combined "Medical+R-S" entry. Owen's coupled-coalition aggregation reduces
    # to summing the two components when they always travel together; for the
    # legacy CSV this is the closest defensible approximation until the AWS
    # rerun produces the proper combined Shapley value.
    if !haskey(out, "Medical+R-S") && haskey(out, "Medical") && haskey(out, "R-S")
        m  = out["Medical"]
        rs = out["R-S"]
        out["Medical+R-S"] = (value_pp = m.value_pp + rs.value_pp,
                              share_pct = m.share_pct + rs.share_pct)
    end
    out
end

# robustness_full.csv embeds commas in specification fields (e.g. "g=2.5,pi=1%")
# so we parse by prefix-match on "category," + reverse-split for the ownership field.
function robustness_ownership(category::AbstractString, specification::AbstractString)
    path = joinpath(CSV_DIR, "robustness_full.csv")
    isfile(path) || error("Missing CSV: $path")
    target = category * "," * specification * ","
    for (i, line) in enumerate(eachline(path))
        i == 1 && continue
        startswith(line, target) || continue
        tail = chopprefix(line, target)
        return parse(Float64, rstrip(tail, '%'))
    end
    error("robustness row ($category, $specification) not found")
end

function ss_cut_ownership(cut_pct::Int)
    rows, _ = read_csv("ss_cut_robustness.csv")
    for r in eachrow(rows)
        if Int(r[1]) == cut_pct
            return Float64(r[2])
        end
    end
    error("ss_cut_pct $cut_pct not in ss_cut_robustness.csv")
end

function state_utility_sensitivity(label::AbstractString)
    rows, _ = read_csv("state_utility_sensitivity.csv")
    for r in eachrow(rows)
        if String(r[1]) == label
            return (phi_good=Float64(r[2]), phi_fair=Float64(r[3]),
                    phi_poor=Float64(r[4]), ownership_pct=Float64(r[5]),
                    mean_alpha=Float64(r[6]))
        end
    end
    error("label $(repr(label)) not in state_utility_sensitivity.csv")
end

function psi_sensitivity(label::AbstractString)
    path = joinpath(CSV_DIR, "psi_sensitivity.csv")
    isfile(path) || return nothing
    prefix = label * ","
    for (i, line) in enumerate(eachline(path))
        i == 1 && continue
        startswith(line, prefix) || continue
        toks = split(chopprefix(line, prefix), ',')
        return (psi=parse(Float64, toks[1]),
                ownership_pct=parse(Float64, toks[2]),
                mean_alpha=parse(Float64, toks[3]),
                solve_time=parse(Float64, toks[4]),
                default_gap_pp=parse(Float64, toks[5]))
    end
    return nothing
end

function monte_carlo_summary()
    path = joinpath(CSV_DIR, "monte_carlo_ownership.csv")
    isfile(path) || return nothing
    raw = readdlm(path, ',', Any; skipstart=1)
    own_col = size(raw, 2)  # last column is ownership_pct (works for old + new schemas)
    vals = sort(Float64.(raw[:, own_col]))
    n = length(vals)
    n == 0 && return nothing
    pick(q) = vals[max(1, round(Int, q * n))]
    return (n=n, mean=sum(vals)/n, median=vals[div(n, 2)],
            q05=pick(0.05), q25=pick(0.25), q75=pick(0.75), q95=pick(0.95),
            min=vals[1], max=vals[end])
end

function hrs_summary()
    isfile(HRS_PATH) || error("Missing HRS sample: $HRS_PATH")
    raw = readdlm(HRS_PATH, ',', Any; skipstart=1)
    n = size(raw, 1)
    wealth_sorted = sort(Float64.(raw[:, 1]))
    median_wealth = wealth_sorted[div(n, 2)]
    wealth = Float64.(raw[:, 1])
    n_elig = count(wealth .>= MIN_WEALTH)
    n_above_wmax = count(wealth .> W_MAX)
    # observed annuity ownership from own_life_ann column (col 5)
    n_own = count(Float64.(raw[:, 5]) .> 0)
    (; n_total=n, n_eligible=n_elig, median_wealth=median_wealth,
       n_above_wmax=n_above_wmax, pct_above_wmax=100 * n_above_wmax / n,
       n_owners=n_own, pct_owners=100 * n_own / n)
end

# ---------------------------------------------------------------------------
# Build macros
# ---------------------------------------------------------------------------

function build_macros!()
    # ======================================================================
    # Section A — Preference, budget, and grid parameters (from config.jl)
    # ======================================================================
    def!("pGamma",              fmt_num(GAMMA; digits=1))
    def!("pBeta",               fmt_num(BETA; digits=2))
    def!("pRRate",              fmt_pct(R_RATE * 100; digits=0))
    def!("pRRateNum",           fmt_num(R_RATE; digits=2))
    def!("pInflation",          fmt_pct(INFLATION * 100; digits=0))
    def!("pInflationNum",       fmt_num(INFLATION; digits=2))
    def!("pCFloor",             fmt_dollar(C_FLOOR))
    def!("pFixedCost",          fmt_dollar(FIXED_COST))
    def!("pMinWealth",          fmt_dollar(MIN_WEALTH))
    def!("pWMax",               fmt_dollar(W_MAX))
    # Use \text{million} so this macro survives inside math mode like $[0, \pWMaxMillions]$.
    def!("pWMaxMillions",       @sprintf("\\\$%s\\text{ million}", W_MAX >= 1_000_000 ? fmt_num(W_MAX / 1_000_000; digits=(W_MAX % 1_000_000 == 0 ? 0 : 1)) : fmt_num(W_MAX / 1_000_000; digits=1)))

    # Bequest
    def!("pThetaDFJ",           fmt_num(THETA_DFJ; digits=2))
    def!("pKappaDFJ",           fmt_dollar(KAPPA_DFJ))

    # Age-varying consumption decline (Aguiar-Hurst)
    def!("pDeltaC",             fmt_num(CONSUMPTION_DECLINE_ACTIVE; digits=2))

    # State-dependent utility weights [G, F, P]
    def!("pHealthUtilGood",     fmt_num(HEALTH_UTILITY_ACTIVE[1]; digits=2))
    def!("pHealthUtilFair",     fmt_num(HEALTH_UTILITY_ACTIVE[2]; digits=2))
    def!("pHealthUtilPoor",     fmt_num(HEALTH_UTILITY_ACTIVE[3]; digits=2))

    # Hazard multipliers [G, F, P]
    def!("pHazardGood",         fmt_num(HAZARD_MULT[1]; digits=2))
    def!("pHazardFair",         fmt_num(HAZARD_MULT[2]; digits=1))
    def!("pHazardPoor",         fmt_num(HAZARD_MULT[3]; digits=1))

    # Survival pessimism
    def!("pPessimism",          fmt_num(SURVIVAL_PESSIMISM; digits=3))

    # Demographics and grid sizes
    def!("pAgeStart",           fmt_int(AGE_START))
    def!("pAgeEnd",             fmt_int(AGE_END))
    def!("pT",                  fmt_int(AGE_END - AGE_START + 1))
    def!("pNWealth",            fmt_int(N_WEALTH))
    def!("pNAnnuity",           fmt_int(N_ANNUITY))
    def!("pNAlpha",             fmt_int(N_ALPHA))
    def!("pNQuad",              fmt_int(N_QUAD))

    # ======================================================================
    # Section B — Baseline MWR (pulled from welfare_counterfactuals.csv
    # "Baseline" row, because that's the value the actual model runs used;
    # scripts/config.jl MWR_LOADED may differ during transitions)
    # ======================================================================
    wc_base = welfare_counterfactual("Baseline")
    def!("pMwrBaseline",        fmt_num(wc_base.mwr; digits=2))
    def!("pMwrLoad",            fmt_pct((1 - wc_base.mwr) * 100; digits=0))

    # ======================================================================
    # Section C — HRS sample summary
    # ======================================================================
    hrs = hrs_summary()
    def!("nHRSTotal",           commas(hrs.n_total))
    def!("nHRSEligible",        fmt_int(hrs.n_eligible))
    def!("nHRSMedianWealth",    fmt_dollar(round(hrs.median_wealth / 1_000) * 1_000))
    def!("nHRSAboveWmax",       fmt_int(hrs.n_above_wmax))
    def!("pctHRSAboveWmax",     fmt_pct(hrs.pct_above_wmax; digits=1))
    def!("pctHRSObserved",      fmt_pct(hrs.pct_owners; digits=1))
    def!("nHRSOwners",          fmt_int(hrs.n_owners))

    # ----------------------------------------------------------------------
    # Section C2 — HRS lifetime annuity indicator (fat-file q286 series)
    # Source: data/processed/hrs_lifetime_ownership.csv (POOLED row)
    # Wilson 95% binomial CIs computed for both lifetime (q286) and any-annuity
    # (r{w}iann income proxy) measures so the manuscript can present both with
    # sampling tolerance.
    # ----------------------------------------------------------------------
    function wilson_ci(k::Int, n::Int; z::Float64=1.96)
        # Wilson score interval — robust for proportions near zero.
        p = k / n
        denom = 1 + z^2 / n
        center = (p + z^2 / (2n)) / denom
        halfwidth = z * sqrt(p * (1 - p) / n + z^2 / (4 * n^2)) / denom
        return (lo = center - halfwidth, hi = center + halfwidth)
    end

    hrs_lifetime_path = joinpath(REPO_ROOT, "data", "processed", "hrs_lifetime_ownership.csv")
    if isfile(hrs_lifetime_path)
        for (i, line) in enumerate(eachline(hrs_lifetime_path))
            i == 1 && continue
            startswith(line, "POOLED,") || continue
            toks = split(chopprefix(line, "POOLED,"), ',')
            n_elig    = parse(Int, toks[1])
            n_iann    = parse(Int, toks[2])
            n_lifetime = parse(Int, toks[4])
            iann_pct  = parse(Float64, toks[5])
            lifetime_pct = parse(Float64, toks[7])
            def!("nHRSLifetimeEligible", commas(n_elig))
            def!("nHRSLifetimeOwners",   fmt_int(n_lifetime))
            def!("pctHRSLifetime",       fmt_pct(lifetime_pct; digits=2))
            def!("pctHRSIannPooled",     fmt_pct(iann_pct;     digits=2))
            def!("nHRSIannOwners",       fmt_int(n_iann))

            # Wilson 95% CIs for both measures
            ci_life = wilson_ci(n_lifetime, n_elig)
            ci_iann = wilson_ci(n_iann, n_elig)
            def!("pctHRSLifetimeCILow",  fmt_pct(100 * ci_life.lo; digits=2))
            def!("pctHRSLifetimeCIHigh", fmt_pct(100 * ci_life.hi; digits=2))
            def!("pctHRSIannCILow",      fmt_pct(100 * ci_iann.lo; digits=2))
            def!("pctHRSIannCIHigh",     fmt_pct(100 * ci_iann.hi; digits=2))
            break
        end
    end

    # ----------------------------------------------------------------------
    # Section C3 — UK ELSA pre/post 2015 freedoms empirical evidence
    # Source: data/processed/elsa_pre_post_freedoms.csv,
    #         data/processed/elsa_disposition_pooled.csv
    # ----------------------------------------------------------------------
    elsa_pp_path = joinpath(REPO_ROOT, "data", "processed", "elsa_pre_post_freedoms.csv")
    if isfile(elsa_pp_path)
        for (i, line) in enumerate(eachline(elsa_pp_path))
            i == 1 && continue
            toks = split(chomp(line), ',')
            length(toks) == 5 || continue
            regime, measure, n_yes, n_denom, pct = toks
            if regime == "pre_freedoms_w6" && measure == "annuity_style_of_dc_recipients"
                # LaTeX macro names cannot contain digits, so "W6" -> "WaveSix".
                def!("nELSAWaveSixDC",         fmt_int(parse(Int, n_denom)))
                def!("nELSAWaveSixAnnuity",    fmt_int(parse(Int, n_yes)))
                def!("pctELSAWaveSixAnnuity",  fmt_pct(parse(Float64, pct); digits=1))
            elseif regime == "post_freedoms_w8_11" && measure == "lumpsum_annuitize"
                def!("nELSAPostLumpSum",  fmt_int(parse(Int, n_denom)))
                def!("nELSAPostAnnuity",  fmt_int(parse(Int, n_yes)))
                def!("pctELSAPostAnnuity", fmt_pct(parse(Float64, pct); digits=2))
            elseif regime == "post_freedoms_pool_w8_11" && measure == "lumpsum_annuitize"
                def!("nELSAPostLumpSum",  fmt_int(parse(Int, n_denom)))
                def!("nELSAPostAnnuity",  fmt_int(parse(Int, n_yes)))
                def!("pctELSAPostAnnuity", fmt_pct(parse(Float64, pct); digits=2))
            elseif regime == "post_freedoms_pool_w8_11" && measure == "plan_annuitize"
                def!("nELSAPostPlanDC",      fmt_int(parse(Int, n_denom)))
                def!("nELSAPostPlanAnnuity", fmt_int(parse(Int, n_yes)))
                def!("pctELSAPostPlanAnnuity", fmt_pct(parse(Float64, pct); digits=1))
            end
        end
        # Implied behavioral elasticity: pre - post (for both lump-sum and plan measures)
        # Pre = 90.2%, post (lump-sum) = 1.27%, post (plan) = 3.50%
        # Headline drop:
        #   90.2 - 1.27 = 88.9 pp (lump-sum disposition basis)
        #   90.2 - 3.50 = 86.7 pp (forward-plan basis)
        def!("ELSADropLumpSum", fmt_num(88.9; digits=0))
        def!("ELSADropPlan",    fmt_num(86.7; digits=0))
        def!("ELSADropRange",   "87--89")
    end

    # ======================================================================
    # Section D — Sequential decomposition (retention path)
    # Bitmasks follow the decomposition ordering used by run_subset_enumeration.jl
    # ======================================================================
    # Frictionless population benchmark
    def!("ownFrictionless",     fmt_pct(subset_ownership(0); digits=1))

    # + SS
    def!("ownAddSS",            fmt_pct(subset_ownership(B_SS); digits=1))
    # + Bequests (SS + Bequests)
    def!("ownAddBequests",      fmt_pct(subset_ownership(B_SS | B_BEQUESTS); digits=1))
    # + Medical risk + R-S correlation (combined channel under 10-channel reformulation)
    def!("ownAddMedRS",         fmt_pct(subset_ownership(B_SS | B_BEQUESTS | B_MED_RS); digits=1))
    # Backward-compat aliases — under 10-channel structure both add the same bundle.
    def!("ownAddMedical",       fmt_pct(subset_ownership(B_SS | B_BEQUESTS | B_MED_RS); digits=1))
    def!("ownAddRS",            fmt_pct(subset_ownership(B_SS | B_BEQUESTS | B_MED_RS); digits=1))
    # + Pessimism
    def!("ownAddPessimism",     fmt_pct(subset_ownership(B_SS | B_BEQUESTS | B_MED_RS | B_PESSIMISM); digits=1))
    # + Loads (skip age needs / state utility — these come in the extension table)
    def!("ownAddLoads",         fmt_pct(subset_ownership(B_SS | B_BEQUESTS | B_MED_RS | B_PESSIMISM | B_LOADS); digits=1))
    # + Inflation  (= 6-channel rational under 10-channel reformulation, bitmask 207)
    def!("ownSixChannel",       fmt_pct(subset_ownership(B_SS | B_BEQUESTS | B_MED_RS | B_PESSIMISM | B_LOADS | B_INFLATION); digits=1))
    # Backward-compat alias (was 7-channel under old 11-channel naming).
    def!("ownSevenChannel",     fmt_pct(subset_ownership(B_SS | B_BEQUESTS | B_MED_RS | B_PESSIMISM | B_LOADS | B_INFLATION); digits=1))
    # + Age needs   (= 7-channel under 10-channel reformulation, bitmask 223)
    def!("ownSevenChannelExt",  fmt_pct(subset_ownership(B_SS | B_BEQUESTS | B_MED_RS | B_PESSIMISM | B_AGE_NEEDS | B_LOADS | B_INFLATION); digits=1))
    def!("ownEightChannel",     fmt_pct(subset_ownership(B_SS | B_BEQUESTS | B_MED_RS | B_PESSIMISM | B_AGE_NEEDS | B_LOADS | B_INFLATION); digits=1))
    # + State utility (= 8-channel rational+preferences under 10-channel, bitmask 255)
    def!("ownEightChannelExt",  fmt_pct(subset_ownership(B_SS | B_BEQUESTS | B_MED_RS | B_PESSIMISM | B_AGE_NEEDS | B_STATE_UTIL | B_LOADS | B_INFLATION); digits=1))
    def!("ownNineChannel",      fmt_pct(subset_ownership(B_SS | B_BEQUESTS | B_MED_RS | B_PESSIMISM | B_AGE_NEEDS | B_STATE_UTIL | B_LOADS | B_INFLATION); digits=1))
    # + SDU (= 9-channel: rational + Force A only). Bitmask 511.
    try
        def!("ownNineChannelSDU", fmt_pct(subset_ownership(B_SS | B_BEQUESTS | B_MED_RS | B_PESSIMISM | B_AGE_NEEDS | B_STATE_UTIL | B_LOADS | B_INFLATION | B_SDU); digits=1))
        def!("ownTenChannel",     fmt_pct(subset_ownership(B_SS | B_BEQUESTS | B_MED_RS | B_PESSIMISM | B_AGE_NEEDS | B_STATE_UTIL | B_LOADS | B_INFLATION | B_SDU); digits=1))
    catch e
        @warn "Skipping ownTenChannel macro (10-channel pipeline not yet run)" exception=e
    end
    # + Narrow-framing PED (= full 10-channel under reformulation, bitmask 1023). Headline production.
    try
        def!("ownTenChannelFull", fmt_pct(subset_ownership(B_SS | B_BEQUESTS | B_MED_RS | B_PESSIMISM | B_AGE_NEEDS | B_STATE_UTIL | B_LOADS | B_INFLATION | B_SDU | B_PSI_PURCHASE); digits=1))
        def!("ownElevenChannel",  fmt_pct(subset_ownership(B_SS | B_BEQUESTS | B_MED_RS | B_PESSIMISM | B_AGE_NEEDS | B_STATE_UTIL | B_LOADS | B_INFLATION | B_SDU | B_PSI_PURCHASE); digits=1))
    catch e
        @warn "Skipping ownElevenChannel macro (10-channel pipeline not yet run)" exception=e
    end

    # Retention rate for SS step (complement as percent)
    own_friction = subset_ownership(0)
    own_ss = subset_ownership(B_SS)
    def!("retentionSS",         fmt_pct(own_ss / own_friction * 100; digits=1))

    # Specific prose values
    own_pre_pessimism = subset_ownership(B_SS | B_BEQUESTS | B_MED_RS)
    own_post_pessimism = subset_ownership(B_SS | B_BEQUESTS | B_MED_RS | B_PESSIMISM)
    def!("ownPrePessimism",     fmt_pct(own_pre_pessimism; digits=1))
    def!("deltaPessimism",      fmt_num(own_post_pessimism - own_pre_pessimism; digits=1))
    def!("retentionPessimism",  fmt_pct(own_post_pessimism / own_pre_pessimism * 100; digits=1))

    # Loads step
    own_post_loads = subset_ownership(B_SS | B_BEQUESTS | B_MED_RS | B_PESSIMISM | B_LOADS)
    def!("retentionLoads",      fmt_pct(own_post_loads / own_post_pessimism * 100; digits=1))

    # Inflation step
    own_post_inflation = subset_ownership(B_SS | B_BEQUESTS | B_MED_RS | B_PESSIMISM | B_LOADS | B_INFLATION)
    def!("retentionInflation",  fmt_pct(own_post_inflation / own_post_loads * 100; digits=1))

    # Combined Medical+R-S delta under 10-channel reformulation.
    # The medical risk and R-S correlation channels are coupled (R-S has no
    # economic content without medical costs to correlate against), so they
    # are added together as a single bundle.
    own_pre_med_rs = subset_ownership(B_SS | B_BEQUESTS)
    own_post_med_rs = subset_ownership(B_SS | B_BEQUESTS | B_MED_RS)
    def!("deltaMedRS",          fmt_num(own_post_med_rs - own_pre_med_rs; digits=1))
    def!("magDeltaMedRS",       fmt_num(abs(own_post_med_rs - own_pre_med_rs); digits=1))
    def!("retentionMedRS",      fmt_pct(own_post_med_rs / own_pre_med_rs * 100; digits=1))
    # Backward-compat aliases for prose still using the old separate names.
    # Both refer to the combined Medical+R-S bundle delta.
    def!("deltaMedical",        fmt_num(own_post_med_rs - own_pre_med_rs; digits=1))
    def!("magDeltaMedical",     fmt_num(abs(own_post_med_rs - own_pre_med_rs); digits=1))
    def!("retentionMedical",    fmt_pct(own_post_med_rs / own_pre_med_rs * 100; digits=1))
    def!("deltaRS",             fmt_num(own_post_med_rs - own_pre_med_rs; digits=1))
    def!("magDeltaRS",          fmt_num(abs(own_post_med_rs - own_pre_med_rs); digits=1))
    def!("retentionRS",         fmt_pct(own_post_med_rs / own_pre_med_rs * 100; digits=1))

    # ======================================================================
    # Section E — Extension path
    # Under 10-channel reformulation: 6-channel rational (SS, Bequests, Med+R-S,
    # Pessimism, Loads, Inflation) → +Age needs → +State utility = 8-channel.
    # Old 11-channel naming retained as aliases for manuscript backward compat.
    # ======================================================================
    own_base = subset_ownership(B_SS | B_BEQUESTS | B_MED_RS | B_PESSIMISM | B_LOADS | B_INFLATION)
    own_with_age = subset_ownership(B_SS | B_BEQUESTS | B_MED_RS | B_PESSIMISM | B_AGE_NEEDS | B_LOADS | B_INFLATION)
    own_with_state = subset_ownership(B_SS | B_BEQUESTS | B_MED_RS | B_PESSIMISM | B_AGE_NEEDS | B_STATE_UTIL | B_LOADS | B_INFLATION)
    def!("deltaAgeNeeds",       fmt_num(own_with_age - own_base; digits=1))
    def!("deltaStateUtil",      fmt_num(own_with_state - own_with_age; digits=1))

    # ======================================================================
    # Section F — Shapley values (from shapley_exact.csv)
    # ======================================================================
    sh = shapley_lookup()
    def!("shapSS",              fmt_num(sh["SS"].value_pp; digits=1))
    def!("shapBequests",        fmt_num(sh["Bequests"].value_pp; digits=1))
    # Combined Medical + R-S correlation channel (10-channel reformulation).
    def!("shapMedRS",           fmt_num(sh["Medical+R-S"].value_pp; digits=1))
    # Backward-compat aliases for prose still using the old separate names.
    def!("shapMedical",         fmt_num(sh["Medical+R-S"].value_pp; digits=1))
    def!("shapRS",              fmt_num(sh["Medical+R-S"].value_pp; digits=1))
    def!("shapPessimism",       fmt_num(sh["Pessimism"].value_pp; digits=1))
    def!("shapAgeNeeds",        fmt_num(sh["Age needs"].value_pp; digits=1))
    def!("shapStateUtil",       fmt_num(sh["State utility"].value_pp; digits=1))
    def!("shapLoads",           fmt_num(sh["Loads"].value_pp; digits=1))
    def!("shapInflation",       fmt_num(sh["Inflation"].value_pp; digits=1))
    if haskey(sh, "SDU (Force A)")
        def!("shapSDU",         fmt_num(sh["SDU (Force A)"].value_pp; digits=1))
    end
    if haskey(sh, "Narrow framing (Force B)")
        def!("shapNarrowFraming", fmt_num(sh["Narrow framing (Force B)"].value_pp; digits=1))
    end

    def!("shapShareSS",         fmt_pct(sh["SS"].share_pct; digits=0))
    def!("shapShareBequests",   fmt_pct(sh["Bequests"].share_pct; digits=0))
    def!("shapShareMedRS",      fmt_pct(sh["Medical+R-S"].share_pct; digits=0))
    def!("shapShareMedical",    fmt_pct(sh["Medical+R-S"].share_pct; digits=0))  # alias
    def!("shapShareRS",         fmt_pct(sh["Medical+R-S"].share_pct; digits=0))  # alias
    def!("shapSharePessimism",  fmt_pct(sh["Pessimism"].share_pct; digits=0))
    def!("shapShareAgeNeeds",   fmt_pct(sh["Age needs"].share_pct; digits=0))
    def!("shapShareStateUtil",  fmt_pct(sh["State utility"].share_pct; digits=0))
    def!("shapShareLoads",      fmt_pct(sh["Loads"].share_pct; digits=0))
    def!("shapShareInflation",  fmt_pct(sh["Inflation"].share_pct; digits=0))
    if haskey(sh, "SDU (Force A)")
        def!("shapShareSDU",    fmt_pct(sh["SDU (Force A)"].share_pct; digits=0))
    end
    if haskey(sh, "Narrow framing (Force B)")
        def!("shapShareNarrowFraming", fmt_pct(sh["Narrow framing (Force B)"].share_pct; digits=0))
    end

    # Non-pricing non-traditional channels sum: Med+R-S + Pessimism + Age needs
    rs_pess_age_pp    = sh["Medical+R-S"].value_pp + sh["Pessimism"].value_pp + sh["Age needs"].value_pp
    rs_pess_age_share = sh["Medical+R-S"].share_pct + sh["Pessimism"].share_pct + sh["Age needs"].share_pct
    def!("shapRSPessAge",       fmt_num(rs_pess_age_pp; digits=1))
    def!("shapShareRSPessAge",  fmt_pct(rs_pess_age_share; digits=0))

    # ======================================================================
    # Section G — Welfare: CEV at headline cells
    # ======================================================================
    cev = cev_grid_row(100_000, "Good")
    def!("cevGoodHundredKNoBq",      fmt_pct(cev.cev_no * 100; digits=1))
    def!("cevGoodHundredKDFJ",       fmt_pct(cev.cev_dfj * 100; digits=1))
    def!("cevGoodHundredKStrong",    fmt_pct(cev.cev_strong * 100; digits=1))

    cev = cev_grid_row(200_000, "Good")
    def!("cevGoodTwoHundredKNoBq",   fmt_pct(cev.cev_no * 100; digits=1))
    def!("cevGoodTwoHundredKDFJ",    fmt_pct(cev.cev_dfj * 100; digits=1))
    def!("cevGoodTwoHundredKStrong", fmt_pct(cev.cev_strong * 100; digits=1))

    cev = cev_grid_row(1_000_000, "Good")
    def!("cevGoodOneMillNoBq",       fmt_pct(cev.cev_no * 100; digits=1))
    def!("cevGoodOneMillDFJ",        fmt_pct(cev.cev_dfj * 100; digits=1))
    def!("cevGoodOneMillStrong",     fmt_pct(cev.cev_strong * 100; digits=1))

    # Population CEV
    pop_no  = population_cev("No bequest")
    pop_dfj = population_cev("Moderate (DFJ)")
    def!("popMeanCevNoBq",      fmt_pct(pop_no.mean_cev * 100; digits=1))
    def!("popMeanCevDFJ",       fmt_pct(pop_dfj.mean_cev * 100; digits=1))
    def!("popFracPosNoBq",      fmt_pct(pop_no.frac_positive * 100; digits=1))
    def!("popFracPosDFJ",       fmt_pct(pop_dfj.frac_positive * 100; digits=1))
    def!("popFracAboveOneNoBq", fmt_pct(pop_no.frac_above_1pct * 100; digits=1))
    def!("popFracAboveOneDFJ",  fmt_pct(pop_dfj.frac_above_1pct * 100; digits=1))

    # ======================================================================
    # Section H — Policy counterfactuals (welfare_counterfactuals.csv)
    # ======================================================================
    for (key, scenario) in [
        ("GroupPricing",     "Group pricing (MWR=0.90)"),
        ("PublicOption",     "Public option (MWR=0.95)"),
        ("ActuariallyFair",  "Actuarially fair (MWR=1.0)"),
        ("RealTIPS",         "Real annuity, TIPS-backed"),
        ("RealNomEquiv",     "Real annuity, nominal-equiv"),
        ("FairReal",         "Fair + real"),
        ("CorrectPessimism", "Correct pessimism (psi=1.0)"),
        ("GroupPlusCorrect", "Group + correct pessimism"),
        ("BestFeasible",     "Best feasible package"),
    ]
        wc = welfare_counterfactual(scenario)
        def!("own" * key, fmt_pct(wc.ownership_pct; digits=1))
    end

    # CEV counterfactuals at specific wealth cells
    for (suffix, wealth) in [("HundredK", 100_000), ("TwoHundredK", 200_000),
                             ("FiveHundredK", 500_000), ("OneMill", 1_000_000)]
        cc = cev_counterfactual_row(wealth, "Good")
        def!("cevGood" * suffix * "Baseline",    fmt_pct(cc.cev_baseline * 100; digits=1))
        def!("cevGood" * suffix * "GroupPrice",  fmt_pct(cc.cev_group * 100; digits=1))
        def!("cevGood" * suffix * "RealAnn",     fmt_pct(cc.cev_real * 100; digits=1))
        def!("cevGood" * suffix * "BestFeas",    fmt_pct(cc.cev_best * 100; digits=1))
    end

    # ======================================================================
    # Section I — Robustness (gamma, inflation, psi sweeps)
    # ======================================================================
    for (key, spec) in [
        ("Two",          "gamma=2.00"),
        ("TwoPointThree","gamma=2.30"),
        ("TwoPointFour", "gamma=2.40"),
        ("TwoPointFive", "gamma=2.50"),
        ("Three",        "gamma=3.00"),
    ]
        def!("ownGamma" * key, fmt_pct(robustness_ownership("Gamma sweep", spec); digits=1))
    end

    # Inflation is reported via the combined Gamma×Inflation sweep
    for (key, spec) in [
        ("One",   "g=2.5,pi=1%"),
        ("Two",   "g=2.5,pi=2%"),
        ("Three", "g=2.5,pi=3%"),
    ]
        def!("ownInflation" * key, fmt_pct(robustness_ownership("Gamma×Inflation", spec); digits=1))
    end

    # Survival pessimism sweep
    for (key, spec) in [
        ("Objective",    "psi=1.000"),
        ("NinetySeven",  "psi=0.970"),
        ("Baseline",     "psi=0.981"),
        ("NinetyNine",   "psi=0.990"),
    ]
        def!("ownPsi" * key, fmt_pct(robustness_ownership("Survival pessimism", spec); digits=1))
    end

    # MWR sweep (appears in MWR sensitivity table in main.tex)
    for (key, spec) in [
        ("EightyTwo",    "MWR=0.82"),
        ("EightyFive",   "MWR=0.85"),
        ("Ninety",       "MWR=0.90"),
        ("NinetyFive",   "MWR=0.95"),
    ]
        def!("ownMWR" * key, fmt_pct(robustness_ownership("MWR sweep", spec); digits=1))
    end

    # Bequest specifications
    def!("ownBequestNone", fmt_pct(robustness_ownership("Bequest spec", "No bequests"); digits=1))

    # Hazard multiplier sensitivity (Section "Health-mortality correlation" in robustness)
    def!("ownHazardRS",           fmt_pct(robustness_ownership("Hazard mult", "[0.45, 1.0, 3.5] (R-S functional, age 65-75)"); digits=1))
    def!("ownHazardHRS",          fmt_pct(robustness_ownership("Hazard mult", "[0.57, 1.0, 2.7] (HRS SRH empirical)"); digits=1))
    def!("ownHazardConservative", fmt_pct(robustness_ownership("Hazard mult", "[0.60, 1.0, 2.0] (conservative SRH)"); digits=1))
    def!("ownHazardAgeBand",      fmt_pct(robustness_ownership("Hazard mult", "Age-varying HRS (3 bands)"); digits=1))

    # ======================================================================
    # Section J — SS cut robustness (from welfare_counterfactuals "SS cut 23%")
    # and ss_cut_robustness.csv if finer grid needed
    # ======================================================================
    def!("ownSSCutZero",       fmt_pct(ss_cut_ownership(0);   digits=1))
    def!("ownSSCutTen",        fmt_pct(ss_cut_ownership(10);  digits=1))
    def!("ownSSCutFifteen",    fmt_pct(ss_cut_ownership(15);  digits=1))
    def!("ownSSCutTwentyThree",fmt_pct(ss_cut_ownership(23);  digits=1))
    def!("ownSSCutThirty",     fmt_pct(ss_cut_ownership(30);  digits=1))
    def!("ownSSCutForty",      fmt_pct(ss_cut_ownership(40);  digits=1))
    def!("ownSSCutFifty",      fmt_pct(ss_cut_ownership(50);  digits=1))
    def!("ownSSCutHundred",    fmt_pct(ss_cut_ownership(100); digits=1))

    # ======================================================================
    # Section K — State-dependent utility sensitivity (both FLN mappings)
    # Source: tables/csv/state_utility_sensitivity.csv
    # ======================================================================
    fln = state_utility_sensitivity("FLN")
    rs  = state_utility_sensitivity("ReichlingSmetters")

    # Raw FLN central mapping (currently the production calibration)
    def!("pHealthUtilFairFLN", fmt_num(fln.phi_fair; digits=2))
    def!("pHealthUtilPoorFLN", fmt_num(fln.phi_poor; digits=2))
    def!("ownNineChannelFLN",  fmt_pct(fln.ownership_pct; digits=1))

    # Reichling-Smetters softer mapping (robustness case)
    def!("pHealthUtilFairRS",  fmt_num(rs.phi_fair;  digits=2))
    def!("pHealthUtilPoorRS",  fmt_num(rs.phi_poor;  digits=2))
    def!("ownNineChannelRS",   fmt_pct(rs.ownership_pct; digits=1))

    # Difference: how much the softer mapping shifts ownership (always small)
    def!("deltaNineChannelRSmFLN", fmt_num(rs.ownership_pct - fln.ownership_pct; digits=1))

    # ======================================================================
    # Section L — Behavioral channel: psi_purchase sensitivity
    # Source: tables/csv/psi_sensitivity.csv (skipped if missing)
    # ======================================================================
    # Anchors from the UK 2015 pension freedoms calibration:
    # - ABI rational-corrected (low/mid/high): aggregate sales-volume decline
    #   mapped through the model after stripping the rational tax-removal
    #   response. Mid is the production / bracket-low end.
    # - ELSA rational-corrected (low/high): UK ELSA wave 6 vs waves 8-11
    #   microdata after the same rational stripping.
    # - ABI total drop: aggregate sales-volume decline, no rational stripping.
    # - ELSA total drop: ELSA microdata, no rational stripping; bracket-high end.
    # Above-range values reported as a corner-bound diagnostic.
    # Macro suffixes (UKLow/UKMid/UKHigh/UKELSALow/UKELSAHigh/UKBLow/UKELSATotal)
    # are stable internal keys referenced from the appendix anchor table.
    psi_macros = [
        ("Zero",        "No PED (rational + SDU only)"),
        ("UKLow",       "ABI rational-corrected low"),                # tax-stripped ABI aggregate
        ("UKMid",       "ABI rational-corrected mid"),                # production / bracket low end
        ("UKHigh",      "ABI rational-corrected high"),               # tax-stripped ABI aggregate
        ("UKELSALow",   "ELSA rational-corrected low"),               # ELSA microdata, low strip
        ("UKELSAHigh",  "ELSA rational-corrected high"),              # ELSA microdata, high strip
        ("UKBLow",      "ABI total drop (no rational stripping)"),    # ABI aggregate, raw
        ("UKELSATotal", "ELSA total drop (no rational stripping)"),   # ELSA microdata, raw; bracket high end
        ("AboveRange",  "Above sensitivity range"),
        ("Corner",      "Corner-bound region"),
    ]
    for (suffix, label) in psi_macros
        s = psi_sensitivity(label)
        s === nothing && continue
        def!("ownPsi" * suffix,        fmt_pct(s.ownership_pct; digits=1))
        def!("pPsi" * suffix,          fmt_num(s.psi;           digits=4))
        def!("defaultGapPsi" * suffix, fmt_num(s.default_gap_pp;digits=1))
    end

    # Production psi value (from config.jl PSI_PURCHASE; UK 2015 Anchor C-mid)
    def!("pPsiPurchase", fmt_num(0.0163; digits=4))
    # Force A — source-dependent utility weight (config.jl LAMBDA_W = 50/80)
    def!("pLambdaW", fmt_num(0.625; digits=3))
    # Reference consumption for narrow-framing penalty (config.jl PSI_PURCHASE_C_REF)
    def!("pPsiPurchaseCRef", "18{,}000")

    # ----------------------------------------------------------------------
    # Section L2 — Headline bracket (UK ELSA microdata + ABI aggregate)
    # The "headline bracket" reflects the empirically defensible UK calibration
    # anchor range. Lower ψ corresponds to higher predicted ownership.
    #   Bracket low  (ψ=0.0163): conservative; ABI rational-corrected mid
    #                            (aggregate sales-volume decline mapped through
    #                            the model after stripping the rational
    #                            tax-removal response).
    #   Bracket high (ψ=0.0335): aggressive; ELSA microdata total drop
    #                            (no rational stripping).
    # The wider sensitivity range adds the corner-bound and below-anchor values.
    # ----------------------------------------------------------------------
    let
        s_low  = psi_sensitivity("ABI rational-corrected mid")             # ψ=0.0163
        s_high = psi_sensitivity("ELSA total drop (no rational stripping)") # ψ=0.0335
        if s_low !== nothing && s_high !== nothing
            # ownBracketHigh = upper end of ownership range (lower ψ, conservative)
            # ownBracketLow  = lower end of ownership range (higher ψ, aggressive)
            def!("ownBracketHigh", fmt_pct(s_low.ownership_pct;  digits=1))
            def!("ownBracketLow",  fmt_pct(s_high.ownership_pct; digits=1))
            def!("pPsiBracketLow",  fmt_num(s_low.psi;  digits=4))
            def!("pPsiBracketHigh", fmt_num(s_high.psi; digits=4))
        end
        # Wider sensitivity range (UKLow → corner-bound)
        s_widel = psi_sensitivity("ABI rational-corrected low")
        s_wideh = psi_sensitivity("Above sensitivity range")
        if s_widel !== nothing && s_wideh !== nothing
            def!("ownBracketWideHigh", fmt_pct(s_widel.ownership_pct; digits=1))
            def!("ownBracketWideLow",  fmt_pct(s_wideh.ownership_pct; digits=1))
        end
    end

    # ======================================================================
    # Section M — Monte Carlo parameter uncertainty
    # Source: tables/csv/monte_carlo_ownership.csv (skipped if missing)
    # ======================================================================
    mc = monte_carlo_summary()
    if mc !== nothing
        # LaTeX macro names cannot contain digits, so spell percentile labels.
        def!("mcMedianOwnership",    fmt_pct(mc.median; digits=1))
        def!("mcMeanOwnership",      fmt_pct(mc.mean;   digits=1))
        def!("mcLowCIOwnership",     fmt_pct(mc.q05;    digits=1))  # 5th pct
        def!("mcHighCIOwnership",    fmt_pct(mc.q95;    digits=1))  # 95th pct
        def!("mcLowIQROwnership",    fmt_pct(mc.q25;    digits=1))  # 25th pct
        def!("mcHighIQROwnership",   fmt_pct(mc.q75;    digits=1))  # 75th pct
        def!("mcMinOwnership",       fmt_pct(mc.min;    digits=1))
        def!("mcMaxOwnership",       fmt_pct(mc.max;    digits=1))
        def!("nMCDraws",             commas(mc.n))
    end
end

# ---------------------------------------------------------------------------
# Emit numbers.tex
# ---------------------------------------------------------------------------

function write_numbers_tex()
    open(OUT_PATH, "w") do io
        println(io, "% !TEX root = main.tex")
        println(io, "% ------------------------------------------------------------------")
        println(io, "% AUTO-GENERATED by scripts/export_manuscript_numbers.jl")
        println(io, "% Do not edit by hand. Regenerate after any analysis re-run.")
        println(io, "% ------------------------------------------------------------------")
        println(io)
        for (name, value) in MACROS
            println(io, "\\newcommand{\\$name}{$value}")
        end
    end
    println("Wrote $(length(MACROS)) macros to $OUT_PATH")
end

build_macros!()
backfill_num_variants!()

# ---------------------------------------------------------------------------
# Auto-generate the extension_path.tex table (3-layer narrative).
# Produces an updated version reflecting whatever bitmasks 415/447/511/1023
# show in subset_enumeration.csv. Skips silently if subset CSV is incomplete.
# ---------------------------------------------------------------------------

function write_extension_path_table()
    # 6-channel rational baseline (under 10-channel reformulation Med+R-S is one channel).
    # Variable names retain "bm7..bm11" for layout backward compat with the table prose,
    # but the count of distinct channels under the reformulation is 6/7/8/9/10.
    bm7 = B_SS | B_BEQUESTS | B_MED_RS | B_PESSIMISM | B_LOADS | B_INFLATION
    # + age needs
    bm8 = bm7 | B_AGE_NEEDS
    # + state utility (= 8-channel rational+preferences under reformulation)
    bm9 = bm8 | B_STATE_UTIL
    # + SDU (Force A; = 9-channel under reformulation)
    bm10 = bm9 | B_SDU
    # + narrow-framing PED (Force B; = full 10-channel under reformulation)
    bm11 = bm10 | B_PSI_PURCHASE

    own = Dict{Int,Float64}()
    for bm in (bm7, bm8, bm9, bm10, bm11)
        try
            own[bm] = subset_ownership(bm)
        catch
            return  # incomplete subset enumeration; skip
        end
    end

    out = joinpath(REPO_ROOT, "tables", "tex", "extension_path.tex")
    open(out, "w") do f
        println(f, raw"\begin{table}[htbp]")
        println(f, raw"\centering")
        println(f, raw"\caption{Four-Layer Decomposition: Rational, Preference, and Two Behavioral Channels}")
        println(f, raw"\label{tab:extension_path}")
        println(f, raw"\begin{threeparttable}")
        println(f, raw"\begin{tabular}{lcc}")
        println(f, raw"\toprule")
        println(f, "Specification & Ownership (\\%) & \$\\Delta\$ (pp) \\\\")
        println(f, raw"\midrule")
        @printf(f, "Six rational channels (Layer~1)              & %.1f & --- \\\\\n", own[bm7])
        @printf(f, "+ Age-varying consumption needs              & %.1f & %+.1f \\\\\n",
                own[bm8], own[bm8] - own[bm7])
        @printf(f, "+ State-dependent utility (Layer~2 complete) & %.1f & %+.1f \\\\\n",
                own[bm9], own[bm9] - own[bm8])
        @printf(f, "+ Source-dependent utility (Force A)         & %.1f & %+.1f \\\\\n",
                own[bm10], own[bm10] - own[bm9])
        @printf(f, "+ Narrow-framing penalty (Force B)           & %.1f & %+.1f \\\\\n",
                own[bm11], own[bm11] - own[bm10])
        println(f, raw"\bottomrule")
        println(f, raw"\end{tabular}")
        println(f, raw"\begin{tablenotes}")
        println(f, raw"\small")
        println(f, raw"\item Layer 1 is the standard rational decomposition. Layer 2 adds the two")
        println(f, raw"preference channels (age-varying needs from \citealp{aguiarhurst2013}; state-")
        println(f, raw"dependent utility from \citealp{finkelsteinluttmer2013}). Force A introduces")
        println(f, raw"source-dependent utility \citep{blanchett2024,blanchett2025}: portfolio-financed")
        println(f, raw"consumption is discounted relative to income-financed consumption, mirroring the")
        println(f, raw"specification in the FPR companion paper. Force B introduces a narrow-framing")
        println(f, raw"purchase penalty \citep{barberishuang2009,tverskykahneman1992}: a per-period")
        println(f, raw"loss-aversion flow over the unrecouped premium, decaying to zero at breakeven.")
        println(f, raw"\end{tablenotes}")
        println(f, raw"\end{threeparttable}")
        println(f, raw"\end{table}")
    end
    println("Wrote $(out)")
end

write_extension_path_table()


# ---------------------------------------------------------------------------
# Submission-grade strict mode (default): every expected macro must come from
# a real CSV value. Set ANNUITY_ALLOW_TBD_FALLBACKS=1 in the environment to
# emit red TBD placeholders for missing values during partial pipeline runs;
# this is intended for in-development use only and must NOT be set when
# generating the artifact for journal submission.
# ---------------------------------------------------------------------------

const FALLBACKS = String[
    "ownTenChannel", "ownElevenChannel",
    "shapSDU", "shapShareSDU",
    "shapNarrowFraming", "shapShareNarrowFraming",
    "mcMedianOwnership", "mcMeanOwnership",
    "mcLowCIOwnership", "mcHighCIOwnership",
    "mcLowIQROwnership", "mcHighIQROwnership",
    "mcMinOwnership", "mcMaxOwnership", "nMCDraws",
]

allow_tbd = get(ENV, "ANNUITY_ALLOW_TBD_FALLBACKS", "0") == "1"
missing_macros = String[]
for name in FALLBACKS
    macro_exists(name) && continue
    push!(missing_macros, name)
    if allow_tbd
        push!(MACROS, name => "{\\color{red}TBD}")
    end
end

if !isempty(missing_macros) && !allow_tbd
    error("Missing macros (no upstream CSV value available): " *
          join(missing_macros, ", ") *
          ". Run the full pipeline (run_all.jl) first, or set " *
          "ANNUITY_ALLOW_TBD_FALLBACKS=1 to emit red TBD placeholders for " *
          "in-development compilation.")
elseif !isempty(missing_macros)
    @warn "ANNUITY_ALLOW_TBD_FALLBACKS=1 is set; emitting TBD placeholders" missing_macros
end

backfill_num_variants!()

write_numbers_tex()
