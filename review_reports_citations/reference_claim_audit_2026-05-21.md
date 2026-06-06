# Reference and Claim Audit

Date: 2026-05-21

Scope: `paper/main.tex`, `paper/appendix.tex`, and `paper/bibliography.bib`.

Method: four true reviewer agents audited independent slices of the manuscript, then I consolidated their findings with a local citation-line pass and DOI/Crossref/official-page checks. Direct source text is intentionally clipped to short cues; use the source locator/DOI for full context.

## Executive Summary

- Bibliography entries in `paper/bibliography.bib`: 61.
- Citation keys used in manuscript/appendix: 39.
- Cited keys missing from bibliography: `heimer2019`, `payne2013`.
- Bibliography entries not cited in the current manuscript: `abel1990`, `ameriks2011`, `benartzi2011`, `beshears2014`, `brown2007`, `brownfinkelstein2008`, `brownmitchellpoterba2002`, `chetty2015`, `denardi2016`, `finkelsteinpoterba2002`, `finkelsteinpoterba2004`, `hastings2013`, `heckmanpinto2018`, `hosseini2015`, `hurd1989`, `inkmann2011`, `kahnemantversky1979`, `kopczuklupton2007`, `laibson1997`, `lockwood2018`, `spillmanlubitz2002`, `tharp2025survey`, `tharpFPR2026`, `tharpforthcoming`.
- Highest-risk bibliography errors: `barberishuang2009` and `hosseini2015` have DOI fields that resolve to the wrong paper; `goda2014`, `cribb2018annuity`, `cannon2016annuity`, `abi2020`, and `fca2025` have notes/usage that overstate or mismatch the source.
- Highest-risk claim errors: Jones et al. medical spending moments are misdescribed as pure OOP when the age-100 moments are combined OOP plus Medicaid; O'Dea-Sturrock supports survival pessimism but not the exact `psi=0.960`; Chetty does not support a clean 1-3 CRRA range with `gamma=2.5` as ordinary; Goda (2014) does not support TSP annuity/default claims; UK transport claims need a harmonized denominator and stable official sources.

## Reference List Audit

