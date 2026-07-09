# Pipeline-level validation gates. Catches the "stale artifact drift"
# pattern where manuscript and code fall out of sync as the model evolves.
#
# Four gates:
#
#   1. Manifest gate: every \input{...tex/X.tex} reference in main.tex,
#      appendix.tex, and cover_letter.tex must appear in run_all.jl's
#      expected_tex list. Catches the failure mode where a new manuscript
#      \input is added but the validation gate isn't updated.
#
#   2. Freshness gate: every .tex file the manuscript inputs must be at
#      least as new as paper/numbers.tex. If a downstream stage changed
#      a CSV but the table generator wasn't re-run, this catches it.
#
#   3. Hardcode-stale-numbers gate: greps the manuscript and code surface
#      for known stale literals (old observed-rate placeholder, old MWR
#      labels, old title strings, etc.). Maintains a small allowlist of
#      legitimate occurrences (e.g., quoted historical references).
#
#   4. Macro-definedness gate: every project-pattern macro the manuscript
#      uses (\ownX, \shapX, \cevX, \mcX, \wtpX, \hrsX, \pX) must be defined
#      in the regenerated numbers.tex. Catches the failure mode where a
#      macro emitter is deleted from export_manuscript_numbers.jl while
#      prose still references it — the build then breaks only at LaTeX
#      compile time, which the pipeline never reaches.
#
# Usage:
#   julia --project=. scripts/validate_pipeline.jl
#
# Returns nonzero exit if any gate fails. Intended to run as the final
# stage of run_all.jl after numbers.tex is generated.

using Printf

const PROJECT_DIR = abspath(joinpath(@__DIR__, ".."))
const PAPER_DIR   = joinpath(PROJECT_DIR, "paper")
const TEX_DIR     = joinpath(PROJECT_DIR, "tables", "tex")
const NUMBERS_TEX = joinpath(PAPER_DIR, "numbers.tex")
const MANUSCRIPT_FILES = ["main.tex", "appendix.tex", "cover_letter.tex"]

# Keep this list in sync with the expected_tex list in run_all.jl.
# (A future architectural improvement would have run_all.jl call this
# script with the list passed in, but for now we duplicate.)
const EXPECTED_TEX_FILES = Set([
    "band_value_destruction.tex",
    "bequest_recalibration.tex",
    "cev_counterfactuals.tex",
    "dia_comparison.tex",
    "empirical_gradients_logit.tex",
    "euler_residuals_table.tex",
    "extension_path.tex",
    "gate_robustness.tex",
    "grid_convergence.tex",
    "implied_gamma.tex",
    "model_vs_data_band.tex",
    "two_product.tex",
    "moment_validation.tex",
    "monte_carlo_summary.tex",
    "pairwise_interactions.tex",
    "partition_robustness.tex",
    "pashchenko_comparison.tex",
    "retention_rates.tex",
    "robustness_gamma_inflation.tex",
    "shapley_exact.tex",
    "shapley_nine.tex",
    "shapley_psi981.tex",
    "ss_cut_robustness.tex",
    "welfare_cev_grid.tex",
    "welfare_counterfactuals.tex",
])

# Stale-number patterns to catch. Each entry is (pattern, description).
# Allowlist patterns occur within explicit "ALLOWLIST:" lines or comments
# documenting historical context.
const STALE_PATTERNS = [  # ALLOWLIST: this file defines the patterns themselves
    (r"vline!\s*\(\s*\[\s*3\.6\s*\]"      , "Stale figure-1 hardcode (3.6%); should pull from numbers.tex"),
    (r"\bMWR\s*=\s*0\.82\b"               , "Stale MWR label (0.82); production is 0.87"),
    (r"\b89\.4\s*[mM]illion\b"            , "Arithmetic error: 89.4M operations (correct is ~8.94M)"),
    (r"\bDissolving\s+the\s+Annuity\s+Puzzle\b" , "Stale title; current is 'Private Annuities and Social Security Cuts: A Distributional Reframing of the Annuity Puzzle'"),
    (r"\bbundled\s+behavioral\s+wedge\b"  , "Stale framing; behavioral channels (SDU, PED) now structurally parameterized"),
    (r"\bForce\s+C\b"                     , "Stale force label; replaced by direct structural channels"),
    (r"\bOption\s+1\s+(?:a-strict|bundled)" , "Stale identification framing"),
    (r"calibrate_psi_chalmers_reuter"      , "Reference to archived calibration script"),  # ALLOWLIST: pattern definition
    (r"psi_(?:calibration|estimation)\.(?:toml|json)" , "Reference to archived psi calibration artifact"),
    (r"LAMBDA_W\s*=\s*(?:0\.85|1\.0)\b"    , "Stale LAMBDA_W value; production is 0.625"),
]

