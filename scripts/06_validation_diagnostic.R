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
  log_dir <- file.path(root, "outputs", "logs")
  dir.create(log_dir, recursive = TRUE, showWarnings = FALSE)
  log_file <- file.path(log_dir, "06_validation_diagnostic.log")
  if (file.exists(log_file)) {
    file.remove(log_file)
  }

  logger <- function(level, message) {
    line <- sprintf("%s | %s | %s", format(Sys.time(), "%Y-%m-%d %H:%M:%S"), level, message)
    cat(line, "\n")
    cat(line, "\n", file = log_file, append = TRUE)
  }
  logger("INFO", sprintf("Logging to %s", log_file))
  logger
}

write_csv_safe <- function(x, path) {
  dir.create(dirname(path), recursive = TRUE, showWarnings = FALSE)
  utils::write.csv(x, path, row.names = FALSE, na = "")
}

write_lines_safe <- function(lines, path) {
  dir.create(dirname(path), recursive = TRUE, showWarnings = FALSE)
  writeLines(lines, con = path, useBytes = TRUE)
}

read_csv_upper <- function(path, log, label) {
  if (!file.exists(path)) {
    stop(sprintf("%s not found: %s", label, path), call. = FALSE)
  }
  data <- utils::read.csv(path, check.names = FALSE)
  names(data) <- toupper(names(data))
  log("INFO", sprintf("Loaded %s: %s rows x %s columns", label, nrow(data), ncol(data)))
  data
}

coalesce_col <- function(data, candidates) {
  candidates <- candidates[candidates %in% names(data)]
  if (length(candidates) == 0) {
    return(rep(NA, nrow(data)))
  }
  out <- data[[candidates[1]]]
  if (length(candidates) > 1) {
    for (candidate in candidates[-1]) {
      out <- ifelse(is.na(out) | out == "", data[[candidate]], out)
    }
  }
  out
}

as_numeric_vec <- function(x) {
  suppressWarnings(as.numeric(x))
}

normalize_cohort <- function(data, cohort, log) {
  out <- data.frame(
    SEQN = coalesce_col(data, c("SEQN")),
    COHORT = cohort,
    AGE = as_numeric_vec(coalesce_col(data, c("AGE", "AGE_YEARS"))),
    SEX = coalesce_col(data, c("SEX")),
    RACE = coalesce_col(data, c("RACE", "RACE_ETHNICITY")),
    EDUCATION = coalesce_col(data, c("EDUCATION")),
    PIR = as_numeric_vec(coalesce_col(data, c("PIR"))),
    BMI = as_numeric_vec(coalesce_col(data, c("BMI"))),
    SMOKE = coalesce_col(data, c("SMOKE", "SMOKING_STATUS")),
    DRINK = coalesce_col(data, c("DRINK", "ALCOHOL_STATUS")),
    DIABETES = coalesce_col(data, c("DIABETES", "DIABETES_STATUS")),
    HYPERTENSION = coalesce_col(data, c("HYPERTENSION", "HYPERTENSION_STATUS")),
    EGFR = as_numeric_vec(coalesce_col(data, c("EGFR", "EGFR_CKD_EPI_2021"))),
    TT4 = as_numeric_vec(coalesce_col(data, c("TT4"))),
    UACR = as_numeric_vec(coalesce_col(data, c("UACR", "UACR_MG_G"))),
    LOG_UACR = as_numeric_vec(coalesce_col(data, c("LOG_UACR"))),
    UACR_CLINICAL_CATEGORY = coalesce_col(data, c("UACR_CLINICAL_CATEGORY")),
    WEIGHT = as_numeric_vec(if (cohort == "discovery") coalesce_col(data, c("ANALYTIC_WT6YR", "WTSA6YR")) else coalesce_col(data, c("WTPFEX6"))),
    PSU = as_numeric_vec(if (cohort == "discovery") coalesce_col(data, c("SDMVPSU")) else coalesce_col(data, c("SDPPSU6"))),
    STRATA = as_numeric_vec(if (cohort == "discovery") coalesce_col(data, c("SDMVSTRA")) else coalesce_col(data, c("SDPSTRA6"))),
    stringsAsFactors = FALSE
  )

  if (all(is.na(out$LOG_UACR)) && any(out$UACR > 0, na.rm = TRUE)) {
    out$LOG_UACR <- ifelse(out$UACR > 0, log(out$UACR), NA_real_)
  }

  out$SEX <- factor(out$SEX)
  out$RACE <- factor(out$RACE)
  out$EDUCATION <- factor(out$EDUCATION)
  out$SMOKE <- factor(out$SMOKE)
  out$DRINK <- factor(out$DRINK)
  out$DIABETES <- factor(out$DIABETES)
  out$HYPERTENSION <- factor(out$HYPERTENSION)
  out$UACR_CLINICAL_CATEGORY <- factor(out$UACR_CLINICAL_CATEGORY, levels = c("<30", "30-300", ">=300"))
  out$UACR_CLINICAL_SCORE <- as.numeric(factor(out$UACR_CLINICAL_CATEGORY, levels = c("<30", "30-300", ">=300")))

  out <- out[!is.na(out$WEIGHT) & out$WEIGHT > 0 & !is.na(out$PSU) & !is.na(out$STRATA), , drop = FALSE]
  log("INFO", sprintf("%s normalized analysis rows with survey design variables: %s", cohort, nrow(out)))
  out
}

