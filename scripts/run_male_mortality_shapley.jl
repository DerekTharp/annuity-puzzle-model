# Nine-channel exact Shapley under the PRIOR mortality convention: the male
# SSA 2003 table from Lockwood's replication files, with unnormalized health
# hazards, for both agent survival and annuity pricing (the same-table
# convention). The production headline instead uses the sex-blended,
# aggregate-anchored table; this game isolates the entire mortality
# treatment as a robustness comparison. Everything else matches the
# headline nine-channel game at the production grid.
#
# Output: tables/csv/shapley_male_mortality.csv,
#         tables/tex/shapley_male_mortality.tex
# Usage:  julia --project=. -p 90 scripts/run_male_mortality_shapley.jl

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

println("=" ^ 70)
println("  9-CHANNEL EXACT SHAPLEY, MALE TABLE / UNNORMALIZED HAZARDS (production grid)")
println("=" ^ 70); flush(stdout)

# Male table, prior convention: no hazard normalization.
p_base = ModelParams(age_start=AGE_START, age_end=AGE_END)
base_surv = build_lockwood_survival(p_base)
@printf("  Male (Lockwood/SSA 2003) table loaded (q65 = %.5f)\n",
        1.0 - base_surv[1]); flush(stdout)

hrs_raw = readdlm(HRS_PATH, ',', Any; skipstart=1)
has_health = assert_hrs_schema(hrs_raw, HRS_PATH)
n_pop = size(hrs_raw, 1)
population = zeros(n_pop, 4)
population[:, 1] = Float64.(hrs_raw[:, 1]); population[:, 2] .= 0.0
population[:, 3] = Float64.(hrs_raw[:, 3])
population[:, 4] = has_health ? Float64.(hrs_raw[:, 4]) : fill(2.0, n_pop)

gkw = (n_wealth=N_WEALTH, n_annuity=N_ANNUITY, n_alpha=N_ALPHA, W_max=W_MAX,
       age_start=AGE_START, age_end=AGE_END, annuity_grid_power=A_GRID_POW)
fair     = compute_payout_rate(ModelParams(; gamma=GAMMA, beta=BETA, r=R_RATE, mwr=1.0, gkw...), base_surv)
fair_nom = INFLATION > 0 ? compute_payout_rate(ModelParams(; gamma=GAMMA, beta=BETA, r=R_RATE, mwr=1.0, inflation_rate=INFLATION, gkw...), base_surv) : fair
@printf("  Fair payout (male table): real %.5f, nominal %.5f\n", fair, fair_nom)

_theta=THETA_DFJ; _kappa=KAPPA_DFJ; _mwr=MWR_LOADED; _fc=FIXED_COST; _minp=MIN_PURCHASE
_infl=INFLATION; _ssq=Float64.(SS_QUARTILE_LEVELS); _gamma=GAMMA; _beta=BETA; _r=R_RATE
_cf=C_FLOOR; _hm=Float64.(HAZARD_MULT); _nq=N_QUAD; _cd=CONSUMPTION_DECLINE
_hu=Float64.(HEALTH_UTILITY); _chi=CHI_LTC; _lw=LAMBDA_W; _pp=PSI_PURCHASE; _ppc=PSI_PURCHASE_C_REF
_psi=SURVIVAL_PESSIMISM
_bs=base_surv; _pop=population; _fair=fair; _fairn=fair_nom; _minw=MIN_WEALTH; _gkw=gkw

