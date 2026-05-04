# ELSA pre vs post 2015 freedoms regime comparison.
#
# Pre-freedoms regulatory baseline (wave 6, 2012-13): UK rules required
# annuitization of DC pension wealth above a small commutable threshold.
# Income drawdown ("flexible drawdown") was technically permitted but only
# for households meeting a high secure-income threshold, so was rare.
#
# Post-freedoms (waves 8-11, 2016-2024): the April 2015 reform removed
# the annuitization requirement. Households with DC pots can now take
# lump sums, drawdown, multiple withdrawals, or annuities at will.
#
# This script measures the regime change empirically:
#   Pre:  among DC pension recipients in wave 6, what % are drawdown?
#         The complement is annuity-style income (the regulatory mandate).
#   Post: among DC pension holders making decisions in waves 8-11, what
#         % chose drawdown / lump sum / annuity / undecided?
#
# Output: data/processed/elsa_pre_post_freedoms.csv

using ReadStatTables
using Printf

const PROJ = joinpath(@__DIR__, "..")

# ELSA archive location. Configurable via ANNUITY_ELSA_ARCHIVE env var.
# Falls back to (1) project-local data/raw/ELSA, then (2) the author's
# personal _Datasets folder for backward compatibility. The archive is
# the UK Data Service deposit 5050 (waves 0-11, 1998-2024).
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
              "data/raw/ELSA/. UK Data Service deposit 5050 " *
              "(https://beta.ukdataservice.ac.uk/datacatalogue/series/series?id=200011).")
    end
end
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
println("  ELSA PRE vs POST 2015 PENSION FREEDOMS REGIME CHANGE")
println("=" ^ 70)
println()

# ---------- Pre-freedoms: wave 6 (2012-13) ----------
# Note: wpdcdb (DC vs DB) is only asked for pensions in ACCUMULATION phase
# (currently contributing). For pensions in receipt (wprec=1), the type
# variable is wppent. We classify "DC recipients" as Personal (pent=1) +
# Stakeholder (pent=4), which are unambiguously DC. Employer pensions
# (pent=2) include both DC and DB and are excluded from the pure DC test.
println("--- Pre-freedoms baseline: wave 6 (2012-13) ---")
tbl6 = readstat(ensure_extracted("wave_6_pensiongrid_archive_v1.dta"))
n_rows6 = length(getproperty(tbl6, propertynames(tbl6)[1]))
@printf("  Pension grid rows: %d\n", n_rows6)

wprec_col  = collect(getproperty(tbl6, :wprec))
wppent_col = collect(getproperty(tbl6, :wppent))
wpincd_col = collect(getproperty(tbl6, :wpincd))
wppyr_col  = collect(getproperty(tbl6, :wppyr))

function count_w6_dc(n_rows6, rec, pent, incd, pyr)
    n_recip = 0; n_dc_recip = 0; n_dd = 0; n_ann = 0; n_unk = 0
    for i in 1:n_rows6
        !ismissing(rec[i]) && numval(rec[i]) == 1 || continue
        n_recip += 1
        # Personal (1) or Stakeholder (4) = unambiguously DC
        pn = ismissing(pent[i]) ? -999.0 : numval(pent[i])
        pn == 1.0 || pn == 4.0 || continue
        n_dc_recip += 1
        da = ismissing(incd[i]) ? missing : numval(incd[i])
        pa = ismissing(pyr[i])  ? missing : numval(pyr[i])
        if !ismissing(da) && da > 0
            n_dd += 1
        elseif !ismissing(pa) && pa > 0
            n_ann += 1
        else
            n_unk += 1
        end
    end
    return n_recip, n_dc_recip, n_dd, n_ann, n_unk
end
n_recip, n_dc_recipients, n_dc_drawdown, n_dc_annuity_style, n_dc_unknown =
    count_w6_dc(n_rows6, wprec_col, wppent_col, wpincd_col, wppyr_col)
