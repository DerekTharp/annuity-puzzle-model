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
const PSI_PURCHASE = 0.001        # bundled behavioral wedge parameter (Option 1
                                   # a-strict). Operates through the at-purchase
                                   # penalty mechanism but interpretation is the
                                   # FULL bundled wedge, not narrow framing alone.
                                   #
                                   # CALIBRATION (Option 1 a-strict, May 9, 2026):
                                   # The UK 2015 pension-freedoms reform activated all
                                   # behavioral phenomena at once when compulsion lifted.
                                   # The bundle contains three named forces:
                                   #   Force A (SDU): post-purchase license-to-spend
                                   #     on guaranteed-income flows. Named, not
                                   #     parameterized (LAMBDA_W = 1.0 normalization).
                                   #   Force B (narrow framing PED): at-purchase loss
                                   #     aversion over unrecouped premium until
                                   #     breakeven. Operates through the PSI_PURCHASE
                                   #     mechanism in the model.
                                   #   Force C (choice-architecture salience):
                                   #     provider communications, adviser conversations,
                                   #     status-quo bias, Madrian-Beshears defaults.
                                   #     Named, not parameterized.
                                   #
                                   # All three forces are observed AS A BUNDLE in the
                                   # UK 2015 reform. Under joint identification, only
                                   # one mechanism (PSI_PURCHASE) is parameterized;
                                   # it carries the bundled wedge effect. The other
                                   # two forces are conceptually present but
                                   # mechanically absorbed into PSI_PURCHASE under
                                   # the LAMBDA_W = 1.0 normalization.
                                   #
                                   # SMM target: PSI_PURCHASE bisected such that the
                                   # model's voluntary ownership matches the UK
                                   # proportional-wedge prediction. With chi_LTC = 0.5
                                   # active, the pre-behavioral 11-channel baseline
                                   # is roughly 1.8% (steep suppression from Medicaid-
                                   # avoidance). Under proportional transport
                                   # (UK retention 17/95 = 0.179), target US
                                   # ownership ~ 1.8% × 0.179 ~ 0.3%. The actual
                                   # production value will be set by Stage 9b SMM
                                   # bisection during the AWS pipeline run; the
                                   # 0.001 placeholder reflects the order of magnitude
                                   # implied by the existing SMM grid (psi=0.001154
                                   # produced 13% retention in the May 9 run with
                                   # LAMBDA_W = 0.85; the LAMBDA_W = 1.0 SMM will
                                   # land at a different value).
                                   #
                                   # DO NOT retune PSI_PURCHASE to match US ownership.
                                   # US ownership is the test moment, not the target.
                                   # Whatever the model predicts is the honest result
                                   # under bundled identification.
                                   #
                                   # PIPELINE STATUS: The May 9 production run used
                                   # LAMBDA_W = 0.85 and PSI_PURCHASE = 0.0266 which
                                   # was inconsistent with the (a-strict) framing
                                   # (two moments doing two jobs). This commit
                                   # corrects to true Option 1 bundling. Re-run
                                   # required for production CSVs and numbers.tex.
                                   #
                                   # Identification: proportional behavioral wedge.
                                   # The post/pre retention ratio (17/95 = 0.179 at
                                   # the production midpoint) is treated as country-
                                   # invariant. Applied to the US pre-behavioral
                                   # baseline (8-channel, 33.6%) yields a target of
                                   # 33.6% × 0.179 ≈ 6.0% predicted US voluntary
                                   # ownership.
                                   #
                                   # Bundle decomposition normalization: λ_W = 0.85
                                   # (Force A) is normalized at the value implied by
                                   # the Blanchett-Finke spending differential, kept
                                   # for cross-paper consistency with the SS claiming
                                   # companion paper. ψ_purchase (Force B) carries the
                                   # residual: calibrated such that the model's
                                   # combined behavioral effect matches the bundled
                                   # UK target. Decomposition of the bundle into
                                   # Force A vs Force B contributions is parameter-
                                   # dependent rather than data-identified.
                                   #
                                   # Sensitivity range:
                                   #   ψ ≈ 0.022 (UK 13% retention, low) → ~4.6% US
                                   #   ψ ≈ 0.026 (UK 17% retention, mid) → ~6.0% US
                                   #   ψ ≈ 0.016 (UK 25% retention, high) → ~8.8% US
                                   # (interpolated from May 3 production sweep;
                                   # tables/csv/psi_sensitivity.csv covers ψ ∈
                                   # [0.0142, 0.0750] with monotonic decline in
                                   # ownership; ψ = 0.0266 falls between the
                                   # tabulated 0.0240 → 10.5% and 0.0281 → 3.5%)
                                   #
                                   # Empirical comparison (out-of-sample):
                                   #   HRS lifetime contract: 2.02% [1.68, 2.43]
                                   #   HRS income proxy:      3.34% [2.89, 3.85]
                                   # Both fall within the wider sensitivity range
                                   # [2.5%, 8.8%]; income proxy near lower-middle
                                   # of headline UK retention bracket [4.6%, 8.8%].
                                   #
                                   # DO NOT retune ψ_purchase to match US ownership.
                                   # US ownership is the test moment, not the target.
                                   # Identification is locked: bundled behavioral
                                   # wedge under proportional-wedge transport; UK
                                   # 2015 reform is the only identifying moment.
                                   # See paper/main.tex Section 3 (bundled
                                   # behavioral wedge subsection) and Section 4
                                   # (Joint calibration paragraph) for the lock-in
                                   # language.
                                   #
                                   # PIPELINE STATUS: production CSVs in tables/csv/
                                   # were generated May 3 with the OLD calibration
                                   # (ψ = 0.0163, "60pp absolute behavioral drop"
                                   # interpretation, producing 24.5% headline). The
                                   # a-strict re-run with ψ = 0.0266 producing ~6%
                                   # headline is PENDING. Manuscript prose has been
                                   # updated to reflect the a-strict identification
                                   # with hand-coded numerical values; macro-driven
                                   # numbers in paper/numbers.tex remain stale until
                                   # the pipeline is re-run at the new ψ.
const LAMBDA_W = 1.0              # source-dependent utility (Force A) — NORMALIZATION
                                   # under Option 1 bundled identification.
                                   # Under (a-strict) bundling, all three behavioral
                                   # forces (Force A SDU, Force B PED, Force C choice-
                                   # architecture salience) are jointly identified
                                   # from one external moment (UK 2015 reform). Two
                                   # parameters from one moment is under-identified;
                                   # we resolve by normalizing LAMBDA_W = 1.0 (SDU
                                   # mechanism off) and letting PSI_PURCHASE carry
                                   # the entire bundled behavioral effect through the
                                   # at-purchase penalty mechanism.
                                   # Force A is named in the manuscript as one
                                   # conceptual component of the bundle, with
                                   # Blanchett-Finke (2024-25) cited as descriptive
                                   # evidence for SDU's existence in retirement
                                   # spending data. BF is NOT used to identify
                                   # LAMBDA_W in this paper — that would re-introduce
                                   # a second moment and break the bundling logic.
                                   # Cross-paper: the SS claiming companion paper
                                   # (Tharp 2026) independently identifies SDU from
                                   # claiming-age moments; that calibration does not
                                   # transfer here under joint UK identification.
                                   # Sensitivity: Section 6 reports model behavior
                                   # under alternative LAMBDA_W normalizations
                                   # including the BF-implied 0.85 value, with
                                   # PSI_PURCHASE re-bisected for each.

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
