# Calibrate psi_purchase to the Chalmers-Reuter (2012) Oregon PERS
# default-vs-opt-in elasticity.
#
# Chalmers and Reuter (2012, JFE) document a 35 pp gap in annuity ownership
# between Oregon PERS retirees facing the annuity-as-default condition (~50%
# elect annuity) and the lump-sum-as-default condition (~15% elect annuity).
# Under the bundled-friction interpretation, this gap measures the magnitude
# of behavioral barriers (narrow framing, evaluation cost, mental accounting)
# that change in default condition can flip on or off.
#
# Calibration strategy: psi_purchase = 0 corresponds to the no-friction case
# (annuity-as-default eliminates the at-purchase loss-aversion stream because
# the household never actively confronts the underwater period). The opt-in
# condition activates the at-purchase penalty at intensity psi_purchase. We
# bisect psi_purchase to match the 35 pp gap in HRS-population predicted
# ownership, holding all other Model 1 channels active.
#
# Output: writes the calibrated value to results/psi_calibration.toml so
# downstream stages (run_subset_enumeration.jl, export_manuscript_numbers.jl)
# can consume the calibration without rerunning the bisection.
#
# Usage: julia --project=. scripts/calibrate_psi_chalmers_reuter.jl

using Printf
using DelimitedFiles
using TOML
using Distributed

if nworkers() > 1
    @everywhere include(joinpath(@__DIR__, "..", "src", "AnnuityPuzzle.jl"))
    @everywhere using .AnnuityPuzzle
else
    include(joinpath(@__DIR__, "..", "src", "AnnuityPuzzle.jl"))
    using .AnnuityPuzzle
end

include(joinpath(@__DIR__, "config.jl"))

println("=" ^ 70)
println("  PSI_PURCHASE CALIBRATION — Chalmers-Reuter (2012) Oregon PERS")
println("=" ^ 70)
@printf("  Target gap (default - opt-in): %.1f pp\n",
    CHALMERS_REUTER_GAP_TARGET * 100)
flush(stdout)

# ===================================================================
# Load HRS population sample
# ===================================================================
println("\nLoading HRS population sample...")
hrs_raw = readdlm(HRS_PATH, ',', Any; skipstart=1)
assert_hrs_schema(hrs_raw, HRS_PATH)
n_pop = size(hrs_raw, 1)
population = zeros(n_pop, 4)
population[:, 1] = Float64.(hrs_raw[:, 1])
population[:, 2] .= 0.0
population[:, 3] = Float64.(hrs_raw[:, 3])
if size(hrs_raw, 2) >= 4
    population[:, 4] = Float64.(hrs_raw[:, 4])
else
    population[:, 4] .= 2.0
end
@printf("  Loaded %d individuals\n", n_pop)
flush(stdout)

# ===================================================================
# Survival, payout rates, grids
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

grids = build_grids(p_fair, max(fair_pr, fair_pr_nom))
loaded_pr = MWR_LOADED * fair_pr_nom

# ===================================================================
# Solve a single (psi, lambda_w) point and return ownership rate.
# All Model 1 rational + preference + structural channels are held active
# so the calibration measures only the marginal contribution of the
# at-purchase penalty, not the joint effect of all behavioral channels.
# ===================================================================
ss_func_q(age, p) = 0.0  # SS via per-quartile dispatch below

function solve_ownership(psi_val::Float64; lambda_w_val::Float64=1.0)
    common_kw = (gamma=GAMMA, beta=BETA, r=R_RATE,
                 stochastic_health=true, n_health_states=3, n_quad=N_QUAD,
                 c_floor=C_FLOOR, hazard_mult=Float64.(HAZARD_MULT))

    # Per-quartile solve (SS levels differ across quartiles)
    ss_levels = Float64.(SS_QUARTILE_LEVELS)
    breaks = Float64.(SS_QUARTILE_BREAKS)

    total_owners = 0.0
    total_n = 0.0

    for q in 1:4
        ss_val = ss_levels[q]
        ss_func_q_local = (age, p) -> ss_val

        p_model = ModelParams(; common_kw...,
            theta=THETA_DFJ, kappa=KAPPA_DFJ,
            mwr=MWR_LOADED, fixed_cost=FIXED_COST,
            min_purchase=MIN_PURCHASE,
            inflation_rate=INFLATION,
            medical_enabled=true, health_mortality_corr=true,
            survival_pessimism=SURVIVAL_PESSIMISM,
            consumption_decline=CONSUMPTION_DECLINE,
            health_utility=Float64.(HEALTH_UTILITY),
            chi_ltc=CHI_LTC,
            lambda_w=lambda_w_val,
            psi_purchase=psi_val,
            psi_purchase_c_ref=PSI_PURCHASE_C_REF,
            grid_kw...)

        sol = solve_lifecycle_health(p_model, grids, base_surv, ss_func_q_local)

        # Filter population to this quartile
        mask = if q == 1
            population[:, 1] .< breaks[1]
        elseif q == 2
            (population[:, 1] .>= breaks[1]) .& (population[:, 1] .< breaks[2])
        elseif q == 3
            (population[:, 1] .>= breaks[2]) .& (population[:, 1] .< breaks[3])
        else
            population[:, 1] .>= breaks[3]
        end
        pop_q = population[mask, :]
        n_q = size(pop_q, 1)
        n_q == 0 && continue

        result = compute_ownership_rate_health(
            sol, pop_q, loaded_pr; base_surv=base_surv,
        )
        total_owners += result.ownership_rate * n_q
        total_n += n_q
    end

    return total_n > 0 ? total_owners / total_n : 0.0
