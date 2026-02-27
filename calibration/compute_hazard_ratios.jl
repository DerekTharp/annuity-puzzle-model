# Compute mortality hazard ratios by self-reported health from RAND HRS data.
#
# Method:
# 1. Load RAND HRS longitudinal file
# 2. Recode 5-point health → 3 states: Good (1-2), Fair (3), Poor (4-5)
# 3. For each wave pair (t, t+1), among respondents aged 65+:
#    - Record health state at wave t (interview where respondent is alive)
#    - Check if died before wave t+1 (iwstat = 5 or 6 in wave t+1)
# 4. Compute 2-year mortality rate by health state and age band
# 5. Convert to annual hazard: μ = -ln(1 - m_2yr) / 2
# 6. Compute hazard ratios: μ(Good)/μ(Fair) and μ(Poor)/μ(Fair)
#
# These ratios are the empirical hazard multipliers for the model.
#
# References:
#   - Idler & Benyamini (1997, J Health Soc Behav): self-reported health predicts mortality
#   - DeSalvo et al. (2006, J Gen Int Med): meta-analysis of SRH-mortality association
#   - De Nardi, French, Jones (2010, JPE): health transitions from HRS

using ReadStatTables
using Printf

# Extract underlying numeric value from ReadStatTables LabeledValue.
# LabeledValue wraps an Int8 with a label string; we need the raw integer.
numval(x) = Int(getfield(x, :value))
numval(x::Number) = Int(x)

