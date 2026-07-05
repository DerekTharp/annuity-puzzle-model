# Emit the value-destruction diagnostic table from the band diagnostic CSV.
# Reads tables/csv/band_value_destruction_diagnostic.csv (produced by
# scripts/run_band3_diagnostic.jl) and writes tables/tex/band_value_destruction.tex.
# Presentation is separated from the (expensive) computation so the table can be
# regenerated without re-solving the model.

using Printf, DelimitedFiles

const ROOT = joinpath(@__DIR__, "..")
csv_path = joinpath(ROOT, "tables", "csv", "band_value_destruction_diagnostic.csv")
isfile(csv_path) || error("Missing $csv_path; run scripts/run_band3_diagnostic.jl first")

raw, _ = readdlm(csv_path, ',', Any; header=true)  # config, band, own_if_costfree_pct, own_hard_pct
costfree = Dict{Tuple{String,Int},Float64}()
for r in 1:size(raw, 1)
    costfree[(strip(String(raw[r, 1])), Int(raw[r, 2]))] = Float64(raw[r, 3])
end

const FULL = "Full structural"
configs = unique(strip.(String.(raw[:, 1])))
others = filter(!=(FULL), configs)
sort!(others, by = c -> -get(costfree, (c, 3), 0.0))  # by band-3 zero-cost share, descending
ordered = [FULL; others]

label(c) = c == FULL ? FULL : replace(c, "- " => "\\quad less ")

tex_path = joinpath(ROOT, "tables", "tex", "band_value_destruction.tex")
open(tex_path, "w") do f
    println(f, raw"\begin{table}[htbp]")
    println(f, raw"\centering")
    println(f, raw"\caption{Value-destruction diagnostic: would-annuitize share at zero transaction cost, by wealth band}")
    println(f, raw"\label{tab:band_value_destruction}")
    println(f, raw"\begin{threeparttable}")
    println(f, raw"\begin{tabular}{lcc}")
    println(f, raw"\toprule")
    println(f, raw"Specification & Band 2 (\$30--120k) & Band 3 (\$120--350k) " * "\\\\")
    println(f, raw"\midrule")
    for c in ordered
        b2 = get(costfree, (c, 2), 0.0)
        b3 = get(costfree, (c, 3), 0.0)
        println(f, label(c) * " & " * @sprintf("%.1f", b2) * "\\% & " *
                   @sprintf("%.1f", b3) * "\\% \\\\")
    end
    println(f, raw"\bottomrule")
    println(f, raw"\end{tabular}")
    println(f, raw"\begin{tablenotes}")
    println(f, raw"\small")
    println(f, raw"\item Share of households in each band who would purchase the immediate annuity at a \emph{zero} transaction cost (indifference fixed cost $F^\star>0$), under the full structural model and under each one-channel-removed variant. Bands 2 and 3 are the interior bands where observed lifetime-annuity ownership most exceeds the model's zero prediction. A full-model entry near zero that jumps when a channel is removed identifies that channel as the one making annuitization value-destroying for the modal observed owner: in band 3 the removal of pricing loads moves the zero-cost share furthest, so the load, not the transaction cost, drives the predicted exclusion. Production grid.")
    println(f, raw"\end{tablenotes}")
    println(f, raw"\end{threeparttable}")
    println(f, raw"\end{table}")
end
println("  LaTeX written: $tex_path")
