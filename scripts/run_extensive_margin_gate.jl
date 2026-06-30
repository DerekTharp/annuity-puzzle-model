# Extensive-margin smoothing gate (the convexity-gap test).
#
# The headline model predicts a CONVEX wealth gradient: hard zeros in the bottom
# three wealth bands, ~33% in the top. The HRS cross-section is CONCAVE/saturating
# (1.7 / 6.4 / 7.9 / 7.6%). The hard zeros are a representative-agent corner: with
# a single fixed cost, every household in a band is on the same side of the
# participation threshold. Real households differ in transaction costs (advisor
# access, search, literacy), so within a band SOME cross even when the median does
# not. This script smooths the extensive margin with HETEROGENEOUS fixed costs
# F_i ~ LogNormal(mu, sigma), calibrated to the four HRS band rates, and asks the
# decision question the distributional claim hinges on:
#
#   Once the bottom bands CAN respond (interior baseline ownership), does a 22%
#   Social Security cut STILL concentrate the induced annuitization at the top,
#   or does the response spread down the distribution?
#
# The smoothing is a pure post-processing of the solved value function: the fixed
# cost enters only the age-65 decision, not V, so participation under G is the
# average of G(F*) across households, where F* is each household's indifference
# fixed cost (compute_indiff_fixed_cost_health). No Bellman re-solve, no engine
# change. The lognormal cost-smoother is a DIAGNOSTIC only (not a manuscript
# input): because smoothed participation is 0 wherever F*=0, the bottom two
# bands sit below their HRS targets and cannot be matched, so the (mu, sigma)
# search is effectively identified by the top band alone. The load-bearing
# outputs are the F* distribution (Result 1) and the killer table
# (run_gate_robustness.jl, fixed dispersion); neither fits any band rate.
#
# Output:
#   tables/csv/extensive_margin_gate.csv   (per-band: n, hrs, hard, smoothed
#                                            baseline + SS-cut, response)
#   tables/csv/wealth_gradient_modeldata.csv  (figure data: hard vs smoothed vs HRS)
#
# Usage: julia --project=. -p 8 scripts/run_extensive_margin_gate.jl
#        EMG_SMOKE=1 julia --project=. scripts/run_extensive_margin_gate.jl

using Printf, DelimitedFiles, Distributed, Statistics

if nworkers() > 1
    @everywhere include(joinpath(@__DIR__, "..", "src", "AnnuityPuzzle.jl"))
    @everywhere using .AnnuityPuzzle
else
    include(joinpath(@__DIR__, "..", "src", "AnnuityPuzzle.jl"))
    using .AnnuityPuzzle
end
include(joinpath(@__DIR__, "config.jl"))
using Distributions: Normal, cdf

const SMOKE = get(ENV, "EMG_SMOKE", "0") == "1"
const NW  = SMOKE ? 40 : N_WEALTH
const NA  = SMOKE ? 15 : N_ANNUITY
const NAL = SMOKE ? 51 : N_ALPHA
const SS_CUT_FRAC = 0.22  # 2026 Trustees projected OASI shortfall; mirrors run_welfare_counterfactuals.jl

# HRS per-band ownership (any-annuity proxy gradient; tables/csv/empirical_gradients_cells.csv)
const HRS_BAND = [1.6941, 6.3556, 7.8824, 7.6164] ./ 100
const BAND_LABELS = ["<30k", "30-120k", "120-350k", ">350k"]

println("=" ^ 70)
println("  EXTENSIVE-MARGIN GATE: heterogeneous fixed costs vs convexity gap")
SMOKE && println("  [SMOKE: coarse $(NW)x$(NA)x$(NAL) grid]")
println("=" ^ 70); flush(stdout)

# --- Population, split into the four fixed wealth bands ---
hrs = readdlm(HRS_PATH, ',', Any; skipstart=1)
has_health = assert_hrs_schema(hrs, HRS_PATH)
n = size(hrs, 1)
pop = zeros(n, 4)
pop[:, 1] = Float64.(hrs[:, 1]); pop[:, 3] = Float64.(hrs[:, 3])
pop[:, 4] = has_health ? Float64.(hrs[:, 4]) : fill(2.0, n)
pop = pop[pop[:, 1] .>= MIN_WEALTH, :]
br = SS_QUARTILE_BREAKS
band_of(w) = w < br[1] ? 1 : w < br[2] ? 2 : w < br[3] ? 3 : 4
pop_band = [pop[[band_of(pop[i, 1]) == b for i in 1:size(pop, 1)], :] for b in 1:4]
@printf("  Eligible N=%d; band sizes: %s\n", size(pop, 1), join(size.(pop_band, 1), "/"))
flush(stdout)

