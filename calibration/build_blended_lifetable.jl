# Sex-blended life table for the mortality robustness run.
#
# The headline model uses a single SSA administrative life table taken from
# Lockwood's (2012) replication code (BAP_wtp.m). That table matches the
# male column of the SSA 2003 period life table to within rounding
# (q65 = 0.018740 vs 0.018751), while the model-eligible HRS sample is
# roughly 69% female. This script constructs a sex-blended table as the
# survivorship mixture of the SSA 2003 male and female period tables from
# the age-65 perspective:
#
#   S_blend(a) = w_f * S_f(a) + w_m * S_m(a),   a = 65..110,
#
# with w_f equal to the female share of model-eligible person-waves
# (wealth >= MIN_WEALTH) in the HRS validation extract when that file is
# present, and the committed value otherwise. Output is a cumulative
# death-probability vector in the same format as LOCKWOOD_CUM_DEATH_PROBS
# (entry i = Pr(dead before age 64+i | alive at 65), i = 1..46).
#
# Inputs:  data/processed/ssa2003_sex_qx.csv
#          (SSA Period Life Table 2003, male/female death probabilities by
#           single year of age; public data, ssa.gov/oact table 4.C6)
#          data/processed/hrs_validation_sample.csv (optional, person-level,
#          not shipped; used only to recompute the female share)
# Output:  data/processed/blended_lifetable.csv
#
# Usage: julia --project=. calibration/build_blended_lifetable.jl

using Printf, DelimitedFiles

const DATA_DIR = joinpath(@__DIR__, "..", "data", "processed")
# Exact model-eligible female share: 1,578 of 2,279 person-waves (single
# retirees 65-69, wealth >= $5,000, waves 5-9). This committed constant is
# the authoritative production input; the private validation extract, when
# present, only VERIFIES it (deterministic replication must not depend on
# restricted files).
const FEMALE_SHARE = 1578 / 2279
const MIN_WEALTH_ELIGIBLE = 5_000.0

qx_path = joinpath(DATA_DIR, "ssa2003_sex_qx.csv")
isfile(qx_path) || error("Missing $qx_path")
raw, hdr = readdlm(qx_path, ',', Any; header=true)
ages = Int.(raw[:, 1])
qx_m = Float64.(raw[:, 2])
qx_f = Float64.(raw[:, 3])
@assert ages[1] == 65 && ages[end] == 110 "expected ages 65-110"

# Female share: the committed constant is authoritative. The private
# validation extract, when present, verifies it and errors on divergence.
w_f = FEMALE_SHARE
val_path = joinpath(DATA_DIR, "hrs_validation_sample.csv")
if isfile(val_path)
    vraw, vhdr = readdlm(val_path, ',', Any; header=true)
    col(n) = findfirst(==(n), vec(vhdr))
    wealth = Float64.(vraw[:, col("wealth")])
    female = Float64.(vraw[:, col("female")])
    el = wealth .>= MIN_WEALTH_ELIGIBLE
    w_check = sum(female[el]) / count(el)
    abs(w_check - w_f) < 1e-9 ||
        error("female share in validation extract ($w_check) diverges from the committed constant ($w_f); update FEMALE_SHARE with provenance")
    @printf("  Female share verified against validation extract: %.6f (n=%d)\n",
            w_f, count(el))
else
    @printf("  Validation extract absent; committed female share %.6f\n", w_f)
end
w_m = 1.0 - w_f

# Survivorship from age 65 by sex, then the mixture.
n = length(ages)
S_m = ones(n); S_f = ones(n)
for i in 2:n
    S_m[i] = S_m[i-1] * (1.0 - qx_m[i-1])
    S_f[i] = S_f[i-1] * (1.0 - qx_f[i-1])
end
S_blend = w_f .* S_f .+ w_m .* S_m
cdp = 1.0 .- S_blend   # cdp[i] = Pr(dead before age 64+i), cdp[1] = 0.0

out_path = joinpath(DATA_DIR, "blended_lifetable.csv")
open(out_path, "w") do f
    println(f, "idx,age,cum_death_prob,female_share")
    for i in 1:n
        @printf(f, "%d,%d,%.9f,%.4f\n", i, ages[i], cdp[i], w_f)
    end
end

le65 = sum(S_blend[2:end]) + 0.5
@printf("  Blended table: q65 = %.6f, complete LE at 65 = %.2f years (male-only table: 16.33)\n",
        cdp[2], le65)
println("  Output: $out_path")
