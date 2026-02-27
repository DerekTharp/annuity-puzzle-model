# Final Cleanup Diff Recommendations

This note translates the remaining concerns into concrete diff-style edits.

## 1. Fix unresolved appendix cross-references in `paper/main.tex`

### Recommended approach

Import labels from the separately compiled appendix instead of leaving the main paper with unresolved references.

### Diff

File: `paper/main.tex`

Add to the preamble after `\usepackage{hyperref}`:

```tex
\usepackage{xr-hyper}
```

Add before `\begin{document}`:

```tex
% Import labels from the separately compiled appendix.
\externaldocument{appendix}
```

### Why

This should resolve references such as:

- `\ref{app:bequest}`
- `\ref{app:quadrature}`
- `\ref{app:euler}`
- `\ref{app:dia}`
- `\ref{tab:full_robustness}`
- `\ref{tab:grid_convergence}`
- `\ref{app:grid_convergence}`

### Optional build note

If you want the build to be robust for future turns, add a short note to your paper build instructions saying:

```text
Compile appendix.tex before main.tex so appendix.aux is available for cross-document references.
```

If you do not want cross-document references at all, the fallback diff is to replace explicit appendix refs in `main.tex` with plain text like “reported in the online appendix.”

## 2. Remove `CodexEdit` table names from the production manuscript

### Problem

The main paper now depends on draft-named table files:

- `tables/tex/retention_rates_CodexEdit.tex`
- `tables/tex/extension_path_CodexEdit.tex`
- `tables/tex/shapley_exact_CodexEdit.tex`

That is fine for drafting, but not ideal for the final submission package.

### Diff

File: `paper/main.tex`

Replace:

```tex
\input{../tables/tex/retention_rates_CodexEdit.tex}
```

with:

```tex
\input{../tables/tex/retention_rates.tex}
```

Replace:

```tex
\input{../tables/tex/extension_path_CodexEdit.tex}
```

with:

```tex
\input{../tables/tex/extension_path.tex}
```

Replace:

```tex
\input{../tables/tex/shapley_exact_CodexEdit.tex}
```

with:

```tex
\input{../tables/tex/shapley_exact.tex}
```

### File actions

1. Copy the current contents of `retention_rates_CodexEdit.tex` into `tables/tex/retention_rates.tex`.
2. Create `tables/tex/extension_path.tex` from `extension_path_CodexEdit.tex`.
3. Copy the current contents of `shapley_exact_CodexEdit.tex` into `tables/tex/shapley_exact.tex`.
4. Remove or archive the `*_CodexEdit.tex` table files after the canonical files are in place.

### Important content to preserve in the canonical files

In `tables/tex/retention_rates.tex`, keep:

- the caption `Sequential Decomposition of Predicted Ownership: Seven Standard Rational Channels`
- the first-row label `Frictionless population benchmark (no SS)`
- the note clarifying that the first row is not the theoretical full-annuitization Yaari result

In `tables/tex/shapley_exact.tex`, keep:

- `Frictionless population benchmark: 41.4%. Full nine-channel model: 6.6%.`

## 3. Make the age-needs appendix table impossible to misread as the headline baseline

### Problem

In `paper/appendix.tex`, the age-needs sensitivity table uses mean Social Security and therefore reports a `13.4%` “baseline” that is not directly comparable to the headline `6.6%` result in the main paper.

### Diff

File: `paper/appendix.tex`

Replace this paragraph:

```tex
Table~\ref{tab:dc_sensitivity} reports the sensitivity of the full nine-channel model to the decline rate $\delta_c$. Predicted ownership declines monotonically from 20.0\% ($\delta_c = 0$, no age-varying needs) to 10.0\% ($\delta_c = 0.03$). At the baseline $\delta_c = 0.02$, ownership is 13.4\%. The central range of $\delta_c \in [0.01, 0.03]$ produces ownership between 10\% and 17\%, all within plausible bounds given that the seven-channel model without this channel predicts 18.3\%.
```

with:

