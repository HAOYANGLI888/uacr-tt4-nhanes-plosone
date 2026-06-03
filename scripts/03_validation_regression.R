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
  log_file <- file.path(log_dir, "03_validation_regression.log")
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

as_numeric_if_present <- function(data, variables) {
  for (variable in intersect(variables, names(data))) {
    data[[variable]] <- suppressWarnings(as.numeric(data[[variable]]))
  }
  data
}

as_factor_if_present <- function(data, variables) {
  for (variable in intersect(variables, names(data))) {
    data[[variable]] <- factor(data[[variable]])
  }
  data
}

prepare_validation <- function(data, log) {
  numeric_vars <- c(
    "SEQN", "AGE", "PIR", "BMI", "UACR", "LOG_UACR", "TT4", "TSH", "TGAB",
    "TPOAB", "EGFR", "WTPFEX6", "SDPPSU6", "SDPSTRA6"
  )
  factor_vars <- c("SEX", "RACE", "EDUCATION", "SMOKE", "DRINK", "DIABETES", "HYPERTENSION")
  data <- as_numeric_if_present(data, numeric_vars)
  data <- as_factor_if_present(data, factor_vars)

  if (!"UACR" %in% names(data) && "UACR_MG_G" %in% names(data)) {
    data$UACR <- suppressWarnings(as.numeric(data$UACR_MG_G))
  }
  if (!"LOG_UACR" %in% names(data)) {
    data$LOG_UACR <- ifelse(data$UACR > 0, log(data$UACR), NA_real_)
  }
  if ("UACR_QUARTILE" %in% names(data)) {
    data$UACR_QUARTILE <- factor(data$UACR_QUARTILE, levels = c("Q1", "Q2", "Q3", "Q4"))
  } else {
    breaks <- unique(stats::quantile(data$UACR, probs = seq(0, 1, 0.25), na.rm = TRUE))
    if (length(breaks) == 5) {
      data$UACR_QUARTILE <- cut(data$UACR, breaks = breaks, include.lowest = TRUE, labels = c("Q1", "Q2", "Q3", "Q4"))
    } else {
      data$UACR_QUARTILE <- factor(rep(NA_character_, nrow(data)), levels = c("Q1", "Q2", "Q3", "Q4"))
      log("WARN", "Validation UACR quartiles unavailable because quantile breaks are not unique")
    }
  }
  if ("UACR_CLINICAL_CATEGORY" %in% names(data)) {
    data$UACR_CLINICAL_CATEGORY <- factor(data$UACR_CLINICAL_CATEGORY, levels = c("<30", "30-300", ">=300"))
  } else {
    data$UACR_CLINICAL_CATEGORY <- cut(data$UACR, breaks = c(-Inf, 30, 300, Inf), right = FALSE, labels = c("<30", "30-300", ">=300"))
  }
  data$UACR_QUARTILE_SCORE <- as.numeric(factor(data$UACR_QUARTILE, levels = c("Q1", "Q2", "Q3", "Q4")))
  data$UACR_CLINICAL_SCORE <- as.numeric(factor(data$UACR_CLINICAL_CATEGORY, levels = c("<30", "30-300", ">=300")))

  if ("EGFR" %in% names(data) && any(!is.na(data$EGFR))) {
    log("INFO", sprintf("Validation eGFR available; Model 3 will adjust for eGFR (nonmissing n=%s)", sum(!is.na(data$EGFR))))
  } else {
    log("WARN", "Validation eGFR unavailable; Model 3 will not adjust for eGFR")
  }
  data
}