make_design <- function(data) {
  survey::svydesign(
    ids = ~PSU,
    strata = ~STRATA,
    weights = ~WEIGHT,
    nest = TRUE,
    data = droplevels(data)
  )
}

make_combined_design <- function(data) {
  data$COMBINED_STRATA <- interaction(data$COHORT, data$STRATA, drop = TRUE)
  data$COMBINED_PSU <- interaction(data$COHORT, data$STRATA, data$PSU, drop = TRUE)
  survey::svydesign(
    ids = ~COMBINED_PSU,
    strata = ~COMBINED_STRATA,
    weights = ~WEIGHT,
    nest = TRUE,
    data = droplevels(data)
  )
}

svy_mean_se <- function(design, variable) {
  result <- tryCatch(survey::svymean(stats::as.formula(paste0("~", variable)), design, na.rm = TRUE), error = function(e) NULL)
  if (is.null(result)) {
    return(c(mean = NA_real_, se = NA_real_))
  }
  c(mean = as.numeric(stats::coef(result)[1]), se = as.numeric(survey::SE(result)[1]))
}

svy_quantile_values <- function(design, variable, probs = c(0.25, 0.5, 0.75)) {
  result <- tryCatch(
    survey::svyquantile(stats::as.formula(paste0("~", variable)), design, quantiles = probs, na.rm = TRUE, ci = FALSE),
    error = function(e) NULL
  )
  if (is.null(result)) {
    return(rep(NA_real_, length(probs)))
  }
  values <- as.numeric(unlist(result, use.names = FALSE))
  if (length(values) < length(probs)) {
    values <- c(values, rep(NA_real_, length(probs) - length(values)))
  }
  values[seq_along(probs)]
}

