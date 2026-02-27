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

# Convenience wrapper for serial calls (backward compatible)
function run_full_model(; overrides...)
    return run_full_model(base_surv, population, base_kw; overrides...)
end

# Collect all results for final table
all_results = Tuple{String,String,String}[]

# ===================================================================
# 1. Fine-grained gamma sweep (characterize bifurcation)
# ===================================================================
println("\n" * "=" ^ 70)
println("  1. GAMMA SENSITIVITY (fine-grained sweep)")
println("     Characterizing structural transition near gamma=2.4-2.5")
println("=" ^ 70)

gamma_vals = [1.5, 2.0, 2.2, 2.3, 2.35, 2.4, 2.45, 2.5, 2.55, 2.6,
              2.7, 2.8, 3.0, 3.5, 4.0, 5.0]
@printf("\n  %-10s  %12s\n", "gamma", "Ownership")
println("  " * "-" ^ 24)

t0_gamma = time()
# Capture data in local variables for closure serialization
_bs, _pop, _bkw = base_surv, population, base_kw
gamma_results = parallel_solve(gamma_vals) do g
    rate = run_full_model(_bs, _pop, _bkw; gamma=g)
    (gamma=g, rate=rate)
end

for gr in gamma_results
    @printf("  %-10.2f  %10.1f%%\n", gr.gamma, gr.rate * 100)
    push!(all_results, ("Gamma sweep", @sprintf("gamma=%.2f", gr.gamma),
                        @sprintf("%.1f%%", gr.rate * 100)))
end
@printf("  Total gamma sweep: %.0fs\n", time() - t0_gamma)

# ===================================================================
# 2. Hazard multiplier comparison
# ===================================================================
println("\n" * "=" ^ 70)
println("  2. HAZARD MULTIPLIER SENSITIVITY")
println("     Empirically anchored: HRS SRH [0.57,1.0,2.7] vs R-S functional [0.45,1.0,3.5]")
println("=" ^ 70)

hazard_specs = [
    ("[0.45, 1.0, 3.5] (R-S functional, age 65-75)", [0.45, 1.0, 3.5]),
    ("[0.50, 1.0, 3.0] (baseline)",                  [0.50, 1.0, 3.0]),
    ("[0.57, 1.0, 2.7] (HRS SRH empirical)",         [0.57, 1.0, 2.7]),
    ("[0.60, 1.0, 2.0] (conservative SRH)",           [0.60, 1.0, 2.0]),
]

@printf("\n  %-45s  %12s\n", "Hazard multipliers", "Ownership")
println("  " * "-" ^ 59)

t0_hazard = time()
hazard_results = parallel_solve(hazard_specs) do (label, hm)
    rate = run_full_model(_bs, _pop, _bkw; hazard_mult=hm)
    (label=label, rate=rate)
end

for hr in hazard_results
    @printf("  %-45s  %10.1f%%\n", hr.label, hr.rate * 100)
    push!(all_results, ("Hazard mult", hr.label, @sprintf("%.1f%%", hr.rate * 100)))
end
@printf("  Total hazard sweep: %.0fs\n", time() - t0_hazard)

# ===================================================================
# 3. Ownership threshold sensitivity (via min_purchase)
# ===================================================================
println("\n" * "=" ^ 70)
println("  3. OWNERSHIP THRESHOLD SENSITIVITY")
println("     Tests whether trivial purchases drive the ownership rate")
println("=" ^ 70)

min_purchase_vals = [0.0, 1_000.0, 5_000.0, 10_000.0, 25_000.0]

@printf("\n  %-30s  %12s\n", "Minimum purchase", "Ownership")
println("  " * "-" ^ 44)

# Need to solve with min_purchase parameter
grid_kw = (n_wealth=N_WEALTH, n_annuity=N_ANNUITY, n_alpha=N_ALPHA,
           W_max=W_MAX, age_start=AGE_START, age_end=AGE_END,
           annuity_grid_power=A_GRID_POW)

common_kw = (gamma=GAMMA, beta=BETA, r=R_RATE,
             stochastic_health=true, n_health_states=3, n_quad=N_QUAD,
             c_floor=C_FLOOR, hazard_mult=HAZARD_MULT)

p_fair = ModelParams(; common_kw..., mwr=1.0, grid_kw...)
fair_pr = compute_payout_rate(p_fair, base_surv)
# Nominal fair payout rate for inflation-active steps
p_fair_nom = ModelParams(; common_kw..., mwr=1.0, inflation_rate=INFLATION, grid_kw...)
fair_pr_nom = compute_payout_rate(p_fair_nom, base_surv)
grids = build_grids(p_fair, max(fair_pr, fair_pr_nom))
loaded_pr = MWR_LOADED * fair_pr
loaded_pr_nom = MWR_LOADED * fair_pr_nom

