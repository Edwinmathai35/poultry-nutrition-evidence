# Executed poultry analysis

Run `1395afb10eb726ef`

- Data: 200 complete monthly USDA ratios; 63 complete trial-performance pens, 9 per treatment. Incomplete ancillary endpoints were excluded explicitly.
- One-month holdout MAE: selected ETS(AAA) 0.2401 versus naive 0.2333.
- Three-month holdout MAE: selected seasonal ARIMA 0.4451 versus naive 0.4167.
- These selected models did not improve the primary holdout metric. No statistical superiority claim is made from the small test window.
- Primary FCR contrasts: none significant after six-contrast Holm adjustment. Non-significance is not equivalence.
- Secondary ADG: LowCP-NoSBM minus CT = -4.519 g/bird/day, pointwise 95% CI [-7.089, -1.949], Holm p=0.005197.
- This ADG finding remains significant in all 63 leave-one-pen-out analyses, under the same modeling assumptions.
- Missing block identifiers prevent exact replication of the published blocked analysis. The estimand is a whole-diet effect.
- 13 internal control tests passed; independent Python numerical verification passed.
- Source: https://www.ers.usda.gov/data-products/feed-grains-database/feed-grains-yearbook-tables
- Article: https://doi.org/10.1016/j.animal.2026.101771
- Data: https://doi.org/10.57745/1ZCQMN

See the full HTML report for all charts, tables, interpretations and limitations. Governance documents distinguish implemented/tested controls from proposed deployment safeguards. No African treatment effect, autonomous operating approval or independent compliance certification is claimed.
