# NHANES 2007-2012 mortality analysis summary

This exploratory mortality module links the discovery cohort to the CDC public-use linked mortality file with follow-up through December 31, 2019.

Eligible participants with follow-up: 6484.
All-cause deaths: 897.
Cardiovascular deaths: 249.

## Continuous Exposures, Full Model
| Outcome | Exposure | HR (95% CI) | P | FDR | n | Events |
|---|---|---:|---:|---:|---:|---:|
| all_cause_mortality | LOG_UACR | 1.387 (1.285 to 1.498) | 6.42e-17 | 6.42e-17 | 6484 | 897 |
| all_cause_mortality | TT4 | 1.065 (1.009 to 1.125) | 0.022 | 0.022 | 6484 | 897 |
| cardiovascular_mortality | LOG_UACR | 1.331 (1.161 to 1.526) | 4.24e-05 | 4.24e-05 | 6484 | 249 |
| cardiovascular_mortality | TT4 | 1.108 (0.978 to 1.255) | 0.108 | 0.108 | 6484 | 249 |

## Model Notes
- H1 adjusts for age, sex, and race.
- Full adjusts for age, sex, race, education, PIR, BMI, smoking, drinking, diabetes, hypertension, eGFR, and UIC.
- Cardiovascular mortality is defined from UCOD_LEADING as diseases of heart or cerebrovascular diseases.
- Joint categories use UACR clinical groups and weighted TT4 tertiles. The reference is UACR <30 mg/g with TT4 tertile T1.
- This is an observational survival extension. It does not establish causality.
- CDC public-use linked mortality files protect confidentiality by perturbing selected information; estimates should be interpreted accordingly.

## Official Data Source
- CDC public-use linked mortality documentation: https://www.cdc.gov/nchs/data-linkage/mortality-public.htm
- CDC linked mortality FTP directory: https://ftp.cdc.gov/pub/Health_Statistics/NCHS/datalinkage/linked_mortality/
