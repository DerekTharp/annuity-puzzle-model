# JRI Reframe — Locked Decisions and Plan

Working reference for the decomposition-led Journal of Risk and Insurance paper.
Decisions here are locked unless the production re-solve contradicts them, in which
case the data win (see Stage 6 gate). Branch: `jri-reframe` (baseline `6c8c352`).

## Target

Journal of Risk and Insurance. Decomposition-led structural paper. Model 2 (UK
reduced-form transport) cut entirely.

## Headline contribution

Prior sequential decompositions (Pashchenko) are order-dependent and can yield
contradictory channel rankings depending on entry order. An exact Shapley
decomposition is order-independent; combined with a gamma-robustness analysis it
delivers the first order-independent, preference-stable ranking of the channels
that suppress voluntary annuity demand.

The level of predicted ownership is gamma-fragile (the extensive-margin indicator
jumps across gamma); the *ranking* is not. That gap is the paper's reason to exist,
not a liability.

## Provisional headline sentence (Stage 0; lock at Stage 6 against re-solve)

"Pricing loads dominate, with survival pessimism and correlated health/mortality
risk as the co-leading secondary suppressors."

Source: 9-channel Shapley (`shapley_nine.tex`, OLD calibration chi_LTC=0.70):
Loads +26.8, Pessimism +12.2, Medical+R-S +11.4, SS -26.4 (negative = pro-annuity
crowd-out direction in the game), Bequests +5.2, Age needs +4.9.

The brief's earlier headline ("loads + correlated health/mortality dominate") is
FALSE at production calibration: pessimism is rank-2, not Med+R-S. Write the
abstract to the output, not the brief.

## Ranking-robustness evidence (resolves the JRI referee's killer objection)

The Shapley is computed on the discontinuous ownership indicator (jumps
0/6.68/25.44% across gamma=2.0/2.5/3.0). Cross-check recomputing the 9-channel
Shapley on the CONTINUOUS mean-alpha from the existing enumeration (zero new
solves):

- Ownership ranking:  Loads > Pessimism > Medical+R-S > Bequests > Age needs > ...
- Mean-alpha ranking: Loads > Pessimism > Medical+R-S > Bequests > Age needs > ...
- Spearman rank correlation: 0.950

Same top-3 in the same order on both statistics. The ranking survives the choice
of statistic. (Numbers at OLD calibration; reconfirm at re-solve.)

## Rank-2/rank-3 order flips between games (handle in prose)

- 9-channel game (HEADLINE): Pessimism (+12.2) > Medical+R-S (+11.4)
- 11-channel game (APPENDIX, adds SDU/PED): Medical+R-S (+15.4) > Pessimism (+5.5)

Adding the two behavioral channels redistributes attribution and flips rank-2/3.
The headline is the 9-channel game; the appendix reports the 11-channel game. The
manuscript must not present these two orderings as if interchangeable.

## Behavioral channels (SDU, PED) — RETAINED as robustness (user decision)

Demoted, not deleted. They stay in the code, in a robustness subsection (equations
to appendix), and in the 11-channel / 2048-subset Shapley (appendix table).

- SDU = source-dependent utility, lambda_W = 0.625 (portfolio-drawdown spending
  valued below income-stream spending).
- PED = purchase-event disutility / narrow-framing penalty, psi = 0.05 (one-time
  loss-aversion hit at the moment of purchase).

Why demoted: (1) parameters are exploratory, not moment-matched (the
Chalmers-Reuter SMM target proved infeasible); (2) their Shapley magnitudes are
mechanically huge (11-ch: PED +42.8, SDU -30.3) because PED single-handedly drives
ownership toward zero, which would dominate any decomposition for arithmetic, not
economic, reasons.

Required framing in the manuscript: one explicit sentence up front defusing the
PED/SDU magnitudes (large because PED mechanically zeroes ownership and is not
identified; that is why they sit in robustness). Upside bought: the structural
top-3 ranking is shown stable whether or not behavioral is bolted on, reinforcing
order-independence.

## The ONE production AWS re-solve (six results-movers, all committed before launch)

1. Config reconciliation: c_floor default 3000->6180, health_utility default
   ->[1.0,0.92,0.82].
2. CHI_LTC 0.70->0.49 (Ameriks 2011 JF C_PC/C_f ratio; delete fabricated
   "Ameriks 2020 ECMA central 0.5 CI[0.3,0.7]" comment).
3. Observed SS+DB income plumbing: SS_QUARTILE_LEVELS=[12918,15747,19298,19335];
   add SS_OBS=[9160,9657,9989,10388], DB_OBS=[3757,6090,9309,8947].
