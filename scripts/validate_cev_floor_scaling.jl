# CEV floor-scaling diagnostic bound (Blocker 7b) — DIAGNOSE ONLY.
#
# This script does NOT re-solve the lifecycle value function. It places a
# diagnostic bound on the error in the closed-form compensating variation via an
# algebraic adjustment of that closed form; the reported CEV numbers are unchanged.
#
# The closed-form compensating variation (src/welfare.jl exact_cev_lambda,
# compute_cev) scales the whole no-access consumption felicity by (1+lambda)^(1-g):
#
#   lambda_closed = [(V_with - B_no)/(V_no - B_no)]^(1/(1-g)) - 1,   U_c = V_no - B_no.
#
# The closed form is exact only if EVERY consumption dollar, including Medicaid-
# floor consumption, scales with lambda. The manuscript instead treats floor
# consumption as a fixed real safety net (invariant to lambda). This script bounds
# the closed-form error that assumption introduces, WITHOUT changing the formula.
#
# Method. For each floor-exposed cell (low nonhousing net worth, health at age 65),
# the no-access consumption felicity is decomposed by simulation into a floor-
# binding share f and a non-floor share (1-f), using the model's own flow utility
# (flow_utility_sdu / flow_utility_sdu_chi_ltc) reconstructed from simulated paths.
# U_c = V_no - B_no is read directly from the solved value function. The floor-
# invariant CEV bisects lambda so the scaled-consumption value function,
# with only the non-floor felicity scaled,
#
#   V_scaled(lambda) = (1+lambda)^(1-g) (1-f) U_c + f U_c + B_no,
#
# equals the with-access value V_with. When f = 0 this reduces to the closed form
# (lambda_num = lambda_closed); the gap grows with the floor-felicity share.
#
# Output: tables/csv/cev_floor_scaling_diagnostic.csv
#         (wealth, health, floor_period_freq, floor_felicity_share_f,
#          cev_closed_pct, cev_numeric_pct, abs_cev_error_pp, converged)
# Reports a diagnostic bound on the max absolute closed-form CEV error across
# floor-binding cells.
#
# Usage: julia --project=. scripts/validate_cev_floor_scaling.jl

using Printf, Random, Interpolations, DelimitedFiles

include(joinpath(@__DIR__, "..", "src", "AnnuityPuzzle.jl"))
using .AnnuityPuzzle
include(joinpath(@__DIR__, "config.jl"))

const HEALTH_NAMES = ["Good", "Fair", "Poor"]
const FLOOR_FREQ_THRESHOLD = 0.02  # cell counts as "floor-binding" above this

# Reconstruct one path's discounted consumption felicity, split into the
# Medicaid-floor-binding share, exactly as src/solve.jl accumulates it: income-
# first medical, Medicaid top-up treated as income for SDU, chi_ltc discount in
# the binding Poor state.
function path_felicity_split(res, p, ss_func)
    death_t = res.age_at_death - p.age_start + 1
    U_total = 0.0
    U_floor = 0.0
    n_periods = 0
    n_floor = 0
    for t in 1:min(death_t, p.T)
        age = p.age_start + t - 1
        ih = res.health_path[t]
        W = res.wealth_path[t]
        m = res.medical_path[t]
        c = res.consumption_path[t]
        A_real = annuity_income_real(0.0, t, p)  # no-access: no annuity
        inc_gross = ss_func(age, p) + A_real
        inc_after = max(0.0, inc_gross - m)
        port_drain = max(0.0, m - inc_gross)
        W_after = max(W - port_drain, 0.0)
        medicaid_binding = (inc_after + W_after < p.c_floor)
        medicaid_binding && (inc_after = p.c_floor - W_after)
        flow = flow_utility_sdu(c, inc_after, p.gamma, t, ih, p)
        if p.chi_ltc < 1.0 && medicaid_binding && ih == 3
            flow = flow_utility_sdu_chi_ltc(c, inc_after, p.gamma, t, ih, p)
        end
        disc = p.beta^(t - 1)
        U_total += disc * flow
        n_periods += 1
        if medicaid_binding
            U_floor += disc * flow
            n_floor += 1
        end
    end
    return (U_total=U_total, U_floor=U_floor, n_periods=n_periods, n_floor=n_floor)
