# Introduction

Yaari (1965) established one of the sharpest predictions in consumer theory: an individual facing uncertain lifetime, with no bequest motive and access to actuarially fair annuities, should convert all wealth into a life annuity. The mortality credit, the return premium financed by redistributing wealth from decedents to survivors, dominates any asset with the same underlying return. Davidoff et al. (2005) extended this result to incomplete markets, showing that partial annuitization remains optimal under a wide range of conditions. Yet observed voluntary annuity ownership among single US retirees aged 65–69 is only a few percent: $`3.11\%`$ on the cleaner HRS lifetime annuity contract indicator (q286 series) and $`5.21\%`$ on the conventional any-annuity income proxy used in prior literature (Lockwood 2012; Dushi and Webb 2004; Poterba et al. 2011).[^3] A companion survey (Tharp 2025) argues that the accumulated evidence from six decades of research substantially accounts for low aggregate annuity demand, but identifies the absence of a unified structural model incorporating all empirically relevant channels as the gap preventing a unified quantitative resolution. This paper supplies that model.

Six decades of research proposed partial explanations for this gap, and the standard tool for adjudicating among them—the sequential decomposition, in which channels are switched on one at a time and the resulting drop in predicted ownership is attributed to each—returns an answer that depends on the order of entry. Lockwood (2012) emphasized bequest motives; Reichling and Smetters (2015) the correlation between health shocks and mortality; Mitchell et al. (1999) and others pricing loads. Because the channels interact, the ranking such a decomposition produces is path-dependent: the same model can crown different dominant frictions depending on which channel enters late, when little surplus remains to attribute. The disagreement in the literature was, in part, an artifact of the decomposition method.

This paper nests nine rational and preference channels in a single calibrated lifecycle model—pre-existing Social Security annuitization, bequest motives, combined medical-expenditure risk and the Reichling and Smetters (2015) health-mortality correlation, subjective survival pessimism (O’Dea and Sturrock 2023), pricing loads, inflation erosion, public-care aversion (Ameriks et al. 2011, 2020), age-varying consumption needs (Aguiar and Hurst 2013), and state-dependent utility (Finkelstein et al. 2013)—and attributes the annuity-demand gap with exact Shapley values computed over all $`2^{9} = 512`$ channel subsets. The Shapley value averages each channel’s marginal contribution across every entry order, so the attribution is order-independent by construction. Where a sequential decomposition reports one of many possible rankings, the Shapley reports a unique attribution given the channel partition and outcome statistic.

Within this game, the ranking is clear. Pricing loads are the dominant suppressor, contributing 31.4 percentage points of the total demand reduction. Subjective survival pessimism (10.9 pp) and the combined medical and Reichling and Smetters (2015) health-mortality channel (9.4 pp) form the co-leading second tier. Bequest motives—the single most-cited explanation for the puzzle—contribute 5.8 pp, mid-pack. Social Security carries a large negative Shapley value ($`-21.1`$ pp): it is the largest-magnitude demand-boosting force, raising annuitization at the margin rather than suppressing it, because the public income floor it provides is what makes a private annuity feasible. Most single retirees are already substantially annuitized through Social Security before they face a private annuity decision, so the marginal value of additional annuitization is small, and the suppressing channels need not be individually large because they compound on a thin remaining surplus.

The ranking is robust where the predicted level is not. The level is knife-edged in risk aversion: predicted ownership moves from 0.0% to 21.9% as $`\gamma`$ ranges over $`[2.0, 3.0]`$, because the extensive margin sits on a fixed-cost and minimum-purchase threshold that the population crosses discontinuously. The same fragility plausibly explains why broadly comparable models in the literature have predicted ownership anywhere from a few percent to full annuitization. The channel ranking, by contrast, is stable: pricing loads remain the top suppressor at all 5 values of $`\gamma`$ and in every one of the 4 wealth quartiles, and the ranking is unchanged whether attribution is computed on the discontinuous ownership indicator or the continuous mean-purchase share (suppressor rank correlation 1.00). The methodological implication is that in calibrated annuity models the predicted participation *level* is the wrong object on which to stake claims. Rankings and comparative statics are the stable, reportable quantities.

Resolving the attribution reframes the puzzle as distributional. Predicted ownership concentrates entirely in the top wealth quartile (33.5%) and is essentially zero below it (0.0% in the bottom quartile). The bottom half of the distribution poses no behavioral puzzle. These households are rationally excluded: already near-fully annuitized through Social Security, below the minimum-purchase threshold, and holding precautionary liquidity against the Medicaid consumption floor. The policy counterfactuals inherit this structure. A 23% Social Security cut, approximating the projected OASI shortfall when the trust fund depletes in 2033 (Board of Trustees, Federal Old-Age and Survivors Insurance and Federal Disability Insurance Trust Funds 2025), raises predicted private annuity demand, but the response is concentrated among the wealthy: top-quartile ownership rises from 33.5% to 46.3%, while the households the cut most exposes show no response at all (0.0%). Privatized longevity insurance does not backfill a public benefit cut where the cut bites hardest.

The cross-sectional implications of the ranking are testable in the same data used to discipline the model. In pooled HRS samples of single retirees aged 65–69, ownership rises with wealth, falls with poor health, and falls with pre-existing annuitized income conditional on wealth: 5 of the 7 channel-implied signs are reproduced. The two that are not come from the expectation-based channels (subjective survival and bequest intention), whose survey proxies are confounded in ways the structural calibration is designed to bypass.

Relative to prior multi-channel papers, the present model broadens the channel set and changes the attribution. Pashchenko (2013) jointly considered Social Security, bequests, minimum purchase requirements, and pricing frictions, but not the Reichling–Smetters health-survival mechanism, subjective survival pessimism, or age-varying needs. Peijnenburg et al. (2016) emphasized incomplete markets and background risk, concluding that the annuity puzzle remains unresolved in their framework. This paper shows that pricing, correlated health and mortality risk, and late-life expenditure decline are quantitatively central once evaluated in a common model.

The welfare results follow the same distributional logic. Under current pricing the gain from annuity-market access is small across the wealth distribution, because most calibrated households optimally do not annuitize; access is approximately welfare-neutral. The interventions that generate larger gains are those that change the optimal choice: group annuity pricing (MWR $`= 0.90`$) on the supply side, and demand-side default architecture, drawing on the broader evidence that defaults strongly shape retirement-saving choices (Madrian and Shea 2001), which operate on separate margins.

The paper makes three contributions. First, it shows that the order-dependence of prior sequential decompositions was itself a source of their disagreement, and delivers an order-independent, preference-stable ranking of the channels that suppress voluntary annuity demand: pricing loads dominate, with survival pessimism and correlated health-mortality risk as the co-leading second tier and bequest motives mid-pack. Second, it establishes the level/ranking distinction as a methodological discipline for calibrated annuity models: the predicted participation level is fragile across risk aversion and grid resolution, while the ranking and the policy comparative statics are stable. Third, it reframes the annuity puzzle from an aggregate behavioral anomaly into a distributional question, identifying which households are rationally excluded from annuitization and which reforms would make it welfare-improving for the rest. Two exploratory behavioral channels (source-dependent utility and a narrow-framing at-purchase penalty) are reported separately as a literature-magnitude robustness exercise. They do not disturb the structural ranking.

These results shift the question away from whether retirees irrationally fail to annuitize and toward a more policy-relevant one: which channels suppress annuity demand most, and which market reforms would make annuitization welfare-improving for particular households?

Section <a href="#sec:model" data-reference-type="ref" data-reference="sec:model">2</a> specifies the model. Section <a href="#sec:calibration" data-reference-type="ref" data-reference="sec:calibration">3</a> describes the calibration. Section <a href="#sec:results" data-reference-type="ref" data-reference="sec:results">4</a> presents the decomposition, counterfactuals, and welfare analysis. Section <a href="#sec:robustness" data-reference-type="ref" data-reference="sec:robustness">5</a> reports sensitivity checks. Section <a href="#sec:discussion" data-reference-type="ref" data-reference="sec:discussion">6</a> discusses limitations. Section <a href="#sec:conclusion" data-reference-type="ref" data-reference="sec:conclusion">7</a> concludes.

# Model

## Environment

Time is discrete. An individual enters at age 65 (period $`t = 1`$) and may survive to a maximum age of 110 (period $`T = 46`$). At $`t = 1`$, the individual makes a single irreversible decision: what fraction $`\alpha \in [0, 1]`$ of initial liquid wealth $`W_0`$ to convert into a single premium immediate annuity (SPIA). The remaining wealth $`(1 - \alpha)W_0`$ stays liquid. In each subsequent period, the individual chooses consumption $`c_t`$ from available resources.

The state at each period $`t`$ is characterized by four variables: liquid wealth $`W_t \geq 0`$, annuity income $`A`$ (fixed after the age-65 purchase), health status $`H_t \in \{1, 2, 3\}`$ (Good, Fair, Poor), and age $`t`$. Social Security income $`\text{SS}(t)`$ is received exogenously in each period and is not a decision variable.

## Preferences

The individual maximizes expected discounted lifetime utility. Flow utility over consumption takes the constant relative risk aversion (CRRA) form:
``` math
\begin{equation}
\label{eq:utility}
u(c) = \frac{c^{1-\gamma}}{1-\gamma}, \quad \gamma > 0, \quad \gamma \neq 1.
\end{equation}
```
The coefficient of relative risk aversion $`\gamma`$ governs both risk aversion and the elasticity of intertemporal substitution.

Bequest utility follows the De Nardi–French–Jones specification, which nests bequests as a luxury good:
``` math
\begin{equation}
\label{eq:bequest}
v(b) = \theta \frac{(b + \kappa)^{1-\gamma}}{1-\gamma},
\end{equation}
```
where $`b`$ is bequeathable wealth (liquid wealth at death; annuity income ceases), $`\theta \geq 0`$ controls bequest intensity, and $`\kappa > 0`$ is a shifter that determines the degree to which bequests are a luxury good (De Nardi 2004). When $`\kappa`$ is large relative to typical wealth levels, the marginal utility of bequests is nearly flat for low-wealth individuals and declines steeply for the wealthy. This specification, estimated by Lockwood (2012) using Health and Retirement Study (HRS) data, captures the empirical pattern that bequest motives are concentrated among high-wealth households.

The parameters $`\theta`$ and $`\kappa`$ must be interpreted jointly. With the DFJ luxury-good calibration ($`\theta = 56.96`$, $`\kappa = \$272{,}628`$), an individual with \$50,000 in wealth faces negligible marginal bequest utility, while an individual with \$1,000,000 faces strong resistance to annuitizing. Combining this $`\theta`$ with a small $`\kappa`$ (e.g., \$10, the homothetic specification) produces pathological results: extreme marginal bequest utility near $`b = 0`$ acts as a precautionary buffer rather than a genuine bequest motive, anomalously *increasing* predicted ownership above the no-bequest case.[^4] The DFJ estimates from Lockwood (2012) are jointly calibrated to HRS bequest data; using one parameter with the other replaced is not a valid counterfactual.

The bequest channel’s isolated effect on ownership is modest under the DFJ specification (100% retention rate in the sequential decomposition) because the luxury-good $`\kappa`$ makes the bequest motive nearly irrelevant for the median retiree in the HRS sample. The 100% retention rate in the sequential decomposition reflects the ordering: bequests are added when ownership is already 100% (steps 0–1 include only SS). In the full nine-channel structural model, removing bequests raises ownership from 7.9% to 26.1% (Table <a href="#A-tab:full_robustness" data-reference-type="ref" data-reference="A-tab:full_robustness">[A-tab:full_robustness]</a>), because bequests interact with pricing loads and inflation to suppress demand for agents near the annuitization margin. The Shapley decomposition, which averages over all orderings, assigns bequests a value of 5.8 pp (15% share).

The individual discounts future utility at rate $`\beta`$ per period.

## Health dynamics and mortality

Health follows a first-order Markov process with three states: Good ($`H = 1`$), Fair ($`H = 2`$), and Poor ($`H = 3`$). Transition probabilities are age-dependent and calibrated to HRS panel data following De Nardi et al. (2010):
``` math
\begin{equation}
\Pr(H_{t+1} = h' \mid H_t = h, \text{age} = t) = \pi(h, h', t).
\end{equation}
```

Mortality depends on health through a proportional hazard specification. Baseline survival probabilities $`s_{\text{base}}(t)`$ come from the SSA period life table used by Lockwood (2012). Health adjusts survival through:
``` math
\begin{equation}
\label{eq:survival}
s(t, H) = s_{\text{base}}(t)^{\mu(H, t)},
\end{equation}
```
where $`\mu(H, t)`$ is a health- and age-specific hazard multiplier with $`\mu(\text{Good}, t) < 1 < \mu(\text{Poor}, t)`$ and $`\mu(\text{Fair}, t) = 1`$. This specification maps directly to proportional hazards: if the baseline hazard is $`\lambda_{\text{base}}(t) = -\ln s_{\text{base}}(t)`$, then the adjusted hazard is $`\mu(H, t) \cdot \lambda_{\text{base}}(t)`$.

The baseline specification uses constant hazard multipliers $`\mu = [0.50, 1.0, 3.75]`$ for Good, Fair, and Poor health respectively, set above the HRS self-reported age-band estimates toward the steeper functional-limitation gradient of Reichling and Smetters (2015). The health-mortality gradient compresses with age: the Poor-to-Fair hazard ratio falls from 3.29 at ages 65–74 to 2.77 at 75–84 to 1.82 at 85+. Section <a href="#sec:robustness" data-reference-type="ref" data-reference="sec:robustness">5</a> reports results across the empirical range of multiplier specifications.

The age-varying multipliers are the mechanism underlying the Reichling and Smetters (2015) result. A negative health shock simultaneously increases mortality ($`\mu(\text{Poor}, t) > 1`$ reduces expected remaining annuity payments) and, through the medical expenditure process described below, increases the need for liquid wealth. The annuity becomes “valuation-risky”: it loses value in precisely the states where liquidity is most valuable. The effect is strongest at younger ages where the gradient is widest, which matters because the annuitization decision is made at age 65.

## Subjective survival beliefs

O’Dea and Sturrock (2023) document that individuals aged 65–69 underestimate their survival probability at age 75 by approximately 15 percentage points relative to actuarial tables (subjective $`\Pr(\text{survive to 75}) \approx 0.71`$ versus actuarial 0.86). This pessimism reduces the perceived value of annuities by overweighting the probability of dying before recovering the premium.

The model allows the agent’s subjective survival probabilities to differ from the objective rates used by the insurer to price annuities:
``` math
\begin{equation}
\label{eq:pessimism}
s^{\text{subj}}(t, H) = \psi \cdot s(t, H), \quad \psi \in (0, 1].
\end{equation}
```
The parameter $`\psi`$ scales each one-year survival probability downward. The annuity is priced using the objective survival rates $`s(t, H)`$; only the agent’s Bellman equation uses $`s^{\text{subj}}`$. A per-year factor of $`\psi = 0.960`$ implies subjective 10-year survival of $`\psi^{10} \approx 0.66`$ times the objective rate, a degree of pessimism consistent with the survival-underestimation evidence of Heimer et al. (2019), Payne et al. (2013), and O’Dea and Sturrock (2023). It is somewhat stronger than the mild per-year discount the O’Dea–Sturrock 10-year ratio implies on its own ($`(0.71/0.86)^{1/10} \approx 0.98`$); Section <a href="#sec:robustness" data-reference-type="ref" data-reference="sec:robustness">5</a> reports sensitivity across $`\psi`$, including that value. When $`\psi = 1`$, beliefs are objective and this channel is inactive.

## Medical expenditures

Out-of-pocket medical expenditures depend on age and health. Log medical spending follows:
``` math
\begin{equation}
\label{eq:medical}
\ln m_{t} = \mu_m(t, H_t) + \sigma_m(t, H_t) \cdot \varepsilon_t, \quad \varepsilon_t \sim N(0, 1),
\end{equation}
```
where $`\mu_m`$ and $`\sigma_m`$ are the mean and standard deviation of log expenditures, both age- and health-dependent. The baseline calibration matches the age profiles reported by Jones et al. (2018): mean out-of-pocket spending of \$4,201 at age 70, rising to \$29,703 at age 100, with a 95th percentile of approximately \$111,509 at age 100.

A Medicaid safety net provides a consumption floor $`\underline{c}`$. If total resources (wealth plus income minus medical costs) fall below $`\underline{c}`$, the government covers the shortfall. The individual consumes $`\underline{c}`$ and enters the next period with zero liquid wealth. This floor is calibrated to the SSI federal benefit rate plus average state supplement for an elderly individual (\$6,180, following the value used in (Lockwood 2012)).

