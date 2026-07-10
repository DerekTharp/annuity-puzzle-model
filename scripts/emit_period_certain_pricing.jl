# Period-certain pricing comparison (Appendix H).
#
# Prices a 10-year period-certain life annuity against the life-only SPIA
# under the production mortality table and discounting, for both the real
# and nominal (2% inflation) pricing conventions. The guarantee replaces
# survival probabilities with 1.0 for the first ten years, so the insurer
# cannot reclaim payments from early decedents and the fair payout rate
# falls. Writes tables/csv/period_certain_pricing.csv; the appendix quotes
# the payout reduction via numbers.tex macros.
#
# Usage: julia --project=. scripts/emit_period_certain_pricing.jl

using Printf

include(joinpath(@__DIR__, "..", "src", "AnnuityPuzzle.jl"))
using .AnnuityPuzzle

include(joinpath(@__DIR__, "config.jl"))

p_base = ModelParams(age_start=AGE_START, age_end=AGE_END)
base_surv = build_lockwood_survival(p_base)

p_nom  = ModelParams(gamma=GAMMA, beta=BETA, r=R_RATE, mwr=1.0,
                     inflation_rate=INFLATION, age_start=AGE_START, age_end=AGE_END)
p_real = ModelParams(gamma=GAMMA, beta=BETA, r=R_RATE, mwr=1.0,
                     age_start=AGE_START, age_end=AGE_END)

csv_path = joinpath(@__DIR__, "..", "tables", "csv", "period_certain_pricing.csv")
mkpath(dirname(csv_path))
open(csv_path, "w") do f
    println(f, "convention,life_only_payout,period_certain10_payout,payout_reduction_pct")
    for (nm, pp) in [("nominal", p_nom), ("real", p_real)]
        life = compute_payout_rate(pp, base_surv)
        pc10 = compute_payout_rate_period_certain(pp, base_surv; guarantee_years=10)
        red = 100 * (1 - pc10 / life)
        @printf(f, "%s,%.6f,%.6f,%.4f\n", nm, life, pc10, red)
        @printf("  %s: life-only %.5f, 10-yr certain %.5f, reduction %.2f%%\n",
                nm, life, pc10, red)
    end
end
println("CSV saved: $csv_path")
