# Seven-channel sub-game Shapley: the nine-channel game with the two
# multiplicative-utility channels (age-varying needs, state-dependent utility)
# excluded as players entirely. Pure post-processing of the existing
# subset_enumeration.csv lookup (restricted to bitmasks with bits 4 and 5 off);
# no model solves. Addresses the CRRA-normalization concern: if the level
# normalization of the multiplicative weights distorted the attribution, the
# ranking would move when those channels are removed from the game.
#
# Output: tables/csv/subgame7_shapley.csv
# Usage:  julia --project=. scripts/compute_subgame_shapley.jl

using Printf, DelimitedFiles

const ROOT = joinpath(@__DIR__, "..")
raw, _ = readdlm(joinpath(ROOT, "tables", "csv", "subset_enumeration.csv"), ',', Any; header=true)
own = Dict{Int,Float64}(Int(raw[r, 1]) => Float64(raw[r, 3]) / 100 for r in 1:size(raw, 1))

const PLAYERS = [0, 1, 2, 3, 6, 7, 8]  # SS, Bequests, Med+R-S, Pessimism, Loads, Inflation, LTC
const NAMES = Dict(0 => "SS", 1 => "Bequests", 2 => "Medical+R-S", 3 => "Pessimism",
                   6 => "Loads", 7 => "Inflation", 8 => "Public-care (LTC)")
n = length(PLAYERS)

mask_of(S) = reduce(|, (1 << p for p in S); init = 0)

shap = Dict{Int,Float64}(p => 0.0 for p in PLAYERS)
# Direct enumeration over all 2^7 coalitions.
for p in PLAYERS
    others = [q for q in PLAYERS if q != p]
    for bits in 0:(2^(n - 1) - 1)
        S = [others[j] for j in 1:(n - 1) if (bits >> (j - 1)) & 1 == 1]
        k = length(S)
        w = factorial(k) * factorial(n - k - 1) / factorial(n)
        shap[p] += w * (own[mask_of(vcat(S, p))] - own[mask_of(S)])
    end
end

tot = sum(values(shap))
drop = own[mask_of(PLAYERS)] - own[0]
@printf("Seven-channel sub-game (weighted-utility channels excluded):\n")
for p in sort(PLAYERS; by = q -> -shap[q])
    @printf("  %-18s %+7.2f pp\n", NAMES[p], shap[p] * 100)
end
@printf("  efficiency: sum = %.4f vs v(full)-v(empty) = %.4f\n", tot, drop)
@assert isapprox(tot, drop; atol = 1e-8) "Shapley efficiency violated"
@printf("  full 7-channel own: %.2f%%\n", own[mask_of(PLAYERS)] * 100)

csv = joinpath(ROOT, "tables", "csv", "subgame7_shapley.csv")
open(csv, "w") do io
    # Stored in the DROP convention (positive = demand-suppressing), matching
    # every other Shapley artifact in the deposit.
    println(io, "channel,shapley_value_pp,full_own_pct")
    for p in PLAYERS
        @printf(io, "%s,%.4f,%.4f\n", NAMES[p], -shap[p] * 100, own[mask_of(PLAYERS)] * 100)
    end
end
println("CSV: $csv")