# Prepare population with health column
pop_h = copy(population)
mask = pop_h[:, 1] .>= MIN_WEALTH
pop_h = pop_h[mask, :]
if size(pop_h, 2) < 4
    pop_h = hcat(pop_h, fill(2.0, size(pop_h, 1)))
end

# Solve full model once (min_purchase doesn't affect solver, only alpha evaluation)
p_full = ModelParams(; common_kw...,
    theta=THETA_DFJ, kappa=KAPPA_DFJ,
    mwr=MWR_LOADED, fixed_cost=FIXED_COST, inflation_rate=INFLATION,
    medical_enabled=true, health_mortality_corr=true,
    min_purchase=0.0,
    grid_kw...)
sol_full = solve_lifecycle_health(p_full, grids, base_surv, ss_zero)

for mp in min_purchase_vals
    # Re-evaluate ownership with different min_purchase thresholds
    p_eval = ModelParams(; common_kw...,
        theta=THETA_DFJ, kappa=KAPPA_DFJ,
        mwr=MWR_LOADED, fixed_cost=FIXED_COST, inflation_rate=INFLATION,
        medical_enabled=true, health_mortality_corr=true,
        min_purchase=mp,
        grid_kw...)
    rate = compute_ownership_rate_health(
        HealthSolution(sol_full.V, sol_full.c_policy, sol_full.grids, p_eval),
        pop_h, loaded_pr; base_surv=base_surv).ownership_rate
    label = mp == 0.0 ? "\$0 (any purchase)" : @sprintf("\$%s", string(round(Int, mp)))
    @printf("  %-30s  %10.1f%%\n", label, rate * 100)
    push!(all_results, ("Min purchase", label, @sprintf("%.1f%%", rate * 100)))
end

# ===================================================================
# 4. Grid convergence check
# ===================================================================
println("\n" * "=" ^ 70)
println("  4. GRID CONVERGENCE")
println("     Verifying results are stable to grid refinement")
println("=" ^ 70)

grid_specs = [
    (40, 15, "Coarse (40×15)"),
    (60, 20, "Medium (60×20)"),
    (80, 30, "Production (80×30) [baseline]"),
    (100, 40, "Fine (100×40)"),
]

@printf("\n  %-30s  %12s\n", "Grid (wealth×annuity)", "Ownership")
println("  " * "-" ^ 44)

t0_grid = time()
grid_results = parallel_solve(grid_specs) do (nw, na, label)
    rate = run_full_model(_bs, _pop, _bkw; n_wealth=nw, n_annuity=na)
    (label=label, rate=rate)
end

for gres in grid_results
    @printf("  %-30s  %10.1f%%\n", gres.label, gres.rate * 100)
    push!(all_results, ("Grid convergence", gres.label, @sprintf("%.1f%%", gres.rate * 100)))
end
@printf("  Total grid sweep: %.0fs\n", time() - t0_grid)

# ===================================================================
# 5. Bequest specification comparison
# ===================================================================
println("\n" * "=" ^ 70)
println("  5. BEQUEST SPECIFICATION COMPARISON")
println("     DFJ luxury good (kappa=272K) vs no bequests vs weak bequests")
println("=" ^ 70)

# theta=56.96 was calibrated jointly with kappa=272K (DFJ luxury good).
# Using theta=56.96 with kappa=10 is INVALID: it creates a near-zero penalty
# that makes the bequest motive act as a precautionary buffer rather than a
# real bequest channel, paradoxically increasing annuity demand.
# Lockwood (2012, BAP_wtp.m) calibrates theta separately for each kappa.
bequest_specs = [
    ("No bequests",              0.0,       0.0),
    ("Weak bequests (theta=2, kappa=\$10)", 2.0, 10.0),
    ("Moderate bequests (theta=10, kappa=\$10)", 10.0, 10.0),
    ("DFJ luxury (theta=$(round(THETA_DFJ, digits=1)), kappa=\$272K)", THETA_DFJ, KAPPA_DFJ),
]

@printf("\n  %-40s  %12s\n", "Bequest specification", "Ownership")
println("  " * "-" ^ 54)

t0_bequest = time()
bequest_results = parallel_solve(bequest_specs) do (label, theta, kappa)
    rate = run_full_model(_bs, _pop, _bkw; theta=theta, kappa=kappa)
    (label=label, rate=rate)
end

for br in bequest_results
    @printf("  %-40s  %10.1f%%\n", br.label, br.rate * 100)
    push!(all_results, ("Bequest spec", br.label, @sprintf("%.1f%%", br.rate * 100)))
end
@printf("  Total bequest sweep: %.0fs\n", time() - t0_bequest)