Expectations over medical expenditure shocks are computed using nine-node Gauss–Hermite quadrature. At the calibrated variance ($`\sigma \approx 1.4`$), lower-order rules place insufficient weight in the tails of the lognormal distribution; Appendix <a href="#A-app:quadrature" data-reference-type="ref" data-reference="A-app:quadrature">[A-app:quadrature]</a> documents the convergence diagnostics.

## Annuity pricing

The annuity is nominal: the insurer prices the stream of nominal payments using the nominal discount rate $`r_{\text{nom}} = (1+r)(1+\pi) - 1`$, where $`r`$ is the real interest rate and $`\pi`$ is the inflation rate. The actuarially fair annual payout per dollar of premium is:
``` math
\begin{equation}
\text{payout}_{\text{fair}} = \frac{1}{\sum_{k=0}^{T-1} \frac{\prod_{j=0}^{k-1} s_{\text{base}}(j)}{(1+r_{\text{nom}})^k}}.
\end{equation}
```
The nominal discount rate reflects the insurer’s investment in nominal bonds. The resulting initial payout is higher than under real discounting, but the consumer’s real income from the annuity declines each period:
``` math
\begin{equation}
A_t^{\text{real}} = \frac{A_1}{(1 + \pi)^{t-1}},
\end{equation}
```
where $`\pi`$ is the annual inflation rate. At $`\pi = 2\%`$, purchasing power falls by 39% over 25 years.

When $`\pi = 0`$ (the Yaari benchmark and intermediate decomposition steps where inflation is inactive), $`r_{\text{nom}} = r`$ and the pricing reduces to the standard real-annuity formula.

The annuity is priced with a money’s worth ratio (MWR), defined as the expected present value of payouts per dollar of premium. The loaded payout rate is $`\text{MWR} \times \text{payout}_{\text{fair}}`$. I set MWR $`= 0.87`$ at baseline, consistent with the population-table estimates of Mitchell et al. (1999) for the US individual annuity market. This choice merits discussion. Mitchell et al. (1999) estimated MWRs of 0.80–0.85 using population mortality tables, which is the relevant benchmark for an individual considering annuitization (the “money’s worth” of the purchase against population life expectancy). Using annuitant mortality tables—which adjust for selection—yields higher MWRs of 0.90–0.94, but this overstates the value proposition for the marginal non-annuitant. More recent estimates from Wettstein et al. (2021) suggest some improvement, with population-table MWRs around 0.85. Section <a href="#sec:robustness" data-reference-type="ref" data-reference="sec:robustness">5</a> reports full sensitivity: at MWR $`= 0.85`$, predicted ownership rises to 2.1%; at MWR $`= 0.90`$, to 11.5%. The steep sensitivity to MWR is itself a finding—it identifies pricing as the most actionable policy lever.

A fixed cost of \$2,500 is incurred upon any purchase.[^5]

## Budget constraint

Within each period, the timing is:

1.  The individual enters with liquid wealth $`W_t`$, annuity income $`A_t`$, Social Security $`\text{SS}(t)`$, and health $`H_t`$.

2.  Medical expenditure $`m_t`$ is realized.

3.  The individual chooses consumption $`c_t`$.

4.  Remaining wealth earns the risk-free return $`r`$.

5.  Health transitions to $`H_{t+1}`$.

6.  The individual survives to $`t+1`$ with probability $`s(t, H_t)`$.

The intertemporal budget constraint is:
``` math
\begin{equation}
\label{eq:budget}
W_{t+1} = (1 + r)(W_t + A_t + \text{SS}(t) - m_t - c_t),
\end{equation}
```
subject to $`c_t \geq \underline{c}`$ and $`W_{t+1} \geq 0`$ (no borrowing).

## Age-varying consumption needs

Aguiar and Hurst (2013) document that consumption expenditure declines at roughly 2% per year in retirement, even among wealthy households, once time costs and home production are accounted for. This decline reflects changing consumption needs—reduced transportation, clothing, and food-away-from-home expenditures—rather than binding liquidity constraints. The declining profile reduces the value of late-life income streams, including annuities.

The model captures this through an age-dependent weight on flow utility:
``` math
\begin{equation}
\label{eq:age_needs}
w(t) = (1 - \delta_c)^{t-1}, \quad \delta_c = 0.02,
\end{equation}
```
where $`t = 1`$ at age 65. Flow utility becomes $`w(t) \cdot u(c)`$. This specification is equivalent to an age-dependent felicity shifter: as consumption needs decline, the marginal value of additional consumption in late life falls, reducing the insurance value of an annuity that provides a level real income stream. When $`\delta_c = 0`$, this channel is inactive and the model reduces to the standard time-separable case.

Age-varying consumption needs should be distinguished from time preference ($`\beta`$). The discount factor $`\beta`$ governs the rate at which future utility is discounted; $`w(t)`$ governs how much utility a given level of consumption generates at each age. A constant $`\beta`$ with declining $`w(t)`$ implies that the individual values future consumption opportunities but needs less consumption to achieve the same felicity as she ages.

## State-dependent utility

Finkelstein et al. (2013) estimate that the marginal utility of consumption declines with poor health, with a central estimate implying that individuals in poor health value a dollar of consumption roughly 10–25% less than those in good health. Reichling and Smetters (2015) incorporated this channel in their annuity model. State-dependent utility reduces annuity demand because the annuity delivers income in poor-health states where its marginal utility is lower.

The model allows the marginal utility of consumption to depend on health status through a multiplicative weight:
``` math
\begin{equation}
\label{eq:state_dependent}
u(c, H) = \varphi(H) \cdot \frac{c^{1-\gamma}}{1-\gamma},
\end{equation}
```
where $`\varphi(\text{Good}) = 1.00`$, $`\varphi(\text{Fair}) = 0.92`$, and $`\varphi(\text{Poor}) = 0.82`$, the central midpoint of the Finkelstein et al. (2013) estimates, applied through the multiplicative state-dependent-utility approach of Reichling and Smetters (2015). When $`\varphi(H) = 1`$ for all $`H`$, this channel is inactive.

In practice, state-dependent utility has a negligible effect on predicted ownership (Shapley value of 0.4 pp). The channel is included for completeness and to confirm that its quantitative irrelevance, suggested by the prior literature, holds in the unified framework.

## Behavioral channels (exploratory)

The nine rational and preference-based channels above constitute the disciplined structural baseline. Two further behavioral channels are reported as exploratory extensions, layered onto the nine-channel baseline rather than substituted for it.

#### Source-dependent utility (SDU; exploratory).

Blanchett and Finke (2024, 2025) document that retirees apply a higher consumption rate to guaranteed income flows than to portfolio assets, consistent with the source-dependent utility framework of Shefrin and Thaler (1988) and Thaler (1999). The model captures this through a multiplicative discount on portfolio drawdowns:
``` math
\begin{equation}
\label{eq:sdu}
c_{\text{eff}}(t) = c_{\text{income}}(t) + \lambda_W \cdot c_{\text{portfolio}}(t), \quad \lambda_W \in (0, 1],
\end{equation}
```
where $`c_{\text{income}}`$ is consumption financed from annuity and Social Security income, $`c_{\text{portfolio}}`$ is consumption financed from liquid wealth drawdowns, and $`\lambda_W < 1`$ reflects the lower utility weight placed on portfolio-financed consumption. The production calibration sets $`\lambda_W = 0.625`$ as a literature-magnitude best guess: Blanchett and Finke (2024) report retirees spending at approximately 50% of the rate from portfolio assets compared with 80% from guaranteed income, implying $`\lambda_W = 50/80 = 0.625`$. This is an exploratory parameter anchored to a behavioral spending differential rather than moment-matched to a US annuitization moment; results across $`\lambda_W \in \{0.5, 0.625, 0.75, 0.85\}`$ are reported in Section <a href="#sec:robustness" data-reference-type="ref" data-reference="sec:robustness">5</a>.

#### Narrow-framing at-purchase penalty (PED; exploratory).

A cumulative-prospect-theory mechanism formalized by Hu and Scott (2007), with empirical support from Brown et al. (2008) and Chalmers and Reuter (2012), generates a per-period at-purchase disutility while the household’s running gain/loss tally on the SPIA is underwater. Letting $`\pi = \alpha W_0`$ denote the premium, $`A = \pi \cdot \rho`$ the annual annuity income at payout rate $`\rho`$, and $`t^* = \lceil 1/\rho \rceil + 1`$ the breakeven horizon, the model captures the penalty as the discounted, survival-weighted NPV of the loss-aversion stream:
``` math
\begin{equation}
\label{eq:ped}
\Delta V_{\text{purchase}} = -\psi_{\text{purchase}} \cdot u'(c_{\text{ref}}) \cdot \sum_{t=1}^{t^*} \beta^{t-1} \cdot S(t) \cdot \max\!\left(0,\, \pi - A(t-1)\right) \cdot \mathbf{1}(\alpha > 0),
\end{equation}
```
where $`c_{\text{ref}} = \$18{,}000`$ is a reference consumption level chosen so that $`\psi_{\text{purchase}}`$ has an interpretable scale, $`u'(c_{\text{ref}}) = c_{\text{ref}}^{-\gamma}`$ is the marginal utility of consumption at $`c_{\text{ref}}`$ (converting dollar-denominated underwater amounts to utility units), $`S(t)`$ is the cumulative survival probability to period $`t`$, and $`\beta`$ is the discount factor. The penalty applies once at age 65 over the underwater period of the SPIA; once cumulative payouts cross the premium (period $`t^*`$) the loss tally turns positive and the penalty vanishes. The production calibration sets $`\psi_{\text{purchase}} = 0.05`$ as a literature-magnitude best guess. The parameter is not moment-matched to a US annuitization target. Results across $`\psi_{\text{purchase}} \in \{0.01, 0.05, 0.09\}`$ are reported in Section <a href="#sec:robustness" data-reference-type="ref" data-reference="sec:robustness">5</a>. At the production magnitude the at-purchase penalty saturates—it eliminates participation for nearly all agents—so the eleven-channel specification is reported as an exploratory exercise illustrating where literature-magnitude behavioral parameters would push predictions, not as a moment-matched calibration.

#### Status of behavioral channels.

Both SDU and PED are exploratory rather than identified. The model could be moment-matched against a US annuitization target, but doing so would conflict with the out-of-sample comparison strategy used elsewhere in the paper (the structural baseline uses no US annuitization moment). The eleven-channel specification therefore shows what happens when these channels are introduced at literature magnitudes. The behavioral results below are reported as an exploratory sensitivity exercise rather than a within-model calibration of the behavioral primitives.

## Bellman equation

For $`t < T`$, the value function satisfies:
``` math
\begin{equation}
\label{eq:bellman}
\begin{split}
V(W, A, H, t) = \mathbb{E}_m \Big[ \max_{c} \Big\{ &w(t) \cdot u(c, H) \\
&+ \beta \, s(t, H) \, \mathbb{E}_{H'}\big[V(W', A', H', t+1) \mid H\big] \\
&+ \beta \, (1 - s(t, H)) \, v(W') \Big\} \Big],
\end{split}
\end{equation}
```
where the medical shock $`m`$ is realized at the start of the period and observed by the agent before the consumption choice, so the maximization over $`c`$ is taken conditional on $`m`$ and the outer expectation is over the medical-shock distribution. The state transition over health ($`H \to H'`$) occurs between periods after the consumption decision, so it enters as an inner expectation in the continuation. $`W' = (1+r)(W + A_t + \text{SS}(t) - m - c)`$, $`A' = A/(1+\pi)`$ is next period’s real annuity income, $`w(t)`$ is the age-varying needs weight from equation (<a href="#eq:age_needs" data-reference-type="ref" data-reference="eq:age_needs">[eq:age_needs]</a>), and $`u(c, H)`$ is the state-dependent utility from equation (<a href="#eq:state_dependent" data-reference-type="ref" data-reference="eq:state_dependent">[eq:state_dependent]</a>). When both channels are inactive ($`\delta_c = 0`$, $`\varphi(H) = 1`$), this reduces to the standard Bellman equation. At the terminal period $`T`$, the individual consumes all remaining resources and leaves any residual as a bequest.

At $`t = 1`$ (age 65), the annuitization decision is:
``` math
\begin{equation}
\label{eq:annuitize}
\alpha^* = \arg\max_{\alpha \in [0,1]} V\big((1-\alpha) W_0 - F \cdot \mathbf{1}(\alpha > 0), \; \alpha W_0 \cdot \text{payout}, \; H_0, \; 1\big),
\end{equation}
```
where $`F`$ is the fixed purchase cost.

## Analytical characterization

The numerical decomposition in Section <a href="#sec:results" data-reference-type="ref" data-reference="sec:results">4</a> can be given analytical structure. Consider the annuitization decision at $`\alpha = 0`$. Shifting one dollar from liquid wealth to the annuity premium changes welfare by
``` math
\begin{equation}
\label{eq:annuity_value_ratio}
\frac{dV}{d\alpha}\bigg|_{\alpha=0} = W_0 \Big[\text{MWR} \cdot V_A(W_0, 0, H, 1) - V_W(W_0, 0, H, 1)\Big],
\end{equation}
```
where $`V_W`$ and $`V_A`$ are the partial derivatives of the value function with respect to liquid wealth and annuity income. Define the *annuity value ratio*
``` math
\begin{equation}
\label{eq:R_ratio}
R \equiv \text{MWR} \cdot \frac{V_A}{V_W}.
\end{equation}
```
The agent annuitizes a positive fraction if and only if $`R > 1`$.

<div class="proposition">

**Proposition 1** (Yaari). *With no bequests ($`\theta = 0`$), deterministic health, fair annuity pricing, and $`\beta(1+r) = 1`$, the envelope theorem implies $`V_W = u'(c^*)`$ at the optimum. The annuity-income derivative $`V_A`$ is the present discounted value of future marginal utilities generated by the income stream, weighted by survival probabilities. Consumption smoothing across states equates these marginal values, yielding $`R = 1`$ with full annuitization weakly optimal.*

</div>

Each demand-suppressing channel introduces a factor $`\Phi_i < 1`$ that reduces $`R`$ below the Yaari benchmark:

<div class="proposition">

**Proposition 2** (Super-additive decomposition). *The annuity value ratio can be written
``` math
\begin{equation}
\label{eq:multiplicative_R}
R = \Phi_{\text{MWR}} \times \Phi_{\text{bequest}} \times \Phi_{\text{health}} \times \Phi_{\text{inflation}} \times \Phi_{\text{SS}} \times \Phi_{\text{pessimism}} \times \Phi_{\text{age}} \times \Phi_{\text{state}},
\end{equation}
```
where:*

- *$`\Phi_{\text{MWR}} = \text{MWR}`$. The pricing load directly scales the numerator. At MWR $`= 0.87`$, each dollar of premium buys 0.87 of expected value, a load of 13% relative to the actuarially fair benchmark.*

- *$`\Phi_{\text{bequest}} = \big[1 + (1 - s) \, v'(b) / u'(c)\big]^{-1}`$, where $`s`$ is the survival probability and $`v'(b)/u'(c)`$ is the ratio of marginal bequest to marginal consumption utility. Under the DFJ luxury-good specification ($`\kappa = \$272{,}628\gg`$ median wealth $`\approx \$40{,}000`$), $`v'(b) \approx \theta(\kappa)^{-\gamma}`$ is nearly constant and small, so $`\Phi_{\text{bequest}} \approx 1.00`$.*

- *$`\Phi_{\text{health}}`$ reflects the covariance between survival and the marginal utility of liquid wealth. When health deterioration simultaneously reduces survival and raises medical costs, the ratio $`V_A / V_W`$ falls. This is the Reichling–Smetters mechanism.*

- *$`\Phi_{\text{inflation}}`$ equals the ratio of the present value of the nominal payment stream (in real terms) to the real payment stream, weighted by marginal utilities. At 2% inflation, payments in year 25 retain only 61% of their initial purchasing power.*

- *$`\Phi_{\text{SS}}`$ captures the diminishing marginal insurance value of additional annuitization when Social Security already provides a longevity-insured income floor.*

- *$`\Phi_{\text{pessimism}} < 1`$ because the agent uses $`\psi \cdot s(t,H)`$ in the Bellman equation. The subjective present value of future annuity income is lower than the objective present value used by the insurer to set the price.*

- *$`\Phi_{\text{age}} < 1`$ because declining consumption needs $`w(t)`$ reduce the marginal utility of late-life income, which is precisely the income the annuity provides.*

- *$`\Phi_{\text{state}} \leq 1`$ because poor-health states generate lower marginal utility of consumption, and the annuity pays into those states.*

</div>