diagnostic_distribution <- function(data, design, cohort) {
  rows <- list()
  add_distribution <- function(variable, unit, source_variable) {
    x <- data[[variable]]
    mean_se <- svy_mean_se(design, variable)
    q <- svy_quantile_values(design, variable)
    iqr_unweighted <- stats::quantile(x, probs = c(0.25, 0.75), na.rm = TRUE, type = 7)
    iqr_width <- as.numeric(iqr_unweighted[2] - iqr_unweighted[1])
    extreme_count <- if (variable == "TT4" && !is.na(iqr_width) && iqr_width > 0) {
      sum(x < (iqr_unweighted[1] - 3 * iqr_width) | x > (iqr_unweighted[2] + 3 * iqr_width), na.rm = TRUE)
    } else {
      NA_integer_
    }

    rows[[length(rows) + 1]] <<- data.frame(
      cohort = cohort,
      row_type = "distribution",
      variable = variable,
      source_variable = source_variable,
      unit = unit,
      category = "",
      n_unweighted = nrow(data),
      n_nonmissing = sum(!is.na(x)),
      missing_n = sum(is.na(x)),
      min = suppressWarnings(min(x, na.rm = TRUE)),
      max = suppressWarnings(max(x, na.rm = TRUE)),
      weighted_mean = mean_se[["mean"]],
      weighted_se = mean_se[["se"]],
      weighted_median = q[2],
      weighted_q1 = q[1],
      weighted_q3 = q[3],
      invalid_uacr_le_zero = if (variable == "UACR") sum(!is.na(x) & x <= 0) else NA_integer_,
      inf_count = sum(is.infinite(x)),
      nan_count = sum(is.nan(x)),
      tt4_extreme_iqr_count = extreme_count,
      natural_log_max_abs_error = NA_real_,
      weighted_percent = NA_real_,
      stringsAsFactors = FALSE
    )
  }

  add_distribution("TT4", "ug/dL", ifelse(cohort == "discovery", "LBXTT4 / TT4", "T4P / TT4"))
  add_distribution("UACR", "mg/g", "albumin-to-creatinine ratio")

  log_error <- abs(log(data$UACR) - data$LOG_UACR)
  rows[[length(rows) + 1]] <- data.frame(
    cohort = cohort,
    row_type = "qc",
    variable = "LOG_UACR",
    source_variable = "log(UACR)",
    unit = "natural log mg/g",
    category = "",
    n_unweighted = nrow(data),
    n_nonmissing = sum(!is.na(data$LOG_UACR)),
    missing_n = sum(is.na(data$LOG_UACR)),
    min = suppressWarnings(min(data$LOG_UACR, na.rm = TRUE)),
    max = suppressWarnings(max(data$LOG_UACR, na.rm = TRUE)),
    weighted_mean = NA_real_,
    weighted_se = NA_real_,
    weighted_median = NA_real_,
    weighted_q1 = NA_real_,
    weighted_q3 = NA_real_,
    invalid_uacr_le_zero = sum(!is.na(data$UACR) & data$UACR <= 0),
    inf_count = sum(is.infinite(data$LOG_UACR)),
    nan_count = sum(is.nan(data$LOG_UACR)),
    tt4_extreme_iqr_count = NA_integer_,
    natural_log_max_abs_error = suppressWarnings(max(log_error[is.finite(log_error)], na.rm = TRUE)),
    weighted_percent = NA_real_,
    stringsAsFactors = FALSE
  )

  table <- tryCatch(survey::svytable(~UACR_CLINICAL_CATEGORY, design), error = function(e) NULL)
  if (!is.null(table)) {
    percentages <- prop.table(table) * 100
    for (category in names(percentages)) {
      rows[[length(rows) + 1]] <- data.frame(
        cohort = cohort,
        row_type = "weighted_clinical_category_percent",
        variable = "UACR_CLINICAL_CATEGORY",
        source_variable = "UACR clinical category",
        unit = "%",
        category = category,
        n_unweighted = nrow(data),
        n_nonmissing = sum(!is.na(data$UACR_CLINICAL_CATEGORY)),
        missing_n = sum(is.na(data$UACR_CLINICAL_CATEGORY)),
        min = NA_real_,
        max = NA_real_,
        weighted_mean = NA_real_,
        weighted_se = NA_real_,
        weighted_median = NA_real_,
        weighted_q1 = NA_real_,
        weighted_q3 = NA_real_,
        invalid_uacr_le_zero = NA_integer_,
        inf_count = NA_integer_,
        nan_count = NA_integer_,
        tt4_extreme_iqr_count = NA_integer_,
        natural_log_max_abs_error = NA_real_,
        weighted_percent = as.numeric(percentages[[category]]),
        stringsAsFactors = FALSE
      )
    }
  }

  do.call(rbind, rows)
}

has_variation <- function(x) {
  observed <- x[!is.na(x)]
  if (length(observed) == 0) {
    return(FALSE)
  }
  if (is.factor(observed) || is.character(observed)) {
    return(length(unique(as.character(observed))) >= 2)
  }
  length(unique(observed)) >= 2
}

model_covariates <- function(model_name) {
  h1 <- c("AGE", "SEX", "RACE")
  h2 <- c(h1, "EDUCATION", "PIR", "BMI", "SMOKE", "DRINK", "DIABETES", "HYPERTENSION")
  if (model_name == "H1") {
    return(h1)
  }
  if (model_name == "H2") {
    return(h2)
  }
  c(h2, "EGFR")
}

usable_covariates <- function(data, requested) {
  present <- requested[requested %in% names(data)]
  used <- present[vapply(present, function(variable) has_variation(data[[variable]]), logical(1))]
  list(used = used, missing = setdiff(requested, used))
}

