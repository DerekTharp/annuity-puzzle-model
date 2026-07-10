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

# Drivers: every .jl the master pipeline references, plus calibration deps.
runall = read(joinpath(ROOT, "run_all.jl"), String)
drivers = String[]
for m in eachmatch(r"\"([A-Za-z0-9_]+\.jl)\"", runall)
    f = m.captures[1]
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

    # Static production-flag consistency: production drivers set hazard_mult
    # from config; they must thread hazard_normalize too. Legacy/replication
    # scripts that never reference HAZARD_MULT are exempt.
    uses_prod_hazard = occursin(r"hazard_mult\s*=\s*(Float64\.\()?(_?hm|_hazard_mult|hm|HAZARD_MULT)", src)
    if uses_prod_hazard && !occursin("hazard_normalize", src)
        push!(failures, "$path: sets production hazard_mult without hazard_normalize")
    end
end

if isempty(failures)
    @printf("PREFLIGHT PASS: %d drivers lowered cleanly, flag-consistent.\n", length(drivers))
else
    println("PREFLIGHT FAIL (", length(failures), "):")
    foreach(f -> println("  ", f), failures)
    exit(1)
end