The decomposition in equation (<a href="#eq:multiplicative_R" data-reference-type="ref" data-reference="eq:multiplicative_R">[eq:multiplicative_R]</a>) characterizes the nine-channel structural baseline. SDU enters the value function as a separate multiplicative factor on portfolio-financed consumption (equation <a href="#eq:sdu" data-reference-type="ref" data-reference="eq:sdu">[eq:sdu]</a>), and the at-purchase penalty (equation <a href="#eq:ped" data-reference-type="ref" data-reference="eq:ped">[eq:ped]</a>) enters as a one-time additive shifter on the annuitization decision; together they contribute to the eleven-channel Shapley enumeration in Section <a href="#sec:shapley" data-reference-type="ref" data-reference="sec:shapley">4.4</a>.

<div class="proposition">

**Proposition 3** (Super-additivity of participation effects). *The fraction of agents annuitizing is $`\Pr(\alpha^* > 0) = \Pr(R_i > 1)`$, where $`R_i`$ varies across agents due to heterogeneity in wealth, health, and Social Security income. In log space,
``` math
\begin{equation}
\ln R_i = \sum_j \ln \Phi_j + \varepsilon_i,
\end{equation}
```
where $`\varepsilon_i`$ captures agent-level heterogeneity. Each additional channel shifts the distribution of $`\ln R_i`$ leftward by $`|\ln \Phi_j|`$. Agents near the participation threshold ($`R_i \approx 1`$, i.e., $`\ln R_i \approx 0`$) are disproportionately eliminated, so the ownership drop from adding a channel is larger when other channels have already thinned the right tail of the $`R_i`$ distribution. This super-additive structure motivates the exact Shapley decomposition in Section <a href="#sec:shapley" data-reference-type="ref" data-reference="sec:shapley">4.4</a>, which attributes the total demand reduction to individual channels without dependence on the order in which channels are added.*

</div>

The dominant term is $`\Phi_{\text{MWR}} = 0.87`$, which alone reduces the annuity value ratio by 13%. The near-unity $`\Phi_{\text{bequest}}`$ under the DFJ specification explains why bequests contribute only 5.8 pp in the Shapley decomposition: the luxury-good curvature parameter makes bequest utility irrelevant for median-wealth retirees.

## Solution method

The model is solved by backward induction over the state space $`(W, A, H, t)`$. The wealth grid uses 80 points with power-function spacing (denser at low wealth) over $`[0, \$3\text{ million}]`$, covering the 99.5th percentile of the HRS wealth distribution. The annuity income grid uses 30 points with cubic spacing to resolve small purchases, and health is discrete with three states. Consumption is optimized at each grid point using Brent’s method. Value function interpolation across the wealth dimension uses piecewise linear interpolation with flat extrapolation.

The annuitization fraction $`\alpha`$ is optimized over a 101-point grid at age 65. Grid convergence is verified at the 9-node production quadrature rule: on the mean-Social-Security diagnostic, predicted ownership ranges from 21.1% at the medium grid ($`60 \times 20`$) to 20.8% at the fine grid ($`100 \times 40`$), both modestly above the production grid ($`80 \times 30`$, 20.0%); the roughly 1.0 pp variation across grid resolutions is small relative to the channel contributions in the Shapley decomposition. See Appendix Table <a href="#A-tab:grid_convergence" data-reference-type="ref" data-reference="A-tab:grid_convergence">[A-tab:grid_convergence]</a>.

# Calibration and Validation

Table <a href="#tab:calibration" data-reference-type="ref" data-reference="tab:calibration">1</a> summarizes the parameter values. Each is drawn from a published source or calibrated to match moments from the HRS.

<div class="threeparttable">

<div id="tab:calibration">

| Parameter | Symbol | Value | Source |
|:---|:---|:---|:---|
|  |  |  |  |
| Risk aversion | $`\gamma`$ | 2.5 | Within Chetty (2006) range (1–3) |
| Discount factor | $`\beta`$ | 0.97 | Standard |
| Bequest intensity | $`\theta`$ | 56.96 | Lockwood (2012) |
| Bequest shifter | $`\kappa`$ | \$272,628 | Lockwood (2012); De Nardi (2004) |
|  |  |  |  |
| Entry age |  | 65 | Retirement |
| Maximum age |  | 110 | Lockwood (2012) |
| Risk-free rate | $`r`$ | 0.02 | Real |
|  |  |  |  |
| Health states |  | 3 | Good, Fair, Poor |
| Hazard multipliers | $`\mu(H, t)`$ | See text | HRS mortality data (see text) |
| Quadrature nodes |  | 9 | Gauss–Hermite |
| Survival pessimism | $`\psi`$ | 0.960 | O’Dea and Sturrock (2023) |
|  |  |  |  |
| Log mean at 65 (Fair) | $`\mu_m`$ | 7.037 | Jones et al. (2018) |
| Annual growth |  | 0.065 | Jones et al. (2018) |
| Log std dev | $`\sigma_m`$ | 1.4 | Jones et al. (2018) |
| Consumption floor | $`\underline{c}`$ | \$6,180 | SSI + state supplement |
|  |  |  |  |
| Money’s worth ratio | MWR | 0.87 | Mitchell et al. (1999) |
| Fixed cost | $`F`$ | \$2,500 | Lockwood (2012) |
| Inflation rate | $`\pi`$ | 0.02 | Post-Volcker average |
|  |  |  |  |
| Age-varying needs decline | $`\delta_c`$ | 0.02 | Aguiar and Hurst (2013) |
| Health-utility weights | $`\varphi(H)`$ |  |  |
| $`0.82]`$ | Finkelstein et al. (2013) |  |  |
| Public-care aversion | $`\chi_{\text{LTC}}`$ | 0.49 | Ameriks et al. (2020) |
|  |  |  |  |
| SDU portfolio discount | $`\lambda_W`$ | 0.625 | Blanchett and Finke (2024, 2025) (literature magnitude) |
| At-purchase penalty | $`\psi_{\text{purchase}}`$ | 0.05 | Brown et al. (2008); Chalmers and Reuter (2012) (literature magnitude) |

Model Parameters

</div>

<div class="tablenotes">

All dollar values in 2014 dollars.

</div>

</div>

#### Preferences.

I set $`\gamma = 2.5`$, within the range of 1–3 estimated by Chetty (2006) from labor supply elasticities. Lockwood (2012) uses $`\gamma = 2`$; the slightly higher value reflects the richer model environment. Section <a href="#sec:robustness" data-reference-type="ref" data-reference="sec:robustness">5</a> reports results for $`\gamma \in \{1.5, 2.0, \ldots, 5.0\}`$.

#### Age-varying consumption needs.

The decline rate $`\delta_c = 0.02`$ matches the central estimate from Aguiar and Hurst (2013), who found that nondurable consumption expenditure declines at roughly 2% per year in retirement after controlling for changes in household composition. This rate is applied uniformly across health states.

#### State-dependent utility.

The health-utility weights $`\varphi = [1.00, 0.92, 0.82]`$ are the central midpoint of the Finkelstein et al. (2013) estimates from the HRS, applied through the multiplicative state-dependent-utility approach of Reichling and Smetters (2015); the softer translation $`\varphi = [1.00, 0.95, 0.85]`$ is examined as a robustness check in Section <a href="#sec:results" data-reference-type="ref" data-reference="sec:results">4</a>. Good-health individuals receive full weight; Fair and Poor health reduce the marginal utility of consumption proportionally.

#### Public-care aversion ($`\chi_{\text{LTC}}`$).

The structural channel applies a utility multiplier $`\chi_{\text{LTC}} = 0.49< 1`$ to consumption in the Medicaid-binding Poor-health state (when the consumption floor binds), representing the reduced utility of publicly-financed long-term care relative to self-financed care. The value is a calibration choice within the public-care-aversion evidence of Ameriks et al. (2020), expressed as a flow-utility transformation rather than a parameter they report directly. The channel’s direction is a priori ambiguous: aversion to the Medicaid state raises the value of retaining liquid wealth (against annuitization), but it also raises the value of guaranteed income that keeps the agent off the floor (toward annuitization). In the fitted model the net effect is mildly pro-annuity, and the channel enters the Shapley decomposition with a small negative (demand-boosting) value (Section <a href="#sec:shapley" data-reference-type="ref" data-reference="sec:shapley">4.4</a>).

#### Exploratory behavioral parameters.

The two behavioral channels are calibrated to literature magnitudes rather than estimated from US moments. SDU’s $`\lambda_W = 0.625`$ follows the Blanchett and Finke (2024, 2025) retiree spending differential (approximately 50% from portfolio assets versus 80% from guaranteed income, implying $`\lambda_W = 50/80 = 0.625`$). The same calibration is applied to the Social Security claiming margin in Tharp (2026). The at-purchase penalty $`\psi_{\text{purchase}} = 0.05`$ at reference consumption $`c_{\text{ref}} = \$18{,}000`$ is a literature-magnitude best guess consistent with cumulative-prospect-theory parameterizations (Hu and Scott 2007) and the Brown et al. (2008) and Chalmers and Reuter (2012) narrow-framing evidence. Both parameters are exploratory and not moment-matched to any US annuitization target. Sensitivity sweeps across $`\lambda_W \in \{0.5, 0.625, 0.75, 0.85\}`$ and $`\psi_{\text{purchase}} \in \{0.01, 0.05, 0.09\}`$ are reported in Section <a href="#sec:robustness" data-reference-type="ref" data-reference="sec:robustness">5</a>.

The bequest parameters $`\theta = 56.96`$ and $`\kappa = \$272{,}628`$ are taken directly from Lockwood (2012), who estimated them from HRS bequest data at $`\gamma = 2`$. Using them at $`\gamma = 2.5`$ raises a portability concern in principle, but a simulation-based check (Appendix <a href="#A-app:bequest_recal" data-reference-type="ref" data-reference="A-app:bequest_recal">[A-app:bequest_recal]</a>) shows the bequest-to-wealth ratio diverges only modestly at the baseline $`\gamma = 2.5`$ (about 14%), rising monotonically toward the upper end of the risk-aversion range. All results use Lockwood’s original estimates, a conservative choice.

#### Health and mortality.

Health transition matrices are calibrated to HRS panel data following De Nardi et al. (2010). The five HRS self-reported health categories are mapped to three states: Good (Excellent/Very Good), Fair (Good), and Poor (Fair/Poor). Baseline survival probabilities use the SSA administrative life table from Lockwood (2012).

Hazard multipliers are estimated from the RAND HRS longitudinal file (waves 4–16, $`N = 126{,}249`$ person-wave observations aged 65+). The estimated ratios by age band are:

<div class="center">

| Age band | Good | Fair | Poor |
|:---------|:----:|:----:|:----:|
| 65–74    | 0.49 | 1.00 | 3.29 |
| 75–84    | 0.60 | 1.00 | 2.77 |
| 85+      | 0.74 | 1.00 | 1.82 |

</div>

The compression of the gradient at older ages is consistent with selection effects: those surviving to 85 in Poor health have already demonstrated above-average resilience. The baseline constant multipliers $`[0.50, 1.0, 3.75]`$ sit at the upper end of the empirical range. The Good and Fair multipliers fall between the HRS self-reported values ($`[0.57, 1.0, 2.7]`$) and the ADL/IADL-based functional estimates of Reichling and Smetters (2015) ($`[0.45, 1.0, 3.5]`$); the Poor multiplier sits just above both, reflecting the steeper functional-limitation gradient at the younger ages where the annuitization decision is made. Section <a href="#sec:robustness" data-reference-type="ref" data-reference="sec:robustness">5</a> reports results across the full range, including the R-S functional and HRS self-reported endpoints.

#### Medical expenditures.

The medical expenditure process matches the moments published by Jones et al. (2018): mean out-of-pocket spending of \$4,201 at age 70, growing to \$29,703 at age 100, with a 95th percentile of approximately \$111,509 at age 100. Health shifts both the mean and variance of log spending, with Poor health raising expected costs by a factor of roughly two relative to Fair.

#### Population sample and empirical targets.

The wealth distribution is drawn from the RAND HRS longitudinal file, selecting single retirees aged 65–69 using filters comparable to Lockwood (2012). The resulting sample contains 4,258 person-wave observations (waves 5–9). The main analysis restricts to the 2279 observations with liquid wealth above \$5,000, as those with negligible wealth cannot meaningfully annuitize. *The empirical-target ownership rates reported below ($`3.11\%`$ lifetime contract indicator and $`5.21\%`$ any-annuity income proxy) are computed on the same wealth-restricted subsample as the model predictions, ensuring symmetric comparison.* The structural model maps each household’s state to a predicted decision rather than estimating moments from the sample distribution. The HRS observations are unweighted; the qualitative results are stable under sample weights. Unweighted estimates serve as the headline so that the empirical target maps directly to the cells solved in the structural decomposition.

The paper reports two HRS measures of US lifetime annuity ownership in parallel as empirical targets:

1.  *Lifetime annuity contract indicator (q286 series; preferred measure).* Drawn from the HRS pension grid (“fat-file”) waves 5–9. Identifies respondents reporting at least one annuity contract for which the question stem “Will this annuity continue for the rest of your life?” is answered affirmatively. In the pooled sample of 2,860 eligible person-waves, 89 report a lifetime annuity contract: 3.11% (Wilson 95% CI $`[2.54\%, 3.81\%]`$). This is the methodologically appropriate target for an SPIA-focused model.

2.  *Any-annuity income proxy (`r{w}iann`; conventional measure).* The RAND HRS variable `r{w}iann` flags any positive annuity income in the wave, including DC pension withdrawals and short-period payouts not life-contingent. Pooled across waves 5–9, 5.21% of person-waves report positive annuity income (Wilson 95% CI $`[4.45\%, 6.09\%]`$). This measure—or a closely comparable any-annuity-income construct—is used by most prior literature (e.g., (Lockwood 2012) reports a 3.6% rate for single retirees 65–69 using a wave-specific HRS annuity-income measure that conceptually overlaps with `r{w}iann` but is not identical at the variable-naming level).[^6] It overstates lifetime annuity ownership by conflating it with one-time DC pension withdrawals.

Both HRS measures are reported as out-of-sample comparisons for the nine-channel structural baseline (7.9%). Section <a href="#sec:results" data-reference-type="ref" data-reference="sec:results">4</a> reports headline results against both measures.

#### Lifecycle moment validation.

Table <a href="#tab:moment_validation" data-reference-type="ref" data-reference="tab:moment_validation">2</a> reports a compact bequest-distribution diagnostic from the lifecycle simulation: simulated vs. HRS exit-interview moments for the mean, median, and fraction with bequest greater than \$10K. These moments are not targeted in calibration. The comparison serves as external discipline on the bequest and decumulation behavior rather than as matched moments.

The bequest moments are partially matched in this representative simulation (Table <a href="#tab:moment_validation" data-reference-type="ref" data-reference="tab:moment_validation">2</a>): the simulated fraction with a bequest above \$10K closely matches the HRS rate, but the simulated mean is below the empirical mean and the simulated median is zero against a positive HRS exit-interview target. The mean gap reflects the right tail of the empirical bequest distribution, which the representative simulation does not reproduce. The welfare and ownership results should not be interpreted as a full bequest-distribution fit. The DFJ luxury-good calibration concentrates bequest motives at high wealth, so the median household in the representative simulation (initial wealth \$250,000, Fair health) does not retain wealth for bequests after correlated medical and longevity risk. A full bequest-targeted calibration would change $`\theta`$ and $`\kappa`$ jointly; the Lockwood (2012) estimates used here are kept fixed in the spirit of the unified-channel decomposition exercise.

<div id="tab:moment_validation">

| Moment                    | Simulated | Empirical (HRS) |
|:--------------------------|:---------:|:---------------:|
| Mean bequest              |  \$50420  |     \$90000     |
| Median bequest            |    \$0    |     \$20000     |
| Fraction bequest \> \$10K |   45.9%   |      45.0%      |

Simulated vs Empirical Lifecycle Moments

</div>

<div class="tablenotes">

Simulated: 100,000 trajectories, initial wealth \$250,000, Fair health.

Empirical: HRS exit interviews (bequests); Jones et al. (2018) (medical).

</div>

# Results

## Sequential decomposition

