# Partition robustness for the exact-Shapley attribution.
#
# The headline nine-channel game bundles two pairs of mechanisms into single
# players: medical-expense risk with the Reichling-Smetters health-mortality
# correlation ("Med+R-S"), and Social Security with DB pension income into a
# single pre-existing-annuitized-income channel ("SS"). The Shapley value is
# order-independent but NOT partition-independent, so a referee can ask whether
# the dominant-channel ranking is an artifact of the bundling. This script
# recomputes the structural game under two alternative partitions and reports
# whether pricing loads remain rank 1 and bequests mid-pack:
#
#   Partition A (Med/R-S unbundled): medical risk and the R-S correlation enter
#     as two separate players (10-channel game, 2^10 = 1024 subsets).
#   Partition B (SS/DB split): Social Security income and DB pension income
#     enter as two separate players (10-channel game, 1024 subsets).
#
# Both use the production grid and calibration; the level is not the object,
# the ranking is. Output:
#   tables/csv/shapley_partition_medrs.csv
#   tables/csv/shapley_partition_ssdb.csv
#   tables/tex/partition_robustness.tex
#
# Usage: julia --project=. -p 90 scripts/run_partition_robustness.jl
#        PARTITION_SMOKE=1 julia --project=. scripts/run_partition_robustness.jl  (coarse grid)

using Printf
using DelimitedFiles
using Distributed

if nworkers() > 1
    @everywhere include(joinpath(@__DIR__, "..", "src", "AnnuityPuzzle.jl"))
    @everywhere using .AnnuityPuzzle
else
    include(joinpath(@__DIR__, "..", "src", "AnnuityPuzzle.jl"))
    using .AnnuityPuzzle
end

include(joinpath(@__DIR__, "config.jl"))

const SMOKE = get(ENV, "PARTITION_SMOKE", "0") == "1"
const NW  = SMOKE ? 40 : N_WEALTH
const NA  = SMOKE ? 15 : N_ANNUITY
const NAL = SMOKE ? 51 : N_ALPHA

println("=" ^ 70)
println("  PARTITION ROBUSTNESS: Med/R-S unbundled and SS/DB split")
SMOKE && println("  [SMOKE MODE: coarse $(NW)x$(NA)x$(NAL) grid]")
println("=" ^ 70)
flush(stdout)

# --- Population (same construction as the headline enumeration) ---
hrs_raw = readdlm(HRS_PATH, ',', Any; skipstart=1)
has_health = assert_hrs_schema(hrs_raw, HRS_PATH)
n_pop = size(hrs_raw, 1)
population = zeros(n_pop, 4)
population[:, 1] = Float64.(hrs_raw[:, 1])
population[:, 2] .= 0.0
population[:, 3] = Float64.(hrs_raw[:, 3])
population[:, 4] = has_health ? Float64.(hrs_raw[:, 4]) : fill(2.0, n_pop)
@printf("  Loaded %d individuals (health column: %s)\n", n_pop, has_health ? "observed" : "imputed")
flush(stdout)

# --- Survival and payout rates ---
p_base = ModelParams(age_start=AGE_START, age_end=AGE_END)
base_surv = production_base_survival(p_base)
grid_kw = (n_wealth=NW, n_annuity=NA, n_alpha=NAL, W_max=W_MAX,
           age_start=AGE_START, age_end=AGE_END, annuity_grid_power=A_GRID_POW)
fair_pr     = compute_payout_rate(ModelParams(; gamma=GAMMA, beta=BETA, r=R_RATE, mwr=1.0, grid_kw...), base_surv)
fair_pr_nom = INFLATION > 0 ?
    compute_payout_rate(ModelParams(; gamma=GAMMA, beta=BETA, r=R_RATE, mwr=1.0, inflation_rate=INFLATION, grid_kw...), base_surv) :
    fair_pr

# --- Config values captured for worker closures ---
_gamma=GAMMA; _beta=BETA; _r=R_RATE; _n_quad=N_QUAD; _c_floor=C_FLOOR
_hazard_mult=Float64.(HAZARD_MULT), hazard_normalize=HAZARD_NORMALIZE; _theta=THETA_DFJ; _kappa=KAPPA_DFJ
_mwr_loaded=MWR_LOADED; _fixed_cost=FIXED_COST; _min_purchase=MIN_PURCHASE
_inflation=INFLATION; _surv_pess=SURVIVAL_PESSIMISM
_consumption_decline=CONSUMPTION_DECLINE; _health_utility=Float64.(HEALTH_UTILITY)
_chi_ltc=CHI_LTC
_ss_comb=Float64.(SS_QUARTILE_LEVELS); _ss_obs=Float64.(SS_OBS); _db_obs=Float64.(DB_OBS)
_base_surv=base_surv; _population=population; _fair_pr=fair_pr; _fair_pr_nom=fair_pr_nom
_min_wealth=MIN_WEALTH
_nw=NW; _na=NA; _nal=NAL; _wmax=W_MAX; _agp=A_GRID_POW
_age_start=AGE_START; _age_end=AGE_END

