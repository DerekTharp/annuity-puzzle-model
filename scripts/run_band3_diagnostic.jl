# Band-3 value-destruction diagnostic.
#
# The clean q286 lifetime-SPIA gradient is hump-shaped (1.69/3.37/5.34/4.46% by
# wealth band), peaking in band 3 ($120-350k). The model predicts 0% ownership
# in band 3 even at a zero transaction cost (fstar_distribution.csv:
# frac_value_destroying=1.0). This script asks WHY: for band-3 (and band-2)
# households it solves the full structural model and each leave-one-channel-out
# variant, and reports the share who would annuitize at zero fixed cost
# (own_if_costfree = mean(F* > 0)). The channel whose removal lifts that share
# off zero is what makes annuitization value-destroying for the empirical modal
# SPIA owner.
#
# Output: tables/csv/band_value_destruction_diagnostic.csv
# Usage:  julia --project=. -p 8 scripts/run_band3_diagnostic.jl

using Printf, DelimitedFiles, Distributed, Statistics

if nworkers() > 1
    @everywhere include(joinpath(@__DIR__, "..", "src", "AnnuityPuzzle.jl"))
    @everywhere using .AnnuityPuzzle
else
    include(joinpath(@__DIR__, "..", "src", "AnnuityPuzzle.jl"))
    using .AnnuityPuzzle
end
include(joinpath(@__DIR__, "config.jl"))

println("=" ^ 70)
println("  BAND-3 VALUE-DESTRUCTION DIAGNOSTIC (why F*=0 where SPIA owners peak)")
println("=" ^ 70); flush(stdout)

# --- Population, bands 2 and 3 ---
hrs = readdlm(HRS_PATH, ',', Any; skipstart=1)
has_health = assert_hrs_schema(hrs, HRS_PATH)
n = size(hrs, 1)
pop = zeros(n, 4)
pop[:, 1] = Float64.(hrs[:, 1]); pop[:, 3] = Float64.(hrs[:, 3])
pop[:, 4] = has_health ? Float64.(hrs[:, 4]) : fill(2.0, n)
pop = pop[pop[:, 1] .>= MIN_WEALTH, :]
br = SS_QUARTILE_BREAKS
band_of(w) = w < br[1] ? 1 : w < br[2] ? 2 : w < br[3] ? 3 : 4
pop_band = Dict(b => pop[[band_of(pop[i, 1]) == b for i in 1:size(pop, 1)], :] for b in 2:3)
@printf("  band 2 n=%d, band 3 n=%d\n", size(pop_band[2], 1), size(pop_band[3], 1)); flush(stdout)

# --- Common objects ---
pb = ModelParams(age_start=AGE_START, age_end=AGE_END)
base_surv = production_base_survival(pb)
gkw = (n_wealth=N_WEALTH, n_annuity=N_ANNUITY, n_alpha=N_ALPHA, W_max=W_MAX,
       age_start=AGE_START, age_end=AGE_END, annuity_grid_power=A_GRID_POW)
fair     = compute_payout_rate(ModelParams(; gamma=GAMMA, beta=BETA, r=R_RATE, mwr=1.0, gkw...), base_surv)
fair_nom = compute_payout_rate(ModelParams(; gamma=GAMMA, beta=BETA, r=R_RATE, mwr=1.0, inflation_rate=INFLATION, gkw...), base_surv)
grids    = build_grids(ModelParams(; gamma=GAMMA, beta=BETA, r=R_RATE, mwr=1.0, gkw...), max(fair, fair_nom))

# Full-structural baseline (production values); each config overrides one channel off.
# Override fields: ss_off, theta, medical, corr, psi, mwr, minp, infl, cd, hu, chi.
CONFIGS = [
    (name="Full structural",       d=(;)),
    (name="- Bequest",             d=(theta=0.0,)),
    (name="- Pre-existing SS+DB",  d=(ss_off=true,)),
    (name="- Med+R-S",             d=(medical=false, corr=false)),
    (name="- Survival pessimism",  d=(psi=1.0,)),
    (name="- Pricing loads (MWR)", d=(mwr=1.0, minp=0.0)),
    (name="- Inflation",           d=(infl=0.0,)),
    (name="- Age needs",           d=(cd=0.0,)),
    (name="- State utility",       d=(hu=[1.0, 1.0, 1.0],)),
    (name="- Public-care (LTC)",   d=(chi=1.0,)),
]

