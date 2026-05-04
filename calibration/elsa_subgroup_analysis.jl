# ELSA post-2015 freedoms: subgroup annuitization rates by age, sex, education,
# health. Merges pension grid (disposition decisions) with IFS-derived
# demographics on idauniq.
#
# Output: data/processed/elsa_disposition_subgroups.csv

using ReadStatTables
using Printf
using Statistics

const PROJ = joinpath(@__DIR__, "..")

# ELSA archive location. Configurable via ANNUITY_ELSA_ARCHIVE env var.
const ELSA_ZIP = let
    env_path = get(ENV, "ANNUITY_ELSA_ARCHIVE", "")
    project_path = joinpath(PROJ, "data", "raw", "ELSA",
        "5050_ELSA_Main_Waves0-11_1998-2024.zip")
    legacy_path = joinpath(homedir(), "Documents", "_Datasets",
        "ELSA (English Longitudinal Study of Aging)",
        "5050_ELSA_Main_Waves0-11_1998-2024.zip")
    if !isempty(env_path) && isfile(env_path)
        env_path
    elseif isfile(project_path)
        project_path
    elseif isfile(legacy_path)
        legacy_path
    else
        error("ELSA archive not found. Set ANNUITY_ELSA_ARCHIVE to the path of " *
              "5050_ELSA_Main_Waves0-11_1998-2024.zip, or place the file at " *
              "data/raw/ELSA/. UK Data Service deposit 5050.")
    end
end
const TMP_DIR = "/tmp/elsa_extract"

const WAVES = [
    (8,  "wave_8_elsa_pensiongrid_eul_v1.dta",  "wave_8_ifs_derived_variables.dta",  "2016-17"),
    (9,  "wave_9_elsa_pensiongrid_eul_v3.dta",  "wave_9_ifs_derived_variables.dta",  "2018-19"),
    (10, "wave_10_elsa_pensiongrid_eul_v2.dta", "wave_10_ifs_derived_variables.dta", "2021-22"),
    (11, "wave_11_elsa_pensiongrid_eul.dta",    "wave_11_ifs_derived_variables.dta", "2023-24"),
]

function ensure_extracted(filename)
    target = joinpath(TMP_DIR, filename)
    isfile(target) && return target
    mkpath(TMP_DIR)
    inner_path = "UKDA-5050-stata/stata/stata13_se/$filename"
    run(pipeline(`unzip -j -o $ELSA_ZIP $inner_path -d $TMP_DIR`,
                 stdout=devnull, stderr=devnull))
    return target
end

numval(x) = try Float64(x) catch; try Float64(x.value) catch; missing end end
get_or_missing(d, k, default=missing) = haskey(d, k) ? d[k] : default

# Build per-person decision: did they annuitize ANY of their lump sums in this wave?
# For each respondent (idauniq), aggregate across pension grid rows:
#   - has_lump_sum = any wpirls > 0
#   - did_annuitize_ls = any wpirpan == 1 (used any lump sum to buy annuity)
function build_person_disposition(pg_tbl)
    idauniq_col = collect(getproperty(pg_tbl, :idauniq))
    wpirls_col  = hasproperty(pg_tbl, :wpirls)  ? collect(getproperty(pg_tbl, :wpirls))  : nothing
    wpirpan_col = hasproperty(pg_tbl, :wpirpan) ? collect(getproperty(pg_tbl, :wpirpan)) : nothing
    wpdcpan_col = hasproperty(pg_tbl, :wpdcpan) ? collect(getproperty(pg_tbl, :wpdcpan)) : nothing
    n = length(idauniq_col)
    person_decisions = Dict{Float64, Dict{Symbol, Any}}()
    for i in 1:n
        ismissing(idauniq_col[i]) && continue
        h = numval(idauniq_col[i])
        ismissing(h) && continue
        d = get!(person_decisions, h) do
            Dict(:has_lump => false, :did_annuitize_ls => false,
                 :has_dc_plan => false, :plans_annuitize => false)
        end
        if wpirls_col !== nothing && !ismissing(wpirls_col[i])
            v = numval(wpirls_col[i])
            if !ismissing(v) && v > 0
                d[:has_lump] = true
            end
        end
        if wpirpan_col !== nothing && !ismissing(wpirpan_col[i])
            v = numval(wpirpan_col[i])
            if !ismissing(v) && v == 1
                d[:did_annuitize_ls] = true
            end
        end
        if wpdcpan_col !== nothing && !ismissing(wpdcpan_col[i])
            v = numval(wpdcpan_col[i])
            if !ismissing(v) && (v == 0 || v == 1)
                d[:has_dc_plan] = true
                d[:plans_annuitize] = (v == 1)
            end
        end
    end
    return person_decisions
