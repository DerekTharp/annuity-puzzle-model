# Reduced-form calibration of the age-varying-needs felicity-weight decline
# (delta_c / CONSUMPTION_DECLINE). This is NOT a structurally identified "needs"
# estimate. delta_c is the single free felicity-weight parameter, pinned so the
# model's simulated no-private-annuity consumption path reproduces one
# survivor-conditioned endpoint ratio: the geometric decline of pooled mean
# consumption between age 65 and age 90. The target is the Aguiar-Hurst (2013)
# ~2%/yr nondurable retirement expenditure slope.
#
# The map from delta_c to the simulated consumption slope runs through the Euler
# equation and the mortality/medical/floor environment, so a 2% weight decline
# is not a 2% consumption decline. The delta_c=0 environment alone already
# produces a ~1.81%/yr survivor-conditioned decline, so delta_c supplies only
# the residual to the 2% target. That residual is small (delta_c ~ 0.008) and,
# being the difference of two nearby slopes, is sensitive to Monte Carlo noise
# and to the survivor-window endpoint. The sensitivity block quantifies that
# fragility across rng seeds and window endpoints; treat the level as fragile.
#
# Slope estimate: pooled over four wealth bands (band-specific SS+DB floor). To
# avoid a single-draw estimate, each band's households are replicated K times
# (K*n_band ~ a few thousand simulated paths per band, uniform K so the pooled
# population weighting is unchanged). A fixed rng seed within a calibration gives
# common random numbers across bisection steps, so the root is stable in delta_c
# even though the absolute slope carries Monte Carlo noise.
#
# Outputs:
#   tables/csv/age_needs_calibration.csv  headline (seed 42, window 65-90)
#   tables/csv/age_needs_sensitivity.csv  delta_c across {seed} x {age_hi}
#
# Usage: julia --project=. scripts/recalibrate_age_needs.jl

using DelimitedFiles, Printf, Statistics
include(joinpath(@__DIR__, "..", "src", "AnnuityPuzzle.jl"))
using .AnnuityPuzzle
include(joinpath(@__DIR__, "config.jl"))

const TARGET_DECLINE = 0.02       # Aguiar-Hurst nondurable retirement slope
const AGE_LO = 65
const AGE_HI = 90                 # headline survivor-window endpoint
const N_SIM = 2500                # target simulated paths per wealth band; the
                                   # uniform replication factor K is derived from
                                   # this and the band sizes (see K_REPS below)
const HEADLINE_SEED = 42
const SENS_SEEDS = (42, 123, 777)
const SENS_AGE_HI = (85, 90, 95)  # survivor-window endpoints (age_lo fixed at 65)

hrs = readdlm(HRS_PATH, ',', Any; skipstart=1)
wealth_all = Float64.(hrs[:, 1])
health_all = Float64.(hrs[:, 4])
keep = wealth_all .>= MIN_WEALTH
wealth_all = wealth_all[keep]; health_all = health_all[keep]

p_base = ModelParams(age_start=AGE_START, age_end=AGE_END)
const BASE_SURV = production_base_survival(p_base)

# Grids and the fair (mwr=1.0) payout rate are invariant to delta_c and to the
# band's SS level, so build them once.
const GKW = (n_wealth=N_WEALTH, n_annuity=N_ANNUITY, n_alpha=N_ALPHA, W_max=W_MAX,
             age_start=AGE_START, age_end=AGE_END, annuity_grid_power=A_GRID_POW)
const FAIR_PR = compute_payout_rate(
    ModelParams(; gamma=GAMMA, beta=BETA, r=R_RATE, mwr=1.0, GKW...), BASE_SURV)
const GRIDS = build_grids(
    ModelParams(; gamma=GAMMA, beta=BETA, r=R_RATE, mwr=1.0, GKW...), FAIR_PR)

# Band assignment (fixed dollar breaks, matching the ownership analysis).
band_of(w) = w < SS_QUARTILE_BREAKS[1] ? 1 :
             w < SS_QUARTILE_BREAKS[2] ? 2 :
             w < SS_QUARTILE_BREAKS[3] ? 3 : 4

