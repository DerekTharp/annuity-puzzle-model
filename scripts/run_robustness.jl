# Comprehensive Robustness and Sensitivity Analysis
#
# Addresses reviewer concerns:
#   1. Fine-grained gamma sweep (characterize bifurcation near 2.4-2.5)
#   2. Hazard multiplier variants (literature-anchored vs current)
#   3. Ownership threshold sensitivity (min_purchase=$0, $5K, $10K, $25K)
#   4. Grid convergence check (n_wealth=30, 60, 100)
#   5. Bequest specification comparison (DFJ luxury vs homothetic)
#   6. Joint gamma × inflation sensitivity
#   7. MWR sensitivity (Mitchell 1999 to Wettstein 2021)
#   8. Gauss-Hermite quadrature check
#   9. Survival pessimism sensitivity (psi sweep)
#
# Parallelism strategy: every sub-section that needs a full-model resolve is
# flattened into a SINGLE master spec list and dispatched via one parallel_solve
# call. Wall-clock time is therefore the longest single solve (~20-30 min for
# the full 10-channel model), not the sum of sub-section times. Each sub-section
# then filters the master results and renders its block of output in the format
# the manuscript expects.
#
# Section 3 (ownership threshold) does NOT re-solve — it builds a single full
# solution and re-evaluates ownership at different min_purchase thresholds.

using Printf
using DelimitedFiles
using Distributed

# Load module on all workers when running with -p N
if nworkers() > 1
    @everywhere include(joinpath(@__DIR__, "..", "src", "AnnuityPuzzle.jl"))
    @everywhere using .AnnuityPuzzle
else
    include(joinpath(@__DIR__, "..", "src", "AnnuityPuzzle.jl"))
    using .AnnuityPuzzle
end

include(joinpath(@__DIR__, "config.jl"))

const SS_LEVELS   = SS_QUARTILE_LEVELS  # [14K, 17K, 20K, 25K] by wealth quartile

println("=" ^ 70)
println("  ROBUSTNESS AND SENSITIVITY ANALYSIS")
println("=" ^ 70)

# ===================================================================
# Load data
# ===================================================================
println("\nLoading HRS population...")
hrs_path = HRS_PATH
hrs_raw = readdlm(hrs_path, ',', Any; skipstart=1)
n_pop = size(hrs_raw, 1)
population = zeros(n_pop, 4)
population[:, 1] = Float64.(hrs_raw[:, 1])
population[:, 2] .= 0.0                      # SS enters via ss_func, not A grid
population[:, 3] = Float64.(hrs_raw[:, 3])
if size(hrs_raw, 2) >= 4
    population[:, 4] = Float64.(hrs_raw[:, 4])  # observed health (1=Good, 2=Fair, 3=Poor)
else
    population[:, 4] .= 2.0
end

p_base = ModelParams(age_start=AGE_START, age_end=AGE_END)
base_surv = build_lockwood_survival(p_base)

ss_zero(age, p) = 0.0

# Common kwargs for run_full_model
base_kw = Dict{Symbol,Any}(
    :gamma => GAMMA, :beta => BETA, :r => R_RATE,
    :theta => THETA_DFJ, :kappa => KAPPA_DFJ,
    :c_floor => C_FLOOR,
    :mwr_loaded => MWR_LOADED,
    :fixed_cost_val => FIXED_COST,
    :min_purchase_val => MIN_PURCHASE,
    :lambda_w_val => LAMBDA_W,
    :inflation_val => INFLATION,
    :n_wealth => N_WEALTH, :n_annuity => N_ANNUITY, :n_alpha => N_ALPHA,
    :W_max => W_MAX, :n_quad => N_QUAD,
    :age_start => AGE_START, :age_end => AGE_END,
    :annuity_grid_power => A_GRID_POW,
    :hazard_mult => HAZARD_MULT,
    :survival_pessimism => SURVIVAL_PESSIMISM,
    :min_wealth => MIN_WEALTH,
    :ss_levels => SS_LEVELS,
    # All headline preference / behavioral channels must be in base_kw;
    # otherwise robustness sweeps evaluate a different model than the
    # production headline.
    :consumption_decline_val => CONSUMPTION_DECLINE,
    :health_utility_vals => Float64.(HEALTH_UTILITY),
    :psi_purchase_val => PSI_PURCHASE,
    :verbose => false,
)

