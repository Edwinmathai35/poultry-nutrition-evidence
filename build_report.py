"""Build a self-contained reader report from executed R outputs; no model fitting."""
from pathlib import Path
import base64,html,json,hashlib
import pandas as pd
P=Path(__file__).resolve().parent;T=P/'outputs/tables';G=P/'governance'
def read(n):return pd.read_csv(T/(n+'.csv'))
a=read('forecast_accuracy');e=read('causal_treatment_effects');ct=read('control_test_results');run=e.run_id.iloc[0]
primary=e[(e.specification=='baseline_adjusted')&(e.SE_type=='HC3')]
gain=primary[(primary.endpoint=='ADGD11D35')&(primary.treatment=='LowCP-NoSBM')].iloc[0]
sel=read('selected_models');summary=read('treatment_summary');diag=read('forecast_diagnostics')
risks=[
('R01','Wrong units or economic interpretation','High','Ratio mislabeled as feed cost, FCR or margin','Definitions and source register; explicit axis labels','Implemented/documented','DQ01 and source checks','No automated semantic proof; interpretation review remains necessary','Analyst'),
('R02','Missing, duplicate or altered source records','High','Biased estimates from incorrect rows','Calendar, pen, identity and pinned SHA256 validation','Implemented/tested','DQ01-DQ07; INT01','Hash protects against change after pinning, not malicious simultaneous code/manifest changes','Data steward'),
('R03','Forecast look-ahead leakage','High','Future observations enter training','Origin-date validator and development-only selection','Implemented/tested','ML01; independent selection verification','Single-vintage backtest cannot reproduce historical release revisions','Model owner'),
('R04','Complexity mistaken for forecast skill','High','Model promoted despite worse holdout MAE','Naive comparator, locked selection and full score table','Implemented/evaluated','forecast_accuracy.csv','Holdout is only 24 months; future regimes may differ','Model owner'),
('R05','Underestimated uncertainty','High','Narrow intervals or invalid residual assumptions','Coverage, interval score, residual diagnostics, HC3 and sensitivity','Implemented/evaluated','forecast_diagnostics.csv; causal_treatment_effects.csv','Small trial and short holdout; ETS residual dependence remains a limitation','Statistician'),
('R06','Unsupported causal attribution','High','Whole-ration effect labeled isolated CP/AA effect','Estimand, DAG, mediator exclusion and claims register','Implemented/documented','trial_DAG; README','Absent public block IDs prevent exact design-based replication','Scientific lead'),
('R07','Transfer to African production without validation','High','US/Canadian estimates presented as local gains','Population labels and transfer restriction','Implemented/documented','Source register and report','Local prices, disease, genetics, climate and diets not measured here','Scientific lead'),
('R08','Stale or altered results/figures','High','Carousel uses old charts with new numerical claims','Run ID and SHA256 for exported outputs','Implemented/tested','REP01-REP03; output_manifest.csv','No digital signature or independent trusted checksum store','Publication reviewer'),
('R09','Privacy and access control at future deployment','High','Farm identifiers become linked to identifiable owners/workers','Public aggregate/animal-pen data only in this project; future minimization and role-based access','Scope screened; deployment controls proposed','Schema review; no live personal-data system','Access-control effectiveness and reidentification risk not tested in production','Future system owner'),
('R10','Software or source supply-chain compromise','High','Tampered dependency or downloaded source','Recorded package versions, source URLs, hashes and original-file reconciliation','Partly implemented','sessionInfo; source_manifest; repository_integrity','No dependency vulnerability scan, signed build, or penetration test','Engineering lead'),
('R11','Autonomous feeding or procurement misuse','High','Forecast treated as an automatic biological/economic decision','Research-only intended use; human sign-off and rollback proposed','Documented; deployment controls proposed','model_cards.md','No production actuation, operational outcome study or verified rollback','Operations lead'),
('R12','License or compliance overclaim','Medium','Redistribution or framework mapping mistaken for certification','Etalab metadata retained; source attribution; compliance scope record','Documented; original integrity tested','inrae.json; governance.md','Deployment jurisdiction and legal obligations not assessed','Project owner')]
cols=['risk_id','risk','severity','failure_scenario','control','status','evidence','residual_limitation','proposed_owner_role']
risk=pd.DataFrame(risks,columns=cols);risk['run_id']=run;risk.to_csv(G/'risk_register.csv',index=False)
claims=[
('C01','200 complete months from January 2010 to August 2026','data_validation.csv; monthly_ratio.csv','Descriptive','This is the selected period, not completeness of the whole workbook'),
('C02','Selected models did not beat the naive baseline on holdout MAE at either horizon','forecast_accuracy.csv; selected_models.csv','Predictive','Do not claim statistical superiority of the baseline or all-horizon failure'),
('C03','No significant FCR treatment-versus-CT contrasts after Holm correction','causal_treatment_effects.csv','Causal under stated design assumptions','Not proof of equivalence or absence of biologically important effects'),
('C04',f'LowCP-NoSBM ADG difference {gain.estimate:.3f} g/bird/day, 95% CI [{gain.lower95:.3f}, {gain.upper95:.3f}], Holm p={gain.p_Holm:.6f}','causal_treatment_effects.csv','Whole-diet causal contrast','Not an isolated protein or soybean mechanism; missing blocks disclosed'),
('C05','LowCP-NoSBM ADG finding survives all 63 leave-one-pen-out checks','leave_one_pen_out_summary.csv','Sensitivity','Does not resolve unmeasured design limitations or external validity'),
('C06','13 of 13 internal control tests passed','control_test_results.csv','Audit evidence','Covers specified scenarios only; not an independent audit or compliance certificate')]
c=pd.DataFrame(claims,columns=['claim_id','claim','evidence_table','claim_type','boundary']);c['run_id']=run;c.to_csv(G/'claims_register.csv',index=False)
(G/'governance.md').write_text(f'''# Governance and internal audit record

Run: `{run}`. Scope: public-data offline research and communication. There is no deployed AI service or automated feeding/procurement action.

## Operating controls and tested evidence

The R pipeline verifies pinned source SHA256 values, original repository MD5 checksums, the original Excel/TAB performance-table agreement, complete monthly calendars, valid treatment labels, unique pens, finite outcomes and FCR arithmetic. It tests training-date leakage, stale run IDs and changed chart checksums. `outputs/tables/control_test_results.csv` contains actual accepted/rejected outcomes for 13 tests, including valid-data tests and deliberately injected faults. `independent_verification.csv` contains independent Python arithmetic and provenance checks. A failed validator stops execution; no automatic repair or imputation is used.

Repository checksum reconciliation matters: the deposited MD5 values refer to original XLSX uploads. Downloaded TAB renditions have different bytes. All six original files, including the README PDF, match the advertised MD5 values. The performance original and TAB values agree to numerical tolerance. SHA256 values pin both original and rendition bytes. Ancillary missingness is disclosed rather than silently repaired.

## Governance framework mapping

This project uses the four functions of NIST AI RMF 1.0 as a voluntary organizing reference: https://doi.org/10.6028/NIST.AI.100-1 . This is an illustrative mapping, not certification, full conformity assessment or legal advice.

| Function | Implemented evidence | Remaining operating requirement |
|---|---|---|
| Govern | Intended-use boundaries, methodological decisions, source register, claims register, proposed owner roles | Organization must appoint owners, authorize use and establish change approval |
| Map | Separate market/trial populations, estimands, DAG, risk register and threat scenarios | Local farm context, users, procurement decisions and downstream harms must be assessed |
| Measure | Holdout metrics, residual checks, HC3 estimates, multiplicity correction, sensitivity and injected-fault tests | Longer prospective evaluation, local validation and production security assessment |
| Manage | Stop on integrity failures; preserve unfavorable results; explicitly limit extrapolation | Monitoring, human override, rollback and incident response need real deployment tests |

## Threats and safeguard effectiveness

Data poisoning or accidental edits: pinned hashes and original-checksum reconciliation detect changed bytes relative to these snapshots. They do not detect an attacker changing both data and the trusted manifest. Model leakage: the origin validator rejects a future training date; development-only model selection is independently checked. Stale outputs: identifier and byte checks reject a stale run or altered chart. Overclaiming: a claims register connects every intended headline to its table and scientific boundary. Dependency compromise: versions are recorded but a vulnerability scan or signed dependency chain is not implemented. Unauthorized access: there is no live application to test; role-based access and secret management remain proposed deployment controls. Prompt injection is not a runtime attack surface for this R-only analysis; adding an LLM assistant would require a separate threat assessment.

## Privacy, licensing and compliance scope

The analyzed schemas contain national monthly price ratios and animal-pen research measurements, not names/contact details of human participants. This schema review does not establish anonymity for a future linked farm database. Retain only identifiers needed for scientific linkage; review future farm-owner/worker information separately. The deposited trial metadata identify the Etalab 2.0 open license; metadata and attribution are bundled. USDA is cited as the public source. No GDPR, Canadian privacy-law, EU AI Act, ISO or other legal compliance conclusion is asserted: deployment location, purpose and controller relationships are unspecified. Required future work is an applicability assessment for the actual deployment, not a blanket compliance badge.

## Audit method and evidence limits

Scope and criteria are defined in the README. Tests inspect the entire selected monthly and performance datasets, not a sample; ancillary endpoints are screened for missingness and excluded from outcome estimation. Fault tests evaluate specific validators, not adversarial coverage of every failure mode. Independent Python numerical verification provides a second implementation, but remains internal to this project and is not an organizationally independent audit. Source and output manifests support traceability. Package versions and the console log support execution review. Proposed owner roles are responsibilities to assign, not evidence that staff have accepted them.

## Release and monitoring decision

Suitable for transparent portfolio communication after review of the stated limitations. Not approved for autonomous procurement or ration formulation. Selected models lose to the carry-forward baseline on held-out MAE, so no complex-model performance superiority claim is permitted. After correcting fitted-parameter degrees of freedom, any residual dependence flagged in the diagnostic table must remain visible. For a future operational pilot, define acceptable error and calibration thresholds with the business owner before testing; monitor monthly forecast error, interval misses, missingness and structural changes. Pause recommendations on integrity failure, unknown schema/treatment, material drift or unjustified extrapolation. Test human override and rollback in the actual application before deployment.
''')
(G/'model_cards.md').write_text(f'''# Model cards
Run `{run}`

## Broiler-feed purchasing power
- Intended use: demonstrate historical forecast evaluation and short-horizon planning uncertainty.
- Population: US national monthly price ratio; January 2010-August 2026; USDA October 2026 workbook vintage.
- Target: pounds of broiler-grower feed equal in value to one pound of live broiler.
- Models: 15 fixed candidates across naive, seasonal naive, ARMA, ARIMA, SARIMA and additive ETS families. ETS means Error, Trend, Seasonal. ANN/AAN/AAA identify additive error, trend and seasonality components; AAdN is damped additive trend without seasonality.
- Selection: development MAE separately for one and three months. Final selected specifications: {dict(zip(sel.h,sel.model))}.
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
''')
# Short publication plan; every message must stay tied to actual evidence.
(P/'Four_Day_Evidence_Map.md').write_text('''# Four-day publication sequence

| Day | Question and evidence | Core figures | Message boundary |
|---|---|---|---|
| 1 | What do poultry feed records actually measure? Explain USDA price ratio, 200 complete months, stationarity and seasonality. | 01, 02, 03 | Economic purchasing power, not farm FCR or African feed costs. |
| 2 | Does a more complex forecast improve decisions? Show fixed candidate comparison, development/holdout separation, prediction intervals and residual limitations. | 04, 05, 06 | The selected models did not beat naive on holdout MAE. Preserve that result. |
| 3 | Can lower-protein diets maintain performance? Introduce trial, randomization, DAG, pen unit, FCR and ADG effects. | 11, 07, 08 | No significant FCR contrasts is not equivalence; low-protein soybean-free whole ration reduced ADG. |
| 4 | What makes a result safe to use? Link phase analysis, sensitivity, source reconciliation and tested governance controls to local data-system requirements. | 09, 10, 12 | Internal checks are not independent certification; local and operational validation remain necessary. |

Each carousel should use one large authentic R chart per results slide and one short interpretation. Light ivory, blue and lavender; no green. No decorative slide IDs, invented numbers or AI-redrawn charts. Provide study/data DOI and repository link only when a repository actually exists. Captions should be 2,925-2,975 characters when drafted, with programmatic counts. Do not publish the forecast ratio as feed cost per bird. State the selected data dates, units, experimental unit, confidence level and material limitations.

Potential × Management × System = Performance is a conceptual campaign framework, not a fitted mathematical identity in these datasets.
''')
def table(df,columns=None):
 if columns is not None:df=df[columns]
 df=df.drop(columns=['run_id'],errors='ignore')
 return df.to_html(index=False,border=0,float_format=lambda x:f'{x:.4f}')
