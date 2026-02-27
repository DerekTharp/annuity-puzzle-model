# Baseline calibration constants shared across all scripts.
# Change values here; all scripts will pick them up.

const GAMMA      = 2.5
const BETA       = 0.97
const R_RATE     = 0.02
const AGE_START  = 65
const AGE_END    = 110
const C_FLOOR    = 6_180.0
const W_MAX      = 3_000_000.0  # covers p99.5 of HRS wealth distribution
const MWR_LOADED = 0.82
const FIXED_COST = 1_000.0
const INFLATION  = 0.02
const N_WEALTH   = 80
const N_ANNUITY  = 30
const N_ALPHA    = 101
const A_GRID_POW = 3.0
const N_QUAD     = 9
const THETA_DFJ  = 56.96
const KAPPA_DFJ  = 272_628.0
const HAZARD_MULT = [0.50, 1.0, 3.0]
const SURVIVAL_PESSIMISM = 0.981
const MIN_WEALTH = 5_000.0

const CONSUMPTION_DECLINE = 0.0   # age-varying consumption needs (off by default)
const HEALTH_UTILITY = [1.0, 1.0, 1.0]  # state-dependent utility (off by default)

# HRS population data path
const HRS_PATH = joinpath(@__DIR__, "..", "data", "processed", "lockwood_hrs_sample.csv")
