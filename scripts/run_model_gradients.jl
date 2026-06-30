# Model-implied ownership gradients (diagnostic only).
#
# Reports model-side gradients for inspection. Not tied to any manuscript
# display item: model_gradients.csv is not parsed by a figure generator,
# table, or export_manuscript_numbers.jl. The empirical-validation exhibit
# (run_empirical_validation.jl) reports the data-side gradients independently.
#   - ownership by wealth bin (by-bin evaluation of the structural model)
#   - ownership by health state at evaluation (split of the same solve)
#   - channel on/off deltas read from subset_enumeration.csv (zero solves):
#     bequests, pessimism, Med+R-S, SS each toggled off from the full
#     9-channel structural mask 511
#
# One per-quartile solve of the 9-channel structural model (behavioral off);
# everything else is evaluation or lookup.
#
# Output: tables/csv/model_gradients.csv (diagnostic)
# Usage:  julia --project=. -p 4 scripts/run_model_gradients.jl
#         ANNUITY_COARSE=1 julia --project=. -p 4 scripts/run_model_gradients.jl

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

const COARSE = get(ENV, "ANNUITY_COARSE", "0") == "1"
const NW = COARSE ? 40 : N_WEALTH
const NA = COARSE ? 12 : N_ANNUITY
const NALPHA = COARSE ? 51 : N_ALPHA

println("=" ^ 70)
println("  MODEL-IMPLIED OWNERSHIP GRADIENTS (9-channel structural)")
println(COARSE ? "  [COARSE]" : "")
println("=" ^ 70)
flush(stdout)

# ===================================================================
# Population / survival / grids
# ===================================================================
hrs_raw = readdlm(HRS_PATH, ',', Any; skipstart=1)
has_health = assert_hrs_schema(hrs_raw, HRS_PATH)
n_pop = size(hrs_raw, 1)
population = zeros(n_pop, 4)
population[:, 1] = Float64.(hrs_raw[:, 1])
population[:, 2] .= 0.0
population[:, 3] = Float64.(hrs_raw[:, 3])
population[:, 4] = has_health ? Float64.(hrs_raw[:, 4]) : fill(2.0, n_pop)
if MIN_WEALTH > 0.0
    population = population[population[:, 1] .>= MIN_WEALTH, :]
end

p_surv = ModelParams(age_start=AGE_START, age_end=AGE_END)
base_surv = build_lockwood_survival(p_surv)
gkw = (n_wealth=NW, n_annuity=NA, n_alpha=NALPHA, W_max=W_MAX,
       age_start=AGE_START, age_end=AGE_END, annuity_grid_power=A_GRID_POW)
ckw = (gamma=GAMMA, beta=BETA, r=R_RATE, stochastic_health=true,
       n_health_states=3, n_quad=N_QUAD, c_floor=C_FLOOR,
       hazard_mult=Float64.(HAZARD_MULT))
p_fg = ModelParams(; ckw..., mwr=1.0, gkw...)
fair_pr = compute_payout_rate(p_fg, base_surv)
p_fn = ModelParams(; ckw..., mwr=1.0, inflation_rate=INFLATION, gkw...)
fair_pr_nom = INFLATION > 0 ? compute_payout_rate(p_fn, base_surv) : fair_pr
grids = build_grids(p_fg, max(fair_pr, fair_pr_nom))
loaded_pr_nom = MWR_LOADED * fair_pr_nom

cfg = build_subset_config(Set(1:9);
    theta_dfj=THETA_DFJ, kappa_dfj=KAPPA_DFJ, mwr_loaded=MWR_LOADED,
    fixed_cost=FIXED_COST, min_purchase=MIN_PURCHASE, inflation_val=INFLATION,
    survival_pessimism=SURVIVAL_PESSIMISM,
    ss_quartile_levels=Float64.(SS_QUARTILE_LEVELS),
    consumption_decline=CONSUMPTION_DECLINE,
    health_utility=Float64.(HEALTH_UTILITY),
    chi_ltc_val=CHI_LTC, lambda_w_val=1.0, psi_purchase_val=0.0,
    psi_purchase_c_ref_val=18_000.0)