formula_for <- function(outcome, exposure, covariates) {
  stats::as.formula(paste(outcome, "~", paste(c(exposure, covariates), collapse = " + ")))
}

direction_from_beta <- function(beta) {
  ifelse(is.na(beta), NA_character_, ifelse(beta > 0, "positive", ifelse(beta < 0, "negative", "null")))
}

fit_svyglm_safe <- function(formula, design, log, context) {
  tryCatch(
    survey::svyglm(formula, design = design),
    error = function(e) {
      log("WARN", sprintf("Model failed for %s: %s", context, conditionMessage(e)))
      NULL
    }
  )
}

analysis_design <- function(data, variables) {
  variables <- variables[variables %in% names(data)]
  mask <- stats::complete.cases(data[, variables, drop = FALSE])
  subset <- data[mask, , drop = FALSE]
  list(data = subset, n = nrow(subset), design = make_design(subset))
}

weighted_pair_summary <- function(design) {
  tt4 <- svy_mean_se(design, "TT4")
  uacr <- svy_quantile_values(design, "UACR")
  c(weighted_tt4_mean = tt4[["mean"]], weighted_tt4_se = tt4[["se"]], weighted_uacr_median = uacr[2])
}

extract_exposure_term <- function(fit, term, cohort, model_name, n_model, pair_summary, used_covs, missing_covs, p_trend = NA_real_) {
  if (is.null(fit)) {
    return(data.frame())
  }
  coefficients <- summary(fit)$coefficients
  if (!term %in% rownames(coefficients)) {
    return(data.frame())
  }
  beta <- as.numeric(coefficients[term, "Estimate"])
  se <- as.numeric(coefficients[term, "Std. Error"])
  data.frame(
    analysis_type = "LOG_UACR_TO_TT4",
    cohort = cohort,
    model = model_name,
    exposure = "LOG_UACR",
    contrast = term,
    beta = beta,
    ci_low = beta - 1.96 * se,
    ci_high = beta + 1.96 * se,
    p_value = as.numeric(coefficients[term, "Pr(>|t|)"]),
    p_fdr = NA_real_,
    n_model = n_model,
    weighted_tt4_mean = pair_summary[["weighted_tt4_mean"]],
    weighted_tt4_se = pair_summary[["weighted_tt4_se"]],
    weighted_uacr_median = pair_summary[["weighted_uacr_median"]],
    direction = direction_from_beta(beta),
    p_trend = p_trend,
    covariates_used = paste(used_covs, collapse = " + "),
    covariates_missing = paste(missing_covs, collapse = " + "),
    note = ifelse(cohort == "discovery", "Harmonized discovery model excludes UIC for NHANES III comparability.", "NHANES III model excludes UIC; H3 includes eGFR when available."),
    stringsAsFactors = FALSE
  )
}

fit_log_model <- function(data, cohort, model_name, log) {
  requested <- model_covariates(model_name)
  covs <- usable_covariates(data, requested)
  variables <- c("TT4", "LOG_UACR", "UACR", covs$used)
  ad <- analysis_design(data, variables)
  fit <- fit_svyglm_safe(formula_for("TT4", "LOG_UACR", covs$used), ad$design, log, paste(cohort, model_name, "LOG_UACR"))
  pair_summary <- weighted_pair_summary(ad$design)
  extract_exposure_term(fit, "LOG_UACR", cohort, model_name, ad$n, pair_summary, covs$used, covs$missing)
}

