# Referee-proofing recomputations for the ranking-stability and policy-lever claims.
#
# (a) Three 9-channel exact Shapley games (512 subsets each) at alternative
#     baselines: MWR = 0.85, MWR = 0.90, and gamma = 1.5. The manuscript claims
#     pricing-load dominance is stable across calibrations; these recompute the
#     game at the modern population-table MWR, the group-pricing MWR, and the
#     low end of the Chetty (2006) risk-aversion range. Coarse grid, matching
#     the psi=0.981 ranking check (the ranking is grid-robust; the level is not
#     the object).
# (b) By-band ownership of the full nine-channel model at policy MWRs 0.90 and
#     0.95 (production grid): whether group or public-option pricing moves the
#     middle wealth bands, which the abstract's closing sentence turns on.
#
# Output: tables/csv/referee_proofing_shapley.csv
#         tables/csv/referee_proofing_byband.csv
# Usage:  julia --project=. -p 12 scripts/run_referee_proofing.jl

using Printf, DelimitedFiles, Distributed

if nworkers() > 1
    @everywhere include(joinpath(@__DIR__, "..", "src", "AnnuityPuzzle.jl"))
    @everywhere using .AnnuityPuzzle
else
    include(joinpath(@__DIR__, "..", "src", "AnnuityPuzzle.jl"))
    using .AnnuityPuzzle
end
include(joinpath(@__DIR__, "config.jl"))

const NW = 40; const NA = 15; const NAL = 51   # coarse: ranking is grid-robust
const N_CH = 9
const NAMES = ["SS", "Bequests", "Medical+R-S", "Pessimism", "Age needs",
               "State utility", "Loads", "Inflation", "Public-care (LTC)"]
const GAMES = [
    (key="mwr085",  label="MWR = 0.85 baseline",  mwr=0.85,       gamma=GAMMA),
    (key="mwr090",  label="MWR = 0.90 baseline",  mwr=0.90,       gamma=GAMMA),
    (key="gamma15", label="gamma = 1.5 baseline", mwr=MWR_LOADED, gamma=1.5),
]
const POLICY_MWRS = [0.90, 0.95]

println("=" ^ 70)
println("  REFEREE-PROOFING: alternative-baseline Shapley games + by-band policy MWRs")
println("=" ^ 70); flush(stdout)

hrs_raw = readdlm(HRS_PATH, ',', Any; skipstart=1)
has_health = assert_hrs_schema(hrs_raw, HRS_PATH)
n_pop = size(hrs_raw, 1)
population = zeros(n_pop, 4)
population[:, 1] = Float64.(hrs_raw[:, 1]); population[:, 2] .= 0.0
population[:, 3] = Float64.(hrs_raw[:, 3])
population[:, 4] = has_health ? Float64.(hrs_raw[:, 4]) : fill(2.0, n_pop)

p_base = ModelParams(age_start=AGE_START, age_end=AGE_END)
base_surv = build_lockwood_survival(p_base)
gkw = (n_wealth=NW, n_annuity=NA, n_alpha=NAL, W_max=W_MAX, age_start=AGE_START,
       age_end=AGE_END, annuity_grid_power=A_GRID_POW)
fair     = compute_payout_rate(ModelParams(; gamma=GAMMA, beta=BETA, r=R_RATE, mwr=1.0, gkw...), base_surv)
fair_nom = INFLATION > 0 ? compute_payout_rate(ModelParams(; gamma=GAMMA, beta=BETA, r=R_RATE, mwr=1.0, inflation_rate=INFLATION, gkw...), base_surv) : fair

_theta=THETA_DFJ; _kappa=KAPPA_DFJ; _fc=FIXED_COST; _minp=MIN_PURCHASE
_infl=INFLATION; _ssq=Float64.(SS_QUARTILE_LEVELS); _beta=BETA; _r=R_RATE
_cf=C_FLOOR; _hm=Float64.(HAZARD_MULT); _nq=N_QUAD; _cd=CONSUMPTION_DECLINE
_hu=Float64.(HEALTH_UTILITY); _chi=CHI_LTC; _lw=LAMBDA_W; _pp=PSI_PURCHASE; _ppc=PSI_PURCHASE_C_REF
_bs=base_surv; _pop=population; _fair=fair; _fairn=fair_nom; _minw=MIN_WEALTH; _gkw=gkw
_psi=SURVIVAL_PESSIMISM; _games=GAMES

