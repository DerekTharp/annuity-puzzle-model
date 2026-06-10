# Shared constants and helpers for RAND HRS sample construction.
# Used by build_hrs_sample.jl and build_ss_profile.jl so filters, deflators,
# and variable choices stay identical across the two scripts.
#
# Price deflation: RAND HRS dollar amounts are nominal. Income variables refer
# to the LAST CALENDAR YEAR before the interview ("Income measures are from the
# last calendar year, e.g., 2001 for income reported at the 2002 interview" —
# RAND HRS 2022 (V1) codebook); wealth is measured at the interview. Both are
# deflated to 2014 dollars (the model's unit, matching the Jones et al. 2018
# medical-cost calibration) with CPI-U annual averages.
#
# CPI-U (NSA, all items, U.S. city average, 1982-84=100), annual averages from
# BLS via FRED series CPIAUCNS, retrieved 2026-06-08.
const CPI_U = Dict(
    1999 => 166.575,
    2000 => 172.200,
    2001 => 177.067,
    2002 => 179.875,
    2003 => 183.958,
    2004 => 188.883,
    2005 => 195.292,
    2006 => 201.592,
    2007 => 207.342,
    2008 => 215.303,
    2014 => 236.736,
)

# Wave -> interview year. Income reference year is the prior calendar year.
const WAVE_YEARS = Dict(5 => 2000, 6 => 2002, 7 => 2004, 8 => 2006, 9 => 2008)

deflator_wealth(wave::Int) = CPI_U[2014] / CPI_U[WAVE_YEARS[wave]]
deflator_income(wave::Int) = CPI_U[2014] / CPI_U[WAVE_YEARS[wave] - 1]

# Marital status codes indicating single (RwMSTAT):
#   3=separated, 4=divorced, 5=widowed, 7=never married, 8=other
const SINGLE_MSTAT = Set([3, 4, 5, 7, 8])

# Labor force status codes (RwLBRF) counted as retired / out of the labor
# force: 4=partly retired, 5=retired, 6=disabled, 7=not in labor force.
# Excludes 1=works FT, 2=works PT, 3=unemployed (job seekers). The sample is
# "single nonworking retirees": the model has no labor income, and active
# workers' not-yet-claimed Social Security would bias the benefit level down.
const RETIRED_LBRF = Set([4, 5, 6, 7])

# Extract underlying numeric value from ReadStatTables LabeledValue.
numval(x) = Int(getfield(x, :value))
numval(x::Number) = Int(x)
numval_float(x) = Float64(getfield(x, :value))
numval_float(x::Number) = Float64(x)
