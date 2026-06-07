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
# Bequest theta is held at THETA_DFJ across gamma. The project's portability
# check (calibration/recalibrate_bequests.jl) shows the bequest-to-wealth ratio
# moves only 0.173 -> 0.196 from gamma=2.0 to 2.5 (13.6%, under the 20% retarget
# threshold), so the bequest channel's empirical strength is approximately
# constant across the sweep; the exhibit varies gamma alone.
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
@printf("  Population (wealth >= \$%.0f): %d\n", MIN_WEALTH, size(population, 1)); flush(stdout)

p_surv = ModelParams(age_start=AGE_START, age_end=AGE_END)
base_surv = build_lockwood_survival(p_surv)

grid_kw = (n_wealth=NW, n_annuity=NA, n_alpha=NALPHA, W_max=W_MAX,
           age_start=AGE_START, age_end=AGE_END, annuity_grid_power=A_GRID_POW)

# Fair payout rates are gamma-independent (actuarial PV of survival).
p_fair = ModelParams(; gamma=2.5, beta=BETA, r=R_RATE, mwr=1.0, grid_kw...)
fair_pr = compute_payout_rate(p_fair, base_surv)
p_fair_nom = ModelParams(; gamma=2.5, beta=BETA, r=R_RATE, mwr=1.0,
                         inflation_rate=INFLATION, grid_kw...)
fair_pr_nom = INFLATION > 0 ? compute_payout_rate(p_fair_nom, base_surv) : fair_pr
grids = build_grids(p_fair, max(fair_pr, fair_pr_nom))

# Capture config constants for worker closures.
_theta_dfj = THETA_DFJ; _kappa_dfj = KAPPA_DFJ; _mwr_loaded = MWR_LOADED
_fixed_cost = FIXED_COST; _min_purchase = MIN_PURCHASE; _inflation = INFLATION
_surv_pess = SURVIVAL_PESSIMISM; _ss_q_levels = Float64.(SS_QUARTILE_LEVELS)
_beta = BETA; _r_rate = R_RATE; _c_floor = C_FLOOR
_hazard_mult = Float64.(HAZARD_MULT); _n_quad = N_QUAD
_consumption_decline = CONSUMPTION_DECLINE; _health_utility = Float64.(HEALTH_UTILITY)
_chi_ltc = CHI_LTC
_base_surv = base_surv; _population = population; _grids = grids
_fair_pr = fair_pr; _fair_pr_nom = fair_pr_nom
_gkw = grid_kw

# ===================================================================
# Solve all 512 structural subsets at a given gamma -> Shapley values
# ===================================================================
function shapley_at_gamma(gamma::Float64)
    specs = [(bitmask=i,) for i in 0:(N_STRUCT_SUBSETS - 1)]

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
               c_floor=_c_floor, hazard_mult=_hazard_mult)

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
            _population, pr; step_name="", verbose=false)
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

# Rank: 1 = largest Shapley value (strongest suppressor of ownership).
ranks_of(v) = (p = sortperm(v; rev=true); r = zeros(Int, length(v)); for (k, idx) in enumerate(p); r[idx] = k; end; r)

# Spearman rank correlation between two ranking vectors.
function spearman(r1::Vector{Int}, r2::Vector{Int})
    n = length(r1)
    d2 = sum((r1 .- r2) .^ 2)
    return 1.0 - 6.0 * d2 / (n * (n^2 - 1))
end

# ===================================================================
# Sweep gamma
# ===================================================================
rows = Tuple{Float64,String,Float64,Float64,Int,Int}[]  # gamma, channel, sh_own_pp, sh_alpha_pp, rank_own, rank_alpha
gamma_summary = Tuple{Float64,Float64,Float64}[]          # gamma, full_own_pct, spearman(own,alpha)

for gamma in GAMMA_GRID
    t0 = time()
    out = shapley_at_gamma(gamma)
    r_own = ranks_of(out.sh_own)
    r_alpha = ranks_of(out.sh_alpha)
    sp = spearman(r_own, r_alpha)
    push!(gamma_summary, (gamma, out.full_own * 100, sp))
    for i in 1:N_STRUCT
        push!(rows, (gamma, STRUCT_NAMES[i], out.sh_own[i] * 100, out.sh_alpha[i] * 100,
                     r_own[i], r_alpha[i]))
    end
    @printf("  gamma=%.2f: full ownership=%.1f%%  Spearman(own,alpha)=%.3f  (%.0fs)\n",
            gamma, out.full_own * 100, sp, time() - t0)
    flush(stdout)
end

# ===================================================================
# Report: per-gamma ranking + cross-gamma stability
# ===================================================================
println("\n" * "=" ^ 70)
println("  9-CHANNEL SHAPLEY RANKING BY GAMMA (ownership statistic)")
println("=" ^ 70)
@printf("  %-28s", "Channel")
for (g, _, _) in gamma_summary; @printf("  g=%.2f", g); end
println()
println("  " * "-" ^ (28 + 8 * length(gamma_summary)))
for i in 1:N_STRUCT
    @printf("  %-28s", STRUCT_NAMES[i])
    for (g, _, _) in gamma_summary
        rk = first(r for (gg, ch, _, _, r, _) in rows if gg == g && ch == STRUCT_NAMES[i])
        @printf("  %5d", rk)
    end
    println()
end

println("\n  Per-gamma Spearman(ownership-rank, mean-alpha-rank):")
for (g, fo, sp) in gamma_summary
    @printf("    gamma=%.2f  full ownership=%5.1f%%  Spearman=%.3f\n", g, fo, sp)
end

# ===================================================================
# Save CSV
# ===================================================================
out_dir = joinpath(@__DIR__, "..", "tables", "csv"); mkpath(out_dir)
csv_path = joinpath(out_dir, "shapley_gamma_stability.csv")
open(csv_path, "w") do f
    println(f, "gamma,channel,shapley_ownership_pp,shapley_meanalpha_pp,rank_ownership,rank_meanalpha")
    for (g, ch, so, sa, ro, ra) in rows
        @printf(f, "%.2f,%s,%.4f,%.4f,%d,%d\n", g, ch, so, sa, ro, ra)
    end
end
println("\n  CSV saved: $csv_path")

summ_path = joinpath(out_dir, "shapley_gamma_stability_summary.csv")
open(summ_path, "w") do f
    println(f, "gamma,full_ownership_pct,spearman_own_alpha")
    for (g, fo, sp) in gamma_summary
        @printf(f, "%.2f,%.4f,%.4f\n", g, fo, sp)
    end
end
println("  Summary CSV saved: $summ_path")
flush(stdout)
