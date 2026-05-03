# Noise-robust HRS annuity acquisition decomposition.
#
# Same setup as decompose_hrs_acquisition.jl but applies stricter rules to
# avoid false-positive "first owner" classifications from reporting noise:
#
#   1. "Real" first owner = first wave with iann > 0 AND iann > 0 in the
#      next observed wave (i.e., persistence requirement).
#   2. Optional dollar threshold: iann > $100 (to drop trivial reports).
#   3. Track also a "single-wave-positive" count to gauge how much noise
#      we'd be picking up.
#
# Reports two decompositions side by side: original and noise-robust.

using ReadStatTables
using Printf
using Statistics

const HRS_PATH = joinpath(@__DIR__, "..", "data", "raw", "HRS",
                           "randhrs1992_2022v1_STATA",
                           "randhrs1992_2022v1.dta")

numval(x::Real) = Float64(x)
numval(x) = Float64(x.value)

println("=" ^ 70)
println("  HRS ANNUITY ACQUISITION DECOMPOSITION — NOISE-ROBUST")
println("=" ^ 70)
println()
println("Loading RAND HRS Longitudinal File...")
tbl = readstat(HRS_PATH)
N = length(getproperty(tbl, :hhidpn))
println("  Loaded: $N person rows")
println()

const WAVES = 1:15
const STUDY_WAVES = 5:9
const MIN_AGE = 65
const MAX_AGE = 69
const SINGLE_CODES = Set([3, 4, 5, 7, 8])
const MIN_DOLLAR_AMOUNT = 100.0

# Pre-extract wave columns
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

# For each person, get the sequence of (wave, age, alive, iann) tuples in
# wave order (skipping waves where person isn't observed alive).
function person_track(i)
    track = Tuple{Int, Int, Float64}[]  # (wave, age, iann)
    for w in WAVES
        sc = iwstat_cols[w]; ac = age_cols[w]; nc = iann_cols[w]
        sc === nothing && continue
        ismissing(sc[i]) && continue
        numval(sc[i]) == 1 || continue  # alive respondent
        ac === nothing && continue
        ismissing(ac[i]) && continue
        age = Int(round(numval(ac[i])))
        iann = (nc !== nothing && !ismissing(nc[i])) ? numval(nc[i]) : 0.0
        push!(track, (w, age, iann))
    end
    return track
end

# Find first wave with iann > threshold AND next observed wave also has iann > 0
# (persistence requirement). Returns (first_wave, first_age) or nothing.
function find_robust_first_owner(track::Vector{Tuple{Int, Int, Float64}}, threshold)
    for k in 1:length(track)
        track[k][3] > threshold || continue
        # If this is the LAST observation, we cannot verify persistence; treat as
        # tentative-positive and skip (report separately).
        k == length(track) && return nothing
        # Persistence: next observed wave must also have iann > 0
        track[k+1][3] > 0.0 || continue
        return (track[k][1], track[k][2])
    end
    return nothing
end

function find_lenient_first_owner(track::Vector{Tuple{Int, Int, Float64}})
    for k in 1:length(track)
        track[k][3] > 0.0 && return (track[k][1], track[k][2])
    end
    return nothing
end

# Categorize first-owner age
function bin_age(a)
    a < 65       && return :pre65
    a <= 66      && return :at_retirement
    return :post65
end

# Iterate eligibility + decomposition
n_eligible = 0
n_owner_in_window_lenient = 0
n_owner_in_window_robust  = 0

# Lenient (original) bins
bins_lenient = Dict{Symbol, Int}(:pre65 => 0, :at_retirement => 0,
                                  :post65 => 0, :left_censored => 0,
                                  :unknown => 0)

# Robust bins
bins_robust = Dict{Symbol, Int}(:pre65 => 0, :at_retirement => 0,
                                 :post65 => 0, :left_censored => 0,
                                 :transient_positive => 0,
                                 :unknown => 0)

ages_lenient = Int[]
ages_robust  = Int[]

# Also tally single-wave (transient) vs persistent (>= 2-wave) ownership in window
n_transient_in_window = 0
n_persistent_in_window = 0

