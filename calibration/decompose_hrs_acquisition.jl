# Decompose HRS observed annuity ownership by acquisition age.
#
# For each individual we observe as an annuity owner (r{w}iann > 0) at any wave
# in {5, 6, 7, 8, 9} (i.e., 2000-2008) at age 65-69, walk backwards through
# earlier waves of the panel to find the FIRST wave they became an owner. Map
# that first-owner wave to the individual's age at that wave, then bin:
#
#   pre-65:     first owner at age <  65
#   at-65/66:   first owner at age 65 or 66
#   post-65:    first owner at age >= 67 in the observation window
#   left-cens:  already an owner at first observed wave (can't determine)
#
# This decomposition tests whether the structural model's single-decision-at-65
# Bellman is a defensible match to the HRS observed ownership stock.
#
# Output: data/processed/hrs_acquisition_decomposition.csv
#         and a printed summary.

using ReadStatTables
using Printf
using Statistics

const HRS_PATH = joinpath(@__DIR__, "..", "data", "raw", "HRS",
                           "randhrs1992_2022v1_STATA",
                           "randhrs1992_2022v1.dta")

# Helper: extract numeric value from a possibly-LabeledValue cell
numval(x::Real) = Float64(x)
numval(x) = Float64(x.value)

println("=" ^ 70)
println("  HRS ANNUITY OWNERSHIP ACQUISITION DECOMPOSITION")
println("=" ^ 70)
println()
println("Loading RAND HRS Longitudinal File...")
println("  Path: $HRS_PATH")

tbl = readstat(HRS_PATH)
N = length(getproperty(tbl, :hhidpn))
println("  Loaded: $N person rows")
println()

# Wave structure: HRS ran biennially. RAND HRS includes waves 1-15 (1992-2020).
# We focus on the panel necessary to determine acquisition age.
# RAND HRS years: w1=1992, w2=1994, w3=1996, w4=1998, w5=2000, ...,
#                 w13=2016, w14=2018, w15=2020.
const WAVES = 1:15
const WAVE_YEARS = Dict(w => 1990 + 2*w for w in WAVES)

# Marital status codes indicating single
const SINGLE_CODES = Set([3, 4, 5, 7, 8])

# Identification: a person enters the analysis sample if they are observed
# at any wave 5-9 with age 65-69, single, alive, and owner (iann > 0).
const STUDY_WAVES = 5:9
const MIN_AGE = 65
const MAX_AGE = 69

println("Building per-person panel...")
hhidpn = collect(getproperty(tbl, :hhidpn))

# Pre-extract all wave columns into dicts of vectors keyed by wave
age_cols    = Dict{Int, Any}()
mstat_cols  = Dict{Int, Any}()
iwstat_cols = Dict{Int, Any}()
iann_cols   = Dict{Int, Any}()

for w in WAVES
    age_cols[w]    = try collect(getproperty(tbl, Symbol("r$(w)agey_b"))) catch; nothing end
    mstat_cols[w]  = try collect(getproperty(tbl, Symbol("r$(w)mstat")))  catch; nothing end
    iwstat_cols[w] = try collect(getproperty(tbl, Symbol("r$(w)iwstat"))) catch; nothing end
    iann_cols[w]   = try collect(getproperty(tbl, Symbol("r$(w)iann")))   catch; nothing end
end

println("  Wave columns extracted for waves $(minimum(WAVES))-$(maximum(WAVES))")
println()

# Walk each person, identify those in the analysis sample, and trace their
# annuity ownership across all waves they appear.

# Categories:
#   :pre65         first observed as owner at age < 65
#   :at_retirement first observed as owner at age 65 or 66
#   :post65        first observed as owner at age >= 67 (within HRS window)
#   :left_censored already owner in first observed wave AND first wave is the
#                  earliest wave this person appears in the panel (so can't
#                  rule out pre-panel acquisition)
#   :unknown       fallback

# For the analysis we are interested in people who appear as owners in any
# wave 5-9 at age 65-69. For each such person, find the FIRST wave they
# became an owner (going back to wave 1 if they were observed earlier).

n_eligible = 0       # observed at any wave 5-9, age 65-69, single
n_owner_in_window = 0
acquisition_bin = Dict{Symbol, Int}(:pre65 => 0, :at_retirement => 0,
                                     :post65 => 0, :left_censored => 0,
                                     :unknown => 0)
