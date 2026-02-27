# Estimate 3x3 health transition matrices by age band from the RAND HRS
# longitudinal file. Uses consecutive-wave pairs from waves 5-12 (2000-2014).
#
# HRS interviews are 2 years apart, so raw transition counts yield 2-YEAR
# transition rates. We convert to annual rates via matrix square root
# (eigendecomposition: P_annual = P_2yr^{1/2}).
#
# Health mapping: RAND HRS r{w}shlt (1=Excellent...5=Poor)
#   {1,2} -> Good(1), {3} -> Fair(2), {4,5} -> Poor(3)
#
# Output: data/processed/health_transitions_age_bands.csv
#
# References:
#   De Nardi, French, Jones (2010, JPE) — health transition calibration
#   Robinson (1996) — 3-state health dynamics
#   RAND HRS Longitudinal File codebook (v1, 2024)

using ReadStatTables
using Printf
using LinearAlgebra

# Extract underlying numeric value from ReadStatTables LabeledValue.
numval(x) = Int(getfield(x, :value))
numval(x::Number) = Int(x)

# Map 5-point self-reported health to 3 states.
# 1=Excellent, 2=Very Good -> Good(1)
# 3=Good -> Fair(2)
# 4=Fair, 5=Poor -> Poor(3)
function map_health(shlt::Int)
    shlt <= 2 && return 1
    shlt == 3 && return 2
    return 3
end

# Age band lookup. Returns band label string, or nothing if age < 65.
function age_band(age::Int)
    age < 65 && return nothing
    age <= 69 && return "65-69"
    age <= 74 && return "70-74"
    age <= 79 && return "75-79"
    age <= 84 && return "80-84"
    age <= 89 && return "85-89"
    return "90+"
end

const BAND_ORDER = ["65-69", "70-74", "75-79", "80-84", "85-89", "90+"]

"""
Compute matrix square root of a 3x3 stochastic matrix via eigendecomposition.
P_annual = P_2yr^{1/2} = V * D^{1/2} * V^{-1}.

If the result contains negative entries or complex eigenvalues, falls back
to Denman-Beavers iteration. Rows are renormalized to sum to 1.
"""
function matrix_sqrt_stochastic(P::Matrix{Float64})
    # Try eigendecomposition first
    F = eigen(P)
    vals = F.values
    vecs = F.vectors

    # Check for negative or complex eigenvalues
    all_real = all(x -> abs(imag(x)) < 1e-12, vals)
    all_positive = all_real && all(x -> real(x) > -1e-12, vals)

    if all_real && all_positive
        sqrt_vals = Diagonal(sqrt.(max.(real.(vals), 0.0)))
        P_sqrt = real(vecs * sqrt_vals * inv(vecs))
    else
        # Denman-Beavers iteration
        P_sqrt = _denman_beavers_sqrt(P)
    end

    # Clamp negative entries and renormalize rows
    P_sqrt = max.(P_sqrt, 0.0)
    for i in 1:size(P_sqrt, 1)
        s = sum(P_sqrt[i, :])
        if s > 0
            P_sqrt[i, :] ./= s
        end
    end
    return P_sqrt
end

"""
Denman-Beavers iteration for matrix square root.
Converges for matrices with no eigenvalues on the negative real axis.
"""
function _denman_beavers_sqrt(A::Matrix{Float64}; maxiter=100, tol=1e-12)
    n = size(A, 1)
    Y = copy(A)
    Z = Matrix{Float64}(I, n, n)
    for _ in 1:maxiter
        Y_new = 0.5 * (Y + inv(Z))
        Z_new = 0.5 * (Z + inv(Y))
        if norm(Y_new - Y, Inf) < tol
            return Y_new
        end
        Y = Y_new
        Z = Z_new
    end
    @warn "Denman-Beavers did not converge after $maxiter iterations"
    return Y
end