fit_clinical_trend <- function(data, cohort, model_name, log) {
  requested <- model_covariates(model_name)
  covs <- usable_covariates(data, requested)
  variables <- c("TT4", "UACR_CLINICAL_CATEGORY", "UACR_CLINICAL_SCORE", "UACR", covs$used)
  ad <- analysis_design(data, variables)
  if (!has_variation(ad$data$UACR_CLINICAL_CATEGORY)) {
    return(data.frame())
  }

  fit_cat <- fit_svyglm_safe(formula_for("TT4", "UACR_CLINICAL_CATEGORY", covs$used), ad$design, log, paste(cohort, model_name, "clinical category"))
  fit_trend <- fit_svyglm_safe(formula_for("TT4", "UACR_CLINICAL_SCORE", covs$used), ad$design, log, paste(cohort, model_name, "clinical trend"))
  coefficients <- if (is.null(fit_trend)) NULL else summary(fit_trend)$coefficients
  p_trend <- if (!is.null(coefficients) && "UACR_CLINICAL_SCORE" %in% rownames(coefficients)) {
    as.numeric(coefficients["UACR_CLINICAL_SCORE", "Pr(>|t|)"])
  } else {
    NA_real_
  }
  pair_summary <- weighted_pair_summary(ad$design)
  if (is.null(fit_cat)) {
    return(data.frame())
  }
  cat_coef <- summary(fit_cat)$coefficients
  wanted <- grep("^UACR_CLINICAL_CATEGORY", rownames(cat_coef), value = TRUE)
  rows <- lapply(wanted, function(term) {
    beta <- as.numeric(cat_coef[term, "Estimate"])
    se <- as.numeric(cat_coef[term, "Std. Error"])
    data.frame(
      analysis_type = "UACR_CLINICAL_TREND_TT4",
      cohort = cohort,
      model = model_name,
      exposure = "UACR_CLINICAL_CATEGORY",
      contrast = term,
      beta = beta,
      ci_low = beta - 1.96 * se,
      ci_high = beta + 1.96 * se,
      p_value = as.numeric(cat_coef[term, "Pr(>|t|)"]),
      p_fdr = NA_real_,
      n_model = ad$n,
      weighted_tt4_mean = pair_summary[["weighted_tt4_mean"]],
      weighted_tt4_se = pair_summary[["weighted_tt4_se"]],
      weighted_uacr_median = pair_summary[["weighted_uacr_median"]],
      direction = direction_from_beta(beta),
      p_trend = p_trend,
      covariates_used = paste(covs$used, collapse = " + "),
      covariates_missing = paste(covs$missing, collapse = " + "),
      note = "P for trend estimated with ordinal clinical category score (<30, 30-300, >=300).",
      stringsAsFactors = FALSE
    )
  })
  do.call(rbind, rows)
}

add_harmonized_fdr <- function(results) {
  if (nrow(results) == 0) {
    return(results)
  }
  log_rows <- results$analysis_type == "LOG_UACR_TO_TT4" & !is.na(results$p_value)
  results$p_fdr[log_rows] <- stats::p.adjust(results$p_value[log_rows], method = "fdr")
  clinical_rows <- results$analysis_type == "UACR_CLINICAL_TREND_TT4" & !is.na(results$p_value)
  results$p_fdr[clinical_rows] <- stats::p.adjust(results$p_value[clinical_rows], method = "fdr")
  results
}

interaction_analysis <- function(discovery, validation, log) {
  common <- rbind(discovery, validation)
  common$COHORT <- factor(common$COHORT, levels = c("discovery", "validation"))
  covs <- model_covariates("H3")
  covs <- usable_covariates(common, covs)$used
  variables <- c("TT4", "LOG_UACR", "COHORT", covs)
  mask <- stats::complete.cases(common[, variables, drop = FALSE])
  analysis_data <- common[mask, , drop = FALSE]
  design <- make_combined_design(analysis_data)
  formula <- stats::as.formula(paste("TT4 ~ LOG_UACR * COHORT +", paste(covs, collapse = " + ")))
  fit <- fit_svyglm_safe(formula, design, log, "cohort interaction TT4 ~ LOG_UACR * COHORT")
  if (is.null(fit)) {
    return(data.frame(
      outcome = "TT4",
      exposure = "LOG_UACR",
      model = "H3 interaction",
      n_model = nrow(analysis_data),
      interaction_beta = NA_real_,
      interaction_ci_low = NA_real_,
      interaction_ci_high = NA_real_,
      p_for_cohort_interaction = NA_real_,
      covariates_used = paste(covs, collapse = " + "),
      note = "Interaction model failed.",
      stringsAsFactors = FALSE
    ))
  }
  coefficients <- summary(fit)$coefficients
  term <- grep("LOG_UACR:COHORT|COHORT.*:LOG_UACR", rownames(coefficients), value = TRUE)
  if (length(term) == 0) {
    term <- NA_character_
  } else {
    term <- term[1]
  }
  test <- tryCatch(survey::regTermTest(fit, ~LOG_UACR:COHORT), error = function(e) NULL)
  p_interaction <- if (is.null(test)) {
    if (!is.na(term)) as.numeric(coefficients[term, "Pr(>|t|)"]) else NA_real_
  } else {
    as.numeric(test$p[1])
  }
  beta <- if (!is.na(term)) as.numeric(coefficients[term, "Estimate"]) else NA_real_
  se <- if (!is.na(term)) as.numeric(coefficients[term, "Std. Error"]) else NA_real_
  data.frame(
    outcome = "TT4",
    exposure = "LOG_UACR",
    model = "H3 interaction",
    n_model = nrow(analysis_data),
    interaction_term = ifelse(is.na(term), "", term),
    interaction_beta = beta,
    interaction_ci_low = beta - 1.96 * se,
    interaction_ci_high = beta + 1.96 * se,
    p_for_cohort_interaction = p_interaction,
    covariates_used = paste(covs, collapse = " + "),
    note = "Stacked discovery/validation survey design uses cohort-prefixed strata and PSU identifiers.",
    stringsAsFactors = FALSE
  )
}