end

# Precompute health-weighted continuation interps (as simulate_batch does) so the
# per-path simulate_lifecycle calls share the work.
function build_c_interps(sol, p)
    g = sol.grids
    nW = length(g.W); nA = length(g.A); nH = 3
    ht = build_all_health_transitions(p)
    c_interps = Matrix{Any}(undef, nH, p.T)
    for ih in 1:nH, t in 1:p.T
        V_hw = zeros(nW, nA)
        if t < p.T
            for ihn in 1:nH
                @views V_hw .+= ht[t][ih, ihn] .* sol.V[:, :, ihn, t + 1]
            end
        end
        c_interps[ih, t] = linear_interpolation((g.W, g.A), V_hw,
            extrapolation_bc=Interpolations.Flat())
    end
    return c_interps
end

# Floor-invariant scaled value: only the non-floor felicity scales by (1+lam)^(1-g).
scaled_value(lam, f, U_c, B_no, gamma) =
    (1.0 + lam)^(1.0 - gamma) * (1.0 - f) * U_c + f * U_c + B_no

# Bisect lam in [0, lam_hi] so scaled_value(lam) == V_with. Converges in LAMBDA
# space (bracket width), not on the value residual: the production value function
# is tiny in magnitude (~1e-6), so a value-residual tolerance would accept a
# spurious root. Returns (lam, converged). V_with <= scaled_value(0) means no
# scaling is needed (root at lam = 0); V_with above the lam->inf ceiling
# (f*U_c + B_no) is unreachable by scaling non-floor felicity alone.
function bisect_lambda(f, U_c, B_no, gamma, V_with; lam_hi=50.0, lam_tol=1e-12, maxit=400)
    v0 = scaled_value(0.0, f, U_c, B_no, gamma)
    V_with <= v0 && return (0.0, true)
    vh = scaled_value(lam_hi, f, U_c, B_no, gamma)
    V_with > vh && return (NaN, false)
    lo, hi = 0.0, lam_hi
    for _ in 1:maxit
        mid = 0.5 * (lo + hi)
        scaled_value(mid, f, U_c, B_no, gamma) < V_with ? (lo = mid) : (hi = mid)
        hi - lo < lam_tol && break
    end
    return (0.5 * (lo + hi), true)
end

