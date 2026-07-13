# Loads-split exact Shapley: the bundled pricing-loads channel decomposed into
# its three components as separate players — the money's-worth wedge
# (MWR = 0.87 vs 1.0), the fixed purchase cost, and the minimum-purchase
# requirement — giving an 11-player game over the eight remaining structural
# channels plus the three loads sub-channels (2^11 = 2048 subsets).
#
# The bundled game cannot say which loads component carries the channel's
# Shapley value; this game can. The full mask reproduces the nine-channel
# full model exactly (same configuration reached through a finer partition),
# and the empty mask is the frictionless benchmark.
#
# Production grid: the result is quoted next to the headline decomposition.
# Output: tables/csv/shapley_loads_split.csv, tables/tex/shapley_loads_split.tex
# Usage:  julia --project=. -p 90 scripts/run_loads_split_shapley.jl
#         ANNUITY_SPLIT_SMOKE=1 julia --project=. -p 8 scripts/run_loads_split_shapley.jl
#         (smoke: coarse-grid 3-player sub-game over the loads bits with all
#          other channels on; prints only, writes nothing)

using Printf, DelimitedFiles, Distributed

if nworkers() > 1
    @everywhere include(joinpath(@__DIR__, "..", "src", "AnnuityPuzzle.jl"))
    @everywhere using .AnnuityPuzzle
else
    include(joinpath(@__DIR__, "..", "src", "AnnuityPuzzle.jl"))
    using .AnnuityPuzzle
end
include(joinpath(@__DIR__, "config.jl"))

const SMOKE = get(ENV, "ANNUITY_SPLIT_SMOKE", "0") == "1"

# Player order for THIS game (bit i-1 <-> player i):
#   1 SS, 2 Bequests, 3 Medical+R-S, 4 Pessimism, 5 Age needs, 6 State utility,
#   7 MWR wedge, 8 Fixed cost, 9 Min purchase, 10 Inflation, 11 LTC
const N_CH = 11
const NAMES = ["SS", "Bequests", "Medical+R-S", "Pessimism", "Age needs",
               "State utility", "MWR wedge", "Fixed cost", "Min purchase",
               "Inflation", "Public-care (LTC)"]

# Map split-game players onto the module's channel indices for
# build_subset_config. Players 1-6 coincide with module channels 1-6;
# module CH_LOADS (7) is never activated — the three loads components are
# applied as explicit overrides. Players 10/11 map to module channels 8/9.
const PLAYER_TO_MODULE = Dict(1=>1, 2=>2, 3=>3, 4=>4, 5=>5, 6=>6, 10=>8, 11=>9)

split_bit(mask::Int, player::Int) = (mask >> (player - 1)) & 1 == 1

function split_active_set(mask::Int)
    active = Set{Int}()
    for (player, ch) in PLAYER_TO_MODULE
        split_bit(mask, player) && push!(active, ch)
    end
    return active
end

println("=" ^ 70)
println("  LOADS-SPLIT EXACT SHAPLEY (11 players, 2^11 = 2048 subsets)")
SMOKE && println("  SMOKE MODE: 3-player loads sub-game, coarse grid, prints only")
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
NW = SMOKE ? 40 : N_WEALTH
NA = SMOKE ? 15 : N_ANNUITY
NAL = SMOKE ? 51 : N_ALPHA
gkw = (n_wealth=NW, n_annuity=NA, n_alpha=NAL, W_max=W_MAX, age_start=AGE_START,
       age_end=AGE_END, annuity_grid_power=A_GRID_POW)
fair     = compute_payout_rate(ModelParams(; gamma=GAMMA, beta=BETA, r=R_RATE, mwr=1.0, gkw...), base_surv)
fair_nom = INFLATION > 0 ? compute_payout_rate(ModelParams(; gamma=GAMMA, beta=BETA, r=R_RATE, mwr=1.0, inflation_rate=INFLATION, gkw...), base_surv) : fair

_theta=THETA_DFJ; _kappa=KAPPA_DFJ; _mwr=MWR_LOADED; _fc=FIXED_COST; _minp=MIN_PURCHASE
_infl=INFLATION; _ssq=Float64.(SS_QUARTILE_LEVELS); _gamma=GAMMA; _beta=BETA; _r=R_RATE
_cf=C_FLOOR; _hm=Float64.(HAZARD_MULT); _hn=HAZARD_NORMALIZE; _nq=N_QUAD; _cd=CONSUMPTION_DECLINE
_hu=Float64.(HEALTH_UTILITY); _chi=CHI_LTC; _lw=LAMBDA_W; _pp=PSI_PURCHASE; _ppc=PSI_PURCHASE_C_REF
_psi=SURVIVAL_PESSIMISM
_bs=base_surv; _pop=population; _fair=fair; _fairn=fair_nom; _minw=MIN_WEALTH; _gkw=gkw
_p2m = PLAYER_TO_MODULE

# Smoke: only the 8 masks that vary the three loads bits with everything
# else on — a complete 3-player sub-game conditional on the other channels.
masks = collect(0:2047)
if SMOKE
    # Int literals throughout: 0b111 is UInt8 and (0b111 << 6) truncates.
    base_others = 63 | (1 << 9) | (1 << 10)  # players 1-6, 10, 11 on; 7-9 off
    masks = [base_others | (l << 6) for l in 0:7]
end

