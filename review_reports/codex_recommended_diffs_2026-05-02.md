# Codex Recommended Diffs, Held For Comparison

Created: 2026-05-02

Scope: this file proposes diffs only. No source files were changed as part of this hold-off pass. One pre-existing uncommitted change already exists in `scripts/aws/launch.sh` from the earlier AWS-sync hardening pass; see `git diff -- scripts/aws/launch.sh`.

## Provenance Read

The error pattern looks like rapid model evolution, not one isolated bad edit:

- The project moved from a 9/10-channel structure to an 11-channel structure, but some exporters, tests, prose, and generated tables lagged behind.
- The behavioral penalty was reparameterized from the old `psi * abs(u(premium))` shape to a marginal-utility-scaled narrow-framing stream; stale comments/tables/tests kept describing the old units.
- The age>65 premium bridge correction changed headline ownership materially, which made all existing CSV/TeX/PDF outputs stale.
- Several pipeline scripts allowed stale generated artifacts to be reused, so old numbers could survive even when source code was corrected.

I do not see evidence that Codex introduced the core model-equation bugs in this list. Codex did surface several of them in review. The one local Codex-originated worktree change I can see now is the `scripts/aws/launch.sh` rsync-exclude hardening patch, which is unrelated to the economic equations.

## Status Of The Eight Pasted Findings

| Finding | Current status | Recommendation |
|---|---|---|
| AWS runner falsely reports success | Mostly fixed in `scripts/aws/run_pipeline_remote.sh`: exit code is captured through `PIPESTATUS` and `.pipeline-complete` is conditional. | Optional small hardening below: use temporary `set +e` around the `tee` pipeline and include `results/*` in the tarball. |
| `test_headline_regression.jl` fails | Stale. File is now `test/test_headline_regression.jl.deprecated` and is not in `test/runtests.jl`. | Do not resurrect it. Either delete after confidence, or leave deprecated. |
| `extension_path.tex` stale | Generated artifact is stale until full rerun. | Do not hand-edit. Make `run_all.jl` fail if expected generated artifacts are missing. |
| welfare counterfactual baseline not full model | Current `scripts/run_welfare_counterfactuals.jl` includes age needs, health utility, lambda_w, and psi_purchase in ownership and CEV configs. | Looks fixed. No diff unless fresh run proves otherwise. |
| behavioral penalty wrong scaling | Current `src/utility.jl` uses marginal utility at `c_ref` times unrecouped premium stream. | Looks fixed. No diff. |
| simulation uses subjective mortality | Current `src/simulation.jl` calls `build_health_survival(...; psi_override=1.0)`. | Looks fixed. No diff. |
| robustness unsupported quadrature nodes | Current `src/health.jl` supports 13/15 nodes; `run_robustness.jl` main GH sweep uses 5/7/11. | Looks fixed. No diff. |
| ten/eleven-channel headline unguarded | Partially fixed: smoke test is in runner, bitmasks are 11-channel, but `test_manuscript_numbers.jl` still skips final-layer checks when CSV is stale. | Tighten test after rerun; proposed diff below. |

## Proposed Diff 1: AWS Runner Hardening

Rationale: current runner is materially better than the old review finding. This patch just makes the truthfulness contract match the shell semantics and captures `results/*`.

```diff
diff --git a/scripts/aws/run_pipeline_remote.sh b/scripts/aws/run_pipeline_remote.sh
--- a/scripts/aws/run_pipeline_remote.sh
+++ b/scripts/aws/run_pipeline_remote.sh
@@
-set -uo pipefail
+set -euo pipefail
@@
-PIPELINE_RC=0
-julia --project=. run_all.jl 2>&1 | tee -a "$LOG"
-PIPELINE_RC=${PIPESTATUS[0]}
+set +e
+julia --project=. run_all.jl 2>&1 | tee -a "$LOG"
+PIPELINE_RC=${PIPESTATUS[0]}
+set -e
@@
     figures/png/*.png \
     paper/numbers.tex \
+    results/* \
     "$LOG" 2>/dev/null || echo "  (tar warning: some expected paths missing)" | tee -a "$LOG"
```

## Proposed Diff 2: Make `run_all.jl` Artifact Validation Fail Closed

Rationale: Stage 16 now validates macros, but the final artifact list still only warns and misses some generated outputs. This is the best guard against “AWS succeeded but paper still contains old table.”

