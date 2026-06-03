# Exploratory bidirectional MR summary

This report contains real OpenGWAS API-derived estimates only. No synthetic MR values are generated.

**Analysis role: exploratory MR analysis. Recommended manuscript placement: Supplementary Materials.**

These results do not establish causality. In particular, FT4 and TT4 GWAS were unavailable in the official searchable OpenGWAS index, so this module cannot test or support a direct causal UACR-to-TT4 interpretation.

Configured bidirectional trait pairs: 18.
Completed IVW analyses: 6.
Unavailable or non-estimable trait pairs: 12.

## OpenGWAS Trait Selection
| Trait | Status | OpenGWAS ID | Metadata trait | Instruments | Note |
|---|---|---|---|---:|---|
| UACR | selected | ieu-a-1107 | Urinary albumin-to-creatinine ratio | 1 | Automatically selected European-priority candidate with the largest reported sample size among direct trait matches. |
| albuminuria | selected | ieu-a-1097 | Microalbuminuria | 1 | Automatically selected European-priority candidate with the largest reported sample size among direct trait matches. |
| eGFR | selected | ebi-a-GCST90103634 | Estimated glomerular filtration rate (creatinine) | 342 | Automatically selected European-priority candidate with the largest reported sample size among direct trait matches. |
| TSH | selected | prot-a-530 | Thyroid Stimulating Hormone | 1 | Automatically selected European-priority candidate with the largest reported sample size among direct trait matches. |
| FT4 | unavailable |  |  | NA | No direct OpenGWAS metadata match for pattern: (^FT4$|^Free T4$|free thyroxine) |
| TT4 | unavailable |  |  | NA | No direct OpenGWAS metadata match for pattern: (^TT4$|^Total T4$|total thyroxine) |

## IVW Results
| Direction | Exposure | Outcome | SNPs | Beta (95% CI) | P | FDR | Status |
|---|---|---|---:|---:|---:|---:|---|
| kidney_to_thyroid | UACR | TSH | 1 | -0.1262 (-1.1833 to 0.9309) | 0.815 | 0.815 | complete |
| kidney_to_thyroid | UACR | FT4 | NA | NA (NA to NA) | NA | NA | unavailable |
| kidney_to_thyroid | UACR | TT4 | NA | NA (NA to NA) | NA | NA | unavailable |
| kidney_to_thyroid | albuminuria | TSH | 1 | -0.1800 (-0.5141 to 0.1541) | 0.291 | 0.436 | complete |
| kidney_to_thyroid | albuminuria | FT4 | NA | NA (NA to NA) | NA | NA | unavailable |
| kidney_to_thyroid | albuminuria | TT4 | NA | NA (NA to NA) | NA | NA | unavailable |
| kidney_to_thyroid | eGFR | TSH | 337 | -0.8854 (-1.8977 to 0.1270) | 0.087 | 0.260 | complete |
| kidney_to_thyroid | eGFR | FT4 | NA | NA (NA to NA) | NA | NA | unavailable |
| kidney_to_thyroid | eGFR | TT4 | NA | NA (NA to NA) | NA | NA | unavailable |
| thyroid_to_kidney | TSH | UACR | 1 | -0.0512 (-0.1446 to 0.0421) | 0.282 | 0.436 | complete |
| thyroid_to_kidney | TSH | albuminuria | 1 | -0.0592 (-0.3561 to 0.2378) | 0.696 | 0.815 | complete |
| thyroid_to_kidney | TSH | eGFR | 1 | -0.0079 (-0.0122 to -0.0037) | 2.46e-04 | 0.001 | complete |
| thyroid_to_kidney | FT4 | UACR | NA | NA (NA to NA) | NA | NA | unavailable |
| thyroid_to_kidney | FT4 | albuminuria | NA | NA (NA to NA) | NA | NA | unavailable |
| thyroid_to_kidney | FT4 | eGFR | NA | NA (NA to NA) | NA | NA | unavailable |
| thyroid_to_kidney | TT4 | UACR | NA | NA (NA to NA) | NA | NA | unavailable |
| thyroid_to_kidney | TT4 | albuminuria | NA | NA (NA to NA) | NA | NA | unavailable |
| thyroid_to_kidney | TT4 | eGFR | NA | NA (NA to NA) | NA | NA | unavailable |

## Multi-SNP Sensitivity Highlights
| Analysis | Method | Detail | SNPs | Beta | P |
|---|---|---|---:|---:|---:|
| forward_egfr_tsh | MR-Egger | intercept=-0.000575223; intercept_p=0.733587 | 337 | -0.9147 | 0.089 |
| forward_egfr_tsh | weighted median |  | 337 | -0.4699 | 0.443 |
| forward_egfr_tsh | weighted mode |  | 337 | -0.6712 | 0.454 |
| forward_egfr_tsh | MR-PRESSO | global_test | 337 | NA | 0.278 |
| forward_egfr_tsh | Steiger directionality | reverse_direction_possible | 337 | -0.1097 | NA |

## Primary Interpretation
- This exploratory MR module should be reported in the Supplementary Materials rather than used as the main causal evidence.
- FT4 and TT4 were unavailable, preventing direct genetic evaluation of the NHANES UACR-TT4 association.
- UACR and albuminuria each had only one LD-clumped genome-wide significant instrument, limiting robustness checks.
- The eGFR -> TSH estimate was not statistically significant after FDR correction.
- The TSH -> eGFR association is a **single-SNP exploratory result** based on a TSH protein proxy and should not be interpreted as causal evidence.

## Interpretation Guardrails
- OpenGWAS index matches were selected automatically using European-priority direct trait matches and the largest reported sample size.
- The selected TSH accession `prot-a-530` is an OpenGWAS protein-measurement dataset. Treat it as a TSH protein proxy; it is not interchangeable with a large population clinical-laboratory TSH GWAS.
- Single-SNP IVW estimates are numerically equivalent to Wald-ratio estimates and do not support multi-instrument sensitivity methods.
- FT4 or TT4 rows remain unavailable when the official OpenGWAS searchable index does not contain a direct trait match.
- Do not claim a direct causal UACR-to-TT4 relationship: direct TT4 MR analysis was unavailable.
- Do not describe any result in this module as establishing causality.
- MR estimates should be described only as exploratory genetic evidence consistent or inconsistent with a directional association.
- NHANES III findings remain not replicated and are not reinterpreted by this MR module.

## Unavailable Traits
- FT4: No direct OpenGWAS metadata match for pattern: (^FT4$|^Free T4$|free thyroxine)
- TT4: No direct OpenGWAS metadata match for pattern: (^TT4$|^Total T4$|total thyroxine)
