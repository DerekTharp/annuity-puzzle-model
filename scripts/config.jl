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
                                  # variance the behavioral channels (PED narrow-
                                  # framing, public-care aversion) explain
                                  # separately.
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
# The structural multi-channel model: all 11 channels (rational + preference
# + structural chi_ltc + behavioral SDU/PED) are parameterized directly in the
# Bellman equation. The two behavioral parameters (LAMBDA_W, PSI_PURCHASE) are
# exploratory, literature-anchored values, not moment-matched, reported as a
# robustness extension with within-model sensitivity ranges.

# Behavioral channel calibrations (exploratory parameters).
#
# These are best-guess literature-anchored values, not identified from a
# moment match. Sensitivity ranges are reported across plausible spans.
#
# LAMBDA_W: source-dependent utility (SDU) discount on portfolio drawdowns
# (Blanchett-Finke 2024-25). Households consume income (SS, annuity
# payouts) at full utility weight and portfolio drawdowns at a discount
# lambda_w in (0, 1]. Production central value is the Blanchett-Finke
# point estimate: retirees spend ~80% of income but only ~50% of
# portfolio, so 50/80 = 0.625. Exploratory best guess (not moment-
# matched); sensitivity reported across {0.5, 0.625, 0.75, 0.85}.
const LAMBDA_W = 0.625

# PSI_PURCHASE: narrow-framing at-purchase penalty (PED) intensity
# (Barberis-Huang 2009 narrow framing; Tversky-Kahneman 1992 loss aversion).
# Exploratory best guess (not moment-matched) — the parameter scales the
# NPV of the loss-aversion stream over the underwater period of the SPIA.
# Chosen as a literature-magnitude anchor in the range of documented
# framing/default effects (Brown 2008 ~25 pp; Chalmers-Reuter 2012 ~35 pp;
# Hu-Scott 2007 ~20-35% NPV discount). Sensitivity reported across
# {0.01, 0.05, 0.09}.
const PSI_PURCHASE = 0.05

# PSI_PURCHASE_C_REF: reference consumption used to express the at-purchase
# loss-aversion stream in utility units. Set to typical SS benefit so the
# resulting psi_purchase magnitudes have an interpretable scale.
const PSI_PURCHASE_C_REF = 18_000.0

# Public-care aversion (mechanism: Ameriks et al. 2011, Journal of Finance;
# LTC-state utility framework extended in Ameriks et al. 2020, Journal of
# Political Economy). Households retain liquid wealth to avoid Medicaid
# long-term-care reliance. Operationally: when the consumption floor binds AND
# health = Poor (proxy for LTC need), the resulting consumption is treated as
# Medicaid-financed and yields flow utility scaled by chi_LTC < 1. Annuitization
# accelerates Medicaid eligibility by depleting liquid wealth faster, so the
# channel reduces predicted ownership.
#
# chi_LTC is a flow-utility transformation of the public-care-aversion evidence,
# not a parameter Ameriks et al. report directly; 0.49 is a calibration choice
# within that evidence (the manuscript appendix documents the derivation).
# Sensitivity is swept in scripts/sweep_chi_ltc.jl: lower chi_LTC is mildly
# PRO-annuity, since liquid wealth is worth less in the Medicaid state. 1.0 = off.
const CHI_LTC = 0.49

# HRS population data path
const HRS_PATH = joinpath(@__DIR__, "..", "data", "processed", "lockwood_hrs_sample.csv")
