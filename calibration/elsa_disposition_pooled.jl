# Pool ELSA waves 8-11 pension grid disposition data to compute the
# post-2015-freedoms voluntary annuitization rate.
#
# Reads from the user's _Datasets ELSA archive at:
#   /Users/derektharp/Documents/_Datasets/ELSA (English Longitudinal Study of Aging)
#
# Per-contract per-respondent records. Disposition variables (post-2015 only):
#   wpirpan: lump sum used to purchase annuity / regular income (1=yes/0=no)
#   wpirpsv: lump sum saved (cash ISA/bank)
#   wpirpiv: lump sum invested (investment ISA)
#   wpirpla: lump sum used to buy property
#   wpirpdb: lump sum used to pay off debts
#   wpirpsp: lump sum spent
#   wpirpfr: lump sum given to family/friend
#   wpirp95: other
#   wpdcpan: forward-looking plan to annuitize remaining DC pot
#
# Pre-2015 baseline: ~100% annuitization (mandatory by UK regulation for
# DC pots above small commutable threshold). Post-2015 freedoms removed
# the requirement; this script computes the resulting rate at the
# individual level.

using ReadStatTables
using Printf
using Statistics

const PROJ = joinpath(@__DIR__, "..")

# ELSA archive location. Configurable via ANNUITY_ELSA_ARCHIVE env var.
# Falls back to (1) project-local data/raw/ELSA, then (2) the author's
# personal _Datasets folder for backward compatibility.
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

# Wave files inside the zip. The script unzips on first use.
const WAVES = [
    (8,  "wave_8_elsa_pensiongrid_eul_v1.dta",  "2016-17"),
    (9,  "wave_9_elsa_pensiongrid_eul_v3.dta",  "2018-19"),
    (10, "wave_10_elsa_pensiongrid_eul_v2.dta", "2021-22"),
    (11, "wave_11_elsa_pensiongrid_eul.dta",    "2023-24"),
]

const TMP_DIR = "/tmp/elsa_extract"

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

println("=" ^ 70)
println("  ELSA WAVES 8-11 POOLED DISPOSITION ANALYSIS")
println("  UK Post-2015 Pension Freedoms — Voluntary Annuitization Rate")
println("=" ^ 70)
println()

const DISPOSITIONS = [
    (:wpirpan, "annuity (lump sum)"),
    (:wpirpsv, "saved (cash ISA)"),
    (:wpirpiv, "invested (ISA)"),
    (:wpirpla, "bought property"),
    (:wpirpdb, "paid off debts"),
    (:wpirpsp, "spent it"),
    (:wpirpfr, "gave to family"),
    (:wpirp95, "other"),
    (:wpdcpan, "plan: annuitize remaining DC pot"),
]

# Per-wave counts
wave_results = []
for (w, fn, period) in WAVES
    path = ensure_extracted(fn)
    tbl = readstat(path)
    counts = Dict{Symbol, Tuple{Int, Int}}()
    for (var, _) in DISPOSITIONS
        if hasproperty(tbl, var)
            col = collect(getproperty(tbl, var))
            n_yes = count(x -> !ismissing(x) && numval(x) == 1, col)
            n_no  = count(x -> !ismissing(x) && numval(x) == 0, col)
            counts[var] = (n_yes, n_no)
        else
            counts[var] = (0, 0)
        end
    end
    push!(wave_results, (wave=w, period=period, n_records=length(getproperty(tbl, propertynames(tbl)[1])), counts=counts))
end

# Print per-wave + pooled
@printf("  %-30s", "Disposition")
for r in wave_results
    @printf("%-15s", "W$(r.wave)")
end
@printf("%-18s", "Pooled")
println()
println("  " * "-" ^ 95)

# Save data for CSV
csv_rows = []
for (var, label) in DISPOSITIONS
    @printf("  %-30s", label)
    pooled_yes = 0
    pooled_no = 0
    for r in wave_results
        n_yes, n_no = r.counts[var]
        pooled_yes += n_yes
        pooled_no += n_no
        denom = n_yes + n_no
        pct = denom > 0 ? 100*n_yes/denom : 0.0
        @printf("%-15s", @sprintf("%d/%d (%.1f%%)", n_yes, denom, pct))
    end
    pooled_denom = pooled_yes + pooled_no
    pct_pooled = pooled_denom > 0 ? 100*pooled_yes/pooled_denom : 0.0
    @printf("%-18s", @sprintf("%d/%d (%.1f%%)", pooled_yes, pooled_denom, pct_pooled))
    println()
    push!(csv_rows, (variable=string(var), label=label,
                     pooled_yes=pooled_yes, pooled_no=pooled_no,
                     pooled_pct=pct_pooled))
end

println()
println("=" ^ 70)
println("  HEADLINE")
println("=" ^ 70)
function pool_var(results, var)
    y, n = 0, 0
    for r in results
        yi, ni = r.counts[var]
        y += yi; n += ni
    end
    return y, n
end
ann_yes, ann_no   = pool_var(wave_results, :wpirpan)
plan_yes, plan_no = pool_var(wave_results, :wpdcpan)
ann_denom  = ann_yes + ann_no
plan_denom = plan_yes + plan_no
@printf("\n  Lump-sum disposition: %d annuitized of %d recipients (%.2f%%)\n",
        ann_yes, ann_denom, 100*ann_yes/max(ann_denom,1))
@printf("  Forward plan:         %d planning of %d DC pot holders (%.2f%%)\n",
        plan_yes, plan_denom, 100*plan_yes/max(plan_denom,1))
println()
@printf("  Pre-freedoms baseline: ~100%% (DC annuitization mandatory pre-April 2015)\n")
@printf("  Post-freedoms (ELSA microdata, waves 8-11, 2016-2024): %.2f%% (lump sum)\n",
        100*ann_yes/max(ann_denom,1))
@printf("  Implied behavioral elasticity: %.1f pp drop\n",
        100 - 100*ann_yes/max(ann_denom,1))
@printf("  ABI 2020 aggregate estimate:   75-87 pp drop\n")
println()

# Save CSV
out_path = joinpath(PROJ, "data", "processed", "elsa_disposition_pooled.csv")
mkpath(dirname(out_path))
open(out_path, "w") do f
    println(f, "variable,label,pooled_yes,pooled_no,pooled_pct")
    for row in csv_rows
        @printf(f, "%s,%s,%d,%d,%.4f\n",
                row.variable, replace(row.label, "," => ";"),
                row.pooled_yes, row.pooled_no, row.pooled_pct)
    end
end
@printf("\n  Saved: %s\n", out_path)
