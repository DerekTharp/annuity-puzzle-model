# STAGE -1 DE-RISK DRY RUN — behavioral moderators of the SS crowd-out slope.
#
# Tests the single most consequential prediction of the option-2 (SS-spine)
# framing: do the behavioral channels MODERATE the crowd-out response in the
# predicted directions?
#   - SDU (source-dependent utility, lambda_w < 1): predicted to AMPLIFY the
#     crowd-out slope (SS income and annuity income share the high-weight
#     "income" bucket, so public->private substitution is stronger).
#   - PED (purchase-event disutility, psi_purchase > 0): predicted to DAMPEN
#     the slope (the at-purchase friction bites at the buy margin an SS cut
#     pushes households toward).
#
# Central exhibit (eventual Fig 2): SS-cut sweep x {none, SDU, PED, both}.
# This dry run uses a COARSE grid and MILDER behavioral values than the
# (saturating) production exploratory values, to check the SIGN of the
# moderation before any AWS spend or manuscript work. If the signs do not
# come out cleanly, the behavioral channels demote to a robustness note and
# the SS-spine still stands (crowd-out curve + 2033 result + Shapley mechanism
# do not depend on the moderator signs).
#
# Bug avoided: run_ss_robustness.jl omits chi_ltc/lambda_w/psi_purchase from
# its p_model constructor (runs with chi_ltc=1.0, LTC off). This script passes
# all behavioral/structural fields explicitly.
#
# Usage: julia --project=. -p 6 scripts/run_ss_crowdout_moderation.jl

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

@everywhere include(joinpath(@__DIR__, "config.jl"))  # config constants are referenced inside the parallel_solve closure, so workers need them

# --- Dry-run settings ---------------------------------------------------------
const CUTS = [0.0, 0.10, 0.23, 0.30, 0.50]   # fractions; 0.23 = 2033 trust-fund
# Milder behavioral values than production (production psi=0.05 saturates to 0%,
# lambda_w=0.625 lifts baseline to ~51%). These are chosen to reveal the
# DIRECTION of moderation without saturating/dominating.
const LAMBDA_W_MILD   = 0.85
const PSI_PURCHASE_MILD = 0.01
const CHI_LTC_VAL     = 0.49                  # corrected Ameriks-2011 value

# Coarse grid for speed (dry run; relative slopes across configs are what matter).
const NW_C     = 40
const NA_C     = 15
const NALPHA_C = 51

# Behavioral configs: (label, lambda_w, psi_purchase)
const CONFIGS = [
    ("none", 1.0,            0.0),
    ("SDU",  LAMBDA_W_MILD,  0.0),
    ("PED",  1.0,            PSI_PURCHASE_MILD),
    ("both", LAMBDA_W_MILD,  PSI_PURCHASE_MILD),
]

println("=" ^ 70)
println("  STAGE -1 DRY RUN — SS crowd-out x behavioral moderators")
println("=" ^ 70)
@printf("  Cuts: %s\n", string(Int.(round.(CUTS .* 100))))
@printf("  Configs: none / SDU(lambda_w=%.2f) / PED(psi=%.3f) / both\n",
        LAMBDA_W_MILD, PSI_PURCHASE_MILD)
@printf("  chi_LTC=%.2f ; coarse grid %dx%dx%d\n", CHI_LTC_VAL, NW_C, NA_C, NALPHA_C)
flush(stdout)

# --- Load HRS population ------------------------------------------------------
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
@printf("  Population (wealth>=\$%s): %d\n", string(round(Int, MIN_WEALTH)), size(population, 1))
flush(stdout)

# --- Survival, payout, grids --------------------------------------------------
p_base = ModelParams(age_start=AGE_START, age_end=AGE_END)
base_surv = build_lockwood_survival(p_base)

gkw = (n_wealth=NW_C, n_annuity=NA_C, n_alpha=NALPHA_C,
       W_max=W_MAX, age_start=AGE_START, age_end=AGE_END, annuity_grid_power=A_GRID_POW)
ckw = (gamma=GAMMA, beta=BETA, r=R_RATE,
       stochastic_health=true, n_health_states=3, n_quad=N_QUAD,
       c_floor=C_FLOOR, hazard_mult=Float64.(HAZARD_MULT))

p_fg = ModelParams(; ckw..., mwr=1.0, gkw...)
fair_pr = compute_payout_rate(p_fg, base_surv)
p_fn = ModelParams(; ckw..., mwr=1.0, inflation_rate=INFLATION, gkw...)
fair_pr_nom = INFLATION > 0 ? compute_payout_rate(p_fn, base_surv) : fair_pr
grids = build_grids(p_fg, max(fair_pr, fair_pr_nom))
loaded_pr_nom = MWR_LOADED * fair_pr_nom
# A trust-fund shortfall cuts Social Security only; DB pension income survives.
# SS_QUARTILE_LEVELS = SS_OBS + DB_OBS, so scale SS_OBS by the cut and add DB_OBS
# back untouched (matching run_ss_robustness.jl / run_welfare_counterfactuals.jl).
ss_obs = Float64.(SS_OBS)
db_obs = Float64.(DB_OBS)

# --- Sweep: config x cut ------------------------------------------------------
specs = [(ci=ci, cut=cut) for ci in 1:length(CONFIGS) for cut in CUTS]

