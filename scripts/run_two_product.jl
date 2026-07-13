# Two-product extension: retail SPIA (MWR_LOADED) plus a group/employer
# annuity (GROUP_MWR) accessible to an observed fraction of each wealth band.
#
# Access is calibrated to employer-pension linkage from the RAND HRS
# (calibration/build_group_access.jl), NOT to any ownership rate. Product
# choice is dominance-ordered: the group product is the same contract at a
# better price, so a household with access weakly prefers it; band-level
# predicted ownership is the access-probability mixture of the two
# single-product predictions. No new state variable and no Bellman change.
#
# Outputs:
#   tables/csv/two_product_gradient.csv  (band: access, retail/group/mixture
#                                          ownership vs observed)
#   tables/csv/two_product_ss_cut.csv    (band: mixture base vs 22% cut,
#                                          response, response share)
# Usage: julia --project=. -p N scripts/run_two_product.jl

using Printf, DelimitedFiles, Distributed

if nworkers() > 1
    @everywhere include(joinpath(@__DIR__, "..", "src", "AnnuityPuzzle.jl"))
    @everywhere using .AnnuityPuzzle
else
    include(joinpath(@__DIR__, "..", "src", "AnnuityPuzzle.jl"))
    using .AnnuityPuzzle
end
include(joinpath(@__DIR__, "config.jl"))

println("=" ^ 70)
println("  TWO-PRODUCT EXTENSION: retail SPIA + group annuity with band access")
println("=" ^ 70); flush(stdout)

# --- Access rates (coverage-calibrated) ---
acc_raw, acc_hdr = readdlm(GROUP_ACCESS_PATH, ',', Any; header=true)
ACCESS = [Float64(acc_raw[b, findfirst(==("access_unw"), vec(acc_hdr))]) for b in 1:4]
@printf("  Group access by band (employer-pension linkage): %s\n",
        join([@sprintf("%.1f%%", a * 100) for a in ACCESS], " / "))

# --- Population split into bands (same as the gate) ---
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
nb = size.(pop_band, 1)
@printf("  Eligible N=%d; band sizes: %s\n", size(pop, 1), join(nb, "/")); flush(stdout)

# --- Common model objects (production grid) ---
pb = ModelParams(age_start=AGE_START, age_end=AGE_END)
base_surv = production_base_survival(pb)
gkw = (n_wealth=N_WEALTH, n_annuity=N_ANNUITY, n_alpha=N_ALPHA, W_max=W_MAX,
       age_start=AGE_START, age_end=AGE_END, annuity_grid_power=A_GRID_POW)
fair_nom = compute_payout_rate(ModelParams(; gamma=GAMMA, beta=BETA, r=R_RATE, mwr=1.0,
                                            inflation_rate=INFLATION, gkw...), base_surv)
fair     = compute_payout_rate(ModelParams(; gamma=GAMMA, beta=BETA, r=R_RATE, mwr=1.0, gkw...), base_surv)
grids    = build_grids(ModelParams(; gamma=GAMMA, beta=BETA, r=R_RATE, mwr=1.0, gkw...), max(fair, fair_nom))

const PRODUCTS = [(key="retail", mwr=MWR_LOADED), (key="group", mwr=GROUP_MWR)]
ss_base = Float64.(SS_QUARTILE_LEVELS)
ss_cut  = (1 - SS_CUT_TRUSTEES) .* Float64.(SS_OBS) .+ Float64.(DB_OBS)

_bs = base_surv; _grids = grids; _popband = pop_band; _fair_nom = fair_nom
_ss_base = ss_base; _ss_cut = ss_cut; _products = PRODUCTS; _db = Float64.(DB_OBS)
_gamma=GAMMA; _beta=BETA; _r=R_RATE; _nq=N_QUAD; _cf=C_FLOOR; _hm=Float64.(HAZARD_MULT); _hn=HAZARD_NORMALIZE
_theta=THETA_DFJ; _kappa=KAPPA_DFJ; _fc=FIXED_COST; _minp=MIN_PURCHASE
_infl=INFLATION; _psi=SURVIVAL_PESSIMISM; _cd=CONSUMPTION_DECLINE
_hu=Float64.(HEALTH_UTILITY); _chi=CHI_LTC; _gkw=gkw

