options(stringsAsFactors = FALSE)

DISCOVERY_WEIGHT_NOTE <- paste(
  "Discovery cohort used cycle-specific thyroid analysis weights:",
  "WTMEC2YR for 2007-2008 and WTSA2YR for 2009-2012,",
  "divided by 3 for 6-year pooled analysis."
)

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

init_fixed_logger <- function(root) {
  log_dir <- file.path(root, "outputs", "logs")
  dir.create(log_dir, recursive = TRUE, showWarnings = FALSE)
  log_file <- file.path(log_dir, "03_discovery_validation_regression.log")
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

empty_result_table <- function() {
  data.frame(
    cohort = character(),
    outcome = character(),
    outcome_role = character(),
    exposure_type = character(),
    contrast = character(),
    model = character(),
    beta = numeric(),
    ci_low = numeric(),
    ci_high = numeric(),
    p_value = numeric(),
    p_fdr = numeric(),
    p_trend = numeric(),
    n = integer(),
    n_model_unweighted = integer(),
    n_missing_dropped = integer(),
    weighted_population_estimate = numeric(),
    covariates_requested = character(),
    covariates_used = character(),
    covariates_missing = character(),
    uic_adjusted = logical(),
    note = character()
  )
}

read_cohort <- function(path, log, cohort_label) {
  if (!file.exists(path)) {
    log("WARN", sprintf("%s dataset not found: %s", cohort_label, path))
    return(NULL)
  }
  data <- utils::read.csv(path, check.names = FALSE)
  names(data) <- toupper(names(data))
  if (nrow(data) == 0) {
    log("WARN", sprintf("%s dataset is empty: %s", cohort_label, path))
  } else {
    log("INFO", sprintf("Loaded %s dataset: %s rows x %s columns", cohort_label, nrow(data), ncol(data)))
  }
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

add_exposure_variables <- function(data, log, cohort_label) {
  if (!"LOG_UACR" %in% names(data) && "UACR_MG_G" %in% names(data)) {
    data$LOG_UACR <- ifelse(data$UACR_MG_G > 0, base::log(data$UACR_MG_G), NA_real_)
  }

  if (!"UACR_QUARTILE" %in% names(data) || all(is.na(data$UACR_QUARTILE))) {
    if ("UACR_MG_G" %in% names(data) && sum(!is.na(data$UACR_MG_G)) >= 4) {
      breaks <- unique(stats::quantile(data$UACR_MG_G, probs = seq(0, 1, 0.25), na.rm = TRUE, type = 7))
      if (length(breaks) == 5) {
        data$UACR_QUARTILE <- cut(
          data$UACR_MG_G,
          breaks = breaks,
          include.lowest = TRUE,
          labels = c("Q1", "Q2", "Q3", "Q4")
        )
      } else {
        data$UACR_QUARTILE <- rep(NA_character_, nrow(data))
        log("WARN", sprintf("%s UACR quartiles unavailable because quantile breaks are not unique", cohort_label))
      }
    } else {
      data$UACR_QUARTILE <- rep(NA_character_, nrow(data))
      log("WARN", sprintf("%s UACR quartiles unavailable because UACR_MG_G is missing or too sparse", cohort_label))
    }
  } else {
    data$UACR_QUARTILE <- factor(data$UACR_QUARTILE, levels = c("Q1", "Q2", "Q3", "Q4"))
  }

  if ("UACR_MG_G" %in% names(data)) {
    data$UACR_CLINICAL_CATEGORY <- cut(
      data$UACR_MG_G,
      breaks = c(-Inf, 30, 300, Inf),
      right = FALSE,
      labels = c("<30", "30-300", ">=300")
    )
  } else {
    data$UACR_CLINICAL_CATEGORY <- rep(NA_character_, nrow(data))
  }

  data$UACR_QUARTILE_SCORE <- as.numeric(factor(data$UACR_QUARTILE, levels = c("Q1", "Q2", "Q3", "Q4")))
  data$UACR_CLINICAL_SCORE <- as.numeric(factor(data$UACR_CLINICAL_CATEGORY, levels = c("<30", "30-300", ">=300")))
  data
}

prepare_cohort <- function(data, log, cohort_label) {
  if (is.null(data)) {
    return(NULL)
  }

  numeric_vars <- c(
    "SEQN", "AGE_YEARS", "PIR", "BMI", "EGFR_CKD_EPI_2021", "UIC_UG_L",
    "UACR_MG_G", "LOG_UACR", "TSH", "TT4", "TGAB", "TPOAB", "FT3", "FT4",
    "TT3", "TG", "WTSA6YR", "WTMEC6YR", "WTSA2YR", "WTPFEX6", "SDMVPSU",
    "SDMVSTRA", "SDPPSU6", "SDPSTRA6"
  )
  factor_vars <- c(
    "SEX", "RACE_ETHNICITY", "EDUCATION", "SMOKING_STATUS", "ALCOHOL_STATUS",
    "DIABETES_STATUS", "HYPERTENSION_STATUS"
  )
  data <- as_numeric_if_present(data, numeric_vars)
  data <- as_factor_if_present(data, factor_vars)
  data <- add_exposure_variables(data, log, cohort_label)
  data
}

cohort_specifications <- function() {
  list(
    discovery = list(
      label = "discovery",
      path = file.path("data", "processed", "discovery_nhanes_2007_2012.csv"),
      weight_candidates = c("ANALYTIC_WT6YR", "WTSA6YR"),
      psu = "SDMVPSU",
      strata = "SDMVSTRA",
      primary_outcomes = c("TT4", "TGAB"),
      secondary_outcomes = c("TSH", "TPOAB", "FT3", "FT4", "TT3", "TG"),
      validation_outcomes = character(),
      uic_variable = "UIC_UG_L",
      include_uic_in_model3 = TRUE
    ),
    validation = list(
      label = "validation",
      path = file.path("data", "processed", "validation_nhanes3.csv"),
      weight_candidates = c("WTPFEX6"),
      psu = "SDPPSU6",
      strata = "SDPSTRA6",
      primary_outcomes = character(),
      secondary_outcomes = character(),
      validation_outcomes = c("TT4", "TSH", "TGAB", "TPOAB"),
      uic_variable = "UIC_UG_L",
      include_uic_in_model3 = FALSE
    )
  )
}

pick_weight <- function(data, spec, log) {
  for (candidate in spec$weight_candidates) {
    if (candidate %in% names(data) && any(!is.na(data[[candidate]]) & data[[candidate]] > 0)) {
      log("INFO", sprintf("%s survey design uses weight: %s", spec$label, candidate))
      return(candidate)
    }
  }
  message <- sprintf("%s has no usable survey weight among: %s", spec$label, paste(spec$weight_candidates, collapse = ", "))
  log("ERROR", message)
  stop(message, call. = FALSE)
}

available_design <- function(data, spec, log) {
  weight <- pick_weight(data, spec, log)
  required <- c(weight, spec$psu, spec$strata)
  required <- required[!is.na(required)]
  missing <- setdiff(required, names(data))
  if (length(missing) > 0) {
    log("WARN", sprintf("%s survey design variables missing: %s", spec$label, paste(missing, collapse = ", ")))
    return(NULL)
  }

  design_data <- data[
    !is.na(data[[weight]]) &
      data[[weight]] > 0 &
      !is.na(data[[spec$psu]]) &
      !is.na(data[[spec$strata]]),
    ,
    drop = FALSE
  ]
  if (nrow(design_data) == 0) {
    log("WARN", sprintf("%s has no rows with complete survey design variables", spec$label))
    return(NULL)
  }

  survey::svydesign(
    ids = stats::as.formula(paste0("~", spec$psu)),
    strata = stats::as.formula(paste0("~", spec$strata)),
    weights = stats::as.formula(paste0("~", weight)),
    nest = TRUE,
    data = design_data
  )
}

outcome_role <- function(outcome, spec) {
  if (outcome %in% spec$primary_outcomes) {
    return("primary")
  }
  if (outcome %in% spec$secondary_outcomes) {
    return("secondary")
  }
  if (outcome %in% spec$validation_outcomes) {
    return("validation")
  }
  "unspecified"
}

requested_covariates <- function(model_name, spec) {
  if (model_name == "Model 1") {
    return(character())
  }
  model2 <- c("AGE_YEARS", "SEX", "RACE_ETHNICITY")
  if (model_name == "Model 2") {
    return(model2)
  }
  model3 <- c(
    model2,
    "EDUCATION", "PIR", "BMI", "SMOKING_STATUS", "ALCOHOL_STATUS",
    "DIABETES_STATUS", "HYPERTENSION_STATUS", "EGFR_CKD_EPI_2021"
  )
  if (identical(spec$include_uic_in_model3, TRUE)) {
    model3 <- c(model3, spec$uic_variable)
  }
  model3
}

usable_covariates <- function(data, requested) {
  present <- requested[requested %in% names(data)]
  used <- present[vapply(present, function(variable) any(!is.na(data[[variable]])), logical(1))]
  missing <- setdiff(requested, used)
  list(used = used, missing = missing)
}

formula_for <- function(outcome, exposure, covariates) {
  rhs <- c(exposure, covariates)
  stats::as.formula(paste(outcome, "~", paste(rhs, collapse = " + ")))
}

safe_svyglm <- function(formula, design, log, context) {
  result <- tryCatch(
    survey::svyglm(formula, design = design),
    error = function(e) {
      log("WARN", sprintf("Model failed for %s: %s", context, conditionMessage(e)))
      NULL
    }
  )
  result
}

trend_p_value <- function(outcome, score_variable, covariates, design, log, context) {
  formula <- formula_for(outcome, score_variable, covariates)
  fit <- safe_svyglm(formula, design, log, paste0(context, " trend"))
  if (is.null(fit)) {
    return(NA_real_)
  }
  coefficients <- summary(fit)$coefficients
  if (!score_variable %in% rownames(coefficients)) {
    return(NA_real_)
  }
  as.numeric(coefficients[score_variable, "Pr(>|t|)"])
}

weighted_population_from_mask <- function(design, complete_mask) {
  if (length(complete_mask) == 0 || !any(complete_mask)) {
    return(0)
  }

  estimate <- tryCatch(
    {
      design_for_total <- design
      design_for_total$variables$.MODEL_COMPLETE_CASE <- as.numeric(complete_mask)
      as.numeric(stats::coef(survey::svytotal(~.MODEL_COMPLETE_CASE, design_for_total, na.rm = TRUE))[1])
    },
    error = function(e) NA_real_
  )

  if (is.na(estimate)) {
    weights <- tryCatch(stats::weights(design, type = "sampling"), error = function(e) NULL)
    if (!is.null(weights) && length(weights) == length(complete_mask)) {
      estimate <- sum(weights[complete_mask], na.rm = TRUE)
    }
  }

  estimate
}

model_sample_info <- function(design, variables, total_n = nrow(design$variables)) {
  design_data <- design$variables
  total_n <- as.integer(total_n)
  missing_variables <- setdiff(variables, names(design_data))

  if (length(missing_variables) > 0) {
    complete_mask <- rep(FALSE, nrow(design_data))
  } else {
    complete_mask <- stats::complete.cases(design_data[, variables, drop = FALSE])
  }

  n_model <- as.integer(sum(complete_mask))
  list(
    n_model_unweighted = n_model,
    n_missing_dropped = as.integer(max(total_n - n_model, 0)),
    weighted_population_estimate = weighted_population_from_mask(design, complete_mask)
  )
}

extract_rows <- function(
    fit,
    coefficient_patterns,
    cohort,
    outcome,
    role,
    exposure_type,
    model_name,
    requested_covs,
    used_covs,
    missing_covs,
    uic_adjusted,
    trend_p,
    sample_info,
    note) {
  if (is.null(fit)) {
    return(empty_result_table())
  }

  coefficients <- summary(fit)$coefficients
  vcov_matrix <- stats::vcov(fit)
  wanted <- unique(unlist(lapply(coefficient_patterns, function(pattern) grep(pattern, rownames(coefficients), value = TRUE))))
  if (length(wanted) == 0) {
    return(empty_result_table())
  }

  rows <- lapply(wanted, function(term) {
    beta <- as.numeric(coefficients[term, "Estimate"])
    se <- as.numeric(coefficients[term, "Std. Error"])
    p_value <- as.numeric(coefficients[term, "Pr(>|t|)"])
    data.frame(
      cohort = cohort,
      outcome = outcome,
      outcome_role = role,
      exposure_type = exposure_type,
      contrast = term,
      model = model_name,
      beta = beta,
      ci_low = beta - 1.96 * se,
      ci_high = beta + 1.96 * se,
      p_value = p_value,
      p_fdr = NA_real_,
      p_trend = trend_p,
      n = sample_info$n_model_unweighted,
      n_model_unweighted = sample_info$n_model_unweighted,
      n_missing_dropped = sample_info$n_missing_dropped,
      weighted_population_estimate = sample_info$weighted_population_estimate,
      covariates_requested = paste(requested_covs, collapse = " + "),
      covariates_used = paste(used_covs, collapse = " + "),
      covariates_missing = paste(missing_covs, collapse = " + "),
      uic_adjusted = isTRUE(uic_adjusted),
      note = note
    )
  })
  do.call(rbind, rows)
}

fit_one_exposure <- function(design, data, spec, outcome, exposure_type, model_name, log, cohort_total_n) {
  requested <- requested_covariates(model_name, spec)
  covs <- usable_covariates(data, requested)
  used_covs <- covs$used
  missing_covs <- covs$missing

  uic_adjusted <- spec$label == "discovery" && model_name == "Model 3" && spec$uic_variable %in% used_covs
  uic_note <- if (spec$label == "validation" && model_name == "Model 3") {
    "UIC not adjusted in NHANES III validation because UIC is unavailable/not requested."
  } else if (spec$label == "discovery" && model_name == "Model 3" && !uic_adjusted) {
    "Discovery Model 3 requested UIC, but UIC was unavailable or all missing."
  } else {
    ""
  }
  missing_note <- if (length(missing_covs) > 0) {
    paste0("Omitted unavailable covariates: ", paste(missing_covs, collapse = ", "), ".")
  } else {
    ""
  }
  weight_note <- if (spec$label == "discovery") DISCOVERY_WEIGHT_NOTE else ""
  note <- paste(c(weight_note, uic_note, missing_note), collapse = " ")
  note <- trimws(note)

  role <- outcome_role(outcome, spec)
  if (exposure_type == "log_UACR") {
    exposure <- "LOG_UACR"
    sample_info <- model_sample_info(design, c(outcome, exposure, used_covs), cohort_total_n)
    fit <- safe_svyglm(
      formula_for(outcome, exposure, used_covs),
      design,
      log,
      paste(spec$label, outcome, exposure_type, model_name)
    )
    return(extract_rows(
      fit, "^LOG_UACR$", spec$label, outcome, role, exposure_type, model_name,
      requested, used_covs, missing_covs, uic_adjusted, NA_real_, sample_info, note
    ))
  }

  if (exposure_type == "UACR quartile") {
    exposure <- "UACR_QUARTILE"
    sample_info <- model_sample_info(design, c(outcome, exposure, used_covs), cohort_total_n)
    fit <- safe_svyglm(
      formula_for(outcome, exposure, used_covs),
      design,
      log,
      paste(spec$label, outcome, exposure_type, model_name)
    )
    trend <- trend_p_value(
      outcome, "UACR_QUARTILE_SCORE", used_covs, design, log,
      paste(spec$label, outcome, exposure_type, model_name)
    )
    return(extract_rows(
      fit, "^UACR_QUARTILE", spec$label, outcome, role, exposure_type, model_name,
      requested, used_covs, missing_covs, uic_adjusted, trend, sample_info, note
    ))
  }

  if (exposure_type == "UACR clinical category") {
    exposure <- "UACR_CLINICAL_CATEGORY"
    sample_info <- model_sample_info(design, c(outcome, exposure, used_covs), cohort_total_n)
    fit <- safe_svyglm(
      formula_for(outcome, exposure, used_covs),
      design,
      log,
      paste(spec$label, outcome, exposure_type, model_name)
    )
    trend <- trend_p_value(
      outcome, "UACR_CLINICAL_SCORE", used_covs, design, log,
      paste(spec$label, outcome, exposure_type, model_name)
    )
    return(extract_rows(
      fit, "^UACR_CLINICAL_CATEGORY", spec$label, outcome, role, exposure_type, model_name,
      requested, used_covs, missing_covs, uic_adjusted, trend, sample_info, note
    ))
  }

  empty_result_table()
}

fit_cohort <- function(data, spec, log) {
  if (is.null(data) || nrow(data) == 0) {
    log("WARN", sprintf("%s has no rows available for regression", spec$label))
    return(empty_result_table())
  }

  all_outcomes <- unique(c(spec$primary_outcomes, spec$secondary_outcomes, spec$validation_outcomes))
  available_outcomes <- all_outcomes[all_outcomes %in% names(data) & vapply(all_outcomes, function(x) any(!is.na(data[[x]])), logical(1))]
  unavailable_outcomes <- setdiff(all_outcomes, available_outcomes)
  if (length(unavailable_outcomes) > 0) {
    log("WARN", sprintf("%s unavailable outcomes: %s", spec$label, paste(unavailable_outcomes, collapse = ", ")))
  }
  if (length(available_outcomes) == 0) {
    log("WARN", sprintf("%s has no available outcomes for regression", spec$label))
    return(empty_result_table())
  }

  design <- available_design(data, spec, log)
  if (is.null(design)) {
    return(empty_result_table())
  }
  design_data <- design$variables

  exposures <- c("log_UACR", "UACR quartile", "UACR clinical category")
  models <- c("Model 1", "Model 2", "Model 3")
  results <- list()

  for (outcome in available_outcomes) {
    for (exposure_type in exposures) {
      for (model_name in models) {
        required <- c(outcome)
        if (exposure_type == "log_UACR") {
          required <- c(required, "LOG_UACR")
        } else if (exposure_type == "UACR quartile") {
          required <- c(required, "UACR_QUARTILE", "UACR_QUARTILE_SCORE")
        } else {
          required <- c(required, "UACR_CLINICAL_CATEGORY", "UACR_CLINICAL_SCORE")
        }
        missing_required <- setdiff(required, names(design_data))
        if (length(missing_required) > 0 || any(!stats::complete.cases(design_data[, required, drop = FALSE]))) {
          complete_required <- stats::complete.cases(design_data[, intersect(required, names(design_data)), drop = FALSE])
          if (!any(complete_required)) {
            log("WARN", sprintf(
              "Skipping %s %s %s %s because required variables are unavailable or all missing",
              spec$label, outcome, exposure_type, model_name
            ))
            next
          }
        }
        results[[length(results) + 1]] <- fit_one_exposure(
          design, design_data, spec, outcome, exposure_type, model_name, log, nrow(data)
        )
      }
    }
  }

  if (length(results) == 0) {
    return(empty_result_table())
  }
  do.call(rbind, results)
}

add_fdr <- function(results) {
  if (nrow(results) == 0) {
    return(results)
  }
  group_key <- paste(
    results$cohort,
    results$model,
    results$exposure_type,
    results$contrast,
    sep = "||"
  )
  results$p_fdr <- ave(results$p_value, group_key, FUN = function(p) {
    adjusted <- rep(NA_real_, length(p))
    ok <- !is.na(p)
    adjusted[ok] <- stats::p.adjust(p[ok], method = "fdr")
    adjusted
  })
  results
}

empty_model_n_check_table <- function() {
  data.frame(
    cohort = character(),
    outcome = character(),
    outcome_role = character(),
    exposure_type = character(),
    model = character(),
    n_model_unweighted = integer(),
    n_missing_dropped = integer(),
    weighted_population_estimate = numeric(),
    covariates_requested = character(),
    covariates_used = character(),
    covariates_missing = character(),
    uic_adjusted = logical(),
    note = character()
  )
}

model_n_check_table <- function(results) {
  if (nrow(results) == 0) {
    return(empty_model_n_check_table())
  }

  columns <- c(
    "cohort", "outcome", "outcome_role", "exposure_type", "model",
    "n_model_unweighted", "n_missing_dropped", "weighted_population_estimate",
    "covariates_requested", "covariates_used", "covariates_missing",
    "uic_adjusted", "note"
  )
  discovery <- results[results$cohort == "discovery", columns, drop = FALSE]
  if (nrow(discovery) == 0) {
    return(empty_model_n_check_table())
  }

  keys <- c("outcome", "exposure_type", "model")
  discovery <- discovery[!duplicated(discovery[, keys, drop = FALSE]), , drop = FALSE]
  discovery[order(discovery$outcome, discovery$exposure_type, discovery$model), , drop = FALSE]
}

log_discovery_model_n_summary <- function(model_n_check, discovery_total_n, log) {
  log("INFO", sprintf("discovery dataset total n: %s", discovery_total_n))

  for (model_name in c("Model 1", "Model 2", "Model 3")) {
    values <- model_n_check$n_model_unweighted[model_n_check$model == model_name]
    values <- values[!is.na(values)]
    if (length(values) == 0) {
      log("WARN", sprintf("%s has no discovery model n values", model_name))
    } else {
      log("INFO", sprintf(
        "%s discovery n_model_unweighted min/max: %s/%s",
        model_name, min(values), max(values)
      ))
    }
  }

  model3 <- model_n_check[model_n_check$model == "Model 3", , drop = FALSE]
  threshold <- 0.8 * discovery_total_n
  low_n <- model3[!is.na(model3$n_model_unweighted) & model3$n_model_unweighted < threshold, , drop = FALSE]
  if (nrow(low_n) > 0) {
    affected <- unique(paste(low_n$outcome, low_n$exposure_type, sep = " / "))
    preview <- paste(utils::head(affected, 12), collapse = "; ")
    suffix <- if (length(affected) > 12) " ..." else ""
    log("WARN", sprintf(
      "Some Model 3 discovery analyses used <80%% of total n (threshold %.1f). Minimum n=%s. Affected: %s%s",
      threshold, min(low_n$n_model_unweighted, na.rm = TRUE), preview, suffix
    ))
  }
}

main_effect_rows <- function(results) {
  if (nrow(results) == 0) {
    return(results)
  }
  keep <- results$exposure_type == "log_UACR" & results$model == "Model 3" & results$contrast == "LOG_UACR"
  results[keep, , drop = FALSE]
}

replication_summary <- function(results) {
  main <- main_effect_rows(results)
  common_outcomes <- c("TT4", "TSH", "TGAB", "TPOAB")
  rows <- lapply(common_outcomes, function(outcome) {
    discovery <- main[main$cohort == "discovery" & main$outcome == outcome, , drop = FALSE]
    validation <- main[main$cohort == "validation" & main$outcome == outcome, , drop = FALSE]
    discovery_beta <- if (nrow(discovery) > 0) discovery$beta[1] else NA_real_
    validation_beta <- if (nrow(validation) > 0) validation$beta[1] else NA_real_
    data.frame(
      outcome = outcome,
      discovery_beta = discovery_beta,
      validation_beta = validation_beta,
      same_direction = ifelse(
        is.na(discovery_beta) | is.na(validation_beta),
        NA,
        sign(discovery_beta) == sign(validation_beta)
      ),
      discovery_p = if (nrow(discovery) > 0) discovery$p_value[1] else NA_real_,
      validation_p = if (nrow(validation) > 0) validation$p_value[1] else NA_real_,
      discovery_fdr = if (nrow(discovery) > 0) discovery$p_fdr[1] else NA_real_,
      validation_fdr = if (nrow(validation) > 0) validation$p_fdr[1] else NA_real_,
      note = ifelse(
        is.na(discovery_beta) | is.na(validation_beta),
        "Not assessable because one cohort lacks a Model 3 log_UACR estimate.",
        "Direction comparison uses Model 3 log_UACR beta."
      )
    )
  })
  do.call(rbind, rows)
}

write_missing_outputs <- function(root, log, note) {
  empty <- empty_result_table()
  table2 <- file.path(root, "outputs", "tables", "Table2_discovery_main_results.csv")
  table3 <- file.path(root, "outputs", "tables", "Table3_validation_results.csv")
  tables <- file.path(root, "outputs", "tables", "TableS_full_thyroid_results.csv")
  n_check <- file.path(root, "outputs", "tables", "Table2_discovery_model_n_check.csv")
  replication <- file.path(root, "outputs", "tables", "replication_summary.csv")
  write_csv_safe(empty, table2)
  write_csv_safe(empty, table3)
  write_csv_safe(empty, tables)
  write_csv_safe(empty_model_n_check_table(), n_check)
  write_csv_safe(data.frame(note = note), replication)
  log("WARN", note)
}

main <- function() {
  root <- find_project_root()
  log <- init_fixed_logger(root)
  for (relative in c("outputs/tables", "outputs/logs", "outputs/reports")) {
    dir.create(file.path(root, relative), recursive = TRUE, showWarnings = FALSE)
  }

  if (!requireNamespace("survey", quietly = TRUE)) {
    write_missing_outputs(root, log, "R package 'survey' is required but not installed.")
    return(invisible(NULL))
  }
  options(survey.lonely.psu = "adjust")

  specs <- cohort_specifications()
  discovery <- read_cohort(file.path(root, specs$discovery$path), log, "discovery")
  validation <- read_cohort(file.path(root, specs$validation$path), log, "validation")
  discovery <- prepare_cohort(discovery, log, "discovery")
  validation <- prepare_cohort(validation, log, "validation")

  discovery_results <- fit_cohort(discovery, specs$discovery, log)
  validation_results <- fit_cohort(validation, specs$validation, log)
  all_results <- add_fdr(rbind(discovery_results, validation_results))

  table2 <- all_results[
    all_results$cohort == "discovery" &
      all_results$outcome_role == "primary",
    ,
    drop = FALSE
  ]
  table3 <- all_results[
    all_results$cohort == "validation",
    ,
    drop = FALSE
  ]
  summary <- replication_summary(all_results)
  n_check <- model_n_check_table(all_results)

  table2_path <- file.path(root, "outputs", "tables", "Table2_discovery_main_results.csv")
  table3_path <- file.path(root, "outputs", "tables", "Table3_validation_results.csv")
  tables_path <- file.path(root, "outputs", "tables", "TableS_full_thyroid_results.csv")
  n_check_path <- file.path(root, "outputs", "tables", "Table2_discovery_model_n_check.csv")
  summary_path <- file.path(root, "outputs", "tables", "replication_summary.csv")

  write_csv_safe(table2, table2_path)
  write_csv_safe(table3, table3_path)
  write_csv_safe(all_results, tables_path)
  write_csv_safe(n_check, n_check_path)
  write_csv_safe(summary, summary_path)

  discovery_total_n <- if (is.null(discovery)) 0L else nrow(discovery)
  log_discovery_model_n_summary(n_check, discovery_total_n, log)

  log("INFO", sprintf("Wrote %s rows to %s", nrow(table2), table2_path))
  log("INFO", sprintf("Wrote %s rows to %s", nrow(table3), table3_path))
  log("INFO", sprintf("Wrote %s rows to %s", nrow(all_results), tables_path))
  log("INFO", sprintf("Wrote discovery model n check to %s", n_check_path))
  log("INFO", sprintf("Wrote replication summary to %s", summary_path))
}

main()