_gamma=GAMMA; _beta=BETA; _r=R_RATE; _nq=N_QUAD; _cf=C_FLOOR; _hm=Float64.(HAZARD_MULT); _hn=HAZARD_NORMALIZE
_theta=THETA_DFJ; _kappa=KAPPA_DFJ; _mwr=MWR_LOADED; _fc=FIXED_COST; _minp=MIN_PURCHASE
_infl=INFLATION; _psi=SURVIVAL_PESSIMISM; _cd=CONSUMPTION_DECLINE; _hu=Float64.(HEALTH_UTILITY); _chi=CHI_LTC
_ssq=Float64.(SS_QUARTILE_LEVELS); _fair=fair; _fairn=fair_nom; _g=grids; _bs=base_surv
_pban=pop_band; _gkw=gkw; _configs=CONFIGS

tasks = [(band=b, ci=ci) for b in 2:3 for ci in 1:length(CONFIGS)]
println("\n  Solving $(length(tasks)) (band x config) cells...\n"); flush(stdout)
t0 = time()
results = parallel_solve(tasks) do task
    b = task.band
    d = _configs[task.ci].d
    g(k, default) = haskey(d, k) ? d[k] : default

    theta   = g(:theta, _theta)
    medical = g(:medical, true); corr = g(:corr, true)
    psi     = g(:psi, _psi)
    mwr     = g(:mwr, _mwr); minp = g(:minp, _minp)
    infl    = g(:infl, _infl)
    cd      = g(:cd, _cd)
    hu      = g(:hu, _hu)
    chi     = g(:chi, _chi)
    ss_val  = g(:ss_off, false) ? 0.0 : _ssq[b]

    has_loads = mwr < 1.0; has_infl = infl > 0
    pr = has_loads && has_infl ? mwr * _fairn : has_loads ? mwr * _fair : has_infl ? _fairn : _fair

    p = ModelParams(; gamma=_gamma, beta=_beta, r=_r, stochastic_health=true,
        n_health_states=3, n_quad=_nq, c_floor=_cf, hazard_mult=_hm, hazard_normalize=_hn,
        theta=theta, kappa=_kappa, mwr=mwr, fixed_cost=_fc, min_purchase=minp,
        inflation_rate=infl, medical_enabled=medical, health_mortality_corr=corr,
        survival_pessimism=psi, consumption_decline=cd, health_utility=hu, chi_ltc=chi, _gkw...)
    sol = solve_lifecycle_health(p, _g, _bs, (age, pp) -> ss_val)
    fs = compute_indiff_fixed_cost_health(sol, _pban[b], pr; base_surv=_bs)
    # count/length, not mean: Statistics is loaded on the master, not on workers.
    costfree = isempty(fs.F_star) ? 0.0 : count(>(0.0), fs.F_star) / length(fs.F_star)
    owns     = isempty(fs.owns_hard) ? 0.0 : count(fs.owns_hard) / length(fs.owns_hard)
    (band=b, ci=task.ci, own_if_costfree=costfree, own_hard=owns)
end
@printf("  done in %.0fs\n", time() - t0); flush(stdout)

R = Dict((r.band, r.ci) => r for r in results)
println("\n  own_if_costfree = share who would annuitize at ZERO fixed cost (F*>0)")
println("  own_hard        = share who own at the production fixed cost\n")
@printf("  %-24s %18s %18s\n", "Config", "band2 (\$30-120k)", "band3 (\$120-350k)")
@printf("  %-24s %9s %8s %9s %8s\n", "", "costfree", "hard", "costfree", "hard")
for ci in 1:length(CONFIGS)
    @printf("  %-24s %8.1f%% %7.1f%% %8.1f%% %7.1f%%\n", CONFIGS[ci].name,
        R[(2,ci)].own_if_costfree*100, R[(2,ci)].own_hard*100,
        R[(3,ci)].own_if_costfree*100, R[(3,ci)].own_hard*100)
end

mkpath(joinpath(@__DIR__, "..", "tables", "csv"))
csv = joinpath(@__DIR__, "..", "tables", "csv", "band_value_destruction_diagnostic.csv")
open(csv, "w") do io
    println(io, "config,band,own_if_costfree_pct,own_hard_pct")
    for ci in 1:length(CONFIGS), b in 2:3
        @printf(io, "%s,%d,%.4f,%.4f\n", CONFIGS[ci].name, b, R[(b,ci)].own_if_costfree*100, R[(b,ci)].own_hard*100)
    end
end
println("\n  CSV: $csv")

# Verdict: which single removal lifts band-3 own_if_costfree the most off the full baseline.
base3 = R[(3,1)].own_if_costfree
lifts = [(CONFIGS[ci].name, R[(3,ci)].own_if_costfree - base3) for ci in 2:length(CONFIGS)]
sort!(lifts, by=x -> -x[2])
println("\n  Band-3 driver ranking (own_if_costfree lift vs full structural):")
for (nm, lift) in lifts
    @printf("    %-24s  %+6.1f pp\n", nm, lift*100)
end
flush(stdout)