| Key | Cited? | Status | Audit finding and correction |
|---|---:|---|---|
| `yaari1965` | Yes | Needs correction | Metadata appears correct; add DOI `10.2307/2296058`. |
| `lockwood2012` | Yes | OK | DOI `10.1016/j.red.2011.03.001` resolves correctly. |
| `lockwood2018` | No | OK | DOI `10.1257/aer.20141651` resolves correctly. |
| `reichlingsmetters2015` | Yes | OK | DOI `10.1257/aer.20131584` resolves correctly. |
| `pashchenko2013` | Yes | OK | DOI `10.1016/j.jpubeco.2012.11.005` resolves correctly. |
| `peijnenburg2016` | Yes | OK | DOI `10.1016/j.jedc.2016.05.023` resolves correctly. |
| `davidoff2005` | Yes | OK | DOI `10.1257/000282805775014281` resolves correctly. |
| `mitchell1999` | Yes | Needs correction | Add DOI `10.1257/aer.89.5.1299`. |
| `denardi2010` | Yes | OK | DOI `10.1086/651674` resolves correctly. |
| `denardi2016` | No | OK | DOI `10.1146/annurev-economics-080315-015127` resolves correctly. |
| `jones2018` | Yes | Needs correction | Add NBER DOI `10.3386/w24599`; Richmond Fed version also lists DOI `10.21144/eq1040301`. |
| `ameriks2011` | No | Needs correction | Add DOI `10.1111/j.1540-6261.2010.01641.x`. |
| `brown2007` | No | Needs correction | Add NBER DOI `10.3386/w13537`. |
| `brown2008framing` | Yes | OK | DOI `10.1257/aer.98.2.304` resolves correctly. |
| `brownfinkelstein2008` | No | OK | DOI `10.1257/aer.98.3.1083` resolves correctly. |
| `brownmitchellpoterba2002` | No | Needs correction | NBER chapter source lists publication year 2001 and pages 321-370; current year 2002 should be checked. |
| `dushiwebb2004` | Yes | OK | DOI `10.1017/S1474747204001696` resolves correctly. |
| `finkelsteinpoterba2002` | No | Needs correction | Add DOI `10.1111/1468-0297.0j672`. |
| `finkelsteinpoterba2004` | No | OK | DOI `10.1086/379936` resolves correctly. |
| `huscott2007` | Yes | Needs correction | Add DOI `10.2469/faj.v63.n6.4928`. |
| `kopczuklupton2007` | No | Needs correction | Add DOI `10.1111/j.1467-937X.2007.00419.x`. |
| `kotlikoffspivak1981` | Yes | Needs correction | Add DOI `10.1086/260970`. |
| `poterbaventiwise2011` | Yes | OK | DOI `10.1257/jep.25.4.95` resolves correctly; weak support for exact voluntary-annuity ownership statistic. |
| `spillmanlubitz2002` | No | Needs correction | Add DOI `10.1097/00005650-200210000-00013`. |
| `tverskykahneman1992` | Yes | Needs correction | Add DOI `10.1007/BF00122574`. |
| `kahnemantversky1979` | No | Needs correction | Add DOI `10.2307/1914185`. |
| `hurd1989` | No | Needs correction | Add DOI `10.2307/1913772`. |
| `wettstein2021` | Yes | Needs correction | Add stable CRR URL and optional SSRN DOI `10.2139/ssrn.3797822`. |
| `laibson1997` | No | Needs correction | Add DOI `10.1162/003355397555253`. |
| `chetty2015` | No | OK | DOI `10.1257/aer.p20151108` resolves correctly. |
| `inkmann2011` | No | OK | DOI `10.1093/rfs/hhq080` resolves correctly. |
| `abel1990` | No | OK | Article metadata appears correct; no final-article DOI found. |
| `benartzi2011` | No | OK | DOI `10.1257/jep.25.4.143` resolves correctly. |
| `beshears2014` | No | OK | DOI `10.1016/j.jpubeco.2013.05.007` resolves correctly. |
| `beshears2008` | Yes | OK | DOI `10.1016/j.jpubeco.2008.04.010` resolves correctly. |
| `bernheimrangel2009` | Yes | OK | DOI `10.1162/qjec.2009.124.1.51` resolves correctly. |
| `chalmersreuter2012` | Yes | Needs correction | Add NBER DOI `10.3386/w18158` or cite the published JFE version DOI `10.1016/j.jfineco.2020.05.005`; current use for narrow-framing magnitude is weak. |
| `denardi2004` | Yes | Needs correction | Add DOI `10.1111/j.1467-937X.2004.00302.x`. |
| `chetty2006` | Yes | Needs correction | Add DOI `10.1257/aer.96.5.1821`. |
| `madrian2001` | Yes | Needs correction | Add DOI `10.1162/003355301753265543`. |
| `hosseini2015` | No | Wrong DOI | Current DOI resolves to a different AEJ Macro paper; correct Hosseini annuity paper is JPE 123(4):941-984, DOI `10.1086/681593`. |
| `ameriks2020` | Yes | OK | DOI `10.1086/706686` resolves correctly. |
| `odeasturrock2023` | Yes | OK | DOI `10.1162/rest_a_01048` resolves correctly. |
| `james2006` | Yes | Needs correction | Source appears to be CeRP WP 16/01 from 2001, not 2006; add stable CeRP URL and optional SSRN DOI `10.2139/ssrn.287375`. |
| `tharp2025survey` | No | Unable | Internal/unpublished; verify manually or add working-paper URL. |
| `tharpforthcoming` | No | Unable | Internal/unpublished and duplicate-looking; verify or deduplicate with `tharp2025survey`. |
| `aguiarhurst2013` | Yes | OK | DOI `10.1086/670740` resolves correctly. |
| `finkelsteinluttmer2013` | Yes | OK | DOI `10.1111/j.1542-4774.2012.01101.x` resolves correctly. |
| `blanchett2025` | Yes | Needs correction | Could not verify current "Journal of Retirement forthcoming" metadata; closest 2025 RII paper is "Retirees Spend Lifetime Income, Not Savings." |
| `blanchett2024` | Yes | Needs correction | Could not verify current title; likely replace with "Guaranteed Income: A License to Spend," RII Original Research #028-2024. |
| `barberishuang2009` | Yes | Wrong DOI | Current DOI resolves to a different JEDC paper; correct DOI is `10.1016/j.jedc.2009.01.009`, pages 1555-1576. |
| `abi2020` | Yes | Needs correction | Current URL is generic ABI homepage; use the specific "Five years on: future-proofing the freedoms" report URL and remove unsupported sales-note claims unless sourced. |
| `cribb2018annuity` | Yes | Needs correction | Metadata/claim mismatch; source is not a pension-freedoms annuity-retention paper. Use IFS DOI `10.1920/wp.ifs.2016.1619` if citing that paper, or replace for UK decumulation claims. |
| `cannon2016annuity` | Yes | Needs correction | Current metadata points to Dutch annuity-market work; if UK reform evidence is intended, use the JPubE UK paper DOI `10.1016/j.jpubeco.2016.07.002`. |
| `fca2025` | Yes | Needs correction | URL valid; note overclaims causal/rate-confound inference. Keep as descriptive FCA statistics only. |
| `heckmanpinto2018` | No | Needs correction | Add DOI `10.3982/ECTA13777`; note overstates direct transportability relevance. |
| `tharpFPR2026` | No | Unable | Internal under-review item; verify manually or add preprint URL. |
| `shefrin1988` | Yes | OK | DOI `10.1111/j.1465-7295.1988.tb01520.x` resolves correctly. |
| `thaler1999` | Yes | OK | DOI resolves correctly: `10.1002/(SICI)1099-0771(199909)12:3<183::AID-BDM318>3.0.CO;2-F`. |
| `goda2014` | Yes | Claim mismatch | Metadata/DOI are OK, but the paper is about retirement income projections and saving, not TSP annuity defaults. Remove the note and do not use for TSP/default claims. |
| `hastings2013` | No | OK | DOI `10.1093/qje/qjt018` resolves correctly. |
| `heimer2019` | Yes | Missing | Add Heimer, Myrseth, Schoenle, "YOLO: Mortality Beliefs and Household Finance Puzzles," JF 74(6):2957-2996, DOI `10.1111/jofi.12828`. |
| `payne2013` | Yes | Missing | Add Payne et al., "Life expectancy as a constructed belief," JRU 46(1):27-50, DOI `10.1007/s11166-012-9158-0`. |