fmt <- function(x, digits = 3) {
  ifelse(is.na(x), "NA", formatC(x, digits = digits, format = "f"))
}

fmt_p <- function(x) {
  ifelse(is.na(x), "NA", ifelse(x < 0.001, formatC(x, digits = 2, format = "e"), formatC(x, digits = 3, format = "f")))
}

markdown_model_table <- function(rows) {
  lines <- c(
    "| Cohort | Model | Beta (95% CI) | P | FDR | n | Weighted TT4 mean | Weighted UACR median | Direction |",
    "|---|---|---:|---:|---:|---:|---:|---:|---|"
  )
  for (i in seq_len(nrow(rows))) {
    lines <- c(lines, sprintf(
      "| %s | %s | %s (%s to %s) | %s | %s | %s | %s | %s | %s |",
      rows$cohort[i],
      rows$model[i],
      fmt(rows$beta[i]),
      fmt(rows$ci_low[i]),
      fmt(rows$ci_high[i]),
      fmt_p(rows$p_value[i]),
      fmt_p(rows$p_fdr[i]),
      rows$n_model[i],
      fmt(rows$weighted_tt4_mean[i]),
      fmt(rows$weighted_uacr_median[i]),
      rows$direction[i]
    ))
  }
  lines
}

diagnostic_report <- function(distribution) {
  tt4 <- distribution[distribution$row_type == "distribution" & distribution$variable == "TT4", , drop = FALSE]
  uacr <- distribution[distribution$row_type == "distribution" & distribution$variable == "UACR", , drop = FALSE]
  log_qc <- distribution[distribution$row_type == "qc" & distribution$variable == "LOG_UACR", , drop = FALSE]
  pct <- distribution[distribution$row_type == "weighted_clinical_category_percent", , drop = FALSE]

  lines <- c(
    "# Validation diagnostic report",
    "",
    "This report compares NHANES 2007-2012 discovery and NHANES III validation distributions before interpreting replication failure.",
    "",
    "## TT4 Distribution",
    "| Cohort | Unit | Range | Weighted mean (SE) | Weighted median | Weighted IQR | IQR extreme n |",
    "|---|---|---:|---:|---:|---:|---:|"
  )
  for (i in seq_len(nrow(tt4))) {
    lines <- c(lines, sprintf(
      "| %s | %s | %s to %s | %s (%s) | %s | %s to %s | %s |",
      tt4$cohort[i], tt4$unit[i], fmt(tt4$min[i]), fmt(tt4$max[i]),
      fmt(tt4$weighted_mean[i]), fmt(tt4$weighted_se[i]), fmt(tt4$weighted_median[i]),
      fmt(tt4$weighted_q1[i]), fmt(tt4$weighted_q3[i]), tt4$tt4_extreme_iqr_count[i]
    ))
  }

  lines <- c(lines, "", "## UACR Distribution", "| Cohort | Unit | Range | Weighted median | Weighted IQR | UACR <=0 n | Inf n | NaN n |", "|---|---|---:|---:|---:|---:|---:|---:|")
  for (i in seq_len(nrow(uacr))) {
    lines <- c(lines, sprintf(
      "| %s | %s | %s to %s | %s | %s to %s | %s | %s | %s |",
      uacr$cohort[i], uacr$unit[i], fmt(uacr$min[i]), fmt(uacr$max[i]),
      fmt(uacr$weighted_median[i]), fmt(uacr$weighted_q1[i]), fmt(uacr$weighted_q3[i]),
      uacr$invalid_uacr_le_zero[i], uacr$inf_count[i], uacr$nan_count[i]
    ))
  }

  lines <- c(lines, "", "## LOG_UACR Check", "| Cohort | Natural log max absolute error | UACR <=0 n | LOG_UACR Inf n | LOG_UACR NaN n |", "|---|---:|---:|---:|---:|")
  for (i in seq_len(nrow(log_qc))) {
    lines <- c(lines, sprintf(
      "| %s | %s | %s | %s | %s |",
      log_qc$cohort[i], fmt(log_qc$natural_log_max_abs_error[i], 8),
      log_qc$invalid_uacr_le_zero[i], log_qc$inf_count[i], log_qc$nan_count[i]
    ))
  }

  lines <- c(lines, "", "## UACR Clinical Category Weighted Percentage", "| Cohort | Category | Weighted percentage |", "|---|---|---:|")
  for (i in seq_len(nrow(pct))) {
    lines <- c(lines, sprintf("| %s | %s | %s |", pct$cohort[i], pct$category[i], fmt(pct$weighted_percent[i])))
  }

  c(
    lines,
    "",
    "## Unit Notes",
    "- TT4 is treated as ug/dL in both cohorts: discovery uses LBXTT4/TT4 and NHANES III uses T4P/TT4. No SI conversion was applied.",
    "- UACR is treated as mg/g in both cohorts and LOG_UACR is checked against the natural logarithm of UACR.",
    "- TT4 extreme values are flagged using an unweighted Q1 - 3*IQR / Q3 + 3*IQR rule."
  )
}

