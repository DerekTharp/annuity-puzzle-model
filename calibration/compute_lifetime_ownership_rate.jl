# Compute the corrected SPIA-equivalent ownership rate using the HRS fat-file
# per-contract lifetime indicator (q286_1, q286_2). For each respondent in
# our analysis sample (single, age 65-69, alive, waves 5-9), check whether
# any reported annuity contract was coded as "continues for life" (response 1).
#
# Cross-validate against:
#   - Lockwood (2012) reported 3.6% lifetime annuity rate
#   - Conventional iann > 0 rate (3.4% in our sample)
#
# Output: per-wave and pooled "lifetime annuity ownership" rates,
#         saved to data/processed/hrs_lifetime_ownership.csv

using ReadStatTables
using Printf
using Statistics

const PROJ = joinpath(@__DIR__, "..")
const RAND_HRS = joinpath(PROJ, "data", "raw", "HRS",
                          "randhrs1992_2022v1_STATA", "randhrs1992_2022v1.dta")

# Per-wave lifetime-annuity variables (respondent's contract slots).
# Wave 5 uses different naming convention; we treat it specially.
WAVES = [
    (5, "h00f1d", [Symbol("g5494_1"), Symbol("g5494_2")]),
    (6, "h02f2c", [Symbol("hq286_1"), Symbol("hq286_2")]),
    (7, "h04f1c", [Symbol("jq286_1"), Symbol("jq286_2")]),
    (8, "h06f4b", [Symbol("kq286_1"), Symbol("kq286_2")]),
    (9, "h08f3b", [Symbol("lq286_1"), Symbol("lq286_2")]),
]

# Single marital status codes
const SINGLE_CODES = Set([3, 4, 5, 7, 8])

numval(x::Real) = Float64(x)
numval(x) = Float64(x.value)

println("=" ^ 70)
println("  HRS LIFETIME ANNUITY OWNERSHIP — FAT-FILE EXTRACT")
println("=" ^ 70)
println()
println("Loading RAND HRS Longitudinal File for filter variables...")
rand_tbl = readstat(RAND_HRS)
const RAND_HHIDPN = collect(getproperty(rand_tbl, :hhidpn))
N_RAND = length(RAND_HHIDPN)
println("  RAND HRS rows: $N_RAND")
println()

# Build a dict: hhidpn -> rand row index
rand_idx = Dict{Float64, Int}()
for (i, h) in enumerate(RAND_HHIDPN)
    if !ismissing(h)
        rand_idx[Float64(h)] = i
    end
end

results_per_wave = []
all_persons_with_lifetime = Set{Float64}()
all_eligible_persons = Set{Float64}()

for (w, ff, life_vars) in WAVES
    println("--- Wave $w ($ff) ---")
    fat_path = joinpath(PROJ, "data", "raw", "HRS", "HRS Fat Files",
                       "$(ff)_STATA", "$(ff).dta")
    fat_tbl = readstat(fat_path)
    fat_hhidpn = collect(getproperty(fat_tbl, :hhidpn))

    # RAND wave-specific filter columns
    age_sym    = Symbol("r$(w)agey_b")
    mstat_sym  = Symbol("r$(w)mstat")
    iwstat_sym = Symbol("r$(w)iwstat")
    iann_sym   = Symbol("r$(w)iann")

    age_col    = collect(getproperty(rand_tbl, age_sym))
    mstat_col  = collect(getproperty(rand_tbl, mstat_sym))
    iwstat_col = collect(getproperty(rand_tbl, iwstat_sym))
    iann_col   = collect(getproperty(rand_tbl, iann_sym))

    # Get fat-file lifetime annuity columns (some may not exist)
    life_cols = []
    for v in life_vars
        if hasproperty(fat_tbl, v)
            push!(life_cols, collect(getproperty(fat_tbl, v)))
        end
    end
    println("  Lifetime-annuity variables found: $(length(life_cols))")

    n_eligible = 0
    n_iann_pos = 0
    n_lifetime = 0
    n_any_contract = 0  # any annuity contract reported (life or not)

    for fi in 1:length(fat_hhidpn)
        ismissing(fat_hhidpn[fi]) && continue
        h = Float64(fat_hhidpn[fi])
        ri = get(rand_idx, h, nothing)
        ri === nothing && continue

        # Filter on age, marital, alive
        ismissing(age_col[ri]) && continue
        age = numval(age_col[ri])
        (age < 65 || age > 69) && continue

        if iwstat_col[ri] !== missing && numval(iwstat_col[ri]) != 1
            continue
        end

        ismissing(mstat_col[ri]) && continue
        mstat = numval(mstat_col[ri])
        mstat in SINGLE_CODES || continue

        n_eligible += 1
        push!(all_eligible_persons, h)

        # iann-based ownership (the literature convention)
        if iann_col[ri] !== missing && numval(iann_col[ri]) > 0
            n_iann_pos += 1
        end

        # Fat-file lifetime indicator
        any_contract = false
        any_lifetime = false
        for col in life_cols
            v = col[fi]
            ismissing(v) && continue
            val = numval(v)
            # In HRS coding: 1=Yes (lifetime), 5=No (period-certain),
            # 8=Don't know, 9=Refused. A value of 0 or missing indicates
            # this contract slot is empty.
            if val == 1.0 || val == 5.0 || val == 8.0 || val == 9.0
                any_contract = true
            end
            if val == 1.0
                any_lifetime = true
            end
        end
        if any_contract
            n_any_contract += 1
        end
        if any_lifetime
            n_lifetime += 1
            push!(all_persons_with_lifetime, h)
        end
    end

    @printf("  n_eligible=%d  iann>0:%d (%.2f%%)  any_contract:%d (%.2f%%)  lifetime:%d (%.2f%%)\n",
            n_eligible,
            n_iann_pos, 100*n_iann_pos/max(n_eligible,1),
            n_any_contract, 100*n_any_contract/max(n_eligible,1),
            n_lifetime, 100*n_lifetime/max(n_eligible,1))
    push!(results_per_wave,
          (wave=w, n_eligible=n_eligible, n_iann_pos=n_iann_pos,
           n_any_contract=n_any_contract, n_lifetime=n_lifetime))