# --- Common model objects ---
pb = ModelParams(age_start=AGE_START, age_end=AGE_END)
base_surv = build_lockwood_survival(pb)
gkw = (n_wealth=NW, n_annuity=NA, n_alpha=NAL, W_max=W_MAX, age_start=AGE_START,
       age_end=AGE_END, annuity_grid_power=A_GRID_POW)
fair     = compute_payout_rate(ModelParams(; gamma=GAMMA, beta=BETA, r=R_RATE, mwr=1.0, gkw...), base_surv)
fair_nom = compute_payout_rate(ModelParams(; gamma=GAMMA, beta=BETA, r=R_RATE, mwr=1.0, inflation_rate=INFLATION, gkw...), base_surv)
loaded   = MWR_LOADED * fair_nom
grids    = build_grids(ModelParams(; gamma=GAMMA, beta=BETA, r=R_RATE, mwr=1.0, gkw...), max(fair, fair_nom))

# Full structural model params (SS supplied per-task via ss_func)
p_full = ModelParams(; gamma=GAMMA, beta=BETA, r=R_RATE, stochastic_health=true,
    n_health_states=3, n_quad=N_QUAD, c_floor=C_FLOOR, hazard_mult=Float64.(HAZARD_MULT),
    theta=THETA_DFJ, kappa=KAPPA_DFJ, mwr=MWR_LOADED, fixed_cost=FIXED_COST,
    min_purchase=MIN_PURCHASE, inflation_rate=INFLATION, medical_enabled=true,
    health_mortality_corr=true, survival_pessimism=SURVIVAL_PESSIMISM,
    consumption_decline=CONSUMPTION_DECLINE, health_utility=Float64.(HEALTH_UTILITY),
    chi_ltc=CHI_LTC, gkw...)

# Per-(band, scenario) SS level: baseline = SS_obs+DB_obs; cut = 0.78*SS_obs + DB_obs.
ss_base = Float64.(SS_QUARTILE_LEVELS)
ss_cut  = (1 - SS_CUT_FRAC) .* Float64.(SS_OBS) .+ Float64.(DB_OBS)

_p = p_full; _grids = grids; _bs = base_surv; _loaded = loaded; _popband = pop_band
# Capture scenario SS levels as locals so the pmap closure does not resolve them
# as worker globals (UndefVar under -p; the single-threaded path masked this).
_ss_base = ss_base; _ss_cut = ss_cut
tasks = [(band=b, scen=s) for b in 1:4 for s in (:base, :cut)]

println("\nSolving 8 (band x scenario) models and computing F*...")
flush(stdout)
t0 = time()
results = parallel_solve(tasks) do task
    b = task.band; s = task.scen
    ss_val = s === :base ? _ss_base[b] : _ss_cut[b]
    sol = solve_lifecycle_health(_p, _grids, _bs, (age, p) -> ss_val)
    fs = compute_indiff_fixed_cost_health(sol, _popband[b], _loaded; base_surv=_bs)
    (band=b, scen=s, F_star=fs.F_star, owns_hard=fs.owns_hard, infeasible=fs.infeasible)
end
@printf("  done in %.0fs\n", time() - t0); flush(stdout)

Fstar = Dict{Tuple{Int,Symbol}, Vector{Float64}}()
hard  = Dict{Tuple{Int,Symbol}, Vector{Bool}}()
Infeas = Dict{Tuple{Int,Symbol}, Vector{Bool}}()
for r in results
    Fstar[(r.band, r.scen)] = r.F_star
    hard[(r.band, r.scen)]  = r.owns_hard
    Infeas[(r.band, r.scen)] = r.infeasible
end

# --- Smoothed participation under LogNormal(mu, sigma) fixed costs ---
# g(F*) = P(F_i <= F*) = Phi((ln F* - mu)/sigma) for F*>0, else 0 (never owns).
function smoothed_band(b::Int, scen::Symbol, mu::Float64, sigma::Float64)
    fs = Fstar[(b, scen)]
    isempty(fs) && return 0.0
    s = 0.0
    for fstar in fs
        s += fstar > 0.0 ? cdf(Normal(mu, sigma), log(fstar)) : 0.0
    end
    return s / length(fs)
