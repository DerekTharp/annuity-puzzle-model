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
population[:, 2] = Float64.(hrs_raw[:, 2])
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

# Median permanent income in the HRS sample: ~$12,600/year (proxy for SS).
# Used as pre-existing annuity income floor for the CEV grid.
median_income = sort(population[:, 2])[div(n_pop, 2)]
@printf("  Median population income: \$%s (used as y_existing for grid)\n",
    string(round(Int, median_income)))

wealth_eval = [10_000.0, 25_000.0, 50_000.0, 100_000.0,
               200_000.0, 500_000.0, 1_000_000.0]

println("\n  Solving models for each bequest specification...")
cev_output = compute_cev_grid(
    base_surv, population;
    bequest_specs=bequest_specs,
    wealth_points=wealth_eval,
    y_existing=median_income,
    gamma=GAMMA, beta=BETA, r=R_RATE,
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
@printf("  Note: y_existing = \$%s (median SS income). alpha* under DFJ bequests.\n",
    string(round(Int, median_income)))

# ===================================================================
# Section 2: Population CEV Statistics
# ===================================================================
println("\n" * "=" ^ 70)
println("  SECTION 2: POPULATION-LEVEL CEV STATISTICS")
println("=" ^ 70)

@printf("\n  %-20s %10s %10s %10s %10s\n",
    "Bequest Spec", "Mean CEV", "Med CEV", "CEV>0", "CEV>1%")
println("  " * "-" ^ 62)

for pcev in cev_output.population_cev
    @printf("  %-20s %9.2f%% %9.2f%% %9.1f%% %9.1f%%\n",
        pcev.name,
        pcev.mean_cev * 100,
        pcev.median_cev * 100,
        pcev.frac_positive * 100,
        pcev.frac_above_1pct * 100)
end

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
    mwr=MWR_LOADED, fixed_cost=FIXED_COST,
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
        payout_rate=loaded_pr, y_existing=median_income,
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