function main()
    println("=" ^ 70)
    println("  EMPIRICAL HAZARD RATIOS FROM RAND HRS")
    println("  Self-reported health → mortality gradient")
    println("=" ^ 70)

    # Load data
    println("\nLoading RAND HRS longitudinal file...")
    dta_path = joinpath(@__DIR__, "..", "data", "raw", "HRS",
        "randhrs1992_2022v1_STATA", "randhrs1992_2022v1.dta")
    tbl = readstat(dta_path; ntasks=0)
    N = length(tbl[1])
    println("  Loaded $N respondents")

    # Wave mapping: RAND HRS waves 4-16 correspond to survey years 1998-2022
    # Each wave is ~2 years apart
    # Wave 4 = 1998, Wave 5 = 2000, ..., Wave 16 = 2022
    wave_years = Dict(4=>1998, 5=>2000, 6=>2002, 7=>2004, 8=>2006,
                      9=>2008, 10=>2010, 11=>2012, 12=>2014, 13=>2016,
                      14=>2018, 15=>2020, 16=>2022)

    # Extract data for all wave pairs
    # For each person × wave: (age, health_3state, died_by_next_wave)

    # Recode 5-point → 3-state
    # Original: 1=Excellent, 2=VeryGood, 3=Good, 4=Fair, 5=Poor
    # Recoded: 1=Good(1-2), 2=Fair(3), 3=Poor(4-5)
    function recode_health(val)
        v = numval(val)
        if v <= 2
            return 1  # Good
        elseif v == 3
            return 2  # Fair
        else
            return 3  # Poor
        end
    end

    # Age bands
    age_bands = [(65, 74, "65-74"), (75, 84, "75-84"), (85, 120, "85+")]

    # Collect (health_3state, age_band_idx, died) observations
    obs_health = Int[]
    obs_ageband = Int[]
    obs_died = Int[]
    obs_age = Int[]

    for w in 4:15
        # Column symbols
        shlt_sym = Symbol("r$(w)shlt")
        agey_sym = Symbol("r$(w)agey_m")
        iwstat_curr_sym = Symbol("r$(w)iwstat")
        iwstat_next_sym = Symbol("r$(w+1)iwstat")

        shlt = collect(getproperty(tbl, shlt_sym))
        agey = collect(getproperty(tbl, agey_sym))
        iw_curr = collect(getproperty(tbl, iwstat_curr_sym))
        iw_next = collect(getproperty(tbl, iwstat_next_sym))

        for i in 1:N
            # Must be alive respondent in current wave
            ismissing(iw_curr[i]) && continue
            numval(iw_curr[i]) != 1 && continue  # 1 = resp, alive

            # Must have health and age
            ismissing(shlt[i]) && continue
            ismissing(agey[i]) && continue

            age = numval(agey[i])
            age < 65 && continue

            # Must have status in next wave
            ismissing(iw_next[i]) && continue
            iw_next_val = numval(iw_next[i])

            # Died = iwstat 5 (died this wave) or 6 (died prev wave)
            # Both indicate death between wave t and t+1
            # Also accept iwstat 1 (alive) or 4 (NR, alive) as survived
            # Skip 0 (inap) and 7 (dropped) — can't determine survival
            died = -1
            if iw_next_val == 5 || iw_next_val == 6
                died = 1
            elseif iw_next_val == 1 || iw_next_val == 4
                died = 0
            else
                continue  # unknown status, skip
            end

            h3 = recode_health(shlt[i])

            # Find age band
            ab = 0
            for (j, (lo, hi, _)) in enumerate(age_bands)
                if age >= lo && age <= hi
                    ab = j
                    break
                end
            end
            ab == 0 && continue

            push!(obs_health, h3)
            push!(obs_ageband, ab)
            push!(obs_died, died)
            push!(obs_age, age)
        end
    end

    n_obs = length(obs_health)
    n_died = sum(obs_died)
    println("  Person-wave observations (age 65+, alive respondents): $n_obs")
    println("  Deaths observed: $n_died")
    println("  Overall 2-year mortality: $(round(n_died/n_obs*100, digits=1))%")

    # Compute mortality by health state and age band
    health_labels = ["Good (Exc/VG)", "Fair (Good)", "Poor (Fair/Poor)"]

    println("\n" * "=" ^ 70)
    println("  2-YEAR MORTALITY RATES BY HEALTH STATE AND AGE BAND")
    println("=" ^ 70)

    # Storage for hazard ratios
    hazard_ratios = zeros(3, 3)  # [age_band, health_state]
    counts = zeros(Int, 3, 3)
    deaths = zeros(Int, 3, 3)

    for ab in 1:3
        for h in 1:3
            mask = (obs_ageband .== ab) .& (obs_health .== h)
            n = sum(mask)
            d = sum(obs_died[mask])
            counts[ab, h] = n
            deaths[ab, h] = d
        end
    end

    @printf("\n  %-15s", "Age band")
    for h in 1:3
        @printf("  %20s", health_labels[h])
    end
    println()
    println("  " * "-" ^ 77)

    for (ab, (lo, hi, label)) in enumerate(age_bands)
        @printf("  %-15s", label)
        for h in 1:3
            n = counts[ab, h]
            d = deaths[ab, h]
            rate = n > 0 ? d / n : NaN
            @printf("  %8.1f%% (%5d/%5d)", rate * 100, d, n)
        end
        println()
    end

    # Overall by health state
    println("  " * "-" ^ 77)
    @printf("  %-15s", "All 65+")
    for h in 1:3
        n = sum(counts[:, h])
        d = sum(deaths[:, h])
        rate = d / n
        @printf("  %8.1f%% (%5d/%5d)", rate * 100, d, n)
    end
    println()

    # Convert to annual hazard rates and compute ratios
    println("\n" * "=" ^ 70)
    println("  ANNUAL HAZARD RATES AND RATIOS (relative to Fair)")
    println("=" ^ 70)

    @printf("\n  %-15s", "Age band")
    for h in 1:3
        @printf("  %10s  %10s", "μ($(health_labels[h][1:4]))", "Ratio")
    end
    println()
    println("  " * "-" ^ 85)

    # Compute hazard ratios by age band
    for (ab, (lo, hi, label)) in enumerate(age_bands)
        @printf("  %-15s", label)
        hazards = Float64[]
        for h in 1:3
            n = counts[ab, h]
            d = deaths[ab, h]
            m2yr = d / n
            # Annual hazard from 2-year mortality
            mu = -log(1 - m2yr) / 2
            push!(hazards, mu)
        end
        # Ratios relative to Fair (h=2)
        for h in 1:3
            ratio = hazards[h] / hazards[2]
            hazard_ratios[ab, h] = ratio
            @printf("  %10.4f  %10.2f", hazards[h], ratio)
        end
        println()
    end

    # Overall ratios
    println("  " * "-" ^ 85)
    @printf("  %-15s", "All 65+")
    overall_hazards = Float64[]
    for h in 1:3
        n = sum(counts[:, h])
        d = sum(deaths[:, h])
        m2yr = d / n
        mu = -log(1 - m2yr) / 2
        push!(overall_hazards, mu)
    end
    for h in 1:3
        ratio = overall_hazards[h] / overall_hazards[2]
        @printf("  %10.4f  %10.2f", overall_hazards[h], ratio)
    end
    println()

    # Summary
    println("\n" * "=" ^ 70)
    println("  SUMMARY: EMPIRICAL HAZARD MULTIPLIERS")
    println("=" ^ 70)

    overall_ratios = overall_hazards ./ overall_hazards[2]
    @printf("\n  Overall hazard multipliers [Good, Fair, Poor]:\n")
    @printf("    [%.2f, 1.00, %.2f]\n", overall_ratios[1], overall_ratios[3])

    println("\n  By age band:")
    for (ab, (_, _, label)) in enumerate(age_bands)
        ratios = hazard_ratios[ab, :] ./ hazard_ratios[ab, 2]
        @printf("    %5s: [%.2f, 1.00, %.2f]\n", label, ratios[1], ratios[3])
    end

    println("\n  Current model:     [0.40, 1.00, 3.00]")
    @printf("  HRS empirical:     [%.2f, 1.00, %.2f]\n", overall_ratios[1], overall_ratios[3])

    # Also compute 5-point health mortality rates for reference
    println("\n" * "=" ^ 70)
    println("  5-POINT HEALTH MORTALITY (for reference)")
    println("=" ^ 70)

    health5_labels = ["Excellent", "Very Good", "Good", "Fair", "Poor"]
    @printf("\n  %-15s", "Health")
    @printf("  %10s  %10s  %10s  %10s\n", "N", "Deaths", "2yr Mort", "Hazard Ratio")
    println("  " * "-" ^ 60)

    # Redo with 5-state storage for fine-grained view
    obs5_health = Int[]
    obs5_died = Int[]
    obs5_ageband = Int[]

    for w in 4:15
        shlt = collect(getproperty(tbl, Symbol("r$(w)shlt")))
        agey = collect(getproperty(tbl, Symbol("r$(w)agey_m")))
        iw_curr = collect(getproperty(tbl, Symbol("r$(w)iwstat")))
        iw_next = collect(getproperty(tbl, Symbol("r$(w+1)iwstat")))

        for i in 1:N
            ismissing(iw_curr[i]) && continue
            numval(iw_curr[i]) != 1 && continue
            ismissing(shlt[i]) && continue
            ismissing(agey[i]) && continue
            age = numval(agey[i])
            age < 65 && continue
            ismissing(iw_next[i]) && continue
            iw_next_val = numval(iw_next[i])

            died = -1
            if iw_next_val == 5 || iw_next_val == 6
                died = 1
            elseif iw_next_val == 1 || iw_next_val == 4
                died = 0
            else
                continue
            end

            push!(obs5_health, numval(shlt[i]))
            push!(obs5_died, died)
            # Age band
            ab = 0
            for (j, (lo, hi, _)) in enumerate(age_bands)
                if age >= lo && age <= hi; ab = j; break; end
            end
            push!(obs5_ageband, ab)
        end
    end

    hazards5_all = Float64[]
    for h5 in 1:5
        mask = obs5_health .== h5
        n5 = sum(mask)
        d5 = sum(obs5_died[mask])
        m2yr = n5 > 0 ? d5 / n5 : 0.0
        mu5 = m2yr > 0 ? -log(1 - m2yr) / 2 : 0.0
        push!(hazards5_all, mu5)
    end

    # Use "Good" (3) as reference for 5-point (maps to our "Fair")
    for h5 in 1:5
        mask = obs5_health .== h5
        n5 = sum(mask)
        d5 = sum(obs5_died[mask])
        m2yr = n5 > 0 ? d5 / n5 : 0.0
        ratio5 = hazards5_all[h5] / hazards5_all[3]
        @printf("  %-15s  %10d  %10d  %9.1f%%  %10.2f\n",
            health5_labels[h5], n5, d5, m2yr * 100, ratio5)
    end

    # Also by age band for 5-point
    println("\n  Hazard ratios by age band (5-point, ref=Good):")
    for (ab, (_, _, label)) in enumerate(age_bands)
        @printf("    %5s: ", label)
        h5_ref = 0.0
        h5_vals = Float64[]
        for h5 in 1:5
            mask = (obs5_health .== h5) .& (obs5_ageband .== ab)
            n5 = sum(mask)
            d5 = sum(obs5_died[mask])
            m2yr = n5 > 0 ? d5 / n5 : 0.0
            mu5 = m2yr > 0 ? -log(1 - m2yr) / 2 : 0.0
            push!(h5_vals, mu5)
            if h5 == 3; h5_ref = mu5; end
        end
        ratios5 = h5_ref > 0 ? h5_vals ./ h5_ref : h5_vals
        @printf("[%.2f, %.2f, 1.00, %.2f, %.2f]\n",
            ratios5[1], ratios5[2], ratios5[4], ratios5[5])
    end

    # Write results to CSV
    csv_path = joinpath(@__DIR__, "..", "data", "processed", "hrs_hazard_ratios.csv")
    open(csv_path, "w") do f
        println(f, "age_band,health_state,n_obs,n_deaths,mortality_2yr,annual_hazard,hazard_ratio_vs_fair")
        for ab in 1:3
            for h in 1:3
                n = counts[ab, h]
                d = deaths[ab, h]
                m2yr = d / n
                mu = -log(1 - m2yr) / 2
                ratio = mu / (-log(1 - deaths[ab,2]/counts[ab,2]) / 2)
                @printf(f, "%s,%s,%d,%d,%.4f,%.4f,%.2f\n",
                    age_bands[ab][3], health_labels[h], n, d, m2yr, mu, ratio)
            end
        end
        # Overall
        for h in 1:3
            n = sum(counts[:, h])
            d = sum(deaths[:, h])
            m2yr = d / n
            mu = -log(1 - m2yr) / 2
            ratio = mu / overall_hazards[2]
            @printf(f, "%s,%s,%d,%d,%.4f,%.4f,%.2f\n",
                "All 65+", health_labels[h], n, d, m2yr, mu, ratio)
        end
    end
    println("\n  Results saved to: $csv_path")

    println("\n" * "=" ^ 70)
    println("  DONE")
    println("=" ^ 70)
end

main()
