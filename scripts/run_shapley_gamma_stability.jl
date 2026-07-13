# Gamma-stability of the 9-channel Shapley ranking (the signature exhibit).
#
# The predicted ownership LEVEL is gamma-fragile (the extensive-margin indicator
# jumps across gamma). The RANKING of channels is not. This script computes the
# exact 9-channel Shapley decomposition (512 structural subsets, behavioral SDU
# and PED off) at each gamma and on TWO value statistics:
#   - ownership (the discontinuous extensive-margin indicator)
#   - mean alpha (the continuous intensive-margin statistic)
# A referee's central objection is that a Shapley on a discontinuous indicator is
# untrustworthy; showing the ranking survives both the choice of statistic and
# the value of gamma answers it.
#
# Bequest theta is held at THETA_DFJ across gamma. The portability check
# (calibration/recalibrate_bequests.jl -> tables/csv/bequest_recalibration.csv)
# measures the bequest-to-wealth ratio drift from the gamma=2.0 calibration:
# 13.5% at gamma=2.5 (production; within the 20% retarget threshold), 20.3% at
# 2.75, 26.8% at 3.0. The sweep endpoints therefore perturb the model JOINTLY:
# higher gamma raises risk aversion AND strengthens the effective bequest
# motive. A ranking stable across this joint perturbation is a stronger
# robustness statement than gamma alone; do NOT describe the sweep as holding
# the bequest channel's empirical strength constant.
#
# Usage:
#   julia --project=. -p 90 scripts/run_shapley_gamma_stability.jl   (production)
#   ANNUITY_COARSE=1 julia --project=. -p 6 scripts/run_shapley_gamma_stability.jl  (local check)

using Printf
using DelimitedFiles
using Distributed
using Statistics

if nworkers() > 1
    @everywhere include(joinpath(@__DIR__, "..", "src", "AnnuityPuzzle.jl"))
    @everywhere using .AnnuityPuzzle
else
    include(joinpath(@__DIR__, "..", "src", "AnnuityPuzzle.jl"))
    using .AnnuityPuzzle
end

include(joinpath(@__DIR__, "config.jl"))

const COARSE = get(ENV, "ANNUITY_COARSE", "0") == "1"

# 9 structural channels (SDU and PED excluded). Names mirror the first nine of
# the enumeration's CHANNEL_NAMES; bits 9,10 (SDU,PED) stay off, so masks run
# 0 .. 511.
const N_STRUCT = 9
const N_STRUCT_SUBSETS = 2^N_STRUCT  # 512
const STRUCT_NAMES = [
    "SS", "Bequests", "Medical+R-S", "Pessimism", "Age needs",
    "State utility", "Loads", "Inflation", "Public-care aversion (LTC)",
]

const GAMMA_GRID = COARSE ? [2.5] : [2.0, 2.25, 2.5, 2.75, 3.0]
const NW = COARSE ? 40 : N_WEALTH
const NA = COARSE ? 12 : N_ANNUITY
const NALPHA = COARSE ? 51 : N_ALPHA

println("=" ^ 70)
println("  GAMMA-STABILITY OF THE 9-CHANNEL SHAPLEY RANKING")
@printf("  %d subsets x %d gamma values%s\n", N_STRUCT_SUBSETS, length(GAMMA_GRID),
        COARSE ? "  [COARSE]" : "")
println("=" ^ 70)
flush(stdout)

# ===================================================================
# Population, survival, payout, grids (all gamma-independent: computed once)
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
@printf("  Population (wealth >= \$%.0f): %d\n", MIN_WEALTH, size(population, 1)); flush(stdout)

p_surv = ModelParams(age_start=AGE_START, age_end=AGE_END)
base_surv = production_base_survival(p_surv)

grid_kw = (n_wealth=NW, n_annuity=NA, n_alpha=NALPHA, W_max=W_MAX,
           age_start=AGE_START, age_end=AGE_END, annuity_grid_power=A_GRID_POW)

# Fair payout rates are gamma-independent (actuarial PV of survival).
p_fair = ModelParams(; gamma=2.5, beta=BETA, r=R_RATE, mwr=1.0, grid_kw...)
fair_pr = compute_payout_rate(p_fair, base_surv)
p_fair_nom = ModelParams(; gamma=2.5, beta=BETA, r=R_RATE, mwr=1.0,
                         inflation_rate=INFLATION, grid_kw...)
