# Shapley-value decomposition of annuity ownership channels.
#
# Addresses the order-dependence critique of sequential decomposition by
# computing each channel's average marginal contribution across random
# permutations of the 7 channels. With 7! = 5,040 orderings, exact
# computation is feasible but slow; Monte Carlo approximation with
# N_PERM random permutations suffices.
#
# Channels:
#   1. SS        — Social Security pre-annuitization
#   2. Bequests  — DFJ luxury good bequest motive
#   3. Medical   — medical expenditure risk (uncorrelated)
#   4. R-S       — health-mortality correlation (requires Medical)
#   5. Pessimism — survival pessimism (O'Dea & Sturrock 2023)
#   6. Loads     — realistic pricing (MWR < 1, fixed cost)
#   7. Inflation — nominal annuity erosion
#
# R-S depends on Medical: when R-S appears before Medical in a permutation,
# both activate together when R-S is reached (standard Shapley treatment
# for complementary channels).
#
# Usage: julia --project=. -p 8 scripts/run_shapley_decomposition.jl

using Printf
using DelimitedFiles
using Distributed
using Random

if nworkers() > 1
    @everywhere include(joinpath(@__DIR__, "..", "src", "AnnuityPuzzle.jl"))
    @everywhere using .AnnuityPuzzle
else
    include(joinpath(@__DIR__, "..", "src", "AnnuityPuzzle.jl"))
    using .AnnuityPuzzle
end

include(joinpath(@__DIR__, "config.jl"))

const N_PERM = 200  # number of random permutations (increase for tighter estimates)
const RNG_SEED = 42

println("=" ^ 70)
println("  SHAPLEY-VALUE DECOMPOSITION OF ANNUITY OWNERSHIP CHANNELS")
println("  N_PERM = $N_PERM random permutations")
println("=" ^ 70)
flush(stdout)

# ===================================================================
# Load HRS population sample
# ===================================================================
println("\nLoading HRS population sample...")
flush(stdout)
hrs_raw = readdlm(HRS_PATH, ',', Any; skipstart=1)
n_pop = size(hrs_raw, 1)
population = zeros(n_pop, 4)
population[:, 1] = Float64.(hrs_raw[:, 1])  # wealth
population[:, 2] .= 0.0                      # SS via ss_func, not A grid
population[:, 3] = Float64.(hrs_raw[:, 3])  # age
if size(hrs_raw, 2) >= 4
    population[:, 4] = Float64.(hrs_raw[:, 4])  # health (1=Good, 2=Fair, 3=Poor)
else
    population[:, 4] .= 2.0
end
@printf("  Loaded %d individuals\n", n_pop)
flush(stdout)

# ===================================================================
# Build survival probabilities
# ===================================================================
p_base = ModelParams(age_start=AGE_START, age_end=AGE_END)
base_surv = build_lockwood_survival(p_base)

# ===================================================================
# Channel definitions (available on all workers)
# ===================================================================
@everywhere const CH_SS          = 1
@everywhere const CH_BEQUESTS    = 2
@everywhere const CH_MEDICAL     = 3
@everywhere const CH_RS          = 4
@everywhere const CH_PESSIMISM   = 5
@everywhere const CH_HEALTHUTIL  = 6
@everywhere const CH_AGENEEDS    = 7
@everywhere const CH_LOADS       = 8
@everywhere const CH_INFLATION   = 9

# Determine active channel count based on config defaults
_ch_names = ["SS", "Bequests", "Medical", "R-S", "Pessimism"]
_ch_count = 5
_health_util_active = !all(x -> x == 1.0, HEALTH_UTILITY)
_cons_decline_active = CONSUMPTION_DECLINE > 0.0
if _health_util_active
    push!(_ch_names, "HealthUtil")
    _ch_count += 1
end
if _cons_decline_active
    push!(_ch_names, "AgeNeeds")
    _ch_count += 1
end
push!(_ch_names, "Loads")
push!(_ch_names, "Inflation")
_ch_count += 2

const N_CHANNELS = _ch_count
const CHANNEL_NAMES = _ch_names

# Build mapping from channel constants to active channel indices
const CH_INDEX = Dict{Int,Int}()
_idx = 1
for ch in [CH_SS, CH_BEQUESTS, CH_MEDICAL, CH_RS, CH_PESSIMISM]
    CH_INDEX[ch] = _idx; _idx += 1
end
if _health_util_active
    CH_INDEX[CH_HEALTHUTIL] = _idx; _idx += 1
end
if _cons_decline_active
    CH_INDEX[CH_AGENEEDS] = _idx; _idx += 1
