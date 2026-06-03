# Validation diagnostic report

This report compares NHANES 2007-2012 discovery and NHANES III validation distributions before interpreting replication failure.

## TT4 Distribution
| Cohort | Unit | Range | Weighted mean (SE) | Weighted median | Weighted IQR | IQR extreme n |
|---|---|---:|---:|---:|---:|---:|
| discovery | ug/dL | 2.500 to 27.600 | 7.801 (0.038) | 7.620 | 6.800 to 8.600 | 25 |
| validation | ug/dL | 0.400 to 32.000 | 8.682 (0.065) | 8.600 | 7.400 to 9.900 | 14 |

## UACR Distribution
| Cohort | Unit | Range | Weighted median | Weighted IQR | UACR <=0 n | Inf n | NaN n |
|---|---|---:|---:|---:|---:|---:|---:|
| discovery | mg/g | 0.216 to 9570.552 | 6.260 | 4.200 to 10.650 | 0 | 0 | 0 |
| validation | mg/g | 0.108 to 18473.896 | 5.465 | 3.437 to 9.316 | 0 | 0 | 0 |

## LOG_UACR Check
| Cohort | Natural log max absolute error | UACR <=0 n | LOG_UACR Inf n | LOG_UACR NaN n |
|---|---:|---:|---:|---:|
| discovery | 0.00000000 | 0 | 0 | 0 |
| validation | 0.00000000 | 0 | 0 | 0 |

## UACR Clinical Category Weighted Percentage
| Cohort | Category | Weighted percentage |
|---|---|---:|
| discovery | <30 | 91.779 |
| discovery | 30-300 | 6.969 |
| discovery | >=300 | 1.252 |
| validation | <30 | 92.598 |
| validation | 30-300 | 6.425 |
| validation | >=300 | 0.977 |

## Unit Notes
- TT4 is treated as ug/dL in both cohorts: discovery uses LBXTT4/TT4 and NHANES III uses T4P/TT4. No SI conversion was applied.
- UACR is treated as mg/g in both cohorts and LOG_UACR is checked against the natural logarithm of UACR.
- TT4 extreme values are flagged using an unweighted Q1 - 3*IQR / Q3 + 3*IQR rule.