Table <a href="#tab:retention" data-reference-type="ref" data-reference="tab:retention">3</a> presents an intuitive sequential decomposition of predicted voluntary annuity ownership, adding channels one at a time across rational, preference, and exploratory behavioral blocks. Because this exercise is order-dependent, I use it as a descriptive path through the model and treat the exact Shapley values below as the preferred attribution. For narrative transparency the table reports medical expenditure risk and the health-mortality correlation as two separate sequential steps. The Shapley analysis combines them into a single Med+R-S channel (Section <a href="#sec:shapley" data-reference-type="ref" data-reference="sec:shapley">4.4</a>), because the R-S mechanism’s quantitative bite in this framework operates through the interaction with medical risk: without competing demand for liquid wealth in sick states, the lower expected annuity NPV does not translate into a precautionary motive against annuitization. The narrative below describes the rational channels in this section and the preference and exploratory behavioral channels in Sections <a href="#sec:extension" data-reference-type="ref" data-reference="sec:extension">4.2</a> and <a href="#sec:behavioral_results" data-reference-type="ref" data-reference="sec:behavioral_results">4.3</a>. The table covers all three blocks for ease of reference. Because Table <a href="#tab:retention" data-reference-type="ref" data-reference="tab:retention">3</a> orders the preference channels (age-varying needs and state-dependent utility) before pricing loads while this section’s narrative defers them, the per-step ownership figure for a given channel can differ between the table and the prose—pricing loads, for instance, enter at a higher ownership level in the rational-only narrative below than in the full-table ordering. Both are valid paths through an order-dependent exercise, which is precisely why the order-independent Shapley values are the preferred attribution.

<div id="tab:retention">

| Channel | Ownership (%) | $`\Delta`$ (pp) | Retention | Cumulative |
|:---|:--:|:--:|:--:|:--:|
| Frictionless population baseline | 46.5 | — | — | — |
| \+ Social Security | 100.0 | +53.5 | 215.2% | 2.1520 |
| \+ Bequest motives | 100.0 | +0.0 | 100.0% | 2.1520 |
| \+ Medical expenditure risk (uncorrelated) | 92.0 | -8.0 | 92.0% | 1.9802 |
| \+ Health-mortality correlation (R-S) | 76.9 | -15.1 | 83.6% | 1.6553 |
| \+ Survival pessimism | 56.6 | -20.3 | 73.6% | 1.2181 |
| \+ State-dependent utility | 57.5 | +0.9 | 101.6% | 1.2380 |
| \+ Age-varying consumption needs | 47.0 | -10.5 | 81.8% | 1.0123 |
| \+ Realistic pricing loads | 7.6 | -39.4 | 16.1% | 0.1634 |
| \+ Inflation erosion | 6.2 | -1.4 | 82.1% | 0.1341 |
| Observed (Lockwood 2012) | 3.6 | — | — | — |

Sequential Decomposition of Predicted Voluntary Annuity Ownership

</div>

<div class="tablenotes">

Retention rate = ownership after channel / ownership before channel. Cumulative product of retention rates tracks geometric compounding.

</div>

#### Population benchmark with public consumption floor.

The first row—no bequest motive, actuarially fair pricing, no medical expenditure risk, no inflation, and no Social Security income—predicts 46.5% ownership in the HRS population sample. This is not the theoretical Yaari full-annuitization result. The benchmark holds two US institutional features fixed across all subsequent decomposition rows: a public consumption floor (Medicaid/SSI proxy at $`c_{\text{floor}} = \$6{,}180`$/year) and a minimum-wealth analytical sample restriction (HRS singles with non-housing wealth $`\geq`$ \$5,000). Many low-wealth households in the data find annuitization unattractive even in this frictionless environment because the public floor effectively guarantees consumption at Medicaid-eligible levels, reducing the marginal value of liquid wealth that could be annuitized. The standard convention in the calibrated lifecycle literature (Pashchenko 2013; Peijnenburg-Nijman-Werker 2016; De Nardi-French-Jones 2010) is to bake the safety net into the institutional environment rather than treat it as a behavioral channel. This paper follows that convention.

#### Social Security.

Adding Social Security income (COLA-protected, calibrated by wealth quartile) raises predicted ownership to 100.0%. SS acts as a complement in the frictionless model: the guaranteed income floor enables consumption smoothing and makes agents willing to lock up additional wealth in annuities. The 215.2% retention rate reflects this complementarity.

#### Bequest motives.

Adding the DFJ luxury-good bequest specification ($`\theta = 56.96`$, $`\kappa = \$272{,}628`$) leaves ownership unchanged at 100.0% (retention rate of 100%). The luxury-good $`\kappa = \$272{,}628`$ makes marginal bequest utility nearly flat for individuals with wealth below \$200,000. In the HRS sample, median liquid wealth is approximately \$40,000.

#### Medical expenditure risk and health-mortality correlation (combined).

Introducing stochastic medical expenditures together with the Reichling–Smetters health-mortality correlation reduces ownership to 76.9% (retention 76.9%, a $`-23.1`$ pp effect). The two are bundled into a single channel because the R-S mechanism’s quantitative bite in this framework operates through the interaction with medical risk: without competing demand for liquid wealth in sick states, the lower expected annuity NPV does not translate into a precautionary motive against annuitization. The mechanism: when a retiree’s health deteriorates, expected remaining lifetime falls (reducing the present value of future annuity payments) and expected medical costs rise (increasing the marginal value of liquid wealth). The demand-suppressing effect depends on this correlation between health deterioration, survival reduction, and cost increases. The combined channel was not jointly incorporated in the multi-channel models of Pashchenko (2013) or Peijnenburg et al. (2016).

#### Survival pessimism.

Introducing subjective survival beliefs ($`\psi = 0.960`$) reduces ownership from 76.9% to 56.6% (retention 73.6%, a $`-20.3`$ pp effect). The agent overweights the probability of dying before recovering the premium.

#### Pricing loads.

Repricing the annuity at MWR $`= 0.87`$ and adding a \$2,500 fixed purchase cost produces the largest single reduction, from 56.6% to 16.3% (retention 28.8%). An 13% load eliminates the surplus that marginally willing buyers retained after accounting for health risk and survival pessimism.

#### Inflation erosion.

Converting the annuity from real to nominal at 2% annual inflation reduces ownership from 16.3% to 14.0% (retention 85.5%). This step is a product counterfactual: the previous steps priced a real annuity (constant purchasing power); this step switches to a nominal annuity whose real value erodes over time. Social Security income is COLA-protected and does not erode, but the private annuity payment loses purchasing power: at 2% inflation, real income from the annuity falls by 39% over 25 years.

#### Summary.

The six standard rational channels predict 14.0% ownership relative to a frictionless population benchmark of 46.5%. Pricing loads (retention 28.8%) and the combined Med+R-S channel (retention 76.9%, reported as two separate steps in Table <a href="#tab:retention" data-reference-type="ref" data-reference="tab:retention">3</a> for narrative transparency) are the two largest single-step percentage-point reductions in this sequential ordering. The key implication is that the standard rational literature substantially overshoots both empirical targets—a gap the preference channels and the structural public-care aversion channel narrow further, and which the exploratory behavioral channels in Section <a href="#sec:behavioral_results" data-reference-type="ref" data-reference="sec:behavioral_results">4.3</a> examine at literature magnitudes.

## Preference Channel Extensions

Table <a href="#tab:extension_path" data-reference-type="ref" data-reference="tab:extension_path">4</a> isolates the incremental effect of the two added preference channels.

<div class="threeparttable">

<div id="tab:extension_path">

| Specification | Ownership (%) | $`\Delta`$ (pp) |
|:---|:--:|:--:|
| Six rational channels (Layer 1) | 14.0 | — |
| \+ Age-varying consumption needs | 7.3 | -6.6 |
| \+ State-dependent utility | 6.2 | -1.1 |
| \+ Public-care aversion $`\chi_{\text{LTC}}`$ (Layer 2 complete) | 7.9 | +1.7 |
| \+ Source-dependent utility (Force A) | 56.5 | +48.6 |
| \+ Narrow-framing penalty (Force B; Model 1) | 0.1 | -56.4 |

Sequential Channel Decomposition

</div>

<div class="tablenotes">

The table is the structural multi-channel decomposition. Layer 1 covers rational frictions; Layer 2 adds preference and structural channels; the two behavioral channels (SDU and PED) are an exploratory extension reported with within-model sensitivity ranges.

</div>

</div>

Adding age-varying consumption needs ($`\delta_c = 0.02`$, calibrated to (Aguiar and Hurst 2013)) reduces predicted ownership from 14.0% to 7.3%. This is the quantitatively important extension beyond the six-channel rational model: if late-life consumption needs decline, the insurance value of a level annuity stream declines as well. The resulting reduction is comparable in magnitude to survival pessimism or inflation erosion.

Adding state-dependent utility ($`\varphi = [1.00, 0.92, 0.82]`$, the central midpoint of the (Finkelstein et al. 2013) estimates) produces only a small additional reduction, from 7.3% to 6.2%. The channel’s effect is insensitive to the specific mapping within the range the literature supports: the harsher FLN raw endpoint $`\varphi = [1.00, 0.90, 0.75]`$ yields 5.6% and the softer translation $`\varphi = [1.00, 0.95, 0.85]`$ used by Reichling and Smetters (2015) yields 6.6%, a spread of 1.0 pp around the production value 6.2%. In either calibration, this channel is best interpreted as a completeness check rather than a load-bearing mechanism.

The full eight-channel rational+preference model therefore predicts 6.2% ownership, a reduction from the 46.5% frictionless benchmark but still above both empirical targets ($`5.21\%`$ on the conventional any-annuity income proxy; $`3.11\%`$ on the cleaner lifetime contract indicator). Adding the structural public-care aversion channel ($`\chi_{\text{LTC}} = 0.49`$) yields the nine-channel structural baseline of 7.9%, modestly above both HRS measures. The remainder of the paper uses the FLN central mapping as the production calibration.

## Behavioral extensions

The eight-channel rational+preference model predicts 6.2% ownership. Adding the structural public-care aversion channel ($`\chi_{\text{LTC}} = 0.49`$) yields the nine-channel structural baseline of 7.9%, modestly above the two HRS measures ($`3.11\%`$ on the lifetime contract indicator, $`5.21\%`$ on the conventional any-annuity income proxy). Structural mechanisms alone bring predicted ownership modestly above the two HRS measures.

#### Literature-magnitude behavioral channels.

The nine-channel result does not imply that behavioral factors do not matter. To examine their potential role, I layer two behavioral channels onto the nine-channel baseline as an exploratory analysis: source-dependent utility ($`\lambda_W = 0.625`$) and a narrow-framing at-purchase penalty ($`\psi_{\text{purchase}} = 0.05`$). Both parameters are exploratory best guesses anchored to literature magnitudes rather than moment-matched to US targets. The headline reading remains the nine-channel structural baseline. With both channels active at these values, SDU raises predicted ownership to 56.5% by transforming portfolio drawdowns into a lower-utility-weight consumption category, and PED then saturates participation, yielding the eleven-channel prediction 0.1%.

At the chosen values, each behavioral channel individually moves ownership by more than almost any single rational, preference, or structural channel in the model. In absolute magnitude the Shapley contributions for PED (46.6 pp) and SDU (-26.5 pp, entering with a negative sign because it is a booster) exceed pricing loads (12.8 pp), the combined Med+R-S channel (14.5 pp), and survival pessimism (4.4 pp; see Section <a href="#sec:shapley" data-reference-type="ref" data-reference="sec:shapley">4.4</a>). The two channels operate in opposite directions and largely offset: SDU pulls demand up, PED pulls it down, and the net effect on ownership depends sensitively on the chosen parameters. Sensitivity sweeps across $`\lambda_W \in \{0.5, 0.625, 0.75, 0.85\}`$ and $`\psi_{\text{purchase}} \in \{0.01, 0.05, 0.09\}`$ in Section <a href="#sec:robustness" data-reference-type="ref" data-reference="sec:robustness">5</a> show that small shifts within the literature-defensible range move the eleven-channel prediction substantially in either direction.

#### Out-of-sample comparison.

The conventional any-annuity income proxy ($`5.21\%`$, Wilson 95% CI $`[4.45\%, 6.09\%]`$) and the cleaner lifetime-contract indicator ($`3.11\%`$, Wilson 95% CI $`[2.54\%, 3.81\%]`$) are reported as out-of-sample comparisons against the nine-channel baseline (7.9%). No US annuitization moment enters the calibration.

## Exact Shapley decomposition

The sequential decomposition is order-dependent: the contribution attributed to each channel depends on which channels precede it. To obtain order-independent attributions, I compute exact Shapley values across two parallel cooperative games. The disciplined headline attribution is the *nine-channel structural Shapley*, computed over all $`2^9 = 512`$ subsets of the rational, preference, and structural-LTC channels (with SDU and PED held off). An exploratory *eleven-channel extended Shapley*, computed over all $`2^{11} = 2{,}048`$ subsets that additionally enumerate the two behavioral parameters at their literature magnitudes, is reported separately at the end of this subsection. Medical expenditure risk and the Reichling–Smetters health-mortality correlation are combined into a single channel because the R-S mechanism’s quantitative bite operates through the interaction with medical risk: without competing demand for liquid wealth in sick states, the lower expected annuity NPV does not translate into a precautionary motive against annuitization.

#### Nine-channel structural Shapley (headline).

Table <a href="#tab:shapley_nine" data-reference-type="ref" data-reference="tab:shapley_nine">5</a> reports the disciplined attribution. Pricing loads are the dominant demand suppressor, contributing 31.4 pp—81% of the total demand drop on their own. Subjective survival pessimism (10.9 pp, 28%) and the combined Med+R-S health-mortality channel (9.4 pp, 24%) form the co-leading second tier. Bequest motives—the single most-cited explanation for the puzzle—contribute 5.8 pp (15%), mid-pack, ahead of age-varying consumption needs (4.4 pp); state-dependent utility (0.4 pp) and inflation erosion (-0.2 pp) contribute small magnitudes, while public-care aversion enters with a small *negative* (demand-boosting) value (-2.4 pp), mildly raising annuitization on net. Social Security enters with a large negative Shapley value ($`-21.1`$ pp, $`-55\%`$): it is the largest-magnitude demand-boosting force in the game, but it raises annuitization at the margin rather than suppressing it, because the income floor it provides is what makes a private annuity rational. The ranking inverts the most prominent claim in the prior literature: bequest motives, often cast as the leading explanation, are a mid-tier channel here, while pricing loads dominate.

<div class="threeparttable">

<div id="tab:shapley_nine">

| Channel                    | Shapley (pp) | Share (%) |
|:---------------------------|:------------:|:---------:|
| Loads                      |    +31.37    |   +81.3   |
| Pessimism                  |    +10.86    |   +28.2   |
| Medical+R-S                |    +9.39     |   +24.3   |
| Bequests                   |    +5.77     |   +15.0   |
| Age needs                  |    +4.37     |   +11.3   |
| State utility              |    +0.44     |   +1.1    |
| Inflation                  |    -0.16     |   -0.4    |
| Public-care aversion (LTC) |    -2.37     |   -6.2    |
| SS                         |    -21.10    |   -54.7   |
| Total demand drop          |    +38.57    |   100.0   |

Nine-Channel Structural Shapley Decomposition (Headline)

</div>

<div class="tablenotes">

Exact Shapley values over all $`2^9 = 512`$ subsets of the nine structural channels (SDU and PED held off). Positive values are demand-suppressing contributions; negative values are demand-boosting (Social Security raises annuitization at the margin by providing the income floor).

Frictionless baseline: 46.5%. Nine-channel structural prediction: 7.9%. Total demand drop: 38.6 pp.

The eleven-channel exploratory Shapley (Table <a href="#tab:shapley_exact" data-reference-type="ref" data-reference="tab:shapley_exact">6</a>) layers the two behavioral channels (SDU, PED) and is reported as a sensitivity exercise rather than the disciplined attribution.

</div>

</div>

The nine-channel Shapley sharpens two findings from the sequential decomposition. First, pricing loads are the dominant demand-suppressing contributor regardless of ordering, with survival pessimism and the combined Med+R-S correlation as the co-leading second tier. Second, the channels not jointly incorporated in the earlier multi-channel literature—the combined Med+R-S correlation, survival pessimism, and age-varying consumption needs—collectively account for a meaningful fraction of the structural demand suppression, comparable in scale to pricing loads.

#### The ranking is stable; the level is not.

The order-independence of the Shapley value removes one source of fragility, but a referee will reasonably ask whether the attribution survives the two perturbations to which calibrated annuity models are most sensitive: the risk-aversion parameter and the discrete extensive-margin statistic. It does. As $`\gamma`$ ranges over $`[2.0, 3.0]`$, predicted full-model ownership moves from 0.0% to 21.9% (a knife-edge driven by the minimum-purchase and fixed-cost thresholds), yet Loads remain the top suppressor at all 5 values of $`\gamma`$, and the second-tier set $`\{`$survival pessimism, Med+R-S$`\}`$ is preserved (their internal order swaps once across the range). Recomputing the Shapley on the continuous mean-purchase share rather than the discontinuous ownership indicator leaves the suppressor ranking essentially unchanged (rank correlation 1.00 at the production calibration). The ranking is therefore the reportable object. The level is a fragile by-product of where the population sits relative to the purchase threshold, and is best read as a range rather than a point.