tasks = [(prod=pi, band=b, scen=s) for pi in 1:2 for b in 1:4 for s in (:base, :cut)]
@printf("\nSolving %d (product x band x scenario) models...\n", length(tasks)); flush(stdout)
t0 = time()
results = parallel_solve(tasks) do task
    prod = _products[task.prod]
    ss_val = task.scen === :base ? _ss_base[task.band] : _ss_cut[task.band]
    db_val = _db[task.band]
    payout = prod.mwr * _fair_nom
    p = ModelParams(; gamma=_gamma, beta=_beta, r=_r, stochastic_health=true,
        n_health_states=3, n_quad=_nq, c_floor=_cf, hazard_mult=_hm, hazard_normalize=_hn,
        theta=_theta, kappa=_kappa, mwr=prod.mwr, fixed_cost=_fc,
        min_purchase=_minp, inflation_rate=_infl, medical_enabled=true,
        health_mortality_corr=true, survival_pessimism=_psi,
        consumption_decline=_cd, health_utility=_hu, chi_ltc=_chi, _gkw...)
    sol = solve_lifecycle_health(p, _grids, _bs,
                                 build_ss_func(ss_val - db_val, db_val, p.age_start))
    res = compute_ownership_rate_health(sol, _popband[task.band], payout; base_surv=_bs)
    @printf("    [done] %s band %d %s: own=%.2f%%\n", prod.key, task.band,
            String(task.scen), res.ownership_rate * 100); flush(stdout)
    (prod=task.prod, band=task.band, scen=task.scen, own=res.ownership_rate)
end
@printf("  solved in %.0fs\n", time() - t0); flush(stdout)

own = Dict((r.prod, r.band, r.scen) => r.own for r in results)
mix(b, s) = ACCESS[b] * own[(2, b, s)] + (1 - ACCESS[b]) * own[(1, b, s)]

# Observed lifetime rates for display (person-wave, restricted sample)
obs_raw, obs_hdr = readdlm(joinpath(@__DIR__, "..", "data", "processed",
    "hrs_lifetime_ownership_by_band.csv"), ',', Any; header=true)
oc = findfirst(==("lifetime_unw_pct"), vec(obs_hdr))
OBS = [Float64(obs_raw[b, oc]) for b in 1:4]

labels = ["<30k", "30-120k", "120-350k", ">350k"]
println("\n  TWO-PRODUCT BASELINE GRADIENT (ownership %):")
@printf("  %-10s %8s %8s %8s %9s %9s\n", "band", "access", "retail", "group", "mixture", "observed")
for b in 1:4
    @printf("  %-10s %7.1f%% %7.2f%% %7.2f%% %8.2f%% %8.2f%%\n", labels[b], ACCESS[b]*100,
        own[(1,b,:base)]*100, own[(2,b,:base)]*100, mix(b,:base)*100, OBS[b])
end
agg_mix_base = sum(nb[b] * mix(b,:base) for b in 1:4) / sum(nb)
@printf("  %-10s %8s %8s %8s %8.2f%%\n", "AGGREGATE", "", "", "", agg_mix_base*100)

println("\n  22% SS-CUT RESPONSE (mixture, pp):")
rises = [mix(b,:cut) - mix(b,:base) for b in 1:4]
tot = sum(nb[b] * rises[b] for b in 1:4)
for b in 1:4
    share = tot > 0 ? nb[b]*rises[b]/tot*100 : 0.0
    @printf("  %-10s base %6.2f%% -> cut %6.2f%%  (%+.2f pp, %5.1f%% of response)\n",
        labels[b], mix(b,:base)*100, mix(b,:cut)*100, rises[b]*100, share)
end
top_share = tot > 0 ? nb[4]*rises[4]/tot*100 : 0.0
@printf("\n  Top band carries %.0f%% of the induced response.\n", top_share)

csv1 = joinpath(@__DIR__, "..", "tables", "csv", "two_product_gradient.csv")
open(csv1, "w") do io
    println(io, "band,band_label,n,access_pct,retail_pct,group_pct,mixture_pct,observed_lifetime_pct")
    for b in 1:4
        @printf(io, "%d,%s,%d,%.4f,%.4f,%.4f,%.4f,%.4f\n", b, labels[b], nb[b], ACCESS[b]*100,
            own[(1,b,:base)]*100, own[(2,b,:base)]*100, mix(b,:base)*100, OBS[b])
    end
    @printf(io, "0,AGGREGATE,%d,,,,%.4f,\n", sum(nb), agg_mix_base*100)
end
csv2 = joinpath(@__DIR__, "..", "tables", "csv", "two_product_ss_cut.csv")
open(csv2, "w") do io
    println(io, "band,band_label,n,mixture_base_pct,mixture_cut_pct,response_pp,response_share_pct")
    for b in 1:4
        share = tot > 0 ? nb[b]*rises[b]/tot*100 : 0.0
        @printf(io, "%d,%s,%d,%.4f,%.4f,%.4f,%.2f\n", b, labels[b], nb[b],
            mix(b,:base)*100, mix(b,:cut)*100, rises[b]*100, share)
    end
end
println("  CSVs: $csv1, $csv2")
println("DONE."); flush(stdout)