# ===================================================================
# 6. Joint gamma × inflation sensitivity (3×3 table)
# ===================================================================
println("\n" * "=" ^ 70)
println("  6. JOINT GAMMA × INFLATION SENSITIVITY")
println("=" ^ 70)

gamma_set = [2.4, 2.5, 2.6, 3.0]
inflation_set = [0.01, 0.02, 0.03]

# Build all (gamma, inflation) pairs for parallel evaluation
gi_pairs = [(g, pi) for g in gamma_set for pi in inflation_set]

t0_joint = time()
gi_results = parallel_solve(gi_pairs) do (g, pi)
    rate = run_full_model(_bs, _pop, _bkw; gamma=g, inflation_val=pi)
    (gamma=g, inflation=pi, rate=rate)
end

# Display as grid
gi_lookup = Dict((r.gamma, r.inflation) => r.rate for r in gi_results)

@printf("\n  %10s", "")
for pi in inflation_set
    @printf("  %10s", @sprintf("pi=%.0f%%", pi * 100))
end
println()
println("  " * "-" ^ (10 + 12 * length(inflation_set)))

for g in gamma_set
    @printf("  gamma=%.1f", g)
    for pi in inflation_set
        rate = gi_lookup[(g, pi)]
        @printf("  %9.1f%%", rate * 100)
        push!(all_results, ("Gamma×Inflation",
            @sprintf("g=%.1f,pi=%.0f%%", g, pi * 100),
            @sprintf("%.1f%%", rate * 100)))
    end
    println()
end
@printf("  Total joint sweep: %.0fs\n", time() - t0_joint)

# ===================================================================
# 7. MWR sensitivity sweep (Mitchell 1999 to Wettstein 2021)
# ===================================================================
println("\n" * "=" ^ 70)
println("  7. MWR SENSITIVITY")
println("     Mitchell et al. (1999) to Wettstein et al. (2021)")
println("=" ^ 70)

mwr_vals = [0.82, 0.85, 0.90, 0.95]
@printf("\n  %-10s  %12s\n", "MWR", "Ownership")
println("  " * "-" ^ 24)

t0_mwr = time()
mwr_results = parallel_solve(mwr_vals) do m
    rate = run_full_model(_bs, _pop, _bkw; mwr_loaded=m)
    (mwr=m, rate=rate)
end

for mr in mwr_results
    @printf("  %-10.2f  %10.1f%%\n", mr.mwr, mr.rate * 100)
    push!(all_results, ("MWR sweep", @sprintf("MWR=%.2f", mr.mwr),
                        @sprintf("%.1f%%", mr.rate * 100)))
end
@printf("  Total MWR sweep: %.0fs\n", time() - t0_mwr)

# ===================================================================
# 8. Gauss-Hermite quadrature check (5 vs 7 nodes)
# ===================================================================
println("\n" * "=" ^ 70)
println("  8. GAUSS-HERMITE QUADRATURE CHECK (5 vs 7 nodes)")
println("=" ^ 70)

@printf("\n  %-15s  %12s\n", "Nodes", "Ownership")
println("  " * "-" ^ 29)

t0_gh = time()
gh_results = parallel_solve([5, 7]) do nq
    rate = run_full_model(_bs, _pop, _bkw; n_quad=nq)
    (n_quad=nq, rate=rate)
end

for ghr in gh_results
    @printf("  %-15d  %10.1f%%\n", ghr.n_quad, ghr.rate * 100)
    push!(all_results, ("GH nodes", @sprintf("n_quad=%d", ghr.n_quad),
                        @sprintf("%.1f%%", ghr.rate * 100)))
end
@printf("  Total GH check: %.0fs\n", time() - t0_gh)

# ===================================================================
# 9. Survival pessimism sensitivity
# ===================================================================
println("\n" * "=" ^ 70)
println("  9. SURVIVAL PESSIMISM SENSITIVITY")
println("     O'Dea & Sturrock (2023) calibration range")
println("=" ^ 70)

psi_vals = [0.970, 0.981, 0.990, 1.000]
@printf("\n  %-10s  %12s\n", "psi", "Ownership")
println("  " * "-" ^ 24)

t0_psi = time()
psi_results = parallel_solve(psi_vals) do psi
    rate = run_full_model(_bs, _pop, _bkw; survival_pessimism=psi)
    (psi=psi, rate=rate)
end

for pr in psi_results
    @printf("  %-10.3f  %10.1f%%\n", pr.psi, pr.rate * 100)
    push!(all_results, ("Survival pessimism", @sprintf("psi=%.3f", pr.psi),
                        @sprintf("%.1f%%", pr.rate * 100)))
end
@printf("  Total psi sweep: %.0fs\n", time() - t0_psi)

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
    println(f, raw"\\\\")
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
        println(f, raw"\\\\")
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
println("=" ^ 70)