end

# ===================================================================
# Anchor: ownership at psi=0 (default condition equivalent — no
# at-purchase friction)
# ===================================================================
println("\nSolving default-condition baseline (psi_purchase = 0, lambda_w = $(LAMBDA_W))...")
flush(stdout)
t0 = time()
own_default = solve_ownership(0.0; lambda_w_val=LAMBDA_W)
@printf("  Default-condition ownership: %.2f%%  (%.1fs)\n",
    own_default * 100, time() - t0)
flush(stdout)

target_optin = own_default - CHALMERS_REUTER_GAP_TARGET
@printf("  Target opt-in ownership:    %.2f%%  (%.1f pp gap)\n",
    target_optin * 100, CHALMERS_REUTER_GAP_TARGET * 100)
flush(stdout)

if target_optin <= 0.0
    @printf("\n  WARNING: target_optin is non-positive (%.2f%%). The default-\n",
        target_optin * 100)
    @printf("  condition baseline (%.2f%%) is below the Chalmers-Reuter gap\n",
        own_default * 100)
    @printf("  (%.1f pp). The model cannot reach the calibration target by\n",
        CHALMERS_REUTER_GAP_TARGET * 100)
    println("  adding the at-purchase penalty alone. Pinning psi at the upper")
    println("  bracket and reporting partial calibration.")
    flush(stdout)
end

# ===================================================================
# Bisection on psi to hit target_optin.
# Wrapped in a function to give the bracket/bisection state a proper
# local scope — top-level `while`/`for` loops in Julia 1.10+ create a
# soft local scope that does not write back to outer-scope bindings,
# so `psi_hi *= 2` inside a top-level loop fails with UndefVarError.
# ===================================================================
function bisect_psi(own_default::Float64, target_optin::Float64)
    psi_lo = 0.0
    psi_hi = 5.0  # upper bracket — reduce if calibration converges quickly
    own_lo = own_default
    own_hi = solve_ownership(psi_hi; lambda_w_val=LAMBDA_W)
    @printf("\n  Bracket: psi in [%.3f, %.3f] -> ownership in [%.2f%%, %.2f%%]\n",
        psi_lo, psi_hi, own_lo * 100, own_hi * 100)
    flush(stdout)

    # Expand bracket if needed
    expansion_iters = 0
    while own_hi > target_optin && expansion_iters < 5
        psi_hi *= 2
        own_hi = solve_ownership(psi_hi; lambda_w_val=LAMBDA_W)
        @printf("  Expanded bracket: psi_hi -> %.3f, ownership = %.2f%%\n",
            psi_hi, own_hi * 100)
        expansion_iters += 1
        flush(stdout)
    end

    # Bisect
    println("\nBisecting...")
    flush(stdout)
    psi_calibrated = NaN
    own_calibrated = NaN
    for iter in 1:25
        psi_mid = 0.5 * (psi_lo + psi_hi)
        own_mid = solve_ownership(psi_mid; lambda_w_val=LAMBDA_W)
        @printf("  iter %2d: psi = %.4f -> ownership = %.3f%%  (target %.3f%%)\n",
            iter, psi_mid, own_mid * 100, target_optin * 100)
        flush(stdout)

        if abs(own_mid - target_optin) < 0.002  # 0.2 pp tolerance
            psi_calibrated = psi_mid
            own_calibrated = own_mid
            break
        end

        if own_mid > target_optin
            psi_lo = psi_mid
            own_lo = own_mid
        else
            psi_hi = psi_mid
            own_hi = own_mid
        end
    end

    if isnan(psi_calibrated)
        psi_calibrated = 0.5 * (psi_lo + psi_hi)
        own_calibrated = solve_ownership(psi_calibrated; lambda_w_val=LAMBDA_W)
    end

    return psi_calibrated, own_calibrated
end

psi_calibrated, own_calibrated = bisect_psi(own_default, target_optin)

@printf("\n  Calibrated psi_purchase: %.4f\n", psi_calibrated)
@printf("  Implied opt-in ownership: %.2f%%\n", own_calibrated * 100)
@printf("  Implied gap:              %.2f pp  (target %.2f pp)\n",
    (own_default - own_calibrated) * 100,
    CHALMERS_REUTER_GAP_TARGET * 100)
flush(stdout)

# ===================================================================
# Persist calibration
# ===================================================================
results_dir = joinpath(@__DIR__, "..", "results")
mkpath(results_dir)
out_path = joinpath(results_dir, "psi_calibration.toml")
open(out_path, "w") do f
    TOML.print(f, Dict(
        "psi_purchase_calibrated" => psi_calibrated,
        "lambda_w_used" => LAMBDA_W,
        "psi_purchase_c_ref" => PSI_PURCHASE_C_REF,
        "default_ownership" => own_default,
        "optin_ownership_calibrated" => own_calibrated,
        "target_gap" => CHALMERS_REUTER_GAP_TARGET,
        "implied_gap" => own_default - own_calibrated,
        "source" => "Chalmers-Reuter (2012) Oregon PERS, 35 pp default-vs-opt-in",
    ))
end
println("\n  Calibration written to: $out_path")
flush(stdout)