const N_PART_CH = 10
const N_PART_SUBSETS = 2^N_PART_CH  # 1024

# Bit layouts (0-indexed bits):
#   Partition A (:medrs)  0 SS+DB, 1 Bequests, 2 Medical, 3 R-S corr, 4 Pessimism,
#                         5 Age needs, 6 State util, 7 Loads, 8 Inflation, 9 LTC
#   Partition B (:ssdb)   0 SS income, 1 DB income, 2 Bequests, 3 Med+R-S, 4 Pessimism,
#                         5 Age needs, 6 State util, 7 Loads, 8 Inflation, 9 LTC
const MEDRS_NAMES = ["SS+DB", "Bequests", "Medical", "R-S corr", "Pessimism",
                     "Age needs", "State util", "Loads", "Inflation", "LTC"]
const SSDB_NAMES  = ["SS income", "DB income", "Bequests", "Med+R-S", "Pessimism",
                     "Age needs", "State util", "Loads", "Inflation", "LTC"]

specs = vcat([(partition=:medrs, mask=m) for m in 0:(N_PART_SUBSETS - 1)],
             [(partition=:ssdb,  mask=m) for m in 0:(N_PART_SUBSETS - 1)])

println("\nSolving $(length(specs)) subsets ($(N_PART_SUBSETS) per partition)...")
flush(stdout)
t0 = time()

results = parallel_solve(specs) do spec
    part = spec.partition
    mask = spec.mask
    bit(i) = (mask >> i) & 1 == 1

    ss_levels = [0.0, 0.0, 0.0, 0.0]
    theta = 0.0; kappa = 0.0
    medical = false; corr = false
    psi = 1.0; cd = 0.0; hu = [1.0, 1.0, 1.0]
    mwr = 1.0; fc = 0.0; minp = 0.0; infl = 0.0; chi = 1.0

    if part == :medrs
        bit(0) && (ss_levels = copy(_ss_comb))
        bit(1) && (theta = _theta; kappa = _kappa)
        bit(2) && (medical = true)
        bit(3) && (corr = true)
        bit(4) && (psi = _surv_pess)
        bit(5) && (cd = _consumption_decline)
        bit(6) && (hu = copy(_health_utility))
        bit(7) && (mwr = _mwr_loaded; fc = _fixed_cost; minp = _min_purchase)
        bit(8) && (infl = _inflation)
        bit(9) && (chi = _chi_ltc)
    else  # :ssdb
        s = zeros(4)
        bit(0) && (s .+= _ss_obs)
        bit(1) && (s .+= _db_obs)
        ss_levels = s
        bit(2) && (theta = _theta; kappa = _kappa)
        bit(3) && (medical = true; corr = true)
        bit(4) && (psi = _surv_pess)
        bit(5) && (cd = _consumption_decline)
        bit(6) && (hu = copy(_health_utility))
        bit(7) && (mwr = _mwr_loaded; fc = _fixed_cost; minp = _min_purchase)
        bit(8) && (infl = _inflation)
        bit(9) && (chi = _chi_ltc)
    end

    has_loads = mwr < 1.0
    has_infl = infl > 0
    pr = has_loads && has_infl ? mwr * _fair_pr_nom :
         has_loads ? mwr * _fair_pr :
         has_infl ? _fair_pr_nom : _fair_pr

    gkw = (n_wealth=_nw, n_annuity=_na, n_alpha=_nal, W_max=_wmax,
           age_start=_age_start, age_end=_age_end, annuity_grid_power=_agp)
    common = (gamma=_gamma, beta=_beta, r=_r, stochastic_health=true,
              n_health_states=3, n_quad=_n_quad, c_floor=_c_floor,
              hazard_mult=_hazard_mult)

    grids = build_grids(ModelParams(; common..., mwr=1.0, gkw...),
                        max(_fair_pr, _fair_pr_nom))
    p = ModelParams(; common..., theta=theta, kappa=kappa, mwr=mwr,
        fixed_cost=fc, min_purchase=minp, inflation_rate=infl,
        medical_enabled=medical, health_mortality_corr=corr,
        survival_pessimism=psi, consumption_decline=cd, health_utility=hu,
        chi_ltc=chi, gkw...)

    pop = copy(_population)
    if _min_wealth > 0.0
        pop = pop[pop[:, 1] .>= _min_wealth, :]
    end

    res = solve_and_evaluate(p, grids, _base_surv, ss_levels, pop, pr;
                             step_name="", verbose=false)
    (partition=part, mask=mask, ownership=res.ownership)
end

@printf("  Solved %d subsets in %.0fs\n", length(specs), time() - t0)
flush(stdout)

# --- Build per-partition lookups and Shapley values ---
function shapley_table(part::Symbol, names::Vector{String})
    lookup = Dict{Int, Float64}()
    for r in results
        r.partition === part && (lookup[r.mask] = r.ownership)
    end
    shap = exact_shapley(N_PART_CH, lookup)
    yaari = lookup[0]
    full = lookup[N_PART_SUBSETS - 1]
    drop = yaari - full
    order = sortperm(shap; rev=true)
    rank = zeros(Int, N_PART_CH)
    for (k, idx) in enumerate(order); rank[idx] = k; end
    return (lookup=lookup, shap=shap, yaari=yaari, full=full, drop=drop,
            order=order, rank=rank, names=names)
