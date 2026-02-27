# Full subset enumeration of annuity ownership channels.
#
# Precomputes the ownership rate for every combination of 9 channels
# (2^9 = 512 subsets), then reconstructs any decomposition ordering,
# exact Shapley values, and pairwise interactions from the lookup table.
#
# Channels:
#   1. SS            — Social Security pre-annuitization
#   2. Bequests      — DFJ luxury good bequest motive
#   3. Medical       — medical expenditure risk (uncorrelated)
#   4. R-S           — health-mortality correlation (requires Medical)
#   5. Pessimism     — survival pessimism (O'Dea & Sturrock 2023)
#   6. Age needs     — front-loaded spending preferences (Aguiar-Hurst)
#   7. State utility — health-varying marginal utility (FLN 2013)
#   8. Loads         — realistic pricing (MWR < 1, fixed cost)
#   9. Inflation     — nominal annuity erosion
#
# R-S depends on Medical: when R-S is active but Medical is not,
# Medical is forced on (standard treatment for complementary channels).
#
# Usage: julia --project=. -p 90 scripts/run_subset_enumeration.jl

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

# Two new channel calibration values (Aguiar-Hurst 2013; FLN 2013)
const CONSUMPTION_DECLINE = 0.02
const HEALTH_UTILITY = [1.0, 0.90, 0.75]

# ===================================================================
# Channel index definitions
# ===================================================================
@everywhere const CH_SS           = 1
@everywhere const CH_BEQUESTS     = 2
@everywhere const CH_MEDICAL      = 3
@everywhere const CH_RS           = 4
@everywhere const CH_PESSIMISM    = 5
@everywhere const CH_AGE_NEEDS    = 6
@everywhere const CH_STATE_UTIL   = 7
@everywhere const CH_LOADS        = 8
@everywhere const CH_INFLATION    = 9

const N_CHANNELS = 9
const N_SUBSETS = 2^N_CHANNELS  # 512
const CHANNEL_NAMES = [
    "SS", "Bequests", "Medical", "R-S", "Pessimism",
    "Age needs", "State utility", "Loads", "Inflation",
]

println("=" ^ 70)
println("  FULL SUBSET ENUMERATION: 2^$N_CHANNELS = $N_SUBSETS CHANNEL SUBSETS")
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
# Build survival probabilities and payout rates
# ===================================================================
p_base = ModelParams(age_start=AGE_START, age_end=AGE_END)
base_surv = build_lockwood_survival(p_base)

grid_kw = (n_wealth=N_WEALTH, n_annuity=N_ANNUITY, n_alpha=N_ALPHA,
           W_max=W_MAX, age_start=AGE_START, age_end=AGE_END,
           annuity_grid_power=A_GRID_POW)

p_fair = ModelParams(; gamma=GAMMA, beta=BETA, r=R_RATE, mwr=1.0, grid_kw...)
fair_pr = compute_payout_rate(p_fair, base_surv)

p_fair_nom = ModelParams(; gamma=GAMMA, beta=BETA, r=R_RATE, mwr=1.0,
                           inflation_rate=INFLATION, grid_kw...)
fair_pr_nom = INFLATION > 0 ? compute_payout_rate(p_fair_nom, base_surv) : fair_pr

@printf("  Fair payout rate (real):    %.4f\n", fair_pr)
@printf("  Fair payout rate (nominal): %.4f\n", fair_pr_nom)
flush(stdout)

# ===================================================================
# Build channel config from bitmask
# ===================================================================
# Convert an integer bitmask (0 to 511) to the set of active channel indices.
# Bit i (0-indexed) corresponds to channel i+1.
@everywhere function bitmask_to_channels(mask::Int)
    active = Set{Int}()
    for i in 0:8
        if (mask >> i) & 1 == 1
            push!(active, i + 1)
        end
    end
    return active
end

