options(stringsAsFactors = FALSE)

find_project_root <- function(start = getwd()) {
  current <- normalizePath(start, winslash = "/", mustWork = TRUE)
  repeat {
    marker <- file.path(current, "config", "analysis_plan.yaml")
    if (file.exists(marker)) {
      return(current)
    }
    parent <- dirname(current)
    if (identical(parent, current)) {
      stop("Could not find project root containing config/analysis_plan.yaml.", call. = FALSE)
    }
    current <- parent
  }
}

init_logger <- function(root) {
  log_path <- file.path(root, "outputs", "logs", "10_generate_plos_table1.log")
  dir.create(dirname(log_path), recursive = TRUE, showWarnings = FALSE)
  if (file.exists(log_path)) {
    file.remove(log_path)
  }
  function(level, message) {
    line <- sprintf("%s | %s | %s", format(Sys.time(), "%Y-%m-%d %H:%M:%S"), level, message)
    cat(line, "\n")
    cat(line, "\n", file = log_path, append = TRUE)
  }
}

format_mean_se <- function(design, variable) {
  estimate <- survey::svymean(stats::as.formula(sprintf("~%s", variable)), design, na.rm = TRUE)
  sprintf("%.2f (%.2f)", as.numeric(stats::coef(estimate))[1], as.numeric(survey::SE(estimate))[1])
}

format_median_iqr <- function(design, variable) {
  estimate <- survey::svyquantile(
    stats::as.formula(sprintf("~%s", variable)),
    design,
    quantiles = c(0.25, 0.50, 0.75),
    ci = FALSE,
    na.rm = TRUE
  )
  values <- as.numeric(stats::coef(estimate))
  sprintf("%.2f (%.2f-%.2f)", values[2], values[1], values[3])
}

format_category <- function(design, variable, value) {
  values <- design$variables[[variable]]
  indicator <- as.numeric(values == value)
  indicator[is.na(values)] <- NA_real_
  design$variables$.TABLE1_INDICATOR <- indicator
  estimate <- survey::svymean(~.TABLE1_INDICATOR, design, na.rm = TRUE)
  count <- sum(indicator == 1, na.rm = TRUE)
  sprintf("%s (%.1f%%)", count, 100 * as.numeric(stats::coef(estimate))[1])
}

append_row <- function(rows, characteristic, statistic, designs, formatter) {
  values <- vapply(designs, formatter, character(1))
  rows[[length(rows) + 1]] <- data.frame(
    Characteristic = characteristic,
    Statistic = statistic,
    Overall = values[["Overall"]],
    UACR_LT30 = values[["UACR_LT30"]],
    UACR_30_300 = values[["UACR_30_300"]],
    UACR_GE300 = values[["UACR_GE300"]],
    stringsAsFactors = FALSE
  )
  rows
}