specs = [(g=g, m=m) for g in 1:length(GAMES) for m in 0:511]
@printf("Solving %d subset models (3 games x 512 subsets, coarse grid)...\n", length(specs)); flush(stdout)
t0 = time()
results = parallel_solve(specs) do spec
    game = _games[spec.g]
    mask = spec.m
    cfg = build_subset_config(bitmask_to_channels(mask);
        theta_dfj=_theta, kappa_dfj=_kappa, mwr_loaded=game.mwr, fixed_cost=_fc,
        min_purchase=_minp, inflation_val=_infl, survival_pessimism=_psi,
        ss_quartile_levels=_ssq, consumption_decline=_cd, health_utility=_hu,
        chi_ltc_val=_chi, lambda_w_val=_lw, psi_purchase_val=_pp, psi_purchase_c_ref_val=_ppc)
    has_loads = cfg.mwr < 1.0; has_infl = cfg.inflation_rate > 0
    pr = has_loads && has_infl ? cfg.mwr * _fairn : has_loads ? cfg.mwr * _fair : has_infl ? _fairn : _fair
    common = (gamma=game.gamma, beta=_beta, r=_r, stochastic_health=true, n_health_states=3,
              n_quad=_nq, c_floor=_cf, hazard_mult=_hm)
    grids = build_grids(ModelParams(; common..., mwr=1.0, _gkw...), max(_fair, _fairn))
    p = ModelParams(; common..., theta=cfg.theta, kappa=cfg.kappa, mwr=cfg.mwr,
        fixed_cost=cfg.fixed_cost, min_purchase=cfg.min_purchase, inflation_rate=cfg.inflation_rate,
        medical_enabled=cfg.medical_enabled, health_mortality_corr=cfg.health_mortality_corr,
        survival_pessimism=cfg.survival_pessimism, consumption_decline=cfg.consumption_decline,
        health_utility=cfg.health_utility, chi_ltc=cfg.chi_ltc, _gkw...)
    pop = _minw > 0 ? _pop[_pop[:, 1] .>= _minw, :] : _pop
    res = solve_and_evaluate(p, grids, _bs, cfg.ss_levels, pop, pr; verbose=false)
    if mask % 64 == 0
        @printf("    [heartbeat] game %d subset %d solved\n", spec.g, mask); flush(stdout)
    end
    (g=spec.g, mask=mask, ownership=res.ownership)
end
@printf("  done in %.0fs\n", time() - t0); flush(stdout)

csv1 = joinpath(@__DIR__, "..", "tables", "csv", "referee_proofing_shapley.csv")
open(csv1, "w") do io
    println(io, "game,channel,shapley_value_pp,abs_rank")
    for (gi, game) in enumerate(GAMES)
        lookup = Dict{Int,Float64}(r.mask => r.ownership for r in results if r.g == gi)
        shap = exact_shapley(N_CH, lookup)
        order = sortperm(abs.(shap); rev=true)
        rk = zeros(Int, N_CH); for (k, i) in enumerate(order); rk[i] = k; end
        @printf("\n  %s  (full own=%.1f%%):\n", game.label, lookup[511] * 100)
        for i in sortperm(shap; rev=true)
            @printf("    %-20s %+8.2f pp  (|rank| %d)\n", NAMES[i], shap[i] * 100, rk[i])
        end
        loads_rank = rk[7]; beq_rank = rk[2]
        @printf("    -> loads |rank| = %d, bequests |rank| = %d\n", loads_rank, beq_rank)
        for i in 1:N_CH
            @printf(io, "%s,%s,%.4f,%d\n", game.key, NAMES[i], shap[i] * 100, rk[i])
        end
    end
end
println("\n  CSV: $csv1"); flush(stdout)