fair_pr_nom = INFLATION > 0 ? compute_payout_rate(p_fair_nom, base_surv) : fair_pr
grids = build_grids(p_fair, max(fair_pr, fair_pr_nom))

# Per-household commuted-PV top-up for the pre-existing-annuitization (SS+DB)
# player, priced at each respondent's observed age (SS real, DB nominal).
# population is already min-wealth filtered above, so it aligns 1:1.
topup_vec = commuted_topup_vector(population, base_surv, p_fair_nom)

# Capture config constants for worker closures.
_theta_dfj = THETA_DFJ; _kappa_dfj = KAPPA_DFJ; _mwr_loaded = MWR_LOADED
_fixed_cost = FIXED_COST; _min_purchase = MIN_PURCHASE; _inflation = INFLATION
_surv_pess = SURVIVAL_PESSIMISM; _ss_q_levels = Float64.(SS_QUARTILE_LEVELS)
_beta = BETA; _r_rate = R_RATE; _c_floor = C_FLOOR
_hazard_mult=Float64.(HAZARD_MULT); _hazard_normalize=HAZARD_NORMALIZE; _n_quad = N_QUAD
_consumption_decline = CONSUMPTION_DECLINE; _health_utility = Float64.(HEALTH_UTILITY)
_chi_ltc = CHI_LTC
_base_surv = base_surv; _population = population; _grids = grids
_topup_vec = topup_vec
_fair_pr = fair_pr; _fair_pr_nom = fair_pr_nom
_gkw = grid_kw

# ===================================================================
# Solve all 512 structural subsets at a given gamma -> Shapley values
# ===================================================================
function shapley_at_gamma(gamma::Float64)
    specs = [(bitmask=i,) for i in 0:(N_STRUCT_SUBSETS - 1)]
    t0_g = time()

    results = parallel_solve(specs) do spec
        mask = spec.bitmask
        active = bitmask_to_channels(mask)  # subset of {1..9}; SDU/PED never set

        cfg = build_subset_config(active;
            theta_dfj=_theta_dfj, kappa_dfj=_kappa_dfj,
            mwr_loaded=_mwr_loaded, fixed_cost=_fixed_cost,
            min_purchase=_min_purchase, inflation_val=_inflation,
            survival_pessimism=_surv_pess, ss_quartile_levels=_ss_q_levels,
            consumption_decline=_consumption_decline, health_utility=_health_utility,
            chi_ltc_val=_chi_ltc, lambda_w_val=1.0, psi_purchase_val=0.0,
            psi_purchase_c_ref_val=18_000.0)

        ckw = (gamma=gamma, beta=_beta, r=_r_rate,
               stochastic_health=true, n_health_states=3, n_quad=_n_quad,
               c_floor=_c_floor, hazard_mult=_hazard_mult, hazard_normalize=_hazard_normalize)

        has_loads = cfg.mwr < 1.0
        has_infl = cfg.inflation_rate > 0
        pr = has_loads && has_infl ? cfg.mwr * _fair_pr_nom :
             has_loads ? cfg.mwr * _fair_pr :
             has_infl ? _fair_pr_nom : _fair_pr

        p_model = ModelParams(; ckw...,
            theta=cfg.theta, kappa=cfg.kappa,
            mwr=cfg.mwr, fixed_cost=cfg.fixed_cost, min_purchase=cfg.min_purchase,
            inflation_rate=cfg.inflation_rate,
            medical_enabled=cfg.medical_enabled,
            health_mortality_corr=cfg.health_mortality_corr,
            survival_pessimism=cfg.survival_pessimism,
            consumption_decline=cfg.consumption_decline,
            health_utility=cfg.health_utility,
            chi_ltc=cfg.chi_ltc, lambda_w=cfg.lambda_w,
            psi_purchase=cfg.psi_purchase, psi_purchase_c_ref=cfg.psi_purchase_c_ref,
            _gkw...)

        res = solve_and_evaluate(p_model, _grids, _base_surv, cfg.ss_levels,
            _population, pr; step_name="", verbose=false,
            wealth_topup_hh = cfg.commute_ss ? _topup_vec : nothing)
        # Liveness heartbeat (~16 lines per gamma; see run_subset_enumeration).
        if mask % 32 == 0
            @printf("    [heartbeat] gamma=%.2f subset %3d/%d done (%.0fs elapsed)\n",
                    gamma, mask, N_STRUCT_SUBSETS, time() - t0_g)
            flush(stdout)
        end
        (bitmask=mask, ownership=res.ownership, mean_alpha=res.mean_alpha)
    end

    own_lookup = Dict{Int,Float64}()
    alpha_lookup = Dict{Int,Float64}()
    for r in results
        own_lookup[r.bitmask] = r.ownership
        alpha_lookup[r.bitmask] = r.mean_alpha
    end

    sh_own = exact_shapley(N_STRUCT, own_lookup)
    sh_alpha = exact_shapley(N_STRUCT, alpha_lookup)
    full_own = own_lookup[N_STRUCT_SUBSETS - 1]
    return (sh_own=sh_own, sh_alpha=sh_alpha, full_own=full_own)