end

println("=" ^ 70)
println("  ELSA POST-FREEDOMS SUBGROUP ANALYSIS (Waves 8-11)")
println("=" ^ 70)
println()

# Pool across waves
all_records = []
for (w, pg_fn, ifs_fn, period) in WAVES
    pg_path = ensure_extracted(pg_fn)
    ifs_path = ensure_extracted(ifs_fn)
    pg_tbl = readstat(pg_path)
    ifs_tbl = readstat(ifs_fn isa String ? ifs_path : ifs_path)

    person_dec = build_person_disposition(pg_tbl)
    @printf("  Wave %d: %d unique persons in pension grid, %d in IFS-derived\n",
            w, length(person_dec),
            length(getproperty(ifs_tbl, propertynames(ifs_tbl)[1])))

    # Merge with demographics from IFS file
    ifs_idauniq = collect(getproperty(ifs_tbl, :idauniq))
    age_col   = collect(getproperty(ifs_tbl, :age))
    sex_col   = collect(getproperty(ifs_tbl, :sex))
    couple_col= collect(getproperty(ifs_tbl, :couple))
    qual3_col = hasproperty(ifs_tbl, :qual3) ? collect(getproperty(ifs_tbl, :qual3)) : nothing
    srh_col   = hasproperty(ifs_tbl, :srh3_hrs) ? collect(getproperty(ifs_tbl, :srh3_hrs)) : nothing

    n_ifs = length(ifs_idauniq)
    for i in 1:n_ifs
        ismissing(ifs_idauniq[i]) && continue
        h = numval(ifs_idauniq[i])
        ismissing(h) && continue
        haskey(person_dec, h) || continue
        d = person_dec[h]
        push!(all_records, (
            wave = w,
            idauniq = h,
            age = ismissing(age_col[i]) ? missing : numval(age_col[i]),
            sex = ismissing(sex_col[i]) ? missing : numval(sex_col[i]),
            couple = ismissing(couple_col[i]) ? missing : numval(couple_col[i]),
            qual3 = (qual3_col === nothing || ismissing(qual3_col[i])) ? missing : numval(qual3_col[i]),
            srh3 = (srh_col === nothing || ismissing(srh_col[i])) ? missing : numval(srh_col[i]),
            has_lump = d[:has_lump],
            did_annuitize_ls = d[:did_annuitize_ls],
            has_dc_plan = d[:has_dc_plan],
            plans_annuitize = d[:plans_annuitize],
        ))
    end
end
println()
@printf("Total person-wave records merged: %d\n", length(all_records))
println()

# ---------- Subgroup analysis: annuitization rate by age band ----------
function rate(records, mask_fn, outcome_fn, denom_fn)
    n_yes = 0; n_denom = 0
    for r in records
        mask_fn(r) || continue
        denom_fn(r) || continue
        if outcome_fn(r); n_yes += 1; end
        n_denom += 1
    end
    return n_yes, n_denom
end

# Two outcomes:
#   (1) Among lump-sum recipients: what fraction used the lump to annuitize?
#   (2) Among DC pot holders with plans recorded: what fraction plan to annuitize?

age_bands = [(50, 59), (60, 64), (65, 69), (70, 74), (75, 79), (80, 100)]
println("=" ^ 70)
println("  ANNUITIZATION RATE BY AGE BAND (post-freedoms, pooled W8-11)")
println("=" ^ 70)
@printf("\n  %-15s   %-22s   %-22s\n",
        "Age band", "Lump-sum annuitization", "DC-pot plan annuitize")
println("  " * "-" ^ 65)
for (lo, hi) in age_bands
    mask_age(r) = !ismissing(r.age) && r.age >= lo && r.age <= hi
    yes_l, n_l = rate(all_records, mask_age, r -> r.did_annuitize_ls, r -> r.has_lump)
    yes_p, n_p = rate(all_records, mask_age, r -> r.plans_annuitize,  r -> r.has_dc_plan)
    pct_l = n_l > 0 ? 100*yes_l/n_l : 0.0
    pct_p = n_p > 0 ? 100*yes_p/n_p : 0.0
    @printf("  %d-%-3d           %3d/%4d (%5.1f%%)         %3d/%4d (%5.1f%%)\n",
            lo, hi, yes_l, n_l, pct_l, yes_p, n_p, pct_p)
end

