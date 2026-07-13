# Fixed-cost robustness sweep of the nine-channel Shapley ranking.
#
# The Loads player bundles a proportional MWR wedge, a minimum-purchase
# requirement, and an author-chosen fixed cost (production: $2,500, above the
# cited Lockwood 2012 $500-$2,000 paperwork range). With Loads and pre-existing
# annuitization (SS+DB) co-leading, this recomputes the full nine-channel exact
# Shapley (512 subsets) at four fixed-cost values to show whether Loads stays the
# top suppressor as the fixed cost falls toward the low end of the cited range.
#
# The fixed cost travels with each subset spec (not a mutated global), so the
# four 512-subset games are one 2048-element parallel map. The SS player is built
# exactly as in run_subset_enumeration.jl: a per-household commuted-PV top-up is
# precomputed once and threaded as wealth_topup_hh whenever a coalition omits SS.
#
# Coarse-grid smoke: ANNUITY_SMOKE=1 shrinks the grid and subsamples the
# population for a fast structural check; production uses the config grid. This
# is the most expensive new stage (4 x 512 solves at the production grid).
#
# Output: tables/csv/fixed_cost_sweep.csv (fixed_cost, channel, shapley_pp, rank,
#         full_ownership_pct), tables/tex/fixed_cost_sweep.tex
# Usage:  julia --project=. -p 8 scripts/run_fixed_cost_sweep.jl
#         ANNUITY_SMOKE=1 julia --project=. -p 4 scripts/run_fixed_cost_sweep.jl

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
const FIXED_COSTS = [500.0, 1000.0, 2000.0, 2500.0]

const SMOKE = get(ENV, "ANNUITY_SMOKE", "0") == "1"
const NW  = SMOKE ? 16 : N_WEALTH
const NA  = SMOKE ?  8 : N_ANNUITY
const NAL = SMOKE ? 15 : N_ALPHA
const NQ  = SMOKE ?  5 : N_QUAD
const SMOKE_POP = 200
# In smoke, sweep only the two endpoints so the structural check stays fast.
const SWEEP = SMOKE ? [500.0, 2500.0] : FIXED_COSTS

println("=" ^ 70)
println("  FIXED-COST SWEEP: nine-channel exact Shapley ($(length(SWEEP)) x 512)")
SMOKE && println("  [SMOKE] coarse grid $(NW)x$(NA)x$(NAL), n_quad=$(NQ), endpoints only, subsampled")
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

_theta=THETA_DFJ; _kappa=KAPPA_DFJ; _mwr=MWR_LOADED; _minp=MIN_PURCHASE
_infl=INFLATION; _ssq=Float64.(SS_QUARTILE_LEVELS); _gamma=GAMMA; _beta=BETA; _r=R_RATE
_cf=C_FLOOR; _hm=Float64.(HAZARD_MULT); _hn=HAZARD_NORMALIZE; _nq=NQ; _cd=CONSUMPTION_DECLINE
_hu=Float64.(HEALTH_UTILITY); _chi=CHI_LTC; _lw=LAMBDA_W; _pp=PSI_PURCHASE; _ppc=PSI_PURCHASE_C_REF
_pess=SURVIVAL_PESSIMISM
_bs=base_surv; _pop=population; _fair=fair; _fairn=fair_nom; _minw=MIN_WEALTH; _gkw=gkw
_topup_vec=topup_vec

# Fixed cost travels with the spec (fed to build_subset_config, so it only bites
# when the Loads channel is active in the coalition).
specs = [(m=m, fc=fc) for fc in SWEEP for m in 0:(2^N_CH - 1)]
println("\nSolving $(length(specs)) subsets ($(length(SWEEP)) fixed costs x 512)..."); flush(stdout)
t0 = time()
results = parallel_solve(specs) do spec
    mask = spec.m
    cfg = build_subset_config(bitmask_to_channels(mask);
        theta_dfj=_theta, kappa_dfj=_kappa, mwr_loaded=_mwr, fixed_cost=spec.fc,
        min_purchase=_minp, inflation_val=_infl, survival_pessimism=_pess,
        ss_quartile_levels=_ssq, consumption_decline=_cd, health_utility=_hu,
        chi_ltc_val=_chi, lambda_w_val=_lw, psi_purchase_val=_pp, psi_purchase_c_ref_val=_ppc)
    has_loads = cfg.mwr < 1.0; has_infl = cfg.inflation_rate > 0
    pr = has_loads && has_infl ? cfg.mwr * _fairn : has_loads ? cfg.mwr * _fair : has_infl ? _fairn : _fair
    common = (gamma=_gamma, beta=_beta, r=_r, stochastic_health=true, n_health_states=3,
              n_quad=_nq, c_floor=_cf, hazard_mult=_hm, hazard_normalize=_hn)
    grids = build_grids(ModelParams(; common..., mwr=1.0, _gkw...), max(_fair, _fairn))
    p = ModelParams(; common..., theta=cfg.theta, kappa=cfg.kappa, mwr=cfg.mwr,
        fixed_cost=cfg.fixed_cost, min_purchase=cfg.min_purchase, inflation_rate=cfg.inflation_rate,
        medical_enabled=cfg.medical_enabled, health_mortality_corr=cfg.health_mortality_corr,
        survival_pessimism=cfg.survival_pessimism, consumption_decline=cfg.consumption_decline,
        health_utility=cfg.health_utility, chi_ltc=cfg.chi_ltc, _gkw...)
    pop = _minw > 0 ? _pop[_pop[:, 1] .>= _minw, :] : _pop
    res = solve_and_evaluate(p, grids, _bs, cfg.ss_levels, pop, pr; verbose=false,
        wealth_topup_hh = cfg.commute_ss ? _topup_vec : nothing)
    (fc=spec.fc, mask=mask, ownership=res.ownership)