replication_report <- function(harmonized, interaction) {
  log_rows <- harmonized[harmonized$analysis_type == "LOG_UACR_TO_TT4", , drop = FALSE]
  val <- log_rows[log_rows$cohort == "validation", , drop = FALSE]
  dis <- log_rows[log_rows$cohort == "discovery", , drop = FALSE]

  validation_near_zero <- nrow(val) == 3 && all(abs(val$beta) < 0.02, na.rm = TRUE)
  validation_h2_positive_sig <- any(val$model == "H2" & val$beta > 0 & val$p_value < 0.05, na.rm = TRUE)
  validation_h3_sig <- any(val$model == "H3" & val$beta > 0 & val$p_value < 0.05, na.rm = TRUE)
  egfr_overadjustment <- validation_h2_positive_sig && !validation_h3_sig
  discovery_no_uic_sig <- any(dis$model == "H3" & dis$beta > 0 & dis$p_value < 0.05, na.rm = TRUE)
  validation_any_sig <- any(val$beta > 0 & val$p_value < 0.05, na.rm = TRUE)

  final_status <- if (validation_any_sig) "directionally consistent" else "not replicated"
  explanation <- if (validation_near_zero) {
    "Validation H1/H2/H3 estimates were all close to zero, supporting a conclusion that NHANES III did not statistically reproduce the discovery association."
  } else if (egfr_overadjustment) {
    "Validation became positive and significant before eGFR adjustment but not after eGFR adjustment, suggesting possible eGFR over-adjustment."
  } else if (discovery_no_uic_sig && !validation_any_sig) {
    "Discovery remained significant without UIC adjustment whereas validation remained non-significant, suggesting differences may arise from cohort era, assay methods, or population structure."
  } else {
    "Validation did not provide statistical replication of the discovery association."
  }

  clinical <- harmonized[harmonized$analysis_type == "UACR_CLINICAL_TREND_TT4", , drop = FALSE]
  clinical_h3 <- clinical[clinical$model == "H3", , drop = FALSE]

  c(
    "# Harmonized replication summary",
    "",
    "Primary comparison: LOG_UACR -> TT4 using harmonized covariate adjustment. Discovery H models intentionally do not adjust for UIC to improve comparability with NHANES III.",
    "",
    sprintf("Replication wording status: **%s**.", final_status),
    "",
    sprintf("Diagnostic interpretation: %s", explanation),
    "",
    sprintf("P for cohort interaction: %s.", fmt_p(interaction$p_for_cohort_interaction[1])),
    "",
    "## LOG_UACR -> TT4 Harmonized Models",
    markdown_model_table(log_rows),
    "",
    "## Clinical Category Trend, H3",
    "| Cohort | Contrast | Beta (95% CI) | P | P trend | Direction |",
    "|---|---|---:|---:|---:|---|",
    if (nrow(clinical_h3) == 0) {
      "| NA | NA | NA | NA | NA | NA |"
    } else {
      apply(clinical_h3, 1, function(row) {
        sprintf(
          "| %s | %s | %s (%s to %s) | %s | %s | %s |",
          row[["cohort"]], row[["contrast"]], fmt(as.numeric(row[["beta"]])),
          fmt(as.numeric(row[["ci_low"]])), fmt(as.numeric(row[["ci_high"]])),
          fmt_p(as.numeric(row[["p_value"]])), fmt_p(as.numeric(row[["p_trend"]])),
          row[["direction"]]
        )
      })
    },
    "",
    "## Conclusion Rules Applied",
    sprintf("- Validation H1/H2/H3 all close to zero: %s.", validation_near_zero),
    sprintf("- eGFR over-adjustment pattern observed: %s.", egfr_overadjustment),
    sprintf("- Discovery without UIC significant while validation non-significant: %s.", discovery_no_uic_sig && !validation_any_sig)
  )
}

