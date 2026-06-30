# chi_LTC sensitivity sweep for the nine-channel structural model.
#
# Solves the full nine-channel structural specification (all rational +
# preference + structural-LTC channels active; SDU and PED off) at a range
# of chi_LTC values and reports predicted ownership. Diagnoses whether the
# structural baseline is knife-edge-sensitive to chi_LTC, and reports the
# baseline at the honest Ameriks-et-al-(2011) anchored value chi_LTC ~ 0.49.
#
# Behavioral channels held off: lambda_w = 1.0, psi_purchase = 0.0.
# Per-quartile Social Security solve, matching the production decomposition.
#
# Usage: julia --project=. -p 6 scripts/sweep_chi_ltc.jl

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

# chi_LTC values to sweep. 1.0 = channel off (reference); 0.49 = current
# production (Ameriks 2011 C_PC / C_f ratio); 0.70 = prior production value.
const CHI_LTC_GRID = [1.0, 0.85, 0.70, 0.60, 0.49, 0.40]

println("=" ^ 70)
println("  CHI_LTC SENSITIVITY SWEEP — nine-channel structural model")
println("=" ^ 70)
@printf("  Grid: %s\n", string(CHI_LTC_GRID))
@printf("  Behavioral channels OFF (lambda_w=1.0, psi_purchase=0.0)\n")
flush(stdout)

# ===================================================================
# Load HRS population
# ===================================================================
hrs_raw = readdlm(HRS_PATH, ',', Any; skipstart=1)
has_health = assert_hrs_schema(hrs_raw, HRS_PATH)
n_pop = size(hrs_raw, 1)
population = zeros(n_pop, 4)
population[:, 1] = Float64.(hrs_raw[:, 1])   # wealth
population[:, 2] .= 0.0                       # SS via ss_func, not A grid
population[:, 3] = Float64.(hrs_raw[:, 3])   # age
if has_health
    population[:, 4] = Float64.(hrs_raw[:, 4])
else
    population[:, 4] .= 2.0
end
@printf("  Loaded %d HRS individuals\n", n_pop)

# Apply the MIN_WEALTH analysis-sample filter that the production pipeline
# (run_subset_enumeration.jl, run_decomposition.jl) applies before
# evaluating ownership. Without it the sweep levels are not comparable to
# the production nine-channel baseline.
if MIN_WEALTH > 0.0
    mask = population[:, 1] .>= MIN_WEALTH
    population = population[mask, :]
    @printf("  After MIN_WEALTH >= \$%s filter: %d individuals\n",
            string(round(Int, MIN_WEALTH)), size(population, 1))
end
flush(stdout)

# ===================================================================
# Survival, payout rates, grids
# ===================================================================
p_base = ModelParams(age_start=AGE_START, age_end=AGE_END)
base_surv = build_lockwood_survival(p_base)

grid_kw = (n_wealth=N_WEALTH, n_annuity=N_ANNUITY, n_alpha=N_ALPHA,
           W_max=W_MAX, age_start=AGE_START, age_end=AGE_END,
           annuity_grid_power=A_GRID_POW)

p_fair = ModelParams(; gamma=GAMMA, beta=BETA, r=R_RATE, mwr=1.0, grid_kw...)
fair_pr = compute_payout_rate(p_fair, base_surv)

p_fair_nom = ModelParams(; gamma=GAMMA, beta=BETA, r=R_RATE, mwr=1.0,
                           inflation_rate=INFLATION, grid_kw...)
fair_pr_nom = INFLATION > 0 ? compute_payout_rate(p_fair_nom, base_surv) : fair_pr

common_kw = (gamma=GAMMA, beta=BETA, r=R_RATE,
             stochastic_health=true, n_health_states=3, n_quad=N_QUAD,
             c_floor=C_FLOOR, hazard_mult=Float64.(HAZARD_MULT))

# Grids built at the fair rate cover the full A range.
p_grid = ModelParams(; common_kw..., mwr=1.0, grid_kw...)
grids = build_grids(p_grid, max(fair_pr, fair_pr_nom))

