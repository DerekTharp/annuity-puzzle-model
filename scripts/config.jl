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
const UK_RETENTION_PRE   = 0.95   # UK pre-2015 reform: compulsory annuitization rate
const UK_RETENTION_LOW   = 0.13   # UK post-2015 voluntary retention (low anchor; FCA)
const UK_RETENTION_MID   = 0.17   # UK post-2015 voluntary retention (mid anchor; ABI/FCA central)
const UK_RETENTION_HIGH  = 0.25   # UK post-2015 voluntary retention (high anchor; ABI)

# Two-model architecture.
#
# Model 1 (structural multi-channel, US-anchored): rational + preference +
# structural (chi_ltc) + behavioral (SDU + PED) channels parameterized
# directly in the Bellman equation. SDU calibrated to Blanchett-Finke
# (2024-25); PED calibrated to Chalmers-Reuter (2012) Oregon PERS
# default-vs-opt-in elasticity in scripts/calibrate_psi_chalmers_reuter.jl.
#
# Model 2 (UK reduced-form transport): apply the proportional retention
# factor from the UK 2015 reform (UK_post / UK_pre) to the model's
# no-behavioral baseline as a deterministic multiplicative transformation
# in scripts/export_manuscript_numbers.jl. The UK pre-reform 95% rate is a
# COMPULSION equilibrium, so the wedge captures the bundle of behavioral
# AND rational frictions that voluntary retirees express; the no-behavioral
# baseline already absorbs most rational frictions, so this transport
# bracket is interpreted as an upper bound on the friction wedge.
#
# Production Model 2 wedge factors (UK_post / UK_pre):
#   low  factor = UK_RETENTION_LOW  / UK_RETENTION_PRE = 0.137
#   mid  factor = UK_RETENTION_MID  / UK_RETENTION_PRE = 0.179  (production)
#   high factor = UK_RETENTION_HIGH / UK_RETENTION_PRE = 0.263
#
# Both Model 1 and Model 2 predictions are reported alongside the HRS
# empirical (2.0-3.3%) for triangulation.

# Behavioral channel calibrations for Model 1.
#
# LAMBDA_W: source-dependent utility discount on portfolio drawdowns
# (Force A; Blanchett-Finke 2024-25). Households consume income (SS,
# annuity payouts) at full utility weight and portfolio drawdowns at a
# discount lambda_w in (0, 1]. Calibrated to the Blanchett-Finke spending
# differential (~0.85 partialled).
const LAMBDA_W = 0.85

# PSI_PURCHASE: narrow-framing at-purchase penalty intensity (Force B;
# Barberis-Huang 2009 narrow framing; Tversky-Kahneman 1992 loss aversion).
# Calibrated to the Chalmers-Reuter (2012) Oregon PERS 35 pp default-vs-
# opt-in ownership gap by scripts/calibrate_psi_chalmers_reuter.jl. The
# value below is a placeholder pending Stage 9b calibration; the
# calibration script writes the calibrated value into a JSON file that
# subsequent stages read at runtime.
const PSI_PURCHASE = 0.05

# PSI_PURCHASE_C_REF: reference consumption used to express the at-purchase
# loss-aversion stream in utility units. Set to typical SS benefit so the
# resulting psi_purchase magnitudes have an interpretable scale.
const PSI_PURCHASE_C_REF = 18_000.0

# Chalmers-Reuter (2012) Oregon PERS calibration target — observed
# default-vs-opt-in ownership gap (35 pp). Used by
# scripts/calibrate_psi_chalmers_reuter.jl as the moment that pins down
# psi_purchase.
const CHALMERS_REUTER_GAP_TARGET = 0.35

# Public-care aversion (Ameriks et al. 2011 QJE; 2020 ECMA "Long-Term-Care Utility")
# Households retain liquid wealth specifically to avoid Medicaid LTC reliance.
# Operationally: when the consumption floor binds AND the agent is in Poor health
# (proxy for LTC need), the resulting consumption is treated as Medicaid-financed
# and yields utility multiplied by chi_LTC < 1. Ameriks et al. (2020 ECMA) identify
# chi_LTC ≈ 0.5 from strategic-survey wealth equivalents (~$50K-$100K aversion
# premium). The channel reduces predicted ownership because annuitization
# accelerates Medicaid eligibility by depleting liquid wealth faster.
const CHI_LTC = 0.7               # Upper bound of Ameriks (2020 ECMA) 95% CI for
                                   # public-care utility weight. Their central
                                   # estimate is 0.5 with CI roughly [0.3, 0.7].
                                   # We adopt 0.7 (the upper CI bound) as a more
                                   # conservative choice than the central estimate,
                                   # avoiding overcalibration of this channel
                                   # relative to the model's other suppression
                                   # mechanisms. The Phase 27 diagnostic showed
                                   # CHI_LTC = 0.5 produces a pre-behavioral
                                   # baseline of 1.4%, which is below any plausible
                                   # behavioral-wedge identification target and
                                   # creates a cliff in the at-purchase penalty
                                   # mechanism. CHI_LTC = 0.7 is empirically
                                   # defensible (within Ameriks CI) while leaving
                                   # room for the bundled wedge to operate.
                                   # 1.0 = channel off; 0.7 = production (May 2026).

# HRS population data path
const HRS_PATH = joinpath(@__DIR__, "..", "data", "processed", "lockwood_hrs_sample.csv")