#### Eleven-channel extended Shapley (exploratory).

Table <a href="#tab:shapley_exact" data-reference-type="ref" data-reference="tab:shapley_exact">6</a> reports the exploratory extension. The eleven-channel cooperative game adds source-dependent utility ($`\lambda_W = 0.625`$) and the at-purchase penalty ($`\psi_{\text{purchase}} = 0.05`$) as additional players. Under the literature-magnitude parameterization, PED carries the largest absolute Shapley contribution (46.6 pp, 101%), and SDU carries a large negative Shapley contribution (-26.5 pp, -57%) because it operates as an ownership booster. These behavioral Shapley values reflect the chosen literature-magnitude parameters within the eleven-channel cooperative game; because $`\lambda_W`$ and $`\psi_{\text{purchase}}`$ are exploratory rather than moment-matched, the attributions should be read as illustrative of where standard behavioral parameters would land in the channel ranking, not as identification of the magnitudes themselves.

<div id="tab:shapley_exact">

| Channel                        | Shapley (pp) | Share (%) |
|:-------------------------------|:------------:|:---------:|
| SS                             |    -6.96     |   -15.0   |
| Bequests                       |    +0.73     |    1.6    |
| Medical+R-S                    |    +14.54    |   31.4    |
| Pessimism                      |    +4.37     |    9.4    |
| Age needs                      |    +2.07     |    4.5    |
| State utility                  |    +0.27     |    0.6    |
| Loads                          |    +12.84    |   27.7    |
| Inflation                      |    -0.57     |   -1.2    |
| Public-care aversion (LTC)     |    -1.07     |   -2.3    |
| Source-dependent utility (SDU) |    -26.47    |   -57.1   |
| Narrow-framing penalty (PED)   |    +46.63    |   100.5   |
| Total                          |    +46.38    |   100.0   |

Exact Shapley-Value Decomposition of Predicted Annuity Ownership

</div>

<div class="tablenotes">

Exact Shapley values computed from all 2048 channel subsets. Each value represents the weighted average marginal ownership reduction (pp) across all coalition orderings. Yaari baseline: 46.5%. Full model: 0.1%.

</div>

## Pairwise channel interactions

Table <a href="#tab:pairwise" data-reference-type="ref" data-reference="tab:pairwise">7</a> reports the pairwise interaction strength for the eight rational and preference channels. For each pair (A, B), the interaction is defined as the difference between the ownership drop when both are active simultaneously and the sum of their individual drops. A negative interaction indicates super-additivity: the channels reinforce each other. The order-independent contributions of the eleven channels are reported in the exact Shapley decomposition (Section <a href="#sec:shapley" data-reference-type="ref" data-reference="sec:shapley">4.4</a>).

<div id="tab:pairwise">

|  | SS | Bequests | Medical+R-S | Loads | Inflation | Pessimism | HealthUtil | AgeNeeds |
|:---|:--:|:--:|:--:|:--:|:--:|:--:|:--:|:--:|
| SS | — | +0.0 | -11.5 | -29.9 | +0.3 | -14.5 | +0.4 | -4.5 |
| Bequests | — | — | -0.2 | +0.0 | +0.0 | -0.2 | +0.0 | +0.0 |
| Medical+R-S | — | — | — | -3.8 | +1.1 | -1.6 | +0.7 | -0.9 |
| Loads | — | — | — | — | -0.5 | -0.8 | +0.3 | -0.2 |
| Inflation | — | — | — | — | — | +0.1 | +0.3 | +0.2 |
| Pessimism | — | — | — | — | — | — | +0.2 | -0.4 |
| HealthUtil | — | — | — | — | — | — | — | +0.1 |
| AgeNeeds | — | — | — | — | — | — | — | — |

Pairwise Interaction Strengths, Rational and Preference Channels (pp)

</div>

<div class="tablenotes">

Each cell shows the interaction: ownership with both channels minus the additive prediction from individual effects. Negative values indicate super-additive demand reduction (channels reinforce each other).

</div>

The strongest interaction is between Social Security and pricing loads ($`-29.9`$ pp). SS raises demand by providing an income floor, and loads destroy demand by eliminating the surplus; when combined, the effect of loads is amplified by the elevated demand that SS creates. The combined Med+R-S health-mortality channel and pricing loads interact at $`-3.8`$ pp, reflecting the economic complementarity between valuation risk and pricing frictions. Bequest interactions are near zero across the board, consistent with the modest isolated effect of the DFJ luxury-good specification.

## Comparison with prior work

Table <a href="#tab:pashchenko" data-reference-type="ref" data-reference="tab:pashchenko">8</a> evaluates the channels that Pashchenko (2013) emphasized—bequest motives, minimum purchase requirements, and pricing loads—within the present framework. This is not a replication of her model, which differs in preference specification, health dynamics, and solution method. Rather, it quantifies how much of the ownership gap those channels account for in the unified model, and how much additional reduction the present paper obtains from the broader channel set. Her model predicted approximately 20% participation; the six-channel rational model here predicts 14.0%, the added preference channels bring the prediction to 6.2%, and the structural public-care aversion channel yields the nine-channel baseline of 7.9%, modestly above both HRS measures.

<div id="tab:pashchenko">

| Model Specification                | Ownership (%) | $`\Delta`$ |
|:-----------------------------------|:-------------:|:----------:|
| Yaari benchmark (SS on)            |     100.0     |     —      |
| \+ Bequest motives (DFJ)           |     100.0     |  +0.0 pp   |
| \+ Minimum purchase (25K)          |     77.3      |  -22.7 pp  |
| \+ Pricing loads (MWR=0.85)        |     58.7      |  -18.6 pp  |
| *Channels omitted by Pashchenko:*  |               |            |
| \+ Medical costs + R-S correlation |     32.4      |  -26.3 pp  |
| \+ Survival pessimism              |     12.9      |  -19.5 pp  |
| \+ Full loads + Inflation          |     14.0      |  +1.1 pp   |
| Observed (Lockwood 2012)           |      3.6      |     —      |

Pashchenko (2013) Channels in Our Framework

</div>

<div class="tablenotes">

Steps 0–3 incorporate the channels Pashchenko (2013) identified (SS, bequests, minimum purchase, pricing loads) into our unified model. Steps 4–6 add channels not in her framework. Note: this is not a replication of her model (different preferences, health dynamics, solution method). Housing illiquidity is not modeled; see text.

</div>

Peijnenburg et al. (2016) found that full annuitization remains approximately optimal in their framework. Their model includes background risk and default risk but omits the health-mortality correlation that drives the Reichling–Smetters mechanism. Without the specific correlation between health shocks, survival, and medical costs, medical expenditure risk alone may increase annuity demand. The combined Med+R-S channel in the present model contributes 23.1 pp in the sequential decomposition (and 9.4 pp in the order-independent nine-channel Shapley attribution), confirming that the correlation is a quantitatively important channel that prior work omitted.

## Sensitivity to risk aversion

The decomposition results depend on calibrated parameters, particularly risk aversion $`\gamma`$. Table <a href="#tab:robustness_gamma_inflation" data-reference-type="ref" data-reference="tab:robustness_gamma_inflation">9</a> reports predicted ownership across a range of $`\gamma`$ values and inflation rates for the eight-channel rational+preference model.

<div id="tab:robustness_gamma_inflation">

|                  | $`\pi = 1\%`$ | $`\pi = 2\%`$ | $`\pi = 3\%`$ |
|:-----------------|:-------------:|:-------------:|:-------------:|
| $`\gamma = 2.4`$ |      0.9      |      0.4      |      0.2      |
| $`\gamma = 2.5`$ |      6.8      |      6.2      |      5.1      |
| $`\gamma = 2.6`$ |     12.5      |     11.9      |     11.0      |
| $`\gamma = 3.0`$ |     23.2      |     22.7      |     22.3      |

Predicted Ownership (%) by Risk Aversion and Inflation Rate

</div>

<div class="tablenotes">

Baseline: $`\gamma = 2.5`$, $`\pi = 2\%`$, DFJ bequests, MWR = 0.87, hazard multipliers \[0.50, 1.0, 3.75\].

</div>

At the baseline $`\gamma = 2.5`$, the eight-channel rational+preference model predicts 6.2%. Predicted ownership rises with $`\gamma`$: 0.0% at $`\gamma = 2.0`$, 0.4% at $`\gamma = 2.4`$, and 22.7% at $`\gamma = 3.0`$. The six-channel rational model, which omits the two preference channels, predicts a higher 14.0%. Adding the structural public-care aversion channel ($`\chi_{\text{LTC}}`$) to the eight-channel model yields the nine-channel structural baseline of 7.9%.

The sensitivity to $`\gamma`$ is not unique to this model. It is shared by all lifecycle annuitization models and reflects the near-margin-of-indifference nature of the annuity purchase decision. The mortality credit is modest for healthy 65-year-olds, so the net surplus from annuitization sits near zero for many households. Small changes in risk aversion tip the optimal decision from non-purchase to purchase.

A multi-gamma diagnostic decomposition (run at $`\gamma = 2.0`$, $`2.5`$, and $`3.0`$) locates where the gamma-sensitivity of the predicted *level* enters. Through the health-mortality correlation step the three decompositions stay close (68.2% to 77.6% ownership across the three values of $`\gamma`$), but survival pessimism splits them sharply: post-pessimism ownership is 10.0%, 56.6%, and 63.5% at $`\gamma = 2.0`$, $`2.5`$, and $`3.0`$. Pricing loads then compress all three further. The knife-edged participation level documented in Section <a href="#sec:results" data-reference-type="ref" data-reference="sec:results">4</a> thus originates in the interaction of survival pessimism and pricing loads with risk aversion, not in the rational channels through the R-S correlation.

## Joint parameter uncertainty

The single-parameter sweeps above hold all other parameters at their calibrated values. To assess robustness to joint calibration uncertainty within the model-internal parameters, I draw 1,000 parameter vectors from independent uniform distributions on the empirically supported ranges: $`\mu_P \sim U(2.5, 5.0)`$, $`\pi \sim U(0.015, 0.025)`$, MWR $`\sim U(0.83, 0.91)`$, $`\psi \sim U(0.92, 1.00)`$, $`\delta_c \sim U(0.01, 0.03)`$. Risk aversion is held fixed at the baseline. For each draw the model is solved on the production grid and the structural-baseline ownership prediction is recorded.

<div id="tab:monte_carlo">

| Statistic                               |      Value      |
|:----------------------------------------|:---------------:|
| Number of draws                         |      1000       |
| Median predicted ownership              |      10.2%      |
| 90% sensitivity interval                | \[0.0%, 32.0%\] |
| Interquartile range (50% interval)      | \[2.2%, 21.2%\] |
| Mean                                    |      12.6%      |
| Min / Max                               |  0.0% / 47.1%   |
| Fraction in \[1%, 10%\]                 |       29%       |
| Fraction in \[3%, 6%\] (observed range) |       10%       |

Conditional Monte Carlo: Predicted Ownership at $`\gamma = 2.5`$

</div>

<div class="tablenotes">

Risk aversion fixed at $`\gamma = 2.5`$. Joint draws over five calibration-uncertain rational/preference parameters: $`\mu_P \sim U(2.5, 5.0)`$, $`\pi \sim U(0.015, 0.025)`$, MWR $`\sim U(0.83, 0.91)`$, $`\psi \sim U(0.92, 1.00)`$, $`\delta_c \sim U(0.01, 0.03)`$. Behavioral channels (SDU $`\lambda_w`$, PED $`\psi_{\text{purchase}}`$) held at production values.

</div>

The nine-channel structural prediction of 7.9% sits inside the IQR of a joint parameter uncertainty draw over five rational and preference nuisance parameters (median 10.2%, IQR \[2.2%, 21.2%\], 90% sensitivity interval \[0.0%, 32.0%\]). The draw is constructed so each parameter’s range is symmetric around its production value (e.g., $`\psi \sim U(0.92, 1.00)`$ around production $`0.960`$; hazard multiplier on Poor health $`\sim U(2.5, 5.0)`$ around production $`3.75`$), so the central calibration is the central tendency of the parameter draw. The 90% ownership interval is nonetheless wide because ownership is a strongly non-linear function of the joint draw: combinations toward the demand-supporting corners (low pricing load, weak pessimism, weak Reichling–Smetters effect) generate large positive ownership, while corners toward demand-suppression generate corner-solution zero ownership. Both HRS measures ($`3.11\%`$ on the lifetime contract indicator, $`5.21\%`$ on the conventional any-annuity income proxy) are reported as out-of-sample comparisons against this range.

## Ownership across the wealth distribution

The aggregate ownership prediction masks a sharp distributional structure. Solving the full structural model and evaluating ownership separately within each wealth bin, predicted ownership is 0.0% in the bottom quartile (non-housing wealth below \$30,000) and remains near zero through the third quartile, then rises to 33.5% in the top quartile (above \$350,000). The aggregate prediction of 7.9% is, almost entirely, a top-quartile phenomenon. The bottom half of the distribution does not puzzlingly forgo annuitization: these households are already heavily annuitized through Social Security relative to their liquid wealth, often fall below the \$10,000 minimum-purchase threshold, and rationally retain precautionary liquidity against the Medicaid consumption floor. For them, optimal private annuitization is zero, and the observed near-zero ownership is the model’s prediction, not a deviation from it.

This concentration raises an identification concern: if predicted ownership lives in one quartile, is the channel ranking merely a description of that quartile? It is not. Recomputing the nine-channel Shapley separately within each wealth bin, pricing loads are the top demand suppressor in all 4 quartiles. The second-tier composition shifts with wealth—survival pessimism leads the second tier in the bottom two quartiles, the Med+R-S correlation in the third, and bequest motives in the top quartile, where Social Security also flips from a demand booster to a mild suppressor as households hold enough liquid wealth that the public floor no longer drives the annuitization margin—but the dominance of pricing loads is invariant across the distribution. The ranking is a property of the model, not an artifact of where ownership happens to concentrate.

## Empirical validation of the channel predictions

The ranking implies testable cross-sectional patterns in observed ownership, which I evaluate in the same HRS sample used to discipline the model (single nonworking retirees aged 65–69, waves 5–9). The resource and health channels predict that ownership rises with wealth (feasibility and the fixed-cost margin), falls with poor health at the purchase age (the Med+R-S valuation-risk channel), and falls with pre-existing annuitized income conditional on wealth (Social Security crowd-out). A weighted logit with person-clustered standard errors reproduces all three: the wealth gradient is positive and significant, the poor-health coefficient is negative, and pre-existing SS+DB income enters negatively conditional on wealth. Of the 7 channel-implied signs, 5 match the data. The two exceptions are the expectation-based channels: subjective survival optimism (from the HRS subjective-survival probability) enters with the wrong sign, and bequest intention (the self-reported probability of leaving a \$100,000 bequest) enters positively rather than negatively. Both survey proxies are confounded—bequest intention is strongly collinear with housing wealth, which itself predicts ownership, and subjective-survival reports are noisy and weakly correlated with realized mortality risk. These are exactly the channels whose identification the structural calibration is designed to bypass, and their failure to separate in a reduced-form regression is consistent with, rather than evidence against, the structural attribution.

## Heterogeneous welfare

Table <a href="#tab:cev_grid" data-reference-type="ref" data-reference="tab:cev_grid">11</a> reports the consumption-equivalent variation (CEV) from annuity market access under baseline pricing, across household types defined by initial wealth, health status, and bequest motive intensity.

<div id="tab:cev_grid">

| Wealth      | Health | No bequest | Moderate (DFJ) | Strong bequest |
|:------------|:-------|-----------:|---------------:|---------------:|
| \$10,000    | Good   |      0.00% |          0.00% |          0.00% |
|             | Fair   |      0.00% |          0.00% |          0.00% |
|             | Poor   |      0.00% |          0.00% |          0.00% |
|             |        |            |                |                |
| \$25,000    | Good   |      0.00% |          0.00% |          0.00% |
|             | Fair   |      0.00% |          0.00% |          0.00% |
|             | Poor   |      0.00% |          0.00% |          0.00% |
|             |        |            |                |                |
| \$50,000    | Good   |      0.00% |          0.00% |          0.00% |
|             | Fair   |      0.00% |          0.00% |          0.00% |
|             | Poor   |      0.00% |          0.00% |          0.00% |
|             |        |            |                |                |
| \$100,000   | Good   |      0.00% |          0.00% |          0.00% |
|             | Fair   |      0.00% |          0.00% |          0.00% |
|             | Poor   |      0.00% |          0.00% |          0.00% |
|             |        |            |                |                |
| \$200,000   | Good   |      0.00% |          0.00% |          0.00% |
|             | Fair   |      0.00% |          0.00% |          0.00% |
|             | Poor   |      0.00% |          0.00% |          0.00% |
|             |        |            |                |                |
| \$500,000   | Good   |      1.15% |          0.00% |          0.00% |
|             | Fair   |      0.82% |          0.00% |          0.00% |
|             | Poor   |      0.00% |          0.00% |          0.00% |
|             |        |            |                |                |
| \$1,000,000 | Good   |      4.68% |          0.28% |          0.00% |
|             | Fair   |      3.44% |          0.09% |          0.00% |
|             | Poor   |      2.23% |          0.00% |          0.00% |