@everywhere function run_full_model(base_surv_arg, population_arg, base_kw_arg; overrides...)
    kw = copy(base_kw_arg)
    theta_explicitly_set = false
    for (k, v) in overrides
        kw[k] = v
        k == :theta && (theta_explicitly_set = true)
    end
    # Use Lockwood's original DFJ theta at all gamma values
    if !theta_explicitly_set
        kw[:theta] = 56.96
    end
    result = run_decomposition(base_surv_arg, population_arg; kw...)
    return result.steps[end].ownership_rate
end

# Capture data in local variables for closure serialization
_bs, _pop, _bkw = base_surv, population, base_kw

# Collect all results for final table
all_results = Tuple{String,String,String}[]

# ===================================================================
# Build master spec list (every full-resolve sub-section)
# ===================================================================
# Each spec: (section::Symbol, label::String, params::Dict{Symbol,Any})
# Single parallel_solve dispatches all of them concurrently across workers,
# so wall-clock time = longest single solve, not sum of sub-section sums.

master_specs = NamedTuple{(:section, :label, :params), Tuple{Symbol, String, Dict{Symbol, Any}}}[]

# § 1. Gamma sweep
gamma_vals = [1.5, 2.0, 2.2, 2.3, 2.35, 2.4, 2.45, 2.5, 2.55, 2.6,
              2.7, 2.8, 3.0, 3.5, 4.0, 5.0]
for g in gamma_vals
    push!(master_specs, (section=:gamma,
                         label=@sprintf("gamma=%.2f", g),
                         params=Dict{Symbol,Any}(:gamma => g)))
end

# § 2. Hazard multiplier variants (constant) + age-banded variant
hazard_specs = [
    ("[0.45, 1.0, 3.5] (R-S functional, age 65-75)", [0.45, 1.0, 3.5]),
    ("[0.50, 1.0, 3.0] (baseline)",                  [0.50, 1.0, 3.0]),
    ("[0.57, 1.0, 2.7] (HRS SRH empirical)",         [0.57, 1.0, 2.7]),
    ("[0.60, 1.0, 2.0] (conservative SRH)",           [0.60, 1.0, 2.0]),
]
for (label, hm) in hazard_specs
    push!(master_specs, (section=:hazard,
                         label=label,
                         params=Dict{Symbol,Any}(:hazard_mult => hm)))
end
hm_by_age = [0.49 1.0 3.29;   # 65-74
             0.60 1.0 2.77;   # 75-84
             0.74 1.0 1.82]   # 85+
hm_midpoints = [70.0, 80.0, 90.0]
push!(master_specs, (section=:hazard_ageband,
                     label="Age-varying HRS (3 bands)",
                     params=Dict{Symbol,Any}(:hazard_mult_by_age => hm_by_age,
                                              :hazard_mult_age_midpoints => hm_midpoints)))

# § 4. Grid convergence
grid_specs = [
    (40, 15, "Coarse (40×15)"),
    (60, 20, "Medium (60×20)"),
    (80, 30, "Production (80×30) [baseline]"),
    (100, 40, "Fine (100×40)"),
]
for (nw, na, label) in grid_specs
    push!(master_specs, (section=:grid,
                         label=label,
                         params=Dict{Symbol,Any}(:n_wealth => nw, :n_annuity => na)))
end