const BAND_IDX = [findall(w -> band_of(w) == q, wealth_all) for q in 1:4]
const BAND_N = [length(BAND_IDX[q]) for q in 1:4]
const SS_FUNCS = [let ss_q = Float64(SS_QUARTILE_LEVELS[q]); (age, pp) -> ss_q; end
                  for q in 1:4]

# Uniform replication factor: one K for all bands preserves the pooled
# population weighting (replicated counts stay proportional to true band sizes).
const K_REPS = max(1, round(Int, N_SIM / mean(BAND_N)))
# No-private-annuity initial states (A = 0), each band replicated K_REPS times.
const INITS_REP = [repeat(hcat(wealth_all[BAND_IDX[q]], health_all[BAND_IDX[q]]),
                          outer=(K_REPS, 1)) for q in 1:4]

make_p(delta_c) = ModelParams(; gamma=GAMMA, beta=BETA, r=R_RATE,
    stochastic_health=true, n_health_states=3, n_quad=N_QUAD, c_floor=C_FLOOR,
    hazard_mult=Float64.(HAZARD_MULT), hazard_normalize=HAZARD_NORMALIZE,
    theta=THETA_DFJ, kappa=KAPPA_DFJ, mwr=MWR_LOADED, fixed_cost=FIXED_COST,
    min_purchase=MIN_PURCHASE, inflation_rate=INFLATION, medical_enabled=true,
    health_mortality_corr=true, survival_pessimism=SURVIVAL_PESSIMISM,
    consumption_decline=delta_c, health_utility=Float64.(HEALTH_UTILITY),
    chi_ltc=CHI_LTC, GKW...)

# Caches. Solving the four bands is the cost; the bisections (headline plus the
# nine sensitivity cells) revisit the same delta_c values, so cache the solved
# bands by delta_c and the pooled consumption curve by (delta_c, seed). Windows
# sharing a seed reuse one curve.
dkey(d) = round(d, digits=6)
const SOL_CACHE = Dict{Float64, Vector{HealthSolution}}()
const CURVE_CACHE = Dict{Tuple{Float64, Int}, Vector{Float64}}()

function solve_bands(delta_c::Float64)
    k = dkey(delta_c)
    haskey(SOL_CACHE, k) && return SOL_CACHE[k]
    p = make_p(delta_c)
    sols = [solve_lifecycle_health(p, GRIDS, BASE_SURV, SS_FUNCS[q]) for q in 1:4]
    SOL_CACHE[k] = sols
    return sols
end

# Population-pooled mean consumption by age for a no-private-annuity household
# under a candidate delta_c and rng seed, holding all other production
# parameters fixed.
function mean_c_curve(delta_c::Float64, seed::Int)
    ck = (dkey(delta_c), seed)
    haskey(CURVE_CACHE, ck) && return CURVE_CACHE[ck]
    p = make_p(delta_c)
    sols = solve_bands(delta_c)
    T = p.T
    cons_sum = zeros(T); alive = zeros(T)
    for q in 1:4
        isempty(BAND_IDX[q]) && continue
        batch = simulate_batch(sols[q], INITS_REP[q], 0.0, BASE_SURV, SS_FUNCS[q], p;
                               rng_seed=seed)
        nrow = size(INITS_REP[q], 1)
        for t in 1:T
            n_t = batch.alive_fraction[t] * nrow
            cons_sum[t] += batch.mean_consumption_by_age[t] * n_t
            alive[t] += n_t
        end
    end
    curve = [alive[t] > 0 ? cons_sum[t] / alive[t] : NaN for t in 1:T]
    CURVE_CACHE[ck] = curve
    return curve
end

# Geometric annual decline of pooled mean consumption over [AGE_LO, age_hi].
function slope(delta_c::Float64, seed::Int, age_hi::Int)
    c = mean_c_curve(delta_c, seed)
    t_lo = AGE_LO - AGE_START + 1
    t_hi = age_hi - AGE_START + 1
    return 1.0 - (c[t_hi] / c[t_lo])^(1.0 / (age_hi - AGE_LO))
end