# Files exempt from the hardcode scan (acceptable contexts: companion
# survey paper, archive, dependencies).
const HARDCODE_EXEMPT_DIRS = [
    joinpath(PROJECT_DIR, "archive"),
    joinpath(PROJECT_DIR, "Gemini_review"),
    joinpath(PROJECT_DIR, "review_reports"),
    joinpath(PROJECT_DIR, "review_reports_channels"),
    joinpath(PROJECT_DIR, "review_reports_citations"),
    joinpath(PROJECT_DIR, "review_reports_code"),
    joinpath(PROJECT_DIR, "review_reports_jpube_refresh"),
    joinpath(PROJECT_DIR, "review_reports_ssm"),
    joinpath(PROJECT_DIR, "docs"),  # companion survey paper
    joinpath(PROJECT_DIR, ".git"),
    joinpath(PROJECT_DIR, ".claude"),
]

"""
Recursively scan a directory for files matching a pattern, excluding
HARDCODE_EXEMPT_DIRS.
"""
function scan_files(rootdir::String, ext_pattern::Regex)
    paths = String[]
    for (root, dirs, files) in walkdir(rootdir)
        # Skip exempt directories
        any(occursin(exempt, root) for exempt in HARDCODE_EXEMPT_DIRS) && continue
        for f in files
            if occursin(ext_pattern, f)
                push!(paths, joinpath(root, f))
            end
        end
    end
    return paths
end

"""
Gate 1: every \\input{tables/tex/X.tex} in the manuscript files must be
in EXPECTED_TEX_FILES.
"""
function gate_manifest()
    referenced = Set{String}()
    for fname in MANUSCRIPT_FILES
        path = joinpath(PAPER_DIR, fname)
        isfile(path) || continue
        for line in eachline(path)
            for m in eachmatch(r"\\input\{[^\}]*?tables/tex/([^\}]+\.tex)\}", line)
                push!(referenced, m.captures[1])
            end
        end
    end

    missing_in_expected = setdiff(referenced, EXPECTED_TEX_FILES)
    extra_in_expected   = setdiff(EXPECTED_TEX_FILES, referenced)

    fail = false
    if !isempty(missing_in_expected)
        println("\n[GATE 1: MANIFEST] FAIL")
        println("  Manuscript inputs the following .tex files that are NOT")
        println("  in run_all.jl's expected_tex validation list:")
        for f in sort(collect(missing_in_expected))
            println("    - $f")
        end
        println("  Add these to expected_tex (and EXPECTED_TEX_FILES in this script).")
        fail = true
    end
    if !isempty(extra_in_expected)
        println("\n[GATE 1: MANIFEST] WARNING")
        println("  expected_tex lists files that the manuscript does NOT input:")
        for f in sort(collect(extra_in_expected))
            println("    - $f")
        end
        println("  Either remove from expected_tex or add the \\input in the manuscript.")
        # Warning, not failure — extra entries are wasteful but not broken.
    end
    fail || println("[GATE 1: MANIFEST] OK ($(length(referenced)) inputs match expected_tex)")
    return !fail
end

