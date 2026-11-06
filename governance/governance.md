# Governance and internal audit record

Run: `1395afb10eb726ef`. Scope: public-data offline research and communication. There is no deployed AI service or automated feeding/procurement action.

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