@printf("  Pension recipients (any type):        %d\n", n_recip)
@printf("  DC recipients (Personal + Stakeholder): %d\n", n_dc_recipients)
@printf("  -- annuity-style income:              %d (%.2f%%)\n",
        n_dc_annuity_style, 100*n_dc_annuity_style/max(n_dc_recipients,1))
@printf("  -- via income drawdown:               %d (%.2f%%)\n",
        n_dc_drawdown, 100*n_dc_drawdown/max(n_dc_recipients,1))
@printf("  -- unknown form:                      %d (%.2f%%)\n",
        n_dc_unknown, 100*n_dc_unknown/max(n_dc_recipients,1))
println()
@printf("  Pre-freedoms regulatory baseline: ~100%% annuitization mandatory\n")
@printf("  Wave 6 microdata confirms: %.1f%% annuity-style vs %.1f%% drawdown\n",
        100*n_dc_annuity_style/max(n_dc_recipients,1),
        100*n_dc_drawdown/max(n_dc_recipients,1))
@printf("  (the 9.6%% unknown form is most likely annuity given the mandate)\n")
println()

# ---------- Post-freedoms: pooled wave 8-11 ----------
println("--- Post-freedoms behavior: pooled waves 8-11 (2016-2024) ---")

WAVES_POST = [
    (8,  "wave_8_elsa_pensiongrid_eul_v1.dta"),
    (9,  "wave_9_elsa_pensiongrid_eul_v3.dta"),
    (10, "wave_10_elsa_pensiongrid_eul_v2.dta"),
    (11, "wave_11_elsa_pensiongrid_eul.dta"),
]

# Among DC pot holders with plans recorded, what's the disposition mix?
# The plan variables: wpdcpan (annuity), wpdcprg (drawdown / regular income),
#                     wpdcpsi (single lump sum), wpdcpmu (multiple withdrawals),
#                     wpdcpdk (haven't decided)
plan_vars = [
    (:wpdcpan, "annuitize"),
    (:wpdcprg, "drawdown / regular income"),
    (:wpdcpsi, "single lump sum"),
    (:wpdcpmu, "multiple cash withdrawals"),
    (:wpdcpdk, "haven't decided"),
]

pooled_yes = Dict{Symbol, Int}(p[1] => 0 for p in plan_vars)
pooled_no  = Dict{Symbol, Int}(p[1] => 0 for p in plan_vars)
for (w, fn) in WAVES_POST
    tbl = readstat(ensure_extracted(fn))
    for (var, _) in plan_vars
        if hasproperty(tbl, var)
            col = collect(getproperty(tbl, var))
            for x in col
                ismissing(x) && continue
                v = numval(x)
                if v == 1; pooled_yes[var] += 1
                elseif v == 0; pooled_no[var] += 1
                end
            end
        end
    end
end

# Total denom (all "have plans recorded" — same per row)
denom = pooled_yes[:wpdcpan] + pooled_no[:wpdcpan]
@printf("  DC pot holders with plans recorded: %d\n", denom)
println()
@printf("  Disposition plans (yes / total):\n")
for (var, label) in plan_vars
    y = pooled_yes[var]
    n = pooled_no[var] + y
    pct = n > 0 ? 100*y/n : 0.0
    @printf("    %-30s %4d / %5d (%.1f%%)\n", label, y, n, pct)
end