"""
Gate 2: tables consumed by the manuscript must have been generated within
the current pipeline run. `paper/numbers.tex` is the LAST artifact written
by a clean run (Stage 15 = export_manuscript_numbers.jl, after every
table-generating stage), so in a healthy run every table .tex will be
slightly OLDER than numbers.tex but only by the time it took the
intervening stages to finish (up to the full run duration, ~7 hours).

The gate fires when a table is older than numbers.tex by MORE than
FRESHNESS_WINDOW_SECONDS, which signals one of two real bug patterns:
  - A downstream stage was re-run without re-generating the upstream
    tables (e.g., someone ran export_manuscript_numbers.jl by itself
    after editing one table, but never re-ran the script that produced
    the OTHER tables, so those other tables are now stale relative to
    the new numbers.tex).
  - A pull from AWS overwrote numbers.tex with a newer version but the
    table .tex files were left from an older bundle.

The window must exceed the full pipeline wall time, because the first
table generated (the sequential-decomposition table in Stage 2) is older
than the final numbers.tex by roughly the whole run duration. Production
wall time is ~7 hours on c7a.48xlarge after the 2026 stage additions
(the 2048-subset partition, the psi=0.981 Shapley, the extensive-margin
gate, and the band diagnostics), so the window is 18 hours: generous
enough to cover any single run with headroom, but still tight enough to
catch the day-old or week-old stale-table failure modes.
"""
const FRESHNESS_WINDOW_SECONDS = 18 * 60 * 60  # 18 hours (full run is ~7h)

function gate_freshness()
    isfile(NUMBERS_TEX) || begin
        println("\n[GATE 2: FRESHNESS] SKIP (numbers.tex does not exist yet)")
        return true
    end
    numbers_mtime = mtime(NUMBERS_TEX)

    stale = String[]
    for f in EXPECTED_TEX_FILES
        path = joinpath(TEX_DIR, f)
        isfile(path) || continue  # missing files caught by Gate 1
        age_diff = numbers_mtime - mtime(path)
        if age_diff > FRESHNESS_WINDOW_SECONDS
            push!(stale, "$(f) (older than numbers.tex by $(round(age_diff / 3600, digits=1)) hours)")
        end
    end

    if !isempty(stale)
        println("\n[GATE 2: FRESHNESS] FAIL")
        println("  The following manuscript-input .tex files are STALE relative to")
        println("  numbers.tex by more than $(FRESHNESS_WINDOW_SECONDS / 3600) hours,")
        println("  suggesting downstream stages were re-run without re-generating")
        println("  these tables, or a stale partial bundle was restored:")
        for s in stale
            println("    - $s")
        end
        return false
    end
    println("[GATE 2: FRESHNESS] OK ($(length(EXPECTED_TEX_FILES)) tables fresh within $(FRESHNESS_WINDOW_SECONDS / 3600)h of numbers.tex)")
    return true
end

"""
Gate 3: scan manuscript and source for known stale-number patterns.
"""
function gate_hardcoded_staleness()
    # Files in scope: paper/*.tex (excluding numbers.tex which is auto-generated),
    # scripts/*.jl, src/*.jl, test/*.jl, README.md
    scan_targets = String[]
    append!(scan_targets, scan_files(PAPER_DIR, r"\.tex$"))
    append!(scan_targets, scan_files(joinpath(PROJECT_DIR, "scripts"), r"\.jl$"))
    append!(scan_targets, scan_files(joinpath(PROJECT_DIR, "src"), r"\.jl$"))
    append!(scan_targets, scan_files(joinpath(PROJECT_DIR, "test"), r"\.jl$"))
    push!(scan_targets, joinpath(PROJECT_DIR, "README.md"))

    # Numbers.tex is the auto-generated source of truth — it can contain
    # any literal value without triggering this gate.
    filter!(p -> p != NUMBERS_TEX, scan_targets)

    findings = Tuple{String, Int, String, String}[]
    for path in scan_targets
        isfile(path) || continue
        for (line_num, line) in enumerate(eachline(path))
            # Skip lines that explicitly opt out via "ALLOWLIST:" comment marker.
            occursin(r"ALLOWLIST:"i, line) && continue
            for (pat, desc) in STALE_PATTERNS
                if occursin(pat, line)
                    rel = relpath(path, PROJECT_DIR)
                    push!(findings, (rel, line_num, desc, strip(line)))
                end
            end
        end
    end

    if !isempty(findings)
        println("\n[GATE 3: HARDCODED STALENESS] FAIL ($(length(findings)) match(es))")
        println("  Found hardcoded stale references. Either update them, or annotate")
        println("  the line with `# ALLOWLIST: <reason>` if the occurrence is intentional.")
        for (path, lnum, desc, line) in findings
            @printf("\n  %s:%d  -- %s\n    > %s\n", path, lnum, desc, line[1:min(120, length(line))])
        end
        return false
    end
    println("[GATE 3: HARDCODED STALENESS] OK (no matches in $(length(scan_targets)) files)")
    return true
