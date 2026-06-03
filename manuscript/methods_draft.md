# Methods draft

## Study design and data sources

We conducted an observational study integrating a cross-sectional discovery analysis, a replication assessment, a prospective mortality extension, and a Supplementary exploratory Mendelian randomization (MR) analysis. The discovery cohort comprised adults from the 2007-2008, 2009-2010, and 2011-2012 cycles of the National Health and Nutrition Examination Survey (NHANES). NHANES III was analyzed separately to assess whether the discovery association was statistically reproduced in an earlier survey cohort. The mortality extension linked eligible participants in the NHANES 2007-2012 discovery cohort to the public-use 2019 Linked Mortality File. The exploratory MR module used summary statistics retrieved from the OpenGWAS platform.

NHANES uses a complex, multistage probability sampling design. All survey-weighted analyses incorporated the relevant sampling weights, strata, and primary sampling units. This study was a secondary analysis of publicly available, de-identified data from NHANES and NHANES III. NHANES protocols were reviewed and approved by the NCHS Research Ethics Review Board, and written informed consent was obtained from participants. Information on NHANES ethics review is available from NCHS: https://www.cdc.gov/nchs/nhanes/about/erb.html. The present study involved no direct participant contact and used only public-use files; therefore, additional institutional review board approval was not required.

## Discovery cohort construction

NHANES 2007-2012 component files were merged by participant identifier (`SEQN`) within each survey cycle and then pooled across cycles. Participants were eligible for the discovery cohort if they were aged at least 18 years, were not pregnant, had a valid urine albumin-to-creatinine ratio (UACR) greater than zero, had non-missing common thyroid indicators used for discovery-replication comparability (thyroid-stimulating hormone [TSH], total thyroxine [TT4], thyroglobulin antibody [TGAb], and thyroid peroxidase antibody [TPOAb]), were not identified as thyroid-medication users, and had complete prespecified cohort-construction covariates. The final discovery cohort included 6487 participants.

For pooled discovery analyses, cycle-specific thyroid-related weights were used. The 2007-2008 cycle used the 2-year mobile examination center weight (`WTMEC2YR`), whereas the 2009-2010 and 2011-2012 cycles used the thyroid subsample weight (`WTSA2YR`). The selected 2-year weight was divided by three to obtain the pooled 6-year analysis weight (`ANALYTIC_WT6YR`). Survey designs used `ANALYTIC_WT6YR`, `SDMVPSU`, and `SDMVSTRA`.

## Replication cohort construction

NHANES III records were merged by participant identifier and analyzed separately. Adults aged at least 18 years were retained after excluding pregnant participants and participants with identified thyroid disease or thyroid-medication use where the relevant variables were available. Participants were additionally required to have valid UACR, TT4, and complete key covariates. The resulting replication cohort included 11302 participants. NHANES III survey analyses used `WTPFEX6`, `SDPPSU6`, and `SDPSTRA6`.

## Exposure definition

UACR was expressed in mg/g. When the NHANES UACR variable (`URDACT`) was available, it was retained and cross-checked against the calculated ratio. Otherwise, UACR was calculated as:

`100 x urine albumin (ug/mL) / urine creatinine (mg/dL)`.

Non-positive UACR values were treated as missing before transformation. The primary exposure was the natural logarithm of UACR (`LOG_UACR`). Secondary exposure definitions were UACR quartiles and clinical categories of <30, 30-300, and >=300 mg/g. For TT4 robustness analyses, UACR was also expressed on a log2 scale.

## Thyroid outcomes

TT4 was the primary thyroid outcome. Secondary thyroid outcomes in the discovery cohort were TSH, free triiodothyronine (FT3), free thyroxine (FT4), total triiodothyronine (TT3), and thyroglobulin (Tg). TGAb and TPOAb were treated as exploratory thyroid-autoimmunity outcomes and were not used as the primary manuscript conclusion. NHANES III analyses focused on the shared TT4 outcome, with other available common indicators retained for exploratory reporting.

## Covariates

Covariates were selected before outcome modeling on the basis of demographic, socioeconomic, lifestyle, metabolic, kidney-function, and iodine-related relevance. Discovery regression Model 1 was unadjusted. Model 2 adjusted for age, sex, and race/ethnicity. Model 3 additionally adjusted for education, poverty-income ratio (PIR), body mass index (BMI), smoking, alcohol use, diabetes, hypertension, estimated glomerular filtration rate (eGFR), and urinary iodine concentration (UIC). eGFR was calculated using the 2021 CKD-EPI creatinine equation.