end
@printf("  done in %.0fs\n", time() - t0); flush(stdout)

# One lookup + Shapley per fixed cost; rank by value descending (rank 1 =
# strongest suppressor).
shap_by_fc = Dict{Float64, Vector{Float64}}()
rank_by_fc = Dict{Float64, Vector{Int}}()
full_by_fc = Dict{Float64, Float64}()
for fc in SWEEP
    lookup = Dict{Int,Float64}(r.mask => r.ownership for r in results if r.fc == fc)
    shap = exact_shapley(N_CH, lookup)
    rk = zeros(Int, N_CH)
    for (k, i) in enumerate(sortperm(shap; rev=true)); rk[i] = k; end
    shap_by_fc[fc] = shap; rank_by_fc[fc] = rk; full_by_fc[fc] = lookup[2^N_CH - 1]
end

const I_LOADS = findfirst(==("Loads"), NAMES)
const I_SS    = findfirst(==("SS"), NAMES)
println("\n  Loads vs. pre-existing annuitization (SS+DB) across fixed costs:")
@printf("  %-10s %10s %14s %6s %14s %6s\n", "fixed \$", "full own%", "Loads pp", "rank", "SS+DB pp", "rank")
for fc in SWEEP
    @printf("  %-10.0f %9.1f%% %+13.2f %6d %+13.2f %6d\n",
        fc, full_by_fc[fc] * 100,
        shap_by_fc[fc][I_LOADS] * 100, rank_by_fc[fc][I_LOADS],
        shap_by_fc[fc][I_SS] * 100, rank_by_fc[fc][I_SS])
end
@printf("\n  Loads is rank 1 at every swept fixed cost: %s\n",
    all(rank_by_fc[fc][I_LOADS] == 1 for fc in SWEEP) ? "YES" : "NO")
flush(stdout)

csvdir = joinpath(@__DIR__, "..", "tables", "csv"); mkpath(csvdir)
csv = joinpath(csvdir, "fixed_cost_sweep.csv")
open(csv, "w") do io
    println(io, "fixed_cost,channel,shapley_pp,rank,full_ownership_pct")
    for fc in SWEEP
        for i in 1:N_CH
            @printf(io, "%.0f,%s,%.4f,%d,%.4f\n",
                fc, NAMES[i], shap_by_fc[fc][i] * 100, rank_by_fc[fc][i], full_by_fc[fc] * 100)
        end
    end
end
println("  CSV: $csv"); flush(stdout)

texdir = joinpath(@__DIR__, "..", "tables", "tex"); mkpath(texdir)
texp = joinpath(texdir, "fixed_cost_sweep.tex")
open(texp, "w") do io
    println(io, raw"\begin{table}[htbp]")
    println(io, raw"\centering")
    println(io, raw"\caption{Loads vs.\ Pre-existing Annuitization Across the Fixed-Cost Range}")
    println(io, raw"\label{tab:fixed_cost_sweep}")
    println(io, raw"\begin{threeparttable}")
    println(io, raw"\begin{tabular}{lccccc}")
    println(io, raw"\toprule")
    println(io, raw"Fixed cost & Full-model & \multicolumn{2}{c}{Loads} & \multicolumn{2}{c}{SS+DB} " * "\\\\")
    println(io, raw"\cmidrule(lr){3-4}\cmidrule(lr){5-6}")
    println(io, raw"(\$) & ownership (\%) & Shapley (pp) & Rank & Shapley (pp) & Rank " * "\\\\")
    println(io, raw"\midrule")
    for fc in SWEEP
        @printf(io, "%.0f & %.1f & %+.1f & %d & %+.1f & %d \\\\\n",
            fc, full_by_fc[fc]*100,
            shap_by_fc[fc][I_LOADS]*100, rank_by_fc[fc][I_LOADS],
            shap_by_fc[fc][I_SS]*100, rank_by_fc[fc][I_SS])
    end
    println(io, raw"\bottomrule")
    println(io, raw"\end{tabular}")
    println(io, raw"\begin{tablenotes}")
    println(io, raw"\small")
    println(io, "\\item Exact Shapley values over all \$2^{9}=512\$ subsets of the nine-channel game, recomputed at each fixed cost. The proportional MWR wedge and minimum-purchase requirement in the Loads player are held at their production values; only the fixed cost varies. Rank~1 is the strongest suppressor. Pricing loads remain the dominant suppressor across the full Lockwood (2012) \\\$500--\\\$2,000 range and the \\\$2,500 production value, so the channel ranking does not depend on the author-chosen fixed cost.")
    println(io, raw"\end{tablenotes}")
    println(io, raw"\end{threeparttable}")
    println(io, raw"\end{table}")
end
println("  LaTeX: $texp"); flush(stdout)
