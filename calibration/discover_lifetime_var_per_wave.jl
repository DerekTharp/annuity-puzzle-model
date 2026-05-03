# Identify the per-wave variable names for the "annuity continues for life"
# question across HRS fat files (waves 5-9).

using ReadStatTables
using Printf

waves = [(5, "h00f1d"), (6, "h02f2c"), (7, "h04f1c"), (8, "h06f4b"), (9, "h08f3b")]

for (w, ff) in waves
    println("=== Wave $w ($ff) ===")
    path = joinpath(@__DIR__, "..", "data", "raw", "HRS", "HRS Fat Files",
                     "$(ff)_STATA", "$(ff).dta")
    tbl = readstat(path)
    mtd = colmetadata(tbl)
    hits = String[]
    for sym in propertynames(tbl)
        lbl = lowercase(String(get(mtd[sym], :label, "")))
        if occursin("continue for life", lbl) && occursin("annuit", lbl)
            label_str = get(mtd[sym], :label, "")
            push!(hits, "$sym  =>  $label_str")
        end
    end
    if isempty(hits)
        for sym in propertynames(tbl)
            lbl = lowercase(String(get(mtd[sym], :label, "")))
            if occursin("continue", lbl) && occursin("annuit", lbl)
                label_str = get(mtd[sym], :label, "")
                push!(hits, "$sym  =>  $label_str")
            end
        end
    end
    for h in hits[1:min(8, length(hits))]
        println("  ", h)
    end
    isempty(hits) && println("  (no \"continue for life\" annuity variable found)")

    # Also report the gate question (R or sp income from annuities)
    gate = String[]
    for sym in propertynames(tbl)
        lbl = lowercase(String(get(mtd[sym], :label, "")))
        if (occursin("income from annuit", lbl) || occursin("inc from annuit", lbl)) &&
           occursin("r ", lbl)
            label_str = get(mtd[sym], :label, "")
            push!(gate, "$sym  =>  $label_str")
        end
    end
    println("  (gate candidates):")
    for g in gate[1:min(4, length(gate))]
        println("    ", g)
    end
    println()
end
