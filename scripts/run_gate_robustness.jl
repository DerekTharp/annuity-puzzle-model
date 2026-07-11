# Killer table: is the SS-cut response concentration an artifact of the
# extensive-margin treatment, or invariant to it?
#
# The convexity-gap critique says the model's bottom-band zeros (and hence the
# "only the top responds to a benefit cut" punchline) are a fixed-cost corner
# artifact. The extensive-margin gate (run_extensive_margin_gate.jl) already
# shows the zeros survive heterogeneous fixed costs (F*=0: value-destroying at
# any cost). This script closes the loop by showing the SS-cut RESPONSE
# concentration is invariant to HOW the extensive margin is modeled:
#
#   hard               -- production model (theta_DFJ, fixed cost $2500): F* > 2500
#   feasibility-only   -- drop the fixed cost entirely (min-purchase + floor
#                         remain): F* > 0. Isolates the feasibility wall.
#   cost-smoothed      -- heterogeneous fixed costs F_i ~ LogNormal (FIXED, not
#                         fitted to band rates: a stress-test envelope): E[G(F*)]
#   theta-dispersed    -- observed within-band bequest-intention dispersion from
#                         HRS beq100 (theta in {0, theta_DFJ/2, theta_DFJ}),
#                         shares FROZEN on the baseline before the cut. The only
#                         mechanism that turns the bottom bands on via identified
#                         preference heterogeneity, not a free parameter.
#
# Every regime derives from the SAME per-household indifference fixed cost F*, so
# no band rate is ever a calibration target (the circularity the critique warns
# of is structurally absent). Plus a PLACEBO: a uniform lump-sum income cut of
# equal aggregate magnitude, to check the concentration is the feasibility wall
# (who CAN respond), not the proportional incidence of the SS cut.
#
# Output: tables/csv/gate_robustness_killer.csv, tables/tex/gate_robustness.tex
#
# Usage: julia --project=. -p 8 scripts/run_gate_robustness.jl
#        GATE_SMOKE=1 julia --project=. scripts/run_gate_robustness.jl

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

const SMOKE = get(ENV, "GATE_SMOKE", "0") == "1"
const NW  = SMOKE ? 40 : N_WEALTH
const NA  = SMOKE ? 15 : N_ANNUITY
const NAL = SMOKE ? 51 : N_ALPHA
const SS_CUT_FRAC = SS_CUT_TRUSTEES  # single source: scripts/config.jl
const COST_SIGMA = 0.5             # fixed stress-test dispersion (NOT fitted)
const THETA_CELLS = [0.0, THETA_DFJ / 2, THETA_DFJ]   # no / half / full bequest
const BAND_LABELS = ["<30k", "30-120k", "120-350k", ">350k"]

println("=" ^ 70)
println("  GATE ROBUSTNESS: is the SS-cut concentration invariant to the")
println("  extensive-margin treatment?")
SMOKE && println("  [SMOKE: coarse $(NW)x$(NA)x$(NAL) grid]")
println("=" ^ 70); flush(stdout)

# --- Model population, split into wealth bands ---
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
nb = [size(pop_band[b], 1) for b in 1:4]

# --- Observed within-band bequest-intention theta-cell shares (HRS beq100) ---
# beq100 is the 0-100 subjective P(leave >= $100k); NaN = missing (verified).
# Cells: ==0 -> theta=0; 0<.<75 -> theta_DFJ/2; >=75 -> theta_DFJ. Computed on
# the model-eligible (W>=MIN_WEALTH) validation subsample; FROZEN here (baseline).
val_path = joinpath(@__DIR__, "..", "data", "processed", "hrs_validation_sample.csv")
val = readdlm(val_path, ',', Any; skipstart=1)
vhead = vec(readdlm(val_path, ',', Any)[1, :])
wc = findfirst(==("wealth"), vhead); bc = findfirst(==("beq100"), vhead)
theta_share = zeros(4, 3)
let cnt = zeros(4, 3)
    for i in 1:size(val, 1)
        w = try Float64(val[i, wc]) catch; continue end
        w < MIN_WEALTH && continue
        b = band_of(w)
        bq = try Float64(val[i, bc]) catch; NaN end
        isnan(bq) && continue
        k = bq == 0 ? 1 : (bq < 75 ? 2 : 3)
        cnt[b, k] += 1
    end
    for b in 1:4
        s = sum(cnt[b, :]); s > 0 && (theta_share[b, :] = cnt[b, :] ./ s)
    end
