# Mortality extension summary

This module extends the NHANES 2007-2012 discovery cohort mortality analysis. It is observational and does not establish causality.

Eligible participants with follow-up: 6484.
All-cause deaths: 897.
Cardiovascular deaths: 249.

## Main Interpretation
- Risk-stratification wording: **UACR-dominant joint risk pattern requiring cautious interpretation**.
- UACR >=30 mg/g with high TT4 was the highest-risk Q4-defined group for both outcomes: FALSE.
- Q4-defined joint groups showed a progressive increase for both outcomes: FALSE.
- Model 3 interaction tests supported effect modification: FALSE.
- TT4 role: secondary prognostic marker because sensitivity estimates were not uniformly stable.
- TT4 sensitivity models positive: 13/14; nominally significant: 6/14.

## Q4-Defined Joint Groups, Model 3
| Outcome | Group | HR (95% CI) | P | n | Events in group |
|---|---|---:|---:|---:|---:|
| all_cause_mortality | UACR <30 + TT4 non-high | 1.000 (1.000 to 1.000) | NA | 6484 | 412 |
| all_cause_mortality | UACR >=30 + TT4 non-high | 2.682 (2.062 to 3.490) | 1.97e-13 | 6484 | 193 |
| all_cause_mortality | UACR <30 + TT4 high | 1.290 (1.071 to 1.555) | 0.007 | 6484 | 200 |
| all_cause_mortality | UACR >=30 + TT4 high | 2.457 (1.745 to 3.459) | 2.59e-07 | 6484 | 92 |
| cardiovascular_mortality | UACR <30 + TT4 non-high | 1.000 (1.000 to 1.000) | NA | 6484 | 114 |
| cardiovascular_mortality | UACR >=30 + TT4 non-high | 2.226 (1.344 to 3.687) | 0.002 | 6484 | 57 |
| cardiovascular_mortality | UACR <30 + TT4 high | 1.031 (0.602 to 1.765) | 0.911 | 6484 | 50 |
| cardiovascular_mortality | UACR >=30 + TT4 high | 1.754 (0.946 to 3.252) | 0.074 | 6484 | 28 |

## Interaction Tests, Model 3
| Outcome | Interaction | Definition | P for interaction |
|---|---|---|---:|
| all_cause_mortality | LOG_UACR:TT4 interaction | continuous TT4 | 0.464 |
| all_cause_mortality | UACR_ALBUMINURIA:TT4_HIGH_Q4 interaction | TT4 highest quartile (Q4) | 0.097 |
| all_cause_mortality | UACR_ALBUMINURIA:TT4_HIGH_T3 interaction | TT4 highest tertile sensitivity | 0.350 |
| cardiovascular_mortality | LOG_UACR:TT4 interaction | continuous TT4 | 0.195 |
| cardiovascular_mortality | UACR_ALBUMINURIA:TT4_HIGH_Q4 interaction | TT4 highest quartile (Q4) | 0.483 |
| cardiovascular_mortality | UACR_ALBUMINURIA:TT4_HIGH_T3 interaction | TT4 highest tertile sensitivity | 0.194 |

## PH Assumption Diagnostic
Survey-weighted Cox models do not provide a validated direct `cox.zph` workflow. Diagnostic PH checks therefore use non-weighted `coxph` models with the same Model 3 covariates.
All four global diagnostic P values exceeded 0.05. 8 covariate-level nominal signal(s) are retained in `Table_mortality_sensitivity.csv` for cautious interpretation.

| Outcome | Exposure | Global PH P |
|---|---|---:|
| all_cause_mortality | LOG_UACR | 0.053 |
| all_cause_mortality | TT4 | 0.064 |
| cardiovascular_mortality | LOG_UACR | 0.116 |
| cardiovascular_mortality | TT4 | 0.073 |

## Notes
- Primary TT4-high definition: weighted highest quartile (Q4). Highest tertile is included as a sensitivity definition.
- Model 1 adjusts for age, sex, and race.
- Model 2 additionally adjusts for education, PIR, BMI, smoking, and drinking.
- Model 3 additionally adjusts for diabetes, hypertension, eGFR, and UIC.
- Early-death sensitivity analysis excludes all-cause deaths occurring within the first 2 years of follow-up.
- Cardiovascular mortality uses public-use UCOD_LEADING heart-disease and cerebrovascular-disease categories.
- NHANES III findings remain not replicated and are not reinterpreted in this mortality extension.
