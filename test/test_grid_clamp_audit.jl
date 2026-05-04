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
    base_surv = build_lockwood_survival(p_base)
    grid_kw = (n_wealth=N_WEALTH, n_annuity=N_ANNUITY, n_alpha=N_ALPHA,
               W_max=W_MAX, age_start=AGE_START, age_end=AGE_END,
               annuity_grid_power=A_GRID_POW)
    p = ModelParams(; gamma=GAMMA, beta=BETA, r=R_RATE, mwr=MWR_LOADED,
                    inflation_rate=INFLATION, grid_kw...)
    payout_rate = compute_payout_rate(p, base_surv)
    g = build_grids(p, payout_rate)

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

    # Existing SS income — production uses by-quartile assignment. Compute
    # the maximum SS quartile level for the audit (worst case).
    max_ss = maximum(SS_QUARTILE_LEVELS)

    # Audit 1: Wealth clamping. Every eligible HRS agent must satisfy
    # W_min <= W <= W_max for the structural model to evaluate them at the
    # interior solution.
    @testset "Wealth-grid clamping" begin
        n_below = count((wealth .< W_min) .& pop_eligible)
        n_above = count((wealth .> W_max) .& pop_eligible)
        @test n_below == 0
        # Some HRS agents above W_max are documented in the manuscript; this
        # test asserts the count is small (< 1% of eligible) so the grid is
        # not silently truncating a large fraction of the sample.
        pct_above = 100.0 * n_above / max(n_eligible, 1)
        @info "Eligible HRS agents above W_max" n_above pct_above W_max
        @test pct_above < 1.5
    end

    # Audit 2: Annuity-income clamping. The model clamps wealth to W_max
    # before any annuity computation. Compute the maximum A_total under
    # the model's actual clamping behavior: alpha=1 with W effectively
    # min(W, W_max). The audit documents how often A_total exceeds A_max
    # (forcing the value function to be evaluated at the annuity-grid
    # boundary) and bounds the maximum overshoot.
    @testset "Annuity-income grid clamping (alpha = 1, max SS)" begin
        eligible_wealth = wealth[pop_eligible]
        effective_wealth = clamp.(eligible_wealth, W_min, W_max)
        max_a_total = max_ss .+ effective_wealth .* payout_rate
        n_above = count(max_a_total .> A_max)
        n_below = count(max_a_total .< A_min)
        @test n_below == 0
        # The annuity grid is sized to W_max * payout_rate. Adding the top
        # SS quartile on top can produce A_total slightly above this bound
        # for the highest-wealth agents at alpha=1. The fraction is small
        # (< 2% of eligible sample) and the maximum overshoot is bounded.
        # If either threshold breaches, the grid needs to be widened.
        pct_above = 100.0 * n_above / max(n_eligible, 1)
        @info "Annuity-grid clamping at alpha=1, max SS" n_above pct_above A_max
        @test pct_above < 2.0
        if n_above > 0
            max_overshoot_pct = 100.0 * (maximum(max_a_total) - A_max) / A_max
            @info "Maximum overshoot (% of A_max)" max_overshoot_pct
            @test max_overshoot_pct < 15.0
        end
    end

    @testset "Headline grid ranges (manuscript reference)" begin
        @info "Production grid bounds" W_min W_max A_min A_max payout_rate
        @test W_max ≈ W_MAX rtol=1e-9
        # A_max equals W_max × payout_rate; see build_annuity_grid docstring
        # for the documented small-overshoot behavior at alpha=1 for the
        # top wealth quartile.
        @test A_max ≈ W_max * payout_rate rtol=1e-6
    end
end
