# Pipeline-level validation gates. Catches the "stale artifact drift"
# pattern where manuscript and code fall out of sync as the model evolves.
#
# Three gates:
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
    "bequest_recalibration.tex",
    "cev_counterfactuals.tex",
    "dia_comparison.tex",
    "extension_path.tex",
    "implied_gamma.tex",
    "moment_validation.tex",
    "monte_carlo_summary.tex",
    "pairwise_interactions.tex",
    "pashchenko_comparison.tex",
    "retention_rates.tex",
    "robustness_gamma_inflation.tex",
    "shapley_exact.tex",
    "ss_cut_robustness.tex",
    "welfare_cev_grid.tex",
    "welfare_counterfactuals.tex",
])

# Stale-number patterns to catch. Each entry is (pattern, description).
# Allowlist patterns occur within explicit "ALLOWLIST:" lines or comments
# documenting historical context.
const STALE_PATTERNS = [
    (r"vline!\s*\(\s*\[\s*3\.6\s*\]"      , "Stale figure-1 hardcode (3.6%); should pull from numbers.tex"),
    (r"\bMWR\s*=\s*0\.82\b"               , "Stale MWR label (0.82); production is 0.87 or 0.88"),
    (r"\b89\.4\s*[mM]illion\b"            , "Arithmetic error: 89.4M operations (correct is ~8.94M)"),
    (r"\bDissolving\s+the\s+Annuity\s+Puzzle\b" , "Stale title (Dissolving); current is Quantifying"),
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
Gate 2: every consumed .tex must be at least as new as numbers.tex.
"""
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
        if mtime(path) < numbers_mtime - 1.0  # 1-sec tolerance
            age_diff = numbers_mtime - mtime(path)
            push!(stale, "$(f) (older than numbers.tex by $(round(age_diff, digits=1))s)")
        end
    end

    if !isempty(stale)
        println("\n[GATE 2: FRESHNESS] FAIL")
        println("  The following manuscript-input .tex files are STALE relative to")
        println("  numbers.tex (suggesting downstream stages were re-run without")
        println("  re-generating these tables):")
        for s in stale
            println("    - $s")
        end
        return false
    end
    println("[GATE 2: FRESHNESS] OK ($(length(EXPECTED_TEX_FILES)) tables newer than numbers.tex)")
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

# ---------------------------------------------------------------------------
# Main
# ---------------------------------------------------------------------------

println("=" ^ 70)
println("  PIPELINE VALIDATION GATES")
println("=" ^ 70)

ok1 = gate_manifest()
ok2 = gate_freshness()
ok3 = gate_hardcoded_staleness()

if !(ok1 && ok2 && ok3)
    println("\n" * "=" ^ 70)
    println("  PIPELINE VALIDATION: FAIL")
    println("=" ^ 70)
    exit(1)
else
    println("\n" * "=" ^ 70)
    println("  PIPELINE VALIDATION: OK")
    println("=" ^ 70)
end
