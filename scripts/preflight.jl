# Pre-AWS preflight gate.
#
# Parse checks alone miss statements that parse but fail at lowering (e.g.
# a comma appended to an assignment: `x = f(y), z = w`). This gate LOWERS
# every top-level expression of every driver script referenced by
# run_all.jl inside a scratch module with the pipeline's macro providers
# loaded, and fails on any lowering error. It also statically requires
# that any script constructing production parameters (marked by setting
# hazard_mult from config) threads hazard_normalize alongside it.
#
# Usage: julia --project=. scripts/preflight.jl   (exit 0 = go)

using Distributed, Printf, DelimitedFiles

const ROOT = normpath(joinpath(@__DIR__, ".."))

# Smallest bracket group ((),{},[]) whose span contains byte position `pos`.
# Returns (open_index, close_index) as valid String indices, or nothing.
function enclosing_group(src::String, pos::Int)
    opens = ('(', '{', '[')
    closes = (')', '}', ']')
    i = pos
    depth = 0
    while i >= firstindex(src)
        c = src[i]
        if c in closes
            depth += 1
        elseif c in opens
            if depth == 0
                # Found the opening bracket; scan forward for its match.
                d = 0
                j = i
                while j <= lastindex(src)
                    cj = src[j]
                    if cj in opens
                        d += 1
                    elseif cj in closes
                        d -= 1
                        d == 0 && return (i, j)
                    end
                    j = nextind(src, j)
                end
                return nothing
            else
                depth -= 1
            end
        end
        i = prevind(src, i)
    end
    return nothing
end

# Drivers: every .jl the master pipeline references, plus calibration deps.
runall = read(joinpath(ROOT, "run_all.jl"), String)
drivers = String[]
for m in eachmatch(r"\"([A-Za-z0-9_]+\.jl)\"", runall)
    f = m.captures[1]
    f == "preflight.jl" && continue   # the gate must not scan its own regex literals
    for dir in ("scripts", "calibration", "test")
        path = joinpath(ROOT, dir, f)
        if isfile(path) && !(path in drivers)
            push!(drivers, path)
        end
    end
end
isempty(drivers) && error("preflight found no drivers in run_all.jl")

failures = String[]

# Scratch module with macro providers so @everywhere/@printf/etc. expand.
scratch = Module(:PreflightScratch)
Core.eval(scratch, :(using Distributed, Printf, DelimitedFiles, Test))

for path in drivers
    src = read(path, String)
    exprs = try
        Meta.parseall(src)
    catch err
        push!(failures, "$path: PARSE: $err")
        continue
    end
    for ex in exprs.args
        ex isa LineNumberNode && continue
        lowered = try
            Meta.lower(scratch, ex)
        catch err
            push!(failures, "$path: LOWERING THREW: $err")
            continue
        end
        if lowered isa Expr && lowered.head === :error
            push!(failures, "$path: LOWERING ERROR: $(lowered.args[1])")
        end
    end

    # Structural production-flag consistency: EVERY construction that sets
    # hazard_mult (a Dict entry `:hazard_mult => ...`, a NamedTuple or
    # ModelParams kwarg `hazard_mult=...`) must set hazard_normalize inside
    # the SAME bracket group. A file-wide text search is insufficient: a
    # script can mention hazard_normalize in one block and drop it in a
    # worker-local rebuild (the exact class that reached production).
    #
    # Allowlist: scripts that intentionally run the prior (male, unnormalized)
    # convention. They set hazard_normalize=false explicitly OR are legacy
    # replications that never touch the normalized path.
    base = basename(path)
    legacy = base in ("run_male_mortality_shapley.jl", "pashchenko_replication.jl",
                      "run_lockwood_replication.jl", "run_health_analysis.jl",
                      "recalibrate_bequests.jl")
    for m in eachmatch(r"(?::hazard_mult\s*=>|hazard_mult\s*=)", src)
        grp = enclosing_group(src, m.offset)
        grp === nothing && continue          # bare capture; the consuming bundle is checked
        inner = src[grp[1]:grp[2]]
        # Only enforce on a FULL parameter bundle (contains gamma). Partial
        # override dicts (`params=Dict(:hazard_mult => hm)`) legitimately
        # inherit hazard_normalize from the base they merge into.
        occursin(r"(?::gamma\s*=>|gamma\s*=)", inner) || continue
        has_norm = occursin(r"(?::hazard_normalize\s*=>|hazard_normalize\s*=)", inner)
        if !has_norm && !legacy
            ln = count(==('\n'), src[1:prevind(src, m.offset)]) + 1
            push!(failures, "$path:$ln sets hazard_mult in a full parameter bundle without hazard_normalize")
        end
    end
end

if isempty(failures)
    @printf("PREFLIGHT PASS: %d drivers lowered cleanly, flag-consistent.\n", length(drivers))
else
    println("PREFLIGHT FAIL (", length(failures), "):")
    foreach(f -> println("  ", f), failures)
    exit(1)
end
