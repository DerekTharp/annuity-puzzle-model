# SS-cut response by wealth bin — incidence of a trust-fund cut on private
# annuity demand across the wealth distribution.
#
# A Social Security shortfall cuts SS only; DB pension income survives. Two
# forces pull the by-wealth response in opposite directions: a thicker DB
# cushion shields a bin's income floor from the cut (dampening), while wealth
# itself determines whether private annuitization is feasible at all (the $10k
# minimum purchase and the consumption floor exclude low-wealth households from
# responding regardless of how hard the cut hits them). Which force dominates
# is an empirical question this script answers; the assessment block below
# reports the computed gradient rather than presupposing it.
#
# Structural model (rational + preference + structural chi_ltc; behavioral off).
#
# Usage:
#   julia --project=. -p 8 scripts/run_ss_cut_by_wealth.jl   (production)
#   ANNUITY_COARSE=1 julia --project=. -p 8 scripts/run_ss_cut_by_wealth.jl  (local check)

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
const CUTS = [0.0, 0.10, 0.22, 0.30, 0.50]
const NW = COARSE ? 40 : N_WEALTH
const NA = COARSE ? 12 : N_ANNUITY
const NALPHA = COARSE ? 51 : N_ALPHA

println("=" ^ 70)
println("  SS-CUT RESPONSE BY WEALTH QUARTILE (DB-cushion exhibit)")
println(COARSE ? "  [COARSE]" : "")
println("=" ^ 70)
flush(stdout)

# ===================================================================
# Population
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

const BREAKS = Float64.(SS_QUARTILE_BREAKS)
const Q_LO = [0.0, BREAKS[1], BREAKS[2], BREAKS[3]]
const Q_HI = [BREAKS[1], BREAKS[2], BREAKS[3], Inf]

# ===================================================================
# Survival / payout / grids (computed once)
# ===================================================================
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

# Capture config values for worker closures (pmap does not ship globals).
_theta = THETA_DFJ; _kappa = KAPPA_DFJ; _mwr = MWR_LOADED; _fc = FIXED_COST
_minp = MIN_PURCHASE; _infl = INFLATION; _pess = SURVIVAL_PESSIMISM
_cd = CONSUMPTION_DECLINE; _hu = Float64.(HEALTH_UTILITY); _chi = CHI_LTC
_gamma = GAMMA; _beta = BETA; _r = R_RATE; _nquad = N_QUAD; _cfloor = C_FLOOR
_hazard = Float64.(HAZARD_MULT)
_nw = NW; _na = NA; _nalpha = NALPHA; _wmax = W_MAX
_astart = AGE_START; _aend = AGE_END; _apow = A_GRID_POW
_ss_obs = Float64.(SS_OBS); _db_obs = Float64.(DB_OBS); _breaks = BREAKS
_base_surv = base_surv; _grids = grids; _pop = population; _lpr = loaded_pr_nom

# ===================================================================
# Solve each (quartile, cut)
# ===================================================================
specs = [(q=q, cut=cut) for q in 1:4 for cut in CUTS]

results = parallel_solve(specs) do spec
    q = spec.q; cut = spec.cut
    lo = q == 1 ? -Inf : _breaks[q - 1]
    hi = q == 4 ? Inf : _breaks[q]
    keep = [(_pop[i, 1] >= lo && _pop[i, 1] < hi) for i in 1:size(_pop, 1)]
    pop_q = _pop[keep, :]
    n_q = size(pop_q, 1)
    if n_q == 0
        return (q=q, cut=cut, ownership=0.0, mean_alpha=0.0, n=0)
    end
    ss_q = (1.0 - cut) * _ss_obs[q] + _db_obs[q]
    gkw = (n_wealth=_nw, n_annuity=_na, n_alpha=_nalpha, W_max=_wmax,
           age_start=_astart, age_end=_aend, annuity_grid_power=_apow)
    ckw = (gamma=_gamma, beta=_beta, r=_r, stochastic_health=true,
           n_health_states=3, n_quad=_nquad, c_floor=_cfloor, hazard_mult=_hazard)
    p_model = ModelParams(; ckw...,
        theta=_theta, kappa=_kappa, mwr=_mwr, fixed_cost=_fc, min_purchase=_minp,
        inflation_rate=_infl, medical_enabled=true, health_mortality_corr=true,
        survival_pessimism=_pess, consumption_decline=_cd, health_utility=_hu,
        chi_ltc=_chi, gkw...)
    res = solve_and_evaluate(p_model, _grids, _base_surv, fill(ss_q, 4),
        pop_q, _lpr; step_name="", verbose=false)
    @printf("    [heartbeat] bin=%d cut=%.0f%% solved (own=%.1f%%)\n",
            q, cut * 100, res.ownership * 100)
    flush(stdout)
    (q=q, cut=cut, ownership=res.ownership, mean_alpha=res.mean_alpha, n=n_q)