for i in 1:N
    # Eligibility check via study-wave criteria
    eligible = false
    in_window_owner = false
    in_window_persistent = false

    for w in STUDY_WAVES
        ac = age_cols[w]; mc = mstat_cols[w]; sc = iwstat_cols[w]; nc = iann_cols[w]
        ac === nothing && continue
        ismissing(ac[i]) && continue
        age = numval(ac[i])
        (age < MIN_AGE || age > MAX_AGE) && continue
        if sc !== nothing && !ismissing(sc[i]) && numval(sc[i]) != 1; continue; end
        mc === nothing && continue
        ismissing(mc[i]) && continue
        numval(mc[i]) in SINGLE_CODES || continue
        eligible = true
        if nc !== nothing && !ismissing(nc[i]) && numval(nc[i]) > 0
            in_window_owner = true
            # Check persistence at next study wave
            wnext = w + 1
            if wnext <= maximum(WAVES)
                nc_next = iann_cols[wnext]
                if nc_next !== nothing && !ismissing(nc_next[i]) && numval(nc_next[i]) > 0
                    in_window_persistent = true
                end
            end
        end
    end

    eligible || continue
    global n_eligible += 1

    in_window_owner || continue
    global n_owner_in_window_lenient += 1
    in_window_persistent && (global n_persistent_in_window += 1)
    in_window_persistent || (global n_transient_in_window += 1)

    if in_window_persistent
        global n_owner_in_window_robust += 1
    end

    track = person_track(i)
    isempty(track) && (bins_lenient[:unknown] += 1; bins_robust[:unknown] += 1; continue)
    first_observed_wave = track[1][1]

    # Lenient
    res_l = find_lenient_first_owner(track)
    if res_l === nothing
        bins_lenient[:unknown] += 1
    else
        first_w, first_a = res_l
        push!(ages_lenient, first_a)
        if first_w == first_observed_wave
            bins_lenient[:left_censored] += 1
        else
            bins_lenient[bin_age(first_a)] += 1
        end
    end

    # Robust
    res_r = find_robust_first_owner(track, MIN_DOLLAR_AMOUNT)
    if res_r === nothing
        # No 2-wave-persistent owner observation found
        if in_window_owner
            bins_robust[:transient_positive] += 1
        else
            bins_robust[:unknown] += 1
        end
    else
        first_w, first_a = res_r
        push!(ages_robust, first_a)
        if first_w == first_observed_wave
            bins_robust[:left_censored] += 1
        else
            bins_robust[bin_age(first_a)] += 1
        end
    end
end

println("=" ^ 70)
println("  RESULTS")
println("=" ^ 70)
println()
@printf("  Eligible person-tracks: %d\n", n_eligible)
@printf("  Owners in window (any iann > 0):       %d (%.2f%%)\n",
        n_owner_in_window_lenient, 100 * n_owner_in_window_lenient / n_eligible)
@printf("  Owners in window (2+ waves persistent): %d (%.2f%%)\n",
        n_owner_in_window_robust, 100 * n_owner_in_window_robust / n_eligible)
@printf("  -- transient (single-wave only):        %d\n", n_transient_in_window)
@printf("  -- persistent (multi-wave):             %d\n", n_persistent_in_window)
println()

println("  ── LENIENT (any iann > 0): ──")
total_l = sum(values(bins_lenient))
for k in [:pre65, :at_retirement, :post65, :left_censored, :unknown]
    n = bins_lenient[k]
    pct = 100 * n / max(total_l, 1)
    @printf("    %-20s n=%4d  (%5.1f%%)\n", string(k), n, pct)
end
println()

println("  ── NOISE-ROBUST (iann > \$$(Int(MIN_DOLLAR_AMOUNT)) AND next wave > 0): ──")
total_r = sum(values(bins_robust))
for k in [:pre65, :at_retirement, :post65, :left_censored, :transient_positive, :unknown]
    n = bins_robust[k]
    pct = 100 * n / max(total_r, 1)
    @printf("    %-20s n=%4d  (%5.1f%%)\n", string(k), n, pct)
end
println()

# Recompute the proportions WITHIN each definition's "real owner" denominator.
# For the structural-model question we want: of confirmed annuity owners,
# what share's first-owner age is at-retirement vs other.
#
# Lenient denom = pre65 + at_retirement + post65 + left_censored.
# Robust denom = same but using robust bins.

denom_l = bins_lenient[:pre65] + bins_lenient[:at_retirement] +
          bins_lenient[:post65] + bins_lenient[:left_censored]
denom_r = bins_robust[:pre65] + bins_robust[:at_retirement] +
          bins_robust[:post65] + bins_robust[:left_censored]

println("  ── ACQUISITION SHARES AMONG CONFIRMED OWNERS ──")
println("                       Lenient    Robust")
for k in [:pre65, :at_retirement, :post65, :left_censored]
    p_l = 100 * bins_lenient[k] / max(denom_l, 1)
    p_r = 100 * bins_robust[k] / max(denom_r, 1)
    @printf("    %-15s   %5.1f%%    %5.1f%%\n", string(k), p_l, p_r)
end
println()
@printf("  Confirmed-owner counts: lenient=%d, robust=%d\n", denom_l, denom_r)
println()

if !isempty(ages_robust)
    @printf("  Median first-owner age (robust): %d\n", Int(round(median(ages_robust))))
end

# Save CSV
out_path = joinpath(@__DIR__, "..", "data", "processed",
                    "hrs_acquisition_decomposition_robust.csv")
open(out_path, "w") do f
    println(f, "definition,category,n_persons,share_of_confirmed")
    for (def, bins, denom) in [("lenient", bins_lenient, denom_l),
                                ("robust",  bins_robust,  denom_r)]
        for k in [:pre65, :at_retirement, :post65, :left_censored,
                  :transient_positive, :unknown]
            haskey(bins, k) || continue
            n = bins[k]
            share = denom > 0 ? n / denom : 0.0
            @printf(f, "%s,%s,%d,%.6f\n", def, string(k), n, share)
        end
    end
end
println("  Saved: $out_path")