p_model = ModelParams(; ckw...,
    theta=cfg.theta, kappa=cfg.kappa, mwr=cfg.mwr, fixed_cost=cfg.fixed_cost,
    min_purchase=cfg.min_purchase, inflation_rate=cfg.inflation_rate,
    medical_enabled=cfg.medical_enabled, health_mortality_corr=cfg.health_mortality_corr,
    survival_pessimism=cfg.survival_pessimism, consumption_decline=cfg.consumption_decline,
    health_utility=cfg.health_utility, chi_ltc=cfg.chi_ltc, lambda_w=cfg.lambda_w,
    psi_purchase=cfg.psi_purchase, psi_purchase_c_ref=cfg.psi_purchase_c_ref, gkw...)

# ===================================================================
# By-wealth and aggregate (one per-quartile solve)
# ===================================================================
println("\nSolving the full structural model...")
flush(stdout)
res = solve_and_evaluate(p_model, grids, base_surv, cfg.ss_levels,
    population, loaded_pr_nom; step_name="full structural", verbose=true)

# By-health: re-solve per quartile is unnecessary — evaluate health subgroups
# against per-quartile solutions is not exposed, so evaluate by health WITHIN
# the uniform-representative approach is inconsistent. Instead: by-health
# ownership from subgroup evaluation of the SAME per-quartile machinery, by
# filtering the population by health and re-running evaluation-only via
# solve_and_evaluate would re-solve. Pragmatic and exact: filter population by
# health and rerun (3 extra per-quartile solves at most when SS levels differ);
# the value functions do not depend on the population, so warm reuse is
# possible in principle, but the per-quartile branch hides the solutions. The
# solve cost is acceptable for a per-AWS-run stage.
rows = Tuple{String,String,Float64,Float64}[]  # gradient, cell, ownership_pct, mean_alpha
push!(rows, ("aggregate", "all", res.ownership * 100, res.mean_alpha))
labels_w = ["<30k", "30-120k", "120-350k", ">350k"]
for q in 1:4
    push!(rows, ("wealth_bin", labels_w[q], res.own_q[q] * 100, res.alpha_q[q]))
end

println("\nBy health state (subgroup re-evaluation)...")
flush(stdout)
labels_h = ["Good", "Fair", "Poor"]
for h in 1:3
    pop_h = population[population[:, 4] .== Float64(h), :]
    if size(pop_h, 1) == 0
        push!(rows, ("health", labels_h[h], NaN, NaN))
        continue
    end
    res_h = solve_and_evaluate(p_model, grids, base_surv, cfg.ss_levels,
        pop_h, loaded_pr_nom; step_name="health=$(labels_h[h])", verbose=true)
    push!(rows, ("health", labels_h[h], res_h.ownership * 100, res_h.mean_alpha))
end

# ===================================================================
# Channel on/off deltas from the enumeration lookup (zero solves)
# ===================================================================
enum_path = joinpath(@__DIR__, "..", "tables", "csv", "subset_enumeration.csv")
if isfile(enum_path)
    enum_rows, _ = readdlm(enum_path, ',', Any; header=true)
    lookup = Dict{Int,Float64}()
    for r in eachrow(enum_rows)
        lookup[Int(r[1])] = Float64(r[3])
    end
    full9 = 511
    # channel -> bit: SS=1, Bequests=2, Med+R-S=4 (bit value), Pessimism=8
    for (name, bit) in [("SS", 1), ("Bequests", 2), ("MedRS", 4), ("Pessimism", 8)]
        off_mask = full9 & ~bit
        if haskey(lookup, full9) && haskey(lookup, off_mask)
            push!(rows, ("channel_off_$(name)", "on",  lookup[full9], NaN))
            push!(rows, ("channel_off_$(name)", "off", lookup[off_mask], NaN))
        end
    end
else
    println("\n  subset_enumeration.csv not found — channel on/off deltas skipped")
end

# ===================================================================
# Report + save
# ===================================================================
println("\n  Model-implied gradients:")
@printf("  %-22s %-12s %10s %10s\n", "gradient", "cell", "own (%)", "mean_a")
println("  " * "-" ^ 58)
for (g, c, o, a) in rows
    @printf("  %-22s %-12s %10.2f %10.4f\n", g, c, o, a)
end

out_dir = joinpath(@__DIR__, "..", "tables", "csv"); mkpath(out_dir)
suffix = COARSE ? "_coarse" : ""
out_path = joinpath(out_dir, "model_gradients$(suffix).csv")
open(out_path, "w") do f
    println(f, "gradient,cell,ownership_pct,mean_alpha")
    for (g, c, o, a) in rows
        @printf(f, "%s,%s,%.4f,%.6f\n", g, c, o, a)
    end
end
println("\n  Saved: $out_path")
flush(stdout)
