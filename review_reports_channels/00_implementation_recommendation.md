# Implementation Recommendation For New Preference Channels

This note gives a concrete recommendation for the two proposed channels in `docs/channel_implementation_spec.md`, based on the current code structure in `src/` and the supporting literature available in `potential references/`.

## Bottom Line

Implement the shared utility-weighting infrastructure now, but do **not** make both channels part of the headline baseline on the first pass.

Recommended stance:

1. Implement **Channel 1** behind a parameter flag and evaluate it as a well-motivated extension.
2. Implement **Channel 2** behind a parameter flag, but treat it as a **robustness / appendix extension unless and until isolated runs show it lowers ownership in this model**.
3. Keep the current core model as the main benchmark for publication framing.
4. If either new channel is used in the paper's main quantitative match, present it as an **externally calibrated extension**, not as a new “gap-closing” knob.
5. If you expand the channel count, use the existing Shapley pipeline in `scripts/run_shapley_decomposition.jl` for the main interaction attribution rather than relying only on a single sequential order.

## Publication Recommendation

These channels can improve realism, but they do not automatically make the paper more publishable at JPubE.

What helps:

- showing that the main result is **not fragile** to richer preference structure
- using externally motivated calibration
- avoiding any appearance that the model is being tuned until it hits `3--6%`

What hurts:

- presenting Aguiar-Hurst as if it directly estimates a utility discount factor
- presenting Finkelstein-Luttmer-Notowidigdo as if it directly maps to `Good/Fair/Poor = [1.0, 0.90, 0.75]`
- claiming novelty for Channel 2 when Reichling-Smetters already incorporate related health-state-dependent utility effects

## Concrete Recommendation By Channel

### Channel 1: Front-Loaded Spending / Age-Varying Consumption Needs

Recommendation:

- **Implement now**
- **Do not make `delta_c = 0.02` the unquestioned headline baseline**
- Present it as **age-varying consumption needs / effective consumption demand**, not as pure time preference

Why:

- This channel is the one most likely to reduce annuity demand in your model.
- It is also the one most likely to draw referee skepticism if oversold.
- Aguiar-Hurst is better interpreted as evidence on retirement expenditure profiles, home production, and changing needs than as a direct estimate of age-specific felicity weights.

Calibration recommendation:

- Use `consumption_decline = 0.0` as the default / off state
- Use `0.01` as the preferred “central extension” value
- Use `0.02` as an upper-end robustness value
- Sensitivity grid: `{0.00, 0.01, 0.02, 0.03}`

Paper framing recommendation:

- Good: `As an extension, I allow effective consumption needs to decline with age, motivated by lifecycle expenditure evidence.`
- Avoid: `Aguiar and Hurst imply a 2% annual decline in utility weight.`

### Channel 2: State-Dependent Utility By Health

Recommendation:

- **Implement now, but do not assume it should be part of the main 9-channel headline model**
- Treat it as a **health-preference extension** or appendix robustness until isolated runs establish its sign in this model

Why:

- It is economically reasonable.
- It is not especially novel relative to Reichling-Smetters.
- The sign is **not guaranteed** to lower annuity demand; in related work, health-state-dependent marginal utility can increase annuitization.

Calibration recommendation:

- Keep default `health_utility = [1.0, 1.0, 1.0]`
- Prefer a central mapping closer to the Reichling-Smetters translation of FLN than the raw `[1.0, 0.90, 0.75]`
- Recommended central mapping: `[1.00, 0.84, 0.76]`
- Recommended mild robustness mapping: `[1.00, 0.90, 0.80]`
- Keep `[1.00, 0.90, 0.75]` as a stronger robustness case if you want the original spec represented

Reason for the alternative central mapping:

- `potential references/Finkelstein_Luttmer_Notowidigdo2013.txt` estimates declines in marginal utility by chronic-disease burden.
- `potential references/Reichling_Smetters2015.txt` already translate those estimates into health-state transitions, reporting lower-bound declines of about `16%` from healthy to impaired and another `10%` from impaired to disabled.

Paper framing recommendation:

- Good: `As a further extension, I allow health-state-dependent marginal utility of consumption, using values guided by FLN as mapped into discrete health states by Reichling and Smetters.`
- Avoid: `Poor health utility is 0.75 according to Finkelstein et al.`

## Recommended Decomposition Treatment

If you keep a sequential decomposition table:

0. Yaari benchmark
1. Social Security
2. Bequests
3. Medical expenditure risk
4. Health-mortality correlation
5. State-dependent utility
6. Survival pessimism
7. Front-loaded spending / age-varying needs
8. Pricing loads
9. Inflation erosion

Why this order:

- Channel 2 belongs with the health block.
- Channel 1 is a time-profile preference channel, not a health channel or a market-friction channel.
- Loads and inflation should remain the last block as market-pricing frictions.

However, the recommended main attribution is:

- use `scripts/run_shapley_decomposition.jl` as the main interaction/accounting exercise once the new channels are added
- keep the sequential decomposition as a more intuitive companion table

## Exact Code Recommendation

### 1. Add Generic Utility-Weight Plumbing

Do **not** hard-code separate multipliers in multiple solver branches. Create one unified flow-utility entry point.

Recommended additions:

- In `src/parameters.jl`
  - add `consumption_decline::Float64 = 0.0`
  - add `health_utility::Vector{Float64} = [1.0, 1.0, 1.0]`
- In `src/utility.jl`
  - add `consumption_weight(t, delta_c)`
  - add `health_utility_weight(ih, p)`
  - add `flow_utility(c, gamma, t, ih, p)` that multiplies all active weights

Recommended implementation shape:

