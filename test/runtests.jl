# Unified test runner for AnnuityPuzzle
#
# Each test file includes the AnnuityPuzzle module independently,
# so they must run in separate Julia processes to avoid re-include conflicts.
#
# Usage: julia test/runtests.jl
#        julia test/runtests.jl test_utility   (run single suite)

using Printf

const TEST_DIR = @__DIR__
const PROJECT_DIR = dirname(TEST_DIR)

const TEST_FILES = [
    "test_utility.jl",
    "test_limiting_cases.jl",
    "test_lockwood.jl",
    "test_health.jl",
    "test_phase4.jl",
    "test_welfare.jl",
    "test_pashchenko_dia.jl",
    "test_10channel_smoke.jl",
    "test_age_invariance.jl",
    "test_manuscript_numbers.jl",
]

function run_test_file(filename::String)
    path = joinpath(TEST_DIR, filename)
    @printf("  %-30s", filename)
    t0 = time()
    proc = run(pipeline(`$(Base.julia_cmd()) --project=$PROJECT_DIR $path`,
                        stderr=stderr), wait=false)
    wait(proc)
    elapsed = time() - t0
    if proc.exitcode == 0
        @printf(" PASS  (%5.1fs)\n", elapsed)
        return true
    else
        @printf(" FAIL  (%5.1fs)\n", elapsed)
        return false
    end
end

function main()
    # Allow running a single test by name
    if length(ARGS) > 0
        filter_name = ARGS[1]
        files = filter(f -> occursin(filter_name, f), TEST_FILES)
        if isempty(files)
            println("No test file matching '$filter_name'")
            println("Available: ", join(TEST_FILES, ", "))
            exit(1)
        end
    else
        files = TEST_FILES
    end

    println("=" ^ 50)
    println("  AnnuityPuzzle Test Suite")
    println("=" ^ 50)
    println()

    results = Dict{String, Bool}()
    t_total = time()

    for f in files
        results[f] = run_test_file(f)
    end

    elapsed_total = time() - t_total
    n_pass = count(values(results))
    n_fail = length(results) - n_pass

    println()
    println("-" ^ 50)
    @printf("  %d/%d suites passed (%.1fs total)\n",
        n_pass, length(results), elapsed_total)

    if n_fail > 0
        println()
        println("  FAILED:")
        for (f, passed) in sort(collect(results), by=first)
            passed || println("    - $f")
        end
        println()
        exit(1)
    else
        println("  All tests passed.")
        println("-" ^ 50)
    end
end

main()
