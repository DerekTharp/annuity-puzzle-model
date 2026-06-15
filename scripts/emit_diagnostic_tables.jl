# Emits the appendix grid-convergence and Euler-residual LaTeX tables from the
# diagnostic CSVs, so those tables are reproducible rather than hand-typed.
# Reads:  tables/csv/convergence_diagnostics.csv, tables/csv/euler_residuals.csv
# Writes: tables/tex/grid_convergence.tex, tables/tex/euler_residuals_table.tex

using DelimitedFiles, Printf

const CSV_DIR = joinpath(@__DIR__, "..", "tables", "csv")
const TEX_DIR = joinpath(@__DIR__, "..", "tables", "tex")
const ROW = "\\\\"   # LaTeX row terminator

read_csv(name) = readdlm(joinpath(CSV_DIR, name), ',', Any; header=true)
nl(io, s) = println(io, s * ROW)      # write a table row (content + \\)
raw_(io, s) = println(io, s)          # write a control line verbatim (no row end)

# Locate a convergence row by (category, specification substring) -> (ownership, mean_alpha).
function conv_row(rows, category, spec_substr)
    for r in eachrow(rows)
        if strip(string(r[1])) == category && occursin(spec_substr, string(r[2]))
            return Float64(r[3]), Float64(r[4])
        end
    end
    error("convergence row not found: $category / $spec_substr")
end

function emit_grid_convergence()
    rows, _ = read_csv("convergence_diagnostics.csv")
    g(spec) = conv_row(rows, "Grid (9-node)", spec)
    q(spec) = conv_row(rows, "Quadrature", spec)
    ref     = conv_row(rows, "Reference", "120x50")
    io = IOBuffer()
    raw_(io, raw"\begin{table}[htbp]")
    raw_(io, raw"\centering")
    raw_(io, raw"\caption{Grid and Quadrature Convergence (Mean-SS Diagnostic Exercise)}")
    raw_(io, raw"\label{tab:grid_convergence}")
    raw_(io, raw"\begin{threeparttable}")
    raw_(io, raw"\begin{tabular}{lcccc}")
    raw_(io, raw"\toprule")
    nl(io, raw"Specification & $n_W \times n_A$ & Nodes & Ownership (\%) & $\bar{\alpha}$ ")
    raw_(io, raw"\midrule")
    nl(io, raw"\multicolumn{5}{l}{\textit{Panel A: Grid convergence (9-node GH)}} ")
    for (lab, sz, spec) in [("Medium", raw"$60 \times 20$", "60x20"),
                            ("Production", raw"$80 \times 30$", "80x30"),
                            ("Fine", raw"$100 \times 40$", "100x40"),
                            ("Very fine", raw"$120 \times 50$", "120x50")]
        o, a = g(spec)
        if lab == "Production"
            nl(io, @sprintf("\\textbf{%s} & \\textbf{%s} & \\textbf{9} & \\textbf{%.2f} & \\textbf{%.4f} ", lab, sz, o, a))
        else
            nl(io, @sprintf("%s & %s & 9 & %.2f & %.4f ", lab, sz, o, a))
        end
    end
    raw_(io, raw"\midrule")
    nl(io, raw"\multicolumn{5}{l}{\textit{Panel B: Quadrature convergence ($80 \times 30$ grid)}} ")
    for n in [3, 5, 7, 9, 11, 13, 15]
        o, a = q("n_quad=$n")
        if n == 9
            nl(io, @sprintf(" & \$80 \\times 30\$ & \\textbf{9} & \\textbf{%.2f} & \\textbf{%.4f} ", o, a))
        else
            nl(io, @sprintf(" & \$80 \\times 30\$ & %d & %.2f & %.4f ", n, o, a))
        end
    end
    raw_(io, raw"\midrule")
    nl(io, raw"\multicolumn{5}{l}{\textit{Panel C: Reference}} ")
    nl(io, @sprintf(" & \$120 \\times 50\$ & 11 & %.2f & %.4f ", ref[1], ref[2]))
    raw_(io, raw"\bottomrule")
    raw_(io, raw"\end{tabular}")
    raw_(io, raw"\begin{tablenotes}")
    raw_(io, raw"\small")
    raw_(io, raw"\item All specifications use baseline parameters ($\gamma = \pGamma$, DFJ bequests, MWR $= \pMwrBaseline$, $\pi = \pInflation$, $\psi = \pPessimism$) with mean Social Security. $n_\alpha = \pNAlpha$ throughout.")
    raw_(io, raw"\end{tablenotes}")
    raw_(io, raw"\end{threeparttable}")
    raw_(io, raw"\end{table}")
    write(joinpath(TEX_DIR, "grid_convergence.tex"), String(take!(io)))
    println("Wrote tables/tex/grid_convergence.tex")