# Build ModelParams overrides for a given set of active channels.
# Handles the R-S -> Medical dependency.
@everywhere function build_subset_config(active::Set{Int};
        theta_dfj, kappa_dfj, mwr_loaded, fixed_cost, inflation_val,
        survival_pessimism, ss_quartile_levels,
        consumption_decline, health_utility)

    ss_levels = [0.0, 0.0, 0.0, 0.0]
    theta = 0.0
    kappa = 0.0
    medical_enabled = false
    health_mortality_corr = false
    psi = 1.0
    mwr = 1.0
    fc = 0.0
    infl = 0.0
    cd = 0.0
    hu = [1.0, 1.0, 1.0]

    if CH_SS in active
        ss_levels = copy(ss_quartile_levels)
    end
    if CH_BEQUESTS in active
        theta = theta_dfj
        kappa = kappa_dfj
    end
    # R-S requires Medical: if R-S is on, Medical must also be on
    if CH_MEDICAL in active || CH_RS in active
        medical_enabled = true
    end
    if CH_RS in active
        health_mortality_corr = true
    end
    if CH_PESSIMISM in active
        psi = survival_pessimism
    end
    if CH_AGE_NEEDS in active
        cd = consumption_decline
    end
    if CH_STATE_UTIL in active
        hu = copy(health_utility)
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
            consumption_decline=cd,
            health_utility=hu,
            mwr=mwr, fixed_cost=fc,
            inflation_rate=infl)
end

# ===================================================================
# Solve all 512 subsets
# ===================================================================
println("\nSolving all $N_SUBSETS channel subsets...")
flush(stdout)

# Capture config values for worker closures
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
_base_surv = base_surv
_population = population
_fair_pr = fair_pr
_fair_pr_nom = fair_pr_nom
_consumption_decline = CONSUMPTION_DECLINE
_health_utility = Float64.(HEALTH_UTILITY)

subset_specs = [(bitmask=i,) for i in 0:(N_SUBSETS - 1)]

t0_solve = time()

results = parallel_solve(subset_specs) do spec
    mask = spec.bitmask
    active = bitmask_to_channels(mask)

    cfg = build_subset_config(active;
        theta_dfj=_theta_dfj, kappa_dfj=_kappa_dfj,
        mwr_loaded=_mwr_loaded, fixed_cost=_fixed_cost,
        inflation_val=_inflation, survival_pessimism=_surv_pess,
        ss_quartile_levels=_ss_q_levels,
        consumption_decline=_consumption_decline,
        health_utility=_health_utility)

    gkw = (n_wealth=_n_wealth, n_annuity=_n_annuity, n_alpha=_n_alpha,
           W_max=_w_max, age_start=_age_start, age_end=_age_end,
           annuity_grid_power=_a_grid_pow)

    common_kw = (gamma=_gamma, beta=_beta, r=_r_rate,
                 stochastic_health=true, n_health_states=3, n_quad=_n_quad,
                 c_floor=_c_floor, hazard_mult=_hazard_mult)

    # Determine payout rate based on active channels
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
        consumption_decline=cfg.consumption_decline,
        health_utility=cfg.health_utility,
        gkw...)

    # Filter population
    pop = copy(_population)
    if _min_wealth > 0.0
        pop_mask = pop[:, 1] .>= _min_wealth
        pop = pop[pop_mask, :]
    end
    if size(pop, 2) < 4
        pop = hcat(pop, fill(2.0, size(pop, 1)))
    end

    t0 = time()
    res = solve_and_evaluate(p_model, grids, _base_surv, cfg.ss_levels,
        pop, pr; step_name="", verbose=false)
    st = time() - t0

    (bitmask=mask, ownership=res.ownership, mean_alpha=res.mean_alpha, solve_time=st)
end

total_solve_time = time() - t0_solve
@printf("  Solved %d subsets in %.0fs (%.1fs per subset)\n",
    N_SUBSETS, total_solve_time, total_solve_time / N_SUBSETS)
flush(stdout)