```diff
diff --git a/run_all.jl b/run_all.jl
--- a/run_all.jl
+++ b/run_all.jl
@@
         "implied_gamma.tex",
+        "monte_carlo_summary.tex",
         "moment_validation.tex",
@@
-    tex_dir = joinpath(PROJECT_DIR, "tables", "tex")
+    expected_csv = [
+        "decomposition.csv",
+        "multigamma_decomposition.csv",
+        "pashchenko_comparison.csv",
+        "moment_validation.csv",
+        "welfare_cev_grid.csv",
+        "population_cev.csv",
+        "welfare_counterfactuals.csv",
+        "cev_counterfactuals.csv",
+        "dia_comparison.csv",
+        "bequest_recalibration.csv",
+        "subset_enumeration.csv",
+        "shapley_exact.csv",
+        "pairwise_interactions_exact.csv",
+        "robustness_full.csv",
+        "ss_cut_robustness.csv",
+        "implied_gamma.csv",
+        "psi_sensitivity.csv",
+        "monte_carlo_ownership.csv",
+        "state_utility_sensitivity.csv",
+    ]
+    expected_figs = [
+        "fig1_decomposition.pdf",
+        "fig2_gamma_sensitivity.pdf",
+        "fig3_policy_functions.pdf",
+        "fig4_welfare_heatmap.pdf",
+        "fig5_cev_heatmap.pdf",
+    ]
+
+    tex_dir = joinpath(PROJECT_DIR, "tables", "tex")
+    csv_dir = joinpath(PROJECT_DIR, "tables", "csv")
+    fig_dir = joinpath(PROJECT_DIR, "figures", "pdf")
     missing_files = String[]
     for f in expected_tex
         if !isfile(joinpath(tex_dir, f))
-            push!(missing_files, f)
+            push!(missing_files, joinpath("tables", "tex", f))
         end
     end
+    for f in expected_csv
+        if !isfile(joinpath(csv_dir, f))
+            push!(missing_files, joinpath("tables", "csv", f))
+        end
+    end
+    for f in expected_figs
+        if !isfile(joinpath(fig_dir, f))
+            push!(missing_files, joinpath("figures", "pdf", f))
+        end
+    end
@@
-        println("  WARNING: Missing manuscript tables:")
+        println("  ERROR: Missing expected pipeline artifacts:")
         for f in missing_files
             println("    $f")
         end
-        println()
+        exit(1)
     end
```

## Proposed Diff 3: Tighten Manuscript Number Test After 11-Channel Rerun

Rationale: this removes the stale-CSV skip. It will make local tests fail until the 2048-row subset CSV is regenerated, which is exactly what we want before declaring the paper ready.

```diff
diff --git a/test/test_manuscript_numbers.jl b/test/test_manuscript_numbers.jl
--- a/test/test_manuscript_numbers.jl
+++ b/test/test_manuscript_numbers.jl
@@
-# Returns true when subset_enumeration.csv reflects the current 11-channel
-# code (2048 subsets). When the CSV is stale (1024 subsets, pre-SDU build),
-# tests that assume the new bit layout skip cleanly. Stage 16's post-run
-# validation runs AFTER a fresh export and will see 2048 rows, so strict
-# checks always run on fresh state.
-function subset_csv_is_eleven_channel()
+function assert_subset_csv_is_eleven_channel()
     path = joinpath(CSV_DIR, "subset_enumeration.csv")
-    isfile(path) || return false
+    isfile(path) || error("subset_enumeration.csv missing")
     n_rows = countlines(path) - 1  # subtract header
-    return n_rows >= 2048
+    @test n_rows == 2048
+    rows, _ = readdlm(path, ',', Any; header=true)
+    @test maximum(Int.(rows[:, 1])) == 2047
 end
@@
-        eleven_ch = subset_csv_is_eleven_channel()
+        assert_subset_csv_is_eleven_channel()
         for (name, bm) in cases
-            if !eleven_ch && (name == "ownTenChannel" || name == "ownElevenChannel")
-                continue
-            end
             @test haskey(macros, name)
             @test macros[name] == fmt_pct(subset_ownership_pct(bm); digits=1)
         end
```

## Proposed Diff 4: Fix `run_welfare_analysis.jl` Hard Failure And Income Double Count

Rationale: this is not in the pasted eight findings, but it is a live blocker. The script comments say SS is wired through the welfare model and `y_existing = 0`, but the population still carries HRS permanent income in column 2. Section 5 also refers to undefined `median_income`.

```diff
diff --git a/scripts/run_welfare_analysis.jl b/scripts/run_welfare_analysis.jl
--- a/scripts/run_welfare_analysis.jl
+++ b/scripts/run_welfare_analysis.jl
@@
 population = zeros(n_pop, 4)
 population[:, 1] = Float64.(hrs_raw[:, 1])
-population[:, 2] = Float64.(hrs_raw[:, 2])
+population[:, 2] .= 0.0
 population[:, 3] = Float64.(hrs_raw[:, 3])
@@
-ss_zero(age, p) = 0.0
+ss_sim(age, p) = 18_500.0
 p_sim = ModelParams(;
@@
     survival_pessimism=SURVIVAL_PESSIMISM,
+    consumption_decline=CONSUMPTION_DECLINE,
+    health_utility=Float64.(HEALTH_UTILITY),
+    psi_purchase=PSI_PURCHASE,
@@
 )
-p_fair_pr = ModelParams(age_start=AGE_START, age_end=AGE_END, mwr=1.0, r=R_RATE)
+p_fair_pr = ModelParams(age_start=AGE_START, age_end=AGE_END, mwr=1.0, r=R_RATE)
 fair_pr = compute_payout_rate(p_fair_pr, base_surv)
-loaded_pr = MWR_LOADED * fair_pr
-grids_sim = build_grids(p_fair_pr, fair_pr)
-sol_sim = solve_lifecycle_health(p_sim, grids_sim, base_surv, ss_zero)
+p_fair_nom = ModelParams(age_start=AGE_START, age_end=AGE_END, mwr=1.0, r=R_RATE,
+                         inflation_rate=INFLATION)
+fair_pr_nom = INFLATION > 0 ? compute_payout_rate(p_fair_nom, base_surv) : fair_pr
+loaded_pr = MWR_LOADED * (INFLATION > 0 ? fair_pr_nom : fair_pr)
+grids_sim = build_grids(p_fair_pr, max(fair_pr, fair_pr_nom))
+sol_sim = solve_lifecycle_health(p_sim, grids_sim, base_surv, ss_sim)
@@
         sol_sim, W_0, 1, base_surv, p_sim;
-        payout_rate=loaded_pr, y_existing=median_income,
+        payout_rate=loaded_pr, y_existing=0.0,
         n_sim=5_000, rng_seed=42,
     )
```