# § 5. Bequest specifications
bequest_specs = [
    ("No bequests",                                              0.0,        0.0),
    ("Weak bequests (theta=2, kappa=\$10)",                      2.0,       10.0),
    ("Moderate bequests (theta=10, kappa=\$10)",                10.0,       10.0),
    ("DFJ luxury (theta=$(round(THETA_DFJ, digits=1)), kappa=\$272K)", THETA_DFJ, KAPPA_DFJ),
]
for (label, theta, kappa) in bequest_specs
    push!(master_specs, (section=:bequest,
                         label=label,
                         params=Dict{Symbol,Any}(:theta => theta, :kappa => kappa)))
end

# § 6. Joint gamma × inflation
gamma_set = [2.4, 2.5, 2.6, 3.0]
inflation_set = [0.01, 0.02, 0.03]
for g in gamma_set, pi in inflation_set
    push!(master_specs, (section=:gamma_inflation,
                         label=@sprintf("g=%.1f,pi=%.0f%%", g, pi * 100),
                         params=Dict{Symbol,Any}(:gamma => g, :inflation_val => pi)))
end

# § 7. MWR sweep
mwr_vals = [0.82, 0.85, 0.90, 0.95]
for m in mwr_vals
    push!(master_specs, (section=:mwr,
                         label=@sprintf("MWR=%.2f", m),
                         params=Dict{Symbol,Any}(:mwr_loaded => m)))
end

# § 8. Gauss-Hermite quadrature
for nq in [5, 7, 11]
    push!(master_specs, (section=:gh,
                         label=@sprintf("n_quad=%d", nq),
                         params=Dict{Symbol,Any}(:n_quad => nq)))
end

# § 9. Survival pessimism
psi_vals = [0.970, 0.981, 0.990, 1.000]
for psi in psi_vals
    push!(master_specs, (section=:pessimism,
                         label=@sprintf("psi=%.3f", psi),
                         params=Dict{Symbol,Any}(:survival_pessimism => psi)))
end

# ===================================================================
# Master parallel dispatch — all sections at once
# ===================================================================
n_specs = length(master_specs)
println("\n" * "=" ^ 70)
@printf("  Dispatching %d sensitivity solves across %d workers\n", n_specs, max(nworkers(), 1))
println("=" ^ 70)
flush(stdout)

t0_master = time()
master_results = parallel_solve(master_specs) do spec
    rate = run_full_model(_bs, _pop, _bkw; spec.params...)
    (section=spec.section, label=spec.label, rate=rate)
end
elapsed_master = time() - t0_master
@printf("  Completed all %d solves in %.0fs (%.1f min)\n",
        n_specs, elapsed_master, elapsed_master / 60)

# Helper: filter master_results by section, preserving order
function results_for(section::Symbol)
    return [r for r in master_results if r.section == section]
end

# ===================================================================
# § 1. Gamma sensitivity
# ===================================================================
println("\n" * "=" ^ 70)
println("  1. GAMMA SENSITIVITY (fine-grained sweep)")
println("     Characterizing structural transition near gamma=2.4-2.5")
println("=" ^ 70)
@printf("\n  %-10s  %12s\n", "gamma", "Ownership")
println("  " * "-" ^ 24)

for (idx, g) in enumerate(gamma_vals)
    gr = results_for(:gamma)[idx]
    @printf("  %-10.2f  %10.1f%%\n", g, gr.rate * 100)
    push!(all_results, ("Gamma sweep", @sprintf("gamma=%.2f", g),
                        @sprintf("%.1f%%", gr.rate * 100)))
end

# ===================================================================
# § 2. Hazard multiplier
# ===================================================================
println("\n" * "=" ^ 70)
println("  2. HAZARD MULTIPLIER SENSITIVITY")
println("     Empirically anchored: HRS SRH [0.57,1.0,2.7] vs R-S functional [0.45,1.0,3.5]")
println("=" ^ 70)
@printf("\n  %-45s  %12s\n", "Hazard multipliers", "Ownership")
println("  " * "-" ^ 59)

