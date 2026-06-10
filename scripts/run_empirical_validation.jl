# Empirical validation of the channel ranking: cross-sectional ownership
# gradients in the HRS sample, compared against the model's predicted signs.
#
# The structural channels predict, in the cross-section of single nonworking
# retirees 65-69:
#   survival pessimism  ownership RISES with subjective survival optimism
#                       (liv10r = self-reported / life-table P(live ~10 yrs))
#   bequests (luxury)   ownership FALLS with bequest intention (beq100)
#   health / Med+R-S    ownership FALLS in poor health
#   SS/DB crowd-out     conditional on wealth, ownership FALLS with
#                       pre-annuitized income (ss_db_income)
#   loads/min purchase  ownership RISES with wealth (feasibility + fixed cost)
#
# Two complementary estimates:
#   1. Weighted ownership means by covariate bins (transparent, no functional
#      form).
#   2. Weighted logit with person-clustered (hhidpn) sandwich standard errors
#      over complete cases (a person appears in up to 5 waves).
#
# Input:  data/processed/hrs_validation_sample.csv
# Output: tables/csv/empirical_gradients_cells.csv
#         tables/csv/empirical_gradients_logit.csv
# Usage:  julia --project=. scripts/run_empirical_validation.jl

using Printf
using DelimitedFiles
using LinearAlgebra
using Statistics

const ROOT = joinpath(@__DIR__, "..")
include(joinpath(@__DIR__, "config.jl"))

# ===================================================================
# Load
# ===================================================================
path = joinpath(ROOT, "data", "processed", "hrs_validation_sample.csv")
raw, hdr = readdlm(path, ','; header=true)
cols = Dict(string(h) => j for (j, h) in enumerate(vec(hdr)))
getcol(name) = Float64.(raw[:, cols[name]])

hhidpn  = getcol("hhidpn")
age     = getcol("age")
female  = getcol("female")
health3 = getcol("health3")
wealth  = getcol("wealth")
hous    = getcol("hous_wealth")
ss_db   = getcol("ss_db_income")
liv10r  = getcol("liv10r")
beq100  = getcol("beq100")
own     = getcol("own_life_ann")
wt      = getcol("weight")
n_all = length(own)
@printf("Loaded %d person-wave observations (%.1f%% owners)\n",
    n_all, sum(own) / n_all * 100)

# Wealth bins: the model's SS_QUARTILE_BREAKS cells.
const BREAKS = [30_000.0, 120_000.0, 350_000.0]
wbin = [w < BREAKS[1] ? 1 : w < BREAKS[2] ? 2 : w < BREAKS[3] ? 3 : 4 for w in wealth]

# ===================================================================
# 1. Weighted ownership by covariate bins
# ===================================================================
wmean(y, w, mask) = sum(w[mask]) > 0 ? sum(y[mask] .* w[mask]) / sum(w[mask]) : NaN

cells = Tuple{String,String,Int,Float64}[]  # covariate, bin label, n, ownership_pct
function add_cells!(covname, labels, masks)
    for (lbl, m) in zip(labels, masks)
        push!(cells, (covname, lbl, count(m), wmean(own, wt, m) * 100))
    end
end

add_cells!("wealth_bin", ["<30k", "30-120k", "120-350k", ">350k"],
    [wbin .== b for b in 1:4])
add_cells!("health", ["Good", "Fair", "Poor"],
    [health3 .== h for h in 1:3])

# Survival optimism: terciles of liv10r among nonmissing.
m_liv = .!isnan.(liv10r)
qs = quantile(liv10r[m_liv], [1/3, 2/3])
add_cells!("surv_optimism_liv10r",
    ["T1 (pessimist)", "T2", "T3 (optimist)"],
    [m_liv .& (liv10r .<= qs[1]),
     m_liv .& (liv10r .> qs[1]) .& (liv10r .<= qs[2]),
     m_liv .& (liv10r .> qs[2])])

# Bequest intention: P(bequest >= 100k) has mass points at 0 and 50.
m_beq = .!isnan.(beq100)
add_cells!("bequest_beq100", ["0%", "1-49%", ">=50%"],
    [m_beq .& (beq100 .== 0), m_beq .& (beq100 .> 0) .& (beq100 .< 50),
     m_beq .& (beq100 .>= 50)])

# Pre-annuitized income terciles WITHIN wealth bins 3-4 (crowd-out is a
# conditional-on-wealth prediction, and ownership is concentrated there).
m_top = wbin .>= 3
qs_ss = quantile(ss_db[m_top], [1/3, 2/3])
add_cells!("ss_db_within_topwealth", ["T1 (low)", "T2", "T3 (high)"],
    [m_top .& (ss_db .<= qs_ss[1]),
     m_top .& (ss_db .> qs_ss[1]) .& (ss_db .<= qs_ss[2]),
     m_top .& (ss_db .> qs_ss[2])])

println("\n  Weighted ownership (%) by covariate bin:")
@printf("  %-26s %-16s %6s %10s\n", "covariate", "bin", "n", "own (%)")
println("  " * "-" ^ 62)
for (cov, lbl, n, o) in cells
    @printf("  %-26s %-16s %6d %9.2f\n", cov, lbl, n, o)