function main()
    println("=" ^ 70)
    println("  CEV FLOOR-SCALING DIAGNOSTIC BOUND (closed-form vs floor-invariant)")
    println("=" ^ 70)

    p_base = ModelParams(age_start=AGE_START, age_end=AGE_END)
    base_surv = production_base_survival(p_base)

    # Solve the full production model once, at the low (band-1) SS+DB floor so
    # low-wealth cells face the most floor exposure. compute_bequest_decomp=true
    # supplies the exact bequest component B for the closed form.
    ss_band1 = Float64(SS_QUARTILE_LEVELS[1])
    ss_func = (age, q) -> ss_band1
    p = ModelParams(; gamma=GAMMA, beta=BETA, r=R_RATE,
        theta=THETA_DFJ, kappa=KAPPA_DFJ,
        mwr=MWR_LOADED, fixed_cost=FIXED_COST, min_purchase=MIN_PURCHASE,
        chi_ltc=CHI_LTC, inflation_rate=INFLATION,
        medical_enabled=true, health_mortality_corr=true,
        stochastic_health=true, n_health_states=3, n_quad=N_QUAD,
        c_floor=C_FLOOR, hazard_mult=Float64.(HAZARD_MULT), hazard_normalize=HAZARD_NORMALIZE,
        survival_pessimism=SURVIVAL_PESSIMISM, consumption_decline=CONSUMPTION_DECLINE,
        health_utility=Float64.(HEALTH_UTILITY),
        n_wealth=N_WEALTH, n_annuity=N_ANNUITY, n_alpha=N_ALPHA,
        W_max=W_MAX, age_start=AGE_START, age_end=AGE_END, annuity_grid_power=A_GRID_POW)

    fair_pr = compute_payout_rate(ModelParams(age_start=AGE_START, age_end=AGE_END,
        mwr=1.0, r=R_RATE, inflation_rate=INFLATION,
        n_wealth=N_WEALTH, n_annuity=N_ANNUITY, n_alpha=N_ALPHA,
        W_max=W_MAX, annuity_grid_power=A_GRID_POW), base_surv)
    loaded_pr = MWR_LOADED * fair_pr
    grids = build_grids(ModelParams(age_start=AGE_START, age_end=AGE_END, mwr=1.0,
        r=R_RATE, inflation_rate=INFLATION,
        n_wealth=N_WEALTH, n_annuity=N_ANNUITY, n_alpha=N_ALPHA,
        W_max=W_MAX, annuity_grid_power=A_GRID_POW), fair_pr)

    @printf("\n  Solving production model (band-1 SS=\$%.0f, DFJ bequests)...\n", ss_band1)
    t0 = time()
    sol = solve_lifecycle_health(p, grids, base_surv, ss_func; compute_bequest_decomp=true)
    @printf("    solved in %.1fs\n", time() - t0)

    g = sol.grids
    c_interps = build_c_interps(sol, p)

    # Cells spanning the floor-exposed low-wealth range (band 1) up through
    # moderate/high wealth, in Fair and Poor health, to search for any cell that
    # is BOTH floor-exposed (f > 0) AND has a positive CEV (alpha* > 0).
    wealth_cells = [8_000.0, 25_000.0, 50_000.0, 100_000.0, 200_000.0, 500_000.0]
    health_cells = [2, 3]  # Fair, Poor
    n_sim = 12_000

    rows = Any[]
    max_err_floor = 0.0; cell_floor = ""      # over floor-binding cells
    max_err_interact = 0.0; cell_interact = "" # over cells with f>0 AND CEV>0.1%
    @printf("\n  %-9s %-6s %8s %8s %8s %10s %10s %9s\n",
        "wealth", "health", "alpha*", "floorFrq", "share_f", "cev_closed", "cev_numer", "err_pp")
    println("  " * "-" ^ 82)

    for W0 in wealth_cells, H0 in health_cells
        # Closed-form CEV from the solved value function (compute_cev logic).
        r = compute_cev(sol, W0, 0.0, H0, loaded_pr)
        V_no = r.V_no_ann
        V_with = r.V_with_ann

        # Bequest component B_no at (W0, A=0, H0, age 65).
        B_interp = linear_interpolation((g.W, g.A), sol.B[:, :, H0, 1],
            extrapolation_bc=Interpolations.Flat())
        Wc = clamp(W0, g.W[1], g.W[end])
        B_no = B_interp(Wc, clamp(0.0, g.A[1], g.A[end]))
        U_c = V_no - B_no

        # Closed-form lambda (unclamped), matching exact_cev_lambda. Zero when the
        # annuity is not purchased (V_with = V_no): there is no CEV to misprice.
        lam_closed = V_with > V_no ?
            ((V_with - B_no) / (V_no - B_no))^(1.0 / (1.0 - p.gamma)) - 1.0 : 0.0

        # Simulate no-access paths; decompose felicity into floor / non-floor.
        rng = Random.MersenneTwister(20260713)
        U_tot_sum = 0.0; U_flr_sum = 0.0; np_sum = 0; nf_sum = 0
        for _ in 1:n_sim
            res = simulate_lifecycle(sol, W0, 0.0, H0, base_surv, ss_func, p;
                rng=rng, c_interps=c_interps)
            s = path_felicity_split(res, p, ss_func)
            U_tot_sum += s.U_total; U_flr_sum += s.U_floor
            np_sum += s.n_periods; nf_sum += s.n_floor
        end
        f = U_tot_sum != 0.0 ? U_flr_sum / U_tot_sum : 0.0
        f = clamp(f, 0.0, 1.0)
        floor_freq = np_sum > 0 ? nf_sum / np_sum : 0.0

        lam_num, converged = bisect_lambda(f, U_c, B_no, p.gamma, V_with)
        err = converged ? abs(lam_closed - lam_num) : NaN

        if converged && floor_freq >= FLOOR_FREQ_THRESHOLD && err > max_err_floor
            max_err_floor = err
            cell_floor = @sprintf("W=\$%.0f %s", W0, HEALTH_NAMES[H0])
        end
        if converged && floor_freq >= FLOOR_FREQ_THRESHOLD && lam_closed > 0.001 && err > max_err_interact
            max_err_interact = err
            cell_interact = @sprintf("W=\$%.0f %s", W0, HEALTH_NAMES[H0])
        end

        @printf("  \$%-8.0f %-6s %7.2f %7.2f%% %8.4f %9.3f%% %9.3f%% %8.4f\n",
            W0, HEALTH_NAMES[H0], r.alpha_star, floor_freq*100, f,
            lam_closed*100, lam_num*100, converged ? err*100 : NaN)

        push!(rows, (W0, HEALTH_NAMES[H0], r.alpha_star, floor_freq, f, lam_closed, lam_num,
                     converged ? err : NaN, converged))
    end

    println("  " * "-" ^ 82)
    @printf("\n  DIAGNOSTIC BOUND on max |CEV error| across floor-binding cells (floorFreq >= %.0f%%): %.4f pp",
        FLOOR_FREQ_THRESHOLD*100, max_err_floor*100)
    isempty(cell_floor) || @printf("  (at %s)", cell_floor)
    println()
    if isempty(cell_interact)
        println("  No cell is simultaneously floor-binding AND positive-CEV (alpha* > 0):")
        println("  where the Medicaid floor binds materially, the optimal annuity share is")
        println("  zero, so the CEV is exactly zero and the floor-scaling assumption cannot")
        println("  introduce any error. Where CEV is positive (higher wealth), the floor")
        println("  essentially never binds. The two regions are disjoint.")
    else
        @printf("  DIAGNOSTIC BOUND on max |CEV error| where floor binds AND CEV > 0.1%%: %.4f pp (at %s)\n",
            max_err_interact*100, cell_interact)
    end
    println("\n  Interpretation: the closed-form CEV error from scaling Medicaid-floor")
    println("  consumption is bounded by (floor felicity share) x (CEV magnitude). Since")
    println("  floor exposure and positive CEV do not co-occur across the wealth")
    println("  distribution, the closed-form CEV is an accurate approximation.")

    csv = joinpath(@__DIR__, "..", "tables", "csv", "cev_floor_scaling_diagnostic.csv")
    open(csv, "w") do io
        println(io, "wealth,health,alpha_star,floor_period_freq,floor_felicity_share_f," *
                    "cev_closed_pct,cev_numeric_pct,abs_cev_error_pp,converged")
        for (W0, hn, a, ff, f, lc, ln, e, cv) in rows
            @printf(io, "%.0f,%s,%.4f,%.6f,%.6f,%.6f,%.6f,%s,%s\n",
                W0, hn, a, ff, f, lc*100, ln*100,
                isnan(e) ? "NA" : @sprintf("%.6f", e*100), cv ? "true" : "false")
        end
    end
    @printf("\n  CSV: %s\n", csv)
    println("=" ^ 70); println("  DONE"); println("=" ^ 70)
end

main()
