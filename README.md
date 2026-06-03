# Urinary albumin-to-creatinine ratio, total thyroxine, and mortality risk among U.S. adults

This repository contains the reproducible analysis code and derived aggregate result tables for the PLOS ONE manuscript:

**Urinary albumin-to-creatinine ratio, total thyroxine, and mortality risk among U.S. adults: evidence from NHANES 2007-2012**

The main analysis evaluates the association between urinary albumin-to-creatinine ratio (UACR) and total thyroxine (TT4) in NHANES 2007-2012, with mortality follow-up through the NCHS public-use linked mortality file. NHANES III is reported as a supplementary assessment and was not statistically replicated. The bidirectional Mendelian randomization module is an exploratory genetic analysis and is supplementary only.

Repository URL: https://github.com/HAOYANGLI888/uacr-tt4-nhanes-plosone

## Repository Contents

```text
uacr-tt4-nhanes-plosone/
|-- README.md
|-- LICENSE
|-- .gitignore
|-- requirements.txt
|-- environment.yml
|-- config/
|   |-- variables.yaml
|   |-- variables_discovery.yaml
|   |-- variables_validation_nhanes3.yaml
|   `-- analysis_plan.yaml
|-- scripts/
|   |-- 01_build_discovery_nhanes_2007_2012.py
|   |-- 02_build_validation_nhanes3.py
|   |-- 03_discovery_validation_regression.R
|   |-- 05_TT4_robustness.R
|   |-- 07_mortality_analysis.R
|   |-- 08_bidirectional_mr.R
|   `-- 09_mortality_extension.R
|-- outputs/
|   |-- tables/
|   |-- figures/
|   `-- reports/
`-- manuscript/
    |-- data_availability_statement.md
    |-- strobe_checklist_mapping.md
    `-- supplementary_table_list.md
```

## Data Sources

This study uses publicly available, de-identified data from:

- NHANES 2007-2012 continuous cycles: https://wwwn.cdc.gov/nchs/nhanes/continuousnhanes/default.aspx
- NHANES III: https://wwwn.cdc.gov/nchs/nhanes/nhanes3/datafiles.aspx
- NCHS public-use linked mortality files: https://www.cdc.gov/nchs/data-linkage/mortality-public.htm
- OpenGWAS summary-level data for supplementary exploratory genetic analyses: https://gwas.mrcieu.ac.uk/

Raw NHANES, NHANES III, mortality, and OpenGWAS cache files are not redistributed in this repository. Users should download public-use files from the official source websites and place them under the paths described below before rerunning the full pipeline.

## Expected Local Data Layout

```text
data/raw/nhanes_2007_2012/
  2007-2008/*.xpt
  2009-2010/*.xpt
  2011-2012/*.xpt

data/raw/nhanes3/
  adult.dat
  adult.sas
  exam.dat
  exam.sas
  lab.dat
  lab.sas
  lab2.dat
  lab2.sas

data/raw/linked_mortality_2019/
  NHANES_2007_2008_MORT_2019_PUBLIC.dat
  NHANES_2009_2010_MORT_2019_PUBLIC.dat
  NHANES_2011_2012_MORT_2019_PUBLIC.dat
```

## Environment

Using conda is recommended:

```bash
conda env create -f environment.yml
conda activate thyroid_uacr_routeB
```

Python-only dependencies can be installed with:

```bash
python -m pip install -r requirements.txt
```

The R analysis requires R packages listed in `environment.yml`, including `survey`, `survival`, `rms`, `ggplot2`, `ragg`, and `svglite`.

## Reproducibility

All scripts should be run from the repository root. Scripts are numbered in the order used for the analysis.

```bash
python scripts/01_build_discovery_nhanes_2007_2012.py
python scripts/02_build_validation_nhanes3.py
Rscript scripts/03_discovery_validation_regression.R
Rscript scripts/05_TT4_robustness.R
Rscript scripts/07_mortality_analysis.R
Rscript scripts/09_mortality_extension.R
Rscript scripts/08_bidirectional_mr.R
```

The exploratory MR script requires a locally configured OpenGWAS JWT environment variable. No credential value is included in this repository.

## Main Outputs

Key aggregate outputs include:

- `outputs/tables/Table1_discovery_baseline_characteristics.csv`
- `outputs/tables/Table2_discovery_main_results.csv`
- `outputs/tables/Table_mortality_main.csv`
- `outputs/tables/TableS_TT4_robustness.csv`
- `outputs/tables/Table_harmonized_discovery_validation_TT4.csv`
- `outputs/tables/Table_MR_main.csv`
- `outputs/figures/submission/Figure1_RCS_TT4.pdf`
- `outputs/figures/submission/Figure2_mortality_forest.pdf`
- `outputs/reports/final_result_audit.md`

## Credentials and Privacy

Do not commit:

- OpenGWAS credential values
- `.Renviron`
- API tokens or secrets
- local absolute-path cache files
- non-public raw data
- temporary files or logs containing local paths

## License

This analysis code is released under the MIT License. Data remain governed by their original public-use data-source terms.