# --- (b) By-band ownership at policy MWRs, production grid, full 9-channel model ---
println("\nBy-band ownership at policy MWRs (production grid)..."); flush(stdout)
gkw_prod = (n_wealth=N_WEALTH, n_annuity=N_ANNUITY, n_alpha=N_ALPHA, W_max=W_MAX,
            age_start=AGE_START, age_end=AGE_END, annuity_grid_power=A_GRID_POW)
fair_p     = compute_payout_rate(ModelParams(; gamma=GAMMA, beta=BETA, r=R_RATE, mwr=1.0, gkw_prod...), base_surv)
fair_nom_p = INFLATION > 0 ? compute_payout_rate(ModelParams(; gamma=GAMMA, beta=BETA, r=R_RATE, mwr=1.0, inflation_rate=INFLATION, gkw_prod...), base_surv) : fair_p
pop_prod = MIN_WEALTH > 0 ? population[population[:, 1] .>= MIN_WEALTH, :] : population

csv2 = joinpath(@__DIR__, "..", "tables", "csv", "referee_proofing_byband.csv")
open(csv2, "w") do io
    println(io, "policy_mwr,aggregate_pct,band1_pct,band2_pct,band3_pct,band4_pct,n1,n2,n3,n4")
    for mwr_pol in POLICY_MWRS
        cfg = build_subset_config(bitmask_to_channels(511);
            theta_dfj=THETA_DFJ, kappa_dfj=KAPPA_DFJ, mwr_loaded=mwr_pol, fixed_cost=FIXED_COST,
            min_purchase=MIN_PURCHASE, inflation_val=INFLATION, survival_pessimism=SURVIVAL_PESSIMISM,
            ss_quartile_levels=Float64.(SS_QUARTILE_LEVELS), consumption_decline=CONSUMPTION_DECLINE,
            health_utility=Float64.(HEALTH_UTILITY), chi_ltc_val=CHI_LTC, lambda_w_val=LAMBDA_W,
            psi_purchase_val=PSI_PURCHASE, psi_purchase_c_ref_val=PSI_PURCHASE_C_REF)
        pr = mwr_pol * fair_nom_p
        p = ModelParams(; gamma=GAMMA, beta=BETA, r=R_RATE, stochastic_health=true,
            n_health_states=3, n_quad=N_QUAD, c_floor=C_FLOOR, hazard_mult=Float64.(HAZARD_MULT),
            theta=cfg.theta, kappa=cfg.kappa, mwr=cfg.mwr, fixed_cost=cfg.fixed_cost,
            min_purchase=cfg.min_purchase, inflation_rate=cfg.inflation_rate,
            medical_enabled=cfg.medical_enabled, health_mortality_corr=cfg.health_mortality_corr,
            survival_pessimism=cfg.survival_pessimism, consumption_decline=cfg.consumption_decline,
            health_utility=cfg.health_utility, chi_ltc=cfg.chi_ltc, gkw_prod...)
        grids_p = build_grids(ModelParams(; gamma=GAMMA, beta=BETA, r=R_RATE, mwr=1.0, gkw_prod...),
                              max(fair_p, fair_nom_p))
        res = solve_and_evaluate(p, grids_p, base_surv, cfg.ss_levels, pop_prod, pr;
                                 step_name=@sprintf("full model at MWR=%.2f", mwr_pol), verbose=true)
        @printf("  MWR=%.2f: aggregate %.1f%%, bands %.1f / %.1f / %.1f / %.1f %%\n",
            mwr_pol, res.ownership * 100,
            res.own_q[1] * 100, res.own_q[2] * 100, res.own_q[3] * 100, res.own_q[4] * 100)
        @printf(io, "%.2f,%.4f,%.4f,%.4f,%.4f,%.4f,%d,%d,%d,%d\n",
            mwr_pol, res.ownership * 100,
            res.own_q[1] * 100, res.own_q[2] * 100, res.own_q[3] * 100, res.own_q[4] * 100,
            Int(res.n_q[1]), Int(res.n_q[2]), Int(res.n_q[3]), Int(res.n_q[4]))
    end
end
println("  CSV: $csv2")
println("\nDONE."); flush(stdout)
