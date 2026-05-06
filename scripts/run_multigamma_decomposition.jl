# Multi-gamma decomposition: run the full 8-step decomposition at
# gamma = 2.0, 2.5, 3.0 side-by-side. Shows which channels are
# gamma-sensitive and which are not.
#
# Output: tables/csv/multigamma_decomposition.csv
#         tables/tex/multigamma_decomposition.tex

using Printf, DelimitedFiles, Distributed

if nworkers() > 1
    @everywhere include(joinpath(@__DIR__, "..", "src", "AnnuityPuzzle.jl"))
    @everywhere using .AnnuityPuzzle
else
    include(joinpath(@__DIR__, "..", "src", "AnnuityPuzzle.jl"))
    using .AnnuityPuzzle
end

include(joinpath(@__DIR__, "config.jl"))

println("=" ^ 70); flush(stdout)
println("  MULTI-GAMMA DECOMPOSITION"); flush(stdout)
println("=" ^ 70); flush(stdout)

hrs_raw = readdlm(HRS_PATH,
                   ',', Any; skipstart=1)
assert_hrs_schema(hrs_raw, HRS_PATH)
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

p_base = ModelParams(age_start=AGE_START, age_end=AGE_END)
base_surv = build_lockwood_survival(p_base)
println("Data loaded ($n_pop obs)"); flush(stdout)

gammas = [2.0, 2.5, 3.0]
all_results = Dict{Float64, Any}()

for g in gammas
    println("\n--- gamma = $g ---"); flush(stdout)
    t0 = time()
    decomp = run_decomposition(
        base_surv, population;
        gamma=g, beta=BETA, r=R_RATE,
        theta=THETA_DFJ, kappa=KAPPA_DFJ,
        c_floor=C_FLOOR,
        mwr_loaded=MWR_LOADED,
        fixed_cost_val=FIXED_COST,
        min_purchase_val=MIN_PURCHASE,
        lambda_w_val=LAMBDA_W,
        # Preference + behavioral channels: passing the production values
        # so this multi-gamma table reflects the full ten-channel model
        # rather than the SDU-only legacy specification. Default kwargs
        # would silently leave consumption_decline, health_utility, and
        # psi_purchase off.
        consumption_decline_val=CONSUMPTION_DECLINE,
        health_utility_vals=HEALTH_UTILITY,
        psi_purchase_val=PSI_PURCHASE,
        inflation_val=INFLATION,
        n_wealth=N_WEALTH, n_annuity=N_ANNUITY, n_alpha=N_ALPHA,
        W_max=W_MAX, n_quad=N_QUAD,
        age_start=AGE_START, age_end=AGE_END,
        annuity_grid_power=A_GRID_POW,
        hazard_mult=HAZARD_MULT,
        survival_pessimism=SURVIVAL_PESSIMISM,
        min_wealth=MIN_WEALTH,
        ss_levels=SS_QUARTILE_LEVELS,
        verbose=true,
    )
    dt = time() - t0
    all_results[g] = decomp
    @printf("  gamma=%.1f complete in %.0f sec\n", g, dt); flush(stdout)
end

# Print side-by-side table
println("\n" * "=" ^ 70); flush(stdout)
println("  SIDE-BY-SIDE DECOMPOSITION"); flush(stdout)
println("=" ^ 70); flush(stdout)

step_names = [s.name for s in all_results[gammas[1]].steps]
n_steps = length(step_names)

# Header
@printf("\n  %-45s", "Channel")
for g in gammas
    @printf("  γ=%.1f  ", g)
end
println(); flush(stdout)
println("  " * "-" ^ (45 + length(gammas) * 10)); flush(stdout)

for i in 1:n_steps
    @printf("  %-45s", step_names[i])
    for g in gammas
        own = all_results[g].steps[i].ownership_rate * 100
        @printf("  %5.1f%%  ", own)
    end
    println(); flush(stdout)
end

# Retention rates
println("\n  Retention Rates:"); flush(stdout)
@printf("  %-45s", "Channel")
for g in gammas
    @printf("  γ=%.1f  ", g)
end
println(); flush(stdout)
println("  " * "-" ^ (45 + length(gammas) * 10)); flush(stdout)