end
CH_INDEX[CH_LOADS] = _idx; _idx += 1
CH_INDEX[CH_INFLATION] = _idx

# Active channel IDs (subset of 1:9 that are in use)
const ACTIVE_CHANNELS = sort(collect(keys(CH_INDEX)))

# Build ModelParams overrides and SS levels for a given set of active channels.
# Returns a NamedTuple suitable for constructing ModelParams and solve_and_evaluate().
@everywhere function build_channel_config(active::Set{Int};
        theta_dfj, kappa_dfj, mwr_loaded, fixed_cost, inflation_val,
        survival_pessimism, ss_quartile_levels,
        health_utility_vals=[1.0, 1.0, 1.0],
        consumption_decline_val=0.0)

    ss_levels = [0.0, 0.0, 0.0, 0.0]
    theta = 0.0
    kappa = 0.0
    medical_enabled = false
    health_mortality_corr = false
    psi = 1.0
    mwr = 1.0
    fc = 0.0
    infl = 0.0
    hu = [1.0, 1.0, 1.0]
    cd = 0.0

    if CH_SS in active
        ss_levels = copy(ss_quartile_levels)
    end
    if CH_BEQUESTS in active
        theta = theta_dfj
        kappa = kappa_dfj
    end
    # R-S requires Medical; if R-S is active, Medical must also be active
    if CH_MEDICAL in active || CH_RS in active
        medical_enabled = true
    end
    if CH_RS in active
        health_mortality_corr = true
    end
    if CH_PESSIMISM in active
        psi = survival_pessimism
    end
    if CH_HEALTHUTIL in active
        hu = copy(health_utility_vals)
    end
    if CH_AGENEEDS in active
        cd = consumption_decline_val
    end
    if CH_LOADS in active
        mwr = mwr_loaded
        fc = fixed_cost
    end
    if CH_INFLATION in active
        infl = inflation_val
    end

    return (ss_levels=ss_levels,
            theta=theta, kappa=kappa,
            medical_enabled=medical_enabled,
            health_mortality_corr=health_mortality_corr,
            survival_pessimism=psi,
            health_utility=hu,
            consumption_decline=cd,
            mwr=mwr, fixed_cost=fc,
            inflation_rate=infl)
end

# ===================================================================
# Generate random permutations
# ===================================================================
rng = MersenneTwister(RNG_SEED)
# Permute the active channel IDs (e.g., [1,2,3,4,5,8,9] for 7 channels)
perms = [ACTIVE_CHANNELS[randperm(rng, N_CHANNELS)] for _ in 1:N_PERM]
@printf("  Generated %d random permutations (seed=%d)\n", N_PERM, RNG_SEED)
flush(stdout)

# ===================================================================
# Evaluate all permutations
# ===================================================================
# For each permutation, we need to evaluate the model at each prefix
# (0 channels, 1 channel, ..., N channels). That's N+1 evaluations per
# permutation. However, many prefixes are shared across permutations,
# so we deduplicate by caching on the frozenset of active channels.
#
# Strategy: collect all unique channel subsets needed, solve each once,
# then reconstruct marginal contributions from the cache.

# Collect all subsets needed across all permutations
subset_set = Set{Set{Int}}()
push!(subset_set, Set{Int}())  # empty set (Yaari baseline)
for perm in perms
    active = Set{Int}()
    for ch in perm
        # R-S depends on Medical: when R-S is added, Medical comes along
        new_active = copy(active)
        push!(new_active, ch)
        if ch == CH_RS
            push!(new_active, CH_MEDICAL)
        end
        push!(subset_set, copy(new_active))
        active = new_active
    end
end

# Convert to sorted tuples for stable indexing and serialization
subset_list = sort(collect(subset_set), by=s -> (length(s), sort(collect(s))))
subset_to_idx = Dict(s => i for (i, s) in enumerate(subset_list))
n_subsets = length(subset_list)
@printf("  Unique channel subsets to evaluate: %d (of %d total prefix evaluations)\n",
    n_subsets, N_PERM * (N_CHANNELS + 1))
flush(stdout)

# ===================================================================
# Solve each unique subset (parallelized)
# ===================================================================
println("\nSolving all unique channel subsets...")
flush(stdout)