Consumption-Equivalent Variation by Household Type

</div>

<div class="tablenotes">

CEV: consumption-equivalent variation (%). Positive values indicate welfare gain from annuity market access. Full model with medical costs, health-mortality correlation, MWR = 0.87, inflation = 2%, $`\gamma = 2.5`$.

</div>

#### Interpretation caveat.

The reported CEVs use the standard CRRA value-ratio approximation, $`\lambda = (V_{\text{with}}/V_{\text{without}})^{1/(1-\gamma)} - 1`$. This is exact under pure CRRA preferences with no non-homothetic terms. In this model, the bequest shifter $`\kappa`$, the consumption floor $`c_{\text{floor}}`$, source-dependent utility, the state-dependent $`\chi_{\text{LTC}}`$ consumption transformation in the Medicaid-binding Poor state, and the at-purchase penalty are non-CRRA value contributions, so the ratio formula is an approximation rather than exact compensating variation. The signs and ordering of CEV across cells are preserved by the approximation, though the reported magnitudes should be read as directional access-value statistics rather than exact welfare measures. Computing exact compensating variation would require solving $`V_{\text{without\_access}}(c \cdot (1+\lambda)) = V_{\text{with\_access}}`$ for $`\lambda`$ at each cell, which is left to future work.

Under the nine-channel structural baseline, the welfare gain from annuity market access is zero for most households and positive only at high wealth with weak bequest motives, where it is largest in good health. The largest single-cell CEV is 4.7% at \$1,000,000 in Good health under no bequests, falling to 0.3% under DFJ bequests at the same cell. At and below \$200,000, and at all Poor-health cells under DFJ or strong bequests, CEV is essentially zero; the one exception is the highest-wealth Poor-health cell under no bequest motive (Table <a href="#tab:cev_grid" data-reference-type="ref" data-reference="tab:cev_grid">11</a>). At the population level, mean CEV under DFJ bequests is 0.0%, with 7.7% of households deriving any positive welfare gain and 0.0% deriving gains exceeding 1% of consumption.

The economic content of these small CEVs is the same as the low predicted ownership rate: most households would not optimally purchase an annuity at current prices, so giving them access to the market provides little marginal value. The CEV grid is therefore the welfare counterpart of the ownership prediction—both confirm that the marginal household is approximately indifferent at the no-purchase margin. Larger welfare gains appear only when policy changes the optimal choice: lowering the load (group pricing) or modifying the choice architecture so that annuitization is the default, reported in Section <a href="#sec:counterfactuals" data-reference-type="ref" data-reference="sec:counterfactuals">4.12</a>.

Section <a href="#sec:counterfactuals" data-reference-type="ref" data-reference="sec:counterfactuals">4.12</a> examines how supply-side reforms change these welfare results.

#### Normative interpretation of the behavioral channels.

The exploratory behavioral channels (SDU, PED) carry a normatively contingent welfare interpretation (Bernheim and Rangel 2009; Beshears et al. 2008): under a preference interpretation of the underlying phenomena (welfare-relevant), agents already incorporate them into their utility function and “removing” them does not increase welfare; under a bias interpretation (welfare-irrelevant), removing them captures the full rational-utility gain. The empirical exercise in this paper does not adjudicate the preference-vs-bias choice; welfare claims involving the behavioral channels are reported with this caveat made explicit.

## Policy counterfactuals

Table <a href="#tab:counterfactuals" data-reference-type="ref" data-reference="tab:counterfactuals">12</a> reports predicted ownership under twelve policy scenarios that vary pricing, inflation protection, survival beliefs, and Social Security generosity. Table <a href="#tab:cev_counterfactuals" data-reference-type="ref" data-reference="tab:cev_counterfactuals">14</a> reports the corresponding welfare gains.

<div id="tab:counterfactuals">

| Policy Scenario | MWR | Inflation | Ownership (%) | $`\Delta`$ (pp) |
|:---|:--:|:--:|:--:|:--:|
| Baseline | 0.87 | 2% | 7.9 | — |
| Group pricing (MWR=0.90) | 0.90 | 2% | 12.1 | +4.2 |
| Public option (MWR=0.95) | 0.95 | 2% | 21.4 | +13.5 |
| Actuarially fair (MWR=1.0) | 1.00 | 2% | 31.5 | +23.6 |
| Real annuity, TIPS-backed | 0.78 | 0 (real) | 0.0 | -7.9 |
| Real annuity, nominal-equiv | 0.87 | 0 (real) | 9.7 | +1.8 |
| Fair + real | 1.00 | 0 (real) | 28.0 | +20.1 |
| SS cut 23% | 0.87 | 2% | 10.9 | +3.0 |
| Correct pessimism (psi=1.0) | 0.87 | 2% | 24.9 | +17.0 |
| Group + correct pessimism | 0.90 | 2% | 31.3 | +23.4 |
| Public consumption floor doubled | 0.87 | 2% | 4.1 | -3.8 |
| Best feasible package | 0.90 | 0 (real) | 30.1 | +22.2 |
| Observed (Lockwood 2012) |  |  | 3.6 |  |

Predicted Annuity Ownership Under Policy Counterfactuals

</div>

<div class="tablenotes">

Baseline: $`\gamma=2.5`$, $`\beta=0.97`$, DFJ bequests ($`\theta=56.96`$, $`\kappa=\$272{,}628`$), $`\psi=0.960`$. Population: HRS single nonworking retirees 65–69 with $`W \geq \$5{,}000`$ ($`N=2{,}279`$). Group pricing reflects TSP/employer plan MWR (James et al. 2006). SS cut: 23% reduction in Social Security benefits only; DB pension income is unaffected (projected trust fund exhaustion).

</div>

#### Pricing loads as a dominant supply-side lever.

Group annuity pricing (MWR $`= 0.90`$), achievable through employer plans or government-sponsored pools (James and Song 2006), raises predicted ownership to 12.1%. A public option at MWR $`= 0.95`$ reaches 21.4%, and an actuarially fair benchmark at MWR $`= 1.00`$ reaches 31.5%. These results quantify the pricing channel’s importance: a modest improvement in the money’s worth ratio—from 0.87 to 0.90—raises participation by roughly four percentage points relative to the nine-channel baseline.

#### Inflation protection.

A real annuity at the same MWR (0.87) leaves ownership essentially unchanged at 9.7%, while a TIPS-backed real annuity at MWR $`= 0.78`$ falls to 0.0%, illustrating that the pricing penalty for inflation indexing offsets most of the gain from removing inflation erosion. Combining inflation protection with fair pricing reaches 28.0%.

#### Social Security and the incidence of a benefit cut.

A 23% Social Security benefit cut—approximating the projected shortfall in the Old-Age and Survivors Insurance (OASI) trust fund, whose reserves the Social Security Trustees project to deplete in 2033, after which roughly 77% of scheduled benefits would be payable from continuing payroll-tax revenue (Board of Trustees, Federal Old-Age and Survivors Insurance and Federal Disability Insurance Trust Funds 2025); implemented as a permanent reduction to the Social Security component of the income floor with defined-benefit pension income held fixed—raises aggregate private annuity demand to 10.9%. Table <a href="#tab:ss_cut" data-reference-type="ref" data-reference="tab:ss_cut">13</a> reports the full schedule. The aggregate figure masks a sharp incidence across the wealth distribution (Section <a href="#sec:bywealth" data-reference-type="ref" data-reference="sec:bywealth">4.9</a>): the response is concentrated entirely in the top wealth quartile, where predicted ownership rises from 33.5% to 46.3% under the cut, while the bottom three quartiles show no response at all (0.0%), because the households most exposed to the cut are precisely those excluded from private annuitization by the minimum-purchase threshold and the binding consumption floor. Privatized longevity insurance does not backfill the public benefit cut where it bites hardest. It expands annuitization only among the wealthy, who least need the substitution. This is a stylized permanent reduction known at age 65, abstracting from transition uncertainty, announcement effects, and variation by claiming history and cohort.

<div id="tab:ss_cut">

| SS Benefit Cut           | Ownership (%) | Mean $`\alpha`$ | $`\Delta`$ (pp) |
|:-------------------------|:-------------:|:---------------:|:---------------:|
| 0% (baseline)            |      7.9      |      0.011      |        —        |
| 10%                      |      9.8      |      0.014      |      +1.9       |
| 15%                      |     10.4      |      0.016      |      +2.5       |
| 23% (trust fund)         |     10.9      |      0.018      |      +3.0       |
| 30%                      |     11.9      |      0.020      |      +4.0       |
| 40%                      |     13.0      |      0.024      |      +5.1       |
| 50%                      |     16.5      |      0.032      |      +8.6       |
| 100% (elimination)       |     43.1      |      0.131      |      +35.2      |
| Observed (Lockwood 2012) |      3.6      |                 |                 |

Private Annuity Demand Response to Social Security Benefit Reductions

</div>

<div class="tablenotes">

Structural model (rational, preference, and public-care aversion channels; behavioral channels off). A trust-fund shortfall cuts Social Security only; DB pension income survives. Baseline SS = \[\$13K, \$14K, \$15K, \$15K\], DB = \[\$5K, \$8K, \$11K, \$12K\]. 23% cut corresponds to projected trust fund exhaustion circa 2033. 100% cut eliminates Social Security entirely (DB pensions remain).

</div>

#### Best feasible (supply-side + information) package.

For ownership counterfactuals, the “best feasible” scenario combines group pricing (MWR $`= 0.90`$), inflation protection (real annuity), and corrected survival beliefs ($`\psi = 1.0`$), producing 30.1% ownership at the nine-channel structural baseline. This is the upper bound of the supply-side and information interventions on the model-internal channels, not a realistic forecast of market participation.

#### Demand-side architecture.

A demand-side lever distinct from pricing reform is changing the choice architecture so that annuitization is the default rather than an opt-in decision. Defaults are among the most powerful levers in retirement saving: automatic enrollment raises 401(k) participation by tens of percentage points (Madrian and Shea 2001). Whether comparable effects extend to annuitization is an open empirical question—no large-scale annuity-default experiment exists—but the analogy suggests demand-side architecture could rival the largest supply-side reforms considered here, while requiring no change to insurer pricing or product design.

<div id="tab:cev_counterfactuals">

<table>
<caption>Welfare Gain from Annuity Access Under Policy Counterfactuals (CEV, %)</caption>
<thead>
<tr>
<th style="text-align: left;">Wealth</th>
<th style="text-align: center;">Baseline</th>
<th style="text-align: center;">Group pricing</th>
<th style="text-align: center;">Real annuity</th>
<th style="text-align: center;">Best feasible</th>
</tr>
</thead>
<tbody>
<tr>
<td colspan="5" style="text-align: left;"><em>Panel A: Good Health, DFJ Bequests</em></td>
</tr>
<tr>
<td style="text-align: left;">$50K</td>
<td style="text-align: center;">0.00</td>
<td style="text-align: center;">0.00</td>
<td style="text-align: center;">0.00</td>
<td style="text-align: center;">0.00</td>
</tr>
<tr>
<td style="text-align: left;">$100K</td>
<td style="text-align: center;">0.00</td>
<td style="text-align: center;">0.00</td>
<td style="text-align: center;">0.00</td>
<td style="text-align: center;">0.00</td>
</tr>
<tr>
<td style="text-align: left;">$200K</td>
<td style="text-align: center;">0.00</td>
<td style="text-align: center;">0.00</td>
<td style="text-align: center;">0.00</td>
<td style="text-align: center;">0.00</td>
</tr>
<tr>
<td style="text-align: left;">$500K</td>
<td style="text-align: center;">0.00</td>
<td style="text-align: center;">0.00</td>
<td style="text-align: center;">0.00</td>
<td style="text-align: center;">2.50</td>
</tr>
<tr>
<td style="text-align: left;">$1000K</td>
<td style="text-align: center;">0.28</td>
<td style="text-align: center;">0.76</td>
<td style="text-align: center;">0.39</td>
<td style="text-align: center;">4.19</td>
</tr>
<tr>
<td colspan="5" style="text-align: left;"><em>Panel B: Fair Health, DFJ Bequests</em></td>
</tr>
<tr>
<td style="text-align: left;">$50K</td>
<td style="text-align: center;">0.00</td>
<td style="text-align: center;">0.00</td>
<td style="text-align: center;">0.00</td>
<td style="text-align: center;">0.00</td>
</tr>
<tr>
<td style="text-align: left;">$100K</td>
<td style="text-align: center;">0.00</td>
<td style="text-align: center;">0.00</td>
<td style="text-align: center;">0.00</td>
<td style="text-align: center;">0.00</td>
</tr>
<tr>
<td style="text-align: left;">$200K</td>
<td style="text-align: center;">0.00</td>
<td style="text-align: center;">0.00</td>
<td style="text-align: center;">0.00</td>
<td style="text-align: center;">0.00</td>
</tr>
<tr>
<td style="text-align: left;">$500K</td>
<td style="text-align: center;">0.00</td>
<td style="text-align: center;">0.00</td>
<td style="text-align: center;">0.00</td>
<td style="text-align: center;">1.85</td>
</tr>
<tr>
<td style="text-align: left;">$1000K</td>
<td style="text-align: center;">0.09</td>
<td style="text-align: center;">0.43</td>
<td style="text-align: center;">0.18</td>
<td style="text-align: center;">2.89</td>
</tr>
<tr>
<td colspan="5" style="text-align: left;"><em>Panel C: Good Health, No Bequests</em></td>
</tr>
<tr>
<td style="text-align: left;">$50K</td>
<td style="text-align: center;">0.00</td>
<td style="text-align: center;">0.00</td>
<td style="text-align: center;">0.00</td>
<td style="text-align: center;">0.00</td>
</tr>
<tr>
<td style="text-align: left;">$100K</td>
<td style="text-align: center;">0.00</td>
<td style="text-align: center;">0.00</td>
<td style="text-align: center;">0.00</td>
<td style="text-align: center;">0.00</td>
</tr>
<tr>
<td style="text-align: left;">$200K</td>
<td style="text-align: center;">0.00</td>
<td style="text-align: center;">0.00</td>
<td style="text-align: center;">0.00</td>
<td style="text-align: center;">0.28</td>
</tr>
<tr>
<td style="text-align: left;">$500K</td>
<td style="text-align: center;">1.15</td>
<td style="text-align: center;">2.24</td>
<td style="text-align: center;">1.19</td>
<td style="text-align: center;">5.04</td>
</tr>
<tr>
<td style="text-align: left;">$1000K</td>
<td style="text-align: center;">4.68</td>
<td style="text-align: center;">6.63</td>
<td style="text-align: center;">4.65</td>
<td style="text-align: center;">10.26</td>
</tr>
</tbody>
</table>

</div>

<div class="tablenotes">

CEV: consumption-equivalent variation (% of lifetime consumption agent would pay for annuity market access). Welfare model uses representative SS income (\$23,556/yr, midpoint of the middle wealth-bin floors). Baseline: MWR=0.87, 2% inflation, $`\psi=0.960`$; behavioral channels off. Group pricing: MWR=0.90. Real annuity: 0% inflation, MWR=0.87. Best feasible combines group pricing, real annuity, and no survival pessimism ($`\psi=1.0`$).

</div>

#### Welfare under reform.

Under baseline pricing, the welfare gain from market access is zero at and below \$200,000 across all bequest specifications and is positive only at high wealth (0.3% at \$1,000,000 in Good health with DFJ bequests, 4.7% without a bequest motive). Policy interventions that change the optimal choice raise these high-wealth gains. Group pricing (MWR $`= 0.90`$) lifts the \$1,000,000 Good/DFJ cell to 0.8%, and the “best feasible” package—group pricing, inflation protection, and corrected survival beliefs—reaches 2.5% at \$500,000 and 4.2% at \$1,000,000 (Good health, DFJ), higher still without a bequest motive (Table <a href="#tab:cev_counterfactuals" data-reference-type="ref" data-reference="tab:cev_counterfactuals">14</a>, Panel C). At and below \$200,000, CEV remains near zero even under the best-feasible package, consistent with annuitization being a high-wealth phenomenon. The values reported in the welfare table are a CRRA value-ratio welfare index. Because the model includes non-homothetic bequests and a consumption floor, these values should be read as directional access-value statistics rather than exact compensating variation. The ranking and signs across scenarios are preserved by the approximation.