main <- function() {
  root <- find_project_root()
  log <- init_logger(root)
  if (!requireNamespace("survey", quietly = TRUE)) {
    stop("R package 'survey' is required.", call. = FALSE)
  }
  options(survey.lonely.psu = "adjust")

  discovery_raw <- read_csv_upper(file.path(root, "data", "processed", "discovery_nhanes_2007_2012.csv"), log, "discovery")
  validation_raw <- read_csv_upper(file.path(root, "data", "processed", "validation_nhanes3.csv"), log, "validation")
  discovery <- normalize_cohort(discovery_raw, "discovery", log)
  validation <- normalize_cohort(validation_raw, "validation", log)

  discovery_design <- make_design(discovery)
  validation_design <- make_design(validation)
  distribution <- rbind(
    diagnostic_distribution(discovery, discovery_design, "discovery"),
    diagnostic_distribution(validation, validation_design, "validation")
  )

  harmonized_rows <- list()
  for (cohort_data in list(discovery = discovery, validation = validation)) {
    cohort_name <- names(cohort_data)
  }
  for (cohort_name in c("discovery", "validation")) {
    data <- if (cohort_name == "discovery") discovery else validation
    for (model_name in c("H1", "H2", "H3")) {
      harmonized_rows[[length(harmonized_rows) + 1]] <- fit_log_model(data, cohort_name, model_name, log)
      harmonized_rows[[length(harmonized_rows) + 1]] <- fit_clinical_trend(data, cohort_name, model_name, log)
    }
  }
  harmonized <- do.call(rbind, harmonized_rows)
  harmonized <- add_harmonized_fdr(harmonized)
  interaction <- interaction_analysis(discovery, validation, log)

  distribution_path <- file.path(root, "outputs", "tables", "Table_validation_diagnostic_distribution.csv")
  harmonized_path <- file.path(root, "outputs", "tables", "Table_harmonized_discovery_validation_TT4.csv")
  interaction_path <- file.path(root, "outputs", "tables", "Table_cohort_interaction_TT4.csv")
  diagnostic_report_path <- file.path(root, "outputs", "reports", "validation_diagnostic_report.md")
  replication_report_path <- file.path(root, "outputs", "reports", "harmonized_replication_summary.md")

  write_csv_safe(distribution, distribution_path)
  write_csv_safe(harmonized, harmonized_path)
  write_csv_safe(interaction, interaction_path)
  write_lines_safe(diagnostic_report(distribution), diagnostic_report_path)
  write_lines_safe(replication_report(harmonized, interaction), replication_report_path)

  log("INFO", sprintf("Wrote diagnostic distribution table to %s", distribution_path))
  log("INFO", sprintf("Wrote harmonized TT4 table to %s", harmonized_path))
  log("INFO", sprintf("Wrote cohort interaction table to %s", interaction_path))
  log("INFO", sprintf("Wrote validation diagnostic report to %s", diagnostic_report_path))
  log("INFO", sprintf("Wrote harmonized replication summary to %s", replication_report_path))
  log("INFO", sprintf("P for cohort interaction: %s", fmt_p(interaction$p_for_cohort_interaction[1])))
}

main()
