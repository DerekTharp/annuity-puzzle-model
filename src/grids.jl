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
