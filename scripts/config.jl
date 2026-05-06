# Baseline calibration constants shared across all scripts.
# Change values here; all scripts will pick them up.

const GAMMA      = 2.5
const BETA       = 0.97
const R_RATE     = 0.02
const AGE_START  = 65
const AGE_END    = 110
const C_FLOOR    = 6_180.0
const W_MAX      = 3_000_000.0  # covers p99.5 of HRS wealth distribution
const MWR_LOADED = 0.87          # Wettstein (2021) modern-market estimate.
                                  # Population-mortality MWR. The model's value
                                  # function handles agent-specific mortality
                                  # heterogeneity via state-dependent survival,
                                  # so no further "buyer-selection" adjustment is
                                  # applied (which would double-count the
                                  # selection wedge already endogenized).
const FIXED_COST = 2_500.0       # transaction + search cost. Lockwood (2012) used
                                  # $500-$2,000 for pure paperwork; the $2,500
                                  # production value accommodates a modest search
                                  # cost above pure transaction without absorbing
                                  # variance the behavioral channels (Force B,
                                  # public-care aversion) explain separately.
const MIN_PURCHASE = 10_000.0    # modal SPIA minimum across major issuers
                                  # (Pacific Life, NY Life, MassMutual, Lincoln,
                                  # Symetra, Mutual of Omaha, etc.); LIMRA modern
                                  # market data. Pashchenko (2013) used $25K
                                  # reflecting late-2000s sample.
const INFLATION  = 0.02
const N_WEALTH   = 80
const N_ANNUITY  = 30
const N_ALPHA    = 101
const A_GRID_POW = 3.0
const N_QUAD     = 9
const THETA_DFJ  = 56.96
const KAPPA_DFJ  = 272_628.0
const SURVIVAL_PESSIMISM = 0.96   # Heimer-Myrseth-Schoenle (2019); Payne et al.
                                   # (2013). 0.96/year gives ~20 pp gap at 10-yr
                                   # horizon, between O'Dea-Sturrock (2023) and
                                   # the Hurd-McGarry (2002) anchor.
const MIN_WEALTH = 5_000.0

# Hazard multipliers — production now uses age-varying HRS estimates with
# constant fallback. Constant baseline kept for back-compat with scripts that
# don't accept matrices yet.
# Constant fallback updated to [0.50, 1.0, 3.75] — moderate position between
# DeSalvo et al. (2006) meta and Reichling-Smetters (2015) ~5x without
# triple-counting against state-dependent utility and public-care aversion.
const HAZARD_MULT = [0.50, 1.0, 3.75]                   # constant fallback
const HAZARD_MULT_AGE_BANDS = [0.49 1.00 3.29;          # ages 65-74
                               0.60 1.00 2.77;          # ages 75-84
                               0.74 1.00 1.82]          # ages 85+
const HAZARD_MULT_AGE_MIDPOINTS = [69.5, 79.5, 90.0]    # band midpoints

const CONSUMPTION_DECLINE = 0.02  # age-varying consumption needs (Aguiar-Hurst 2013)
const HEALTH_UTILITY = [1.0, 0.92, 0.82]  # state-dep utility — FLN (2013) central
                                           # within their 95% CI. Reichling-Smetters
                                           # (2015) used softer [1, 0.95, 0.90]; FLN
                                           # raw central is [1, 0.90, 0.75]. Choosing
                                           # the midpoint avoids picking either
                                           # endpoint while staying within the
                                           # empirically defensible range and
                                           # avoiding interaction with steeper
                                           # hazards / public-care aversion.
const PSI_PURCHASE = 0.000893     # narrow-framing purchase penalty (Barberis-Huang 2009;
                                   # Tversky-Kahneman 1992 loss aversion). Decays with
                                   # cumulative payouts; vanishes at breakeven.
                                   # CALIBRATION: single-moment SMM on the UK 2015
                                   # pension-freedoms reform identifying moment.
                                   # The 11-channel disciplined-calibration AWS run
                                   # (HEAD 7fd346f, Phase 24) bisected psi to match
                                   # UK voluntary retention (post-reform DC pot
                                   # holders): 0.001154 at low retention 13%, 0.000893
                                   # at mid 17%, 0.000370 at high 25%. Production
                                   # value adopts the mid retention anchor; the
                                   # full bracket is reported as the calibration
                                   # uncertainty range. NOT calibrated to observed
                                   # US ownership — US ownership is the out-of-sample
                                   # prediction that emerges from the model.
const LAMBDA_W = 0.85             # source-dependent utility (Blanchett-Finke 2024-25
                                   # spending differential, partialled). The raw 80/50
                                   # spending differential between income and portfolio
                                   # gives 0.625 as a gross SDU loading, but that
                                   # differential is observationally confounded with
                                   # liquidity buffering, mental accounting, bequest
                                   # preservation, and tax timing — channels already
                                   # captured separately in this model. Netting those
                                   # channels from the differential leaves a residual
                                   # SDU loading of ~0.85 (defensible range
                                   # [0.80, 0.90] across alternative
                                   # decompositions). 1.0 = SDU off; <1.0 = portfolio
                                   # dollars consumed at discounted utility weight.
                                   # The 0.625 raw value is reported as an upper-
                                   # bound sensitivity in the robustness table.

# Public-care aversion (Ameriks et al. 2011 QJE; 2020 ECMA "Long-Term-Care Utility")
# Households retain liquid wealth specifically to avoid Medicaid LTC reliance.
# Operationally: when the consumption floor binds AND the agent is in Poor health
# (proxy for LTC need), the resulting consumption is treated as Medicaid-financed
# and yields utility multiplied by chi_LTC < 1. Ameriks et al. (2020 ECMA) identify
# chi_LTC ≈ 0.5 from strategic-survey wealth equivalents (~$50K-$100K aversion
# premium). The channel reduces predicted ownership because annuitization
# accelerates Medicaid eligibility by depleting liquid wealth faster.
const CHI_LTC = 0.5               # Ameriks (2020 ECMA) central estimate
                                   # 1.0 = channel off; 0.5 = production active

# HRS population data path
const HRS_PATH = joinpath(@__DIR__, "..", "data", "processed", "lockwood_hrs_sample.csv")