println("Solving 512 nine-channel subsets under the prior mortality convention..."); flush(stdout)
t0 = time()
results = parallel_solve([(m=m,) for m in 0:511]) do spec
    mask = spec.m
    cfg = build_subset_config(bitmask_to_channels(mask);
        theta_dfj=_theta, kappa_dfj=_kappa, mwr_loaded=_mwr, fixed_cost=_fc,
        min_purchase=_minp, inflation_val=_infl, survival_pessimism=_psi,
        ss_quartile_levels=_ssq, consumption_decline=_cd, health_utility=_hu,
        chi_ltc_val=_chi, lambda_w_val=_lw, psi_purchase_val=_pp, psi_purchase_c_ref_val=_ppc)
    has_loads = cfg.mwr < 1.0; has_infl = cfg.inflation_rate > 0
    pr = has_loads && has_infl ? cfg.mwr * _fairn : has_loads ? cfg.mwr * _fair : has_infl ? _fairn : _fair
    common = (gamma=_gamma, beta=_beta, r=_r, stochastic_health=true, n_health_states=3,
              n_quad=_nq, c_floor=_cf, hazard_mult=_hm,
              hazard_normalize=false)  # prior convention by design
    grids = build_grids(ModelParams(; common..., mwr=1.0, _gkw...), max(_fair, _fairn))
    p = ModelParams(; common..., theta=cfg.theta, kappa=cfg.kappa, mwr=cfg.mwr,
        fixed_cost=cfg.fixed_cost, min_purchase=cfg.min_purchase, inflation_rate=cfg.inflation_rate,
        medical_enabled=cfg.medical_enabled, health_mortality_corr=cfg.health_mortality_corr,
        survival_pessimism=cfg.survival_pessimism, consumption_decline=cfg.consumption_decline,
        health_utility=cfg.health_utility, chi_ltc=cfg.chi_ltc, _gkw...)
    pop = _minw > 0 ? _pop[_pop[:, 1] .>= _minw, :] : _pop
    res = solve_and_evaluate(p, grids, _bs, cfg.ss_levels, pop, pr; verbose=false)
    (mask=mask, ownership=res.ownership)
end
@printf("  done in %.0fs\n", time() - t0); flush(stdout)

lookup = Dict{Int,Float64}(r.mask => r.ownership for r in results)
shap = exact_shapley(N_CH, lookup)
order = sortperm(abs.(shap); rev=true)
@printf("\n  Male-table (unnormalized) Shapley (empty=%.2f%%, full=%.2f%%):\n",
        lookup[0] * 100, lookup[511] * 100)
@printf("  %-20s %12s\n", "Channel", "Shapley (pp)")
for i in order
    @printf("  %-20s %+11.2f\n", NAMES[i], shap[i] * 100)
end

csv = joinpath(@__DIR__, "..", "tables", "csv", "shapley_male_mortality.csv")
mkpath(dirname(csv))
open(csv, "w") do io
    println(io, "channel,shapley_value_pp,abs_rank,full_own_pct,empty_own_pct")
    rk = zeros(Int, N_CH); for (k, i) in enumerate(order); rk[i] = k; end
    for i in 1:N_CH
        @printf(io, "%s,%.4f,%d,%.4f,%.4f\n", NAMES[i], shap[i] * 100, rk[i],
                lookup[511] * 100, lookup[0] * 100)
    end
end
println("  CSV: $csv"); flush(stdout)

vord = sortperm(shap; rev=true)
texp = joinpath(@__DIR__, "..", "tables", "tex", "shapley_male_mortality.tex")
mkpath(dirname(texp))
open(texp, "w") do io
    println(io, raw"\begin{table}[htbp]")
    println(io, raw"\centering")
    println(io, raw"\caption{Nine-Channel Shapley Decomposition under the Prior Mortality Convention (Male Table, Unnormalized Hazards)}")
    println(io, raw"\label{tab:shapley_male}")
    println(io, raw"\begin{threeparttable}")
    println(io, raw"\begin{tabular}{lc}")
    println(io, raw"\toprule")
    println(io, raw"Channel & Shapley (pp) " * "\\\\")
    println(io, raw"\midrule")
    for i in vord
        @printf(io, "%s & %+.1f \\\\\n", NAMES[i], shap[i] * 100)
    end
    println(io, raw"\bottomrule")
    println(io, raw"\end{tabular}")
    println(io, raw"\begin{tablenotes}")
    println(io, raw"\small")
    println(io, raw"\item Exact Shapley values over all $2^{9}=512$ subsets under the prior mortality convention: the male SSA 2003 table used by \citet{lockwood2012}, with unnormalized health hazards, for both agent survival and annuity pricing. The headline game instead uses the sex-blended, aggregate-anchored table. All other channels and the production grid match the headline game. Positive values are demand-suppressing; pre-existing income is demand-raising.")
    println(io, raw"\end{tablenotes}")
    println(io, raw"\end{threeparttable}")
    println(io, raw"\end{table}")
end
println("  LaTeX: $texp"); flush(stdout)