# ===================================================================
# Build lookup table
# ===================================================================
ownership_lookup = Dict{Int, Float64}()
alpha_lookup = Dict{Int, Float64}()
solvetime_lookup = Dict{Int, Float64}()
for r in results
    ownership_lookup[r.bitmask] = r.ownership
    alpha_lookup[r.bitmask] = r.mean_alpha
    solvetime_lookup[r.bitmask] = r.solve_time
end

yaari_own = ownership_lookup[0]
full_mask = (1 << N_CHANNELS) - 1  # 511
full_own = ownership_lookup[full_mask]
total_drop = yaari_own - full_own

println("\n  Yaari baseline (bitmask 0):   $(round(yaari_own * 100, digits=1))%")
println("  Full model (bitmask $full_mask):  $(round(full_own * 100, digits=1))%")
println("  Total drop:                   $(round(total_drop * 100, digits=1)) pp")
flush(stdout)

# ===================================================================
# Helper: channel names for a bitmask
# ===================================================================
function channels_active_str(mask::Int)
    names = String[]
    for i in 0:(N_CHANNELS - 1)
        if (mask >> i) & 1 == 1
            push!(names, CHANNEL_NAMES[i + 1])
        end
    end
    return isempty(names) ? "None" : join(names, "+")
end

# ===================================================================
# Save full enumeration CSV
# ===================================================================
tables_dir = joinpath(@__DIR__, "..", "tables")
mkpath(joinpath(tables_dir, "csv"))
mkpath(joinpath(tables_dir, "tex"))

enum_csv_path = joinpath(tables_dir, "csv", "subset_enumeration.csv")
open(enum_csv_path, "w") do f
    println(f, "bitmask,channel_names_active,ownership_pct,mean_alpha,solve_time")
    for mask in 0:(N_SUBSETS - 1)
        @printf(f, "%d,%s,%.4f,%.6f,%.1f\n",
            mask,
            channels_active_str(mask),
            ownership_lookup[mask] * 100,
            alpha_lookup[mask],
            solvetime_lookup[mask])
    end
end
println("\n  Enumeration CSV saved: $enum_csv_path")
flush(stdout)

# ===================================================================
# Sequential decomposition from the lookup table (any ordering)
# ===================================================================
println("\n" * "=" ^ 70)
println("  SEQUENTIAL DECOMPOSITION (from lookup table)")
println("=" ^ 70)

# Default ordering matches the manuscript decomposition
default_order = [CH_SS, CH_BEQUESTS, CH_MEDICAL, CH_RS, CH_PESSIMISM,
                 CH_AGE_NEEDS, CH_STATE_UTIL, CH_LOADS, CH_INFLATION]

"""
Reconstruct a sequential decomposition for any channel ordering
from the precomputed lookup table.
"""
function sequential_from_lookup(ordering::Vector{Int}, lookup::Dict{Int, Float64})
    steps = Tuple{String, Float64, Float64}[]
    mask = 0
    prev_own = lookup[0]
    push!(steps, ("Yaari benchmark", prev_own, 0.0))

    for ch in ordering
        # R-S dependency: if adding R-S and Medical not yet active, add Medical too
        if ch == CH_RS && (mask >> (CH_MEDICAL - 1)) & 1 == 0
            mask |= (1 << (CH_MEDICAL - 1))
        end
        mask |= (1 << (ch - 1))
        own = lookup[mask]
        delta = own - prev_own
        push!(steps, ("+ " * CHANNEL_NAMES[ch], own, delta))
        prev_own = own
    end
    return steps
end

steps = sequential_from_lookup(default_order, ownership_lookup)

@printf("\n  %-55s  %8s  %10s  %10s\n", "Model Specification", "Own (%)", "Delta (pp)", "Retention")
println("  " * "-" ^ 88)

for (i, (name, own, delta)) in enumerate(steps)
    if i == 1
        @printf("  %-55s  %7.1f%%\n", name, own * 100)
    else
        prev_own = steps[i - 1][2]
        retention = prev_own > 0 ? own / prev_own : 0.0
        @printf("  %-55s  %7.1f%%  %+9.1f pp  %8.1f%%\n",
            name, own * 100, delta * 100, retention * 100)
    end