for hr in results_for(:hazard)
    @printf("  %-45s  %10.1f%%\n", hr.label, hr.rate * 100)
    push!(all_results, ("Hazard mult", hr.label, @sprintf("%.1f%%", hr.rate * 100)))
end

println("\n  Age-varying specification (HRS empirical by age band):")
ageband = results_for(:hazard_ageband)[1]
@printf("  %-45s  %10.1f%%\n", "Age-varying HRS (3 bands)", ageband.rate * 100)
push!(all_results, ("Hazard mult", "Age-varying HRS (3 bands)",
                    @sprintf("%.1f%%", ageband.rate * 100)))

# ===================================================================
# § 3. Ownership threshold sensitivity (separate code path — single solve,
#      multiple ownership thresholds; does NOT participate in master dispatch)
# ===================================================================
println("\n" * "=" ^ 70)
println("  3. OWNERSHIP THRESHOLD SENSITIVITY")
println("     Tests whether trivial purchases drive the ownership rate")
println("=" ^ 70)

min_purchase_vals = [0.0, 1_000.0, 5_000.0, 10_000.0, 25_000.0]

@printf("\n  %-30s  %12s\n", "Minimum purchase", "Ownership")
println("  " * "-" ^ 44)

# Need to solve with min_purchase parameter once
grid_kw = (n_wealth=N_WEALTH, n_annuity=N_ANNUITY, n_alpha=N_ALPHA,
           W_max=W_MAX, age_start=AGE_START, age_end=AGE_END,
           annuity_grid_power=A_GRID_POW)

common_kw = (gamma=GAMMA, beta=BETA, r=R_RATE,
             stochastic_health=true, n_health_states=3, n_quad=N_QUAD,
             c_floor=C_FLOOR, hazard_mult=HAZARD_MULT)

p_fair = ModelParams(; common_kw..., mwr=1.0, grid_kw...)
fair_pr = compute_payout_rate(p_fair, base_surv)
p_fair_nom = ModelParams(; common_kw..., mwr=1.0, inflation_rate=INFLATION, grid_kw...)
fair_pr_nom = compute_payout_rate(p_fair_nom, base_surv)
loaded_pr = MWR_LOADED * fair_pr_nom

grids = build_grids(p_fair, max(fair_pr, fair_pr_nom))

p_full = ModelParams(; common_kw...,
    theta=THETA_DFJ, kappa=KAPPA_DFJ,
    mwr=MWR_LOADED, fixed_cost=FIXED_COST, inflation_rate=INFLATION,
    medical_enabled=true, health_mortality_corr=true,
    survival_pessimism=SURVIVAL_PESSIMISM,
    min_purchase=0.0,
    grid_kw...)

pop_h = copy(population)
pop_h = pop_h[pop_h[:, 1] .>= MIN_WEALTH, :]
sol_full = solve_lifecycle_health(p_full, grids, base_surv, ss_zero)

for mp in min_purchase_vals
    p_eval = ModelParams(; common_kw...,
        theta=THETA_DFJ, kappa=KAPPA_DFJ,
        mwr=MWR_LOADED, fixed_cost=FIXED_COST, inflation_rate=INFLATION,
        medical_enabled=true, health_mortality_corr=true,
        min_purchase=mp,
        grid_kw...)
    rate = compute_ownership_rate_health(
        HealthSolution(sol_full.V, sol_full.c_policy, sol_full.grids, p_eval, base_surv),
        pop_h, loaded_pr; base_surv=base_surv).ownership_rate
    label = mp == 0.0 ? "\$0 (any purchase)" : @sprintf("\$%s", string(round(Int, mp)))
    @printf("  %-30s  %10.1f%%\n", label, rate * 100)
    push!(all_results, ("Min purchase", label, @sprintf("%.1f%%", rate * 100)))
end