# By sex
println()
println("=" ^ 70)
println("  BY SEX")
println("=" ^ 70)
for (sex_code, sex_label) in [(1.0, "Male"), (2.0, "Female")]
    mask(r) = !ismissing(r.sex) && r.sex == sex_code
    yes_l, n_l = rate(all_records, mask, r -> r.did_annuitize_ls, r -> r.has_lump)
    yes_p, n_p = rate(all_records, mask, r -> r.plans_annuitize,  r -> r.has_dc_plan)
    pct_l = n_l > 0 ? 100*yes_l/n_l : 0.0
    pct_p = n_p > 0 ? 100*yes_p/n_p : 0.0
    @printf("  %-10s    LS: %3d/%4d (%5.1f%%)    Plan: %3d/%4d (%5.1f%%)\n",
            sex_label, yes_l, n_l, pct_l, yes_p, n_p, pct_p)
end

# By education (qual3: 1=high, 2=mid, 3=low)
println()
println("=" ^ 70)
println("  BY EDUCATION (qual3: 1=high, 2=mid, 3=low)")
println("=" ^ 70)
for (q, lbl) in [(1.0, "High"), (2.0, "Mid"), (3.0, "Low")]
    mask(r) = !ismissing(r.qual3) && r.qual3 == q
    yes_l, n_l = rate(all_records, mask, r -> r.did_annuitize_ls, r -> r.has_lump)
    yes_p, n_p = rate(all_records, mask, r -> r.plans_annuitize,  r -> r.has_dc_plan)
    pct_l = n_l > 0 ? 100*yes_l/n_l : 0.0
    pct_p = n_p > 0 ? 100*yes_p/n_p : 0.0
    @printf("  %-10s    LS: %3d/%4d (%5.1f%%)    Plan: %3d/%4d (%5.1f%%)\n",
            lbl, yes_l, n_l, pct_l, yes_p, n_p, pct_p)
end

# By self-rated health (srh3: 1=excellent/v.good/good, 2=fair, 3=poor)
println()
println("=" ^ 70)
println("  BY SELF-RATED HEALTH (HRS form, 3-way)")
println("=" ^ 70)
for (h, lbl) in [(1.0, "Good"), (2.0, "Fair"), (3.0, "Poor")]
    mask(r) = !ismissing(r.srh3) && r.srh3 == h
    yes_l, n_l = rate(all_records, mask, r -> r.did_annuitize_ls, r -> r.has_lump)
    yes_p, n_p = rate(all_records, mask, r -> r.plans_annuitize,  r -> r.has_dc_plan)
    pct_l = n_l > 0 ? 100*yes_l/n_l : 0.0
    pct_p = n_p > 0 ? 100*yes_p/n_p : 0.0
    @printf("  %-10s    LS: %3d/%4d (%5.1f%%)    Plan: %3d/%4d (%5.1f%%)\n",
            lbl, yes_l, n_l, pct_l, yes_p, n_p, pct_p)
end

# Save subgroup CSV
out_path = joinpath(PROJ, "data", "processed", "elsa_disposition_subgroups.csv")
mkpath(dirname(out_path))
open(out_path, "w") do f
    println(f, "subgroup,bucket,outcome,n_yes,n_denom,pct")
    function write_subgroup(subgroup_name, items, mask_fn_factory)
        for (key, lbl) in items
            mask = mask_fn_factory(key)
            yes_l, n_l = rate(all_records, mask, r -> r.did_annuitize_ls, r -> r.has_lump)
            yes_p, n_p = rate(all_records, mask, r -> r.plans_annuitize,  r -> r.has_dc_plan)
            @printf(f, "%s,%s,lump_sum,%d,%d,%.4f\n",
                    subgroup_name, lbl, yes_l, n_l, n_l > 0 ? 100*yes_l/n_l : 0.0)
            @printf(f, "%s,%s,dc_plan,%d,%d,%.4f\n",
                    subgroup_name, lbl, yes_p, n_p, n_p > 0 ? 100*yes_p/n_p : 0.0)
        end
    end
    write_subgroup("age", [((lo, hi), "$lo-$hi") for (lo, hi) in age_bands],
                   k -> r -> !ismissing(r.age) && r.age >= k[1] && r.age <= k[2])
    write_subgroup("sex", [(1.0, "Male"), (2.0, "Female")],
                   k -> r -> !ismissing(r.sex) && r.sex == k)
    write_subgroup("education", [(1.0, "High"), (2.0, "Mid"), (3.0, "Low")],
                   k -> r -> !ismissing(r.qual3) && r.qual3 == k)
    write_subgroup("health", [(1.0, "Good"), (2.0, "Fair"), (3.0, "Poor")],
                   k -> r -> !ismissing(r.srh3) && r.srh3 == k)
end
println()
@printf("Saved: %s\n", out_path)