## Proposed Diff 5: Add Baseline MWR = 0.87 To Robustness Export

Rationale: current paper rows label baseline MWR but consume `ownMWREightyTwo`. That was defensible only under the old MWR=0.82 baseline.

```diff
diff --git a/scripts/run_robustness.jl b/scripts/run_robustness.jl
--- a/scripts/run_robustness.jl
+++ b/scripts/run_robustness.jl
@@
-mwr_vals = [0.82, 0.85, 0.90, 0.95]
+mwr_vals = sort(unique([0.82, 0.85, MWR_LOADED, 0.90, 0.95]))
@@
-    println(f, "MWR = 0.82, hazard multipliers [0.50, 1.0, 3.0].")
+    println(f, @sprintf("MWR = %.2f, hazard multipliers [0.50, 1.0, 3.0].", MWR_LOADED))
```

```diff
diff --git a/scripts/export_manuscript_numbers.jl b/scripts/export_manuscript_numbers.jl
--- a/scripts/export_manuscript_numbers.jl
+++ b/scripts/export_manuscript_numbers.jl
@@
     # MWR sweep (appears in MWR sensitivity table in main.tex)
+    def!("ownMWRBaseline",
+         fmt_pct(robustness_ownership("MWR sweep", @sprintf("MWR=%.2f", MWR_LOADED)); digits=1))
     for (key, spec) in [
         ("EightyTwo",    "MWR=0.82"),
```

```diff
diff --git a/paper/main.tex b/paper/main.tex
--- a/paper/main.tex
+++ b/paper/main.tex
@@
-\pMwrBaseline{} (baseline) & \ownMWREightyTwoNum \\
+0.82 & \ownMWREightyTwoNum \\
+\pMwrBaseline{} (baseline) & \ownMWRBaselineNum \\
 0.85 & \ownMWREightyFiveNum \\
```

Apply the same table-row change in `paper/appendix.tex`.

## Proposed Diff 6: Current AWS Sync Patch Already In Worktree

Rationale: this is already an uncommitted source change from the earlier pass. It prevents uploading huge/stale local directories to AWS. Keep or drop deliberately.

```diff
diff --git a/scripts/aws/launch.sh b/scripts/aws/launch.sh
--- a/scripts/aws/launch.sh
+++ b/scripts/aws/launch.sh
@@
     --exclude '.git/'
+    --exclude '.claude/'
+    --exclude '.aws-instance.meta*'
+    --exclude 'archive/'
     --exclude 'logs/'
+    --exclude 'review_reports*/'
+    --exclude 'potential references/'
+    --exclude 'data/raw/'
     --exclude 'results-latest.tar.gz'
     --exclude 'results_*.tar.gz'
+    --exclude 'results-*.tar.gz'
```

## Optional Design Decision Before Full Rerun: R-S And Medical In Shapley

`scripts/run_subset_enumeration.jl` still forces Medical on whenever R-S is active. That makes economic sense if R-S is defined as a complement to medical risk, but it means the exact 2048-coalition Shapley game contains duplicate realized model states. If the paper says “11 independent channels,” this should be changed. If the paper says “R-S only exists as a medical-risk interaction,” the current code is defensible but the manuscript should be explicit.

Recommended decision:

- For clean Shapley accounting: stop forcing Medical when R-S is active, and let R-S alone mean health-dependent mortality without medical spending.
- For economic complement accounting: keep current code, but describe Shapley as an 11-flag game with one structural dependency rather than 11 independent toggles.

I would not silently patch this without your approval because it changes the interpretation of the Shapley values.

## My Recommended Apply Order

1. Apply Diff 4 (`run_welfare_analysis.jl`) because it fixes a live hard failure.
2. Apply Diff 2 and Diff 3 so stale artifacts cannot pass.
3. Apply Diff 5 so MWR tables match the 0.87 baseline.
4. Apply Diff 1 and decide whether to keep Diff 6 before launching AWS.
5. Decide the R-S/Medical Shapley convention, then run AWS once.