```tex
Table~\ref{tab:dc_sensitivity} reports an auxiliary mean-Social-Security sensitivity exercise for the full nine-channel model. Because this exercise replaces the quartile-specific Social Security assignment used in the main text with a common mean benefit, the ownership levels are not directly comparable to the headline 6.6\% baseline. Within that simplified environment, predicted ownership declines monotonically from 20.0\% ($\delta_c = 0$, no age-varying needs) to 10.0\% ($\delta_c = 0.03$). At the baseline $\delta_c = 0.02$, ownership is 13.4\%.
```

Replace the caption:

```tex
\caption{Sensitivity of Nine-Channel Model to Age-Varying Needs Decline Rate}
```

with:

```tex
\caption{Sensitivity of Nine-Channel Model to Age-Varying Needs Decline Rate (Mean-SS Auxiliary Runs)}
```

Replace the table note:

```tex
\item Full nine-channel model with state-dependent utility ($\varphi = [1.0, 0.95, 0.85]$), mean Social Security, production grid ($80 \times 30$), 9-node Gauss--Hermite quadrature.
```

with:

```tex
\item Auxiliary sensitivity exercise using mean Social Security rather than the quartile-specific Social Security assignment used in the headline decomposition. Ownership levels are therefore not directly comparable to the 6.6\% full-model baseline in the main text. Full nine-channel model with state-dependent utility ($\varphi = [1.0, 0.95, 0.85]$), production grid ($80 \times 30$), 9-node Gauss--Hermite quadrature.
```

## 4. Make the grid-convergence appendix section clearly diagnostic, not headline

### Problem

The convergence table in `paper/appendix.tex` reports ownership levels like `21.4%` under mean Social Security. The text does explain this later, but the caveat should appear immediately.

### Diff

File: `paper/appendix.tex`

Replace this opening sentence:

```tex
Table~\ref{tab:grid_convergence} reports predicted ownership and mean annuitization share ($\bar{\alpha}$) under the full model at different grid resolutions and quadrature node counts.
```

with:

```tex
Table~\ref{tab:grid_convergence} reports numerical diagnostics from a simplified mean-Social-Security version of the full model at different grid resolutions and quadrature node counts. The ownership levels in this table are not the headline baseline results and should be interpreted only as numerical diagnostics.
```

Replace the caption:

```tex
\caption{Grid and Quadrature Convergence}
```

with:

```tex
\caption{Grid and Quadrature Convergence (Mean-SS Diagnostic Runs)}
```

Replace the table note:

```tex
\item All specifications use baseline parameters ($\gamma = 2.5$, DFJ bequests, MWR $= 0.82$, $\pi = 2\%$, $\psi = 0.981$) with mean Social Security. $n_\alpha = 101$ throughout.
```

with:

```tex
\item Numerical diagnostic runs using mean Social Security rather than the quartile-specific Social Security assignment used in the headline decomposition. Ownership levels are therefore not directly comparable to the main-text baseline. All specifications use baseline parameters ($\gamma = 2.5$, DFJ bequests, MWR $= 0.82$, $\pi = 2\%$, $\psi = 0.981$). $n_\alpha = 101$ throughout.
```

### Optional tightening

The explanatory paragraph starting `Ownership rates in this table differ from the headline result of 18.3\%...` can stay, but after the edits above it can be shortened substantially because the caveat will already be visible.

## 5. Soften one remaining over-strong literature sentence

### Problem

This sentence in `paper/main.tex` still reads too strongly:

```tex
This is the channel that \citet{pashchenko2013} and \citet{peijnenburg2016} omitted.
```

### Diff

File: `paper/main.tex`

Replace:

```tex
This is the channel that \citet{pashchenko2013} and \citet{peijnenburg2016} omitted.
```

with:

```tex
This mechanism was not jointly incorporated in the multi-channel quantitative frameworks of \citet{pashchenko2013} and \citet{peijnenburg2016}.
```

That keeps the point while sounding much safer to a referee.

## 6. Optional: reduce future confusion by standardizing terminology once more

### Recommended micro-edits

File: `paper/main.tex`

- Keep using `frictionless population benchmark` instead of `Yaari benchmark` for the 41.4\% empirical participation result.
- Keep using `preferred attribution result` when introducing the exact Shapley table.
- Keep describing state-dependent utility as a `completeness check` or `minor channel`, not a coequal driver.

These are already mostly in place; this is just a reminder to preserve them if later edits reopen old phrasing.