# Bisect delta_c so the survivor-conditioned slope over [65, age_hi] equals the
# 2% target. slope is increasing in delta_c. Returns (delta_c, achieved_slope).
function calibrate(seed::Int, age_hi::Int; tol::Float64, maxit::Int)
    base = slope(0.0, seed, age_hi)
    if base >= TARGET_DECLINE
        return (0.0, base)   # environment already declines at/above target
    end
    lo, hi = 0.0, 0.02
    while slope(hi, seed, age_hi) < TARGET_DECLINE && hi < 0.16
        hi *= 2
    end
    d = hi; achieved = slope(hi, seed, age_hi)
    for it in 1:maxit
        mid = (lo + hi) / 2
        s = slope(mid, seed, age_hi)
        s < TARGET_DECLINE ? (lo = mid) : (hi = mid)
        d = mid; achieved = s
        abs(s - TARGET_DECLINE) < tol && break
    end
    return (d, achieved)
end

@printf("Recalibrating delta_c to a %.1f%%/yr no-annuity consumption decline (ages %d-%d)\n",
    TARGET_DECLINE * 100, AGE_LO, AGE_HI)
@printf("  bands n = %s; uniform replication K = %d (draws/band = %s)\n",
    string(BAND_N), K_REPS, string(K_REPS .* BAND_N))
flush(stdout)

base_slope = slope(0.0, HEADLINE_SEED, AGE_HI)
@printf("  delta_c=0 baseline slope (mortality+medical only): %.4f (%.2f%%/yr)\n",
    base_slope, base_slope * 100)
flush(stdout)

# --- Headline: seed 42, window 65-90, fine tolerance ---
target_delta, achieved = calibrate(HEADLINE_SEED, AGE_HI; tol=1e-4, maxit=12)
@printf("\n  Headline calibrated delta_c = %.4f  (achieved slope %.4f)\n",
    target_delta, achieved)
flush(stdout)

# Consistency guard: the production constant CONSUMPTION_DECLINE should equal the
# freshly-derived headline value (within rounding), or the config is stale.
if abs(target_delta - CONSUMPTION_DECLINE) > 5e-4
    @warn "Calibrated delta_c differs from config CONSUMPTION_DECLINE" calibrated=target_delta config=CONSUMPTION_DECLINE
end

out = joinpath(@__DIR__, "..", "tables", "csv", "age_needs_calibration.csv")
open(out, "w") do io
    println(io, "target_decline,baseline_slope_delta0,calibrated_delta_c,achieved_slope,age_lo,age_hi")
    @printf(io, "%.4f,%.6f,%.6f,%.6f,%d,%d\n",
        TARGET_DECLINE, base_slope, target_delta, achieved, AGE_LO, AGE_HI)
end
println("Wrote $out")
flush(stdout)

# --- Sensitivity: {seed} x {age_hi}, coarser tolerance to keep compute bounded.
# Reports the delta_c range; the headline stays seed=42, window 65-90.
println("\n  Sensitivity of delta_c to rng seed and survivor-window endpoint:")
@printf("  %6s %7s %10s %12s\n", "seed", "age_hi", "delta_c", "ach_slope")
sens_rows = Any[]
for seed in SENS_SEEDS, age_hi in SENS_AGE_HI
    d, s = calibrate(seed, age_hi; tol=1e-3, maxit=6)
    push!(sens_rows, (seed, age_hi, d, s))
    @printf("  %6d %7d %10.6f %12.6f\n", seed, age_hi, d, s)
    flush(stdout)
end

sens_deltas = [r[3] for r in sens_rows]
@printf("\n  delta_c range across seeds x windows: [%.6f, %.6f] (spread %.6f)\n",
    minimum(sens_deltas), maximum(sens_deltas), maximum(sens_deltas) - minimum(sens_deltas))

sens_out = joinpath(@__DIR__, "..", "tables", "csv", "age_needs_sensitivity.csv")
open(sens_out, "w") do io
    println(io, "seed,age_hi,delta_c,achieved_slope")
    for (seed, age_hi, d, s) in sens_rows
        @printf(io, "%d,%d,%.6f,%.6f\n", seed, age_hi, d, s)
    end
end
println("Wrote $sens_out")