end

# ===================================================================
# 2. Weighted logit, person-clustered SEs
# ===================================================================
# Complete cases for the expectation covariates.
cc = m_liv .& m_beq
# Clip the optimism ratio's sparse upper tail (life-table denominators near
# the sample's age bounds can inflate it).
liv10r_c = clamp.(liv10r, 0.0, 2.5)

# log(1+w) tightens the wealth control beyond the coarse bins; housing wealth
# enters separately because the bequest-expectation covariate proxies it (the
# modal $100k+ bequest is the house).
X = hcat(ones(sum(cc)),
         Float64.(wbin[cc] .== 2), Float64.(wbin[cc] .== 3), Float64.(wbin[cc] .== 4),
         log.(1.0 .+ wealth[cc]) ./ 10,
         log.(1.0 .+ hous[cc]) ./ 10,
         ss_db[cc] ./ 10_000,
         liv10r_c[cc],
         beq100[cc] ./ 100,
         Float64.(health3[cc] .== 2), Float64.(health3[cc] .== 3),
         female[cc], (age[cc] .- 67.0))
names_x = ["const", "wealth 30-120k", "wealth 120-350k", "wealth >350k",
           "log(1+wealth)/10", "log(1+housing)/10",
           "ss_db (per \$10k)", "surv optimism (liv10r)", "beq100 (0-1)",
           "health Fair", "health Poor", "female", "age - 67"]
y = own[cc]
w = wt[cc] ./ mean(wt[cc])
clus = hhidpn[cc]
@printf("\n  Logit complete cases: %d (%.1f%% owners), %d persons\n",
    length(y), mean(y) * 100, length(unique(clus)))

# Newton-Raphson for the weighted logit MLE.
k = size(X, 2)
beta = zeros(k)
H = zeros(k, k)
for it in 1:50
    eta = X * beta
    pr = 1.0 ./ (1.0 .+ exp.(-eta))
    g = X' * (w .* (y .- pr))
    global H = X' * (X .* (w .* pr .* (1.0 .- pr)))
    step = H \ g
    global beta += step
    maximum(abs.(step)) < 1e-10 && break
end

# Cluster-robust sandwich: meat from person-summed scores.
eta = X * beta
pr = 1.0 ./ (1.0 .+ exp.(-eta))
score = X .* (w .* (y .- pr))
meat = zeros(k, k)
for c in unique(clus)
    s_c = vec(sum(score[clus .== c, :], dims=1))
    meat .+= s_c * s_c'
end
Hinv = inv(H)
V = Hinv * meat * Hinv
se = sqrt.(diag(V))
z = beta ./ se

# Average marginal effects for magnitude readability.
ame_scale = mean(w .* pr .* (1.0 .- pr)) / mean(w)
ame = beta .* ame_scale

# Predicted signs from the model's channels ("" = control, no prediction).
pred_sign = ["", "+", "+", "+", "", "", "-", "+", "-", "", "-", "", ""]

println("\n  Weighted logit (cluster-robust by person):")
@printf("  %-26s %9s %8s %7s %9s %6s %6s\n",
    "covariate", "coef", "se", "z", "AME(pp)", "pred", "match")
println("  " * "-" ^ 78)
n_match = 0; n_pred = 0
for j in 1:k
    match = ""
    if pred_sign[j] != ""
        global n_pred += 1
        ok = (pred_sign[j] == "+" && beta[j] > 0) || (pred_sign[j] == "-" && beta[j] < 0)
        ok && (global n_match += 1)
        match = ok ? "YES" : "NO"
    end
    @printf("  %-26s %9.4f %8.4f %7.2f %9.3f %6s %6s\n",
        names_x[j], beta[j], se[j], z[j], ame[j] * 100, pred_sign[j], match)
end
@printf("\n  Channel-sign concordance: %d / %d predicted gradients match\n",
    n_match, n_pred)

# ===================================================================
# Save
# ===================================================================
out_dir = joinpath(ROOT, "tables", "csv"); mkpath(out_dir)
cells_path = joinpath(out_dir, "empirical_gradients_cells.csv")
open(cells_path, "w") do f
    println(f, "covariate,bin,n,ownership_pct")
    for (cov, lbl, n, o) in cells
        @printf(f, "%s,%s,%d,%.4f\n", cov, lbl, n, o)
    end
end
logit_path = joinpath(out_dir, "empirical_gradients_logit.csv")
open(logit_path, "w") do f
    println(f, "covariate,coef,se_cluster,z,ame_pp,predicted_sign,sign_match")
    for j in 1:k
        match = pred_sign[j] == "" ? "" :
            ((pred_sign[j] == "+" && beta[j] > 0) ||
             (pred_sign[j] == "-" && beta[j] < 0)) ? "yes" : "no"
        @printf(f, "%s,%.6f,%.6f,%.4f,%.4f,%s,%s\n",
            names_x[j], beta[j], se[j], z[j], ame[j] * 100, pred_sign[j], match)
    end
end
println("\n  Saved: $cells_path")
println("  Saved: $logit_path")
flush(stdout)
