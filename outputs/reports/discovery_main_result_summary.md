# Discovery main result summary

Source tables:
- outputs/tables/Table2_discovery_main_results.csv
- outputs/tables/TableS_full_thyroid_results.csv

Filter: discovery cohort, primary outcomes TT4 and TGAB, Model 3.

Direction consistency rule: LOG_UACR uses its beta; UACR_QUARTILE uses Q4 vs Q1; UACR_CLINICAL_CATEGORY uses >=300 vs <30.

## Evidence conclusion
- Weak evidence for a positive association between UACR and TT4 in Model 3.
- No evidence for a mixed association between UACR and TGAB in Model 3.

Evidence grading rule: Strong evidence requires directional consistency and FDR significance in all three exposure definitions; Moderate evidence requires directional consistency and FDR significance in at least two exposure definitions; Weak evidence requires any FDR-significant exposure definition or at least two nominally significant exposure definitions; otherwise No evidence.

## Direction and significance checks
- TT4: directionally consistent across exposure definitions = TRUE; exposure definitions significant before FDR = 2; after FDR = 1.
- TGAB: directionally consistent across exposure definitions = FALSE; exposure definitions significant before FDR = 1; after FDR = 0.

## Model 3 results
| Outcome | Exposure | Contrast | Beta (95% CI) | P | FDR | Direction | Significant before FDR | Significant after FDR |
|---|---|---|---:|---:|---:|---|---|---|
| TT4 | LOG_UACR | LOG_UACR | 0.077 (0.035 to 0.119) | 0.001 | 0.010 | positive | TRUE | TRUE |
| TT4 | UACR_QUARTILE | UACR_QUARTILEQ2 | 0.024 (-0.159 to 0.206) | 0.802 | 0.982 | positive | FALSE | FALSE |
| TT4 | UACR_QUARTILE | UACR_QUARTILEQ3 | 0.077 (-0.067 to 0.220) | 0.307 | 0.986 | positive | FALSE | FALSE |
| TT4 | UACR_QUARTILE | UACR_QUARTILEQ4 | 0.129 (-0.008 to 0.266) | 0.077 | 0.243 | positive | FALSE | FALSE |
| TT4 | UACR_CLINICAL_CATEGORY | UACR_CLINICAL_CATEGORY30-300 | 0.228 (0.032 to 0.425) | 0.031 | 0.124 | positive | TRUE | FALSE |
| TT4 | UACR_CLINICAL_CATEGORY | UACR_CLINICAL_CATEGORY>=300 | 0.412 (0.127 to 0.696) | 0.009 | 0.069 | positive | TRUE | FALSE |
| TGAB | LOG_UACR | LOG_UACR | 0.773 (-0.320 to 1.867) | 0.176 | 0.471 | positive | FALSE | FALSE |
| TGAB | UACR_QUARTILE | UACR_QUARTILEQ2 | 8.488 (1.975 to 15.000) | 0.017 | 0.128 | positive | TRUE | FALSE |
| TGAB | UACR_QUARTILE | UACR_QUARTILEQ3 | 3.557 (0.959 to 6.155) | 0.012 | 0.100 | positive | TRUE | FALSE |
| TGAB | UACR_QUARTILE | UACR_QUARTILEQ4 | 4.749 (0.982 to 8.516) | 0.020 | 0.163 | positive | TRUE | FALSE |
| TGAB | UACR_CLINICAL_CATEGORY | UACR_CLINICAL_CATEGORY30-300 | 0.029 (-4.436 to 4.495) | 0.990 | 0.990 | positive | FALSE | FALSE |
| TGAB | UACR_CLINICAL_CATEGORY | UACR_CLINICAL_CATEGORY>=300 | -3.387 (-8.103 to 1.329) | 0.171 | 0.455 | negative | FALSE | FALSE |
