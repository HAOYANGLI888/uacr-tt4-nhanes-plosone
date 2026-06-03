# NHANES III TT4 validation summary

Primary validation outcome: TT4.

TGAb and TPOAb are not used as validation primary outcomes in this report; they are treated only as exploratory availability markers.

## Replication judgement
- LOG_UACR -> TT4 in NHANES III Model 3 was positive (beta=0.003, 95% CI -0.074 to 0.080, P=0.932).
- Directionally consistent with discovery: TRUE.
- Validation P < 0.05: FALSE.
- UACR clinical category supports positive trend: FALSE.
- Replication status: directionally_consistent_only.

## Model 3 validation results
| Exposure | Contrast | Model | Beta (95% CI) | P | FDR | P trend | n | Direction |
|---|---|---|---:|---:|---:|---:|---:|---|
| log_UACR | LOG_UACR | Model 3 | 0.003 (-0.074 to 0.080) | 0.932 | 0.987 | NA | 11200 | positive |
| UACR quartile | UACR_QUARTILEQ2 | Model 3 | 0.015 (-0.202 to 0.232) | 0.891 | 0.987 | 0.573 | 11200 | positive |
| UACR quartile | UACR_QUARTILEQ3 | Model 3 | 0.066 (-0.179 to 0.310) | 0.603 | 0.987 | 0.573 | 11200 | positive |
| UACR quartile | UACR_QUARTILEQ4 | Model 3 | 0.060 (-0.203 to 0.323) | 0.659 | 0.987 | 0.573 | 11200 | positive |
| UACR clinical category | UACR_CLINICAL_CATEGORY30-300 | Model 3 | -0.074 (-0.377 to 0.230) | 0.639 | 0.987 | 0.541 | 11200 | negative |
| UACR clinical category | UACR_CLINICAL_CATEGORY>=300 | Model 3 | -0.139 (-0.687 to 0.409) | 0.625 | 0.987 | 0.541 | 11200 | negative |

## Exploratory thyroid marker availability
- TSH: available=True, nonmissing n=18148
- TT4: available=True, nonmissing n=17795
- TGAB: available=True, nonmissing n=18148
- TPOAB: available=True, nonmissing n=18148

## Notes
- Model 3 adjusts for age, sex, race, education, PIR, BMI, smoking, drinking, diabetes, hypertension, and eGFR when available.
- NHANES III validation models do not adjust for UIC.
- Survey design uses WTPFEX6, SDPPSU6, and SDPSTRA6.