end

# Calibrate (mu, sigma) to the four HRS band rates (weighted by band n).
nb = [length(Fstar[(b, :base)]) for b in 1:4]
function sse(mu, sigma)
    s = 0.0
    for b in 1:4
        s += nb[b] * (smoothed_band(b, :base, mu, sigma) - HRS_BAND[b])^2
    end
    return s
end
function calibrate()
    best = (mu=log(2500.0), sigma=1.0, sse=Inf)
    for mu in log.(range(250.0, 8000.0; length=60)), sigma in range(0.15, 3.5; length=60)
        e = sse(mu, sigma)
        e < best.sse && (best = (mu=mu, sigma=sigma, sse=e))
    end
    # Local refinement
    for mu in range(best.mu - 0.3, best.mu + 0.3; length=40), sigma in range(max(0.05, best.sigma - 0.3), best.sigma + 0.3; length=40)
        e = sse(mu, sigma)
        e < best.sse && (best = (mu=mu, sigma=sigma, sse=e))
    end
    return best
end
best = calibrate()
mu_f, sig_f = best.mu, best.sigma
@printf("\n  Diagnostic LogNormal smoother (identified by the top band; not a manuscript input): median=\$%.0f, sigma=%.2f (SSE=%.2e)\n",
        exp(mu_f), sig_f, best.sse)
@printf("  (literature point fixed cost = \$%.0f; Lockwood range \$500-\$2000)\n", FIXED_COST)
flush(stdout)

# --- Aggregate and per-band results ---
function agg(scen::Symbol, f::Function)
    num = sum(nb[b] * f(b, scen) for b in 1:4)
    den = sum(nb)
    return num / den
end
hard_band(b, scen) = isempty(hard[(b, scen)]) ? 0.0 : mean(hard[(b, scen)])
smooth_base(b) = smoothed_band(b, :base, mu_f, sig_f)
smooth_cut(b)  = smoothed_band(b, :cut,  mu_f, sig_f)

println("\n  Wealth gradient (ownership %):")
@printf("  %-10s %8s %8s %10s %10s %10s\n", "band", "n", "HRS", "hard", "smooth", "smooth_cut")
for b in 1:4
    @printf("  %-10s %8d %7.2f%% %9.2f%% %9.2f%% %9.2f%%\n", BAND_LABELS[b], nb[b],
            HRS_BAND[b]*100, hard_band(b, :base)*100, smooth_base(b)*100, smooth_cut(b)*100)
end
agg_hard   = agg(:base, hard_band)
agg_smooth = agg(:base, (b, s) -> smooth_base(b))
agg_cut    = agg(:cut,  (b, s) -> smooth_cut(b))
@printf("  %-10s %8d %7s %9.2f%% %9.2f%% %9.2f%%\n", "AGGREGATE", sum(nb), "--",
        agg_hard*100, agg_smooth*100, agg_cut*100)

# --- Concentration test: where does the SS-cut response go? ---
println("\n  SS-cut response (smoothed, pp) by band:")
rises = [smooth_cut(b) - smooth_base(b) for b in 1:4]
tot_rise_count = sum(nb[b] * rises[b] for b in 1:4)
for b in 1:4
    share = tot_rise_count > 0 ? nb[b] * rises[b] / tot_rise_count * 100 : 0.0
    @printf("  %-10s  +%.3f pp   (%.0f%% of the aggregate induced rise)\n", BAND_LABELS[b], rises[b]*100, share)
end
top_share = tot_rise_count > 0 ? nb[4]*rises[4]/tot_rise_count*100 : 0.0
bottom3_share = 100 - top_share
@printf("\n  Top band carries %.0f%% of the induced response; bottom three carry %.0f%%.\n", top_share, bottom3_share)
@printf("  Bottom-band baseline ownership is now interior: %.2f%% (hard model: %.2f%%).\n",
        smooth_base(1)*100, hard_band(1, :base)*100)