end

# Locate an Euler row by exact specification label -> (mean, median, pct1, pct5).
function euler_row(rows, label)
    for r in eachrow(rows)
        if strip(string(r[1])) == label
            return Float64(r[3]), Float64(r[4]), Float64(r[5]), Float64(r[6])
        end
    end
    error("euler row not found: $label")
end

function emit_euler_table()
    rows, _ = read_csv("euler_residuals.csv")
    io = IOBuffer()
    raw_(io, raw"\begin{table}[htbp]")
    raw_(io, raw"\centering")
    raw_(io, raw"\caption{Euler Equation Residuals}")
    raw_(io, raw"\label{tab:euler}")
    raw_(io, raw"\begin{threeparttable}")
    raw_(io, raw"\begin{tabular}{lcccc}")
    raw_(io, raw"\toprule")
    nl(io, raw"Specification & Mean & Median & \% ${>} 1\%$ & \% ${>} 5\%$ ")
    raw_(io, raw"\midrule")
    nl(io, raw"\multicolumn{5}{l}{\textit{Grid convergence (9-node GH)}} ")
    for (disp, lab) in [(raw"$40 \times 15$", "Grid 40x15 (9-node)"),
                        (raw"$60 \times 20$", "Grid 60x20 (9-node)"),
                        (raw"$80 \times 30$ (production)", "Baseline 80x30 (9-node)"),
                        (raw"$100 \times 40$", "Grid 100x40 (9-node)")]
        m, md, p1, p5 = euler_row(rows, lab)
        nl(io, @sprintf("%s & %.3f & %.3f & %.1f & %.1f ", disp, m, md, p1, p5))
    end
    raw_(io, raw"\midrule")
    nl(io, raw"\multicolumn{5}{l}{\textit{Quadrature sensitivity ($80 \times 30$ grid)}} ")
    for (disp, lab) in [("5-node GH", "80x30 5-node GH"),
                        ("7-node GH", "80x30 7-node GH"),
                        ("9-node GH", "Baseline 80x30 (9-node)"),
                        ("11-node GH", "80x30 11-node GH")]
        m, md, p1, p5 = euler_row(rows, lab)
        nl(io, @sprintf("%s & %.3f & %.3f & %.1f & %.1f ", disp, m, md, p1, p5))
    end
    raw_(io, raw"\bottomrule")
    raw_(io, raw"\end{tabular}")
    raw_(io, raw"\begin{tablenotes}")
    raw_(io, raw"\small")
    raw_(io, raw"\item Normalized Euler residual $= |u'(c^*) - \text{RHS}| / |u'(c^*)|$, computed at all interior grid points (corner solutions excluded). Marginal value of next-period wealth computed by central finite differences ($\Delta W = \$100$) on the piecewise-linear value function interpolant.")
    raw_(io, raw"\end{tablenotes}")
    raw_(io, raw"\end{threeparttable}")
    raw_(io, raw"\end{table}")
    write(joinpath(TEX_DIR, "euler_residuals_table.tex"), String(take!(io)))
    println("Wrote tables/tex/euler_residuals_table.tex")
end

emit_grid_convergence()
emit_euler_table()
