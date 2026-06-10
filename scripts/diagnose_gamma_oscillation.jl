# Gamma-oscillation diagnostic (the kill-criterion).
#
# The full structural model's predicted ownership jumps across gamma (e.g.
# 0.0 / 6.7 / 25.4% at gamma = 2.0 / 2.5 / 3.0 on the production grid). This
# script sweeps gamma at fine resolution and records, at each point:
#   - ownership (discontinuous extensive-margin indicator)
#   - mean alpha (continuous intensive-margin statistic)
#   - frac_at_kink (share of owners pinned at the $10k minimum-purchase floor)
#
# Interpretation:
#   * If mean_alpha moves SMOOTHLY while ownership jumps, the jumps are a
#     discretization/threshold effect on the indicator, not a real instability.
#   * If the jumps coincide with a HIGH frac_at_kink, they are a genuine
#     minimum-purchase participation-fragility effect (a defensible
#     insurance-market finding, not a solver artifact).
#   * If mean_alpha itself oscillates at a fine grid with LOW frac_at_kink and no
#     kink mechanism, the model is under-resolved -> pivot to a methods note.
#
# Grid is env-overridable so the same script runs the (101,80), (201,160), and
# (401,160) checks the JRI plan calls for:
#   ANNUITY_NW=201 ANNUITY_NALPHA=160 julia --project=. -p 8 scripts/diagnose_gamma_oscillation.jl
#   ANNUITY_COARSE=1 julia --project=. -p 8 scripts/diagnose_gamma_oscillation.jl  (local check)

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
const NW = parse(Int, get(ENV, "ANNUITY_NW", string(COARSE ? 40 : N_WEALTH)))
const NA = parse(Int, get(ENV, "ANNUITY_NA", string(COARSE ? 12 : N_ANNUITY)))
const NALPHA = parse(Int, get(ENV, "ANNUITY_NALPHA", string(COARSE ? 51 : N_ALPHA)))
const GAMMA_GRID = COARSE ? [2.0, 2.5, 3.0] : collect(2.0:0.05:3.0)

println("=" ^ 70)
println("  GAMMA-OSCILLATION DIAGNOSTIC (full 9-channel structural model)")
@printf("  grid (NW,NA,Nalpha) = (%d,%d,%d) ; %d gamma points%s\n",
        NW, NA, NALPHA, length(GAMMA_GRID), COARSE ? "  [COARSE]" : "")
println("=" ^ 70)
flush(stdout)

# ===================================================================
# Population
# ===================================================================
hrs_raw = readdlm(HRS_PATH, ',', Any; skipstart=1)
assert_hrs_schema(hrs_raw, HRS_PATH)
n_pop = size(hrs_raw, 1)
population = zeros(n_pop, 4)
population[:, 1] = Float64.(hrs_raw[:, 1])
population[:, 2] .= 0.0
population[:, 3] = Float64.(hrs_raw[:, 3])
population[:, 4] = size(hrs_raw, 2) >= 4 ? Float64.(hrs_raw[:, 4]) : fill(2.0, n_pop)
if MIN_WEALTH > 0.0
    population = population[population[:, 1] .>= MIN_WEALTH, :]
end

# ===================================================================
# Survival / payout / grids (gamma-independent: computed once)
# ===================================================================
p_surv = ModelParams(age_start=AGE_START, age_end=AGE_END)
base_surv = build_lockwood_survival(p_surv)

gkw = (n_wealth=NW, n_annuity=NA, n_alpha=NALPHA, W_max=W_MAX,
       age_start=AGE_START, age_end=AGE_END, annuity_grid_power=A_GRID_POW)
ckw_ref = (gamma=2.5, beta=BETA, r=R_RATE, stochastic_health=true,
           n_health_states=3, n_quad=N_QUAD, c_floor=C_FLOOR,
           hazard_mult=Float64.(HAZARD_MULT))
p_fg = ModelParams(; ckw_ref..., mwr=1.0, gkw...)
fair_pr = compute_payout_rate(p_fg, base_surv)
p_fn = ModelParams(; ckw_ref..., mwr=1.0, inflation_rate=INFLATION, gkw...)
fair_pr_nom = INFLATION > 0 ? compute_payout_rate(p_fn, base_surv) : fair_pr
grids = build_grids(p_fg, max(fair_pr, fair_pr_nom))
loaded_pr_nom = MWR_LOADED * fair_pr_nom

# Full 9-channel structural configuration (behavioral off).
cfg = build_subset_config(Set(1:9);
    theta_dfj=THETA_DFJ, kappa_dfj=KAPPA_DFJ, mwr_loaded=MWR_LOADED,
    fixed_cost=FIXED_COST, min_purchase=MIN_PURCHASE, inflation_val=INFLATION,
    survival_pessimism=SURVIVAL_PESSIMISM, ss_quartile_levels=Float64.(SS_QUARTILE_LEVELS),
    consumption_decline=CONSUMPTION_DECLINE, health_utility=Float64.(HEALTH_UTILITY),
    chi_ltc_val=CHI_LTC, lambda_w_val=1.0, psi_purchase_val=0.0,
    psi_purchase_c_ref_val=18_000.0)