# Capture config values for workers
_theta_dfj = THETA_DFJ
_kappa_dfj = KAPPA_DFJ
_mwr_loaded = MWR_LOADED
_fixed_cost = FIXED_COST
_inflation = INFLATION
_surv_pess = SURVIVAL_PESSIMISM
_ss_q_levels = Float64.(SS_QUARTILE_LEVELS)
_gamma = GAMMA
_beta = BETA
_r_rate = R_RATE
_c_floor = C_FLOOR
_hazard_mult = Float64.(HAZARD_MULT)
_n_wealth = N_WEALTH
_n_annuity = N_ANNUITY
_n_alpha = N_ALPHA
_w_max = W_MAX
_n_quad = N_QUAD
_age_start = AGE_START
_age_end = AGE_END
_a_grid_pow = A_GRID_POW
_min_wealth = MIN_WEALTH
_health_utility = Float64.(HEALTH_UTILITY)
_consumption_decline = CONSUMPTION_DECLINE
_base_surv = base_surv
_population = population

# Pre-compute payout rates on main process
grid_kw = (n_wealth=N_WEALTH, n_annuity=N_ANNUITY, n_alpha=N_ALPHA,
           W_max=W_MAX, age_start=AGE_START, age_end=AGE_END,
           annuity_grid_power=A_GRID_POW)
p_fair = ModelParams(; gamma=GAMMA, beta=BETA, r=R_RATE, mwr=1.0, grid_kw...)
fair_pr = compute_payout_rate(p_fair, base_surv)
p_fair_nom = ModelParams(; gamma=GAMMA, beta=BETA, r=R_RATE, mwr=1.0,
                           inflation_rate=INFLATION, grid_kw...)
fair_pr_nom = INFLATION > 0 ? compute_payout_rate(p_fair_nom, base_surv) : fair_pr

_fair_pr = fair_pr
_fair_pr_nom = fair_pr_nom

t0_solve = time()

# Convert subsets to serializable form for pmap
subset_specs = [(idx=i, channels=sort(collect(s))) for (i, s) in enumerate(subset_list)]

ownership_results = parallel_solve(subset_specs) do spec
    active = Set{Int}(spec.channels)

    cfg = build_channel_config(active;
        theta_dfj=_theta_dfj, kappa_dfj=_kappa_dfj,
        mwr_loaded=_mwr_loaded, fixed_cost=_fixed_cost,
        inflation_val=_inflation, survival_pessimism=_surv_pess,
        ss_quartile_levels=_ss_q_levels,
        health_utility_vals=_health_utility,
        consumption_decline_val=_consumption_decline)

    gkw = (n_wealth=_n_wealth, n_annuity=_n_annuity, n_alpha=_n_alpha,
           W_max=_w_max, age_start=_age_start, age_end=_age_end,
           annuity_grid_power=_a_grid_pow)

    common_kw = (gamma=_gamma, beta=_beta, r=_r_rate,
                 stochastic_health=true, n_health_states=3, n_quad=_n_quad,
                 c_floor=_c_floor, hazard_mult=_hazard_mult)

    # Determine payout rate
    has_loads = cfg.mwr < 1.0
    has_infl = cfg.inflation_rate > 0
    if has_loads && has_infl
        pr = cfg.mwr * _fair_pr_nom
    elseif has_loads
        pr = cfg.mwr * _fair_pr
    elseif has_infl
        pr = _fair_pr_nom
    else
        pr = _fair_pr
    end

    # Build grids using fair payout rate (covers full A range)
    p_grid = ModelParams(; common_kw..., mwr=1.0, gkw...)
    grids = build_grids(p_grid, max(_fair_pr, _fair_pr_nom))

    p_model = ModelParams(; common_kw...,
        theta=cfg.theta, kappa=cfg.kappa,
        mwr=cfg.mwr, fixed_cost=cfg.fixed_cost,
        inflation_rate=cfg.inflation_rate,
        medical_enabled=cfg.medical_enabled,
        health_mortality_corr=cfg.health_mortality_corr,
        survival_pessimism=cfg.survival_pessimism,
        health_utility=cfg.health_utility,
        consumption_decline=cfg.consumption_decline,
        gkw...)

    # Filter population
    pop = copy(_population)
    if _min_wealth > 0.0
        mask = pop[:, 1] .>= _min_wealth
        pop = pop[mask, :]
    end
    if size(pop, 2) < 4
        pop = hcat(pop, fill(2.0, size(pop, 1)))
    end

    # Solve with per-quartile SS
    res = solve_and_evaluate(p_model, grids, _base_surv, cfg.ss_levels,
        pop, pr; step_name="", verbose=false)

    (idx=spec.idx, ownership=res.ownership, mean_alpha=res.mean_alpha)
end

solve_time = time() - t0_solve
@printf("  Solved %d subsets in %.0fs (%.1fs per subset)\n",
    n_subsets, solve_time, solve_time / n_subsets)
flush(stdout)

