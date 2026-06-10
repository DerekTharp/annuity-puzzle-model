# JRI Paper Narrative — the five classes of insight (spine for manuscript surgery)

This is the agreed narrative arc for the paper. The manuscript surgery (Task 14)
builds the abstract, introduction, results, and discussion around exactly these
five classes, in this order. Author-endorsed framing — do not dilute it.

Each class is annotated with the production stage that confirms it and a
LIVE-EVIDENCE line tracking what the in-progress AWS run has shown so far.
"Pending" = the confirming stage has not produced output yet; the framing is a
prediction until it does. The order-INDEPENDENT Shapley (Stage 10) is the
headline; everything seen before it is the ordering-dependent preview.

---

## 1. Which frictions actually do the work — settled, not asserted

The headline and the genuinely novel piece. Six decades of literature produced
contradictory "dominant channel" claims: Lockwood says bequests,
Reichling-Smetters say correlated health/mortality risk, Mitchell et al. point at
loads, Pashchenko's sequential decomposition gives different answers depending on
the order channels enter. The exact Shapley dissolves that dispute by showing the
order-dependence WAS the disagreement: every prior decomposition was implicitly
path-dependent, and once you average over all 512 entry orders, the ranking is
loads first, with survival pessimism and correlated health/mortality risk as the
second tier — and that ranking holds across risk aversion, across the
ownership-vs-mean-alpha statistic, and (post-fix) across wealth quartiles.
Bequests, the most-cited explanation in the literature, land mid-pack. A citable
adjudication of a 20-year argument, not another entry in it.

- Confirmed by: Stage 10 (subset_enumeration.csv -> shapley_exact / shapley_nine),
  Stage 10b (shapley_gamma_stability), shapley_by_wealth (Stage 10).
- LIVE EVIDENCE (sequential preview, ordering-dependent): Loads -39.5pp >>
  Survival pessimism -20.3pp ~ R-S health-mortality -15.1pp; bequests 0.0pp in
  position. Magnitudes already in the predicted order. Shapley (order-independent)
  pending.

## 2. The puzzle is mostly pre-existing annuitization plus compounding

The mixed-sign structure the audit flagged becomes, presented honestly, the
economic story. SS+DB is the largest-magnitude force in the game: most single
retirees are already 60-75% annuitized before they ever see a SPIA quote, so the
marginal value of private annuitization is small — and then the suppressors don't
need to be individually large, because they compound. The pairwise-interaction
matrix quantifies this: loads alone are survivable, bequests alone are survivable,
but loads applied to the thin surplus left after crowd-out and bequests eliminate
it. There was never a single explanation to find — the literature's serial failure
to crown one channel IS the finding.

- Confirmed by: Stage 10 (SS Shapley magnitude; pairwise_interactions_exact.csv),
  the pre-existing annuitization share from SS_OBS+DB_OBS vs wealth.
- LIVE EVIDENCE: in the sequential ordering SS moves ownership +53.5pp (the single
  largest step, 46.5% -> 100% at fair pricing) — confirms SS as the dominant
  force. Pairwise matrix computing now (Stage 2 tail). Compounding claim pending
  the matrix.

## 3. The puzzle is a top-quartile phenomenon — reframes whose problem it is

The by-wealth decomposition shows predicted ownership essentially zero for the
bottom half of the wealth distribution and concentrated in the top quartile. The
bottom quartiles aren't "puzzlingly" failing to annuitize — they're rationally
excluded (already nearly fully annuitized via SS, below the $10k minimum purchase,
holding precautionary liquidity against the Medicaid floor). The welfare question
replaces the aggregate puzzle: the CEV map identifies who would gain (single,
healthy, wealthy, weak bequest motive) and shows CEV ~ 0 for nearly everyone else.
Redirects the research program exactly as the companion survey argues.

- Confirmed by: shapley_by_wealth.csv + subset_enumeration own_q columns (Stage
  10); CEV grid (Stage 6, done).
- LIVE EVIDENCE: coarse de-risk run showed Q1=0, Q2=0, Q3=1.1%, Q4=83.8%.
  Production by-wealth pending Stage 10. Aggregate 6.2% with the steep gradient is
  consistent with concentration persisting.

## 4. Policy comparative statics with distributional teeth

The 2033 trust-fund scenario: a 23% SS-only cut raises private annuity demand
monotonically — but the response is concentrated among the WEALTHY, who need the
substitution least. The households most exposed to the cut cannot substitute into
private annuities at all — too little wealth, minimum-purchase barrier, binding
floor. Privatized longevity insurance does not backfill a public cut where the cut
bites. Supply vs demand levers: the counterfactual grid ranks interventions —
group pricing (MWR 0.90), correcting survival pessimism, real annuities, and their
interactions — telling you which margin (pricing, beliefs, product design) moves
demand and welfare most per unit of policy effort.

- Confirmed by: ss_cut_robustness (Stage 11), ss_cut_by_wealth (Stage 11b),
  welfare_counterfactuals (Stage 7, done).
- LIVE EVIDENCE: Stage 7 counterfactuals ran (e.g. eliminate survival pessimism ->
  24.9%). DB-cushion by-wealth pending Stage 11b; coarse run confirmed the
  response INCREASES with wealth (the corrected DB-cushion direction).

## 5. A methodological lesson the literature needs

The level/ranking split is itself a contribution: predicted participation in
calibrated lifecycle models is knife-edged — it jumps across gamma while mean
alpha moves smoothly, because the extensive margin sits on a fixed-cost /
minimum-purchase threshold. That explains, in one mechanism, why Lockwood
predicted ~5%, Pashchenko ~20%, and Peijnenburg full annuitization from broadly
similar models. The field implication: stop staking claims on predicted ownership
levels; rankings and comparative statics are the stable objects. The frac_at_kink
diagnostic (split into contractual-vs-grid components) is the evidence that this
is economics, not numerics.

- Confirmed by: shapley_gamma_stability_summary (Stage 10b: full ownership by
  gamma + top-k concordance), gamma_oscillation_diagnostic, frac_at_kink_contract.
- LIVE EVIDENCE: coarse runs showed mean_alpha monotone in gamma while ownership
  jumped (kill-criterion clear). Production gamma sweep pending Stage 10b.

---

## What it cannot tell you (state crisply in Discussion)

No supply side or equilibrium pricing response; one-shot decision at 65 (no
deferred/gradual purchase timing); singles only (no Kotlikoff-Spivak
intra-household insurance); housing absent from the decision; the SS cut is an
anticipated permanent level shift, not transition uncertainty; the model does not
pin the ownership level (by design). The behavioral channels remain exploratory —
their honest role is the robustness statement that even mild narrow-framing
annihilates the small residual structural demand without disturbing the ranking.

## The arc (one paragraph, for the intro and the abstract)

The survey paper argued qualitatively that the puzzle dissolves; this model proves
it quantitatively WITHOUT needing the level to match — the channels rank stably,
they compound, the remaining demand is rationally concentrated where the welfare
stakes are, and the interesting question left standing is distributional, not
aggregate.
