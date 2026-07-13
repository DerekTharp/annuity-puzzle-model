# Grid-robustness of the nine-channel Shapley RANKING.
#
# The predicted ownership level is grid-fragile (disclosed in the text); this
# recomputes the full 512-subset game at two finer grids than production
# (80x30x101) to show the ranking is not: 100x40x101 and 120x50x101, all other
# settings at production values. Output feeds the ranking-stability discussion.
#
# Output: tables/csv/grid_robustness_shapley.csv
# Usage:  julia --project=. -p N scripts/run_grid_robustness_shapley.jl

using Printf, DelimitedFiles, Distributed

if nworkers() > 1
    @everywhere include(joinpath(@__DIR__, "..", "src", "AnnuityPuzzle.jl"))
    @everywhere using .AnnuityPuzzle
else
    include(joinpath(@__DIR__, "..", "src", "AnnuityPuzzle.jl"))
    using .AnnuityPuzzle
end
include(joinpath(@__DIR__, "config.jl"))

const N_CH = 9
const NAMES = ["SS", "Bequests", "Medical+R-S", "Pessimism", "Age needs",
               "State utility", "Loads", "Inflation", "Public-care (LTC)"]
const GRIDS = [
    (key="g100x40", nw=100, na=40, nal=N_ALPHA),
    (key="g120x50", nw=120, na=50, nal=N_ALPHA),
]

println("=" ^ 70)
println("  GRID-ROBUSTNESS OF THE NINE-CHANNEL SHAPLEY RANKING")
println("  (512 subsets at 100x40 and 120x50; production settings otherwise)")
println("=" ^ 70); flush(stdout)

hrs_raw = readdlm(HRS_PATH, ',', Any; skipstart=1)
has_health = assert_hrs_schema(hrs_raw, HRS_PATH)
n_pop = size(hrs_raw, 1)
population = zeros(n_pop, 4)
population[:, 1] = Float64.(hrs_raw[:, 1]); population[:, 2] .= 0.0
population[:, 3] = Float64.(hrs_raw[:, 3])
population[:, 4] = has_health ? Float64.(hrs_raw[:, 4]) : fill(2.0, n_pop)

p_base = ModelParams(age_start=AGE_START, age_end=AGE_END)
base_surv = production_base_survival(p_base)

# Filter to the model-eligible population ONCE so the per-household commuted-PV
# top-up aligns 1:1. The top-up is grid-independent (payout_rate_at_age depends
# only on survival, discount, and age), so build it once here.
if MIN_WEALTH > 0.0
    population = population[population[:, 1] .>= MIN_WEALTH, :]
end
p_topup = ModelParams(; gamma=GAMMA, beta=BETA, r=R_RATE, mwr=1.0,
                      inflation_rate=INFLATION, age_start=AGE_START, age_end=AGE_END)
topup_vec = commuted_topup_vector(population, base_surv, p_topup)

_theta=THETA_DFJ; _kappa=KAPPA_DFJ; _mwr=MWR_LOADED; _fc=FIXED_COST; _minp=MIN_PURCHASE
_infl=INFLATION; _ssq=Float64.(SS_QUARTILE_LEVELS); _gamma=GAMMA; _beta=BETA; _r=R_RATE
_cf=C_FLOOR; _hm=Float64.(HAZARD_MULT); _hn=HAZARD_NORMALIZE; _nq=N_QUAD; _cd=CONSUMPTION_DECLINE
_hu=Float64.(HEALTH_UTILITY); _chi=CHI_LTC; _lw=LAMBDA_W; _pp=PSI_PURCHASE; _ppc=PSI_PURCHASE_C_REF
_bs=base_surv; _pop=population; _minw=MIN_WEALTH; _psi=SURVIVAL_PESSIMISM
_topup_vec=topup_vec
_grids_spec=GRIDS; _wmax=W_MAX; _agp=A_GRID_POW; _as=AGE_START; _ae=AGE_END