# Build lookup from subset index to ownership
ownership_by_idx = Dict{Int, Float64}()
alpha_by_idx = Dict{Int, Float64}()
for r in ownership_results
    ownership_by_idx[r.idx] = r.ownership
    alpha_by_idx[r.idx] = r.mean_alpha
end

# ===================================================================
# Compute Shapley values from cached results
# ===================================================================
println("\nComputing Shapley values from permutation marginal contributions...")
flush(stdout)

# For each channel, collect its marginal contribution in each permutation.
# Use CH_INDEX to map channel IDs to array positions.
marginal_contributions = [Float64[] for _ in 1:N_CHANNELS]

for perm in perms
    active = Set{Int}()
    prev_ownership = ownership_by_idx[subset_to_idx[Set{Int}()]]

    for ch in perm
        new_active = copy(active)
        push!(new_active, ch)
        # R-S dependency: adding R-S also adds Medical
        if ch == CH_RS
            push!(new_active, CH_MEDICAL)
        end

        curr_ownership = ownership_by_idx[subset_to_idx[new_active]]
        marginal = prev_ownership - curr_ownership  # positive = demand reduction

        push!(marginal_contributions[CH_INDEX[ch]], marginal)

        active = new_active
        prev_ownership = curr_ownership
    end
end

# Helper: mean and std for Float64 vectors
function _mean(v::Vector{Float64})
    return sum(v) / length(v)
end
function _std(v::Vector{Float64})
    m = _mean(v)
    return sqrt(sum((x - m)^2 for x in v) / (length(v) - 1))
end

# Shapley value = mean marginal contribution
shapley_values = [_mean(mc) for mc in marginal_contributions]
shapley_std = [_std(mc) for mc in marginal_contributions]
shapley_min = [minimum(mc) for mc in marginal_contributions]
shapley_max = [maximum(mc) for mc in marginal_contributions]

# ===================================================================
# Print results
# ===================================================================
println("\n" * "=" ^ 70)
println("  SHAPLEY VALUE DECOMPOSITION RESULTS")
println("=" ^ 70)

# Yaari baseline and full model ownership
yaari_own = ownership_by_idx[subset_to_idx[Set{Int}()]]
full_own = ownership_by_idx[subset_to_idx[Set{Int}(ACTIVE_CHANNELS)]]
total_drop = yaari_own - full_own

@printf("\n  Yaari baseline ownership:  %6.1f%%\n", yaari_own * 100)
@printf("  Full model ownership:      %6.1f%%\n", full_own * 100)
@printf("  Total drop:                %6.1f pp\n", total_drop * 100)
@printf("  Sum of Shapley values:     %6.1f pp (should equal total drop)\n",
    sum(shapley_values) * 100)
flush(stdout)

@printf("\n  %-12s  %10s  %8s  %10s  %10s  %8s\n",
    "Channel", "Shapley", "Std Dev", "Min", "Max", "Share")
println("  " * "-" ^ 64)

for i in 1:N_CHANNELS
    share = total_drop > 0 ? shapley_values[i] / total_drop : 0.0
    @printf("  %-12s  %9.1f pp  %7.1f pp  %9.1f pp  %9.1f pp  %7.1f%%\n",
        CHANNEL_NAMES[i],
        shapley_values[i] * 100,
        shapley_std[i] * 100,
        shapley_min[i] * 100,
        shapley_max[i] * 100,
        share * 100)
end
println("  " * "-" ^ 64)
@printf("  %-12s  %9.1f pp\n", "Total", sum(shapley_values) * 100)
flush(stdout)

# ===================================================================
# Compare to sequential decomposition marginal contributions
# ===================================================================
# Run standard sequential decomposition for comparison
println("\n" * "=" ^ 70)
println("  COMPARISON: SHAPLEY vs SEQUENTIAL DECOMPOSITION")
println("=" ^ 70)
flush(stdout)

decomp = run_decomposition(
    base_surv, population;
    gamma=GAMMA, beta=BETA, r=R_RATE,
    theta=THETA_DFJ, kappa=KAPPA_DFJ,
    c_floor=C_FLOOR,
    mwr_loaded=MWR_LOADED,
    fixed_cost_val=FIXED_COST,
    inflation_val=INFLATION,
    n_wealth=N_WEALTH, n_annuity=N_ANNUITY, n_alpha=N_ALPHA,
    W_max=W_MAX, n_quad=N_QUAD,
    age_start=AGE_START, age_end=AGE_END,
    annuity_grid_power=A_GRID_POW,
    hazard_mult=HAZARD_MULT,
    survival_pessimism=SURVIVAL_PESSIMISM,
    min_wealth=MIN_WEALTH,
    ss_levels=Float64.(SS_QUARTILE_LEVELS),
    consumption_decline_val=CONSUMPTION_DECLINE,
    health_utility_vals=Float64.(HEALTH_UTILITY),
    verbose=false,
)