The welfare analysis reframes the annuity puzzle. For the median retiree at current market conditions, non-annuitization is the correct response to loaded pricing, nominal payment erosion, correlated health and survival risk, pre-existing Social Security coverage, and declining consumption needs. The welfare case for annuitization emerges only when policy reforms also change the optimal choice: supply-side cost reductions and demand-side default architecture together raise CEV for high-wealth households in good health from near zero to as much as 4.2% of consumption, while leaving the welfare-neutral majority of the wealth distribution unaffected.

# Robustness

Table <a href="#A-tab:full_robustness" data-reference-type="ref" data-reference="A-tab:full_robustness">[A-tab:full_robustness]</a> in the appendix reports the full sensitivity analysis. Key dimensions are summarized here.

## Risk aversion

The sensitivity of predicted ownership to $`\gamma`$ is documented in Table <a href="#tab:robustness_gamma_inflation" data-reference-type="ref" data-reference="tab:robustness_gamma_inflation">9</a> and discussed in Section <a href="#sec:monte_carlo" data-reference-type="ref" data-reference="sec:monte_carlo">4.7</a>. At the baseline $`\gamma = 2.5`$, the eight-channel rational+preference model predicts 6.2%. Ownership is 0.0% for $`\gamma \leq 2.0`$, rises through 0.0% at $`\gamma = 2.3`$ and 0.4% at $`\gamma = 2.4`$, and reaches 22.7% at $`\gamma = 3.0`$. The six-channel rational model, which omits the two preference channels, predicts a higher 14.0% at the baseline.

Inflation has competing effects in the nominal-annuity calibration: it erodes the real value of later payments, but it also raises the initial nominal payout through the insurer’s pricing, which uses the nominal discount rate. The net effect on demand depends on which side dominates at the calibrated parameters. At the baseline $`\gamma = 2.5`$, predicted ownership falls monotonically over the empirically defensible range, from 6.8% at $`\pi = 1\%`$ to 5.1% at $`\pi = 3\%`$, indicating that payment erosion dominates the higher initial nominal payout at the calibrated margin.

## Health-mortality correlation

The hazard multipliers govern the strength of the Reichling–Smetters mechanism. The R-S functional estimates ($`[0.45, 1.0, 3.5]`$) produce 8.2% ownership; the HRS self-reported health estimates ($`[0.57, 1.0, 2.7]`$) produce 11.9%; the conservative specification ($`[0.60, 1.0, 2.0]`$) produces 17.2%. An age-varying specification that linearly interpolates the HRS estimates across the three age bands in Section <a href="#sec:calibration" data-reference-type="ref" data-reference="sec:calibration">3</a> produces 12.5%, reflecting the compression of the health-mortality gradient at older ages (the Poor-health multiplier falls from 3.29 at ages 65–74 to 1.82 at 85+). The qualitative pattern, that wider health gradients reduce annuity demand, holds across all parameterizations.

## Money’s worth ratio

Table <a href="#tab:mwr_sensitivity" data-reference-type="ref" data-reference="tab:mwr_sensitivity">15</a> reports ownership under MWR values from the policy counterfactual exercise.

<div class="threeparttable">

<div id="tab:mwr_sensitivity">

| MWR             | Ownership (%) |
|:----------------|:-------------:|
| 0.82            |      0.1      |
| 0.85            |      2.1      |
| 0.87 (baseline) |      7.9      |
| 0.90            |     11.5      |
| 0.95            |     19.6      |

Predicted Ownership by Money’s Worth Ratio

</div>

<div class="tablenotes">

Nine-channel structural baseline (rational + preferences + $`\chi_{\text{LTC}} = 0.49`$).

</div>

</div>

## Survival pessimism

Varying $`\psi`$ from 0.970 to 1.000 (objective beliefs) shifts predicted ownership from 10.7% to 26.2%. At the baseline $`\psi = 0.960`$, the model predicts 6.2%. The steep sensitivity confirms that survival pessimism is a quantitatively meaningful channel, consistent with its Shapley value of 10.9 pp.

## Additional robustness checks

#### Grid convergence.

On the mean-Social-Security diagnostic, predicted ownership ranges from 21.1% at the medium grid ($`60 \times 20`$) to 20.8% at the fine grid ($`100 \times 40`$), bracketing the production grid ($`80 \times 30`$, 20.0%; Table <a href="#A-tab:grid_convergence" data-reference-type="ref" data-reference="A-tab:grid_convergence">[A-tab:grid_convergence]</a>). The roughly 1.0 pp variation across grid resolutions is small relative to the Shapley channel contributions.

#### Quadrature convergence.

Binary ownership rises gradually with quadrature order (Table <a href="#A-tab:grid_convergence" data-reference-type="ref" data-reference="A-tab:grid_convergence">[A-tab:grid_convergence]</a>, Panel B): values at $`n_{\text{quad}} \in \{9, 11, 13, 15\}`$ are 20.0%, 20.5%, 21.1%, and 21.2% at the diagnostic specification, a range of 1.2 pp. Lower-order rules ($`n_{\text{quad}} \leq 7`$) deviate by up to 2 pp because the heavy lognormal medical-expense tail interacts with the Medicaid floor. Nine-node quadrature is adopted as a balance of accuracy and computational cost; Appendix <a href="#A-app:quadrature" data-reference-type="ref" data-reference="A-app:quadrature">[A-app:quadrature]</a> provides details.

#### Annuitization grid.

Because ownership is the discontinuous indicator $`\alpha^* > 0`$, the resolution of the age-65 annuitization grid could in principle shift marginal households across the participation threshold. Holding the wealth grid and quadrature at production resolution and varying $`n_\alpha`$ over $`\{51, 101, 201, 401\}`$ leaves predicted ownership within a 0.2 pp band (19.9% to 20.1%, 20.0% at the production $`n_\alpha = 101`$; Table <a href="#A-tab:grid_convergence" data-reference-type="ref" data-reference="A-tab:grid_convergence">[A-tab:grid_convergence]</a>, Panel D), so the participation level is not an artifact of the annuitization-grid resolution.

#### Bequest specification.

Under the nine-channel structural baseline, the DFJ luxury-good specification ($`\theta = 56.96`$, $`\kappa = \$272{,}628`$) produces 7.9% ownership; removing bequests raises this to 26.1%. See Section <a href="#sec:model" data-reference-type="ref" data-reference="sec:model">2</a> for discussion of why $`\theta`$ and $`\kappa`$ must be interpreted jointly.

#### Behavioral parameter sensitivity.

The eleven-channel extended specification is sensitive to the literature-magnitude calibrations of $`\lambda_W`$ and $`\psi_{\text{purchase}}`$. The reported sweeps span $`\lambda_W \in \{0.5, 0.625, 0.75, 0.85\}`$ and $`\psi_{\text{purchase}} \in \{0.01, 0.05, 0.09\}`$. At the production magnitudes, the at-purchase penalty saturates participation, which is why the nine-channel structural baseline—not the eleven-channel extended specification—is reported as the disciplined reading.

#### Numerical accuracy.

Euler equation residuals, grid convergence, and quadrature convergence diagnostics are reported in Appendices <a href="#A-app:grid_convergence" data-reference-type="ref" data-reference="A-app:grid_convergence">[A-app:grid_convergence]</a>, <a href="#A-app:quadrature" data-reference-type="ref" data-reference="A-app:quadrature">[A-app:quadrature]</a>, and <a href="#A-app:euler" data-reference-type="ref" data-reference="A-app:euler">[A-app:euler]</a>.

# Discussion

This paper is a calibrated structural exercise, not a formal estimation. All parameters are drawn from published sources. The main contribution is therefore quantitative accounting: how far the standard rational channels go, what the added preference channels contribute, and which mechanisms matter most once they are evaluated together.

Under the baseline calibration ($`\gamma = 2.5`$, MWR $`= 0.87`$), the six standard rational channels predict 14.0% ownership relative to a frictionless population benchmark of 46.5%—above both empirical targets and echoing the residual overprediction in Pashchenko (2013). The two preference channels bring the prediction to 6.2%, and adding the structural public-care aversion channel yields the nine-channel structural baseline of 7.9%, modestly above the two HRS measures ($`5.21\%`$ on the conventional any-annuity income proxy, 95% CI $`[4.45\%, 6.09\%]`$; $`3.11\%`$ on the cleaner lifetime-contract indicator, 95% CI $`[2.54\%, 3.81\%]`$). The disciplined reading is the nine-channel structural baseline, not a moment-matched fit.

The exact Shapley decomposition provides the clearest attribution hierarchy. The nine-channel structural Shapley (the disciplined headline) places pricing loads as the dominant demand-suppressing contributor, with survival pessimism and the combined Med+R-S health-mortality correlation as the co-leading second tier, and bequest motives mid-pack. Social Security enters with a large negative Shapley value as a complement that raises demand. State-dependent utility contributes a small positive magnitude, while inflation erosion and public-care aversion enter with small negative (demand-boosting) values in the current enumeration. That bequest motives—the literature’s most-cited explanation—rank below pricing, survival beliefs, and correlated health risk is itself a substantive correction to the received account. The eleven-channel extended Shapley adds SDU and PED at their literature magnitudes. PED carries the largest absolute contribution and SDU a large opposite-sign booster contribution, but these behavioral attributions are illustrative of where literature-magnitude behavioral parameters land in the ranking, not identification of the magnitudes themselves.

Two features of the exploratory behavioral results deserve emphasis because they bear on how readers should weigh the broader empirical literature. First, SDU and PED at literature-magnitude values are each individually larger than nearly any single rational, preference, or structural channel in the model, yet they operate in opposite directions and largely offset. The net behavioral effect on ownership is therefore small in level, even though each channel individually moves predictions substantially. Second, the eleven-channel prediction is sensitive to assumptions: modest shifts within the literature-defensible range for either $`\lambda_W`$ or $`\psi_{\text{purchase}}`$ produce large changes in predicted ownership. Given these dynamics, one would expect a meaningful amount of inconsistency in empirical and structural estimates of annuity demand across studies and over time, even when rational, preference, and structural factors are well identified, simply because small differences in implicit behavioral assumptions can amplify, offset, or override otherwise clean variation. This is consistent with the observed dispersion in prior multi-channel structural estimates.

The Social Security results illustrate the complement-substitute duality. In the frictionless environment, SS crowds *in* private annuity demand by providing an income floor that makes annuitization feasible. Once pricing loads and inflation erosion are active, the same SS income crowds *out* private annuity demand. The public-finance payoff is the incidence of a benefit cut: a 23% Social Security reduction raises private annuitization only in the top wealth quartile, while the households the cut most exposes cannot substitute at all. That asymmetry—privatized longevity insurance backfilling a public cut only for those who least need it—is a substantive result, not just a robustness check.

The baseline MWR of 0.87 is drawn from Mitchell et al. (1999) and Wettstein et al. (2021). Recent evidence suggests that annuity pricing has improved, with population-table MWRs near the baseline 0.87 for age-65 immediate annuities in recent market conditions. At MWR $`= 0.85`$, the model predicts 2.1% ownership (Table <a href="#tab:mwr_sensitivity" data-reference-type="ref" data-reference="tab:mwr_sensitivity">15</a>). Pricing remains the highest-leverage supply-side policy margin in this market.

Several modeling choices condition the results.

**Marital structure.** The model treats all retirees as single. Kotlikoff and Spivak (1981) showed that marriage provides partial longevity insurance through intra-household risk sharing, which would further reduce annuity demand among married couples.

**Housing wealth.** Housing wealth is excluded. Pashchenko (2013) found that housing illiquidity reduces annuity demand by constraining the liquid wealth available for annuitization.

**Subjective survival belief structure.** The survival pessimism channel uses a simple proportional scaling of one-year survival rates; the actual structure of subjective belief distortions may be more complex (O’Dea and Sturrock 2023).

**Age-varying consumption needs heterogeneity.** The age-varying consumption needs channel assumes a uniform 2% annual decline; heterogeneity in this rate across health states and wealth levels is not modeled.

**Exploratory behavioral parameters.** The eleven-channel extended specification uses $`\lambda_W = 0.625`$ and $`\psi_{\text{purchase}} = 0.05`$ as literature-magnitude best guesses rather than moment-matched calibrations. The at-purchase penalty saturates at the chosen magnitude, producing an eleven-channel prediction that overshoots in the opposite direction. The nine-channel structural baseline—not the eleven-channel specification—is the disciplined reading. A future US-moment-matched calibration of the behavioral channels would require an external annuitization moment that we do not adopt here precisely to preserve the out-of-sample reading.

The behavioral evidence base is wide. Blanchett and Finke (2024, 2025) document the spending differential that motivates the SDU $`\lambda_W`$ parameter. Hu and Scott (2007) showed analytically that cumulative-prospect-theory loss aversion reduces optimal annuitization substantially; Brown et al. (2008) and Chalmers and Reuter (2012) document the corresponding empirical patterns. Ameriks et al. (2020) document the importance of long-term care aversion in late-life saving decisions (operationalized through $`\chi_{\text{LTC}}`$). Madrian and Shea (2001) documents the dominance of defaults in retirement savings behavior more generally.

Deferred income annuities (DIAs) and qualified longevity annuity contracts (QLACs) have received attention as alternatives to immediate annuities. In an extension (Appendix <a href="#A-app:dia" data-reference-type="ref" data-reference="A-app:dia">[A-app:dia]</a>), DIA ownership rates are similar to SPIA rates. The lower MWR on deferred products—Wettstein et al. (2021) estimate MWRs of 0.50 for DIA-80 and 0.45 for DIA-85—offsets the actuarial advantage of concentrating payments in late life.

For policy, the counterfactual analysis identifies two distinct levers operating on different margins. Supply-side reform (group pricing at MWR $`= 0.90`$) raises the value of annuitization at the structural baseline. Demand-side reform (annuitization as default) is motivated by the broader evidence on the power of defaults in retirement saving (Madrian and Shea 2001), though no large-scale annuity-default experiment yet exists. These levers are not substitutes: pricing reform leaves the demand-side default-vs-opt-in margin unaddressed, and default architecture without pricing reform fails to capture households for whom the rational valuation gap is binding.

# Conclusion

This paper developed a structural lifecycle decomposition of the annuity puzzle. A nine-channel rational-plus-preference baseline predicts 7.9% US voluntary annuity ownership, modestly above the two HRS measures ($`5.21\%`$ on the conventional any-annuity income proxy, 95% CI $`[4.45\%, 6.09\%]`$; $`3.11\%`$ on the cleaner lifetime-contract indicator, 95% CI $`[2.54\%, 3.81\%]`$). This does not imply that behavioral factors do not matter. As an exploratory exercise, an eleven-channel extended specification layers two behavioral channels—source-dependent utility ($`\lambda_W = 0.625`$) and a narrow-framing at-purchase penalty ($`\psi_{\text{purchase}} = 0.05`$)—onto the baseline at literature-magnitude parameters. At these values each behavioral channel individually moves predicted ownership by more than almost any single rational, preference, or structural channel, but the two operate in opposite directions and largely offset. The eleven-channel prediction is 0.1% and is sensitive to assumptions—small shifts within the literature-defensible parameter range move predictions substantially in either direction—so the nine-channel structural baseline is the disciplined reading.

The nine-channel structural Shapley over all $`2^{9} = 512`$ subsets is the paper’s preferred order-independent attribution. Pricing loads are the dominant demand-suppressing contributor, with survival pessimism and the combined Med+R-S health-mortality channel as the co-leading second tier, and bequest motives mid-pack. Social Security enters with a large negative Shapley value as a complement that raises demand at the margin. The eleven-channel extended Shapley adds SDU and PED at literature magnitudes; PED carries the largest absolute contribution and SDU a large opposite-sign booster contribution, with both attributions explicitly illustrative rather than identified. Given that each behavioral channel individually exceeds nearly any single rational, preference, or structural channel in magnitude, and that the two largely offset, one would expect a meaningful amount of inconsistency in empirical and structural estimates of annuity demand across studies and over time—small differences in implicit behavioral assumptions can amplify, offset, or override otherwise clean variation in the channels typically identified.

