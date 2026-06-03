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
  log_file <- file.path(log_dir, "05_TT4_robustness.log")
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

read_discovery <- function(root, log) {
  path <- file.path(root, "data", "processed", "discovery_nhanes_2007_2012.csv")
  if (!file.exists(path)) {
    stop(sprintf("Discovery dataset not found: %s", path), call. = FALSE)
  }
  data <- utils::read.csv(path, check.names = FALSE)
  names(data) <- toupper(names(data))
  log("INFO", sprintf("Loaded discovery dataset: %s rows x %s columns", nrow(data), ncol(data)))
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

prepare_discovery <- function(data) {
  aliases <- list(
    AGE_YEARS = "AGE",
    RACE_ETHNICITY = "RACE",
    SMOKING_STATUS = "SMOKE",
    ALCOHOL_STATUS = "DRINK",
    DIABETES_STATUS = "DIABETES",
    HYPERTENSION_STATUS = "HYPERTENSION",
    EGFR_CKD_EPI_2021 = "EGFR",
    UACR_MG_G = "UACR"
  )
  for (target in names(aliases)) {
    source <- aliases[[target]]
    if (!target %in% names(data) && source %in% names(data)) {
      data[[target]] <- data[[source]]
    }
  }

  numeric_vars <- c(
    "SEQN", "AGE", "AGE_YEARS", "PIR", "BMI", "EGFR", "EGFR_CKD_EPI_2021",
    "UIC_UG_L", "UACR", "UACR_MG_G", "LOG_UACR", "TSH", "FT4", "TT4",
    "ANALYTIC_WT6YR", "WTSA6YR", "SDMVPSU", "SDMVSTRA", "DIABETES", "HYPERTENSION"
  )
  data <- as_numeric_if_present(data, numeric_vars)

  if (!"UACR_MG_G" %in% names(data) && "UACR" %in% names(data)) {
    data$UACR_MG_G <- data$UACR
  }
  if (!"LOG_UACR" %in% names(data)) {
    data$LOG_UACR <- ifelse(data$UACR_MG_G > 0, log(data$UACR_MG_G), NA_real_)
  }
  data$LOG2_UACR <- ifelse(data$UACR_MG_G > 0, log2(data$UACR_MG_G), NA_real_)

  factor_vars <- c(
    "SEX", "RACE_ETHNICITY", "EDUCATION", "SMOKING_STATUS", "ALCOHOL_STATUS",
    "DIABETES_STATUS", "HYPERTENSION_STATUS"
  )
  data <- as_factor_if_present(data, factor_vars)
  if ("UACR_QUARTILE" %in% names(data)) {
    data$UACR_QUARTILE <- factor(data$UACR_QUARTILE, levels = c("Q1", "Q2", "Q3", "Q4"))
  }
  if ("UACR_CLINICAL_CATEGORY" %in% names(data)) {
    data$UACR_CLINICAL_CATEGORY <- factor(data$UACR_CLINICAL_CATEGORY, levels = c("<30", "30-300", ">=300"))
  }
  data
}

pick_weight <- function(data, log) {
  candidates <- c("ANALYTIC_WT6YR", "WTSA6YR")
  for (candidate in candidates) {
    if (candidate %in% names(data) && any(!is.na(data[[candidate]]) & data[[candidate]] > 0)) {
      log("INFO", sprintf("Using discovery survey weight: %s", candidate))
      return(candidate)
    }
  }
  stop("No usable discovery survey weight found among ANALYTIC_WT6YR and WTSA6YR.", call. = FALSE)
}

make_design <- function(data, weight, log, label) {
  required <- c(weight, "SDMVPSU", "SDMVSTRA")
  missing <- setdiff(required, names(data))
  if (length(missing) > 0) {
    stop(sprintf("Missing survey design variables for %s: %s", label, paste(missing, collapse = ", ")), call. = FALSE)
  }
  design_data <- data[
    !is.na(data[[weight]]) & data[[weight]] > 0 &
      !is.na(data$SDMVPSU) & !is.na(data$SDMVSTRA),
    ,
    drop = FALSE
  ]
  design_data <- droplevels(design_data)
  log("INFO", sprintf("%s survey design rows: %s", label, nrow(design_data)))
  survey::svydesign(
    ids = ~SDMVPSU,
    strata = ~SDMVSTRA,
    weights = stats::as.formula(paste0("~", weight)),
    nest = TRUE,
    data = design_data
  )
}

requested_covariates <- function() {
  c(
    "AGE_YEARS", "SEX", "RACE_ETHNICITY", "EDUCATION", "PIR", "BMI",
    "SMOKING_STATUS", "ALCOHOL_STATUS", "DIABETES_STATUS", "HYPERTENSION_STATUS",
    "EGFR_CKD_EPI_2021", "UIC_UG_L"
  )
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
  rhs <- c(exposure, covariates)
  stats::as.formula(paste(outcome, "~", paste(rhs, collapse = " + ")))
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

model_sample_n <- function(data, variables) {
  variables <- variables[variables %in% names(data)]
  if (length(variables) == 0) {
    return(0L)
  }
  as.integer(sum(stats::complete.cases(data[, variables, drop = FALSE])))
}

direction_from_beta <- function(beta) {
  ifelse(is.na(beta), NA_character_, ifelse(beta > 0, "positive", ifelse(beta < 0, "negative", "null")))
}

extract_model_rows <- function(
    fit,
    pattern,
    analysis_label,
    sensitivity_filter,
    exposure_definition,
    exposure_variable,
    n_model,
    requested_covs,
    used_covs,
    dropped_covs) {
  empty <- data.frame()
  if (is.null(fit)) {
    return(empty)
  }
  coefficients <- summary(fit)$coefficients
  wanted <- grep(pattern, rownames(coefficients), value = TRUE)
  if (length(wanted) == 0) {
    return(empty)
  }

  rows <- lapply(wanted, function(term) {
    beta <- as.numeric(coefficients[term, "Estimate"])
    se <- as.numeric(coefficients[term, "Std. Error"])
    p_value <- as.numeric(coefficients[term, "Pr(>|t|)"])
    data.frame(
      analysis_type = "survey_model",
      analysis_label = analysis_label,
      sensitivity_filter = sensitivity_filter,
      outcome = "TT4",
      exposure_definition = exposure_definition,
      exposure_variable = exposure_variable,
      contrast = term,
      model = "Model 3",
      beta = beta,
      ci_low = beta - 1.96 * se,
      ci_high = beta + 1.96 * se,
      p_value = p_value,
      p_fdr = NA_real_,
      n_model_unweighted = n_model,
      direction = direction_from_beta(beta),
      covariates_requested = paste(requested_covs, collapse = " + "),
      covariates_used = paste(used_covs, collapse = " + "),
      covariates_dropped = paste(dropped_covs, collapse = " + "),
      rcs_p_overall = NA_real_,
      rcs_p_nonlinearity = NA_real_,
      note = ""
    )
  })
  do.call(rbind, rows)
}

fit_exposure <- function(data, weight, exposure_definition, analysis_label, sensitivity_filter, log) {
  exposure_map <- list(
    LOG_UACR = list(variable = "LOG_UACR", pattern = "^LOG_UACR$"),
    LOG2_UACR = list(variable = "LOG2_UACR", pattern = "^LOG2_UACR$"),
    UACR_QUARTILE = list(variable = "UACR_QUARTILE", pattern = "^UACR_QUARTILE"),
    UACR_CLINICAL_CATEGORY = list(variable = "UACR_CLINICAL_CATEGORY", pattern = "^UACR_CLINICAL_CATEGORY")
  )
  spec <- exposure_map[[exposure_definition]]
  if (is.null(spec) || !spec$variable %in% names(data)) {
    log("WARN", sprintf("Skipping %s %s because exposure is unavailable", analysis_label, exposure_definition))
    return(data.frame())
  }

  data <- droplevels(data)
  if (!has_variation(data[[spec$variable]])) {
    log("WARN", sprintf("Skipping %s %s because exposure has insufficient variation", analysis_label, exposure_definition))
    return(data.frame())
  }

  requested_covs <- requested_covariates()
  covs <- usable_covariates(data, requested_covs)
  n_model <- model_sample_n(data, c("TT4", spec$variable, covs$used))
  design <- make_design(data, weight, log, analysis_label)
  fit <- safe_svyglm(
    formula_for("TT4", spec$variable, covs$used),
    design,
    log,
    paste(analysis_label, exposure_definition)
  )

  extract_model_rows(
    fit = fit,
    pattern = spec$pattern,
    analysis_label = analysis_label,
    sensitivity_filter = sensitivity_filter,
    exposure_definition = exposure_definition,
    exposure_variable = spec$variable,
    n_model = n_model,
    requested_covs = requested_covs,
    used_covs = covs$used,
    dropped_covs = covs$missing
  )
}

rcs_terms <- function(x, knots) {
  positive_cube <- function(z) ifelse(z > 0, z^3, 0)
  last <- length(knots)
  denominator <- knots[last] - knots[last - 1]
  basis <- lapply(seq_len(last - 2), function(j) {
    positive_cube(x - knots[j]) -
      positive_cube(x - knots[last - 1]) * (knots[last] - knots[j]) / denominator +
      positive_cube(x - knots[last]) * (knots[last - 1] - knots[j]) / denominator
  })
  names(basis) <- paste0("RCS_NL", seq_along(basis))
  as.data.frame(basis)
}

add_rcs_terms <- function(data, knots) {
  basis <- rcs_terms(data$LOG_UACR, knots)
  for (name in names(basis)) {
    data[[name]] <- basis[[name]]
  }
  data
}

term_test_p <- function(fit, term_formula, log, label) {
  test <- tryCatch(
    survey::regTermTest(fit, term_formula),
    error = function(e) {
      log("WARN", sprintf("RCS term test failed for %s: %s", label, conditionMessage(e)))
      NULL
    }
  )
  if (is.null(test)) {
    return(NA_real_)
  }
  as.numeric(test$p[1])
}

typical_covariate_row <- function(data, covariates) {
  row <- data[1, , drop = FALSE]
  for (variable in covariates) {
    if (!variable %in% names(data)) {
      next
    }
    observed <- data[[variable]][!is.na(data[[variable]])]
    if (length(observed) == 0) {
      next
    }
    if (is.factor(data[[variable]])) {
      tab <- sort(table(observed), decreasing = TRUE)
      row[[variable]] <- factor(names(tab)[1], levels = levels(data[[variable]]))
    } else if (is.character(data[[variable]])) {
      tab <- sort(table(observed), decreasing = TRUE)
      row[[variable]] <- names(tab)[1]
    } else {
      row[[variable]] <- stats::median(observed, na.rm = TRUE)
    }
  }
  row
}

predict_svyglm <- function(fit, newdata) {
  prediction <- predict(fit, newdata = newdata, se.fit = TRUE, type = "response")
  if (is.list(prediction)) {
    fit_values <- as.numeric(prediction$fit)
    se_values <- as.numeric(prediction$se.fit)
  } else {
    fit_values <- as.numeric(prediction)
    variance <- attr(prediction, "var")
    se_values <- if (is.null(variance)) rep(NA_real_, length(fit_values)) else sqrt(diag(as.matrix(variance)))
  }
  data.frame(
    fit = fit_values,
    se = se_values,
    lower = fit_values - 1.96 * se_values,
    upper = fit_values + 1.96 * se_values
  )
}

fit_rcs_and_plot <- function(data, weight, root, log) {
  covs <- usable_covariates(data, requested_covariates())
  complete_vars <- c("TT4", "LOG_UACR", covs$used)
  rcs_data <- data[stats::complete.cases(data[, complete_vars, drop = FALSE]), , drop = FALSE]
  knots <- as.numeric(stats::quantile(rcs_data$LOG_UACR, probs = c(0.05, 0.35, 0.65, 0.95), na.rm = TRUE, type = 7))
  rcs_data <- add_rcs_terms(rcs_data, knots)
  rcs_terms_used <- names(rcs_terms(rcs_data$LOG_UACR, knots))
  design <- make_design(rcs_data, weight, log, "RCS full cohort")
  formula <- formula_for("TT4", c("LOG_UACR", rcs_terms_used), covs$used)
  fit <- safe_svyglm(formula, design, log, "RCS LOG_UACR and TT4")

  p_overall <- NA_real_
  p_nonlinearity <- NA_real_
  if (!is.null(fit)) {
    p_overall <- term_test_p(
      fit,
      stats::as.formula(paste("~", paste(c("LOG_UACR", rcs_terms_used), collapse = " + "))),
      log,
      "overall"
    )
    p_nonlinearity <- term_test_p(
      fit,
      stats::as.formula(paste("~", paste(rcs_terms_used, collapse = " + "))),
      log,
      "non-linearity"
    )
  }

  figure_path <- file.path(root, "outputs", "figures", "Figure2_RCS_TT4.pdf")
  dir.create(dirname(figure_path), recursive = TRUE, showWarnings = FALSE)
  if (!is.null(fit)) {
    grid_log_uacr <- seq(
      min(rcs_data$LOG_UACR, na.rm = TRUE),
      max(rcs_data$LOG_UACR, na.rm = TRUE),
      length.out = 200
    )
    newdata <- typical_covariate_row(rcs_data, covs$used)
    newdata <- newdata[rep(1, length(grid_log_uacr)), , drop = FALSE]
    newdata$LOG_UACR <- grid_log_uacr
    new_basis <- rcs_terms(grid_log_uacr, knots)
    for (name in names(new_basis)) {
      newdata[[name]] <- new_basis[[name]]
    }
    predicted <- predict_svyglm(fit, newdata)
    x <- exp(grid_log_uacr)

    grDevices::pdf(figure_path, width = 7, height = 5)
    old_par <- graphics::par(no.readonly = TRUE)
    on.exit({
      graphics::par(old_par)
      grDevices::dev.off()
    }, add = TRUE)
    graphics::plot(
      x, predicted$fit,
      type = "n",
      log = "x",
      xlab = "UACR (mg/g, log scale)",
      ylab = "Predicted total T4",
      main = "Restricted cubic spline: UACR and TT4"
    )
    graphics::polygon(
      c(x, rev(x)),
      c(predicted$lower, rev(predicted$upper)),
      col = grDevices::adjustcolor("grey70", alpha.f = 0.45),
      border = NA
    )
    graphics::lines(x, predicted$fit, lwd = 2, col = "#1f77b4")
    graphics::abline(v = c(30, 300), lty = 2, col = "#b22222")
    graphics::text(30, max(predicted$upper, na.rm = TRUE), "30 mg/g", pos = 4, col = "#b22222", cex = 0.8)
    graphics::text(300, max(predicted$upper, na.rm = TRUE), "300 mg/g", pos = 4, col = "#b22222", cex = 0.8)
    graphics::mtext(
      sprintf("P overall = %.3g; P non-linearity = %.3g", p_overall, p_nonlinearity),
      side = 3,
      line = 0.2,
      cex = 0.8
    )
  } else {
    grDevices::pdf(figure_path, width = 7, height = 5)
    graphics::plot.new()
    graphics::text(0.5, 0.5, "RCS model failed; no curve available.")
    grDevices::dev.off()
  }
  log("INFO", sprintf("Wrote RCS figure to %s", figure_path))

  list(
    p_overall = p_overall,
    p_nonlinearity = p_nonlinearity,
    n_model_unweighted = nrow(rcs_data),
    knots_log_uacr = knots,
    figure_path = figure_path
  )
}

subset_definitions <- function(data) {
  uacr_p <- stats::quantile(data$UACR_MG_G, probs = c(0.01, 0.99), na.rm = TRUE, type = 7)
  list(
    list(label = "Full Model 3 cohort", filter = "none", keep = rep(TRUE, nrow(data))),
    list(label = "Exclude eGFR <60", filter = "EGFR >=60", keep = !is.na(data$EGFR_CKD_EPI_2021) & data$EGFR_CKD_EPI_2021 >= 60),
    list(label = "Exclude diabetes", filter = "DIABETES == 0", keep = !is.na(data$DIABETES) & data$DIABETES == 0),
    list(label = "Exclude hypertension", filter = "HYPERTENSION == 0", keep = !is.na(data$HYPERTENSION) & data$HYPERTENSION == 0),
    list(label = "Exclude UACR >=300", filter = "UACR <300 mg/g", keep = !is.na(data$UACR_MG_G) & data$UACR_MG_G < 300),
    list(label = "Keep UACR p1-p99", filter = sprintf("UACR %.3f to %.3f mg/g", uacr_p[1], uacr_p[2]), keep = !is.na(data$UACR_MG_G) & data$UACR_MG_G >= uacr_p[1] & data$UACR_MG_G <= uacr_p[2]),
    list(label = "Euthyroid participants", filter = "TSH 0.45-4.50 and FT4 0.60-1.60", keep = !is.na(data$TSH) & !is.na(data$FT4) & data$TSH >= 0.45 & data$TSH <= 4.50 & data$FT4 >= 0.60 & data$FT4 <= 1.60)
  )
}

empty_results_table <- function() {
  data.frame(
    analysis_type = character(),
    analysis_label = character(),
    sensitivity_filter = character(),
    outcome = character(),
    exposure_definition = character(),
    exposure_variable = character(),
    contrast = character(),
    model = character(),
    beta = numeric(),
    ci_low = numeric(),
    ci_high = numeric(),
    p_value = numeric(),
    p_fdr = numeric(),
    n_model_unweighted = integer(),
    direction = character(),
    covariates_requested = character(),
    covariates_used = character(),
    covariates_dropped = character(),
    rcs_p_overall = numeric(),
    rcs_p_nonlinearity = numeric(),
    note = character()
  )
}

rcs_result_rows <- function(rcs) {
  data.frame(
    analysis_type = c("rcs_test", "rcs_test"),
    analysis_label = c("RCS full cohort", "RCS full cohort"),
    sensitivity_filter = c("none", "none"),
    outcome = c("TT4", "TT4"),
    exposure_definition = c("RCS_LOG_UACR", "RCS_LOG_UACR"),
    exposure_variable = c("LOG_UACR", "LOG_UACR"),
    contrast = c("RCS overall", "RCS non-linearity"),
    model = c("Model 3", "Model 3"),
    beta = c(NA_real_, NA_real_),
    ci_low = c(NA_real_, NA_real_),
    ci_high = c(NA_real_, NA_real_),
    p_value = c(rcs$p_overall, rcs$p_nonlinearity),
    p_fdr = c(NA_real_, NA_real_),
    n_model_unweighted = c(rcs$n_model_unweighted, rcs$n_model_unweighted),
    direction = c(NA_character_, NA_character_),
    covariates_requested = paste(requested_covariates(), collapse = " + "),
    covariates_used = NA_character_,
    covariates_dropped = NA_character_,
    rcs_p_overall = c(rcs$p_overall, rcs$p_overall),
    rcs_p_nonlinearity = c(rcs$p_nonlinearity, rcs$p_nonlinearity),
    note = sprintf(
      "RCS knots for LOG_UACR: %s",
      paste(formatC(rcs$knots_log_uacr, digits = 3, format = "f"), collapse = ", ")
    )
  )
}

add_fdr <- function(results) {
  if (nrow(results) == 0) {
    return(results)
  }
  model_rows <- results$analysis_type == "survey_model"
  adjusted <- rep(NA_real_, nrow(results))
  ok <- model_rows & !is.na(results$p_value)
  adjusted[ok] <- stats::p.adjust(results$p_value[ok], method = "fdr")
  results$p_fdr <- adjusted
  results
}

format_num <- function(x, digits = 3) {
  ifelse(is.na(x), "NA", formatC(x, digits = digits, format = "f"))
}

format_p <- function(x) {
  ifelse(is.na(x), "NA", ifelse(x < 0.001, formatC(x, digits = 2, format = "e"), formatC(x, digits = 3, format = "f")))
}

markdown_table <- function(rows) {
  lines <- c(
    "| Analysis | Exposure | Contrast | Beta (95% CI) | P | FDR | n | Direction |",
    "|---|---|---|---:|---:|---:|---:|---|"
  )
  if (nrow(rows) == 0) {
    return(c(lines, "| NA | NA | NA | NA | NA | NA | NA | NA |"))
  }
  for (i in seq_len(nrow(rows))) {
    beta_ci <- if (is.na(rows$beta[i])) {
      "NA"
    } else {
      sprintf("%s (%s to %s)", format_num(rows$beta[i]), format_num(rows$ci_low[i]), format_num(rows$ci_high[i]))
    }
    lines <- c(lines, sprintf(
      "| %s | %s | %s | %s | %s | %s | %s | %s |",
      rows$analysis_label[i],
      rows$exposure_definition[i],
      rows$contrast[i],
      beta_ci,
      format_p(rows$p_value[i]),
      format_p(rows$p_fdr[i]),
      rows$n_model_unweighted[i],
      ifelse(is.na(rows$direction[i]), "", rows$direction[i])
    ))
  }
  lines
}

judge_evidence <- function(results, rcs) {
  continuous <- results[
    results$analysis_type == "survey_model" &
      results$exposure_definition == "LOG_UACR" &
      results$contrast == "LOG_UACR",
    ,
    drop = FALSE
  ]
  if (nrow(continuous) == 0) {
    return(list(
      direction_consistent = FALSE,
      positive_count = 0,
      total_count = 0,
      nominal_count = 0,
      fdr_count = 0,
      evidence_grade = "No evidence",
      upgraded_to_moderate = FALSE,
      sentence = "No evidence: LOG_UACR robustness models were unavailable."
    ))
  }

  positive_count <- sum(continuous$direction == "positive", na.rm = TRUE)
  nominal_count <- sum(continuous$p_value < 0.05, na.rm = TRUE)
  fdr_count <- sum(continuous$p_fdr < 0.05, na.rm = TRUE)
  total_count <- nrow(continuous)
  direction_consistent <- positive_count >= ceiling(total_count / 2)
  majority_nominal <- nominal_count >= ceiling(total_count / 2)
  rcs_overall <- !is.na(rcs$p_overall) && rcs$p_overall < 0.05

  evidence_grade <- if (direction_consistent && majority_nominal && rcs_overall) {
    "Moderate evidence"
  } else if (direction_consistent && (nominal_count > 0 || fdr_count > 0)) {
    "Weak evidence"
  } else {
    "No evidence"
  }

  list(
    direction_consistent = direction_consistent,
    positive_count = positive_count,
    total_count = total_count,
    nominal_count = nominal_count,
    fdr_count = fdr_count,
    evidence_grade = evidence_grade,
    upgraded_to_moderate = identical(evidence_grade, "Moderate evidence"),
    sentence = sprintf(
      "%s for a positive association between UACR and TT4 after robustness checks: %s/%s LOG_UACR models were positive, %s/%s were nominally significant, and RCS overall P = %s.",
      evidence_grade,
      positive_count,
      total_count,
      nominal_count,
      total_count,
      format_p(rcs$p_overall)
    )
  )
}

build_report <- function(results, rcs, evidence) {
  model_rows <- results[results$analysis_type == "survey_model", , drop = FALSE]
  log_rows <- model_rows[
    model_rows$exposure_definition %in% c("LOG_UACR", "LOG2_UACR"),
    ,
    drop = FALSE
  ]
  clinical_rows <- model_rows[
    model_rows$exposure_definition %in% c("UACR_QUARTILE", "UACR_CLINICAL_CATEGORY") &
      model_rows$sensitivity_filter == "none",
    ,
    drop = FALSE
  ]

  c(
    "# TT4 robustness summary",
    "",
    "Primary outcome: TT4. TGAB is not treated as a primary conclusion in this robustness report.",
    "",
    "All survey models use Model 3 covariate adjustment where covariates have non-missing values and variation within the analyzed subset.",
    "",
    "## Evidence judgement",
    sprintf("- %s", evidence$sentence),
    sprintf("- Directionally consistent in most sensitivity analyses: %s.", evidence$direction_consistent),
    sprintf("- Evidence upgraded from weak to moderate: %s.", evidence$upgraded_to_moderate),
    "",
    "## RCS",
    sprintf("- P for overall association: %s.", format_p(rcs$p_overall)),
    sprintf("- P for non-linearity: %s.", format_p(rcs$p_nonlinearity)),
    "- The RCS figure marks UACR = 30 mg/g and 300 mg/g.",
    "",
    "## Continuous-exposure robustness models",
    markdown_table(log_rows),
    "",
    "## Full-cohort categorical exposure checks",
    markdown_table(clinical_rows),
    "",
    "## Outputs",
    "- outputs/tables/TableS_TT4_robustness.csv",
    "- outputs/figures/Figure2_RCS_TT4.pdf",
    "- outputs/logs/05_TT4_robustness.log"
  )
}

main <- function() {
  root <- find_project_root()
  log <- init_logger(root)
  if (!requireNamespace("survey", quietly = TRUE)) {
    stop("R package 'survey' is required.", call. = FALSE)
  }
  options(survey.lonely.psu = "adjust")

  data <- prepare_discovery(read_discovery(root, log))
  weight <- pick_weight(data, log)

  subsets <- subset_definitions(data)
  exposures <- c("LOG_UACR", "LOG2_UACR", "UACR_QUARTILE", "UACR_CLINICAL_CATEGORY")
  results <- list()

  for (subset_spec in subsets) {
    subset_data <- data[subset_spec$keep, , drop = FALSE]
    subset_data <- droplevels(subset_data)
    log("INFO", sprintf("%s rows after filter [%s]: %s", subset_spec$label, subset_spec$filter, nrow(subset_data)))
    for (exposure in exposures) {
      rows <- fit_exposure(
        data = subset_data,
        weight = weight,
        exposure_definition = exposure,
        analysis_label = subset_spec$label,
        sensitivity_filter = subset_spec$filter,
        log = log
      )
      if (nrow(rows) > 0) {
        results[[length(results) + 1]] <- rows
      }
    }
  }

  model_results <- if (length(results) == 0) empty_results_table() else do.call(rbind, results)
  model_results <- add_fdr(model_results)

  rcs <- fit_rcs_and_plot(data, weight, root, log)
  all_results <- rbind(model_results, rcs_result_rows(rcs))
  evidence <- judge_evidence(model_results, rcs)

  table_path <- file.path(root, "outputs", "tables", "TableS_TT4_robustness.csv")
  report_path <- file.path(root, "outputs", "reports", "TT4_robustness_summary.md")
  write_csv_safe(all_results, table_path)
  write_lines_safe(build_report(all_results, rcs, evidence), report_path)

  log("INFO", sprintf("Wrote %s rows to %s", nrow(all_results), table_path))
  log("INFO", sprintf("Wrote robustness report to %s", report_path))
  log("INFO", evidence$sentence)
  log("INFO", sprintf("Evidence upgraded from weak to moderate: %s", evidence$upgraded_to_moderate))
}

main()
