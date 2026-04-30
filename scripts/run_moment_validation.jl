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
    lambda_w=LAMBDA_W,
    inflation_rate=INFLATION,
    medical_enabled=true, health_mortality_corr=true,
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