acquisition_ages = Int[]

for i in 1:N
    # Did this person ever appear in an analysis wave with the right age/status?
    eligible_anywhere = false
    owner_in_window = false
    for w in STUDY_WAVES
        ac = age_cols[w]; mc = mstat_cols[w]; sc = iwstat_cols[w]; nc = iann_cols[w]
        ac === nothing && continue
        ismissing(ac[i]) && continue
        age = numval(ac[i])
        (age < MIN_AGE || age > MAX_AGE) && continue
        if sc !== nothing && !ismissing(sc[i]) && numval(sc[i]) != 1; continue; end
        if mc === nothing || ismissing(mc[i]); continue; end
        mstat = numval(mc[i])
        mstat in SINGLE_CODES || continue
        eligible_anywhere = true
        if nc !== nothing && !ismissing(nc[i]) && numval(nc[i]) > 0
            owner_in_window = true
        end
    end
    eligible_anywhere || continue
    global n_eligible += 1
    owner_in_window || continue
    global n_owner_in_window += 1

    # Find the FIRST wave where this person was observed (any age) with iann
    # data, and the first wave where iann > 0.
    first_observed_wave = nothing
    first_owner_wave = nothing
    first_owner_age = nothing
    for w in WAVES
        ac = age_cols[w]; sc = iwstat_cols[w]; nc = iann_cols[w]
        ac === nothing && continue
        ismissing(ac[i]) && continue
        # Person must have been alive/interviewed
        sc === nothing && continue
        ismissing(sc[i]) && continue
        numval(sc[i]) == 1 || continue
        if first_observed_wave === nothing
            first_observed_wave = w
        end
        nc === nothing && continue
        ismissing(nc[i]) && continue
        if numval(nc[i]) > 0 && first_owner_wave === nothing
            first_owner_wave = w
            first_owner_age = Int(round(numval(ac[i])))
            break
        end
    end

    if first_owner_wave === nothing
        acquisition_bin[:unknown] += 1
        continue
    end

    if first_owner_wave == first_observed_wave
        # Already owner when first observed; can't determine if pre-panel
        acquisition_bin[:left_censored] += 1
        push!(acquisition_ages, first_owner_age)
        continue
    end

    push!(acquisition_ages, first_owner_age)
    if first_owner_age < 65
        acquisition_bin[:pre65] += 1
    elseif first_owner_age <= 66
        acquisition_bin[:at_retirement] += 1
    else
        acquisition_bin[:post65] += 1
    end
end

println("=" ^ 70)
println("  RESULTS")
println("=" ^ 70)
println()
@printf("  Eligible person-tracks (single, age 65-69 in waves 5-9): %d\n", n_eligible)
@printf("  Owners observed in window (iann > 0 at age 65-69, w5-9): %d\n", n_owner_in_window)
@printf("  Implied window ownership rate: %.2f%%\n", 100 * n_owner_in_window / n_eligible)
println()
println("  Acquisition decomposition (of owners observed in window):")
total_traced = sum(values(acquisition_bin))
for k in [:pre65, :at_retirement, :post65, :left_censored, :unknown]
    n = acquisition_bin[k]
    pct = 100 * n / max(total_traced, 1)
    @printf("    %-15s n=%4d  (%5.1f%%)\n", string(k), n, pct)
end
println()

if !isempty(acquisition_ages)
    println("  Distribution of first-observed-owner age (where determinable):")
    for a_lo in 50:5:75
        cnt = count(a -> a >= a_lo && a < a_lo + 5, acquisition_ages)
        if cnt > 0
            @printf("    age %d-%d: %d\n", a_lo, a_lo + 4, cnt)
        end
    end
    @printf("  Median first-owner age: %d\n", Int(round(median(acquisition_ages))))
end

# Save CSV
out_path = joinpath(@__DIR__, "..", "data", "processed", "hrs_acquisition_decomposition.csv")
open(out_path, "w") do f
    println(f, "category,n_persons,share_of_traced")
    for k in [:pre65, :at_retirement, :post65, :left_censored, :unknown]
        n = acquisition_bin[k]
        share = n / max(total_traced, 1)
        @printf(f, "%s,%d,%.6f\n", string(k), n, share)
    end
end
println()
println("  Saved: $out_path")
