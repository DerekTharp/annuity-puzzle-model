# Recalibrate the age-varying-needs weight decline (delta_c) so the model's
# simulated no-annuity retirement consumption path declines at the empirical
# target, rather than mapping an observed expenditure decline directly onto the
# felicity weight (a 2% weight decline is not a 2% consumption decline; the map
# runs through the Euler equation and depends on gamma, beta, mortality, and
# the medical/floor environment).
#
# Target: Aguiar and Hurst (2013, JPE), non-durable retirement expenditure
# decline of ~2%/yr. We bisect delta_c so the population-pooled mean
# consumption of a no-private-annuity household declines at that geometric
# rate over ages 65-90 in the full production model.
#
# Output: tables/csv/age_needs_calibration.csv (delta_c, target, achieved slope,
# and the delta_c=0 baseline slope for the over-attribution disclosure).
#
# Usage: julia --project=. scripts/recalibrate_age_needs.jl

using DelimitedFiles, Printf
include(joinpath(@__DIR__, "..", "src", "AnnuityPuzzle.jl"))
using .AnnuityPuzzle
include(joinpath(@__DIR__, "config.jl"))

const TARGET_DECLINE = 0.02       # Aguiar-Hurst non-durable retirement slope
const AGE_LO = 65
const AGE_HI = 90                 # survival thins past 90; AH is a retirement fact
const N_SIM = 5_000

hrs = readdlm(HRS_PATH, ',', Any; skipstart=1)
wealth_all = Float64.(hrs[:, 1])
health_all = Float64.(hrs[:, 4])
keep = wealth_all .>= MIN_WEALTH
wealth_all = wealth_all[keep]; health_all = health_all[keep]

p_base = ModelParams(age_start=AGE_START, age_end=AGE_END)
base_surv = production_base_survival(p_base)

# Band assignment (fixed dollar breaks, matching the ownership analysis).
band_of(w) = w < SS_QUARTILE_BREAKS[1] ? 1 :
             w < SS_QUARTILE_BREAKS[2] ? 2 :
             w < SS_QUARTILE_BREAKS[3] ? 3 : 4

# Population-pooled mean consumption by age for a no-private-annuity household
# under a candidate delta_c, holding all other production parameters fixed.
function simulated_slope(delta_c::Float64)
    gkw = (n_wealth=N_WEALTH, n_annuity=N_ANNUITY, n_alpha=N_ALPHA, W_max=W_MAX,
           age_start=AGE_START, age_end=AGE_END, annuity_grid_power=A_GRID_POW)
    p = ModelParams(; gamma=GAMMA, beta=BETA, r=R_RATE, stochastic_health=true,
        n_health_states=3, n_quad=N_QUAD, c_floor=C_FLOOR,
        hazard_mult=Float64.(HAZARD_MULT), hazard_normalize=HAZARD_NORMALIZE,
        theta=THETA_DFJ, kappa=KAPPA_DFJ, mwr=MWR_LOADED, fixed_cost=FIXED_COST,
        min_purchase=MIN_PURCHASE, inflation_rate=INFLATION, medical_enabled=true,
        health_mortality_corr=true, survival_pessimism=SURVIVAL_PESSIMISM,
        consumption_decline=delta_c, health_utility=Float64.(HEALTH_UTILITY),
        chi_ltc=CHI_LTC, gkw...)
    T = p.T
    cons_sum = zeros(T); alive = zeros(T)
    for q in 1:4
        idx = findall(w -> band_of(w) == q, wealth_all)
        isempty(idx) && continue
        ss_q = Float64(SS_QUARTILE_LEVELS[q])
        ss_func = (age, pp) -> ss_q
        grids = build_grids(p, compute_payout_rate(ModelParams(; gamma=GAMMA,
            beta=BETA, r=R_RATE, mwr=1.0, gkw...), base_surv))
        sol = solve_lifecycle_health(p, grids, base_surv, ss_func)
        inits = hcat(wealth_all[idx], health_all[idx])   # no private annuity: A=0
        batch = simulate_batch(sol, inits, 0.0, base_surv, ss_func, p)
        for t in 1:T
            n_t = batch.alive_fraction[t] * size(inits, 1)
            cons_sum[t] += batch.mean_consumption_by_age[t] * n_t
            alive[t] += n_t
        end
    end
    mean_c = [alive[t] > 0 ? cons_sum[t] / alive[t] : NaN for t in 1:T]
    t_lo = AGE_LO - AGE_START + 1; t_hi = AGE_HI - AGE_START + 1
    # Geometric annual decline rate over [65, 90].
    return 1.0 - (mean_c[t_hi] / mean_c[t_lo])^(1.0 / (AGE_HI - AGE_LO))
end

@printf("Recalibrating delta_c to a %.1f%%/yr no-annuity consumption decline (ages %d-%d)\n",
    TARGET_DECLINE * 100, AGE_LO, AGE_HI)
flush(stdout)

base_slope = simulated_slope(0.0)
@printf("  delta_c=0 baseline slope (mortality+medical only): %.4f (%.2f%%/yr)\n",
    base_slope, base_slope * 100)

# Bisection: slope is increasing in delta_c. Wrapped in a function to avoid
# top-level soft-scope ambiguity.
function calibrate(base_slope)
    if base_slope >= TARGET_DECLINE
        @printf("  Baseline already declines at/above target; needs channel is redundant.\n")
        return (0.0, base_slope)
    end
    lo, hi = 0.0, 0.08
    target_delta = 0.0; achieved = base_slope
    for it in 1:18
        mid = (lo + hi) / 2
        s = simulated_slope(mid)
        @printf("    iter %2d: delta_c=%.4f -> slope %.4f\n", it, mid, s); flush(stdout)
        if s < TARGET_DECLINE; lo = mid; else; hi = mid; end
        target_delta = mid; achieved = s
        abs(s - TARGET_DECLINE) < 1e-4 && break
    end
    return (target_delta, achieved)
end
target_delta, achieved = calibrate(base_slope)

@printf("\n  Calibrated delta_c = %.4f  (achieved slope %.4f)\n", target_delta, achieved)

# Consistency guard: the production constant CONSUMPTION_DECLINE must equal the
# freshly-derived value (within rounding), or the config is stale.
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
