# Floor-on / floor-off robustness of the nine-channel Shapley ranking.
#
# The Medicaid consumption floor (C_FLOOR) is held fixed in every coalition,
# OUTSIDE the cooperative game. This recomputes the full nine-channel exact
# Shapley (512 subsets) at two floor settings -- the production floor and a
# near-zero floor -- to show the channel RANKING is invariant to it. Pricing
# loads and pre-existing annuitization (SS+DB) stay the top-two suppressors
# under both settings. A near-zero (rather than exactly zero) floor is used
# because CRRA flow utility diverges as c -> 0.
#
# The floor value travels with each subset spec (not a mutated global), so the
# two 512-subset games are one 1024-element parallel map. The SS player is built
# exactly as in run_subset_enumeration.jl: a per-household commuted-PV top-up is
# precomputed once and threaded as wealth_topup_hh whenever a coalition omits SS.
#
# Coarse-grid smoke: ANNUITY_SMOKE=1 shrinks the grid and subsamples the
# population for a fast structural check; production uses the config grid.
#
# Output: tables/csv/floor_robustness_shapley.csv (floor_setting, channel,
#         shapley_pp, rank), tables/tex/floor_robustness_shapley.tex
# Usage:  julia --project=. -p 8 scripts/run_floor_robustness.jl
#         ANNUITY_SMOKE=1 julia --project=. -p 4 scripts/run_floor_robustness.jl

using Printf, DelimitedFiles, Distributed

if nworkers() > 1
    @everywhere include(joinpath(@__DIR__, "..", "src", "AnnuityPuzzle.jl"))
    @everywhere using .AnnuityPuzzle
else
    include(joinpath(@__DIR__, "..", "src", "AnnuityPuzzle.jl"))
    using .AnnuityPuzzle
end
include(joinpath(@__DIR__, "config.jl"))

const N_CH  = 9
const NAMES = ["SS", "Bequests", "Medical+R-S", "Pessimism", "Age needs",
               "State utility", "Loads", "Inflation", "LTC"]

const SMOKE = get(ENV, "ANNUITY_SMOKE", "0") == "1"
const NW  = SMOKE ? 16 : N_WEALTH
const NA  = SMOKE ?  8 : N_ANNUITY
const NAL = SMOKE ? 15 : N_ALPHA
const NQ  = SMOKE ?  5 : N_QUAD
const SMOKE_POP = 200

# Near-zero floor stands in for "floor off" (CRRA utility diverges at c=0).
const FLOOR_SETTINGS = [("floor_on", C_FLOOR), ("floor_off", 1.0)]

println("=" ^ 70)
println("  FLOOR-ON / FLOOR-OFF ROBUSTNESS: nine-channel exact Shapley (2 x 512)")
SMOKE && println("  [SMOKE] coarse grid $(NW)x$(NA)x$(NAL), n_quad=$(NQ), subsampled population")
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
gkw = (n_wealth=NW, n_annuity=NA, n_alpha=NAL, W_max=W_MAX, age_start=AGE_START,
       age_end=AGE_END, annuity_grid_power=A_GRID_POW)
fair     = compute_payout_rate(ModelParams(; gamma=GAMMA, beta=BETA, r=R_RATE, mwr=1.0, gkw...), base_surv)
fair_nom = INFLATION > 0 ? compute_payout_rate(ModelParams(; gamma=GAMMA, beta=BETA, r=R_RATE, mwr=1.0, inflation_rate=INFLATION, gkw...), base_surv) : fair

# Filter to the model-eligible population ONCE so the per-household commuted-PV
# top-up aligns 1:1 (worker's own min-wealth filter then keeps every row).
if MIN_WEALTH > 0.0
    population = population[population[:, 1] .>= MIN_WEALTH, :]
end
if SMOKE
    stride = max(1, size(population, 1) ÷ SMOKE_POP)
    population = population[1:stride:end, :]
    @printf("  [SMOKE] subsampled to %d households\n", size(population, 1)); flush(stdout)
end
p_topup = ModelParams(; gamma=GAMMA, beta=BETA, r=R_RATE, mwr=1.0, inflation_rate=INFLATION, gkw...)
topup_vec = commuted_topup_vector(population, base_surv, p_topup)