for i in 2:n_steps
    @printf("  %-45s", step_names[i])
    for g in gammas
        prev = all_results[g].steps[i-1].ownership_rate
        curr = all_results[g].steps[i].ownership_rate
        ret = prev > 0.001 ? curr / prev * 100 : 0.0
        @printf("  %5.1f%%  ", ret)
    end
    println(); flush(stdout)
end

# Save CSV
tables_dir = joinpath(@__DIR__, "..", "tables", "csv")
mkpath(tables_dir)
csv_path = joinpath(tables_dir, "multigamma_decomposition.csv")
open(csv_path, "w") do f
    print(f, "step")
    for g in gammas
        @printf(f, ",own_gamma%.1f,alpha_gamma%.1f,ret_gamma%.1f", g, g, g)
    end
    println(f)
    for i in 1:n_steps
        print(f, step_names[i])
        for g in gammas
            own = all_results[g].steps[i].ownership_rate * 100
            alpha = all_results[g].steps[i].mean_alpha
            if i == 1
                ret = 0.0
            else
                prev = all_results[g].steps[i-1].ownership_rate
                ret = prev > 0.001 ? all_results[g].steps[i].ownership_rate / prev * 100 : 0.0
            end
            @printf(f, ",%.2f,%.4f,%.1f", own, alpha, ret)
        end
        println(f)
    end
end
println("\nCSV written: $csv_path"); flush(stdout)

# Save LaTeX table
tex_dir = joinpath(@__DIR__, "..", "tables", "tex")
mkpath(tex_dir)
tex_path = joinpath(tex_dir, "multigamma_decomposition.tex")
open(tex_path, "w") do f
    println(f, raw"\begin{table}[htbp]")
    println(f, raw"\centering")
    println(f, raw"\caption{Sequential Decomposition at Alternative Risk Aversion Values}")
    println(f, raw"\label{tab:multigamma}")
    println(f, raw"\begin{threeparttable}")
    # 3 gammas × 2 cols (own + ret) + step name = 7 cols
    println(f, raw"\begin{tabular}{l" * repeat("cc", length(gammas)) * "}")
    println(f, raw"\toprule")
    print(f, " ")
    for g in gammas
        @printf(f, " & \\multicolumn{2}{c}{\$\\gamma = %.1f\$}", g)
    end
    println(f, " \\\\")
    # Sub-header
    for _ in gammas
        print(f, " & Own.\\ (\\%) & Ret.\\ (\\%)")
    end
    println(f, " \\\\")
    println(f, raw"\midrule")
    for i in 1:n_steps
        print(f, step_names[i])
        for g in gammas
            own = all_results[g].steps[i].ownership_rate * 100
            if i == 1
                @printf(f, " & %.1f & ---", own)
            else
                prev = all_results[g].steps[i-1].ownership_rate
                ret = prev > 0.001 ? all_results[g].steps[i].ownership_rate / prev * 100 : 0.0
                @printf(f, " & %.1f & %.1f", own, ret)
            end
        end
        println(f, " \\\\")
    end
    println(f, raw"\bottomrule")
    println(f, raw"\end{tabular}")
    println(f, raw"\begin{tablenotes}")
    println(f, raw"\small")
    println(f, raw"\item Own.\ = predicted ownership rate (\%). Ret.\ = retention rate relative to previous step (\%).")
    @printf(f, "\\item All other parameters at production values (DFJ bequests, MWR \$= %.2f\$, \$\\pi = 2\\%%\$, \$\\psi = %.3f\$, \$\\lambda_W = %.3f\$, \$\\psi_{\\text{purchase}} = %.4f\$).\n",
            MWR_LOADED, SURVIVAL_PESSIMISM, LAMBDA_W, PSI_PURCHASE)
    println(f, raw"\end{tablenotes}")
    println(f, raw"\end{threeparttable}")
    println(f, raw"\end{table}")
end
println("LaTeX written: $tex_path"); flush(stdout)

println("\n" * "=" ^ 70); flush(stdout)
println("  MULTI-GAMMA DECOMPOSITION COMPLETE"); flush(stdout)
println("=" ^ 70); flush(stdout)