function main()
    println("=" ^ 70)
    println("  ESTIMATE HEALTH TRANSITION MATRICES BY AGE BAND")
    println("  RAND HRS waves 5-12 (2000-2014), ages 65+")
    println("=" ^ 70)

    # Load RAND HRS
    dta_path = joinpath(@__DIR__, "..", "data", "raw", "HRS",
        "randhrs1992_2022v1_STATA", "randhrs1992_2022v1.dta")
    println("\nLoading RAND HRS longitudinal file...")
    flush(stdout)
    tbl = readstat(dta_path; ntasks=0)
    N = length(tbl[1])
    @printf("  Loaded %d respondents\n", N)
    flush(stdout)

    # Waves 5-12 (2000-2014): consecutive pairs (5,6), (6,7), ..., (11,12)
    wave_pairs = [(w, w+1) for w in 5:11]
    wave_years = Dict(5=>2000, 6=>2002, 7=>2004, 8=>2006, 9=>2008,
                      10=>2010, 11=>2012, 12=>2014)

    # Accumulate 2-year transition counts: counts[band][from, to]
    counts = Dict{String, Matrix{Int}}()
    for band in BAND_ORDER
        counts[band] = zeros(Int, 3, 3)
    end

    total_obs = 0
    total_used = 0

    for (w1, w2) in wave_pairs
        @printf("\n  Processing wave pair (%d, %d): %d-%d\n", w1, w2,
                wave_years[w1], wave_years[w2])
        flush(stdout)

        # Column symbols
        shlt1_sym = Symbol("r$(w1)shlt")
        shlt2_sym = Symbol("r$(w2)shlt")
        age1_sym  = Symbol("r$(w1)agey_b")

        shlt1_col = try collect(getproperty(tbl, shlt1_sym)) catch; nothing end
        shlt2_col = try collect(getproperty(tbl, shlt2_sym)) catch; nothing end
        age1_col  = try collect(getproperty(tbl, age1_sym))  catch; nothing end

        if shlt1_col === nothing || shlt2_col === nothing || age1_col === nothing
            println("    Warning: missing columns, skipping")
            continue
        end

        n_pair = 0
        for i in 1:N
            total_obs += 1

            # Both health measures must be non-missing and valid (1-5)
            ismissing(shlt1_col[i]) && continue
            ismissing(shlt2_col[i]) && continue
            ismissing(age1_col[i])  && continue

            h1_raw = numval(shlt1_col[i])
            h2_raw = numval(shlt2_col[i])
            age    = numval(age1_col[i])

            (h1_raw < 1 || h1_raw > 5) && continue
            (h2_raw < 1 || h2_raw > 5) && continue

            band = age_band(age)
            band === nothing && continue  # age < 65

            h1 = map_health(h1_raw)
            h2 = map_health(h2_raw)
            counts[band][h1, h2] += 1
            n_pair += 1
        end
        total_used += n_pair
        @printf("    Used %d transitions (ages 65+, non-missing health)\n", n_pair)
        flush(stdout)
    end

    @printf("\n  Total observation-pairs checked: %d\n", total_obs)
    @printf("  Total transitions used:          %d\n", total_used)

    # ---------------------------------------------------------------
    # Compute 2-year and annual transition matrices
    # ---------------------------------------------------------------
    println("\n" * "=" ^ 70)
    println("  RAW 2-YEAR TRANSITION COUNTS AND MATRICES")
    println("=" ^ 70)

    trans_2yr = Dict{String, Matrix{Float64}}()
    trans_annual = Dict{String, Matrix{Float64}}()

    for band in BAND_ORDER
        C = counts[band]
        n_total = sum(C)

        println("\n  Age band: $band  (N = $n_total)")
        println("  Raw counts (rows=from, cols=to):")
        for i in 1:3
            @printf("    [%5d  %5d  %5d]\n", C[i,1], C[i,2], C[i,3])
        end

        # Row-normalize to get 2-year transition probabilities
        P2 = zeros(3, 3)
        for i in 1:3
            row_sum = sum(C[i, :])
            if row_sum > 0
                P2[i, :] = C[i, :] ./ row_sum
            else
                P2[i, i] = 1.0  # absorbing if no data
            end
        end
        trans_2yr[band] = P2

        println("  2-year transition matrix:")
        for i in 1:3
            @printf("    [%.4f  %.4f  %.4f]\n", P2[i,1], P2[i,2], P2[i,3])
        end

        # Annual = matrix square root
        P1 = matrix_sqrt_stochastic(P2)
        trans_annual[band] = P1

        println("  Annual transition matrix (sqrt of 2-year):")
        for i in 1:3
            @printf("    [%.4f  %.4f  %.4f]\n", P1[i,1], P1[i,2], P1[i,3])
        end

        # Verify: P1^2 should approximate P2
        P1sq = P1 * P1
        max_err = maximum(abs.(P1sq - P2))
        @printf("  Verification: max|P1^2 - P2| = %.2e\n", max_err)
        flush(stdout)
    end

    # ---------------------------------------------------------------
    # Print Julia code for pasting into health.jl
    # ---------------------------------------------------------------
    println("\n" * "=" ^ 70)
    println("  JULIA CODE FOR health.jl")
    println("=" ^ 70)
    println()
    println("# Annual transition matrices by age band (estimated from HRS panel data)")
    println("# Waves 5-12 (2000-2014), consecutive-wave pairs, matrix square root of 2-year rates")
    println("# See calibration/estimate_health_transitions.jl for estimation details")
    println("const HEALTH_TRANS_BANDS = Dict{String, Matrix{Float64}}(")
    for (idx, band) in enumerate(BAND_ORDER)
        P = trans_annual[band]
        comma = idx < length(BAND_ORDER) ? "," : ""
        @printf("    \"%s\" => [%.6f %.6f %.6f; %.6f %.6f %.6f; %.6f %.6f %.6f]%s\n",
            band,
            P[1,1], P[1,2], P[1,3],
            P[2,1], P[2,2], P[2,3],
            P[3,1], P[3,2], P[3,3],
            comma)
    end
    println(")")
    flush(stdout)

    # ---------------------------------------------------------------
    # Save to CSV
    # ---------------------------------------------------------------
    outpath = joinpath(@__DIR__, "..", "data", "processed", "health_transitions_age_bands.csv")
    println("\nWriting to $outpath...")
    open(outpath, "w") do io
        println(io, "age_band,type,from_state,to_good,to_fair,to_poor,n_from")
        for band in BAND_ORDER
            C = counts[band]
            P2 = trans_2yr[band]
            P1 = trans_annual[band]
            state_labels = ["Good", "Fair", "Poor"]
            for i in 1:3
                row_n = sum(C[i, :])
                @printf(io, "%s,count,%s,%d,%d,%d,%d\n",
                    band, state_labels[i], C[i,1], C[i,2], C[i,3], row_n)
            end
            for i in 1:3
                row_n = sum(C[i, :])
                @printf(io, "%s,2year,%s,%.6f,%.6f,%.6f,%d\n",
                    band, state_labels[i], P2[i,1], P2[i,2], P2[i,3], row_n)
            end
            for i in 1:3
                row_n = sum(C[i, :])
                @printf(io, "%s,annual,%s,%.6f,%.6f,%.6f,%d\n",
                    band, state_labels[i], P1[i,1], P1[i,2], P1[i,3], row_n)
            end
        end
    end
    println("  Done.")
    println("=" ^ 70)
    flush(stdout)
end

main()