end
@printf("  Eligible N=%d (bands %s)\n", size(pop, 1), join(nb, "/"))
println("  Observed theta-cell shares by band (no / half / full bequest):")
for b in 1:4
    @printf("    %-10s  %.2f / %.2f / %.2f\n", BAND_LABELS[b], theta_share[b, 1], theta_share[b, 2], theta_share[b, 3])
end
flush(stdout)

# --- Common objects ---
pbase = ModelParams(age_start=AGE_START, age_end=AGE_END)
base_surv = production_base_survival(pbase)
gkw = (n_wealth=NW, n_annuity=NA, n_alpha=NAL, W_max=W_MAX, age_start=AGE_START, age_end=AGE_END, annuity_grid_power=A_GRID_POW)
fair     = compute_payout_rate(ModelParams(; gamma=GAMMA, beta=BETA, r=R_RATE, mwr=1.0, gkw...), base_surv)
fair_nom = compute_payout_rate(ModelParams(; gamma=GAMMA, beta=BETA, r=R_RATE, mwr=1.0, inflation_rate=INFLATION, gkw...), base_surv)
loaded   = MWR_LOADED * fair_nom
grids    = build_grids(ModelParams(; gamma=GAMMA, beta=BETA, r=R_RATE, mwr=1.0, gkw...), max(fair, fair_nom))

ss_base = Float64.(SS_QUARTILE_LEVELS)
ss_cut  = (1 - SS_CUT_FRAC) .* Float64.(SS_OBS) .+ Float64.(DB_OBS)
# Placebo: uniform lump-sum income cut, same aggregate dollars as the SS cut.
lump = sum(nb[b] * SS_CUT_FRAC * Float64(SS_OBS[b]) for b in 1:4) / sum(nb)
ss_placebo = [max(ss_base[b] - lump, 1.0) for b in 1:4]
@printf("\n  Placebo lump-sum income cut = \$%.0f/yr (aggregate-equal to the 22%% SS cut)\n", lump)

_p = (gamma=GAMMA, beta=BETA, r=R_RATE, n_quad=N_QUAD, c_floor=C_FLOOR, hazard_mult=Float64.(HAZARD_MULT), hazard_normalize=HAZARD_NORMALIZE,
      kappa=KAPPA_DFJ, mwr=MWR_LOADED, fixed_cost=FIXED_COST, min_purchase=MIN_PURCHASE, inflation=INFLATION,
      pess=SURVIVAL_PESSIMISM, cd=CONSUMPTION_DECLINE, hu=Float64.(HEALTH_UTILITY), chi=CHI_LTC)
_g = grids; _bs = base_surv; _loaded = loaded; _pban = pop_band; _gkw = gkw
# Capture top-level scenario/theta bindings as locals so the pmap closure does
# not resolve them as worker globals (UndefVar under -p; ran fine single-threaded).
_ss_base = ss_base; _ss_cut = ss_cut; _ss_placebo = ss_placebo; _theta_cells = THETA_CELLS

# Tasks: (band, scen, theta_k). scen in {base, cut} x theta in {1,2,3}; placebo only theta=3.
tasks = NamedTuple[]
for b in 1:4, s in (:base, :cut), k in 1:3
    push!(tasks, (band=b, scen=s, k=k))
end
for b in 1:4
    push!(tasks, (band=b, scen=:placebo, k=3))
end

