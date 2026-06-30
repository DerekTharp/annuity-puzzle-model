# Emit the model-vs-data wealth-band ownership table.
#
# Joins observed lifetime-SPIA ownership by wealth band (with owner counts, for
# inference) to the model's band predictions (sharp-threshold and cost-smoothed),
# and reports three tests that discipline the comparison:
#   (1) Cochran-Armitage trend across the four ordered bands (is the observed
#       gradient real?);
#   (2) a pooled Wilson 95% CI for the three non-top bands (does observed
#       interior ownership exclude zero, where the single-product model predicts
#       none?);
#   (3) a Fisher exact test of the top two bands (is the apparent peak-then-dip
#       statistically distinguishable from monotonic?).
#
# Inputs:  data/processed/hrs_lifetime_ownership_by_band.csv (committed)
#          tables/csv/wealth_gradient_modeldata.csv (Stage 11f output)
# Output:  tables/tex/model_vs_data_band.tex

using Printf, DelimitedFiles, Distributions

const ROOT = joinpath(@__DIR__, "..")

hrs_raw, hrs_hdr = readdlm(joinpath(ROOT, "data", "processed",
    "hrs_lifetime_ownership_by_band.csv"), ',', Any; header=true)
# columns: band, band_label, n, n_lifetime, lifetime_unw_pct, lifetime_wtd_pct, iann_pct, anyc_pct
col(name) = findfirst(==(name), vec(hrs_hdr))
n_band   = Int.(hrs_raw[:, col("n")])
o_band   = Int.(hrs_raw[:, col("n_lifetime")])
hrs_pct  = Float64.(hrs_raw[:, col("lifetime_unw_pct")])

mod_raw, mod_hdr = readdlm(joinpath(ROOT, "tables", "csv",
    "wealth_gradient_modeldata.csv"), ',', Any; header=true)
mcol(name) = findfirst(==(name), vec(mod_hdr))
model_hard = Float64.(mod_raw[:, mcol("model_hard_pct")])
model_smth = Float64.(mod_raw[:, mcol("model_smoothed_pct")])

band_labels = ["\\\$0--30k", "\\\$30--120k", "\\\$120--350k", "Above \\\$350k"]

# --- (1) Cochran-Armitage trend test (scores 1..K) ---
function ca_trend(o::Vector{Int}, n::Vector{Int})
    t = Float64.(1:length(o))
    N = sum(n); pbar = sum(o) / N
    tbar = sum(t .* n) / N
    num = sum(t[i] * (o[i] - n[i] * pbar) for i in eachindex(o))
    var = pbar * (1 - pbar) * sum(n[i] * (t[i] - tbar)^2 for i in eachindex(o))
    z = num / sqrt(var)
    p = 2 * (1 - cdf(Normal(), abs(z)))
    return z, p
end
z_trend, p_trend = ca_trend(o_band, n_band)

# --- (2) Pooled Wilson 95% CI for the three non-top bands ---
function wilson_ci(k::Int, n::Int; z::Float64 = 1.96)
    phat = k / n
    center = (phat + z^2 / (2n)) / (1 + z^2 / n)
    half = (z / (1 + z^2 / n)) * sqrt(phat * (1 - phat) / n + z^2 / (4n^2))
    return (center - half, center + half)
end
o_int = sum(o_band[1:3]); n_int = sum(n_band[1:3])
ci_lo, ci_hi = wilson_ci(o_int, n_int)

# --- (3) Fisher exact test of the top two bands (band 3 vs band 4) ---
function fisher_exact(a::Int, b::Int, c::Int, d::Int)
    # 2x2: rows = bands {3,4}, cols = {owner, non-owner}
    n1 = a + b; k = a + c; N = a + b + c + d
    dist = Hypergeometric(k, N - k, n1)
    p_obs = pdf(dist, a)
    lo = max(0, n1 - (N - k)); hi = min(n1, k)
    return sum(pdf(dist, x) for x in lo:hi if pdf(dist, x) <= p_obs * (1 + 1e-7))
end
p_hump = fisher_exact(o_band[3], n_band[3] - o_band[3],
                      o_band[4], n_band[4] - o_band[4])

# --- Table ---
tex_path = joinpath(ROOT, "tables", "tex", "model_vs_data_band.tex")
open(tex_path, "w") do f
    println(f, raw"\begin{table}[htbp]")
    println(f, raw"\centering")
    println(f, raw"\caption{Predicted and observed annuity ownership by wealth band}")
    println(f, raw"\label{tab:model_vs_data_band}")
    println(f, raw"\begin{threeparttable}")
    println(f, raw"\begin{tabular}{lccc}")
    println(f, raw"\toprule")
    println(f, raw" & Observed & Model & Model " * "\\\\")
    println(f, raw"Wealth band & (HRS lifetime) & (threshold) & (cost-smoothed) " * "\\\\")
    println(f, raw"\midrule")
    for i in 1:4
        println(f, band_labels[i] * " & " *
            @sprintf("%.1f\\%%", hrs_pct[i]) * " & " *
            @sprintf("%.1f\\%%", model_hard[i]) * " & " *
            @sprintf("%.1f\\%%", model_smth[i]) * " \\\\")
    end
    println(f, raw"\bottomrule")
    println(f, raw"\end{tabular}")
    println(f, raw"\begin{tablenotes}")
    println(f, raw"\small")
    println(f, "\\item Observed: unweighted lifetime-SPIA ownership in the HRS analysis sample " *
        @sprintf("(%d owners among %d households).", sum(o_band), sum(n_band)))
    println(f, "\\item Model (threshold): the single-product structural model's predicted " *
        "ownership by band. Model (cost-smoothed): the same prediction under a " *
        "fixed-cost dispersion (Section~\\ref{sec:gate}).")
    println(f, "\\item The observed gradient is increasing: a Cochran--Armitage trend test " *
        @sprintf("across the four bands gives \$z=%.2f\$, \$p=%.3f\$. ", z_trend, p_trend) *
        @sprintf("Pooled observed ownership in the three non-top bands is %.1f\\%% ", 100 * o_int / n_int) *
        @sprintf("(Wilson 95\\%% CI [%.2f\\%%, %.2f\\%%]), excluding zero, where the ", 100 * ci_lo, 100 * ci_hi) *
        "single-product model predicts none. The apparent peak-then-dip across the " *
        @sprintf("top two bands is not statistically resolvable (Fisher exact \$p=%.2f\$).", p_hump))
    println(f, raw"\end{tablenotes}")
    println(f, raw"\end{threeparttable}")
    println(f, raw"\end{table}")
end
@printf("  trend z=%.3f p=%.4f | interior %.2f%% CI [%.2f, %.2f] | hump Fisher p=%.3f\n",
        z_trend, p_trend, 100 * o_int / n_int, 100 * ci_lo, 100 * ci_hi, p_hump)
println("  LaTeX written: $tex_path")