```julia
function consumption_weight(t::Int, delta_c::Float64)
    delta_c == 0.0 && return 1.0
    return (1.0 - delta_c)^(t - 1)
end

function health_utility_weight(ih::Int, p::ModelParams)
    return p.health_utility[ih]
end

function flow_utility(c::Float64, gamma::Float64, t::Int, ih::Int, p::ModelParams)
    w_age = consumption_weight(t, p.consumption_decline)
    w_health = health_utility_weight(ih, p)
    return w_age * w_health * utility(c, gamma)
end
```

### 2. Thread `t` And `ih` Through Bellman Evaluation

The spec is right that `t` must be passed into `solve_consumption`, but the main missing detail is that the weighting must also hit the terminal period.

Recommended signature changes:

- In `src/bellman.jl`
  - change `solve_consumption(...)` to accept `t::Int` and `ih::Int=2`
  - change `terminal_value(...)` to accept `t::Int` and `ih::Int=2`

Use `ih=2` as the neutral non-health default in the no-health solver.

Recommended replacement points:

- `src/bellman.jl:39`, `52`, `63`
- `src/bellman.jl:102`, `110`, `115`

Replace `utility(...)` with `flow_utility(...)`.

### 3. Update Solver Call Sites

In `src/solve.jl`:

- no-health branch:
  - pass `t` into `solve_consumption`
  - pass `T` into `terminal_value`
- health branch:
  - pass both `t` and `ih` into `solve_consumption`
  - pass both `T` and `ih` into `terminal_value`

Key call sites:

- `src/solve.jl:56`
- `src/solve.jl:79-81`
- `src/solve.jl:149`
- `src/solve.jl:206-209`
- `src/solve.jl:216-219`

### 4. Extend Configuration

In `scripts/config.jl`, add:

```julia
const CONSUMPTION_DECLINE = 0.00
const HEALTH_UTILITY = [1.0, 1.0, 1.0]
```

Recommendation:

- leave both at neutral defaults in config until the code path is tested
- turn them on explicitly in dedicated scripts rather than silently changing the baseline

### 5. Extend TOML Loader

In `src/parameters.jl`, add the new parameters to the `preferences` section map, or create a new section if you prefer:

- `consumption_decline`
- `health_utility`

Backward compatibility requirement:

- old config files must continue to produce identical solutions

## Recommended Test Plan

Create one new file:

- `test/test_preference_channels.jl`

And add the following tests.

### A. Backward Compatibility

With:

- `consumption_decline = 0.0`
- `health_utility = [1.0, 1.0, 1.0]`

verify that:

- `flow_utility(c, gamma, t, ih, p) == utility(c, gamma)`
- solved value functions match pre-change values to tight tolerance on a tiny grid

### B. Utility Mechanics

Add to `test/test_utility.jl` or the new file:

- `consumption_weight(1, 0.02) == 1.0`
- `consumption_weight(2, 0.02) ≈ 0.98`
- `consumption_weight(21, 0.02) < consumption_weight(11, 0.02)`
- `health_utility_weight(1, p) == 1.0`
- `health_utility_weight(3, p) < health_utility_weight(2, p)`

### C. Limiting Behavioral Sign Checks

On a coarse grid, with all other channels fixed:

1. baseline
2. baseline + Channel 1 only
3. baseline + Channel 2 only
4. baseline + both

Record:

- ownership
- mean alpha
- value at representative wealth levels

Do **not** assume the sign of Channel 2. Test it.

### D. Health-Solver Regression

Add one health regression test in `test/test_health.jl`:

- with `health_utility = [1,1,1]`, results must match the current health solver
- with `health_utility = [1,0.84,0.76]`, the model should solve cleanly with no `NaN`, `-Inf`, or optimizer failures

## Recommended Run Plan Before Another Full AWS Cycle

### Phase 1: Plumbing Only

Implement the parameter and solver changes with both channels off.

Success condition:

- all tests pass
- baseline outputs unchanged

### Phase 2: Cheap Sign Runs

On a reduced grid:

- run Channel 1 only
- run Channel 2 only
- run both together

Success condition:

- sign and rough magnitude are understood before a full production rerun

### Phase 3: Promotion Decision

Use this rule:

- If Channel 1 lowers ownership materially and can be defended as age-varying needs, promote it to the main extension table.
- If Channel 2 lowers ownership only modestly or raises ownership, keep it in the appendix robustness section.
- Do **not** present Channel 2 as a “neglected factor that resolves the puzzle” unless the isolated-run evidence is strong and the calibration mapping is transparently defended.

### Phase 4: Full Run

Only after the sign check:

- update the decomposition scripts
- update the Shapley script
- run the full model

## Recommended Paper Strategy

Best publishability path:

1. Keep the current core model as the main contribution.
2. Present Channel 1 as an age-varying-needs extension.
3. Present Channel 2 as a richer health-preference robustness check.
4. Emphasize that the paper's conclusion is strengthened if the main result survives these richer preference assumptions.

Less effective path:

- expanding the headline from 7 channels to 9 channels and presenting both as essential gap-closing factors

That second strategy risks looking like calibration chasing.

## Files To Touch

- `docs/channel_implementation_spec.md`
- `src/parameters.jl`
- `src/utility.jl`
- `src/bellman.jl`
- `src/solve.jl`
- `scripts/config.jl`
- `scripts/run_shapley_decomposition.jl`
- `test/test_utility.jl`
- `test/test_health.jl`
- `test/test_phase4.jl`
- `test/test_preference_channels.jl` (new)

## Sources Used

- `potential references/Finkelstein_Luttmer_Notowidigdo2013.txt`
- `potential references/Reichling_Smetters2015.txt`
- `docs/channel_implementation_spec.md`
- `src/bellman.jl`
- `src/solve.jl`
- `src/utility.jl`
- `src/parameters.jl`
- `scripts/run_shapley_decomposition.jl`
