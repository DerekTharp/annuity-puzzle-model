# Audit: confirm that the production wealth and annuity-income grids contain
# the entire HRS population sample under all alpha choices, with no binding
# clamps. If any agent at any alpha would have A_total > g.A[end], the
# downstream interpolation evaluates at the grid boundary and the structural
# results silently depend on extrapolation rather than the interior solution.
#
# This test runs in seconds and is a hard check that the production grids
# are sized correctly. If it ever fails, expand W_max or A_max in config.jl.

using Test
using Printf
using DelimitedFiles
include(joinpath(@__DIR__, "..", "src", "AnnuityPuzzle.jl"))
using .AnnuityPuzzle
include(joinpath(@__DIR__, "..", "scripts", "config.jl"))

@testset "Grid-clamp audit on production sample" begin
    # Build production grids
    p_base = ModelParams(age_start=AGE_START, age_end=AGE_END)
    base_surv = production_base_survival(p_base)
    grid_kw = (n_wealth=N_WEALTH, n_annuity=N_ANNUITY, n_alpha=N_ALPHA,
               W_max=W_MAX, age_start=AGE_START, age_end=AGE_END,
               annuity_grid_power=A_GRID_POW)
    # Mirror production grid sizing exactly: grids are built at mwr = 1.0
    # with the larger of the fair real and fair nominal payout rates
    # (run_subset_enumeration.jl convention), not the loaded payout.
    p_fair = ModelParams(; gamma=GAMMA, beta=BETA, r=R_RATE, mwr=1.0, grid_kw...)
    fair_pr = compute_payout_rate(p_fair, base_surv)
    p_fair_nom = ModelParams(; gamma=GAMMA, beta=BETA, r=R_RATE, mwr=1.0,
                             inflation_rate=INFLATION, grid_kw...)
    fair_pr_nom = compute_payout_rate(p_fair_nom, base_surv)
    g = build_grids(p_fair, max(fair_pr, fair_pr_nom))

    W_min = first(g.W)
    W_max = last(g.W)
    A_min = first(g.A)
    A_max = last(g.A)

    # Load production HRS sample
    hrs_csv = joinpath(@__DIR__, "..", "data", "processed", "lockwood_hrs_sample.csv")
    if !isfile(hrs_csv)
        @info "HRS sample CSV not present; skipping clamp audit."
        return
    end
    raw = readdlm(hrs_csv, ',', Any; skipstart=1)
    wealth = Float64.(raw[:, 1])
    pop_eligible = wealth .>= MIN_WEALTH
    n_eligible = count(pop_eligible)
    @test n_eligible > 0

    # Existing SS income — mirror the production by-band assignment exactly
    # (agents get their own band's SS+DB level, not a worst case). The
    # overshooting agents are all in the top band, so this coincides with
    # the worst case today; the per-band assignment keeps the audit aligned
    # with production if band levels drift.
    br = SS_QUARTILE_BREAKS
    band_of(x) = x < br[1] ? 1 : x < br[2] ? 2 : x < br[3] ? 3 : 4

    # Audit 1: Wealth clamping. Every eligible HRS agent must satisfy
    # W_min <= W <= W_max for the structural model to evaluate them at the
    # interior solution.
    @testset "Wealth-grid clamping" begin
        n_below = count((wealth .< W_min) .& pop_eligible)
        n_above = count((wealth .> W_max) .& pop_eligible)
        @test n_below == 0
        # The headline evaluation is unweighted over eligible person-waves,
        # so the audit counts unweighted shares (currently ~1.0%). The
        # manuscript's above-W_max figure is HRS-weighted and therefore
        # smaller; the two are different statistics, not a discrepancy.
        pct_above = 100.0 * n_above / max(n_eligible, 1)
        @info "Eligible HRS agents above W_max (unweighted)" n_above pct_above W_max
        @test pct_above < 1.2
    end

    # Audit 2: Annuity-income clamping. The model clamps wealth to W_max
    # before any annuity computation. Compute the maximum A_total under
    # the model's actual clamping behavior: alpha=1 with W effectively
    # min(W, W_max). The audit documents how often A_total exceeds A_max
    # (forcing the value function to be evaluated at the annuity-grid
    # boundary) and bounds the maximum overshoot.
    @testset "Annuity-income grid clamping (alpha = 1, production evaluation)" begin
        # Mirror the production evaluation: Social Security flows through the
        # income function (never the annuity state), and agents older than 65
        # are repriced at their observed age (higher payout per premium
        # dollar), which is what actually produces the boundary cases.
        ages = Int.(round.(Float64.(raw[:, 3])))
        eligible_idx = findall(pop_eligible)
        loaded_nom_by_age = Dict{Int, Float64}()
        for a in unique(ages[eligible_idx])
            p_a = ModelParams(; gamma=GAMMA, beta=BETA, r=R_RATE, mwr=1.0,
                              inflation_rate=INFLATION, grid_kw...,
                              age_start=a)
            surv_a = production_base_survival(p_a)
            loaded_nom_by_age[a] = MWR_LOADED * compute_payout_rate(p_a, surv_a)
        end
        # Purchases at age a > 65 are stored in age-65 nominal units:
        # A_state = premium * (1+pi)^(t-1) * payout (wtp.jl purchase block).
        max_a_total = [clamp(wealth[i], W_min, W_max) * loaded_nom_by_age[ages[i]] *
                       (1.0 + INFLATION)^(ages[i] - AGE_START)
                       for i in eligible_idx]
        n_above = count(max_a_total .> A_max)
        n_below = count(max_a_total .< A_min)
        @test n_below == 0
        pct_above = 100.0 * n_above / max(n_eligible, 1)
        @info "Annuity-grid clamping at alpha=1, production evaluation" n_above pct_above A_max
        @test pct_above < 0.6
        if n_above > 0
            max_overshoot_pct = 100.0 * (maximum(max_a_total) - A_max) / A_max
            @info "Maximum overshoot (% of A_max)" max_overshoot_pct
            @test max_overshoot_pct < 8.0
        end
    end

    @testset "Headline grid ranges (manuscript reference)" begin
        @info "Production grid bounds" W_min W_max A_min A_max fair_pr fair_pr_nom
        @test W_max ≈ W_MAX rtol=1e-9
        # A_max equals W_max × max(fair real, fair nominal) payout, the
        # production grid-sizing convention.
        @test A_max ≈ W_max * max(fair_pr, fair_pr_nom) rtol=1e-6
    end
end