# Nine-channel model has loads and inflation active, so the loaded nominal
# payout rate is the relevant pricing (matches run_subset_enumeration.jl).
loaded_pr_nom = MWR_LOADED * fair_pr_nom

ss_levels = Float64.(SS_QUARTILE_LEVELS)

# ===================================================================
# Sweep
# ===================================================================
@printf("\n  %-10s  %12s  %10s\n", "chi_LTC", "Ownership", "mean_alpha")
println("  " * "-" ^ 36)
flush(stdout)

results = NamedTuple{(:chi_ltc, :ownership, :mean_alpha), Tuple{Float64, Float64, Float64}}[]

for chi in CHI_LTC_GRID
    # Nine-channel structural specification (bitmask 511): all rational +
    # preference + structural-LTC channels active; behavioral channels off.
    p_model = ModelParams(; common_kw...,
        theta=THETA_DFJ, kappa=KAPPA_DFJ,
        mwr=MWR_LOADED, fixed_cost=FIXED_COST, min_purchase=MIN_PURCHASE,
        inflation_rate=INFLATION,
        medical_enabled=true, health_mortality_corr=true,
        survival_pessimism=SURVIVAL_PESSIMISM,
        consumption_decline=CONSUMPTION_DECLINE,
        health_utility=Float64.(HEALTH_UTILITY),
        chi_ltc=chi,
        lambda_w=1.0,
        psi_purchase=0.0,
        grid_kw...)

    res = solve_and_evaluate(p_model, grids, base_surv, ss_levels,
        population, loaded_pr_nom; step_name="", verbose=false)

    push!(results, (chi_ltc=chi, ownership=res.ownership, mean_alpha=res.mean_alpha))
    @printf("  %-10.2f  %11.2f%%  %10.4f\n", chi, res.ownership * 100, res.mean_alpha)
    flush(stdout)
end

# ===================================================================
# Summary
# ===================================================================
println("\n" * "=" ^ 70)
println("  SUMMARY")
println("=" ^ 70)

own_by_chi = Dict(r.chi_ltc => r.ownership for r in results)
if haskey(own_by_chi, 0.70) && haskey(own_by_chi, 0.49)
    @printf("  Prior value (chi_LTC=0.70):         %.2f%%\n", own_by_chi[0.70] * 100)
    @printf("  Production (chi_LTC=0.49):          %.2f%%\n", own_by_chi[0.49] * 100)
    @printf("  Recalibration shift:              %+.2f pp\n",
            (own_by_chi[0.49] - own_by_chi[0.70]) * 100)
end

# Knife-edge diagnostic: max absolute first difference across adjacent grid
# points, normalized by the chi_LTC step. Wrapped in a function so the
# accumulators have a proper local scope (Julia 1.10+ soft-scope rule).
sorted = sort(results, by=r -> r.chi_ltc)

function steepest_segment(pts)
    max_slope = 0.0
    max_seg = ""
    for i in 2:length(pts)
        d_own = abs(pts[i].ownership - pts[i-1].ownership) * 100
        d_chi = abs(pts[i].chi_ltc - pts[i-1].chi_ltc)
        slope = d_own / d_chi
        if slope > max_slope
            max_slope = slope
            max_seg = @sprintf("[%.2f, %.2f]", pts[i-1].chi_ltc, pts[i].chi_ltc)
        end
    end
    return max_slope, max_seg
end

max_slope, max_seg = steepest_segment(sorted)
@printf("\n  Steepest segment: %s at %.1f pp per unit chi_LTC\n", max_seg, max_slope)
println("  (A large value relative to the ownership level indicates")
println("   knife-edge sensitivity rather than smooth response.)")

# Save CSV
out_path = joinpath(@__DIR__, "..", "tables", "csv", "chi_ltc_sweep.csv")
open(out_path, "w") do f
    println(f, "chi_ltc,ownership_pct,mean_alpha")
    for r in sorted
        @printf(f, "%.4f,%.4f,%.6f\n", r.chi_ltc, r.ownership * 100, r.mean_alpha)
    end
end
println("\n  CSV saved: $out_path")
flush(stdout)
