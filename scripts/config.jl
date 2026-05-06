# Baseline calibration constants shared across all scripts.
# Change values here; all scripts will pick them up.

const GAMMA      = 2.5
const BETA       = 0.97
const R_RATE     = 0.02
const AGE_START  = 65
const AGE_END    = 110
const C_FLOOR    = 6_180.0
const W_MAX      = 3_000_000.0  # covers p99.5 of HRS wealth distribution
const MWR_LOADED = 0.87          # Wettstein (2021) modern-market estimate
const FIXED_COST = 1_000.0
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
const SURVIVAL_PESSIMISM = 0.981
const MIN_WEALTH = 5_000.0

# Hazard multipliers — production now uses age-varying HRS estimates with
# constant fallback. Constant baseline kept for back-compat with scripts that
# don't accept matrices yet.
const HAZARD_MULT = [0.50, 1.0, 3.0]                    # constant fallback
const HAZARD_MULT_AGE_BANDS = [0.49 1.00 3.29;          # ages 65-74
                               0.60 1.00 2.77;          # ages 75-84
                               0.74 1.00 1.82]          # ages 85+
const HAZARD_MULT_AGE_MIDPOINTS = [69.5, 79.5, 90.0]    # band midpoints

const CONSUMPTION_DECLINE = 0.02  # age-varying consumption needs (Aguiar-Hurst 2013)
const HEALTH_UTILITY = [1.0, 0.90, 0.75]  # state-dep utility — raw FLN central (production)
const PSI_PURCHASE = 0.0163       # narrow-framing purchase penalty (Barberis-Huang 2009;
                                   # Tversky-Kahneman 1992 loss aversion). Decays with
                                   # cumulative payouts; vanishes at breakeven.
                                   # CALIBRATION: single-moment SMM on the ABI
                                   # rational-corrected mid sensitivity target. The UK
                                   # 2015 pension-freedoms reform shifted the regulated
                                   # default from compulsory annuitization (~95-100%
                                   # of DC pots pre-reform) to opt-in (13-25%
                                   # post-reform retention), a 70-87 pp drop in
                                   # ownership rate. Anchor C-mid strips the rational
                                   # tax-removal component (~15-25 pp from a lump-sum
                                   # 55% tax penalty removal already in the model's
                                   # rational pricing) from the raw drop and matches
                                   # the residual 60 pp behavioral component. Production
                                   # point; bracket low end. Bracket high end ψ=0.0335
                                   # corresponds to the ELSA microdata total drop with
                                   # no rational stripping. The full sensitivity range
                                   # across alternative single-anchor SMM specifications
                                   # is reported in the appendix. NOT calibrated to
                                   # observed US ownership.
const LAMBDA_W = 0.625            # source-dependent utility (FPR companion paper;
                                   # Blanchett-Finke 2024-25): retirees spend ~80% of
                                   # income but only ~50% of portfolio → 50/80 = 0.625.
                                   # 1.0 = SDU off; <1.0 = portfolio dollars discounted.

# HRS population data path
const HRS_PATH = joinpath(@__DIR__, "..", "data", "processed", "lockwood_hrs_sample.csv")