# ===================================================================
# § 4. Grid convergence
# ===================================================================
println("\n" * "=" ^ 70)
println("  4. GRID CONVERGENCE")
println("     Verifying results are stable to grid refinement")
println("=" ^ 70)
@printf("\n  %-30s  %12s\n", "Grid (wealth×annuity)", "Ownership")
println("  " * "-" ^ 44)

for gres in results_for(:grid)
    @printf("  %-30s  %10.1f%%\n", gres.label, gres.rate * 100)
    push!(all_results, ("Grid convergence", gres.label,
                        @sprintf("%.1f%%", gres.rate * 100)))
end

# ===================================================================
# § 5. Bequest specifications
# ===================================================================
println("\n" * "=" ^ 70)
println("  5. BEQUEST SPECIFICATION COMPARISON")
println("     DFJ luxury good (kappa=272K) vs no bequests vs weak bequests")
println("=" ^ 70)
@printf("\n  %-40s  %12s\n", "Bequest specification", "Ownership")
println("  " * "-" ^ 54)

for br in results_for(:bequest)
    @printf("  %-40s  %10.1f%%\n", br.label, br.rate * 100)
    push!(all_results, ("Bequest spec", br.label,
                        @sprintf("%.1f%%", br.rate * 100)))
end

# ===================================================================
# § 6. Joint gamma × inflation
# ===================================================================
println("\n" * "=" ^ 70)
println("  6. JOINT GAMMA × INFLATION SENSITIVITY")
println("=" ^ 70)

# Map results back to grid for table-style printing
gi_lookup = Dict{String, Float64}()
for r in results_for(:gamma_inflation)
    gi_lookup[r.label] = r.rate
end

@printf("\n  %10s", "")
for pi in inflation_set
    @printf("  %10s", @sprintf("pi=%.0f%%", pi * 100))
end
println()
println("  " * "-" ^ (10 + 12 * length(inflation_set)))

for g in gamma_set
    @printf("  gamma=%.1f", g)
    for pi in inflation_set
        key = @sprintf("g=%.1f,pi=%.0f%%", g, pi * 100)
        rate = gi_lookup[key]
        @printf("  %9.1f%%", rate * 100)
        push!(all_results, ("Gamma×Inflation", key,
                            @sprintf("%.1f%%", rate * 100)))
    end
    println()
end

# ===================================================================
# § 7. MWR sweep
# ===================================================================
println("\n" * "=" ^ 70)
println("  7. MWR SENSITIVITY")
println("     Mitchell et al. (1999) to Wettstein et al. (2021)")
println("=" ^ 70)
@printf("\n  %-10s  %12s\n", "MWR", "Ownership")
println("  " * "-" ^ 24)

for (idx, m) in enumerate(mwr_vals)
    mr = results_for(:mwr)[idx]
    @printf("  %-10.2f  %10.1f%%\n", m, mr.rate * 100)
    push!(all_results, ("MWR sweep", @sprintf("MWR=%.2f", m),
                        @sprintf("%.1f%%", mr.rate * 100)))
end

# ===================================================================
# § 8. Gauss-Hermite quadrature
# ===================================================================
println("\n" * "=" ^ 70)
println("  8. GAUSS-HERMITE QUADRATURE CHECK (5 / 7 / 11 nodes)")
println("=" ^ 70)
# Note: only 3, 5, 7, 9, 11 nodes have weight tables in gauss_hermite_normal.
# Higher node counts (13, 15) require extending that table; deferred until
# referees ask for finer convergence than 11 demonstrates.

@printf("\n  %-15s  %12s\n", "Nodes", "Ownership")
println("  " * "-" ^ 29)

for (idx, nq) in enumerate([5, 7, 11])
    ghr = results_for(:gh)[idx]
    @printf("  %-15d  %10.1f%%\n", nq, ghr.rate * 100)
    push!(all_results, ("GH nodes", @sprintf("n_quad=%d", nq),
                        @sprintf("%.1f%%", ghr.rate * 100)))