end
println("  " * "-" ^ 88)
@printf("  %-55s  %7.1f%%\n", "Observed (Lockwood 2012, single retirees 65-69)", 3.6)
flush(stdout)

# ===================================================================
# Exact Shapley values
# ===================================================================
println("\n" * "=" ^ 70)
println("  EXACT SHAPLEY VALUES (from $N_SUBSETS precomputed subsets)")
println("=" ^ 70)
flush(stdout)

# v(S) = yaari_own - ownership(S) = total ownership drop caused by subset S.
# Using the cooperative game convention: v maps subsets to the total demand
# reduction they produce. Shapley decomposes the total drop across channels.

function exact_shapley(n::Int, lookup::Dict{Int, Float64})
    yaari = lookup[0]
    shapley = zeros(n)

    # Precompute factorials
    fact = zeros(Int, n + 1)
    fact[1] = 1  # 0! = 1
    for k in 1:n
        fact[k + 1] = fact[k] * k
    end

    for i in 1:n
        bit_i = 1 << (i - 1)
        phi_i = 0.0

        # Sum over all subsets S that do NOT contain channel i
        for s_mask in 0:((1 << n) - 1)
            (s_mask & bit_i) != 0 && continue  # skip if i is in S

            s_size = count_ones(s_mask)

            # Build S union {i}, handling R-S -> Medical dependency
            s_union_i = s_mask | bit_i
            # If adding R-S (ch 4) and Medical (ch 3) is not in s_union_i, add it
            if i == CH_RS && (s_union_i >> (CH_MEDICAL - 1)) & 1 == 0
                s_union_i |= (1 << (CH_MEDICAL - 1))
            end
            # Also handle the case where S already has R-S but not Medical
            if (s_mask >> (CH_RS - 1)) & 1 == 1 && (s_mask >> (CH_MEDICAL - 1)) & 1 == 0
                # S has R-S but not Medical — this shouldn't happen in a consistent
                # enumeration because we force Medical on when R-S is on.
                # But the lookup table was built with this enforcement, so
                # the ownership for s_mask already includes Medical.
                # No special handling needed here.
            end

            # Marginal contribution of channel i to coalition S
            # v(S ∪ {i}) - v(S) where v(S) = yaari - ownership(S)
            # = (yaari - ownership(S ∪ {i})) - (yaari - ownership(S))
            # = ownership(S) - ownership(S ∪ {i})
            mc = lookup[s_mask] - lookup[s_union_i]

            # Shapley weight: |S|! * (N - |S| - 1)! / N!
            weight = Float64(fact[s_size + 1]) * Float64(fact[n - s_size]) / Float64(fact[n + 1])
            phi_i += weight * mc
        end

        shapley[i] = phi_i
    end

    return shapley
end

shapley = exact_shapley(N_CHANNELS, ownership_lookup)

@printf("\n  %-15s  %12s  %10s\n", "Channel", "Shapley (pp)", "Share (%)")
println("  " * "-" ^ 40)

for i in 1:N_CHANNELS
    share = total_drop > 0 ? shapley[i] / total_drop * 100 : 0.0
    @printf("  %-15s  %+11.2f  %9.1f\n",
        CHANNEL_NAMES[i], shapley[i] * 100, share)
end
println("  " * "-" ^ 40)
@printf("  %-15s  %+11.2f  %9.1f\n", "Total", sum(shapley) * 100,
    total_drop > 0 ? sum(shapley) / total_drop * 100 : 0.0)
@printf("\n  Verification: sum of Shapley = %.2f pp, total drop = %.2f pp\n",
    sum(shapley) * 100, total_drop * 100)
flush(stdout)

# ===================================================================
# Pairwise interactions from lookup table
# ===================================================================
println("\n" * "=" ^ 70)
println("  PAIRWISE INTERACTIONS (from lookup table)")
println("=" ^ 70)
flush(stdout)

