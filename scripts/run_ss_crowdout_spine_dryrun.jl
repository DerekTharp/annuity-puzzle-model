# STAGE -1 DE-RISK DRY RUN (2 of 2) — the SS crowd-out SPINE under corrected income.
#
# Tests whether the substitute-then-complement crowd-out shape survives the
# corrected income floor, and how much the 23%-cut response shrinks once DB
# pension is (a) included in the floor and (b) NOT cut by an SS shortfall.
#
# Three floor structures compared (per-quartile levels), cut = SS shortfall:
#   1. hardcoded_blob  : (1-cut) * [14k,17k,20k,25k]   (current/old code — cuts the blob)
#   2. obs_ss_cut_db_fixed : (1-cut)*SS_obs + DB_obs    (CORRECT: trust-fund cut hits
#                                                        only SS; DB pension untouched)
#   3. obs_blob_cut    : (1-cut) * (SS_obs + DB_obs)    (cuts everything; for contrast)
#
# Observed levels from calibration/build_ss_profile.jl (RAND HRS, verified vars
# r{w}isret and r{w}ipena):
#   SS_obs = [9160, 9657, 9989, 10388] ; DB_obs = [3757, 6090, 9309, 8947]
#
# Behavioral channels OFF (demoted to robustness after dry run 1). chi_LTC=0.49.
# Coarse grid for speed; the rise-then-fall SHAPE and the relative 23% response
# are what matter, not exact production levels.
#
# Usage: julia --project=. -p 6 scripts/run_ss_crowdout_spine_dryrun.jl

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

const SS_OBS = [9160.0, 9657.0, 9989.0, 10388.0]
const DB_OBS = [3757.0, 6090.0, 9309.0, 8947.0]
const HARDCODED = [14000.0, 17000.0, 20000.0, 25000.0]
const CUTS = [0.0, 0.10, 0.23, 0.30, 0.50, 1.0]
const CHI_LTC_VAL = 0.49

const NW_C = 40; const NA_C = 15; const NALPHA_C = 51

# floor structures: label => function(cut) -> 4-vector of per-quartile income
const STRUCTURES = [
    ("hardcoded_blob",      cut -> (1.0 - cut) .* HARDCODED),
    ("obs_ss_cut_db_fixed", cut -> (1.0 - cut) .* SS_OBS .+ DB_OBS),
    ("obs_blob_cut",        cut -> (1.0 - cut) .* (SS_OBS .+ DB_OBS)),
]

println("=" ^ 70)
println("  STAGE -1 DRY RUN — SS crowd-out spine under corrected income floor")
println("=" ^ 70)
@printf("  SS_obs=%s\n  DB_obs=%s\n", string(Int.(SS_OBS)), string(Int.(DB_OBS)))
@printf("  chi_LTC=%.2f ; coarse grid %dx%dx%d ; behavioral OFF\n", CHI_LTC_VAL, NW_C, NA_C, NALPHA_C)
flush(stdout)

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
@printf("  Population: %d\n", size(population, 1)); flush(stdout)

p_base = ModelParams(age_start=AGE_START, age_end=AGE_END)
base_surv = production_base_survival(p_base)
gkw = (n_wealth=NW_C, n_annuity=NA_C, n_alpha=NALPHA_C,
       W_max=W_MAX, age_start=AGE_START, age_end=AGE_END, annuity_grid_power=A_GRID_POW)
ckw = (gamma=GAMMA, beta=BETA, r=R_RATE,
       stochastic_health=true, n_health_states=3, n_quad=N_QUAD,
       c_floor=C_FLOOR, hazard_mult=Float64.(HAZARD_MULT), hazard_normalize=HAZARD_NORMALIZE)
p_fg = ModelParams(; ckw..., mwr=1.0, gkw...)
fair_pr = compute_payout_rate(p_fg, base_surv)
p_fn = ModelParams(; ckw..., mwr=1.0, inflation_rate=INFLATION, gkw...)
fair_pr_nom = INFLATION > 0 ? compute_payout_rate(p_fn, base_surv) : fair_pr
grids = build_grids(p_fg, max(fair_pr, fair_pr_nom))
loaded_pr_nom = MWR_LOADED * fair_pr_nom

specs = [(si=si, cut=cut) for si in 1:length(STRUCTURES) for cut in CUTS]
results = parallel_solve(specs) do spec
    (label, floorfn) = STRUCTURES[spec.si]
    ss_lvls = floorfn(spec.cut)
    p_model = ModelParams(; ckw...,
        theta=THETA_DFJ, kappa=KAPPA_DFJ,
        mwr=MWR_LOADED, fixed_cost=FIXED_COST, min_purchase=MIN_PURCHASE,
        inflation_rate=INFLATION,
        medical_enabled=true, health_mortality_corr=true,
        survival_pessimism=SURVIVAL_PESSIMISM,
        consumption_decline=CONSUMPTION_DECLINE,
        health_utility=Float64.(HEALTH_UTILITY),
        chi_ltc=CHI_LTC_VAL,
        lambda_w=1.0, psi_purchase=0.0,
        gkw...)
    res = solve_and_evaluate(p_model, grids, base_surv, ss_lvls,
        population, loaded_pr_nom; step_name="", verbose=false)
    (label=label, cut=spec.cut, ownership=res.ownership, mean_alpha=res.mean_alpha)
end

own = Dict{Tuple{String,Float64},Float64}()
for r in results; own[(r.label, r.cut)] = r.ownership; end

println("\n  Ownership (%) by floor structure x SS cut:")
@printf("  %-22s", "structure")
for c in CUTS; @printf("  %6s", string(Int(round(c*100)))*"%"); end
println(); println("  " * "-"^(22 + 8*length(CUTS)))
for (label, _) in STRUCTURES
    @printf("  %-22s", label)
    for c in CUTS; @printf("  %5.1f ", own[(label,c)]*100); end
    println()
end

println("\n" * "=" ^ 70)
println("  SHAPE & 23%-RESPONSE CHECK")
println("=" ^ 70)
for (label, _) in STRUCTURES
    base = own[(label,0.0)]*100
    at23 = own[(label,0.23)]*100
    peak_cut = CUTS[argmax([own[(label,c)] for c in CUTS])]
    at100 = own[(label,1.0)]*100
    risefall = peak_cut < 1.0 && at100 < own[(label,peak_cut)]*100
    @printf("  %-22s base=%.1f%%  23%%cut=%.1f%% (Δ=%+.1f pp)  peak@%.0f%%  elim=%.1f%%  rise-then-fall=%s\n",
            label, base, at23, at23-base, peak_cut*100, at100, risefall ? "YES" : "no")
end

out_dir = joinpath(@__DIR__, "..", "tables", "csv"); mkpath(out_dir)
open(joinpath(out_dir, "ss_crowdout_spine_dryrun.csv"), "w") do f
    println(f, "floor_structure,cut_pct,ownership_pct")
    for (label,_) in STRUCTURES, c in CUTS
        @printf(f, "%s,%.0f,%.4f\n", label, c*100, own[(label,c)]*100)
    end
end
println("\n  CSV: tables/csv/ss_crowdout_spine_dryrun.csv"); flush(stdout)