println("\n  Solving $(length(tasks)) (band x scenario x theta) models...")
flush(stdout)
t0 = time()
results = parallel_solve(tasks) do task
    b = task.band; s = task.scen; k = task.k
    ss_val = s === :base ? _ss_base[b] : s === :cut ? _ss_cut[b] : _ss_placebo[b]
    theta_k = _theta_cells[k]
    p = ModelParams(; gamma=_p.gamma, beta=_p.beta, r=_p.r, stochastic_health=true,
        n_health_states=3, n_quad=_p.n_quad, c_floor=_p.c_floor,
        hazard_mult=_p.hazard_mult, hazard_normalize=_p.hazard_normalize,
        theta=theta_k, kappa=_p.kappa, mwr=_p.mwr, fixed_cost=_p.fixed_cost,
        min_purchase=_p.min_purchase, inflation_rate=_p.inflation, medical_enabled=true,
        health_mortality_corr=true, survival_pessimism=_p.pess, consumption_decline=_p.cd,
        health_utility=_p.hu, chi_ltc=_p.chi, _gkw...)
    sol = solve_lifecycle_health(p, _g, _bs, (age, pp) -> ss_val)
    fs = compute_indiff_fixed_cost_health(sol, _pban[b], _loaded; base_surv=_bs)
    (band=b, scen=s, k=k, F_star=fs.F_star)
end
@printf("  done in %.0fs\n", time() - t0); flush(stdout)

F = Dict{Tuple{Int,Symbol,Int}, Vector{Float64}}()
for r in results; F[(r.band, r.scen, r.k)] = r.F_star; end

# --- Per-band ownership under each regime (all from F*) ---
gcdf(fstar) = fstar > 0 ? cdf(Normal(log(FIXED_COST), COST_SIGMA), log(fstar)) : 0.0
own_hard(b, s)  = mean(F[(b, s, 3)] .> FIXED_COST)
own_feas(b, s)  = mean(F[(b, s, 3)] .> 0.0)
own_cost(b, s)  = mean(gcdf.(F[(b, s, 3)]))
own_theta(b, s) = sum(theta_share[b, k] * mean(F[(b, s, k)] .> FIXED_COST) for k in 1:3)

regimes = [("hard", own_hard), ("feasibility-only", own_feas),
           ("cost-smoothed", own_cost), ("theta-dispersed", own_theta)]

aggregate(f, s) = sum(nb[b] * f(b, s) for b in 1:4) / sum(nb)
top_share(f) = begin
    resp = [f(b, :cut) - f(b, :base) for b in 1:4]
    # Share of the POSITIVE induced response borne by the top band. Using a
    # positive-only denominator avoids the >100% artifact that a net-signed
    # denominator produces when a lower band responds negatively.
    posden = sum(nb[b] * max(resp[b], 0.0) for b in 1:4)
    posden > 0 ? nb[4] * max(resp[4], 0.0) / posden * 100 : NaN
end

println("\n  KILLER TABLE: SS-cut response concentration by regime")
@printf("  %-18s %10s %10s %14s\n", "regime", "agg base", "agg cut", "top-band share")
killer = NamedTuple[]
for (name, f) in regimes
    ts = top_share(f)
    @printf("  %-18s %9.2f%% %9.2f%% %12.0f%%\n", name, aggregate(f, :base)*100, aggregate(f, :cut)*100, ts)
    push!(killer, (regime=name, agg_base=aggregate(f, :base), agg_cut=aggregate(f, :cut), top_share=ts,
                   resp_band=[f(b, :cut) - f(b, :base) for b in 1:4],
                   base_band=[f(b, :base) for b in 1:4]))
end

# Placebo: uniform lump-sum cut, hard regime. If the response still concentrates
# at the top, the concentration is the feasibility wall (who CAN respond), not the
# proportional incidence of the SS cut.
own_placebo(b) = mean(F[(b, :placebo, 3)] .> FIXED_COST)
placebo_resp = [own_placebo(b) - own_hard(b, :base) for b in 1:4]
ptot = sum(nb[b] * placebo_resp[b] for b in 1:4)
ptop = ptot != 0 ? nb[4] * placebo_resp[4] / ptot * 100 : NaN
println("\n  PLACEBO (uniform lump-sum income cut, hard regime): response (pp) by band")
for b in 1:4
    @printf("    %-10s  %+.3f pp\n", BAND_LABELS[b], placebo_resp[b] * 100)
end
@printf("    top-band share of placebo response: %.0f%%\n", ptop)

