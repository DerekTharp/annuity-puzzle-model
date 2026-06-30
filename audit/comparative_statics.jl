# Dynamic correctness battery for the full health model.
# Solves the model under the headline per-household configuration and checks the
# unambiguous comparative-static signs and limiting cases from the project's
# correctness oracle (CLAUDE.md sections 8 and 4.5). Uses the scalar outputs of
# solve_and_evaluate (ownership, mean_alpha) so it does not depend on value-
# function internals. Coarse grid for speed; the SIGNS, not the levels, are the
# object of the test.
#
# Run: julia --project=. audit/comparative_statics.jl
# Output: prints PASS/FAIL per check and a final count; nonzero exit if any FAIL.

using Printf, DelimitedFiles

include(joinpath(@__DIR__, "..", "src", "AnnuityPuzzle.jl"))
using .AnnuityPuzzle
include(joinpath(@__DIR__, "..", "scripts", "config.jl"))

const SS_MEAN = sum(SS_QUARTILE_LEVELS) / length(SS_QUARTILE_LEVELS)

# Coarse grid for speed; comparative-static signs are insensitive to it.
const NW = 40
const NA = 15
const NALPHA = 51

base_surv = build_lockwood_survival(ModelParams(age_start=AGE_START, age_end=AGE_END))

hrs_raw = readdlm(joinpath(@__DIR__, "..", "data", "processed", "lockwood_hrs_sample.csv"),
                  ',', Any; skipstart=1)
n_pop = size(hrs_raw, 1)
population = zeros(n_pop, 4)
population[:, 1] = Float64.(hrs_raw[:, 1])
population[:, 2] .= 0.0
population[:, 3] = Float64.(hrs_raw[:, 3])
population[:, 4] = size(hrs_raw, 2) >= 4 ? Float64.(hrs_raw[:, 4]) : fill(2.0, n_pop)
population = population[population[:, 1] .>= MIN_WEALTH, :]

# Solve the full model under a one-parameter perturbation of the headline config
# and return (ownership, mean_alpha). Mirrors grid_convergence_full.jl exactly.
function solve_alpha(; gamma=GAMMA, beta=BETA, r=R_RATE, mwr_loaded=MWR_LOADED,
                       inflation=INFLATION, theta=THETA_DFJ, kappa=KAPPA_DFJ,
                       psi=SURVIVAL_PESSIMISM, hm=Float64.(HAZARD_MULT), chi_ltc=CHI_LTC,
                       lambda_w=1.0, psi_purchase=0.0,
                       medical=true, corr=true, stochastic_health=true,
                       ss_level=SS_MEAN, c_floor=C_FLOOR, fixed_cost=FIXED_COST)
    grid_kw = (n_wealth=NW, n_annuity=NA, n_alpha=NALPHA, W_max=W_MAX,
               age_start=AGE_START, age_end=AGE_END, annuity_grid_power=A_GRID_POW)

    p_fair_nom = ModelParams(; gamma=gamma, beta=beta, r=r, mwr=1.0,
                               inflation_rate=inflation, grid_kw...)
    fair_pr_nom = compute_payout_rate(p_fair_nom, base_surv)
    loaded_pr_nom = mwr_loaded * fair_pr_nom

    p_fair = ModelParams(; gamma=gamma, beta=beta, r=r, mwr=1.0, grid_kw...)
    fair_pr = compute_payout_rate(p_fair, base_surv)
    grids = build_grids(p_fair, max(fair_pr, fair_pr_nom))

    p_full = ModelParams(; gamma=gamma, beta=beta, r=r, theta=theta, kappa=kappa,
        stochastic_health=stochastic_health, n_health_states=3, n_quad=N_QUAD,
        c_floor=c_floor, hazard_mult=hm, mwr=mwr_loaded, fixed_cost=fixed_cost,
        inflation_rate=inflation, medical_enabled=medical,
        health_mortality_corr=corr, survival_pessimism=psi,
        consumption_decline=CONSUMPTION_DECLINE, health_utility=Float64.(HEALTH_UTILITY),
        chi_ltc=chi_ltc, lambda_w=lambda_w, psi_purchase=psi_purchase,
        psi_purchase_c_ref=PSI_PURCHASE_C_REF, grid_kw...)

    ss_func(age, pp) = ss_level
    res = solve_and_evaluate(p_full, grids, base_surv, ss_func, population,
                             loaded_pr_nom; verbose=false)
    return (own=res.ownership, alpha=res.mean_alpha)
end

# --- Test harness -----------------------------------------------------------
const TOL = 1e-4              # mean_alpha must move by more than this to count as a move
results = Tuple{String,Bool,String}[]   # (name, pass, detail)

function check(name, pass, detail)
    @printf("  [%s] %-46s  %s\n", pass ? "PASS" : "FAIL", name, detail)
    flush(stdout)
    push!(results, (name, pass, detail))
end

# A relational check: a_perturbed should be LOWER / HIGHER / HIGH / LOW.
lower(a, b)  = a < b - TOL
higher(a, b) = a > b + TOL

println("=" ^ 72)
println("  DYNAMIC CORRECTNESS BATTERY (full health model, coarse grid $(NW)x$(NA))")
println("=" ^ 72)
@printf("  Population n=%d (wealth >= \$%.0f); SS_mean=\$%.0f\n", size(population,1), MIN_WEALTH, SS_MEAN)
flush(stdout)