Welfare and policy implications follow from the same calibration. Under current pricing, the welfare gain from annuity market access alone is concentrated at high wealth (4.7% at \$1,000,000 in Good health without a bequest motive; near zero at and below \$200,000), because most calibrated households would not optimally buy at current prices. Larger welfare gains require policy reforms that change the optimal choice: the best-feasible package reaches 4.2% at \$1,000,000 in Good health, higher still without a bequest motive, while remaining near zero below the top of the wealth distribution. Two distinct policy levers operate on different margins: supply-side reforms (group pricing) raise the value of annuitization at the structural baseline. Demand-side reforms (default architecture) operate on the choice-environment margin.

Research framing should therefore shift from “why don’t retirees annuitize?” to “which channels matter most, and what mix of supply-side and demand-side interventions would make annuitization welfare-improving, and for whom?”

# Data Availability

Replication code (Julia) and processed calibration data are available at <https://github.com/DerekTharp/annuity-puzzle-model>. Health transition matrices and wealth distributions are computed from the RAND HRS Longitudinal File (public use, available at <https://hrsdata.isr.umich.edu>). All other calibration parameters are taken from published sources cited in the text.

<figure id="fig:decomposition" data-latex-placement="htbp">
<embed src="../figures/pdf/fig1_decomposition.pdf" style="width:90.0%" />
<figcaption>Sequential decomposition of predicted annuity ownership (six-channel rational model). Each bar shows predicted ownership after adding the labeled channel to all previous channels. The dashed line marks observed ownership in the present sample (5.21% on the conventional any-annuity income proxy, 3.11% on the cleaner lifetime contract indicator).</figcaption>
</figure>

<figure id="fig:gamma" data-latex-placement="htbp">
<embed src="../figures/pdf/fig2_gamma_sensitivity.pdf" style="width:80.0%" />
<figcaption>Predicted ownership by coefficient of relative risk aversion (<span class="math inline"><em>γ</em></span>). All other parameters at baseline values (<span class="math inline"><em>π</em> = 2%</span>, MWR <span class="math inline"> = 0.87</span>, DFJ bequests). The shaded band marks observed ownership of 3–6%.</figcaption>
</figure>

<figure id="fig:hazard" data-latex-placement="htbp">
<embed src="../figures/pdf/fig3_hazard_sensitivity.pdf" style="width:80.0%" />
<figcaption>Predicted ownership by hazard multiplier specification. Each specification varies the Good- and Poor-health multipliers while holding Fair at 1.0. Labels indicate the empirical source for each calibration. The shaded band marks observed ownership of 3–6%.</figcaption>
</figure>

<figure id="fig:policy" data-latex-placement="htbp">
<embed src="../figures/pdf/fig4_policy_functions.pdf" />
<figcaption>Optimal annuitization fraction (<span class="math inline"><em>α</em><sup>*</sup></span>) at age 65 by initial wealth, for Good health (<span class="math inline"><em>H</em> = 1</span>). Left panel: no bequest motive, pricing loads and inflation active. Right panel: full model (DFJ bequests, medical risk, Reichling–Smetters correlation, pricing loads, inflation). Both panels use MWR <span class="math inline"> = 0.87</span> and <span class="math inline"><em>π</em> = 2%</span>.</figcaption>
</figure>

<figure id="fig:cev" data-latex-placement="htbp">
<embed src="../figures/pdf/fig5_cev_heatmap.pdf" style="width:80.0%" />
<figcaption>Consumption-equivalent variation (%) from annuity market access, by initial wealth and health status. No-bequest specification (<span class="math inline"><em>θ</em> = 0</span>). Full model with medical costs, Reichling–Smetters correlation, MWR <span class="math inline"> = 0.87</span>, and 2% inflation.</figcaption>
</figure>

<div id="refs" class="references csl-bib-body hanging-indent">

<div id="ref-aguiarhurst2013" class="csl-entry">

Aguiar, Mark, and Erik Hurst. 2013. “Deconstructing Life Cycle Expenditure.” *Journal of Political Economy* 121 (3): 437–92. <https://doi.org/10.1086/670740>.

</div>

<div id="ref-ameriks2020" class="csl-entry">

Ameriks, John, Joseph Briggs, Andrew Caplin, Matthew D. Shapiro, and Christopher Tonetti. 2020. “Long-Term-Care Utility and Late-in-Life Saving.” *Journal of Political Economy* 128 (6): 2375–451. <https://doi.org/10.1086/706686>.

</div>

<div id="ref-ameriks2011" class="csl-entry">

Ameriks, John, Andrew Caplin, Steven Laufer, and Stijn Van Nieuwerburgh. 2011. “The Joy of Giving or Assisted Living? Using Strategic Surveys to Separate Public Care Aversion from Bequest Motives.” *The Journal of Finance* 66 (2): 519–61.

</div>

<div id="ref-bernheimrangel2009" class="csl-entry">

Bernheim, B. Douglas, and Antonio Rangel. 2009. “Beyond Revealed Preference: Choice-Theoretic Foundations for Behavioral Welfare Economics.” *Quarterly Journal of Economics* 124 (1): 51–104. <https://doi.org/10.1162/qjec.2009.124.1.51>.

</div>

<div id="ref-beshears2008" class="csl-entry">

Beshears, John, James J. Choi, David Laibson, and Brigitte C. Madrian. 2008. “How Are Preferences Revealed?” *Journal of Public Economics* 92 (8–9): 1787–94. <https://doi.org/10.1016/j.jpubeco.2008.04.010>.

</div>

<div id="ref-blanchett2024" class="csl-entry">

Blanchett, David, and Michael S. Finke. 2024. “Guaranteed Income and the Retirement Spending Puzzle.” *Working Paper*.

</div>

<div id="ref-blanchett2025" class="csl-entry">

Blanchett, David, and Michael S. Finke. 2025. “Guaranteed Income: A License to Spend.” *The Journal of Retirement*.

</div>

<div id="ref-ssatrustees2025" class="csl-entry">

Board of Trustees, Federal Old-Age and Survivors Insurance and Federal Disability Insurance Trust Funds. 2025. *The 2025 Annual Report of the Board of Trustees of the Federal Old-Age and Survivors Insurance and Federal Disability Insurance Trust Funds*. U.S. Social Security Administration, Washington, DC.

</div>

<div id="ref-brown2008framing" class="csl-entry">

Brown, Jeffrey R., Jeffrey R. Kling, Sendhil Mullainathan, and Marian V. Wrobel. 2008. “Why Don’t People Insure Late-Life Consumption? A Framing Explanation of the Under-Annuitization Puzzle.” *American Economic Review: Papers and Proceedings* 98 (2): 304–9. <https://doi.org/10.1257/aer.98.2.304>.

</div>

<div id="ref-chalmersreuter2012" class="csl-entry">

Chalmers, John, and Jonathan Reuter. 2012. *Is Conflicted Investment Advice Better Than No Advice?* Working Paper No. 18158. National Bureau of Economic Research.

</div>

<div id="ref-chetty2006" class="csl-entry">

Chetty, Raj. 2006. “A New Method of Estimating Risk Aversion.” *American Economic Review* 96 (5): 1821–34.

</div>

<div id="ref-davidoff2005" class="csl-entry">

Davidoff, Thomas, Jeffrey R. Brown, and Peter A. Diamond. 2005. “Annuities and Individual Welfare.” *American Economic Review* 95 (5): 1573–90. <https://doi.org/10.1257/000282805775014281>.

</div>

<div id="ref-denardi2004" class="csl-entry">

De Nardi, Mariacristina. 2004. “Wealth Inequality and Intergenerational Links.” *Review of Economic Studies* 71 (3): 743–68.

</div>

<div id="ref-denardi2010" class="csl-entry">

De Nardi, Mariacristina, Eric French, and John B. Jones. 2010. “Why Do the Elderly Save? The Role of Medical Expenses.” *Journal of Political Economy* 118 (1): 39–75. <https://doi.org/10.1086/651674>.

</div>

<div id="ref-dushiwebb2004" class="csl-entry">

Dushi, Irena, and Anthony Webb. 2004. “Household Annuitization Decisions: Simulations and Empirical Analyses.” *Journal of Pension Economics and Finance* 3 (2): 109–43. <https://doi.org/10.1017/S1474747204001696>.

</div>

<div id="ref-finkelsteinluttmer2013" class="csl-entry">

Finkelstein, Amy, Erzo F. P. Luttmer, and Matthew J. Notowidigdo. 2013. “What Good Is Wealth Without Health? The Effect of Health on the Marginal Utility of Consumption.” *Journal of the European Economic Association* 11 (S1): 221–58. <https://doi.org/10.1111/j.1542-4774.2012.01101.x>.

</div>

<div id="ref-heimer2019" class="csl-entry">

Heimer, Rawley Z., Kristian Ove R. Myrseth, and Raphael S. Schoenle. 2019. “YOLO: Mortality Beliefs and Household Finance Puzzles.” *The Journal of Finance* 74 (6): 2957–96. <https://doi.org/10.1111/jofi.12828>.

</div>

<div id="ref-huscott2007" class="csl-entry">

Hu, Wei-Yin, and Jason S. Scott. 2007. “Behavioral Obstacles in the Annuity Market.” *Financial Analysts Journal* 63 (6): 71–82.

</div>

<div id="ref-james2006" class="csl-entry">

James, Estelle, and Xue Song. 2006. *Annuities Markets Around the World: Money’s Worth and Risk Intermediation*. CeRP Working Paper 16/01. Center for Research on Pensions; Welfare Policies.

</div>

<div id="ref-jones2018" class="csl-entry">

Jones, John Bailey, Mariacristina De Nardi, Eric French, Rory McGee, and Justin Kirschner. 2018. *The Lifetime Medical Spending of Retirees*. Working Paper No. 24599. National Bureau of Economic Research.

</div>

<div id="ref-kotlikoffspivak1981" class="csl-entry">

Kotlikoff, Laurence J., and Avia Spivak. 1981. “The Family as an Incomplete Annuities Market.” *Journal of Political Economy* 89 (2): 372–91.

</div>

<div id="ref-lockwood2012" class="csl-entry">

Lockwood, Lee M. 2012. “Bequest Motives and the Annuity Puzzle.” *Review of Economic Dynamics* 15 (2): 226–43. <https://doi.org/10.1016/j.red.2011.03.001>.

</div>

<div id="ref-madrian2001" class="csl-entry">

Madrian, Brigitte C., and Dennis F. Shea. 2001. “The Power of Suggestion: Inertia in 401(k) Participation and Savings Behavior.” *The Quarterly Journal of Economics* 116 (4): 1149–87.

</div>

<div id="ref-mitchell1999" class="csl-entry">

Mitchell, Olivia S., James M. Poterba, Mark J. Warshawsky, and Jeffrey R. Brown. 1999. “New Evidence on the Money’s Worth of Individual Annuities.” *American Economic Review* 89 (5): 1299–318.

</div>

<div id="ref-odeasturrock2023" class="csl-entry">

O’Dea, Cormac, and David Sturrock. 2023. “Survival Pessimism and the Demand for Annuities.” *The Review of Economics and Statistics* 105 (2): 442–57. <https://doi.org/10.1162/rest_a_01048>.

</div>

<div id="ref-pashchenko2013" class="csl-entry">

Pashchenko, Svetlana. 2013. “Accounting for Non-Annuitization.” *Journal of Public Economics* 98: 53–67. <https://doi.org/10.1016/j.jpubeco.2012.11.005>.

</div>

<div id="ref-payne2013" class="csl-entry">

Payne, John W., Namika Sagara, Suzanne B. Shu, Kirstin C. Appelt, and Eric J. Johnson. 2013. “Life Expectancy as a Constructed Belief: Evidence of a Live-to or Die-by Framing Effect.” *Journal of Risk and Uncertainty* 46 (1): 27–50. <https://doi.org/10.1007/s11166-012-9158-0>.

</div>

<div id="ref-peijnenburg2016" class="csl-entry">

Peijnenburg, Kim, Theo Nijman, and Bas J. M. Werker. 2016. “The Annuity Puzzle Remains a Puzzle.” *Journal of Economic Dynamics and Control* 70: 18–35. <https://doi.org/10.1016/j.jedc.2016.05.023>.

</div>

<div id="ref-poterbaventiwise2011" class="csl-entry">

Poterba, James, Steven Venti, and David Wise. 2011. “The Composition and Drawdown of Wealth in Retirement.” *Journal of Economic Perspectives* 25 (4): 95–118. <https://doi.org/10.1257/jep.25.4.95>.

</div>

<div id="ref-reichlingsmetters2015" class="csl-entry">

Reichling, Felix, and Kent Smetters. 2015. “Optimal Annuitization with Stochastic Mortality and Correlated Medical Costs.” *American Economic Review* 105 (11): 3273–320. <https://doi.org/10.1257/aer.20131584>.

</div>

<div id="ref-shefrin1988" class="csl-entry">

Shefrin, Hersh M., and Richard H. Thaler. 1988. “The Behavioral Life-Cycle Hypothesis.” *Economic Inquiry* 26 (4): 609–43. <https://doi.org/10.1111/j.1465-7295.1988.tb01520.x>.

</div>

<div id="ref-thaler1999" class="csl-entry">

Thaler, Richard H. 1999. “Mental Accounting Matters.” *Journal of Behavioral Decision Making* 12 (3): 183–206. [https://doi.org/10.1002/(SICI)1099-0771(199909)12:3\<183::AID-BDM318\>3.0.CO;2-F](https://doi.org/10.1002/(SICI)1099-0771(199909)12:3<183::AID-BDM318>3.0.CO;2-F).

</div>

<div id="ref-tharp2025survey" class="csl-entry">

Tharp, Derek. 2025. “Dissolving the Annuity Puzzle: A Critical Survey.” Unpublished manuscript.

</div>

<div id="ref-tharpFPR2026" class="csl-entry">

Tharp, Derek. 2026. *Revisiting the Social Security Claiming Puzzle: Behavioral Preferences as Rational Explanations for Early Claiming*. Under review (revise and resubmit) at *Financial Planning Review*. Calibrates source-dependent utility parameter $`\lambda_W = 0.625`$ to the same Blanchett-Finke spending differential used for source-dependent utility in the present paper.

</div>

<div id="ref-wettstein2021" class="csl-entry">

Wettstein, Gal, Alicia H. Munnell, Wenliang Hou, and Nilufer Gok. 2021. *The Value of Annuities*. Working Paper CRR WP 2021-5. Center for Retirement Research at Boston College.

</div>

<div id="ref-yaari1965" class="csl-entry">

Yaari, Menahem E. 1965. “Uncertain Lifetime, Life Insurance, and the Theory of the Consumer.” *The Review of Economic Studies* 32 (2): 137–50.

</div>

</div>

[^1]: Department of Accounting & Finance, University of Southern Maine. Email: <derek.tharp@maine.edu>.

[^2]: Generative AI tools were used to assist with code development, manuscript preparation, and editing. All analysis, interpretation, and conclusions are the sole responsibility of the author. Replication code and data are available at <https://github.com/DerekTharp/annuity-puzzle-model>.

[^3]: The two HRS measures differ because the income proxy ($`r{w}iann`$) classifies any positive annuity income as ownership, including one-time DC pension withdrawals and short-period payouts; the lifetime contract indicator (the question stem “Will this continue for the rest of your life?”) isolates true life-contingent annuity contracts. Section <a href="#sec:calibration" data-reference-type="ref" data-reference="sec:calibration">3</a> discusses both measures in detail.

[^4]: At $`\kappa = \$10`$, marginal bequest utility near $`b = 0`$ is $`\theta \cdot 10^{-\gamma}`$, which is extreme relative to marginal consumption utility. Individuals avoid annuitizing not to protect bequests, but to avoid near-zero-wealth states where $`v'(b)`$ becomes very large. The implementation applies a small numerical floor at $`\max(b + \kappa, 1)`$ to prevent overflow at $`b = 0`$ when $`\kappa = 0`$ is used as a robustness check; with the production DFJ calibration ($`\kappa = \$272{,}628`$) the floor never binds. See Appendix <a href="#A-app:bequest" data-reference-type="ref" data-reference="A-app:bequest">[A-app:bequest]</a> for details.

[^5]: The MWR is computed using beginning-of-period payment timing: the first payment occurs at purchase. This convention is standard in the annuity pricing literature (Mitchell et al. 1999) and matches the implementation in the replication code.

[^6]: Lockwood’s measure is constructed from wave-specific HRS pension and income variables; the RAND HRS Longitudinal File’s `r{w}iann` is the canonical pooled variable that subsequent literature has used as the analogous measure across waves. The two yield essentially identical pooled rates for single retirees 65–69, but readers seeking exact variable mapping to Lockwood’s construct should consult his data appendix.