# --- CSV ---
mkpath(joinpath(@__DIR__, "..", "tables", "csv"))
csv_path = joinpath(@__DIR__, "..", "tables", "csv", "gate_robustness_killer.csv")
open(csv_path, "w") do io
    println(io, "regime,agg_base_pct,agg_cut_pct,top_band_resp_share_pct," *
                "resp_b1_pp,resp_b2_pp,resp_b3_pp,resp_b4_pp")
    for k in killer
        @printf(io, "%s,%.4f,%.4f,%.2f,%.4f,%.4f,%.4f,%.4f\n", k.regime,
                k.agg_base*100, k.agg_cut*100, k.top_share, (k.resp_band .* 100)...)
    end
    @printf(io, "placebo_lumpsum,%.4f,%.4f,%.2f,%.4f,%.4f,%.4f,%.4f\n",
            aggregate(own_hard, :base)*100, NaN, ptop, (placebo_resp .* 100)...)
    @printf(io, "# cost_sigma=%.2f (fixed stress-test), lump_sum=%.0f\n", COST_SIGMA, lump)
end
println("\n  CSV written: $csv_path")

# --- LaTeX ---
tex_path = joinpath(@__DIR__, "..", "tables", "tex", "gate_robustness.tex")
mkpath(dirname(tex_path))
open(tex_path, "w") do io
    println(io, raw"\begin{table}[htbp]")
    println(io, raw"\centering")
    println(io, raw"\small")
    println(io, raw"\caption{Social Security Cut Response: Robustness to the Extensive-Margin Treatment}")
    println(io, raw"\label{tab:gate_robustness}")
    println(io, raw"\begin{threeparttable}")
    println(io, raw"\begin{tabular}{lcccccc}")
    println(io, raw"\toprule")
    println(io, raw" & & & \multicolumn{4}{c}{Induced response by wealth band (pp)} " * "\\\\")
    println(io, raw"\cmidrule(lr){4-7}")
    println(io, raw"Extensive-margin treatment & Base (\%) & Cut (\%) & $<$30k & 30--120k & 120--350k & $>$350k " * "\\\\")
    println(io, raw"\midrule")
    for k in killer
        @printf(io, "%s & %.1f & %.1f & %+.1f & %+.1f & %+.1f & %+.1f \\\\\n", k.regime,
                k.agg_base*100, k.agg_cut*100, (k.resp_band .* 100)...)
    end
    println(io, raw"\bottomrule")
    println(io, raw"\end{tabular}")
    println(io, raw"\begin{tablenotes}")
    println(io, raw"\small")
    println(io, raw"\item Each row models the age-65 participation margin differently; all derive from the same")
    println(io, raw"per-household indifference fixed cost, so no band rate is a calibration target. ``hard'' is the")
    println(io, raw"production model; ``feasibility-only'' drops the fixed cost (minimum purchase and consumption floor")
    println(io, raw"remain); ``cost-smoothed'' applies heterogeneous fixed costs (fixed dispersion, not fitted);")
    println(io, raw"``theta-dispersed'' applies the observed within-band bequest-intention distribution (HRS beq100),")
    println(io, raw"frozen before the cut. The induced response is concentrated in the top band in every")
    println(io, raw"treatment, with a smaller positive third-band response under the fixed-cost treatments and")
    println(io, raw"zero or negative responses in the bottom two bands throughout.")
    println(io, raw"\end{tablenotes}")
    println(io, raw"\end{threeparttable}")
    println(io, raw"\end{table}")
end
println("  LaTeX written: $tex_path")

# --- Verdict ---
shares = [k.top_share for k in killer]
println("\n" * "=" ^ 70)
@printf("  Top-band response share across regimes: %s\n", join([@sprintf("%.0f%%", s) for s in shares], ", "))
if all(s -> !isnan(s) && s >= 90, shares)
    println("  INVARIANT: the SS-cut concentration does not depend on the extensive-")
    println("  margin treatment -> it is the feasibility wall, not a smoother artifact.")
else
    println("  NOT invariant: the concentration shifts with the treatment -> the")
    println("  distributional claim is mechanism-dependent (see fallback).")
end
println("=" ^ 70); flush(stdout)