# TT4 robustness summary

Primary outcome: TT4. TGAB is not treated as a primary conclusion in this robustness report.

All survey models use Model 3 covariate adjustment where covariates have non-missing values and variation within the analyzed subset.

## Evidence judgement
- Moderate evidence for a positive association between UACR and TT4 after robustness checks: 7/7 LOG_UACR models were positive, 7/7 were nominally significant, and RCS overall P = 0.005.
- Directionally consistent in most sensitivity analyses: TRUE.
- Evidence upgraded from weak to moderate: TRUE.

## RCS
- P for overall association: 0.005.
- P for non-linearity: 0.518.
- The RCS figure marks UACR = 30 mg/g and 300 mg/g.

## Continuous-exposure robustness models
| Analysis | Exposure | Contrast | Beta (95% CI) | P | FDR | n | Direction |
|---|---|---|---:|---:|---:|---:|---|
| Full Model 3 cohort | LOG_UACR | LOG_UACR | 0.077 (0.035 to 0.119) | 0.001 | 0.015 | 6487 | positive |
| Full Model 3 cohort | LOG2_UACR | LOG2_UACR | 0.053 (0.024 to 0.082) | 0.001 | 0.015 | 6487 | positive |
| Exclude eGFR <60 | LOG_UACR | LOG_UACR | 0.073 (0.023 to 0.123) | 0.008 | 0.032 | 6045 | positive |
| Exclude eGFR <60 | LOG2_UACR | LOG2_UACR | 0.051 (0.016 to 0.085) | 0.008 | 0.032 | 6045 | positive |
| Exclude diabetes | LOG_UACR | LOG_UACR | 0.075 (0.020 to 0.129) | 0.012 | 0.038 | 5627 | positive |
| Exclude diabetes | LOG2_UACR | LOG2_UACR | 0.052 (0.014 to 0.090) | 0.012 | 0.038 | 5627 | positive |
| Exclude hypertension | LOG_UACR | LOG_UACR | 0.071 (0.005 to 0.138) | 0.045 | 0.102 | 3802 | positive |
| Exclude hypertension | LOG2_UACR | LOG2_UACR | 0.049 (0.003 to 0.095) | 0.045 | 0.102 | 3802 | positive |
| Exclude UACR >=300 | LOG_UACR | LOG_UACR | 0.073 (0.022 to 0.124) | 0.009 | 0.032 | 6356 | positive |
| Exclude UACR >=300 | LOG2_UACR | LOG2_UACR | 0.051 (0.016 to 0.086) | 0.009 | 0.032 | 6356 | positive |
| Keep UACR p1-p99 | LOG_UACR | LOG_UACR | 0.077 (0.026 to 0.128) | 0.006 | 0.032 | 6357 | positive |
| Keep UACR p1-p99 | LOG2_UACR | LOG2_UACR | 0.053 (0.018 to 0.088) | 0.006 | 0.032 | 6357 | positive |
| Euthyroid participants | LOG_UACR | LOG_UACR | 0.078 (0.040 to 0.116) | 4.07e-04 | 0.010 | 5934 | positive |
| Euthyroid participants | LOG2_UACR | LOG2_UACR | 0.054 (0.028 to 0.080) | 4.07e-04 | 0.010 | 5934 | positive |

## Full-cohort categorical exposure checks
| Analysis | Exposure | Contrast | Beta (95% CI) | P | FDR | n | Direction |
|---|---|---|---:|---:|---:|---:|---|
| Full Model 3 cohort | UACR_QUARTILE | UACR_QUARTILEQ2 | 0.024 (-0.159 to 0.206) | 0.802 | 0.873 | 6487 | positive |
| Full Model 3 cohort | UACR_QUARTILE | UACR_QUARTILEQ3 | 0.077 (-0.067 to 0.220) | 0.307 | 0.433 | 6487 | positive |
| Full Model 3 cohort | UACR_QUARTILE | UACR_QUARTILEQ4 | 0.129 (-0.008 to 0.266) | 0.077 | 0.148 | 6487 | positive |
| Full Model 3 cohort | UACR_CLINICAL_CATEGORY | UACR_CLINICAL_CATEGORY30-300 | 0.228 (0.032 to 0.425) | 0.031 | 0.079 | 6487 | positive |
| Full Model 3 cohort | UACR_CLINICAL_CATEGORY | UACR_CLINICAL_CATEGORY>=300 | 0.412 (0.127 to 0.696) | 0.009 | 0.032 | 6487 | positive |

## Outputs
- outputs/tables/TableS_TT4_robustness.csv
- outputs/figures/Figure2_RCS_TT4.pdf
- outputs/logs/05_TT4_robustness.log