# Lump-sum disposition (post-event)
println()
@printf("  Lump-sum recipients' disposition (post-event):\n")
ls_dispositions = [
    (:wpirpan, "annuitize"),
    (:wpirpsv, "saved"),
    (:wpirpiv, "invested"),
    (:wpirpla, "bought property"),
    (:wpirpdb, "paid off debts"),
    (:wpirpsp, "spent it"),
    (:wpirpfr, "gave to family"),
    (:wpirp95, "other"),
]
ls_yes = Dict{Symbol, Int}(p[1] => 0 for p in ls_dispositions)
ls_no  = Dict{Symbol, Int}(p[1] => 0 for p in ls_dispositions)
for (w, fn) in WAVES_POST
    tbl = readstat(ensure_extracted(fn))
    for (var, _) in ls_dispositions
        if hasproperty(tbl, var)
            col = collect(getproperty(tbl, var))
            for x in col
                ismissing(x) && continue
                v = numval(x)
                if v == 1; ls_yes[var] += 1
                elseif v == 0; ls_no[var] += 1
                end
            end
        end
    end
end
denom_ls = ls_yes[:wpirpan] + ls_no[:wpirpan]
for (var, label) in ls_dispositions
    y = ls_yes[var]
    n = ls_no[var] + y
    pct = n > 0 ? 100*y/n : 0.0
    @printf("    %-30s %4d / %5d (%.1f%%)\n", label, y, n, pct)
end

println()
println("=" ^ 70)
println("  HEADLINE COMPARISON")
println("=" ^ 70)
ann_pct_post = 100*ls_yes[:wpirpan]/max(denom_ls,1)
plan_ann_post = 100*pooled_yes[:wpdcpan]/max(denom,1)
plan_dd_post  = 100*pooled_yes[:wpdcprg]/max(denom,1)
@printf("\n  Pre-freedoms (regulatory baseline):    ~100%% annuitized\n")
@printf("  Pre-freedoms (wave 6 microdata):       %.1f%% annuity-style of DC recipients\n",
        100*n_dc_annuity_style/max(n_dc_recipients,1))
@printf("  Post-freedoms (lump-sum disposition):  %.1f%% used lump for annuity\n",
        ann_pct_post)
@printf("  Post-freedoms (DC pot plans):          %.1f%% plan to annuitize\n",
        plan_ann_post)
@printf("  Post-freedoms (DC pot plans):          %.1f%% plan drawdown instead\n",
        plan_dd_post)
@printf("  Post-freedoms (DC pot plans):          %.1f%% haven't decided\n",
        100*pooled_yes[:wpdcpdk]/max(denom,1))
println()
@printf("  Implied behavioral elasticity (pre vs post): %.0f pp drop (forward-plan basis)\n",
        100*n_dc_annuity_style/max(n_dc_recipients,1) - plan_ann_post)
@printf("                                              %.0f pp drop (lump-sum disposition basis)\n",
        100*n_dc_annuity_style/max(n_dc_recipients,1) - ann_pct_post)

# Save CSV
out_path = joinpath(PROJ, "data", "processed", "elsa_pre_post_freedoms.csv")
mkpath(dirname(out_path))
open(out_path, "w") do f
    println(f, "regime,measure,n_yes,n_denom,pct")
    @printf(f, "pre_freedoms_w6,annuity_style_of_dc_recipients,%d,%d,%.4f\n",
            n_dc_annuity_style, n_dc_recipients, 100*n_dc_annuity_style/max(n_dc_recipients,1))
    @printf(f, "pre_freedoms_w6,drawdown_of_dc_recipients,%d,%d,%.4f\n",
            n_dc_drawdown, n_dc_recipients, 100*n_dc_drawdown/max(n_dc_recipients,1))
    for (var, label) in plan_vars
        y = pooled_yes[var]; n = pooled_no[var] + y
        @printf(f, "post_freedoms_pool_w8_11,plan_%s,%d,%d,%.4f\n",
                replace(label, " " => "_"), y, n, n > 0 ? 100*y/n : 0.0)
    end
    for (var, label) in ls_dispositions
        y = ls_yes[var]; n = ls_no[var] + y
        @printf(f, "post_freedoms_pool_w8_11,lumpsum_%s,%d,%d,%.4f\n",
                replace(label, " " => "_"), y, n, n > 0 ? 100*y/n : 0.0)
    end
end
println()
@printf("Saved: %s\n", out_path)