end

# ===================================================================
# § 9. Survival pessimism
# ===================================================================
println("\n" * "=" ^ 70)
println("  9. SURVIVAL PESSIMISM SENSITIVITY")
println("     O'Dea & Sturrock (2023) calibration range")
println("=" ^ 70)
@printf("\n  %-10s  %12s\n", "psi", "Ownership")
println("  " * "-" ^ 24)

for (idx, psi) in enumerate(psi_vals)
    pr = results_for(:pessimism)[idx]
    @printf("  %-10.3f  %10.1f%%\n", psi, pr.rate * 100)
    push!(all_results, ("Survival pessimism", @sprintf("psi=%.3f", psi),
                        @sprintf("%.1f%%", pr.rate * 100)))
end

# ===================================================================
# Generate LaTeX tables
# ===================================================================
println("\n\nGenerating LaTeX tables...")

tables_dir = joinpath(@__DIR__, "..", "tables")
mkpath(joinpath(tables_dir, "tex"))
mkpath(joinpath(tables_dir, "csv"))

const ds = '\$'  # LaTeX math delimiter (avoids Julia string interpolation issues)

# --- Gamma × Inflation table ---
tex_path = joinpath(tables_dir, "tex", "robustness_gamma_inflation.tex")
open(tex_path, "w") do f
    println(f, raw"\begin{table}[htbp]")
    println(f, raw"\centering")
    println(f, raw"\caption{Predicted Ownership (\%) by Risk Aversion and Inflation Rate}")
    println(f, raw"\label{tab:robustness_gamma_inflation}")
    ncols = length(inflation_set) + 1
    println(f, raw"\begin{tabular}{l" * "c" ^ length(inflation_set) * "}")
    println(f, raw"\toprule")
    print(f, " ")
    for pi in inflation_set
        print(f, "& ", ds, raw"\pi = ", @sprintf("%.0f", pi * 100), raw"\%", ds, " ")
    end
    println(f, "\\\\")  # LaTeX `\\` line break — non-raw string for unambiguous escaping
    println(f, raw"\midrule")

    for g in gamma_set
        print(f, ds, raw"\gamma = ", @sprintf("%.1f", g), ds, " ")
        for pi in inflation_set
            key = @sprintf("g=%.1f,pi=%.0f%%", g, pi * 100)
            idx = findfirst(r -> r[1] == "Gamma×Inflation" && r[2] == key, all_results)
            if idx !== nothing
                val = replace(all_results[idx][3], "%" => "")
                print(f, "& ", val, " ")
            end
        end
        println(f, "\\\\")  # LaTeX `\\` line break — non-raw string for unambiguous escaping
    end

    println(f, raw"\bottomrule")
    println(f, raw"\end{tabular}")
    println(f, raw"\begin{tablenotes}")
    println(f, raw"\small")
    println(f, raw"\item Baseline: ", ds, raw"\gamma = 2.5", ds, ", ",
            ds, raw"\pi = 2\%", ds, ", DFJ bequests,")
    println(f, "MWR = 0.82, hazard multipliers [0.50, 1.0, 3.0].")
    println(f, raw"\end{tablenotes}")
    println(f, raw"\end{table}")
end
println("  $tex_path")

# --- Full robustness CSV ---
csv_path = joinpath(tables_dir, "csv", "robustness_full.csv")
open(csv_path, "w") do f
    println(f, "category,specification,ownership")
    for (cat, spec, rate) in all_results
        println(f, "$cat,$spec,$rate")
    end
end
println("  $csv_path")

println("\n" * "=" ^ 70)
println("  ROBUSTNESS ANALYSIS COMPLETE")
@printf("  Master parallel dispatch wall-clock: %.1f min over %d specs\n",
        elapsed_master / 60, n_specs)
println("=" ^ 70)
