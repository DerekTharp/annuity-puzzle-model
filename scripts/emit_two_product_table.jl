# Emit the two-product extension table (gradient + SS-cut incidence panels)
# from tables/csv/two_product_gradient.csv and two_product_ss_cut.csv.
#
# Output: tables/tex/two_product.tex (tab:two_product)
# Usage:  julia --project=. scripts/emit_two_product_table.jl

using Printf, DelimitedFiles

const ROOT = joinpath(@__DIR__, "..")

g_raw, g_hdr = readdlm(joinpath(ROOT, "tables", "csv", "two_product_gradient.csv"), ',', Any; header=true)
c_raw, c_hdr = readdlm(joinpath(ROOT, "tables", "csv", "two_product_ss_cut.csv"), ',', Any; header=true)
gc(name) = findfirst(==(name), vec(g_hdr))
cc(name) = findfirst(==(name), vec(c_hdr))

labels = Dict(1 => raw"$<$\$30k", 2 => raw"\$30--120k", 3 => raw"\$120--350k", 4 => raw"$>$\$350k")

tex = joinpath(ROOT, "tables", "tex", "two_product.tex")
open(tex, "w") do f
    println(f, raw"\begin{table}[htbp]")
    println(f, raw"\centering")
    println(f, raw"\caption{Two-Product Extension: Group-Annuity Access, the Wealth Gradient, and the Benefit-Cut Response}")
    println(f, raw"\label{tab:two_product}")
    println(f, raw"\begin{threeparttable}")
    println(f, raw"\begin{tabular}{lccccc}")
    println(f, raw"\toprule")
    println(f, raw"\multicolumn{6}{l}{\textit{Panel A: Baseline ownership by band (\%)}}" * "\\\\")
    println(f, "Band & Access & Retail & Group & Mixture & Observed " * "\\\\")
    println(f, raw"\midrule")
    for r in 1:size(g_raw, 1)
        b = Int(g_raw[r, 1]); b == 0 && continue
        @printf(f, "%s & %.0f\\%% & %.2f & %.2f & %.2f & %.2f \\\\\n", labels[b],
            Float64(g_raw[r, gc("access_pct")]), Float64(g_raw[r, gc("retail_pct")]),
            Float64(g_raw[r, gc("group_pct")]), Float64(g_raw[r, gc("mixture_pct")]),
            Float64(g_raw[r, gc("observed_lifetime_pct")]))
    end
    println(f, raw"\midrule")
    println(f, raw"\multicolumn{6}{l}{\textit{Panel B: 22\% Social Security cut (mixture, \%)}}" * "\\\\")
    println(f, "Band & & Baseline & Under cut & Response (pp) & Share " * "\\\\")
    println(f, raw"\midrule")
    for r in 1:size(c_raw, 1)
        b = Int(c_raw[r, 1])
        @printf(f, "%s & & %.2f & %.2f & %+.2f & %.0f\\%% \\\\\n", labels[b],
            Float64(c_raw[r, cc("mixture_base_pct")]), Float64(c_raw[r, cc("mixture_cut_pct")]),
            Float64(c_raw[r, cc("response_pp")]), Float64(c_raw[r, cc("response_share_pct")]))
    end
    println(f, raw"\bottomrule")
    println(f, raw"\end{tabular}")
    println(f, raw"\begin{tablenotes}")
    println(f, raw"\small")
    println(f, raw"\item Access is the fraction of each band with employer-pension linkage in the RAND HRS analysis sample (receipt of employer pension income), a coverage-calibrated proxy for access to institutionally priced annuitization; no ownership rate enters the calibration. Retail prices at MWR $= \pMwrBaseline$; the group product at MWR $= 0.95$ (TSP- and TIAA-class institutional pricing). Product choice is dominance-ordered, so band ownership is the access-probability mixture of the two single-product predictions. Observed: unweighted lifetime-contract (q286) rates, person-wave, restricted sample. Panel B applies the 22\% cut to the Social Security component only. A negative response is the income effect: the cut removes the income floor that made the group annuity rational for marginal lower-middle-band buyers.")
    println(f, raw"\end{tablenotes}")
    println(f, raw"\end{threeparttable}")
    println(f, raw"\end{table}")
end
println("LaTeX written: $tex")
