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
    # Approximate SSA benefit schedule by quartile.
    # Mean benefit ~$18K; bottom quartile ~$14K, top quartile ~$25K.
    # Progressive formula: replacement rate falls with earnings.
    quartile_benefits = [14_000.0, 17_000.0, 20_000.0, 25_000.0]
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