4. SS-only-cut accounting in run_ss_robustness.jl (cut SS, DB survives).
5. run_ss_robustness.jl chi_ltc/lambda_w/psi kwarg fix (was running LTC off).
6. theta-recalibration keyed to gamma=2.5 (recalibrate_theta_dfj).

A second production re-solve is a process failure (the 32-phase results-chasing
pattern). Everything else is local and off the critical path.

## Kill-criterion

If mean-alpha still oscillates at the fine (401,160) grid with no frac_at_kink
mechanism explaining it, withdraw the ranking-only paper in favor of a methods
note. The Stage 3 local diagnostic settles this BEFORE the AWS spend.

## Stage status

- Stage 0 (decisions doc): DONE (commit bfc148f).
- Stage 1 (config lock): DONE.
  - Calibration lock (chi_LTC 0.49, observed SS+DB floor, citation fixes,
    test_config_consistency.jl 27/27): commit bfc148f.
  - Model 2 (UK reduced-form transport) excised entirely (7 files): this commit.

### Stage-1 deviations from the master plan (verified, intentional)
- Struct defaults (parameters.jl: c_floor=3000, health_utility=[1,1,1]) were NOT
  changed. Every production solve path passes c_floor/health_utility explicitly
  via config constants; the only bare-constructor callers are survival/grid
  builders and the Lockwood/Pashchenko replications, which must inherit the
  neutral defaults to reproduce published numbers. test_config_consistency.jl
  guards the neutral defaults.
- Two welfare counterfactuals ("Default architecture (no transport)",
  "Default + group pricing") were dropped during the Model-2 excision: they
  existed only to express the wedge-vs-no-wedge contrast, which no longer exists,
  and were not referenced by name in code. Welfare set is now 12 configs.

## Stage 2 (results-mover code edits): DONE

- src/subset_enum.jl: extracted bitmask_to_channels / build_subset_config /
  exact_shapley (shared by enumeration + gamma-stability). test_subset_enum.jl
  29/29.
- frac_at_kink diagnostic in wtp.jl, threaded through both solve_and_evaluate
  signatures. test_frac_at_kink.jl 7/7.
- run_ss_robustness.jl: SS-only cut (DB survives) + chi_ltc kwarg fix.
- New scripts (all coarse-verified): run_shapley_gamma_stability.jl,
  run_ss_cut_by_wealth.jl, diagnose_gamma_oscillation.jl (env-overridable grids).
- run_all.jl: Stages 10b (gamma-stability) and 11b (DB-cushion) wired.
- grid_convergence_joint.jl: gamma un-hardcoded (ANNUITY_GAMMA env).

### Stage-2 deviation from the master plan (verified, intentional)
- theta-recalibration mover DROPPED. recalibrate_theta_dfj (power-law
  theta^(gamma/2) -> 156.5 at gamma=2.5) is dead code; applying it would blow the
  bequest-to-wealth ratio far past target. The project's portability check
  (bequest_recalibration.csv) shows the ratio moves only 0.173 -> 0.196 from
  gamma=2.0 to 2.5 (13.6% < 20% retarget threshold), so theta=56.96 is portable
  and is held fixed across the gamma sweep (with that caveat noted in the
  exhibit). Third plan-mover eliminated by verification (after struct defaults
  and behavioral-as-headline). The only baseline re-solve movers are CHID_LTC
  and SS+DB, both already committed.

### Coarse-grid verification signals (production will confirm at fine grid)
- gamma-stability: Spearman(ownership-rank, mean-alpha-rank) = 0.983 — the
  ranking is robust to the value statistic, answering the JRI referee's killer
  objection.
- diagnose_gamma_oscillation: mean_alpha rises monotonically (0.000 -> 0.042 ->
  0.101) across gamma=2.0/2.5/3.0 while the ownership indicator jumps
  (0/17/23%). The kill-criterion is NOT triggered: the level fragility is an
  extensive-margin indicator effect, not model instability.
- WATCH: at corrected calibration (chi_ltc=0.49, observed SS+DB), the coarse
  9-channel ranking shows Loads > Medical+R-S > Pessimism (rank-2/3 vs the old
  Loads > Pessimism > Med+R-S). Lock the headline sentence at Stage 6 against the
  production numbers. Also WATCH: the DB-cushion response increases with wealth
  at coarse grid (richer = more to annuitize), so the "cushion shrinks response
  toward the top" framing may need reworking after production.

## Next: Stage 3 (local diagnose + pre-flight)
Run diagnose_gamma_oscillation.jl at (101,80) and (201,160) fine grids (via
ANNUITY_NW/ANNUITY_NALPHA) to settle artifact-vs-economic before the AWS run;
confirm all six results-movers (now four: CHID_LTC, SS+DB, run_ss_robustness
fixes, behavioral-off) committed; pre-flight checklist.
