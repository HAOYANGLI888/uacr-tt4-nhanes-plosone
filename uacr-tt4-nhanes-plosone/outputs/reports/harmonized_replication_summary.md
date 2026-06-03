# Harmonized replication summary

Primary comparison: LOG_UACR -> TT4 using harmonized covariate adjustment. Discovery H models intentionally do not adjust for UIC to improve comparability with NHANES III.

Replication wording status: **not replicated**.

Diagnostic interpretation: Validation H1/H2/H3 estimates were all close to zero, supporting a conclusion that NHANES III did not statistically reproduce the discovery association.

P for cohort interaction: 0.003.

## LOG_UACR -> TT4 Harmonized Models
| Cohort | Model | Beta (95% CI) | P | FDR | n | Weighted TT4 mean | Weighted UACR median | Direction |
|---|---|---:|---:|---:|---:|---:|---:|---|
| discovery | H1 | 0.110 (0.064 to 0.155) | 2.76e-05 | 1.66e-04 | 6487 | 7.801 | 6.260 | positive |
| discovery | H2 | 0.077 (0.035 to 0.119) | 0.001 | 0.002 | 6487 | 7.801 | 6.260 | positive |
| discovery | H3 | 0.077 (0.035 to 0.119) | 0.001 | 0.002 | 6487 | 7.801 | 6.260 | positive |
| validation | H1 | 0.006 (-0.065 to 0.078) | 0.859 | 0.932 | 11302 | 8.682 | 5.465 | positive |
| validation | H2 | 0.004 (-0.072 to 0.080) | 0.918 | 0.932 | 11302 | 8.682 | 5.465 | positive |
| validation | H3 | 0.003 (-0.074 to 0.080) | 0.932 | 0.932 | 11200 | 8.683 | 5.464 | positive |

## Clinical Category Trend, H3
| Cohort | Contrast | Beta (95% CI) | P | P trend | Direction |
|---|---|---:|---:|---:|---|
| discovery | UACR_CLINICAL_CATEGORY30-300 | 0.228 (0.032 to 0.424) | 0.031 | 0.005 | positive |
| discovery | UACR_CLINICAL_CATEGORY>=300 | 0.412 (0.127 to 0.696) | 0.008 | 0.005 | positive |
| validation | UACR_CLINICAL_CATEGORY30-300 | -0.074 (-0.377 to 0.230) | 0.639 | 0.541 | negative |
| validation | UACR_CLINICAL_CATEGORY>=300 | -0.139 (-0.687 to 0.409) | 0.625 | 0.541 | negative |

## Conclusion Rules Applied
- Validation H1/H2/H3 all close to zero: TRUE.
- eGFR over-adjustment pattern observed: FALSE.
- Discovery without UIC significant while validation non-significant: TRUE.