end

# Rank: 1 = largest Shapley value. Ranks over the FULL signed vector pin the
# booster channels (negative Shapley: SS crowd-out, and typically Inflation)
# at the bottom in every column, which mechanically inflates a full-vector
# Spearman. The headline statistics are therefore computed on the SUPPRESSOR
# subset (positive ownership-Shapley), with boosters reported separately.
ranks_of(v) = (p = sortperm(v; rev=true); r = zeros(Int, length(v)); for (k, idx) in enumerate(p); r[idx] = k; end; r)

# Spearman rank correlation between two ranking vectors (no ties by construction).
function spearman(r1::Vector{Int}, r2::Vector{Int})
    n = length(r1)
    n < 2 && return 1.0
    d2 = sum((r1 .- r2) .^ 2)
    return 1.0 - 6.0 * d2 / (n * (n^2 - 1))
end

# Top-k channel names by descending value, restricted to given indices.
function topk_names(v::Vector{Float64}, idxs::Vector{Int}, k::Int)
    order = sort(idxs; by=i -> -v[i])
    return [STRUCT_NAMES[i] for i in order[1:min(k, length(order))]]
end

# ===================================================================
# Sweep gamma
# ===================================================================
rows = Tuple{Float64,String,Float64,Float64,Int,Int,Int}[]  # gamma, channel, sh_own_pp, sh_alpha_pp, rank_own, rank_alpha, is_suppressor
gamma_summary = NamedTuple[]

for gamma in GAMMA_GRID
    t0 = time()
    out = shapley_at_gamma(gamma)
    r_own = ranks_of(out.sh_own)
    r_alpha = ranks_of(out.sh_alpha)
    sp_full = spearman(r_own, r_alpha)

    # Suppressors: positive ownership-Shapley (channels that reduce demand).
    # Boosters (SS crowd-out; typically Inflation) are reported separately —
    # their sign pins them at fixed ranks and would inflate a full-vector
    # Spearman.
    sup = [i for i in 1:N_STRUCT if out.sh_own[i] > 0]
    boosters = [STRUCT_NAMES[i] for i in 1:N_STRUCT if out.sh_own[i] <= 0]
    sup_r_own = ranks_of([out.sh_own[i] for i in sup])
    sup_r_alpha = ranks_of([out.sh_alpha[i] for i in sup])
    sp_sup = spearman(sup_r_own, sup_r_alpha)

    top1_own = topk_names(out.sh_own, sup, 1)
    top1_alpha = topk_names(out.sh_alpha, sup, 1)
    top3_own = topk_names(out.sh_own, sup, 3)
    top3_alpha = topk_names(out.sh_alpha, sup, 3)

    push!(gamma_summary, (gamma=gamma, full_own=out.full_own * 100,
        sp_full=sp_full, sp_sup=sp_sup,
        top1_own=top1_own, top1_alpha=top1_alpha,
        top3_own=top3_own, top3_alpha=top3_alpha,
        boosters=boosters))
    for i in 1:N_STRUCT
        push!(rows, (gamma, STRUCT_NAMES[i], out.sh_own[i] * 100, out.sh_alpha[i] * 100,
                     r_own[i], r_alpha[i], i in sup ? 1 : 0))
    end
    @printf("  gamma=%.2f: full own=%.1f%%  Spearman full=%.3f sup-only=%.3f  top1=%s  (%.0fs)\n",
            gamma, out.full_own * 100, sp_full, sp_sup,
            isempty(top1_own) ? "-" : top1_own[1], time() - t0)
    flush(stdout)