_theta=THETA_DFJ; _kappa=KAPPA_DFJ; _mwr=MWR_LOADED; _fc=FIXED_COST; _minp=MIN_PURCHASE
_infl=INFLATION; _ssq=Float64.(SS_QUARTILE_LEVELS); _gamma=GAMMA; _beta=BETA; _r=R_RATE
_hm=Float64.(HAZARD_MULT); _hn=HAZARD_NORMALIZE; _nq=NQ; _cd=CONSUMPTION_DECLINE
_hu=Float64.(HEALTH_UTILITY); _chi=CHI_LTC; _lw=LAMBDA_W; _pp=PSI_PURCHASE; _ppc=PSI_PURCHASE_C_REF
_pess=SURVIVAL_PESSIMISM
_bs=base_surv; _pop=population; _fair=fair; _fairn=fair_nom; _minw=MIN_WEALTH; _gkw=gkw
_topup_vec=topup_vec; _db=Float64.(DB_OBS)

specs = [(m=m, cf=cf, tag=tag) for (tag, cf) in FLOOR_SETTINGS for m in 0:(2^N_CH - 1)]
println("\nSolving $(length(specs)) subsets ($(length(FLOOR_SETTINGS)) floor settings x 512)..."); flush(stdout)
t0 = time()
results = parallel_solve(specs) do spec
    mask = spec.m
    cfg = build_subset_config(bitmask_to_channels(mask);
        theta_dfj=_theta, kappa_dfj=_kappa, mwr_loaded=_mwr, fixed_cost=_fc,
        min_purchase=_minp, inflation_val=_infl, survival_pessimism=_pess,
        ss_quartile_levels=_ssq, consumption_decline=_cd, health_utility=_hu,
        chi_ltc_val=_chi, lambda_w_val=_lw, psi_purchase_val=_pp, psi_purchase_c_ref_val=_ppc,
        db_levels=_db)
    has_loads = cfg.mwr < 1.0; has_infl = cfg.inflation_rate > 0
    pr = has_loads && has_infl ? cfg.mwr * _fairn : has_loads ? cfg.mwr * _fair : has_infl ? _fairn : _fair
    common = (gamma=_gamma, beta=_beta, r=_r, stochastic_health=true, n_health_states=3,
              n_quad=_nq, c_floor=spec.cf, hazard_mult=_hm, hazard_normalize=_hn)
    grids = build_grids(ModelParams(; common..., mwr=1.0, _gkw...), max(_fair, _fairn))
    p = ModelParams(; common..., theta=cfg.theta, kappa=cfg.kappa, mwr=cfg.mwr,
        fixed_cost=cfg.fixed_cost, min_purchase=cfg.min_purchase, inflation_rate=cfg.inflation_rate,
        medical_enabled=cfg.medical_enabled, health_mortality_corr=cfg.health_mortality_corr,
        survival_pessimism=cfg.survival_pessimism, consumption_decline=cfg.consumption_decline,
        health_utility=cfg.health_utility, chi_ltc=cfg.chi_ltc, _gkw...)
    pop = _minw > 0 ? _pop[_pop[:, 1] .>= _minw, :] : _pop
    res = solve_and_evaluate(p, grids, _bs, cfg.ss_levels, pop, pr; verbose=false,
        wealth_topup_hh = cfg.commute_ss ? _topup_vec : nothing, db_levels=cfg.db_levels)
    (tag=spec.tag, mask=mask, ownership=res.ownership)
end
@printf("  done in %.0fs\n", time() - t0); flush(stdout)

# One lookup + Shapley per floor setting; rank by value descending (rank 1 =
# strongest suppressor, so the demand-raising channels sort to the bottom).
shap_by_tag = Dict{String, Vector{Float64}}()
rank_by_tag = Dict{String, Vector{Int}}()
full_by_tag = Dict{String, Float64}()
for (tag, _) in FLOOR_SETTINGS
    lookup = Dict{Int,Float64}(r.mask => r.ownership for r in results if r.tag == tag)
    shap = exact_shapley(N_CH, lookup)
    rk = zeros(Int, N_CH)
    for (k, i) in enumerate(sortperm(shap; rev=true)); rk[i] = k; end
    shap_by_tag[tag] = shap; rank_by_tag[tag] = rk; full_by_tag[tag] = lookup[2^N_CH - 1]