# Interaction(i,j) = [v({i,j}) - v({i}) - v({j}) + v({})]
# where v(S) = yaari - ownership(S)
# = [ownership({i}) + ownership({j}) - ownership({i,j}) - yaari]
# Negative means channels reinforce (super-additive).

interaction_matrix = fill(NaN, N_CHANNELS, N_CHANNELS)

for i in 1:N_CHANNELS
    for j in (i+1):N_CHANNELS
        mask_i = 1 << (i - 1)
        mask_j = 1 << (j - 1)
        mask_ij = mask_i | mask_j

        # Handle R-S -> Medical dependency in all relevant masks
        if i == CH_RS || j == CH_RS
            mask_ij |= (1 << (CH_MEDICAL - 1))
        end
        if i == CH_RS
            mask_i |= (1 << (CH_MEDICAL - 1))
        end
        if j == CH_RS
            mask_j |= (1 << (CH_MEDICAL - 1))
        end

        own_i = ownership_lookup[mask_i]
        own_j = ownership_lookup[mask_j]
        own_ij = ownership_lookup[mask_ij]

        # Additive prediction: yaari - drop_i - drop_j
        drop_i = yaari_own - own_i
        drop_j = yaari_own - own_j
        additive_pred = yaari_own - drop_i - drop_j
        interaction_matrix[i, j] = own_ij - additive_pred
        interaction_matrix[j, i] = interaction_matrix[i, j]
    end
    interaction_matrix[i, i] = 0.0
end

@printf("\n  %-15s", "")
for name in CHANNEL_NAMES
    @printf("  %9s", length(name) > 9 ? name[1:9] : name)
end
println()
println("  " * "-" ^ (15 + 11 * N_CHANNELS))

for i in 1:N_CHANNELS
    @printf("  %-15s", CHANNEL_NAMES[i])
    for j in 1:N_CHANNELS
        if i == j
            @printf("  %9s", "---")
        elseif j > i
            @printf("  %+8.1f", interaction_matrix[i, j] * 100)
        else
            @printf("  %9s", "")
        end
    end
    println()
end
println("\n  Negative = channels reinforce (super-additive demand reduction)")
flush(stdout)

# ===================================================================
# Save Shapley CSV
# ===================================================================
shapley_csv_path = joinpath(tables_dir, "csv", "shapley_exact.csv")
open(shapley_csv_path, "w") do f
    println(f, "channel,shapley_value_pp,share_pct")
    for i in 1:N_CHANNELS
        share = total_drop > 0 ? shapley[i] / total_drop * 100 : 0.0
        @printf(f, "%s,%.4f,%.2f\n", CHANNEL_NAMES[i], shapley[i] * 100, share)
    end
end
println("\n  Shapley CSV saved: $shapley_csv_path")
flush(stdout)

# ===================================================================
# Save Shapley LaTeX table
# ===================================================================
shapley_tex_path = joinpath(tables_dir, "tex", "shapley_exact.tex")
open(shapley_tex_path, "w") do f
    println(f, raw"\begin{table}[htbp]")
    println(f, raw"\centering")
    println(f, raw"\caption{Exact Shapley-Value Decomposition of Predicted Annuity Ownership}")
    println(f, raw"\label{tab:shapley_exact}")
    println(f, raw"\begin{tabular}{lcc}")
    println(f, raw"\toprule")
    println(f, "Channel & Shapley (pp) & Share (\\%) \\\\")
    println(f, raw"\midrule")

    for i in 1:N_CHANNELS
        share = total_drop > 0 ? shapley[i] / total_drop * 100 : 0.0
        @printf(f, "%s & %+.2f & %.1f \\\\\n",
            CHANNEL_NAMES[i], shapley[i] * 100, share)
    end

    println(f, raw"\midrule")
    @printf(f, "Total & %+.2f & 100.0 \\\\\n", sum(shapley) * 100)
    println(f, raw"\bottomrule")
    println(f, raw"\end{tabular}")
    println(f, raw"\begin{tablenotes}")
    println(f, raw"\small")
    @printf(f, "\\item Exact Shapley values computed from all %d channel subsets.\n", N_SUBSETS)
    println(f, "Each value represents the weighted average marginal ownership reduction (pp)")
    println(f, "across all coalition orderings.")
    @printf(f, "Yaari baseline: %.1f\\%%. Full model: %.1f\\%%.\n",
        yaari_own * 100, full_own * 100)
    println(f, raw"\end{tablenotes}")
    println(f, raw"\end{table}")