end

"""
Gate 4: every project-pattern macro used in the manuscript must be defined
in numbers.tex. Project macros follow the naming convention
\\<prefix><UpperCamel> with prefix in {own, shap, cev, mc, wtp, hrs, p};
standard LaTeX commands are all-lowercase and never match.

Set ANNUITY_ALLOW_ORPHANS=1 to downgrade to a warning (intended ONLY for
runs before a planned prose surgery that will remove the orphaned usages).
"""
function gate_macro_definedness()
    isfile(NUMBERS_TEX) || begin
        println("\n[GATE 4: MACRO DEFINEDNESS] SKIP (numbers.tex does not exist yet)")
        return true
    end

    # Definition sites: numbers.tex (the generated source of truth) plus any
    # \providecommand fallbacks the manuscript files declare locally. Local
    # fallbacks keep the build alive, so they are not build-breakage orphans —
    # but their VALUES can go stale; that is Gate 3 / prose-surgery territory.
    defined = Set{String}()
    def_sources = vcat([NUMBERS_TEX],
                       [joinpath(PAPER_DIR, f) for f in MANUSCRIPT_FILES])
    for src in def_sources
        isfile(src) || continue
        for line in eachline(src)
            for m in eachmatch(r"\\(?:provide|new|renew)command\{?\\([A-Za-z]+)\}?", line)
                push!(defined, m.captures[1])
            end
        end
    end

    proj_pat = r"\\((?:own|shap|cev|mc|wtp|hrs|p)[A-Z][A-Za-z]*)"
    orphans = Tuple{String, Int, String}[]
    for fname in MANUSCRIPT_FILES
        path = joinpath(PAPER_DIR, fname)
        isfile(path) || continue
        for (lnum, line) in enumerate(eachline(path))
            # Strip LaTeX comments (unescaped % to end of line).
            stripped = replace(line, r"(?<!\\)%.*$" => "")
            for m in eachmatch(proj_pat, stripped)
                name = m.captures[1]
                name in defined || push!(orphans, (fname, lnum, name))
            end
        end
    end

    if !isempty(orphans)
        allow = get(ENV, "ANNUITY_ALLOW_ORPHANS", "0") == "1"
        verdict = allow ? "WARNING (ANNUITY_ALLOW_ORPHANS=1)" : "FAIL"
        println("\n[GATE 4: MACRO DEFINEDNESS] $verdict ($(length(orphans)) orphaned usage(s))")
        println("  The manuscript uses macros that numbers.tex no longer defines;")
        println("  the LaTeX build would break. Distinct orphaned macros:")
        for name in sort(unique(o[3] for o in orphans))
            uses = [o for o in orphans if o[3] == name]
            locs = join(["$(u[1]):$(u[2])" for u in uses[1:min(3, length(uses))]], ", ")
            extra = length(uses) > 3 ? " (+$(length(uses) - 3) more)" : ""
            println("    \\$name  — $locs$extra")
        end
        return allow
    end
    println("[GATE 4: MACRO DEFINEDNESS] OK ($(length(defined)) defined; no orphans)")
    return true
end

