# STROBE checklist mapping

This working document maps the manuscript package to the STROBE cohort-study checklist. Final page and line numbers should be inserted after journal formatting.

Official checklist: [STROBE checklist for cohort studies](https://strobe-statement.org/fileadmin/Strobe/uploads/checklists/STROBE_checklist_v4_cohort.pdf)

| Item | STROBE recommendation | Planned manuscript location | Current evidence or action |
|---:|---|---|---|
| 1a | Indicate the study design in the title or abstract | Title; Abstract | Add "NHANES observational study" or equivalent design wording in the final title or abstract. |
| 1b | Provide an informative and balanced abstract summary | Abstract | Draft after final table curation. Include discovery association, NHANES III non-replication, mortality findings, and exploratory MR boundary. |
| 2 | Explain scientific background and rationale | Introduction | Describe the kidney-thyroid homeostasis question and the need for replication and longitudinal mortality assessment. |
| 3 | State specific objectives and prespecified hypotheses | Introduction | Primary objective: evaluate UACR-TT4 association. Secondary: NHANES III replication assessment and mortality extension. Supplementary: exploratory MR. |
| 4 | Present key elements of study design early | Methods: Study design and data sources | Drafted. |
| 5 | Describe setting, locations, and relevant dates | Methods: Study design and data sources | Add NHANES cycle dates, NHANES III survey years, and linked mortality-file release details in the formatted manuscript. |
| 6a | Give eligibility criteria and participant selection methods | Methods: Discovery cohort construction; Replication cohort construction; Mortality extension | Drafted. Source tables: `discovery_exclusion_flow.csv`, `validation_exclusion_flow.csv`, and `mortality_linkage_flow.csv`. |
| 6b | For matched studies, give matching criteria | Not applicable | No matched cohort design. |
| 7 | Clearly define outcomes, exposures, predictors, confounders, and effect modifiers | Methods: Exposure definition; Thyroid outcomes; Covariates; Mortality extension | Drafted. |
| 8 | Give data sources and measurement methods | Methods: Exposure definition; Thyroid outcomes; Mortality extension | Add official NHANES laboratory-method citations during reference insertion. |
| 9 | Describe efforts to address potential sources of bias | Methods; Limitations | Complete-case selection, harmonized models, sensitivity analyses, and cautious interpretation are documented. |
| 10 | Explain how study size was arrived at | Methods; Results: Discovery cohort | Use participant-flow tables and final analytic counts. |
| 11 | Explain handling of quantitative variables | Methods: Exposure definition; Survey-weighted thyroid analyses; Mortality extension | Drafted: natural-log UACR, quartiles, clinical categories, RCS, and per-SD TT4. |
| 12a | Describe all statistical methods, including confounding control | Methods: Survey-weighted thyroid analyses; Harmonized replication assessment; Mortality extension | Drafted. |
| 12b | Describe subgroup and interaction methods | Methods: Mortality extension | Drafted: euthyroid restriction, joint groups, and multiplicative interaction tests. |
| 12c | Explain how missing data were addressed | Methods: cohort-construction subsections | Complete-case approach documented. Add a short explicit missing-data sentence to the final manuscript. |
| 12d | Explain loss-to-follow-up handling | Methods: Mortality extension | Public-use linked mortality eligibility and follow-up-month criteria documented. |
| 12e | Describe sensitivity analyses | Methods: Survey-weighted thyroid analyses; Mortality extension | Drafted. |
| 13a | Report numbers at each study stage | Results; Supplementary flow tables | Available in discovery, NHANES III, and mortality linkage flow tables. |
| 13b | Give reasons for non-participation at each stage | Supplementary flow tables | Available. |
| 13c | Consider a flow diagram | Figure 1 placeholder | Generate a manuscript flow diagram from existing flow tables before submission. |
| 14a | Give participant characteristics and exposures | Table 1 placeholder | Required: generate survey-weighted baseline characteristics table. |
| 14b | Indicate missing data for variables of interest | Supplementary Materials | Available in `discovery_variable_missingness.csv`; summarize in Supplementary Materials. |
| 14c | Summarize follow-up time | Results; Table S5 | Add median or distribution of follow-up time only if already generated or after an explicitly approved descriptive summary. |
| 15 | Report outcome events or summary measures over time | Results: Mortality extension | Drafted: 897 all-cause and 249 cardiovascular deaths. |
| 16a | Give unadjusted and adjusted estimates with precision | Main Tables 2-4 | Available in source tables; curate final journal tables. |
| 16b | Report category boundaries | Methods; table captions | Drafted: UACR <30, 30-300, and >=300 mg/g; TT4 high defined as weighted Q4 in joint mortality analysis. |
| 16c | Consider translating relative risk into absolute risk | Discussion or Supplementary Materials | Consider only if requested by the target journal; not currently generated. |
| 17 | Report other analyses | Supplementary Materials | TT4 robustness, joint mortality categories, interaction tests, PH diagnostics, and exploratory MR are available. |
| 18 | Summarize key results with reference to objectives | Discussion opening | Included in `discussion_outline.md`. |
| 19 | Discuss limitations and direction or magnitude of potential bias | Limitations | Drafted in `limitations.md`. |
| 20 | Give a cautious overall interpretation | Discussion | Use bounded observational language; state NHANES III non-replication and exploratory MR boundary. |
| 21 | Discuss generalizability | Discussion; Limitations | Add a final paragraph on applicability to sampled US adults and limits across survey eras. |
| 22 | Give funding source and funder role | End matter | Included: National Excellent Young Physician Program (Document No. 2024[41]); funder role stated. |