end

for (tag, cf) in FLOOR_SETTINGS
    shap = shap_by_tag[tag]; rk = rank_by_tag[tag]
    @printf("\n  %s (c_floor=\$%.0f, full-model own=%.1f%%):\n", tag, cf, full_by_tag[tag] * 100)
    @printf("  %-14s %12s %6s\n", "Channel", "Shapley (pp)", "rank")
    for i in sortperm(shap; rev=true)
        @printf("  %-14s %+11.2f %6d\n", NAMES[i], shap[i] * 100, rk[i])
    end
end

# Ranking-invariance summary: the top-two suppressors should be {Loads, SS}
# under both floor settings.
top2 = Dict(tag => Set(findall(i -> rank_by_tag[tag][i] <= 2, 1:N_CH)) for (tag, _) in FLOOR_SETTINGS)
loads_ss = Set([findfirst(==("Loads"), NAMES), findfirst(==("SS"), NAMES)])
@printf("\n  Top-two suppressors == {Loads, SS+DB} under both floors: %s\n",
    all(top2[tag] == loads_ss for (tag, _) in FLOOR_SETTINGS) ? "YES" : "NO")
flush(stdout)

csvdir = joinpath(@__DIR__, "..", "tables", "csv"); mkpath(csvdir)
csv = joinpath(csvdir, "floor_robustness_shapley.csv")
open(csv, "w") do io
    println(io, "floor_setting,channel,shapley_pp,rank")
    for (tag, _) in FLOOR_SETTINGS
        for i in 1:N_CH
            @printf(io, "%s,%s,%.4f,%d\n", tag, NAMES[i], shap_by_tag[tag][i] * 100, rank_by_tag[tag][i])
        end
    end
end
println("  CSV: $csv"); flush(stdout)

texdir = joinpath(@__DIR__, "..", "tables", "tex"); mkpath(texdir)
texp = joinpath(texdir, "floor_robustness_shapley.tex")
open(texp, "w") do io
    println(io, raw"\begin{table}[htbp]")
    println(io, raw"\centering")
    println(io, raw"\caption{Nine-Channel Shapley Ranking Under the Consumption Floor On and Off}")
    println(io, raw"\label{tab:floor_robustness_shapley}")
    println(io, raw"\begin{threeparttable}")
    println(io, raw"\begin{tabular}{lcccc}")
    println(io, raw"\toprule")
    println(io, raw" & \multicolumn{2}{c}{Floor on} & \multicolumn{2}{c}{Floor off} " * "\\\\")
    println(io, raw"\cmidrule(lr){2-3}\cmidrule(lr){4-5}")
    println(io, raw"Channel & Shapley (pp) & Rank & Shapley (pp) & Rank " * "\\\\")
    println(io, raw"\midrule")
    on = shap_by_tag["floor_on"]; ron = rank_by_tag["floor_on"]
    off = shap_by_tag["floor_off"]; roff = rank_by_tag["floor_off"]
    for i in sortperm(on; rev=true)
        disp = NAMES[i] == "SS" ? "Pre-existing annuitization (SS+DB)" : NAMES[i]
        @printf(io, "%s & %+.1f & %d & %+.1f & %d \\\\\n", disp, on[i]*100, ron[i], off[i]*100, roff[i])
    end
    println(io, raw"\bottomrule")
    println(io, raw"\end{tabular}")
    println(io, raw"\begin{tablenotes}")
    println(io, raw"\small")
    @printf(io, "\\item Exact Shapley values over all \$2^{9}=512\$ subsets of the nine-channel game, computed with the Medicaid consumption floor at its production value (\\\$%.0f) and at a near-zero value (\\\$1). ", C_FLOOR)
    println(io, "The Medicaid consumption floor is fixed in every coalition, outside the nine-channel game; this exhibit recomputes the exact Shapley attribution with the floor at its production level and near zero, to show how much the ranking is conditional on the safety net. Rank~1 is the strongest suppressor. Positive values are demand-suppressing. The two floor settings are reported side by side; the manuscript reads the actual reordering from the values below.")
    println(io, raw"\end{tablenotes}")
    println(io, raw"\end{threeparttable}")
    println(io, raw"\end{table}")
end
println("  LaTeX: $texp"); flush(stdout)