end
println("  Shapley LaTeX saved: $shapley_tex_path")
flush(stdout)

# ===================================================================
# Save pairwise interactions CSV
# ===================================================================
pw_csv_path = joinpath(tables_dir, "csv", "pairwise_interactions_exact.csv")
open(pw_csv_path, "w") do f
    println(f, "channel_A,channel_B,own_A_pct,own_B_pct,own_AB_pct,interaction_pp")
    for i in 1:N_CHANNELS
        for j in (i+1):N_CHANNELS
            mask_i = 1 << (i - 1)
            mask_j = 1 << (j - 1)
            mask_ij = mask_i | mask_j
            # Apply R-S dependency for display
            if i == CH_RS
                mask_i |= (1 << (CH_MEDICAL - 1))
            end
            if j == CH_RS
                mask_j |= (1 << (CH_MEDICAL - 1))
            end
            if i == CH_RS || j == CH_RS
                mask_ij |= (1 << (CH_MEDICAL - 1))
            end
            @printf(f, "%s,%s,%.2f,%.2f,%.2f,%.2f\n",
                CHANNEL_NAMES[i], CHANNEL_NAMES[j],
                ownership_lookup[mask_i] * 100,
                ownership_lookup[mask_j] * 100,
                ownership_lookup[mask_ij] * 100,
                interaction_matrix[i, j] * 100)
        end
    end
end
println("  Pairwise CSV saved: $pw_csv_path")
flush(stdout)

# ===================================================================
# Summary statistics
# ===================================================================
println("\n" * "=" ^ 70)
println("  SUMMARY STATISTICS")
println("=" ^ 70)

# Most/least effective single channels
single_drops = [(CHANNEL_NAMES[i], yaari_own - ownership_lookup[1 << (i - 1)]) for i in 1:N_CHANNELS]
# For R-S, use mask that includes Medical
rs_mask = (1 << (CH_RS - 1)) | (1 << (CH_MEDICAL - 1))
single_drops[CH_RS] = (CHANNEL_NAMES[CH_RS], yaari_own - ownership_lookup[rs_mask])

sort!(single_drops, by=x -> -x[2])

println("\n  Single-channel effectiveness (demand reduction from Yaari):")
for (name, drop) in single_drops
    @printf("    %-15s  %+.1f pp\n", name, drop * 100)
end

# Count subsets that produce ownership <= 5%
low_own_count = count(v -> v <= 0.05, values(ownership_lookup))
@printf("\n  Subsets with ownership <= 5%%: %d of %d (%.1f%%)\n",
    low_own_count, N_SUBSETS, low_own_count / N_SUBSETS * 100)

# Minimum and maximum ownership across all subsets
local min_mask = 0
local max_mask = 0
local min_own_val = Inf
local max_own_val = -Inf
for (m, o) in ownership_lookup
    if o < min_own_val
        min_own_val = o
        min_mask = m
    end
    if o > max_own_val
        max_own_val = o
        max_mask = m
    end
end
@printf("  Min ownership: %.1f%% (%s)\n", min_own_val * 100, channels_active_str(min_mask))
@printf("  Max ownership: %.1f%% (%s)\n", max_own_val * 100, channels_active_str(max_mask))

println("\n" * "=" ^ 70)
println("  SUBSET ENUMERATION COMPLETE")
@printf("  Total computation time: %.0fs\n", total_solve_time)
println("=" ^ 70)
flush(stdout)