end

println()
println("=" ^ 70)
println("  POOLED PERSON-WAVE TOTALS")
println("=" ^ 70)
total_elig = sum(r.n_eligible for r in results_per_wave)
total_iann = sum(r.n_iann_pos for r in results_per_wave)
total_anyc = sum(r.n_any_contract for r in results_per_wave)
total_life = sum(r.n_lifetime for r in results_per_wave)
@printf("  Total person-waves:       %d\n", total_elig)
@printf("  iann > 0:                 %d  (%.2f%%)\n", total_iann, 100*total_iann/max(total_elig,1))
@printf("  Any annuity contract:     %d  (%.2f%%)\n", total_anyc, 100*total_anyc/max(total_elig,1))
@printf("  Lifetime annuity:         %d  (%.2f%%)\n", total_life, 100*total_life/max(total_elig,1))
println()
@printf("  Lockwood (2012) reported lifetime rate: 3.6%%\n")
@printf("  Our iann>0 conventional rate:           3.4%%\n")
println()

# Person-level (panel) cumulative incidence
println("=" ^ 70)
println("  PANEL: PERSONS WITH \"AT LEAST ONE LIFETIME ANNUITY\" EVER")
println("=" ^ 70)
n_persons_eligible = length(all_eligible_persons)
n_persons_lifetime = length(all_persons_with_lifetime)
@printf("  Unique persons eligible:        %d\n", n_persons_eligible)
@printf("  Unique persons w/ lifetime ann: %d  (%.2f%%)\n",
        n_persons_lifetime, 100*n_persons_lifetime/max(n_persons_eligible,1))
println()

# Save CSV
out_path = joinpath(PROJ, "data", "processed", "hrs_lifetime_ownership.csv")
open(out_path, "w") do f
    println(f, "wave,n_eligible,n_iann_pos,n_any_contract,n_lifetime,iann_pct,any_pct,lifetime_pct")
    for r in results_per_wave
        @printf(f, "%d,%d,%d,%d,%d,%.4f,%.4f,%.4f\n",
                r.wave, r.n_eligible, r.n_iann_pos, r.n_any_contract, r.n_lifetime,
                100*r.n_iann_pos/max(r.n_eligible,1),
                100*r.n_any_contract/max(r.n_eligible,1),
                100*r.n_lifetime/max(r.n_eligible,1))
    end
    @printf(f, "POOLED,%d,%d,%d,%d,%.4f,%.4f,%.4f\n",
            total_elig, total_iann, total_anyc, total_life,
            100*total_iann/max(total_elig,1),
            100*total_anyc/max(total_elig,1),
            100*total_life/max(total_elig,1))
end
println("  Saved: $out_path")