main <- function() {
  if (!requireNamespace("survey", quietly = TRUE)) {
    stop("R package 'survey' is required.", call. = FALSE)
  }

  root <- find_project_root()
  log <- init_logger(root)
  log("INFO", sprintf("Project root: %s", root))

  input_path <- file.path(root, "data", "processed", "discovery_nhanes_2007_2012.csv")
  output_path <- file.path(root, "outputs", "tables", "Table1_discovery_baseline_characteristics.csv")
  descriptive_output_path <- file.path(root, "outputs", "tables", "PLOS_submission_descriptive_summary.csv")
  if (!file.exists(input_path)) {
    stop(sprintf("Discovery dataset not found: %s", input_path), call. = FALSE)
  }

  data <- utils::read.csv(input_path, check.names = FALSE)
  required <- c(
    "AGE", "SEX", "RACE", "EDUCATION", "PIR", "BMI", "SMOKE", "DRINK",
    "DIABETES", "HYPERTENSION", "PHYSICAL_ACTIVITY", "UIC_UG_L", "EGFR",
    "UACR", "TT4", "TSH", "UACR_CLINICAL_CATEGORY", "ANALYTIC_WT6YR",
    "SDMVPSU", "SDMVSTRA"
  )
  missing <- setdiff(required, names(data))
  if (length(missing) > 0) {
    stop(sprintf("Required columns missing: %s", paste(missing, collapse = ", ")), call. = FALSE)
  }

  numeric_variables <- setdiff(required, "UACR_CLINICAL_CATEGORY")
  for (variable in numeric_variables) {
    data[[variable]] <- suppressWarnings(as.numeric(data[[variable]]))
  }
  data$UACR_CLINICAL_CATEGORY <- factor(
    data$UACR_CLINICAL_CATEGORY,
    levels = c("<30", "30-300", ">=300")
  )

  design <- survey::svydesign(
    ids = ~SDMVPSU,
    strata = ~SDMVSTRA,
    weights = ~ANALYTIC_WT6YR,
    nest = TRUE,
    data = data
  )
  designs <- list(
    Overall = design,
    UACR_LT30 = subset(design, UACR_CLINICAL_CATEGORY == "<30"),
    UACR_30_300 = subset(design, UACR_CLINICAL_CATEGORY == "30-300"),
    UACR_GE300 = subset(design, UACR_CLINICAL_CATEGORY == ">=300")
  )

  log("INFO", sprintf("Loaded discovery cohort: n=%s", nrow(data)))
  for (name in names(designs)) {
    log("INFO", sprintf("%s unweighted n=%s", name, nrow(designs[[name]]$variables)))
  }

  rows <- list()
  rows <- append_row(rows, "Age, years", "Mean (SE)", designs, function(x) format_mean_se(x, "AGE"))
  # Add the threshold indicator once so the age-group summary remains transparent.
  for (name in names(designs)) {
    designs[[name]]$variables$AGE_GE65 <- as.numeric(designs[[name]]$variables$AGE >= 65)
  }
  rows[[length(rows) + 1]] <- data.frame(
    Characteristic = "Age >=65 years",
    Statistic = "n (weighted %)",
    Overall = format_category(designs$Overall, "AGE_GE65", 1),
    UACR_LT30 = format_category(designs$UACR_LT30, "AGE_GE65", 1),
    UACR_30_300 = format_category(designs$UACR_30_300, "AGE_GE65", 1),
    UACR_GE300 = format_category(designs$UACR_GE300, "AGE_GE65", 1),
    stringsAsFactors = FALSE
  )

  categorical_rows <- list(
    c("Male", "SEX", "1"),
    c("Race/ethnicity: Mexican American", "RACE", "1"),
    c("Race/ethnicity: Other Hispanic", "RACE", "2"),
    c("Race/ethnicity: Non-Hispanic White", "RACE", "3"),
    c("Race/ethnicity: Non-Hispanic Black", "RACE", "4"),
    c("Race/ethnicity: Other or multiracial", "RACE", "5"),
    c("Education: Less than 9th grade", "EDUCATION", "1"),
    c("Education: 9th-11th grade", "EDUCATION", "2"),
    c("Education: High school graduate or GED", "EDUCATION", "3"),
    c("Education: Some college or associate degree", "EDUCATION", "4"),
    c("Education: College graduate or above", "EDUCATION", "5"),
    c("Smoking: Never", "SMOKE", "0"),
    c("Smoking: Former", "SMOKE", "1"),
    c("Smoking: Current", "SMOKE", "2"),
    c("Any alcohol use", "DRINK", "1"),
    c("Diabetes: Yes", "DIABETES", "1"),
    c("Diabetes: Borderline", "DIABETES", "2"),
    c("Hypertension", "HYPERTENSION", "1"),
    c("Any physical activity", "PHYSICAL_ACTIVITY", "1")
  )

  for (item in categorical_rows) {
    rows <- append_row(
      rows,
      item[1],
      "n (weighted %)",
      designs,
      function(x) format_category(x, item[2], as.numeric(item[3]))
    )
  }

  rows <- append_row(rows, "Poverty-income ratio", "Mean (SE)", designs, function(x) format_mean_se(x, "PIR"))
  rows <- append_row(rows, "Body mass index, kg/m2", "Mean (SE)", designs, function(x) format_mean_se(x, "BMI"))
  rows <- append_row(rows, "Urinary iodine concentration, ug/L", "Median (IQR)", designs, function(x) format_median_iqr(x, "UIC_UG_L"))
  rows <- append_row(rows, "eGFR, mL/min/1.73 m2", "Mean (SE)", designs, function(x) format_mean_se(x, "EGFR"))
  rows <- append_row(rows, "UACR, mg/g", "Median (IQR)", designs, function(x) format_median_iqr(x, "UACR"))
  rows <- append_row(rows, "TT4, ug/dL", "Mean (SE)", designs, function(x) format_mean_se(x, "TT4"))
  rows <- append_row(rows, "TSH, uIU/mL", "Median (IQR)", designs, function(x) format_median_iqr(x, "TSH"))

  table <- do.call(rbind, rows)
  names(table)[3:6] <- c(
    sprintf("Overall (n=%s)", nrow(designs$Overall$variables)),
    sprintf("UACR <30 mg/g (n=%s)", nrow(designs$UACR_LT30$variables)),
    sprintf("UACR 30-300 mg/g (n=%s)", nrow(designs$UACR_30_300$variables)),
    sprintf("UACR >=300 mg/g (n=%s)", nrow(designs$UACR_GE300$variables))
  )

  dir.create(dirname(output_path), recursive = TRUE, showWarnings = FALSE)
  utils::write.csv(table, output_path, row.names = FALSE, na = "")
  log("INFO", sprintf("Wrote %s baseline rows to %s", nrow(table), output_path))
  log("INFO", "Table 1 contains survey-weighted descriptive statistics only; no between-group hypothesis tests were generated.")

  mortality_path <- file.path(root, "data", "processed", "discovery_nhanes_2007_2012_mortality.csv")
  if (!file.exists(mortality_path)) {
    stop(sprintf("Linked mortality dataset not found: %s", mortality_path), call. = FALSE)
  }
  mortality <- utils::read.csv(mortality_path, check.names = FALSE)
  mortality_required <- c(
    "ELIGSTAT", "PERMTH_EXM", "ALL_CAUSE_DEATH", "CVD_DEATH",
    "ANALYTIC_WT6YR", "SDMVPSU", "SDMVSTRA"
  )
  mortality_missing <- setdiff(mortality_required, names(mortality))
  if (length(mortality_missing) > 0) {
    stop(sprintf("Linked mortality columns missing: %s", paste(mortality_missing, collapse = ", ")), call. = FALSE)
  }
  for (variable in mortality_required) {
    mortality[[variable]] <- suppressWarnings(as.numeric(mortality[[variable]]))
  }
  mortality <- mortality[
    !is.na(mortality$ELIGSTAT) &
      mortality$ELIGSTAT == 1 &
      !is.na(mortality$PERMTH_EXM) &
      mortality$PERMTH_EXM > 0,
  ]
  mortality$FOLLOWUP_YEARS <- mortality$PERMTH_EXM / 12
  mortality_design <- survey::svydesign(
    ids = ~SDMVPSU,
    strata = ~SDMVSTRA,
    weights = ~ANALYTIC_WT6YR,
    nest = TRUE,
    data = mortality
  )
  followup_quantiles <- as.numeric(stats::coef(survey::svyquantile(
    ~FOLLOWUP_YEARS,
    mortality_design,
    quantiles = c(0.25, 0.50, 0.75),
    ci = FALSE,
    na.rm = TRUE
  )))
  descriptive_summary <- data.frame(
    metric = c(
      "discovery_analytic_n",
      "mortality_eligible_n",
      "all_cause_deaths",
      "cardiovascular_deaths",
      "followup_years_weighted_median",
      "followup_years_weighted_q1",
      "followup_years_weighted_q3"
    ),
    value = c(
      nrow(data),
      nrow(mortality),
      sum(mortality$ALL_CAUSE_DEATH == 1, na.rm = TRUE),
      sum(mortality$CVD_DEATH == 1, na.rm = TRUE),
      followup_quantiles[2],
      followup_quantiles[1],
      followup_quantiles[3]
    ),
    note = c(
      "NHANES 2007-2012 discovery cohort",
      "ELIGSTAT == 1 and PERMTH_EXM > 0",
      "MORTSTAT == 1",
      "UCOD_LEADING heart disease or cerebrovascular disease categories",
      "Survey-weighted median",
      "Survey-weighted first quartile",
      "Survey-weighted third quartile"
    ),
    stringsAsFactors = FALSE
  )
  utils::write.csv(descriptive_summary, descriptive_output_path, row.names = FALSE, na = "")
  log("INFO", sprintf("Wrote submission descriptive summary to %s", descriptive_output_path))
  log(
    "INFO",
    sprintf(
      "Survey-weighted follow-up years: median=%.2f, IQR=%.2f-%.2f",
      followup_quantiles[2],
      followup_quantiles[1],
      followup_quantiles[3]
    )
  )
}

tryCatch(
  main(),
  error = function(error) {
    cat(sprintf("ERROR: %s\n", conditionMessage(error)))
    quit(status = 1)
  }
)