make_design <- function(data, log) {
  required <- c("WTPFEX6", "SDPPSU6", "SDPSTRA6")
  missing <- setdiff(required, names(data))
  if (length(missing) > 0) {
    stop(sprintf("Missing NHANES III survey design variables: %s", paste(missing, collapse = ", ")), call. = FALSE)
  }
  design_data <- data[
    !is.na(data$WTPFEX6) & data$WTPFEX6 > 0 &
      !is.na(data$SDPPSU6) & !is.na(data$SDPSTRA6),
    ,
    drop = FALSE
  ]
  log("INFO", sprintf("Validation survey design rows: %s", nrow(design_data)))
  survey::svydesign(
    ids = ~SDPPSU6,
    strata = ~SDPSTRA6,
    weights = ~WTPFEX6,
    nest = TRUE,
    data = droplevels(design_data)
  )
}

requested_covariates <- function(model_name, data) {
  if (model_name == "Model 1") {
    return(character())
  }
  model2 <- c("AGE", "SEX", "RACE")
  if (model_name == "Model 2") {
    return(model2)
  }
  model3 <- c(model2, "EDUCATION", "PIR", "BMI", "SMOKE", "DRINK", "DIABETES", "HYPERTENSION")
  if ("EGFR" %in% names(data) && any(!is.na(data$EGFR))) {
    model3 <- c(model3, "EGFR")
  }
  model3
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

usable_covariates <- function(data, requested) {
  present <- requested[requested %in% names(data)]
  used <- present[vapply(present, function(variable) has_variation(data[[variable]]), logical(1))]
  list(used = used, missing = setdiff(requested, used))
}

formula_for <- function(outcome, exposure, covariates) {
  stats::as.formula(paste(outcome, "~", paste(c(exposure, covariates), collapse = " + ")))
}

safe_svyglm <- function(formula, design, log, context) {
  tryCatch(
    survey::svyglm(formula, design = design),
    error = function(e) {
      log("WARN", sprintf("Model failed for %s: %s", context, conditionMessage(e)))
      NULL
    }
  )
}

complete_case_info <- function(data, variables) {
  variables <- variables[variables %in% names(data)]
  if (length(variables) == 0) {
    return(list(mask = rep(FALSE, nrow(data)), n = 0L, dropped = nrow(data), weighted = NA_real_))
  }
  mask <- stats::complete.cases(data[, variables, drop = FALSE])
  weighted <- if ("WTPFEX6" %in% names(data)) sum(data$WTPFEX6[mask], na.rm = TRUE) else NA_real_
  list(mask = mask, n = as.integer(sum(mask)), dropped = as.integer(nrow(data) - sum(mask)), weighted = weighted)
}

trend_p_value <- function(outcome, score_variable, covariates, design, log, context) {
  fit <- safe_svyglm(formula_for(outcome, score_variable, covariates), design, log, paste0(context, " trend"))
  if (is.null(fit)) {
    return(NA_real_)
  }
  coefficients <- summary(fit)$coefficients
  if (!score_variable %in% rownames(coefficients)) {
    return(NA_real_)
  }
  as.numeric(coefficients[score_variable, "Pr(>|t|)"])
}

direction_from_beta <- function(beta) {
  ifelse(is.na(beta), NA_character_, ifelse(beta > 0, "positive", ifelse(beta < 0, "negative", "null")))
}

extract_rows <- function(
    fit,
    pattern,
    exposure_type,
    model_name,
    requested_covs,
    used_covs,
    missing_covs,
    sample_info,
    trend_p,
    note) {
  if (is.null(fit)) {
    return(data.frame())
  }
  coefficients <- summary(fit)$coefficients
  wanted <- grep(pattern, rownames(coefficients), value = TRUE)
  if (length(wanted) == 0) {
    return(data.frame())
  }
  rows <- lapply(wanted, function(term) {
    beta <- as.numeric(coefficients[term, "Estimate"])
    se <- as.numeric(coefficients[term, "Std. Error"])
    data.frame(
      cohort = "validation",
      outcome = "TT4",
      outcome_role = "primary_validation",
      exposure_type = exposure_type,
      contrast = term,
      model = model_name,
      beta = beta,
      ci_low = beta - 1.96 * se,
      ci_high = beta + 1.96 * se,
      p_value = as.numeric(coefficients[term, "Pr(>|t|)"]),
      p_fdr = NA_real_,
      p_trend = trend_p,
      n = sample_info$n,
      n_model_unweighted = sample_info$n,
      n_missing_dropped = sample_info$dropped,
      weighted_population_estimate = sample_info$weighted,
      direction = direction_from_beta(beta),
      covariates_requested = paste(requested_covs, collapse = " + "),
      covariates_used = paste(used_covs, collapse = " + "),
      covariates_missing = paste(missing_covs, collapse = " + "),
      egfr_adjusted = "EGFR" %in% used_covs,
      uic_adjusted = FALSE,
      note = note
    )
  })
  do.call(rbind, rows)
}

fit_one <- function(design, data, exposure_type, model_name, log) {
  exposure_map <- list(
    "log_UACR" = list(variable = "LOG_UACR", pattern = "^LOG_UACR$", trend = NA_character_),
    "UACR quartile" = list(variable = "UACR_QUARTILE", pattern = "^UACR_QUARTILE", trend = "UACR_QUARTILE_SCORE"),
    "UACR clinical category" = list(variable = "UACR_CLINICAL_CATEGORY", pattern = "^UACR_CLINICAL_CATEGORY", trend = "UACR_CLINICAL_SCORE")
  )
  spec <- exposure_map[[exposure_type]]
  requested <- requested_covariates(model_name, data)
  covs <- usable_covariates(data, requested)
  sample_info <- complete_case_info(data, c("TT4", spec$variable, covs$used))
  note <- if ("EGFR" %in% requested && "EGFR" %in% covs$used) {
    "NHANES III Model 3 adjusted for eGFR; UIC was not adjusted because it is not used for validation."
  } else if ("EGFR" %in% requested) {
    "NHANES III Model 3 requested eGFR, but eGFR was unavailable in this model; UIC was not adjusted."
  } else {
    "NHANES III validation model; UIC was not adjusted."
  }
  fit <- safe_svyglm(
    formula_for("TT4", spec$variable, covs$used),
    design,
    log,
    paste("validation TT4", exposure_type, model_name)
  )
  trend <- NA_real_
  if (!is.na(spec$trend)) {
    trend <- trend_p_value("TT4", spec$trend, covs$used, design, log, paste("validation TT4", exposure_type, model_name))
  }
  extract_rows(fit, spec$pattern, exposure_type, model_name, requested, covs$used, covs$missing, sample_info, trend, note)
}

add_fdr <- function(results) {
  if (nrow(results) == 0) {
    return(results)
  }
  ok <- !is.na(results$p_value)
  results$p_fdr[ok] <- stats::p.adjust(results$p_value[ok], method = "fdr")
  results
}

discovery_tt4_reference <- function(root) {
  path <- file.path(root, "outputs", "tables", "Table2_discovery_main_results.csv")
  if (!file.exists(path)) {
    return(NULL)
  }
  data <- utils::read.csv(path, check.names = FALSE)
  row <- data[
    data$cohort == "discovery" &
      data$outcome == "TT4" &
      data$model == "Model 3" &
      data$exposure_type == "log_UACR" &
      data$contrast == "LOG_UACR",
    ,
    drop = FALSE
  ]
  if (nrow(row) == 0) {
    return(NULL)
  }
  row[1, , drop = FALSE]
}

replication_summary <- function(validation_results, discovery_ref) {
  validation <- validation_results[
    validation_results$outcome == "TT4" &
      validation_results$model == "Model 3" &
      validation_results$exposure_type == "log_UACR" &
      validation_results$contrast == "LOG_UACR",
    ,
    drop = FALSE
  ]
  clinical <- validation_results[
    validation_results$outcome == "TT4" &
      validation_results$model == "Model 3" &
      validation_results$exposure_type == "UACR clinical category",
    ,
    drop = FALSE
  ]

  discovery_beta <- if (!is.null(discovery_ref)) discovery_ref$beta[1] else NA_real_
  discovery_p <- if (!is.null(discovery_ref)) discovery_ref$p_value[1] else NA_real_
  discovery_fdr <- if (!is.null(discovery_ref)) discovery_ref$p_fdr[1] else NA_real_
  validation_beta <- if (nrow(validation) > 0) validation$beta[1] else NA_real_
  validation_p <- if (nrow(validation) > 0) validation$p_value[1] else NA_real_
  validation_fdr <- if (nrow(validation) > 0) validation$p_fdr[1] else NA_real_
  clinical_trend <- if (nrow(clinical) > 0) clinical$p_trend[1] else NA_real_
  high_clinical <- clinical[grepl(">=300", clinical$contrast, fixed = TRUE), , drop = FALSE]
  clinical_supports_trend <- !is.na(clinical_trend) && clinical_trend < 0.05 &&
    nrow(high_clinical) > 0 && high_clinical$beta[1] > 0

  same_direction <- ifelse(
    is.na(discovery_beta) | is.na(validation_beta),
    NA,
    sign(discovery_beta) == sign(validation_beta)
  )
  data.frame(
    outcome = "TT4",
    discovery_beta = discovery_beta,
    discovery_p = discovery_p,
    discovery_fdr = discovery_fdr,
    validation_beta = validation_beta,
    validation_p = validation_p,
    validation_fdr = validation_fdr,
    validation_direction = direction_from_beta(validation_beta),
    validation_p_lt_0_05 = !is.na(validation_p) && validation_p < 0.05,
    directionally_consistent = same_direction,
    clinical_category_p_trend = clinical_trend,
    clinical_category_supports_positive_trend = clinical_supports_trend,
    replication_status = ifelse(
      isTRUE(same_direction) && !is.na(validation_p) && validation_p < 0.05,
      "replicated",
      ifelse(isTRUE(same_direction), "directionally_consistent_only", "not_replicated")
    ),
    note = "Validation primary conclusion is restricted to TT4. TGAb/TPOAb are exploratory availability markers only."
  )
}

format_num <- function(x, digits = 3) {
  ifelse(is.na(x), "NA", formatC(x, digits = digits, format = "f"))
}

format_p <- function(x) {
  ifelse(is.na(x), "NA", ifelse(x < 0.001, formatC(x, digits = 2, format = "e"), formatC(x, digits = 3, format = "f")))
}

markdown_table <- function(rows) {
  lines <- c(
    "| Exposure | Contrast | Model | Beta (95% CI) | P | FDR | P trend | n | Direction |",
    "|---|---|---|---:|---:|---:|---:|---:|---|"
  )
  for (i in seq_len(nrow(rows))) {
    lines <- c(lines, sprintf(
      "| %s | %s | %s | %s (%s to %s) | %s | %s | %s | %s | %s |",
      rows$exposure_type[i],
      rows$contrast[i],
      rows$model[i],
      format_num(rows$beta[i]),
      format_num(rows$ci_low[i]),
      format_num(rows$ci_high[i]),
      format_p(rows$p_value[i]),
      format_p(rows$p_fdr[i]),
      format_p(rows$p_trend[i]),
      rows$n_model_unweighted[i],
      rows$direction[i]
    ))
  }
  lines
}

build_report <- function(results, summary, thyroid_available) {
  model3 <- results[results$model == "Model 3", , drop = FALSE]
  log_row <- model3[model3$exposure_type == "log_UACR" & model3$contrast == "LOG_UACR", , drop = FALSE]
  log_sentence <- if (nrow(log_row) > 0) {
    sprintf(
      "LOG_UACR -> TT4 in NHANES III Model 3 was %s (beta=%s, 95%% CI %s to %s, P=%s).",
      log_row$direction[1],
      format_num(log_row$beta[1]),
      format_num(log_row$ci_low[1]),
      format_num(log_row$ci_high[1]),
      format_p(log_row$p_value[1])
    )
  } else {
    "LOG_UACR -> TT4 in NHANES III Model 3 was not estimable."
  }

  available_lines <- if (nrow(thyroid_available) > 0) {
    apply(thyroid_available, 1, function(row) {
      sprintf("- %s: available=%s, nonmissing n=%s", row[["indicator"]], row[["available"]], row[["nonmissing_n"]])
    })
  } else {
    "- Exploratory thyroid availability table was unavailable."
  }

  c(
    "# NHANES III TT4 validation summary",
    "",
    "Primary validation outcome: TT4.",
    "",
    "TGAb and TPOAb are not used as validation primary outcomes in this report; they are treated only as exploratory availability markers.",
    "",
    "## Replication judgement",
    sprintf("- %s", log_sentence),
    sprintf("- Directionally consistent with discovery: %s.", summary$directionally_consistent[1]),
    sprintf("- Validation P < 0.05: %s.", summary$validation_p_lt_0_05[1]),
    sprintf("- UACR clinical category supports positive trend: %s.", summary$clinical_category_supports_positive_trend[1]),
    sprintf("- Replication status: %s.", summary$replication_status[1]),
    "",
    "## Model 3 validation results",
    markdown_table(model3),
    "",
    "## Exploratory thyroid marker availability",
    available_lines,
    "",
    "## Notes",
    "- Model 3 adjusts for age, sex, race, education, PIR, BMI, smoking, drinking, diabetes, hypertension, and eGFR when available.",
    "- NHANES III validation models do not adjust for UIC.",
    "- Survey design uses WTPFEX6, SDPPSU6, and SDPSTRA6."
  )
}

main <- function() {
  root <- find_project_root()
  log <- init_logger(root)
  if (!requireNamespace("survey", quietly = TRUE)) {
    stop("R package 'survey' is required.", call. = FALSE)
  }
  options(survey.lonely.psu = "adjust")

  validation <- prepare_validation(
    read_csv_upper(file.path(root, "data", "processed", "validation_nhanes3.csv"), log, "validation_nhanes3.csv"),
    log
  )
  design <- make_design(validation, log)
  design_data <- design$variables

  results <- list()
  for (exposure in c("log_UACR", "UACR quartile", "UACR clinical category")) {
    for (model_name in c("Model 1", "Model 2", "Model 3")) {
      rows <- fit_one(design, design_data, exposure, model_name, log)
      if (nrow(rows) > 0) {
        results[[length(results) + 1]] <- rows
      }
    }
  }
  validation_results <- if (length(results) == 0) data.frame() else add_fdr(do.call(rbind, results))
  discovery_ref <- discovery_tt4_reference(root)
  summary <- replication_summary(validation_results, discovery_ref)

  thyroid_path <- file.path(root, "outputs", "tables", "validation_available_thyroid_indicators.csv")
  thyroid_available <- if (file.exists(thyroid_path)) utils::read.csv(thyroid_path, check.names = FALSE) else data.frame()

  table_path <- file.path(root, "outputs", "tables", "Table3_validation_results.csv")
  summary_path <- file.path(root, "outputs", "tables", "replication_summary.csv")
  report_path <- file.path(root, "outputs", "reports", "validation_TT4_summary.md")

  write_csv_safe(validation_results, table_path)
  write_csv_safe(summary, summary_path)
  write_lines_safe(build_report(validation_results, summary, thyroid_available), report_path)

  log("INFO", sprintf("Wrote %s validation result rows to %s", nrow(validation_results), table_path))
  log("INFO", sprintf("Wrote replication summary to %s", summary_path))
  log("INFO", sprintf("Wrote validation TT4 report to %s", report_path))
  log("INFO", sprintf("TT4 replication status: %s", summary$replication_status[1]))
}

main()