def fig(stem,caption):
 f=P/'outputs/figures'/f'{stem}.png'
 return '<figure><img src="data:image/png;base64,'+base64.b64encode(f.read_bytes()).decode()+'"><figcaption>'+html.escape(caption)+'</figcaption></figure>'
parts=[]
def section(title,text):parts.append('<h2>'+title+'</h2>'+text)
section('What the completed analysis found',f'''<div class="callout"><strong>The preselected forecasts did not beat the baseline.</strong> The development-selected models had slightly higher holdout MAE than the previous-month baseline. In the trial, none of the six FCR contrasts was significant after Holm correction. The LowCP-NoSBM diet reduced daily gain by {abs(gain.estimate):.2f} g/bird/day (95% CI {gain.lower95:.2f} to {gain.upper95:.2f}; Holm p={gain.p_Holm:.4f}). This is a whole-diet effect, subject to the public-data design limitations.</div><p>Executed in R, with independent Python verification. All 200 selected months and all 63 performance pens are complete. Thirteen internal control tests passed. This report presents two separate studies; it does not join US market ratios to Canadian animal outcomes or claim African effect sizes.</p>''')
section('1. Sources and validation','''<p><a href="https://www.ers.usda.gov/data-products/feed-grains-database/feed-grains-yearbook-tables">USDA ERS Yearbook Table 15</a>: workbook dated 13 October 2026, January 2010-August 2026 selected. The ratio is pounds of broiler-grower feed equal in value to one pound of live broiler. Higher means stronger feed purchasing power relative to bird value.</p><p>Randomized trial: <a href="https://doi.org/10.1016/j.animal.2026.101771">article DOI</a>; <a href="https://doi.org/10.57745/1ZCQMN">data DOI</a>. Trial conducted in Quebec, Canada in 2022, with seven whole-diet treatments and nine pens per treatment. CT is control; MedCP/LowCP denote crude-protein reductions of approximately 15/30 g/kg from control; High/Med/NoSBM denote soybean-meal sourcing strategies. Experimental diets were fed over days 11-35.</p>'''+table(read('data_validation'))+'<p>The repository original-file MD5 values match. The original Excel performance values match the TAB rendition to numerical tolerance. Ancillary missingness is disclosed below; these incomplete endpoints are excluded from the performance analysis.</p>'+table(read('ancillary_completeness')))
section('2. Time structure and model development','''<p>Initial training: January 2010-December 2017. Development targets end August 2024. Holdout targets: September 2024-August 2026. Models are refitted on expanding histories for 1- and 3-month forecasts. Selection uses development MAE only. Fifteen fixed model specifications cover ARMA, ARIMA, SARIMA, ETS and simple baselines. ETS means Error, Trend, Seasonal.</p><p>ADF and KPSS diagnostics on development data support first differencing. Neither test establishes an immutable data-generating process. The decomposition is descriptive and is not computed over future observations for forecasting features.</p>'''+table(read('stationarity_tests'))+fig('01_feed_purchasing_power','Historical economic purchasing power, not biological conversion efficiency.')+fig('02_seasonal_decomposition','Descriptive development-period decomposition. Its fixed seasonal component is an assumption, not proof of constant future seasonality.')+fig('03_acf_pacf','Persistence and seasonal dependence motivate the candidate model families. For a monthly ts object, an ACF/PACF axis value of 1 represents 12 months.'))
keep=a[(a.split=='holdout')&(a.selected|a.model.isin(['Naive','SeasonalNaive']))]
section('3. Held-out forecast performance','''<p>Each reported horizon has 24 holdout targets. Errors are in ratio units. Selected ETS(AAA) has 1-month MAE 0.2401 versus naive 0.2333. Selected SARIMA(0,1,1)(0,1,1)[12] has 3-month MAE 0.4451 versus naive 0.4167. These comparisons do not establish statistically significant superiority; they show that this model-selection exercise did not improve the primary holdout metric.</p>'''+table(keep,['h','model','n','MAE','RMSE','bias','coverage95','width95','selected'])+fig('04_holdout_forecast_accuracy','Both horizons are shown for the baseline and selected model families. ETS was selected for one month; SARIMA for three months. Other-horizon bars are contextual comparisons.')+fig('05_holdout_predictions','Observed values and one-month ETS forecasts with nominal 95% prediction intervals. All 24 held-out observations were covered; a small sample and wide intervals do not prove calibration.')+fig('06_selected_residual_diagnostics','Residual structure and tail departures remain relevant even when point forecasts look close.')+'<p>Residual Ljung-Box tests below adjust for ARIMA orders or the number of fitted ETS parameters. They are diagnostics, not proof of model correctness. The selected ETS model retains evidence of residual dependence; this limits reliance on its nominal uncertainty.</p>'+table(diag[diag.model.isin(sel.model)],['model','lag','fitdf','Ljung_Box','p'])+'<p>Seven fitting failures occurred in other candidate models and were logged. Models with incomplete development forecasts were ineligible for selection. The single-vintage backtest does not reconstruct historical release delays or revisions, and 3-month errors overlap.</p>')
section('4. Causal estimand and trial findings','''<p>Experimental unit: pen. Primary outcome: FCR during days 11-35; secondary: daily gain during the same period. Effects are treatment minus CT, adjusted for centered pretreatment body weight. HC3 standard errors and residual-degrees-of-freedom t confidence intervals are used. Six comparisons within each endpoint receive Holm correction; intervals are pointwise 95%, not simultaneous.</p><p>Randomization supports causal interpretation of the assigned ration under consistency and no relevant between-pen interference. Block IDs are absent from the public data, so this analysis does not replicate the published blocked model. Other formulation components change with protein and soybean-meal strategies; isolated protein or amino-acid effects cannot be identified.</p>'''+fig('11_trial_DAG','The DAG makes the proposed adjustment logic explicit. Feed intake is downstream of diet assignment; conditioning on it would change the estimand.')+table(summary,['treatment','pens','FCR_mean','FCR_SD','ADG_mean','ADG_SD'])+fig('07_causal_FCR','All primary FCR confidence intervals cross zero. Holm-adjusted p values are 1.00. This is not evidence of equivalence.')+fig('08_causal_ADG','The LowCP-NoSBM whole-diet strategy reduced ADG relative to control. No other secondary contrast remains significant after Holm correction.')+table(primary[['endpoint','treatment','estimate','lower95','upper95','p_Holm']]))
section('5. Longitudinal and sensitivity evidence','''<p>Two deposited phases per pen produce 126 linked observations. Mixed models use pen random intercepts and phase-specific residual variances. Treatment-by-phase interaction is supported for ADG (exploratory p=0.0037), but not FCR (p=0.1547). These are phase-level measurements, not daily time-series data.</p><p>The supporting 54-pen CP-by-SBM FCR interaction has HC3 Wald p=0.2248. In all 63 leave-one-pen-out analyses, the LowCP-NoSBM ADG estimate remains negative and its Holm p stays below 0.023. This sensitivity does not recover missing blocks or establish generalizability.</p>'''+fig('09_phase_performance','Descriptive phase means. Higher finisher FCR can reflect age and growth composition; the phase contrast alone is not a randomized effect of age.')+fig('10_sensitivity_FCR','Adjusted and unadjusted HC3 FCR contrasts lead to the same non-equivalence-limited interpretation.')+table(read('phase_interaction_tests'))+table(read('factorial_interaction')))
section('6. Governance, risk and internal audit','''<p>The project organizes governance evidence around NIST AI RMF 1.0: Govern, Map, Measure and Manage. The risk register distinguishes controls implemented and tested from future deployment proposals. There is no live AI service or automated feeding/procurement system.</p><p>Data-integrity, calendar, pen identity, label, leakage and stale-output controls were challenged with invalid inputs. All 13 positive/negative tests passed. Independent Python calculations reproduce R treatment estimates, SEs, confidence intervals and raw p values to within numerical precision, and verify forecast arithmetic, selection, run IDs and hashes.</p>'''+fig('12_control_tests','Passing these specified tests is internal audit evidence, not independent certification, legal compliance or complete cybersecurity assurance.')+table(ct,['control_id','test','expected','observed','passed'])+'<p>Remaining limitations include missing trial blocks, regional transfer, possible data revisions, model residual dependence, unscreened software vulnerabilities, and untested production access control/rollback. Full details and evidence references are in the risk register and governance document.</p>')
section('7. Practical deductions and publication sequence','''<p>Retain a simple forecast baseline in every procurement planning review. Evaluate feed purchasing power separately from biological feed efficiency. Do not promise that protein reduction preserves performance merely because FCR differences were not significant. In African systems, link dated ingredient prices and lab assays to formulations, batches, pen feed records, weights, health and carcass outcomes before claiming local forecast or treatment benefits.</p><p>Four-day sequence: (1) what feed records measure; (2) whether forecasting complexity helps; (3) what the randomized ration comparison shows; (4) sensitivity and governance evidence. Use the actual R figures, one main result per slide, with light backgrounds and no green. The campaign expression Potential × Management × System = Performance remains conceptual, not a fitted model.</p><p>R code, raw snapshots, cleaned data, tables, PNG/PDF charts, fitted objects, console logs, Python verification, risk and claims registers are bundled. Re-run instructions and methodological boundaries are in README.md.</p>''')
css='''body{margin:0;background:#fcfbf7;color:#18334f;font:17px/1.65 system-ui,sans-serif}main{max-width:1100px;margin:auto;padding:48px 32px}header{background:#18334f;color:white;padding:45px;border-radius:14px}h1{font-size:38px;line-height:1.2}h2{font-size:27px;margin-top:55px;border-bottom:2px solid #dce5ef;padding-bottom:10px}.callout{padding:24px;background:#e9edf7;border-left:5px solid #a29acd;margin:20px 0}table{border-collapse:collapse;width:100%;font-size:13px;margin:24px 0}th{text-align:left;background:#e9edf7}td,th{padding:9px;border-bottom:1px solid #dce1e8}figure{margin:35px 0;break-inside:avoid}img{width:100%;display:block}figcaption{padding:12px 18px;background:#eff1f6;font-size:15px}a{color:#315e95}small{color:#dce5ef}@media print{main{padding:0}header{border-radius:0}h2{break-after:avoid}table{font-size:10px}body{font-size:12px}figure{page-break-inside:avoid}}'''
report='<html><head><meta charset="utf-8"><title>Poultry evidence: executed R analysis</title><style>'+css+'</style></head><body><main><header><p>BUILDING THE FUTURE OF AFRICAN LIVESTOCK</p><h1>Poultry nutrition: forecasting, causal evidence and tested controls</h1><p>Executed analysis and interpretation</p><small>Analysis run '+run+' | Public-data research | 200 months · 63 pens</small></header>'+''.join(parts)+'</main></body></html>'
(P/'Poultry_Analysis_Report.html').write_text(report)
# A concise, readable text companion supports review without a browser.
(P/'Results_Summary.md').write_text(f'''# Executed poultry analysis

Run `{run}`

- Data: 200 complete monthly USDA ratios; 63 complete trial-performance pens, 9 per treatment. Incomplete ancillary endpoints were excluded explicitly.
- One-month holdout MAE: selected ETS(AAA) 0.2401 versus naive 0.2333.
- Three-month holdout MAE: selected seasonal ARIMA 0.4451 versus naive 0.4167.
- These selected models did not improve the primary holdout metric. No statistical superiority claim is made from the small test window.
- Primary FCR contrasts: none significant after six-contrast Holm adjustment. Non-significance is not equivalence.
- Secondary ADG: LowCP-NoSBM minus CT = {gain.estimate:.3f} g/bird/day, pointwise 95% CI [{gain.lower95:.3f}, {gain.upper95:.3f}], Holm p={gain.p_Holm:.6f}.
- This ADG finding remains significant in all 63 leave-one-pen-out analyses, under the same modeling assumptions.
- Missing block identifiers prevent exact replication of the published blocked analysis. The estimand is a whole-diet effect.
- 13 internal control tests passed; independent Python numerical verification passed.
- Source: https://www.ers.usda.gov/data-products/feed-grains-database/feed-grains-yearbook-tables
- Article: https://doi.org/10.1016/j.animal.2026.101771
- Data: https://doi.org/10.57745/1ZCQMN

See the full HTML report for all charts, tables, interpretations and limitations. Governance documents distinguish implemented/tested controls from proposed deployment safeguards. No African treatment effect, autonomous operating approval or independent compliance certification is claimed.
''')
print('Built report, model cards, risk register, claims register and four-day evidence map for run',run)