For harmonized discovery-replication comparisons, H1 adjusted for age, sex, and race/ethnicity; H2 additionally adjusted for education, PIR, BMI, smoking, alcohol use, diabetes, and hypertension; and H3 additionally adjusted for eGFR. UIC was intentionally omitted from harmonized models because it was not available for the NHANES III comparison.

## Survey-weighted thyroid analyses

Associations of UACR with thyroid outcomes were estimated using survey-weighted generalized linear models implemented with the R `survey` package. Continuous-exposure models estimated the change in TT4 per one-unit increase in natural-log UACR. Categorical models compared UACR quartiles and clinical categories with their lowest categories and estimated P values for trend using ordinal scores. False-discovery-rate (FDR) correction was applied across multiple thyroid outcomes.

For the primary TT4 robustness analysis, restricted cubic splines modeled the association between natural-log UACR and TT4 using knots at the 5th, 35th, 65th, and 95th percentiles. Prespecified sensitivity analyses excluded participants with eGFR <60 mL/min/1.73 m2, diabetes, hypertension, UACR >=300 mg/g, or UACR values outside the 1st-99th percentile range, and separately restricted the analysis to euthyroid participants, defined as TSH 0.45-4.50 and FT4 0.60-1.60.

## Harmonized replication assessment

The discovery and NHANES III cohorts were analyzed using aligned exposure definitions and H1-H3 covariate blocks. To evaluate between-cohort heterogeneity, the cohorts were stacked with cohort-prefixed survey identifiers and a survey-weighted interaction term between natural-log UACR and cohort was fitted. This analysis assessed whether the discovery estimate differed from the NHANES III estimate; it was not used to describe NHANES III as statistically reproducing the discovery association.

## Mortality extension

The discovery cohort was linked by `SEQN` to the public-use 2019 NHANES Linked Mortality File. Participants were eligible for mortality analyses if `ELIGSTAT == 1` and follow-up months from the mobile examination center examination (`PERMTH_EXM`) were available. Follow-up time was calculated as `PERMTH_EXM / 12`. All-cause mortality was defined using `MORTSTAT == 1`. Cardiovascular mortality was defined among decedents using public-use leading underlying-cause categories for heart disease or cerebrovascular disease (`UCOD_LEADING` values 1 or 5).

Survey-weighted Cox proportional-hazards models were fitted for all-cause and cardiovascular mortality. Mortality Model 1 adjusted for age, sex, and race/ethnicity. Model 2 additionally adjusted for education, PIR, BMI, smoking, and alcohol use. Model 3 additionally adjusted for diabetes, hypertension, eGFR, and UIC. The primary mortality exposure was natural-log UACR. TT4 was evaluated as a secondary prognostic marker, including a per-standard-deviation sensitivity analysis.

Secondary mortality analyses evaluated four joint groups defined by UACR <30 or >=30 mg/g and TT4 below or within the weighted highest quartile. Multiplicative interaction terms were evaluated for natural-log UACR x TT4 and albuminuria category x high-TT4 group. Sensitivity analyses excluded deaths within the first two years of follow-up and restricted analyses to euthyroid participants. Because a validated direct `cox.zph` workflow is not available for survey-weighted Cox models, proportional-hazards assumptions were evaluated diagnostically using non-weighted Cox models with the same Model 3 covariates.

## Supplementary exploratory MR analysis

Exploratory bidirectional MR analyses were performed as Supplementary analyses using OpenGWAS summary statistics. The automatically selected direct trait matches were `ieu-a-1107` for UACR, `ieu-a-1097` for albuminuria, `ebi-a-GCST90103634` for creatinine-based eGFR, and `prot-a-530` for a TSH protein proxy. Genome-wide significant instruments were extracted at P < 5 x 10^-8 and LD-clumped using r2 = 0.001 and a 10,000-kb window in the European reference panel. FT4 and TT4 GWAS were unavailable in the searchable OpenGWAS index.

Inverse-variance weighted MR was the main method where estimable. MR-Egger, weighted-median, weighted-mode, MR-PRESSO, leave-one-out, and Steiger analyses were retained where instrument counts permitted. Single-SNP estimates were treated as Wald-ratio-equivalent exploratory results. This MR module does not establish causality.

## Software

Data construction used Python 3.12.7. Statistical analyses used R 4.5.3, including `survey` 4.5 and `survival` 3.8.6. OpenGWAS access used `ieugwasr` 1.1.0. Reproducible scripts, configuration files, logs, and derived output tables are retained in the project repository: https://github.com/HAOYANGLI888/uacr-tt4-nhanes-plosone.
