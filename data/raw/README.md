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

## Reproducibility notes

- Both raw datasets (the RAND HRS Longitudinal File and the HRS public
  fat files) are available at no cost to registered HRS users; neither
  requires a restricted-data use agreement. Aggregate processed
  CSVs in `data/processed/` are checked into the repository; the two
  person-level extracts (`lockwood_hrs_sample.csv`,
  `hrs_validation_sample.csv`) are NOT shipped under HRS conditions of use,
  so the compute stages require regenerating them from a free RAND HRS
  download (see the top-level README's Data availability section).
- `run_all.jl` skips Stage 0c whose processed CSV already exists.
  Set `ANNUITY_FORCE_HRS_REBUILD=1` to force regeneration.
- If the raw data is unavailable at runtime, the run_all.jl wrapper logs
  a warning and falls back to the checked-in processed CSVs rather than
  failing. The substantive structural results (Stages 1+) depend on the
  processed CSVs only.
