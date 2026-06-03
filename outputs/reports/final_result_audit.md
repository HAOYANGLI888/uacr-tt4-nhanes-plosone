# Final result audit for PLOS ONE submission

## Frozen manuscript title

Urinary albumin-to-creatinine ratio, total thyroxine, and mortality risk among U.S. adults: evidence from NHANES 2007–2012

## Frozen main-text storyline

1. In NHANES 2007-2012, higher natural-log UACR was associated with higher TT4.
2. The UACR-TT4 association remained positive across prespecified sensitivity analyses and showed no evidence of non-linearity.
3. Higher natural-log UACR was associated with higher all-cause and cardiovascular mortality.
4. TT4 showed a modest association with all-cause mortality but not cardiovascular mortality.
5. The NHANES III result was not statistically replicated and is placed in the Supplementary Materials.
6. The genetic module is an exploratory genetic analysis in the Supplementary Materials and does not establish causality.

## Frozen numerical results

### NHANES 2007-2012 TT4 analysis

- Discovery cohort: n=6487.
- Natural-log UACR -> TT4, fully adjusted model: beta=0.077, 95% CI 0.035-0.119, P=0.001, FDR-adjusted P=0.010.
- UACR 30-300 vs <30 mg/g -> TT4: beta=0.228, 95% CI 0.032-0.425, P=0.031.
- UACR >=300 vs <30 mg/g -> TT4: beta=0.412, 95% CI 0.127-0.696, P=0.009.
- Clinical-category trend: P=0.005.
- Restricted cubic spline: P overall=0.00463; P non-linearity=0.518.

### Mortality analysis

- Eligible follow-up: n=6484.
- Survey-weighted median follow-up: 9.83 years (IQR 8.08-11.25).
- All-cause deaths: 897.
- Cardiovascular deaths: 249.
- Natural-log UACR -> all-cause mortality: HR=1.387, 95% CI 1.285-1.498, P<0.001.
- Natural-log UACR -> cardiovascular mortality: HR=1.331, 95% CI 1.161-1.526, P<0.001.
- TT4 -> all-cause mortality: HR=1.065, 95% CI 1.009-1.125, P=0.022.
- TT4 -> cardiovascular mortality: HR=1.108, 95% CI 0.978-1.255, P=0.108.

### Supplementary NHANES III assessment

- NHANES III cohort: n=11302; harmonized H3 n=11200.
- Natural-log UACR -> TT4, H3: beta=0.003, 95% CI -0.074 to 0.080, P=0.932.
- Clinical-category trend: P=0.541.
- Required wording: **not statistically replicated in NHANES III**.

### Supplementary exploratory genetic analysis

- Keep the genetic analysis outside the main evidence chain.
- FT4 and TT4 GWAS were unavailable in the searchable OpenGWAS index.
- UACR and albuminuria each had one LD-clumped genome-wide significant instrument.
- The TSH -> eGFR result is a single-SNP exploratory result based on a TSH protein proxy.
- Do not use the genetic results to claim a direct UACR-TT4 pathway.

## Submission artifacts generated

- `manuscript/PLOS_ONE_title_page_final.docx`
- `manuscript/PLOS_ONE_main_manuscript_final.docx`
- `manuscript/PLOS_ONE_cover_letter_final.docx`
- `manuscript/PLOS_ONE_STROBE_checklist_final.docx`
- `manuscript/PLOS_ONE_data_availability_statement_final.md`
- `manuscript/PLOS_ONE_ethics_statement_final.md`
- `manuscript/PLOS_ONE_competing_interests_statement_final.md`
- `manuscript/PLOS_ONE_funding_statement_final.md`
- `outputs/tables/final_main_table_list.csv`
- `outputs/tables/final_supplementary_table_list.csv`
- `manuscript/PLOS_ONE_Supplementary_Tables.docx`
- `manuscript/PLOS_ONE_Supplementary_Tables_full.xlsx`
- `manuscript/PLOS_ONE_Supplementary_Figure_Legends.md`
- `outputs/tables/final_figure_list.csv`
- `outputs/figures/submission/Figure1_RCS_TT4.pdf`
- `outputs/figures/submission/Figure2_mortality_forest.pdf`
- `outputs/figures/submission/FigureS1_joint_mortality.pdf`
- `outputs/figures/submission/FigureS2_exploratory_MR_forest.pdf`
- `outputs/reports/PLOS_ONE_author_information_audit.md`

## Final author actions before upload

1. Perform a final Word-layout review of tables and figure placement before upload.
2. Update STROBE page numbers after final pagination if the journal requires exact page numbers.
3. If a Zenodo DOI is minted later, add it during proofing; the submitted text currently uses the GitHub repository URL.

## Funding record

This study was supported by the National Excellent Young Physician Program (Document No. 2024[41]). The funder had no role in study design, data collection and analysis, decision to publish, or preparation of the manuscript.

## Competing interests record

The authors have declared that no competing interests exist.

## Ethics record

This study was a secondary analysis of publicly available, de-identified data from NHANES and NHANES III. NHANES protocols were reviewed and approved by the NCHS Research Ethics Review Board, and written informed consent was obtained from participants. Information on NHANES ethics review is available from NCHS: https://www.cdc.gov/nchs/nhanes/about/erb.html. The present study involved no direct participant contact and used only public-use files; therefore, additional institutional review board approval was not required.

## Claim guardrails

- Do not describe NHANES III as a successful replication.
- Do not state that UACR causes higher TT4.
- Do not claim a mortality effect-modification finding for UACR and TT4.
- Do not elevate TGAb or TPOAb to primary outcomes.
- Do not place the exploratory genetic analysis in the main evidence chain.

## Repository record

GitHub: https://github.com/HAOYANGLI888/uacr-tt4-nhanes-plosone

## Official guidance checked

- PLOS ONE submission guidelines: https://journals.plos.org/plosone/s/submission-guidelines
- PLOS data availability policy: https://journals.plos.org/plosone/s/data-availability
- STROBE cohort checklist: https://strobe-statement.org/fileadmin/Strobe/uploads/checklists/STROBE_checklist_v4_cohort.pdf
- NHANES ethics review information: https://www.cdc.gov/nchs/nhanes/about/erb.html
