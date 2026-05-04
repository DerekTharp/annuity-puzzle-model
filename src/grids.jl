# Grid construction for the lifecycle model state space.
# Wealth grid uses power-function mapping for nonuniform spacing
# (denser at low wealth where value function has more curvature).

"""
Build nonuniform wealth grid: W_i = W_min + (W_max - W_min) * (i/N)^p
where p > 1 concentrates points near W_min.
"""
function build_wealth_grid(p::ModelParams)
    n = p.n_wealth
    raw = range(0.0, 1.0, length=n)
    # Power mapping: higher p => denser at low wealth
    grid = p.W_min .+ (p.W_max - p.W_min) .* (raw .^ p.wealth_grid_power)
    return collect(grid)
end

"""
Build nonuniform annuity income grid from 0 to maximum feasible annual payout.
Uses same power-function mapping as wealth grid to concentrate points
at low annuity income levels (where low-wealth agents' annuity values fall).

The grid upper bound is W_max × payout_rate, sized to the new annuity income
from a full alpha=1 purchase at maximum wealth. For agents with substantial
pre-existing SS income (top quartile, around 21K dollars), A_total = SS +
alpha * W * payout_rate can slightly exceed this bound at α=1; in that case
the value function is evaluated at the grid boundary and a small
interpolation imprecision results. The audit in
test/test_grid_clamp_audit.jl quantifies the affected fraction (~1% of the
HRS eligible sample, all in the top wealth quartile) and the maximum
overshoot (~9.5% above the bound).
"""
function build_annuity_grid(p::ModelParams, payout_rate::Float64)
    A_max = p.W_max * payout_rate
    n = p.n_annuity
    raw = range(0.0, 1.0, length=n)
    grid = A_max .* (raw .^ p.annuity_grid_power)
    return collect(grid)
end

"""
Build grid of annuitization fractions α ∈ [0, 1].
"""
function build_alpha_grid(p::ModelParams)
    return collect(range(0.0, 1.0, length=p.n_alpha))
end

struct Grids
    W::Vector{Float64}     # wealth grid
    A::Vector{Float64}     # annuity income grid
    alpha::Vector{Float64} # annuitization fraction grid
end

function build_grids(p::ModelParams, payout_rate::Float64)
    Grids(
        build_wealth_grid(p),
        build_annuity_grid(p, payout_rate),
        build_alpha_grid(p),
    )
end

# ---------------------------------------------------------------------------
# Grid-bound auditing
# ---------------------------------------------------------------------------
# Many evaluation routines call `clamp(A_total, g.A[1], g.A[end])` or
# `clamp(W, g.W[1], g.W[end])` to keep a state value inside the discretized
# grid. If the clamp binds materially often, the structural results may
# silently depend on grid-boundary extrapolation rather than on the
# interior solution.
#
# The audit counters below tally how often each clamp bound across a run.
# A run is "clean" if both counters report 0; otherwise the run prints a
# summary that the manuscript / referee can inspect.
#
# Usage:
#   reset_clamp_audit!()      # call once at the start of a run
#   x_c = clamp_audit(x, lo, hi, :wealth)   # instead of clamp(x, lo, hi)
#   report_clamp_audit()      # call once at the end of a run

const _CLAMP_AUDIT = Dict{Symbol, Tuple{Int, Int, Float64}}()  # :tag => (n_total, n_bound, max_overshoot)

function reset_clamp_audit!()
    empty!(_CLAMP_AUDIT)
    return nothing
end

@inline function clamp_audit(x::Real, lo::Real, hi::Real, tag::Symbol=:default)
    n_total, n_bound, max_over = get(_CLAMP_AUDIT, tag, (0, 0, 0.0))
    n_total += 1
    if x < lo
        n_bound += 1
        max_over = max(max_over, lo - x)
    elseif x > hi
        n_bound += 1
        max_over = max(max_over, x - hi)
    end
    _CLAMP_AUDIT[tag] = (n_total, n_bound, max_over)
    return clamp(x, lo, hi)
end

function report_clamp_audit(; threshold_pct::Float64=1.0, throw_on_breach::Bool=false)
    isempty(_CLAMP_AUDIT) && return nothing
    println("\n=== Grid-clamp audit ===")
    breach = false
    for (tag, (n_total, n_bound, max_over)) in sort(collect(_CLAMP_AUDIT), by=x->x[1])
        pct = 100.0 * n_bound / max(n_total, 1)
        marker = pct >= threshold_pct ? " ** BREACH **" : ""
        @printf("  %-15s: %d/%d clamped (%.3f%%), max overshoot = %.4g%s\n",
                tag, n_bound, n_total, pct, max_over, marker)
        if pct >= threshold_pct
            breach = true
        end
    end
    println("=========================")
    if breach && throw_on_breach
        error("clamp audit breached threshold of $threshold_pct% for at least one tag")
    end
    return nothing
end
