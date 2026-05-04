# Raw data provenance

This directory holds the raw input data used to construct the processed
calibration CSVs in `data/processed/`. All files are restricted-use or
licensed; none are checked into the public repository.

## RAND HRS Longitudinal File

- **Path expected:** `data/raw/HRS/randhrs1992_2022v1_STATA/`
- **Source:** RAND Center for the Study of Aging, RAND HRS Longitudinal File
  2022 (v1) Stata distribution.
- **URL:** <https://hrsdata.isr.umich.edu/data-products/rand-hrs-longitudinal-file-2022-v1>
- **Used by:** `calibration/build_hrs_sample.jl` (Stage 0b).
- **Produces:** `data/processed/lockwood_hrs_sample.csv`.

## HRS Fat Files (per-contract pension/annuity records)

- **Path expected:** `data/raw/HRS/HRS Fat Files/`
- **Source:** University of Michigan HRS Public Survey Data, fat-file
  pension/wealth modules across waves 5--9.
- **URL:** <https://hrsdata.isr.umich.edu/data-products/2002-hrs-core> (and
  later wave equivalents).
- **Used by:** `calibration/compute_lifetime_ownership_rate.jl` (Stage 0c)
  to compute the lifetime annuity contract indicator from question stem
  q286 ("Will this annuity continue for the rest of your life?").
- **Produces:** `data/processed/hrs_lifetime_ownership.csv`.

## ELSA archive (UK Data Service deposit 5050)

- **Path expected:** `data/raw/ELSA/5050_ELSA_Main_Waves0-11_1998-2024.zip`
- **Source:** UK Data Service, English Longitudinal Study of Ageing,
  deposit 5050 (waves 0--11, 1998--2024).
- **URL:** <https://beta.ukdataservice.ac.uk/datacatalogue/series/series?id=200011>
- **Override:** scripts honor the `ANNUITY_ELSA_ARCHIVE` environment
  variable if you keep the zip elsewhere on disk.
- **Used by:** `calibration/elsa_pre_post_freedoms.jl` (Stage 0d),
  `calibration/elsa_disposition_pooled.jl` (Stage 0e),
  `calibration/elsa_subgroup_analysis.jl` (robustness).
- **Produces:** `data/processed/elsa_*.csv` files.

## Reproducibility notes

- All three raw datasets require institutional / DUA access. The processed
  CSVs in `data/processed/` are checked into the repository so that the
  full structural pipeline can run without raw access.
- `run_all.jl` skips any Stage 0c--0e whose processed CSV already exists.
  Set `ANNUITY_FORCE_HRS_REBUILD=1` to force regeneration.
- If the raw data is unavailable at runtime, the run_all.jl wrapper logs
  a warning and falls back to the checked-in processed CSVs rather than
  failing. The substantive structural results (Stages 1+) depend on the
  processed CSVs only.
