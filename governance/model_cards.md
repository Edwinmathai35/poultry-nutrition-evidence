# Model cards
Run `1395afb10eb726ef`

## Broiler-feed purchasing power
- Intended use: demonstrate historical forecast evaluation and short-horizon planning uncertainty.
- Population: US national monthly price ratio; January 2010-August 2026; USDA October 2026 workbook vintage.
- Target: pounds of broiler-grower feed equal in value to one pound of live broiler.
- Models: 15 fixed candidates across naive, seasonal naive, ARMA, ARIMA, SARIMA and additive ETS families. ETS means Error, Trend, Seasonal. ANN/AAN/AAA identify additive error, trend and seasonality components; AAdN is damped additive trend without seasonality.
- Selection: development MAE separately for one and three months. Final selected specifications: {1: 'ETS_AAA', 3: 'SARIMA011011'}.
- Evaluation: 24 holdout target months per horizon. All candidate results disclosed; failed fits recorded. Two-best-development-model equal-weight forecast is a sensitivity exercise.
- Limitations: one data vintage; possible revisions; overlapping horizon errors; residual dependence; no farm-level economic outcomes, feed formulation optimization or local African validation.
- Decision: selected complexity did not improve holdout MAE over naive. Further model development requires a new evaluation period rather than reuse of this holdout for a fresh claim.

## Dietary treatment effects
- Intended use: estimate whole-ration assignment effects in the deposited randomized trial.
- Population: 63 Canadian research pens, seven treatments, male Ross308 broilers. Pen is the experimental unit.
- Primary estimand: treatment minus CT mean FCR over days 11-35. Secondary: ADG over days 11-35.
- Estimator: linear treatment contrasts adjusted for centered pretreatment weight, HC3 covariance with residual-df t intervals; six-contrast Holm correction separately per outcome. Raw/unadjusted and conventional-SE sensitivities included.
- Supporting analyses: CP by SBM interaction in 54 factorial pens; pen random-intercept, phase-heteroscedastic mixed models; leave-one-pen-out influence checks.
- Identification assumptions: randomized assignment as described, consistency of rations, no relevant spillovers across pens, valid pretreatment timing. Assignment probabilities are positive (nine pens per treatment).
- Limitations: missing block IDs; no exact published-model replication; repeated measurements are two feeding phases, not daily trajectories; mortality percentages do not identify death counts or causes; non-significance is not equivalence.
- Decision: LowCP-NoSBM shows lower ADG relative to CT; the reanalysis cannot isolate which ration component caused the reduction. No demonstrated FCR advantage after correction.

## Methods applicability
- Potential outcomes, randomized-treatment contrasts, DAG, positivity, mediator handling and sensitivity: applied.
- Matching and propensity-score IPTW: not applied; randomized design already identifies assignment contrasts under stated assumptions, and estimated reweighting would add unnecessary instability.
- Instrumental variables: not applied; no defensible excluded instrument is available.
- Forecasting is predictive; the USDA time trend alone does not identify nutritional causal effects.