# --- F* distribution by band (the rational-exclusion finding: Result 1) ---
# frac_fstar_zero = share with F*=0, split into:
#   frac_value_destroying = feasible plan exists but is value-destroying at zero cost;
#   frac_infeasible       = no feasible alpha at zero cost (W_0 below the minimum
#                           purchase), so the household is size-excluded, not cost-excluded.
# frac_below_fc = 0 < F* < fixed cost (would own if cost were lower: corner);
# frac_above_fc = F* > fixed cost (owns at the production fixed cost).
println("\n  F* distribution by band (Result 1):")
@printf("  %-10s %8s %9s %9s %10s %11s\n", "band", "F*=0", "valdestr", "infeas", "0<F*<fc", "own(cost=0)")
mkpath(joinpath(@__DIR__, "..", "tables", "csv"))
fstar_csv = joinpath(@__DIR__, "..", "tables", "csv", "fstar_distribution.csv")
open(fstar_csv, "w") do io
    println(io, "band,n,frac_fstar_zero,frac_value_destroying,frac_infeasible," *
                "frac_fstar_below_fc,frac_fstar_above_fc,own_if_costfree_pct,own_hard_pct")
    for b in 1:4
        fs = Fstar[(b, :base)]
        inf = Infeas[(b, :base)]
        f0     = isempty(fs) ? 0.0 : mean(fs .== 0.0)
        finf   = isempty(inf) ? 0.0 : mean(inf)
        fvd    = max(f0 - finf, 0.0)
        fmid   = isempty(fs) ? 0.0 : mean((fs .> 0.0) .& (fs .< FIXED_COST))
        fhi    = isempty(fs) ? 0.0 : mean(fs .>= FIXED_COST)
        ofree  = isempty(fs) ? 0.0 : mean(fs .> 0.0)
        @printf("  %-10s %7.0f%% %8.0f%% %8.0f%% %9.0f%% %10.2f%%\n",
                BAND_LABELS[b], f0*100, fvd*100, finf*100, fmid*100, ofree*100)
        @printf(io, "%s,%d,%.4f,%.4f,%.4f,%.4f,%.4f,%.4f,%.4f\n", BAND_LABELS[b], length(fs),
                f0, fvd, finf, fmid, fhi, ofree*100, hard_band(b, :base)*100)
    end
end
println("  F* distribution CSV written: $fstar_csv")

# --- CSVs ---
mkpath(joinpath(@__DIR__, "..", "tables", "csv"))
gate_csv = joinpath(@__DIR__, "..", "tables", "csv", "extensive_margin_gate.csv")
open(gate_csv, "w") do f
    println(f, "band,n,hrs_pct,hard_pct,smoothed_base_pct,smoothed_cut_pct,response_pp,response_share_pct")
    for b in 1:4
        share = tot_rise_count > 0 ? nb[b]*rises[b]/tot_rise_count*100 : 0.0
        @printf(f, "%s,%d,%.4f,%.4f,%.4f,%.4f,%.4f,%.2f\n", BAND_LABELS[b], nb[b],
                HRS_BAND[b]*100, hard_band(b,:base)*100, smooth_base(b)*100, smooth_cut(b)*100, rises[b]*100, share)
    end
    @printf(f, "AGGREGATE,%d,,%.4f,%.4f,%.4f,%.4f,100.00\n", sum(nb),
            agg_hard*100, agg_smooth*100, agg_cut*100, (agg_cut-agg_smooth)*100)
    @printf(f, "# calibrated lognormal median=%.0f sigma=%.4f\n", exp(mu_f), sig_f)
end
println("\n  CSV written: $gate_csv")

grad_csv = joinpath(@__DIR__, "..", "tables", "csv", "wealth_gradient_modeldata.csv")
open(grad_csv, "w") do f
    println(f, "band,wealth_label,hrs_pct,model_hard_pct,model_smoothed_pct")
    for b in 1:4
        @printf(f, "%d,%s,%.4f,%.4f,%.4f\n", b, BAND_LABELS[b], HRS_BAND[b]*100, hard_band(b,:base)*100, smooth_base(b)*100)
    end
end
println("  CSV written: $grad_csv")

println("\n" * "=" ^ 70)
println("  GATE VERDICT")
println("=" ^ 70)
if top_share >= 60
    println("  Response REMAINS top-concentrated after smoothing -> distributional")
    println("  claim survives; promote it (reframed on the marginal-response sign).")
else
    println("  Response SPREADS down the distribution after smoothing -> the")
    println("  top-concentration was a corner artifact; keep SS-cut as a caveated")
    println("  application only.")
end
flush(stdout)