@printf("Solving %d subsets (grid %dx%dx%d)...\n", length(masks), NW, NA, NAL); flush(stdout)
t0 = time()
results = parallel_solve([(m=m,) for m in masks]) do spec
    mask = spec.m
    # Helpers inlined so the closure ships only captured values to workers
    # (script-local functions are not defined on worker processes).
    active = Set{Int}()
    for (player, ch) in _p2m
        ((mask >> (player - 1)) & 1 == 1) && push!(active, ch)
    end
    cfg = build_subset_config(active;
        theta_dfj=_theta, kappa_dfj=_kappa, mwr_loaded=_mwr, fixed_cost=_fc,
        min_purchase=_minp, inflation_val=_infl, survival_pessimism=_psi,
        ss_quartile_levels=_ssq, consumption_decline=_cd, health_utility=_hu,
        chi_ltc_val=_chi, lambda_w_val=_lw, psi_purchase_val=_pp, psi_purchase_c_ref_val=_ppc,
        fair_pr=_fair)
    # Loads components applied individually; only the MWR wedge touches the
    # payout rate.
    mwr_use  = ((mask >> 6) & 1 == 1) ? _mwr  : 1.0
    fc_use   = ((mask >> 7) & 1 == 1) ? _fc   : 0.0
    minp_use = ((mask >> 8) & 1 == 1) ? _minp : 0.0
    has_wedge = mwr_use < 1.0; has_infl = cfg.inflation_rate > 0
    pr = has_wedge && has_infl ? mwr_use * _fairn :
         has_wedge             ? mwr_use * _fair  :
         has_infl              ? _fairn           : _fair
    common = (gamma=_gamma, beta=_beta, r=_r, stochastic_health=true, n_health_states=3,
              n_quad=_nq, c_floor=_cf, hazard_mult=_hm, hazard_normalize=_hn)
    grids = build_grids(ModelParams(; common..., mwr=1.0, _gkw...), max(_fair, _fairn))
    p = ModelParams(; common..., theta=cfg.theta, kappa=cfg.kappa, mwr=mwr_use,
        fixed_cost=fc_use, min_purchase=minp_use, inflation_rate=cfg.inflation_rate,
        medical_enabled=cfg.medical_enabled, health_mortality_corr=cfg.health_mortality_corr,
        survival_pessimism=cfg.survival_pessimism, consumption_decline=cfg.consumption_decline,
        health_utility=cfg.health_utility, chi_ltc=cfg.chi_ltc, _gkw...)
    pop = _minw > 0 ? _pop[_pop[:, 1] .>= _minw, :] : _pop
    res = solve_and_evaluate(p, grids, _bs, cfg.ss_levels, pop, pr; verbose=false,
        wealth_topup=cfg.w_commuted)
    (mask=mask, ownership=res.ownership)
end
@printf("  done in %.0fs\n", time() - t0); flush(stdout)

lookup = Dict{Int,Float64}(r.mask => r.ownership for r in results)

if SMOKE
    # Conditional 3-player game over the loads bits (others fixed on).
    base_others = masks[1] & ~(7 << 6)
    sub = Dict{Int,Float64}(l => lookup[base_others | (l << 6)] for l in 0:7)
    shap3 = exact_shapley(3, sub)
    @printf("\n  Conditional loads sub-game (others on): empty=%.2f%% full=%.2f%%\n",
            sub[0] * 100, sub[7] * 100)
    for (i, nm) in enumerate(["MWR wedge", "Fixed cost", "Min purchase"])
        @printf("  %-14s %+8.2f pp\n", nm, shap3[i] * 100)
    end
    println("\n  Smoke complete (nothing written).")
else
    shap = exact_shapley(N_CH, lookup)
    order = sortperm(abs.(shap); rev=true)
    @printf("\n  Loads-split Shapley (empty=%.2f%%, full=%.2f%%):\n",
            lookup[0] * 100, lookup[2047] * 100)
    @printf("  %-20s %12s\n", "Channel", "Shapley (pp)")
    for i in order
        @printf("  %-20s %+11.2f\n", NAMES[i], shap[i] * 100)
    end
    loads_sum = (shap[7] + shap[8] + shap[9]) * 100
    @printf("\n  Loads components sum: %+.2f pp (bundled game value differs by\n", loads_sum)
    println("  construction; Shapley values are not additive across game partitions).")

    csv = joinpath(@__DIR__, "..", "tables", "csv", "shapley_loads_split.csv")
mkpath(dirname(csv))
    open(csv, "w") do io
        println(io, "channel,shapley_value_pp,abs_rank,full_own_pct,empty_own_pct")
        rk = zeros(Int, N_CH); for (k, i) in enumerate(order); rk[i] = k; end
        for i in 1:N_CH
            @printf(io, "%s,%.4f,%d,%.4f,%.4f\n", NAMES[i], shap[i] * 100, rk[i],
                    lookup[2047] * 100, lookup[0] * 100)
        end
    end
    println("  CSV: $csv"); flush(stdout)

    vord = sortperm(shap; rev=true)
    texp = joinpath(@__DIR__, "..", "tables", "tex", "shapley_loads_split.tex")
mkpath(dirname(texp))
    open(texp, "w") do io
        println(io, raw"\begin{table}[htbp]")
        println(io, raw"\centering")
        println(io, raw"\caption{Loads-Split Shapley Decomposition (11 Players, 2{,}048 Subsets)}")
        println(io, raw"\label{tab:shapley_loads_split}")
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
        println(io, raw"\item Exact Shapley values over all $2^{11} = 2{,}048$ subsets of the game that replaces the bundled pricing-loads channel with its three components as separate players: the money's-worth wedge (MWR $=$ baseline vs.\ $1.0$; the only component that changes the payout rate), the fixed purchase cost, and the minimum-purchase requirement. All other channels and the production grid match the nine-channel headline game; the full coalition reproduces the nine-channel full model. Shapley values are not additive across game partitions, so the three components need not sum to the bundled channel's value. Positive values are demand-suppressing.")
        println(io, raw"\end{tablenotes}")
        println(io, raw"\end{threeparttable}")
        println(io, raw"\end{table}")
    end
    println("  LaTeX: $texp"); flush(stdout)
end
