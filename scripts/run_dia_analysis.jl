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
assert_hrs_schema(hrs_raw, hrs_path)
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
            chi_ltc=CHI_LTC,
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