end

# ===================================================================
# Report: per-gamma ranking + cross-gamma stability
# ===================================================================
println("\n" * "=" ^ 70)
println("  9-CHANNEL SHAPLEY RANKING BY GAMMA (ownership statistic)")
println("=" ^ 70)
@printf("  %-28s", "Channel")
for gs in gamma_summary; @printf("  g=%.2f", gs.gamma); end
println()
println("  " * "-" ^ (28 + 8 * length(gamma_summary)))
for i in 1:N_STRUCT
    @printf("  %-28s", STRUCT_NAMES[i])
    for gs in gamma_summary
        rk = first(r for (gg, ch, _, _, r, _, _) in rows if gg == gs.gamma && ch == STRUCT_NAMES[i])
        @printf("  %5d", rk)
    end
    println()
end

println("\n  Per-gamma statistics:")
for gs in gamma_summary
    @printf("    gamma=%.2f  full own=%5.1f%%  Spearman full=%.3f  suppressors-only=%.3f\n",
            gs.gamma, gs.full_own, gs.sp_full, gs.sp_sup)
    @printf("      top-3 suppressors (ownership):  %s\n", join(gs.top3_own, " > "))
    @printf("      top-3 suppressors (mean-alpha): %s\n", join(gs.top3_alpha, " > "))
    @printf("      boosters (negative Shapley):    %s\n", join(gs.boosters, ", "))
end

# Cross-gamma / cross-statistic concordance — the operative claim. The
# full-vector Spearman cannot distinguish a single adjacent swap (0.983 at
# n=9) from identity, so the headline is stated on top-k concordance.
top1_set = unique(vcat([gs.top1_own for gs in gamma_summary]...,
                       [gs.top1_alpha for gs in gamma_summary]...))
top3_sets = unique(vcat([sort(gs.top3_own) for gs in gamma_summary],
                        [sort(gs.top3_alpha) for gs in gamma_summary]))
println("\n" * "=" ^ 70)
println("  CONCORDANCE ACROSS GAMMA AND STATISTIC")
println("=" ^ 70)
if length(top1_set) == 1
    @printf("  Top-1 suppressor: %s in EVERY gamma and under BOTH statistics.\n", top1_set[1])
else
    @printf("  Top-1 suppressor varies: %s\n", join(top1_set, ", "))
end
if length(top3_sets) == 1
    @printf("  Top-3 suppressor SET identical everywhere: {%s}.\n", join(top3_sets[1], ", "))
else
    println("  Top-3 suppressor sets differ across columns:")
    for s in top3_sets
        println("    {", join(s, ", "), "}")
    end
end

# ===================================================================
# Save CSV (coarse local checks must not overwrite production artifacts)
# ===================================================================
out_dir = joinpath(@__DIR__, "..", "tables", "csv"); mkpath(out_dir)
suffix = COARSE ? "_coarse" : ""
csv_path = joinpath(out_dir, "shapley_gamma_stability$(suffix).csv")
open(csv_path, "w") do f
    println(f, "gamma,channel,shapley_ownership_pp,shapley_meanalpha_pp,rank_ownership,rank_meanalpha,is_suppressor")
    for (g, ch, so, sa, ro, ra, isup) in rows
        @printf(f, "%.2f,%s,%.4f,%.4f,%d,%d,%d\n", g, ch, so, sa, ro, ra, isup)
    end
end
println("\n  CSV saved: $csv_path")

summ_path = joinpath(out_dir, "shapley_gamma_stability_summary$(suffix).csv")
open(summ_path, "w") do f
    println(f, "gamma,full_ownership_pct,spearman_full,spearman_suppressors," *
               "top1_ownership,top1_meanalpha,top3_ownership,top3_meanalpha,boosters")
    for gs in gamma_summary
        @printf(f, "%.2f,%.4f,%.4f,%.4f,%s,%s,%s,%s,%s\n",
            gs.gamma, gs.full_own, gs.sp_full, gs.sp_sup,
            isempty(gs.top1_own) ? "" : gs.top1_own[1],
            isempty(gs.top1_alpha) ? "" : gs.top1_alpha[1],
            join(gs.top3_own, "|"), join(gs.top3_alpha, "|"),
            join(gs.boosters, "|"))
    end
end
println("  Summary CSV saved: $summ_path")
flush(stdout)