end

tabs = Dict(:medrs => shapley_table(:medrs, MEDRS_NAMES),
            :ssdb  => shapley_table(:ssdb,  SSDB_NAMES))

for (part, label) in [(:medrs, "Partition A: Med/R-S unbundled"),
                      (:ssdb,  "Partition B: SS/DB split")]
    t = tabs[part]
    println("\n" * "-" ^ 60)
    @printf("  %s  (Yaari %.1f%% -> full %.1f%%, drop %.1f pp)\n",
            label, t.yaari * 100, t.full * 100, t.drop * 100)
    println("-" ^ 60)
    @printf("  %-12s  %12s  %6s\n", "Channel", "Shapley (pp)", "Rank")
    for i in t.order
        @printf("  %-12s  %+11.2f  %6d\n", t.names[i], t.shap[i] * 100, t.rank[i])
    end
    flush(stdout)
end

# --- Write CSVs ---
tables_dir = joinpath(@__DIR__, "..", "tables")
mkpath(joinpath(tables_dir, "csv"))
mkpath(joinpath(tables_dir, "tex"))

function write_csv(part::Symbol, fname::String)
    t = tabs[part]
    path = joinpath(tables_dir, "csv", fname)
    open(path, "w") do f
        println(f, "channel,shapley_value_pp,share_pct,rank")
        for i in 1:N_PART_CH
            share = t.drop > 0 ? t.shap[i] / t.drop * 100 : 0.0
            @printf(f, "%s,%.4f,%.2f,%d\n", t.names[i], t.shap[i] * 100, share, t.rank[i])
        end
    end
    println("  CSV written: $path")
end
write_csv(:medrs, "shapley_partition_medrs.csv")
write_csv(:ssdb,  "shapley_partition_ssdb.csv")

# --- Write combined LaTeX table ---
tex_path = joinpath(tables_dir, "tex", "partition_robustness.tex")
open(tex_path, "w") do f
    println(f, raw"\begin{table}[htbp]")
    println(f, raw"\centering")
    println(f, raw"\caption{Shapley Attribution Under Alternative Channel Partitions}")
    println(f, raw"\label{tab:partition_robustness}")
    println(f, raw"\begin{threeparttable}")
    println(f, raw"\begin{tabular}{lcc}")
    println(f, raw"\toprule")
    println(f, raw"Channel & Shapley (pp) & Rank " * "\\\\")
    println(f, raw"\midrule")
    let t = tabs[:medrs]
        println(f, raw"\multicolumn{3}{l}{\textit{Panel A: medical risk and R-S correlation unbundled}} " * "\\\\")
        for i in t.order
            @printf(f, "%s & %+.2f & %d \\\\\n", t.names[i], t.shap[i] * 100, t.rank[i])
        end
        println(f, raw"\midrule")
    end
    let t = tabs[:ssdb]
        println(f, raw"\multicolumn{3}{l}{\textit{Panel B: Social Security income and DB pension split}} " * "\\\\")
        for i in t.order
            @printf(f, "%s & %+.2f & %d \\\\\n", t.names[i], t.shap[i] * 100, t.rank[i])
        end
    end
    println(f, raw"\bottomrule")
    println(f, raw"\end{tabular}")
    println(f, raw"\begin{tablenotes}")
    println(f, raw"\small")
    @printf(f, "\\item Exact Shapley values over all \$2^{%d}=%d\$ subsets of each %d-channel game, production grid and calibration.\n",
            N_PART_CH, N_PART_SUBSETS, N_PART_CH)
    println(f, raw"Panel A separates medical-expense risk from the Reichling--Smetters health--mortality correlation;")
    println(f, raw"Panel B separates Social Security income from DB pension income. A positive value is demand-suppressing.")
    println(f, raw"\end{tablenotes}")
    println(f, raw"\end{threeparttable}")
    println(f, raw"\end{table}")
end
println("  LaTeX written: $tex_path")

# --- Headline summary for the manuscript ---
println("\n" * "=" ^ 70)
let a = tabs[:medrs], b = tabs[:ssdb]
    loads_a = findfirst(==("Loads"), a.names)
    loads_b = findfirst(==("Loads"), b.names)
    @printf("  Loads rank: %d (Med/R-S unbundled), %d (SS/DB split)\n", a.rank[loads_a], b.rank[loads_b])
    beq_a = findfirst(==("Bequests"), a.names)
    @printf("  Bequests rank: %d (Med/R-S unbundled)\n", a.rank[beq_a])
    ssi = findfirst(==("SS income"), b.names); dbi = findfirst(==("DB income"), b.names)
    @printf("  SS income Shapley: %+.2f pp; DB income Shapley: %+.2f pp\n",
            b.shap[ssi] * 100, b.shap[dbi] * 100)
end
println("  PARTITION ROBUSTNESS COMPLETE")
println("=" ^ 70)
flush(stdout)