# Baseline headline config (single-solve, mean SS).
println("\n--- baseline ---")
base = solve_alpha()
@printf("  baseline: ownership=%.4f  mean_alpha=%.5f\n", base.own, base.alpha)
flush(stdout)

# ===================== LIMITING CASES =====================
println("\n--- limiting cases ---")

# Yaari-ish: all frictions off (no bequest, fair pricing, no fixed cost, no
# inflation, no medical, no health-mortality corr, no pessimism, no LTC), near-
# zero SS and safety net. Expect HIGH annuitization.
yaari = solve_alpha(theta=0.0, mwr_loaded=1.0, fixed_cost=0.0, inflation=0.0,
                    medical=false, corr=false, psi=1.0, chi_ltc=1.0,
                    ss_level=1.0, c_floor=1.0)
check("Yaari (all frictions off) -> high alpha", yaari.alpha > 0.5,
      @sprintf("mean_alpha=%.3f own=%.3f (want alpha>0.5)", yaari.alpha, yaari.own))

# Infinite bequest weight -> alpha ~ 0.
inf_beq = solve_alpha(theta=1.0e6)
check("Infinite bequest -> alpha ~ 0", inf_beq.alpha < 0.02,
      @sprintf("mean_alpha=%.4f (want <0.02)", inf_beq.alpha))

# ===================== COMPARATIVE STATICS (unambiguous oracle signs) =====================
println("\n--- comparative statics (sign vs baseline) ---")

# alpha DECREASES in bequest intensity theta.
hi_theta = solve_alpha(theta=THETA_DFJ * 4)
check("alpha decreasing in bequest theta", lower(hi_theta.alpha, base.alpha),
      @sprintf("theta x4: %.5f vs base %.5f", hi_theta.alpha, base.alpha))

# alpha INCREASES in MWR (less load).
hi_mwr = solve_alpha(mwr_loaded=min(MWR_LOADED + 0.10, 1.0))
check("alpha increasing in MWR", higher(hi_mwr.alpha, base.alpha),
      @sprintf("MWR+0.10: %.5f vs base %.5f", hi_mwr.alpha, base.alpha))

# alpha DECREASES in inflation (nominal annuity erosion).
hi_inf = solve_alpha(inflation=INFLATION + 0.03)
check("alpha decreasing in inflation", lower(hi_inf.alpha, base.alpha),
      @sprintf("inf+3pp: %.5f vs base %.5f", hi_inf.alpha, base.alpha))

# alpha DECREASES with more survival pessimism (lower psi = perceive shorter life).
lo_psi = solve_alpha(psi=SURVIVAL_PESSIMISM - 0.05)
check("alpha decreasing with more survival pessimism", lower(lo_psi.alpha, base.alpha),
      @sprintf("psi-0.05: %.5f vs base %.5f", lo_psi.alpha, base.alpha))

# alpha DECREASES in pre-existing SS income (diminishing marginal insurance).
hi_ss = solve_alpha(ss_level=SS_MEAN * 2)
check("alpha decreasing in pre-existing SS", lower(hi_ss.alpha, base.alpha),
      @sprintf("SS x2: %.5f vs base %.5f", hi_ss.alpha, base.alpha))

# alpha LOWER with health-mortality correlation ON vs OFF (Reichling-Smetters).
corr_off = solve_alpha(corr=false)
check("alpha lower with R-S correlation ON (vs off)", lower(base.alpha, corr_off.alpha),
      @sprintf("corr-on %.5f vs corr-off %.5f", base.alpha, corr_off.alpha))

# chi_ltc is mildly PRO-annuity: LTC aversion ON (chi_ltc<1) -> alpha >= LTC off (chi_ltc=1).
ltc_off = solve_alpha(chi_ltc=1.0)
check("chi_ltc pro-annuity (on >= off)", base.alpha >= ltc_off.alpha - TOL,
      @sprintf("chi_ltc-on %.5f vs off %.5f", base.alpha, ltc_off.alpha))

# Behavioral: lambda_w < 1 (source-dependent utility) is demand-BOOSTING. It
# discounts asset-funded consumption relative to income-funded consumption, so
# annuitizing (converting assets to a guaranteed income stream) escapes the
# discount and raises demand. Opposite sign to the purchase-event channel below.
sdu = solve_alpha(lambda_w=0.625)
check("lambda_w<1 (SDU) demand-boosting", higher(sdu.alpha, base.alpha),
      @sprintf("lambda_w=0.625 %.5f vs base %.5f", sdu.alpha, base.alpha))

# Behavioral: psi_purchase > 0 (purchase-event disutility) is demand-suppressing.
ped = solve_alpha(psi_purchase=0.05)
check("psi_purchase>0 (PED) demand-suppressing", lower(ped.alpha, base.alpha),
      @sprintf("psi_purchase=0.05 %.5f vs base %.5f", ped.alpha, base.alpha))

# ===================== RED FLAGS =====================
println("\n--- red flags ---")

# Full model ownership should not exceed 20%.
check("full-model ownership <= 20%", base.own <= 0.20,
      @sprintf("ownership=%.4f (want <=0.20)", base.own))

# ===================== SUMMARY =====================
npass = count(r -> r[2], results)
ntot = length(results)
println("\n" * "=" ^ 72)
@printf("  BATTERY RESULT: %d/%d checks passed\n", npass, ntot)
if npass < ntot
    println("  FAILURES:")
    for (name, pass, detail) in results
        pass || @printf("    - %s | %s\n", name, detail)
    end
end
println("=" ^ 72)
flush(stdout)

exit(npass == ntot ? 0 : 1)
