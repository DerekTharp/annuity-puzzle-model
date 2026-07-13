# Social Security and pension income profiles.
# SS benefits are exogenous, real (inflation-indexed), and non-commutable.
# Calibrated to match distribution by wealth quartile (Dushi and Webb 2004;
# Poterba, Venti, and Wise 2011; Lockwood 2012).

"""
Annual Social Security benefit by wealth quartile (1-indexed).
Quartile 1 = lowest wealth, quartile 4 = highest.

Bottom quartile gets the highest SS replacement rate (~90% of wealth annuitized).
Top quartile has lowest replacement rate (~40%).
Absolute SS benefit rises with wealth quartile but at a decreasing rate,
reflecting the progressive benefit formula.

Benefits in 2014 dollars.
"""
function ss_benefit(quartile::Int, p::ModelParams)
    # Legacy helper. The live decomposition path passes ss_levels vectors
    # directly (SS_QUARTILE_LEVELS); these values must mirror that constant.
    # Observed combined pre-existing annuitized income (SS + DB) by wealth
    # bin from RAND HRS (calibration/build_ss_profile.jl), 2014 dollars.
    quartile_benefits = [18_284.0, 21_188.0, 25_924.0, 26_873.0]
    return quartile_benefits[quartile]
end

"""
SS benefit as a function of initial wealth W_0, mapping wealth to quartile.
Uses quartile breakpoints from HRS/SCF data (approximate, 2014 dollars).
"""
function ss_benefit_by_wealth(W_0::Float64, p::ModelParams)
    # Wealth quartile breakpoints for single retirees 65-69 (HRS, approximate)
    if W_0 < 30_000.0
        return ss_benefit(1, p)
    elseif W_0 < 120_000.0
        return ss_benefit(2, p)
    elseif W_0 < 350_000.0
        return ss_benefit(3, p)
    else
        return ss_benefit(4, p)
    end
end

"""
For the Yaari benchmark: zero SS income.
"""
function ss_benefit_zero(t::Int, p::ModelParams)
    return 0.0
end

"""
    build_ss_func(ss_real_level, db_nominal_level, age_start) -> Function

Build the pre-existing-annuitization income function `ss_func(age, p)` for one
wealth band. SS is COLA-protected and enters as a constant real flow
`ss_real_level`. DB pensions are nominal, so their real value erodes at the
fixed expected inflation rate `DB_EROSION_RATE`: real DB income at age `a` is
`db_nominal_level * (1 + DB_EROSION_RATE)^(-(a - age_start))`, equal to
`db_nominal_level` at `age_start` and declining thereafter.

DB erosion uses the FIXED `DB_EROSION_RATE`, not the coalition's
`p.inflation_rate`. DB nominality is a property of the household's pre-existing
resources, independent of the Inflation channel (which toggles whether the
*private* SPIA the household might purchase is nominal). The off-state
commutation always prices DB at the nominal rate (fair_pr_nom, at INFLATION),
so the on-state DB must always erode at the same rate for PV-consistency in
every coalition — including the ~256 subsets with the Inflation channel off.

With the payout-rate convention PV = sum_{t>=0} S(t)/(1+r)^t, the eroding-DB
stream's real PV equals db_nominal_level / fair_pr_nom, so the ON-state DB PV
matches the OFF-state nominal commutation in commuted_topup_vector.

`db_nominal_level = 0` yields a constant real flow `ss_real_level` (the real-DB
sensitivity and legacy COLA-protected callers).
"""
# DB nominal-erosion rate. Must equal the production INFLATION (config.jl); the
# commutation prices DB at fair_pr_nom computed at INFLATION, so the on-state
# erosion must match. Enforced by test/test_config_consistency.jl.
const DB_EROSION_RATE = 0.02

function build_ss_func(ss_real_level::Float64, db_nominal_level::Float64, age_start::Int)
    return (age, p) -> ss_real_level +
        db_nominal_level * (1.0 + DB_EROSION_RATE)^(-(age - age_start))
end
