# Replication Package Review

## 1. Summary Assessment
The package is close to a credible replication archive: the Julia environment is pinned, the master pipeline is explicit, the tests are broad, and the processed calibration data are bundled. Within the current repo state, the main tables and figures appear reproducible.

The main concern is that the archive is not yet fully audit-ready from a data-editor perspective. The raw HRS rebuild is only partly documented, the shipped processed sample contains a placeholder annuity-ownership column, the main pipeline does not regenerate the HRS sample, and survey weights are present but not used in the main ownership calculations. In short, the code is reproducible, but the provenance story still needs tightening.

## 2. Specific Strengths
- The pipeline is centralized and easy to follow. `run_all.jl` lays out the full sequence from tests through tables and figures, with explicit failure checks and output verification (`run_all.jl:1-16`, `76-158`, `176-219`).
- The computational environment is pinned. `Project.toml` lists the dependencies (`Project.toml:1-14`), and `Manifest.toml` locks the exact Julia version and package graph (`Manifest.toml:1-5`).
- The test suite is unusually broad for a structural package. The runner executes separate suites for limiting cases, Lockwood replication, health, welfare, and Pashchenko/DIA checks (`test/runtests.jl:14-22`, `24-39`).
- The HRS sample builder is transparent about filters and variable mapping, which is helpful for reconstruction (`calibration/build_hrs_sample.jl:1-31`, `43-73`, `229-270`).
- The manuscript includes a dedicated Data Availability statement and points to the code/data repository (`paper/main.tex:554-556`).

## 3. Specific Weaknesses
- The headline result is inconsistent across documents. The README says baseline ownership is 3.2% (`README.md:3-9`), while the manuscript and generated tables report 5.3% (`paper/main.tex:46`, `73`, `542`; `tables/csv/decomposition.csv`). That makes the reproduction target ambiguous.
- The shipped processed sample does not actually contain observed annuity ownership. The builder writes `own_life_ann`, but the code sets it to zero as a placeholder and explicitly says to use a separate question if available (`calibration/build_hrs_sample.jl:201-206`, `261-270`). The archived CSV therefore cannot independently verify the 3.6% benchmark from the bundled data alone.
- The sample-size description is muddled. The paper says the sample contains 793 individuals and 566 above $5,000 (`paper/main.tex:347`), but the builder explicitly pools person-wave observations across five waves and writes one row per person-wave (`calibration/build_hrs_sample.jl:71-73`, `261-270`). The README then describes the file as 793 observations (`README.md:43-45`), which is not the same object as the shipped CSV.
- Survey weights are available but not used in the main reported ownership calculations. The ownership routines accept weights (`src/wtp.jl:515-516`, `552-553`), but `src/decomposition.jl` calls `compute_ownership_rate_health` without weights (`src/decomposition.jl:52-77`, `86-145`), and `scripts/run_decomposition.jl` drops the weight column when building the population matrix (`scripts/run_decomposition.jl:32-47`). The published rates are therefore unweighted, despite the CSV carrying weights.
- The raw-data rebuild path is hardcoded to a local RAND HRS file path (`calibration/build_hrs_sample.jl:52-55`), but the quick-start instructions only show `Pkg.instantiate()` and `run_all.jl` (`README.md:20-25`). A replicator can run the shipped pipeline, but not fully reconstruct the processed HRS file from scratch without additional guesswork.
- There is no release tag in the repository, and the current state appears to be anchored only by a single commit. That is not fatal, but it is weaker than a tagged archival replication package.

## 4. Concrete Suggestions for Improvement
- Harmonize the headline ownership number across the README, manuscript, highlights, and generated tables. If 5.3% is the intended baseline, update the README and any stale language.
- Either populate `own_life_ann` with the actual annuity-ownership variable or remove/rename the column so the CSV does not imply it contains a validated benchmark outcome. Add a short provenance note explaining how the 3.6% observed ownership rate is measured.
- Pass the HRS survey weights through the main decomposition and counterfactual scripts, or explicitly justify in the paper why unweighted population evaluation is preferred.
- Add a short “Rebuild the processed HRS sample” subsection to the README with the exact raw-data path, access requirements, and the command for `calibration/build_hrs_sample.jl`.
- Add a small test that checks the processed CSV schema and key provenance assumptions, including the distinction between pooled person-wave observations and unique individuals.
- Create an archival tag or release and cite it in the README so the package can be referenced at a stable version.

## 5. Score and Recommendation
Score: 6/10.

Recommendation: revise-and-resubmit.
