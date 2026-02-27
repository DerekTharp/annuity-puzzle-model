# Channel Review Handoff

This folder contains the concrete implementation recommendation for the two proposed preference channels.

## Key File

- `review_reports_channels/00_implementation_recommendation.md`

## Core Spec Reviewed

- `docs/channel_implementation_spec.md`

## Code Files Referenced

- `src/parameters.jl`
- `src/utility.jl`
- `src/bellman.jl`
- `src/solve.jl`
- `scripts/config.jl`
- `scripts/run_shapley_decomposition.jl`

## Main Recommendation

- Implement the shared infrastructure now.
- Promote Channel 1 only as an extension unless the calibration story is tightened.
- Keep Channel 2 as a robustness/appendix extension unless isolated runs show it lowers ownership in this model and the mapping is clearly defended.