specs = [(g=g, m=m) for g in 1:length(GRIDS) for m in 0:511]
@printf("Solving %d subset models (2 grids x 512 subsets)...\n", length(specs)); flush(stdout)
t0 = time()
results = parallel_solve(specs) do spec
    gr = _grids_spec[spec.g]
    mask = spec.m
    gkw = (n_wealth=gr.nw, n_annuity=gr.na, n_alpha=gr.nal, W_max=_wmax,
           age_start=_as, age_end=_ae, annuity_grid_power=_agp)
    fair     = compute_payout_rate(ModelParams(; gamma=_gamma, beta=_beta, r=_r, mwr=1.0, gkw...), _bs)
    fair_nom = _infl > 0 ? compute_payout_rate(ModelParams(; gamma=_gamma, beta=_beta, r=_r, mwr=1.0, inflation_rate=_infl, gkw...), _bs) : fair
    cfg = build_subset_config(bitmask_to_channels(mask);
        theta_dfj=_theta, kappa_dfj=_kappa, mwr_loaded=_mwr, fixed_cost=_fc,
        min_purchase=_minp, inflation_val=_infl, survival_pessimism=_psi,
        ss_quartile_levels=_ssq, consumption_decline=_cd, health_utility=_hu,
        chi_ltc_val=_chi, lambda_w_val=_lw, psi_purchase_val=_pp, psi_purchase_c_ref_val=_ppc)
    has_loads = cfg.mwr < 1.0; has_infl = cfg.inflation_rate > 0
    pr = has_loads && has_infl ? cfg.mwr * fair_nom : has_loads ? cfg.mwr * fair : has_infl ? fair_nom : fair
    common = (gamma=_gamma, beta=_beta, r=_r, stochastic_health=true, n_health_states=3,
              n_quad=_nq, c_floor=_cf, hazard_mult=_hm, hazard_normalize=_hn)
    grids = build_grids(ModelParams(; common..., mwr=1.0, gkw...), max(fair, fair_nom))
    p = ModelParams(; common..., theta=cfg.theta, kappa=cfg.kappa, mwr=cfg.mwr,
        fixed_cost=cfg.fixed_cost, min_purchase=cfg.min_purchase, inflation_rate=cfg.inflation_rate,
        medical_enabled=cfg.medical_enabled, health_mortality_corr=cfg.health_mortality_corr,
        survival_pessimism=cfg.survival_pessimism, consumption_decline=cfg.consumption_decline,
        health_utility=cfg.health_utility, chi_ltc=cfg.chi_ltc, gkw...)
    pop = _minw > 0 ? _pop[_pop[:, 1] .>= _minw, :] : _pop
    res = solve_and_evaluate(p, grids, _bs, cfg.ss_levels, pop, pr; verbose=false,
        wealth_topup_hh = cfg.commute_ss ? _topup_vec : nothing)
    if mask % 64 == 0
        @printf("    [heartbeat] grid %d subset %d\n", spec.g, mask); flush(stdout)
    end
    (g=spec.g, mask=mask, ownership=res.ownership)
end
@printf("  done in %.0fs\n", time() - t0); flush(stdout)

csv = joinpath(@__DIR__, "..", "tables", "csv", "grid_robustness_shapley.csv")
open(csv, "w") do io
    println(io, "grid,channel,shapley_value_pp,abs_rank,full_own_pct")
    for (gi, gr) in enumerate(GRIDS)
        lookup = Dict{Int,Float64}(r.mask => r.ownership for r in results if r.g == gi)
        shap = exact_shapley(N_CH, lookup)
        order = sortperm(abs.(shap); rev=true)
        rk = zeros(Int, N_CH); for (k, i) in enumerate(order); rk[i] = k; end
        @printf("\n  %s  (full own=%.2f%%):\n", gr.key, lookup[511] * 100)
        for i in sortperm(shap; rev=true)
            @printf("    %-20s %+8.2f pp\n", NAMES[i], shap[i] * 100)
        end
        for i in 1:N_CH
            @printf(io, "%s,%s,%.4f,%d,%.4f\n", gr.key, NAMES[i], shap[i] * 100, rk[i], lookup[511] * 100)
        end
    end
end
println("  CSV: $csv")
println("DONE."); flush(stdout)