# Map decomposition step names to Shapley channel indices.
# The decomposition steps (after Yaari) have names that we match to Shapley channels.
seq_deltas = Dict{Int, Float64}()
decomp_name_to_ch = Dict(
    "+ Social Security" => CH_SS,
    "+ Bequest motives" => CH_BEQUESTS,
    "+ Medical expenditure risk (uncorrelated)" => CH_MEDICAL,
    "+ Health-mortality correlation (R-S)" => CH_RS,
    "+ Survival pessimism" => CH_PESSIMISM,
    "+ State-dependent utility" => CH_HEALTHUTIL,
    "+ Age-varying consumption needs" => CH_AGENEEDS,
    "+ Realistic pricing loads" => CH_LOADS,
    "+ Inflation erosion" => CH_INFLATION,
)
for step in decomp.steps
    ch_id = get(decomp_name_to_ch, step.name, nothing)
    if ch_id !== nothing && haskey(CH_INDEX, ch_id)
        seq_deltas[CH_INDEX[ch_id]] = abs(step.delta)
    end
end

@printf("\n  %-12s  %12s  %12s  %10s\n",
    "Channel", "Shapley (pp)", "Seq (pp)", "Difference")
println("  " * "-" ^ 50)
for i in 1:N_CHANNELS
    seq_val = get(seq_deltas, i, 0.0)
    diff = shapley_values[i] - seq_val
    @printf("  %-12s  %11.1f  %11.1f  %+9.1f\n",
        CHANNEL_NAMES[i],
        shapley_values[i] * 100,
        seq_val * 100,
        diff * 100)
end
flush(stdout)

# ===================================================================
# Save results
# ===================================================================
tables_dir = joinpath(@__DIR__, "..", "tables")
mkpath(joinpath(tables_dir, "csv"))
mkpath(joinpath(tables_dir, "tex"))

# CSV
csv_path = joinpath(tables_dir, "csv", "shapley_decomposition.csv")
open(csv_path, "w") do f
    println(f, "channel,shapley_value,std_dev,min_contribution,max_contribution")
    for i in 1:N_CHANNELS
        @printf(f, "%s,%.6f,%.6f,%.6f,%.6f\n",
            CHANNEL_NAMES[i],
            shapley_values[i],
            shapley_std[i],
            shapley_min[i],
            shapley_max[i])
    end
end
println("\n  CSV saved: $csv_path")
flush(stdout)

# LaTeX table
tex_path = joinpath(tables_dir, "tex", "shapley_decomposition.tex")
open(tex_path, "w") do f
    println(f, raw"\begin{table}[htbp]")
    println(f, raw"\centering")
    println(f, raw"\caption{Shapley-Value Decomposition of Predicted Annuity Ownership}")
    println(f, raw"\label{tab:shapley}")
    println(f, raw"\begin{tabular}{lccccc}")
    println(f, raw"\toprule")
    println(f, "Channel & Shapley (pp) & Std Dev & Min & Max & Share (\\%) \\\\")
    println(f, raw"\midrule")

    for i in 1:N_CHANNELS
        share = total_drop > 0 ? shapley_values[i] / total_drop * 100 : 0.0
        @printf(f, "%s & %.1f & %.1f & %.1f & %.1f & %.1f \\\\\n",
            CHANNEL_NAMES[i],
            shapley_values[i] * 100,
            shapley_std[i] * 100,
            shapley_min[i] * 100,
            shapley_max[i] * 100,
            share)
    end

    println(f, raw"\midrule")
    @printf(f, "Total & %.1f & & & & 100.0 \\\\\n", sum(shapley_values) * 100)
    println(f, raw"\bottomrule")
    println(f, raw"\end{tabular}")
    println(f, raw"\begin{tablenotes}")
    println(f, raw"\small")
    @printf(f, "\\item Shapley values computed from %d random permutations of %d channels.\n",
        N_PERM, N_CHANNELS)
    println(f, "Each value represents the average marginal ownership reduction (pp)")
    println(f, "when the channel is added, averaged across all orderings.")
    @printf(f, "Yaari baseline: %.1f\\%%. Full model: %.1f\\%%.\n",
        yaari_own * 100, full_own * 100)
    println(f, raw"\end{tablenotes}")
    println(f, raw"\end{table}")
end
println("  LaTeX saved: $tex_path")

println("\n" * "=" ^ 70)
println("  SHAPLEY DECOMPOSITION COMPLETE")
println("=" ^ 70)
flush(stdout)