## Claim-Level Audit

| Manuscript location | Citation key(s) | Manuscript claim attached to citation | Direct source text cue | Assessment | Recommended fix |
|---|---|---|---|---|---|
| `paper/main.tex:65` | `yaari1965` | No-bequest actuarially fair benchmark implies full annuitization. | "actuarial notes" | Supported | Keep; retain assumptions next to claim. |
| `paper/main.tex:65,93,230,526`; `paper/appendix.tex:133` | `aguiarhurst2013` | Age-varying needs/expenditure decline lowers annuity value; calibration uses about 2 percent annual decline. | "life-cycle expenditure" | Partially supported | Source supports expenditure decline/composition, but exact 2 percent annuity-valuation mapping needs table/page calculation or softer wording. |
| `paper/main.tex:65,93,244,251,420,440,528`; `paper/appendix.tex:164` | `finkelsteinluttmer2013`, `reichlingsmetters2015` | Poor health lowers marginal utility of consumption; weights are mapped into model. | "marginal utility ... declines" | Partially supported | Direction and broad 10-25 percent range supported; exact Good/Fair/Poor weights should be described as derived/adapted, not directly taken. |
| `paper/main.tex:68,95,260,423,444`; `paper/appendix.tex:171` | `blanchett2024`, `blanchett2025`, `shefrin1988`, `thaler1999` | SDU/mental accounting: retirees spend more from guaranteed income than portfolio wealth; lambdaW 0.625. | "mental accounting" | Partially supported | Treat lambdaW as exploratory mapping. Verify Blanchett/Finke metadata and cite exact table for 50/80 spending differential. |
| `paper/main.tex:68,95,267,424,444,734`; `paper/appendix.tex:171` | `brown2008framing`, `huscott2007`, `chalmersreuter2012`, `barberishuang2009`, `tverskykahneman1992` | Narrow framing/prospect-theory purchase penalty explains annuity aversion; psi_purchase calibrated to literature magnitude. | "investment frame" | Partially supported | Literature supports framing/loss aversion generally; the specific utility penalty is the manuscript's construct. Replace/qualify `chalmersreuter2012`; fix `barberishuang2009` DOI. |
| `paper/main.tex:71,97,285,426,633`; `paper/appendix.tex:291` | `abi2020`, `fca2025` | UK 2015 reform shifted from de facto compulsory annuitization to opt-in; post-reform retention around mid anchor; 87-89 pp drop. | "action consumers take first time" | Partially supported | Direction supported, but exact pre/post denominators and retention ratio need stable official table citations and harmonized denominator. |
| `paper/main.tex:71,97` | `fca2025` | 2024/25 annuity share around 9 percent despite 14-year-high gilt yields rules out a rate confound. | "Retirement income market data" | Misleading | FCA supports product-choice data, not gilt-yield history or causal exclusion. Weaken to descriptive persistence and cite rate series separately. |
| `paper/main.tex:91` | `davidoff2005` | Partial annuitization remains optimal under broad incomplete-market conditions. | "positive annuitization" | Supported | Keep but avoid implying Davidoff always implies full annuitization. |
| `paper/main.tex:91,472,478` | `lockwood2012`, `dushiwebb2004`, `poterbaventiwise2011` | Voluntary annuity ownership among single older US retirees is only a few percent. | "3.6 percent" | Partially supported | Lockwood/Dushi-Webb support this; Poterba-Venti-Wise is weaker for the exact ownership statistic. Use Poterba only for wealth/drawdown context. |
| `paper/main.tex:91,472,478` | `lockwood2012` plus HRS/RAND variables | HRS q286 is cleaner lifetime contract indicator; `r{w}iann` is broad any-annuity income proxy and can include non-life-contingent payouts. | "continue ... as long as you live" | Partially supported | Variable definitions supported; add direct HRS/RAND documentation for DC withdrawals/short-period inclusion or soften. |
| `paper/main.tex:93,164,509,574`; `paper/appendix.tex:293` | `reichlingsmetters2015` | Health shocks reduce annuity value while raising liquidity/medical needs; R-S correlation is key. | "value ... correlated with medical costs" | Supported | Keep; clarify where hazard multipliers are your reduced-form calibration. |
| `paper/main.tex:93,168,408,728`; `paper/appendix.tex:126` | `odeasturrock2023` | Survival pessimism reduces annuity demand; manuscript's proportional scalar psi=0.960 is broadly consistent with evidence. | "underestimate survival" | Misleading | O'Dea-Sturrock supports pessimism, not exact scalar. `(0.71/0.86)^(1/10)` is about 0.981, not 0.960. Label 0.960 aggressive or recalibrate. |
| `paper/main.tex:93,421,734` | `ameriks2020` | Public-care aversion raises value of liquid wealth; manuscript uses chi_LTC=0.7. | "public care aversion" | Partially supported | Qualitative mechanism supported; chi_LTC is not directly Ameriks' parameter. Provide transformation or cite only qualitatively. |
| `paper/main.tex:101,204,415,450,720`; `paper/appendix.tex:450` | `wettstein2021`, `mitchell1999` | Modern/historical MWR values justify baseline 0.87 and sensitivity range. | "80 and 85 cents" | Partially supported | Mitchell supports historical 0.80-0.85; Wettstein supports recent range up to 0.87. Add newer quote source if 0.87 is central. |
| `paper/main.tex:103,509,570,712`; `paper/appendix.tex:277,291` | `pashchenko2013` | Pashchenko includes several channels and predicts around 20 percent, above observed annuity ownership. | "still higher than ... observed" | Supported with nuance | Use specific table value (about 19.6 or 20.8 depending specification) and observed comparator (about 6.2 in her table if used). |
| `paper/main.tex:103,509,574`; `paper/appendix.tex:291` | `pashchenko2013`, `peijnenburg2016` | Prior multi-channel models omitted the combined R-S health-cost valuation-risk channel. | "background risk ... default risk" | Supported with nuance | Phrase as "omitted the specific Reichling-Smetters correlated health-cost valuation-risk mechanism"; Pashchenko does include health/medical risk more generally. |
| `paper/main.tex:103,574` | `peijnenburg2016` | Full annuitization remains approximately optimal in their framework. | "full annuitization remains optimal" | Supported | Keep. |
| `paper/main.tex:107,633,734` | `goda2014` | Federal TSP/default architecture evidence documents about 86 pp default-vs-opt-in gap. | "income projections affect" | Unsupported | Goda (2014) is about income projections and saving. Replace with true TSP/default source or remove. |
| `paper/main.tex:140,399`; `paper/appendix.tex:251,255,260` | `denardi2004`, `lockwood2012` | Bequest utility follows DFJ/Lockwood luxury-good form; theta/kappa taken from Lockwood who estimated them from HRS. | "bequests are luxury goods" | Partially supported | Functional form supported. But Lockwood imports/reports DFJ/De Nardi estimates; do not say Lockwood estimated the exact parameters unless citing his own estimation table/code. |
| `paper/main.tex:142`; `paper/appendix.tex:255` | `lockwood2012` | Theta and kappa must be interpreted jointly; mixing them is invalid. | "threshold" | Partially supported | Economic logic is correct, but this is your implementation rule. Present as model discipline, not as Lockwood's direct claim. |
| `paper/main.tex:150,452`; `paper/appendix.tex:63` | `denardi2010` | Health transition matrices calibrated from HRS/RAND, mapped to three states and age bands. | "bad health" | Partially supported | DFJ supports HRS health/mortality estimation generally; exact 5-to-3 mapping and six age bands are your construction and need appendix/data citation. |
| `paper/main.tex:155,402,452`; `paper/appendix.tex:95` | `lockwood2012` | Survival uses SSA life table/max-age convention from Lockwood and his replication code. | "maximum possible age" | Partially supported | Life-table convention supported if code/table align; BAP_sim2.m should be cited as replication code, not article text. |
| `paper/main.tex:184,410-412,470`; `paper/appendix.tex:81-90` | `jones2018` | Medical spending: OOP is 4,200 at 70, 29,700 at 100, 95th percentile 111,200. | "sum of out-of-pocket and Medicaid" | Misleading | Revise: 4,200 is OOP at 70; 5,100/29,700/111,200 are combined OOP plus Medicaid. Fix table labels and text. |
| `paper/main.tex:186,416` | `lockwood2012` | Consumption floor and fixed cost follow Lockwood; fixed cost is 2,500. | "fixed cost of $2,000" | Partially supported | Lockwood supports SSI floor and a 2,000 fixed cost. If using 2,500, cite Pashchenko/minimum purchase or call it updated calibration. |
| `paper/main.tex:204,206,415,720`; `paper/appendix.tex:450` | `mitchell1999` | MWR 0.80-0.85 population and 0.90-0.94 annuitant; beginning-of-period payment convention. | "between 80 and 85 cents" | Partially supported | MWR claim supported. Payment timing convention needs product quote/pricing-text citation or should be labeled as modeling convention. |
| `paper/main.tex:230,438,526`; `paper/appendix.tex:133` | `aguiarhurst2013` | Nondurable consumption declines roughly 2 percent per year in retirement and model maps that to felicity weights. | "expenditure ... decline" | Needs stronger cite | Cite exact table/figure calculation or soften; source does not directly state the felicity-weight transformation. |
| `paper/main.tex:244,251,440,528`; `paper/appendix.tex:164` | `finkelsteinluttmer2013`, `reichlingsmetters2015` | Health-utility weights are central estimates/direct mapping. | "10%-25%" | Partially supported | Direction/range supported; exact vector and mapping are author-derived. |
| `paper/main.tex:260,265,423,444`; `paper/appendix.tex:171` | `blanchett2024`, `blanchett2025` | Guaranteed income spending differential is about 80 percent versus 50 percent from assets. | "lifetime income" | Needs stronger cite | Metadata uncertain; add exact RII/SSRN source and table locator. |
| `paper/main.tex:267,424,444,734`; `paper/appendix.tex:171` | `huscott2007`, `brown2008framing`, `chalmersreuter2012` | Loss aversion/framing create at-purchase annuity aversion. | "risky gamble" | Partially supported | Hu-Scott/Brown support framing; Chalmers is weak for the structural penalty magnitude. |
| `paper/main.tex:285` | `cribb2018annuity`, `cannon2016annuity`, `fca2025` | Tax/behavior adjustment of 5-15 pp for UK reform. | "current source mismatch" | Unsupported | Current Cribb/Cannon entries do not support this exact adjustment. Replace with direct UK pension-freedoms evidence or remove numeric adjustment. |
| `paper/main.tex:396,436`; `paper/appendix.tex:457` | `chetty2006` | Gamma 2.5 lies within Chetty's 1-3 CRRA range. | "mean estimate ... about 1" | Misleading | Say Chetty's central estimate is near 1 and gamma above 2 requires strong assumptions; justify 2.5 from lifecycle literature instead. |
| `paper/main.tex:398,399,450`; `paper/appendix.tex:251` | `lockwood2012`, `denardi2004` | Theta/kappa are Lockwood's HRS estimates at gamma=2 and are used without recalibration. | "De Nardi et al." | Misleading | Cite De Nardi/DFJ for estimates; state portability check as internal simulation, not source-backed. |
| `paper/main.tex:408`; `paper/appendix.tex:126` | `odeasturrock2023`, `heimer2019`, `payne2013` | Subjective survival scalar is sourced from Heimer/Payne and broadly O'Dea-Sturrock consistent. | "constructed belief" | Needs stronger cite | Add missing bib entries, quote exact survival-belief moments, and show derivation of psi. |
| `paper/main.tex:419,438,526` | `aguiarhurst2013` | Delta_c equals central estimate from Aguiar-Hurst. | "home production" | Needs stronger cite | Add exact source table or label as calibrated to match documented decline. |
| `paper/main.tex:421,734` | `ameriks2020` | chi_LTC is based on public-care aversion evidence. | "long-term-care risk" | Partially supported | Qualitative only unless a parameter transformation is added. |
| `paper/main.tex:426,633`; `paper/appendix.tex:291` | `abi2020`, `fca2025` | UK retention factor rho comes from ABI/FCA. | "first time" | Partially supported | Add exact ABI/FCA URLs and denominator construction; generic ABI URL is insufficient. |
| `paper/main.tex:444` | `huscott2007`, `brown2008framing`, `chalmersreuter2012` | psi_purchase 0.01/0.05/0.09 are literature-defensible magnitudes. | "loss aversion" | Partially supported | Keep exploratory label; provide derivation from prospect-theory parameters or avoid implying direct calibration. |
| `paper/main.tex:468` | R-S/HRS implied | Hazard multipliers fall between R-S and HRS estimates. | "health shocks" | Needs stronger cite | If own HRS estimates, cite code/appendix; do not imply R-S reports scalar 3.5 multiplier. |
| `paper/main.tex:472,478` | `lockwood2012` | Wealth-restricted single-retiree HRS ownership comparators are comparable to Lockwood. | "single retirees" | Partially supported | Lockwood 3.6 percent supported. Current variable/sample construction is internal and needs reproducible appendix table. |
| `paper/main.tex:485` | `lockwood2012` | Keeping Lockwood/DFJ bequest estimates fixed is appropriate for decomposition. | "bequest motives" | Partially supported | Source supports estimates; fixed-across-gamma choice is author choice and should be presented as such. |
| `paper/main.tex:503` | `pashchenko2013`, `peijnenburg2016`, `denardi2010` | Safety-net/consumption-floor convention is standard in calibrated lifecycle models. | "consumption minimum floor" | Supported | Add exact equation/table references if possible. |
| `paper/main.tex:528` | `finkelsteinluttmer2013`, `reichlingsmetters2015` | State-dependent utility effect is small and not load-bearing. | "marginal utility" | Partially supported | Size is internal model result; cite literature only for mechanism. |
| `paper/main.tex:613` | `bernheimrangel2009`, `beshears2008` | Behavioral channels have preference-vs-bias welfare ambiguity. | "normative preferences" | Supported | Keep. |
| `paper/main.tex:623` | `james2006` | Group annuity pricing at MWR 0.90 is achievable via employer/government pools. | "exceed 90%" | Partially supported | James supports high MWRs in mandatory/quasi-compulsory markets; U.S. employer/government achievability needs extra support or softer wording. |
| `paper/main.tex:625` | No citation | TIPS-backed real annuity MWR equals 0.78. | No cited source | Needs citation | Add direct real-annuity MWR source, likely Brown/Mitchell/Poterba or quote data, or label as model assumption. |
| `paper/main.tex:627` | No citation | Social Security trust fund depletion implies about 23 percent cut around 2033. | "77 percent payable" | Supported but uncited | Add SSA Trustees Report citation. |
| `paper/main.tex:633,734` | `madrian2001`, `goda2014` | Defaults dominate retirement saving generally. | "automatic enrollment" | Partially supported | Madrian supports default effects; Goda supports projection/framing, not defaults. Replace Goda for default claim. |
| `paper/main.tex:724` | `kotlikoffspivak1981` | Marriage provides partial longevity insurance through intra-household risk sharing. | "families can provide insurance" | Supported | Keep. |
| `paper/main.tex:726` | `pashchenko2013` | Housing illiquidity reduces annuity demand. | "housing wealth is ... illiquid" | Supported | Keep. |
| `paper/main.tex:728`; `paper/appendix.tex:126` | `odeasturrock2023` | Subjective survival distortions may be more complex than proportional scaling. | "not estimated from observed data" | Supported | Keep; add scalar derivation separately. |
| `paper/main.tex:734` | `blanchett2024`, `blanchett2025`, `huscott2007`, `brown2008framing`, `chalmersreuter2012`, `ameriks2020`, `madrian2001`, `goda2014` | Summary of behavioral evidence base. | "automatic enrollment" | Partially supported | Split into mechanisms; remove Goda from defaults and Chalmers from penalty magnitude unless rephrased. |
| `paper/main.tex:736`; `paper/appendix.tex:304` | `wettstein2021` | Wettstein estimates MWR 0.50 for DIA-80 and 0.45 for DIA-85. | "deferred annuities" | Needs stronger cite | Wettstein supports lower deferred MWRs qualitatively; exact DIA-80/DIA-85 values need table/source or should be removed. |
| `paper/appendix.tex:63` | `denardi2010` | Hurd-Michaud-Rohwedder 2017 supports poor-health acceleration around 75-85. | No bib entry/source retrieved | Needs citation | Add exact HMR citation or remove parenthetical; Denardi is not a substitute for this named claim. |
| `paper/appendix.tex:90` | `jones2018` | Log SD 1.4/CV 2.5 matches HRS/MEPS moments. | "right skewed" | Needs stronger cite | Add exact Jones table or internal calibration appendix. |
| `paper/appendix.tex:95` | `lockwood2012` | Cumulative death probabilities taken from Lockwood replication code BAP_sim2.m. | "life table" | Partially supported | Cite replication code explicitly or move to internal data provenance. |
| `paper/appendix.tex:101-106` | Life table/HRS implied | Health hazard multipliers calibrated to match HRS/Lockwood survival. | No cited source | Needs citation | Add derivation table and reconcile with macros/config values. |
| `paper/appendix.tex:171` | `barberishuang2009`, `brown2008framing` | Behavioral parameters anchored on literature magnitudes. | "framing effects" | Partially supported | Fix Barberis-Huang DOI; keep exploratory language and add derivation. |
| `paper/appendix.tex:260-266` | `lockwood2012` | Using Lockwood parameters at all gamma is conservative/acceptable. | "sigma=2" | Partially supported | The source supports original sigma only; portability is internal and should not be source-backed. |
| `paper/appendix.tex:289` | `lockwood2012` | Automated tests reproduce eight Lockwood moments including payout, WTP, monotonicity. | "25.3 percent" | Partially supported | Article supports headline moments; test-suite pass is internal. Add test output appendix or avoid implying external verification. |
| `paper/appendix.tex:293` | `reichlingsmetters2015` | Present model reproduces R-S qualitative sign-flip under their parameter choices. | "valuation risky" | Partially supported | Mechanism supported; reproduction claim needs internal test artifact/table. |
| `paper/appendix.tex:302-308` | `wettstein2021` | DIA/QLAC products have lower MWRs and do not materially raise ownership. | "substantially lower" | Partially supported | Qualitative product concern supported; exact product MWRs and ownership effect are model results needing internal evidence. |
| `paper/appendix.tex:427-434` | Product design implied | Period-certain/death-benefit annuities provide bequest protection but small effect. | No cited source | Needs citation | Cite product-pricing source and show implementation; if not modeled, delete. |
| `paper/appendix.tex:446` | `reichlingsmetters2015` | Poor-health hazard multiplier upper bound 3.5 corresponds to R-S functional limitation states. | "functional limitation" | Needs stronger cite | R-S supports state-dependent mortality, not necessarily scalar 3.5. Add derivation or soften. |
| `paper/appendix.tex:450` | `mitchell1999`, `wettstein2021` | MWR uncertainty U(0.75,0.89) reflects current pricing uncertainty. | "0.76 and 0.87" | Partially supported | 0.75-0.87 supported better than 0.89. Add current quote source for 0.89. |
| `paper/appendix.tex:457` | `chetty2006` | Median implied gamma 2.77 is inside upper half of Chetty range 1-3. | "gamma > 2 requires" | Misleading | Do not summarize Chetty as cleanly supporting 1-3; state that many draws exceed Chetty-plausible central estimates. |
| `paper/appendix.tex:486` | Internal solver claim | Stored policy values are certainty-equivalent or comparable. | No cited source | Needs verification | Verify in code; if policy is expected value not CE, fix wording. |
| `paper/appendix.tex:494` | Internal sample claim | Population evaluated with observed wealth/permanent income/age/health. | No cited source | Needs verification | Check code/data pipeline; prior code review suggested possible mismatch. |

## Priority Fix List

1. Add missing bibliography entries `heimer2019` and `payne2013`; correct wrong DOIs for `barberishuang2009` and `hosseini2015`.
2. Correct Jones et al. medical expenditure labels everywhere: the age-100 mean and 95th percentile are combined OOP plus Medicaid, not pure OOP.
3. Recalibrate or re-label survival pessimism `psi=0.960`; current citation support does not justify that scalar.
4. Remove `goda2014` from TSP/default claims and replace with an actual default/TSP annuity source.
5. Replace weak UK transport sources and notes with exact ABI/FCA/Parliament/ELSA source tables and a harmonized denominator appendix.
6. Rephrase behavioral parameter claims as exploratory author mappings unless a derivation from the cited literature is added.
7. Add direct source or internal derivation for current MWR 0.87, DIA-80/DIA-85 MWRs, TIPS real-annuity MWR, hazard multipliers, and HRS ownership variable definitions.