results = parallel_solve(specs) do spec
    (label, lam, psi) = CONFIGS[spec.ci]
    ss_lvls = (1.0 - spec.cut) .* ss_obs .+ db_obs
    p_model = ModelParams(; ckw...,
        theta=THETA_DFJ, kappa=KAPPA_DFJ,
        mwr=MWR_LOADED, fixed_cost=FIXED_COST, min_purchase=MIN_PURCHASE,
        inflation_rate=INFLATION,
        medical_enabled=true, health_mortality_corr=true,
        survival_pessimism=SURVIVAL_PESSIMISM,
        consumption_decline=CONSUMPTION_DECLINE,
        health_utility=Float64.(HEALTH_UTILITY),
        chi_ltc=CHI_LTC_VAL,
        lambda_w=lam, psi_purchase=psi, psi_purchase_c_ref=PSI_PURCHASE_C_REF,
        gkw...)
    res = solve_and_evaluate(p_model, grids, base_surv, ss_lvls,
        population, loaded_pr_nom; step_name="", verbose=false)
    (label=label, cut=spec.cut, ownership=res.ownership, mean_alpha=res.mean_alpha)
end

# --- Tabulate -----------------------------------------------------------------
own = Dict{Tuple{String,Float64}, Float64}()
alp = Dict{Tuple{String,Float64}, Float64}()
for r in results
    own[(r.label, r.cut)] = r.ownership
    alp[(r.label, r.cut)] = r.mean_alpha
end

println("\n  Ownership (%) by config x cut:")
@printf("  %-6s", "config")
for c in CUTS; @printf("  %6s", string(Int(round(c*100)))*"%"); end
println()
println("  " * "-"^(6 + 8*length(CUTS)))
for (label, _, _) in CONFIGS
    @printf("  %-6s", label)
    for c in CUTS; @printf("  %5.1f ", own[(label,c)]*100); end
    println()
end

println("\n  Mean alpha by config x cut:")
@printf("  %-6s", "config")
for c in CUTS; @printf("  %6s", string(Int(round(c*100)))*"%"); end
println()
println("  " * "-"^(6 + 8*length(CUTS)))
for (label, _, _) in CONFIGS
    @printf("  %-6s", label)
    for c in CUTS; @printf("  %5.3f ", alp[(label,c)]); end
    println()
end

# --- Sign check ---------------------------------------------------------------
# Substitution-region slope = (ownership at 23% cut - at 0% cut) / 23, per config.
slope(label) = (own[(label,0.23)] - own[(label,0.0)]) / 23.0 * 100  # pp per pp-cut
sl_none = slope("none"); sl_sdu = slope("SDU"); sl_ped = slope("PED"); sl_both = slope("both")
# mean-alpha slope as continuous backup (extensive-margin indicator can saturate)
aslope(label) = (alp[(label,0.23)] - alp[(label,0.0)]) / 23.0
asl_none = aslope("none"); asl_sdu = aslope("SDU"); asl_ped = aslope("PED")

println("\n" * "=" ^ 70)
println("  SIGN CHECK — substitution-region slope (0% -> 23% cut)")
println("=" ^ 70)
@printf("  ownership slope (pp per pp-cut):  none=%.3f  SDU=%.3f  PED=%.3f  both=%.3f\n",
        sl_none, sl_sdu, sl_ped, sl_both)
@printf("  mean-alpha slope (backup):        none=%.5f  SDU=%.5f  PED=%.5f\n",
        asl_none, asl_sdu, asl_ped)
sdu_amplifies = sl_sdu > sl_none
ped_dampens   = sl_ped < sl_none
@printf("\n  PREDICTION: SDU amplifies (slope_SDU > slope_none): %s\n",
        sdu_amplifies ? "PASS" : "FAIL")
@printf("  PREDICTION: PED dampens   (slope_PED < slope_none): %s\n",
        ped_dampens ? "PASS" : "FAIL")
# Saturation flags
base_sat = own[("PED",0.0)] < 0.005 && own[("PED",0.23)] < 0.005
sdu_ceil = own[("SDU",0.0)] > 0.90
base_sat && println("  WARNING: PED config saturates near 0% — slope undefined; need milder psi or use mean-alpha.")
sdu_ceil && println("  WARNING: SDU config near ceiling — slope may be clipped; check mean-alpha slope sign.")

println("\n  VERDICT: ",
    (sdu_amplifies && ped_dampens && !base_sat && !sdu_ceil) ?
    "CLEAN — moderators behave as predicted; behavioral-as-headline viable." :
    "NOT CLEAN — demote behavioral to robustness; SS-spine still stands.")

# --- Save ---------------------------------------------------------------------
out_dir = joinpath(@__DIR__, "..", "tables", "csv")
mkpath(out_dir)
open(joinpath(out_dir, "ss_crowdout_moderation_dryrun.csv"), "w") do f
    println(f, "behavioral_config,cut_pct,ownership_pct,mean_alpha")
    for (label,_,_) in CONFIGS, c in CUTS
        @printf(f, "%s,%.0f,%.4f,%.6f\n", label, c*100, own[(label,c)]*100, alp[(label,c)])
    end
end
println("\n  CSV: tables/csv/ss_crowdout_moderation_dryrun.csv")
flush(stdout)