"""
Gate 4b: no project-pattern macro may rely on a hardcoded \\providecommand
literal fallback that numbers.tex does not also define. Fallbacks that ALIAS
another macro (value begins with a backslash) or are [pending] placeholders are
allowed; a hardcoded numeric literal that is never regenerated from config/CSVs
is the pChiLTC=0.7 drift failure mode (the manuscript showed 0.7 while the
pipeline ran 0.49) and is rejected here.
"""
function gate_no_fallback_only_literals()
    isfile(NUMBERS_TEX) || begin
        println("\n[GATE 4b: FALLBACK-ONLY LITERALS] SKIP (numbers.tex absent)")
        return true
    end
    numbers_defined = Set{String}()
    for line in eachline(NUMBERS_TEX)
        for m in eachmatch(r"\\(?:new|renew)command\{?\\([A-Za-z]+)\}?", line)
            push!(numbers_defined, m.captures[1])
        end
    end
    proj = r"^(?:own|shap|cev|mc|wtp|hrs|p)[A-Z]"
    offenders = Tuple{String, Int, String, String}[]
    for fname in MANUSCRIPT_FILES
        path = joinpath(PAPER_DIR, fname)
        isfile(path) || continue
        for (lnum, line) in enumerate(eachline(path))
            for m in eachmatch(r"\\providecommand\{?\\([A-Za-z]+)\}?\{([^}]*)\}", line)
                name, val = m.captures[1], m.captures[2]
                occursin(proj, name) || continue
                name in numbers_defined && continue      # generated source of truth — fine
                startswith(strip(val), "\\") && continue  # alias to another macro — fine
                strip(val) == "[pending]" && continue     # placeholder — fine
                occursin(r"\d", val) || continue          # only hardcoded numeric literals
                push!(offenders, (fname, lnum, name, val))
            end
        end
    end
    if !isempty(offenders)
        println("\n[GATE 4b: FALLBACK-ONLY LITERALS] FAIL ($(length(offenders)) macro(s))")
        println("  These project macros carry a hardcoded \\providecommand literal that")
        println("  numbers.tex does not regenerate — the pChiLTC=0.7 drift failure mode.")
        println("  Emit them from scripts/export_manuscript_numbers.jl instead:")
        for (f, l, n, v) in offenders
            println("    \\$n = $v  ($f:$l)")
        end
        return false
    end
    println("[GATE 4b: FALLBACK-ONLY LITERALS] OK (no hardcoded-literal fallbacks)")
    return true
end

# ---------------------------------------------------------------------------
# Gate 2b: figures. Every \includegraphics target in the manuscript must exist
# on disk. Figure content is regenerated at run_all.jl Stage 14 from the same
# CSVs the tables draw on; this gate catches a missing or renamed figure file
# (which otherwise surfaces only at LaTeX compile time) and reports figure age
# relative to the newest table CSV for transparency.
# ---------------------------------------------------------------------------
function gate_figures()
    missing_figs = String[]
    figs = String[]
    for mf in MANUSCRIPT_FILES
        path = joinpath(PAPER_DIR, mf)
        isfile(path) || continue
        for m in eachmatch(r"\\includegraphics(?:\[[^\]]*\])?\{([^}]*)\}", read(path, String))
            ref = m.captures[1]
            (endswith(ref, ".pdf") || endswith(ref, ".png")) || (ref *= ".pdf")
            push!(figs, ref)
            isfile(normpath(joinpath(PAPER_DIR, ref))) || push!(missing_figs, ref)
        end
    end
    if !isempty(missing_figs)
        println("\n[GATE 2b: FIGURES] FAIL ($(length(unique(missing_figs))) missing)")
        println("  The manuscript \\includegraphics these files, which do not exist:")
        for f in unique(missing_figs)
            println("    - $f")
        end
        println("  Run scripts/generate_figures.jl (run_all.jl Stage 14).")
        return false
    end
    csv_dir = joinpath(PROJECT_DIR, "tables", "csv")
    note = ""
    if isdir(csv_dir) && !isempty(figs)
        csvs = filter(f -> endswith(f, ".csv"), readdir(csv_dir; join=true))
        if !isempty(csvs)
            newest_csv = maximum(mtime, csvs)
            oldest_fig = minimum(f -> mtime(normpath(joinpath(PAPER_DIR, f))), unique(figs))
            oldest_fig < newest_csv && (note = "; note: a figure predates the newest table CSV — confirm figures were regenerated on the production run")
        end
    end
    println("[GATE 2b: FIGURES] OK ($(length(unique(figs))) figures present$note)")
    return true
end

# ---------------------------------------------------------------------------
# Main
# ---------------------------------------------------------------------------

println("=" ^ 70)
println("  PIPELINE VALIDATION GATES")
println("=" ^ 70)

ok1 = gate_manifest()
ok2 = gate_freshness()
ok2b = gate_figures()
ok3 = gate_hardcoded_staleness()
ok4 = gate_macro_definedness()
ok4b = gate_no_fallback_only_literals()
ok3 = ok3 && ok4 && ok4b

if !(ok1 && ok2 && ok2b && ok3)
    println("\n" * "=" ^ 70)
    println("  PIPELINE VALIDATION: FAIL")
    println("=" ^ 70)
    exit(1)
else
    println("\n" * "=" ^ 70)
    println("  PIPELINE VALIDATION: OK")
    println("=" ^ 70)
end