end

own = Dict{Tuple{Int,Float64},Float64}()
nq = Dict{Int,Int}()
for r in results
    own[(r.q, r.cut)] = r.ownership
    nq[r.q] = r.n
end

# ===================================================================
# Report
# ===================================================================
println("\n  Ownership (%) by wealth quartile x SS cut:")
@printf("  %-14s %5s %7s %7s", "wealth", "n", "SS", "DB")
for c in CUTS; @printf("  %5s", string(Int(round(c * 100))) * "%"); end
println(); println("  " * "-" ^ (40 + 7 * length(CUTS)))
labels = ["<30k", "30-120k", "120-350k", ">350k"]
for q in 1:4
    @printf("  %-14s %5d %7.0f %7.0f", labels[q], get(nq, q, 0), SS_OBS[q], DB_OBS[q])
    for c in CUTS; @printf("  %5.1f", own[(q, c)] * 100); end
    println()
end

println("\n  SS-cut incidence (22% SS cut response by wealth bin):")
@printf("  %-14s  %8s  %12s  %12s\n", "wealth", "DB share", "base own", "22%cut d_pp")
responses = Float64[]
for q in 1:4
    db_share = SS_OBS[q] + DB_OBS[q] > 0 ? DB_OBS[q] / (SS_OBS[q] + DB_OBS[q]) : 0.0
    base = own[(q, 0.0)] * 100
    at22 = own[(q, 0.22)] * 100
    push!(responses, at22 - base)
    @printf("  %-14s  %7.2f  %11.1f%%  %+11.1f\n", labels[q], db_share, base, at22 - base)
end
# Report the computed gradient; do not presuppose its direction.
if issorted(responses)
    println("\n  Computed gradient: the 22% SS-cut response INCREASES with wealth —")
    println("  feasibility (minimum purchase, consumption floor) dominates the DB cushion.")
elseif issorted(responses; rev=true)
    println("\n  Computed gradient: the 22% SS-cut response DECREASES with wealth —")
    println("  the DB cushion dominates feasibility.")
else
    println("\n  Computed gradient: the 22% SS-cut response is non-monotone in wealth;")
    println("  feasibility and the DB cushion trade off across bins.")
end

# ===================================================================
# Save CSV
# ===================================================================
out_dir = joinpath(@__DIR__, "..", "tables", "csv"); mkpath(out_dir)
# Coarse local checks must not overwrite the production artifact.
csv_path = joinpath(out_dir, COARSE ? "ss_cut_by_wealth_coarse.csv" : "ss_cut_by_wealth.csv")
open(csv_path, "w") do f
    println(f, "quartile,wealth_lo,wealth_hi,n,ss_obs,db_obs,db_share,cut_pct,ownership_pct")
    for q in 1:4
        db_share = SS_OBS[q] + DB_OBS[q] > 0 ? DB_OBS[q] / (SS_OBS[q] + DB_OBS[q]) : 0.0
        for c in CUTS
            @printf(f, "%d,%.0f,%.0f,%d,%.0f,%.0f,%.4f,%.0f,%.4f\n",
                q, Q_LO[q], Q_HI[q], get(nq, q, 0), SS_OBS[q], DB_OBS[q],
                db_share, c * 100, own[(q, c)] * 100)
    end
    end
end
println("\n  CSV saved: $csv_path")
flush(stdout)