# ===================================================================
# Sweep gamma (serial outer loop; quartile solves parallelize inside)
# ===================================================================
rows = Tuple{Float64,Float64,Float64,Float64,Float64}[]  # gamma, ownership_pct, mean_alpha, kink_contract, grid_floor
for gamma in GAMMA_GRID
    t0 = time()
    ckw = (gamma=gamma, beta=BETA, r=R_RATE, stochastic_health=true,
           n_health_states=3, n_quad=N_QUAD, c_floor=C_FLOOR,
           hazard_mult=Float64.(HAZARD_MULT))
    p_model = ModelParams(; ckw...,
        theta=cfg.theta, kappa=cfg.kappa, mwr=cfg.mwr, fixed_cost=cfg.fixed_cost,
        min_purchase=cfg.min_purchase, inflation_rate=cfg.inflation_rate,
        medical_enabled=cfg.medical_enabled, health_mortality_corr=cfg.health_mortality_corr,
        survival_pessimism=cfg.survival_pessimism, consumption_decline=cfg.consumption_decline,
        health_utility=cfg.health_utility, chi_ltc=cfg.chi_ltc, lambda_w=cfg.lambda_w,
        psi_purchase=cfg.psi_purchase, psi_purchase_c_ref=cfg.psi_purchase_c_ref, gkw...)
    res = solve_and_evaluate(p_model, grids, base_surv, cfg.ss_levels,
        population, loaded_pr_nom; step_name="", verbose=false)
    push!(rows, (gamma, res.ownership * 100, res.mean_alpha,
                 res.frac_at_kink_contract, res.frac_at_grid_floor))
    @printf("  gamma=%.2f  ownership=%6.2f%%  mean_alpha=%.4f  kink_contract=%.3f  grid_floor=%.3f  (%.0fs)\n",
            gamma, res.ownership * 100, res.mean_alpha,
            res.frac_at_kink_contract, res.frac_at_grid_floor, time() - t0)
    flush(stdout)
end

# ===================================================================
# Assess: smoothness of mean_alpha + kink coincidence
# ===================================================================
alphas = [r[3] for r in rows]
owns = [r[2] for r in rows]
kink_contract = [r[4] for r in rows]
grid_floor = [r[5] for r in rows]

# Count sign changes in the first difference of mean_alpha (a monotone series
# has zero). The ownership indicator may jump; the question is whether the
# continuous intensive margin also oscillates.
dalpha = diff(alphas)
sign_changes = 0
for i in 2:length(dalpha)
    if dalpha[i] != 0 && dalpha[i-1] != 0 && sign(dalpha[i]) != sign(dalpha[i-1])
        global sign_changes += 1
    end
end
own_range = maximum(owns) - minimum(owns)
max_contract = maximum(kink_contract)
max_grid_floor = maximum(grid_floor)

println("\n" * "=" ^ 70)
println("  ASSESSMENT")
println("=" ^ 70)
@printf("  Ownership range across gamma: %.1f pp (min %.1f%%, max %.1f%%)\n",
        own_range, minimum(owns), maximum(owns))
@printf("  mean_alpha monotonicity: %d sign change(s) in the first difference\n", sign_changes)
@printf("  max frac_at_kink_contract across gamma: %.3f\n", max_contract)
@printf("  max frac_at_grid_floor across gamma:    %.3f\n", max_grid_floor)
if sign_changes == 0
    println("  -> mean_alpha is monotone in gamma; any ownership jump is an")
    println("     extensive-margin indicator/threshold effect, not instability.")
elseif max_contract >= 0.25
    println("  -> mean_alpha oscillates AND owners pile up at the contractual")
    println("     \$10k minimum: consistent with minimum-purchase participation")
    println("     fragility (a substantive insurance-market finding).")
elseif max_grid_floor >= 0.25
    println("  -> mean_alpha oscillates AND owners pile up at the ALPHA-GRID")
    println("     floor (not the contract): the alpha grid is under-resolved.")
    println("     Re-run with finer ANNUITY_NALPHA before drawing conclusions.")
else
    println("  -> mean_alpha oscillates with no kink mechanism at this grid:")
    println("     re-run finer (ANNUITY_NW/ANNUITY_NALPHA); if it persists,")
    println("     the ranking-only paper pivots to a methods note.")
end

# ===================================================================
# Save CSV
# ===================================================================
out_dir = joinpath(@__DIR__, "..", "tables", "csv"); mkpath(out_dir)
# Tag the output with the grid so multi-resolution diagnosis runs (the
# (101,80)/(201,160)/(401,160) sequence) accumulate instead of overwriting.
csv_path = joinpath(out_dir, "gamma_oscillation_diagnostic_$(NW)x$(NALPHA).csv")
open(csv_path, "w") do f
    println(f, "gamma,ownership_pct,mean_alpha,frac_at_kink_contract,frac_at_grid_floor,n_wealth,n_alpha")
    for (g, o, a, kc, gf) in rows
        @printf(f, "%.3f,%.4f,%.6f,%.4f,%.4f,%d,%d\n", g, o, a, kc, gf, NW, NALPHA)
    end
end
println("\n  CSV saved: $csv_path")
flush(stdout)
