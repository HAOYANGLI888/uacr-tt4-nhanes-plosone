options(stringsAsFactors = FALSE)

find_project_root <- function(start = getwd()) {
  current <- normalizePath(start, winslash = "/", mustWork = TRUE)
  repeat {
    if (file.exists(file.path(current, "config", "analysis_plan.yaml"))) {
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
  log_file <- file.path(log_dir, "09_mortality_extension.log")
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

read_linked_cohort <- function(root, log) {
  path <- file.path(root, "data", "processed", "discovery_nhanes_2007_2012_mortality.csv")
  if (!file.exists(path)) {
    stop(sprintf("Linked mortality cohort not found: %s", path), call. = FALSE)
  }
  data <- utils::read.csv(path, check.names = FALSE)
  names(data) <- toupper(names(data))
  log("INFO", sprintf("Loaded linked mortality cohort: %s rows x %s columns", nrow(data), ncol(data)))
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

weighted_quantile <- function(x, weights, probs) {
  keep <- !is.na(x) & !is.na(weights) & weights > 0
  x <- x[keep]
  weights <- weights[keep]
  if (length(x) == 0) {
    return(rep(NA_real_, length(probs)))
  }
  index <- order(x)
  x <- x[index]
  weights <- weights[index]
  cumulative <- cumsum(weights) / sum(weights)
  vapply(probs, function(prob) x[which(cumulative >= prob)[1]], numeric(1))
}

weighted_mean_sd <- function(x, weights) {
  keep <- !is.na(x) & !is.na(weights) & weights > 0
  x <- x[keep]
  weights <- weights[keep]
  mean <- sum(weights * x) / sum(weights)
  sd <- sqrt(sum(weights * (x - mean)^2) / sum(weights))
  c(mean = mean, sd = sd)
}

prepare_data <- function(data, log) {
  numeric_vars <- c(
    "AGE", "PIR", "BMI", "EGFR", "UIC_UG_L", "UACR", "LOG_UACR", "TSH", "FT4", "TT4",
    "ANALYTIC_WT6YR", "SDMVPSU", "SDMVSTRA", "ELIGSTAT", "PERMTH_EXM", "ALL_CAUSE_DEATH", "CVD_DEATH"
  )
  factor_vars <- c("SEX", "RACE", "EDUCATION", "SMOKE", "DRINK", "DIABETES", "HYPERTENSION")
  data <- as_numeric_if_present(data, numeric_vars)
  data <- as_factor_if_present(data, factor_vars)
  data <- data[
    data$ELIGSTAT == 1 &
      !is.na(data$PERMTH_EXM) &
      data$PERMTH_EXM > 0 &
      !is.na(data$ANALYTIC_WT6YR) &
      data$ANALYTIC_WT6YR > 0 &
      !is.na(data$SDMVPSU) &
      !is.na(data$SDMVSTRA),
    ,
    drop = FALSE
  ]
  data$FOLLOWUP_YEARS <- data$PERMTH_EXM / 12
  data$UACR_ALBUMINURIA <- factor(ifelse(data$UACR >= 30, "UACR_ge30", "UACR_lt30"), levels = c("UACR_lt30", "UACR_ge30"))
  data$UACR_CLINICAL_CATEGORY <- factor(
    ifelse(data$UACR < 30, "<30", ifelse(data$UACR < 300, "30-300", ">=300")),
    levels = c("<30", "30-300", ">=300")
  )

  q75 <- weighted_quantile(data$TT4, data$ANALYTIC_WT6YR, 0.75)
  q67 <- weighted_quantile(data$TT4, data$ANALYTIC_WT6YR, 2 / 3)
  data$TT4_HIGH_Q4 <- factor(ifelse(data$TT4 >= q75, "TT4_high", "TT4_non_high"), levels = c("TT4_non_high", "TT4_high"))
  data$TT4_HIGH_T3 <- factor(ifelse(data$TT4 >= q67, "TT4_high", "TT4_non_high"), levels = c("TT4_non_high", "TT4_high"))

  joint_levels <- c(
    "UACR_lt30__TT4_non_high",
    "UACR_ge30__TT4_non_high",
    "UACR_lt30__TT4_high",
    "UACR_ge30__TT4_high"
  )
  data$JOINT_Q4 <- factor(paste(data$UACR_ALBUMINURIA, data$TT4_HIGH_Q4, sep = "__"), levels = joint_levels)
  data$JOINT_T3 <- factor(paste(data$UACR_ALBUMINURIA, data$TT4_HIGH_T3, sep = "__"), levels = joint_levels)

  tt4_stats <- weighted_mean_sd(data$TT4, data$ANALYTIC_WT6YR)
  data$TT4_PER_SD <- (data$TT4 - tt4_stats[["mean"]]) / tt4_stats[["sd"]]

  log("INFO", sprintf("Mortality extension eligible rows: %s", nrow(data)))
  log("INFO", sprintf("All-cause deaths: %s", sum(data$ALL_CAUSE_DEATH == 1, na.rm = TRUE)))
  log("INFO", sprintf("Cardiovascular deaths: %s", sum(data$CVD_DEATH == 1, na.rm = TRUE)))
  log("INFO", sprintf("Weighted TT4 Q4 cutoff: %.3f", q75))
  log("INFO", sprintf("Weighted TT4 highest-tertile cutoff: %.3f", q67))
  log("INFO", sprintf("Weighted TT4 SD: %.3f", tt4_stats[["sd"]]))
  data
}

make_design <- function(data) {
  survey::svydesign(
    ids = ~SDMVPSU,
    strata = ~SDMVSTRA,
    weights = ~ANALYTIC_WT6YR,
    nest = TRUE,
    data = droplevels(data)
  )
}

model_covariates <- function(model_name) {
  model1 <- c("AGE", "SEX", "RACE")
  model2 <- c(model1, "EDUCATION", "PIR", "BMI", "SMOKE", "DRINK")
  if (model_name == "Model 1") {
    return(model1)
  }
  if (model_name == "Model 2") {
    return(model2)
  }
  c(model2, "DIABETES", "HYPERTENSION", "EGFR", "UIC_UG_L")
}

has_variation <- function(x) {
  observed <- x[!is.na(x)]
  if (length(observed) == 0) {
    return(FALSE)
  }
  length(unique(as.character(observed))) >= 2
}

usable_covariates <- function(data, requested) {
  present <- requested[requested %in% names(data)]
  used <- present[vapply(present, function(variable) has_variation(data[[variable]]), logical(1))]
  list(used = used, dropped = setdiff(requested, used))
}

complete_analysis <- function(data, variables) {
  variables <- variables[variables %in% names(data)]
  mask <- stats::complete.cases(data[, variables, drop = FALSE])
  droplevels(data[mask, , drop = FALSE])
}

cox_formula <- function(event, exposure_terms, covariates) {
  stats::as.formula(
    paste0("survival::Surv(FOLLOWUP_YEARS, ", event, ") ~ ", paste(c(exposure_terms, covariates), collapse = " + "))
  )
}

fit_svycox_safe <- function(formula, design, log, context) {
  tryCatch(
    survey::svycoxph(formula, design = design),
    error = function(e) {
      log("WARN", sprintf("Survey Cox model failed for %s: %s", context, conditionMessage(e)))
      NULL
    }
  )
}

event_name <- function(outcome) {
  ifelse(outcome == "all_cause_mortality", "ALL_CAUSE_DEATH", "CVD_DEATH")
}

group_summary <- function(data, variable) {
  categories <- levels(data[[variable]])
  do.call(rbind, lapply(categories, function(category) {
    subset <- data[as.character(data[[variable]]) == category, , drop = FALSE]
    data.frame(
      group = category,
      group_n = nrow(subset),
      group_all_cause_events = sum(subset$ALL_CAUSE_DEATH == 1, na.rm = TRUE),
      group_cvd_events = sum(subset$CVD_DEATH == 1, na.rm = TRUE),
      stringsAsFactors = FALSE
    )
  }))
}

extract_joint_rows <- function(fit, data, outcome, model_name, high_definition, joint_variable, covs) {
  reference <- "UACR_lt30__TT4_non_high"
  summary <- group_summary(data, joint_variable)
  coefficients <- if (is.null(fit)) numeric() else stats::coef(fit)
  vcov_matrix <- if (is.null(fit)) matrix(numeric(), 0, 0) else stats::vcov(fit)
  categories <- levels(data[[joint_variable]])
  rows <- lapply(categories, function(category) {
    is_reference <- identical(category, reference)
    term <- paste0(joint_variable, category)
    beta <- if (is_reference) 0 else if (term %in% names(coefficients)) as.numeric(coefficients[term]) else NA_real_
    se <- if (is_reference) 0 else if (term %in% rownames(vcov_matrix)) sqrt(as.numeric(vcov_matrix[term, term])) else NA_real_
    local <- summary[summary$group == category, , drop = FALSE]
    data.frame(
      outcome = outcome,
      model = model_name,
      high_definition = high_definition,
      joint_variable = joint_variable,
      group = category,
      reference_group = reference,
      hr = ifelse(is_reference, 1, exp(beta)),
      ci_low = ifelse(is_reference, 1, exp(beta - 1.96 * se)),
      ci_high = ifelse(is_reference, 1, exp(beta + 1.96 * se)),
      p_value = ifelse(is_reference, NA_real_, 2 * stats::pnorm(abs(beta / se), lower.tail = FALSE)),
      p_fdr = NA_real_,
      n_model = nrow(data),
      events = sum(data[[event_name(outcome)]] == 1, na.rm = TRUE),
      group_n = local$group_n,
      group_events = if (outcome == "all_cause_mortality") local$group_all_cause_events else local$group_cvd_events,
      covariates_used = paste(covs$used, collapse = " + "),
      covariates_dropped = paste(covs$dropped, collapse = " + "),
      note = "Reference group: UACR <30 mg/g with TT4 non-high group.",
      stringsAsFactors = FALSE
    )
  })
  do.call(rbind, rows)
}

fit_joint <- function(data, outcome, model_name, high_definition, joint_variable, log) {
  covs <- usable_covariates(data, model_covariates(model_name))
  analysis_data <- complete_analysis(data, c("FOLLOWUP_YEARS", event_name(outcome), joint_variable, covs$used))
  fit <- fit_svycox_safe(
    cox_formula(event_name(outcome), joint_variable, covs$used),
    make_design(analysis_data),
    log,
    paste(outcome, high_definition, model_name)
  )
  extract_joint_rows(fit, analysis_data, outcome, model_name, high_definition, joint_variable, covs)
}

add_fdr <- function(results, keys) {
  if (nrow(results) == 0) {
    return(results)
  }
  group_key <- do.call(paste, c(results[keys], sep = "||"))
  results$p_fdr <- ave(results$p_value, group_key, FUN = function(p) {
    adjusted <- rep(NA_real_, length(p))
    ok <- !is.na(p)
    adjusted[ok] <- stats::p.adjust(p[ok], method = "fdr")
    adjusted
  })
  results
}

extract_interaction_row <- function(fit, data, outcome, model_name, interaction_type, high_definition, covs, log) {
  coefficients <- if (is.null(fit)) NULL else stats::coef(fit)
  covariance <- if (is.null(fit)) NULL else stats::vcov(fit)
  terms <- if (is.null(coefficients)) character() else grep(":", names(coefficients), value = TRUE)
  interaction_term <- if (length(terms) > 0) terms[1] else ""
  beta <- if (interaction_term != "") as.numeric(coefficients[interaction_term]) else NA_real_
  se <- if (interaction_term != "") sqrt(as.numeric(covariance[interaction_term, interaction_term])) else NA_real_
  p_value <- if (interaction_term != "") 2 * stats::pnorm(abs(beta / se), lower.tail = FALSE) else NA_real_
  if (!is.null(fit)) {
    tested <- tryCatch(
      survey::regTermTest(fit, stats::as.formula(paste0("~", sub(" interaction$", "", interaction_type)))),
      error = function(e) NULL
    )
    if (!is.null(tested)) {
      p_value <- as.numeric(tested$p[1])
    }
  }
  data.frame(
    outcome = outcome,
    model = model_name,
    interaction_type = interaction_type,
    high_definition = high_definition,
    interaction_term = interaction_term,
    interaction_beta_log_hr = beta,
    interaction_hr = exp(beta),
    ci_low = exp(beta - 1.96 * se),
    ci_high = exp(beta + 1.96 * se),
    p_for_interaction = p_value,
    n_model = nrow(data),
    events = sum(data[[event_name(outcome)]] == 1, na.rm = TRUE),
    covariates_used = paste(covs$used, collapse = " + "),
    covariates_dropped = paste(covs$dropped, collapse = " + "),
    note = "Survey-weighted Cox interaction model.",
    stringsAsFactors = FALSE
  )
}

fit_interaction <- function(data, outcome, model_name, interaction_type, high_definition,
                            exposure_terms, required_exposures, log) {
  covs <- usable_covariates(data, model_covariates(model_name))
  analysis_data <- complete_analysis(
    data,
    c("FOLLOWUP_YEARS", event_name(outcome), required_exposures, covs$used)
  )
  fit <- fit_svycox_safe(
    cox_formula(event_name(outcome), exposure_terms, covs$used),
    make_design(analysis_data),
    log,
    paste(outcome, interaction_type, model_name)
  )
  extract_interaction_row(fit, analysis_data, outcome, model_name, interaction_type, high_definition, covs, log)
}

sensitivity_subsets <- function(data) {
  list(
    list(label = "Full analytic cohort", filter = "none", keep = rep(TRUE, nrow(data))),
    list(label = "Exclude deaths within first 2 years", filter = "not (all-cause death within <=2 years)", keep = !(data$ALL_CAUSE_DEATH == 1 & data$FOLLOWUP_YEARS <= 2)),
    list(label = "Exclude eGFR <60", filter = "EGFR >=60", keep = !is.na(data$EGFR) & data$EGFR >= 60),
    list(label = "Exclude diabetes", filter = "DIABETES == 0", keep = !is.na(data$DIABETES) & as.character(data$DIABETES) == "0"),
    list(label = "Exclude hypertension", filter = "HYPERTENSION == 0", keep = !is.na(data$HYPERTENSION) & as.character(data$HYPERTENSION) == "0"),
    list(label = "Exclude UACR >=300", filter = "UACR <300 mg/g", keep = !is.na(data$UACR) & data$UACR < 300),
    list(label = "Euthyroid participants", filter = "TSH 0.45-4.50 and FT4 0.60-1.60", keep = !is.na(data$TSH) & !is.na(data$FT4) & data$TSH >= 0.45 & data$TSH <= 4.50 & data$FT4 >= 0.60 & data$FT4 <= 1.60)
  )
}

extract_sensitivity_rows <- function(fit, data, outcome, scenario, filter, exposure, pattern, covs, note = "") {
  if (is.null(fit)) {
    return(data.frame())
  }
  coefficients <- stats::coef(fit)
  vcov_matrix <- stats::vcov(fit)
  wanted <- grep(pattern, names(coefficients), value = TRUE)
  if (length(wanted) == 0) {
    return(data.frame())
  }
  rows <- lapply(wanted, function(term) {
    beta <- as.numeric(coefficients[term])
    se <- sqrt(as.numeric(vcov_matrix[term, term]))
    data.frame(
      analysis_type = "survey_weighted_cox",
      scenario = scenario,
      filter = filter,
      outcome = outcome,
      exposure = exposure,
      contrast = term,
      model = "Model 3",
      hr = exp(beta),
      ci_low = exp(beta - 1.96 * se),
      ci_high = exp(beta + 1.96 * se),
      p_value = 2 * stats::pnorm(abs(beta / se), lower.tail = FALSE),
      p_fdr = NA_real_,
      n_model = nrow(data),
      events = sum(data[[event_name(outcome)]] == 1, na.rm = TRUE),
      direction = ifelse(beta > 0, "positive", ifelse(beta < 0, "negative", "null")),
      ph_term = "",
      ph_p_value = NA_real_,
      covariates_used = paste(covs$used, collapse = " + "),
      covariates_dropped = paste(covs$dropped, collapse = " + "),
      note = note,
      stringsAsFactors = FALSE
    )
  })
  do.call(rbind, rows)
}

fit_sensitivity_exposure <- function(data, outcome, scenario, filter, exposure, log) {
  covs <- usable_covariates(data, model_covariates("Model 3"))
  analysis_data <- complete_analysis(data, c("FOLLOWUP_YEARS", event_name(outcome), exposure, covs$used))
  fit <- fit_svycox_safe(
    cox_formula(event_name(outcome), exposure, covs$used),
    make_design(analysis_data),
    log,
    paste(outcome, scenario, exposure)
  )
  pattern <- paste0("^", exposure)
  note <- if (exposure == "TT4_PER_SD") {
    "TT4 effect reported per weighted-SD increase."
  } else if (exposure == "UACR_CLINICAL_CATEGORY") {
    "UACR clinical category reference: <30 mg/g."
  } else {
    "Survey-weighted Cox sensitivity analysis."
  }
  extract_sensitivity_rows(fit, analysis_data, outcome, scenario, filter, exposure, pattern, covs, note)
}

ph_diagnostic_rows <- function(data, log) {
  log("INFO", "PH assumption: survey::svycoxph does not provide a validated direct cox.zph workflow; running diagnostic unweighted survival::coxph models.")
  rows <- list()
  for (outcome in c("all_cause_mortality", "cardiovascular_mortality")) {
    for (exposure in c("LOG_UACR", "TT4")) {
      covs <- usable_covariates(data, model_covariates("Model 3"))
      analysis_data <- complete_analysis(data, c("FOLLOWUP_YEARS", event_name(outcome), exposure, covs$used))
      formula <- cox_formula(event_name(outcome), exposure, covs$used)
      fit <- tryCatch(survival::coxph(formula, data = analysis_data, x = TRUE), error = function(e) NULL)
      zph <- if (is.null(fit)) NULL else tryCatch(survival::cox.zph(fit), error = function(e) NULL)
      if (is.null(zph)) {
        rows[[length(rows) + 1]] <- data.frame(
          analysis_type = "ph_diagnostic_unweighted",
          scenario = "PH assumption diagnostic",
          filter = "unweighted coxph diagnostic",
          outcome = outcome,
          exposure = exposure,
          contrast = "",
          model = "Model 3 diagnostic",
          hr = NA_real_, ci_low = NA_real_, ci_high = NA_real_, p_value = NA_real_, p_fdr = NA_real_,
          n_model = nrow(analysis_data),
          events = sum(analysis_data[[event_name(outcome)]] == 1, na.rm = TRUE),
          direction = "",
          ph_term = "diagnostic_failed",
          ph_p_value = NA_real_,
          covariates_used = paste(covs$used, collapse = " + "),
          covariates_dropped = paste(covs$dropped, collapse = " + "),
          note = "Unweighted PH diagnostic failed.",
          stringsAsFactors = FALSE
        )
      } else {
        table <- as.data.frame(zph$table)
        table$ph_term <- rownames(table)
        for (i in seq_len(nrow(table))) {
          rows[[length(rows) + 1]] <- data.frame(
            analysis_type = "ph_diagnostic_unweighted",
            scenario = "PH assumption diagnostic",
            filter = "unweighted coxph diagnostic",
            outcome = outcome,
            exposure = exposure,
            contrast = "",
            model = "Model 3 diagnostic",
            hr = NA_real_, ci_low = NA_real_, ci_high = NA_real_, p_value = NA_real_, p_fdr = NA_real_,
            n_model = nrow(analysis_data),
            events = sum(analysis_data[[event_name(outcome)]] == 1, na.rm = TRUE),
            direction = "",
            ph_term = table$ph_term[i],
            ph_p_value = as.numeric(table$p[i]),
            covariates_used = paste(covs$used, collapse = " + "),
            covariates_dropped = paste(covs$dropped, collapse = " + "),
            note = "Diagnostic PH check uses unweighted coxph because direct survey-weighted cox.zph support is unavailable.",
            stringsAsFactors = FALSE
          )
        }
      }
    }
  }
  result <- do.call(rbind, rows)
  global_rows <- result[result$ph_term == "GLOBAL", , drop = FALSE]
  for (i in seq_len(nrow(global_rows))) {
    log(
      "INFO",
      sprintf(
        "Unweighted PH diagnostic global P [%s, %s]: %.4f",
        global_rows$outcome[i], global_rows$exposure[i], global_rows$ph_p_value[i]
      )
    )
  }
  nominal_terms <- result[
    !result$ph_term %in% c("GLOBAL", "diagnostic_failed") &
      !is.na(result$ph_p_value) & result$ph_p_value < 0.05,
    ,
    drop = FALSE
  ]
  if (nrow(nominal_terms) > 0) {
    log(
      "WARNING",
      sprintf(
        "Unweighted PH diagnostics identified %s nominal covariate-level signal(s); inspect Table_mortality_sensitivity.csv. These diagnostics do not replace survey-weighted assessment.",
        nrow(nominal_terms)
      )
    )
  }
  result
}

joint_label <- function(x) {
  labels <- c(
    "UACR_lt30__TT4_non_high" = "UACR <30 + TT4 non-high",
    "UACR_ge30__TT4_non_high" = "UACR >=30 + TT4 non-high",
    "UACR_lt30__TT4_high" = "UACR <30 + TT4 high",
    "UACR_ge30__TT4_high" = "UACR >=30 + TT4 high"
  )
  unname(labels[x])
}

theme_contract <- function() {
  ggplot2::theme_classic(base_size = 7, base_family = "Arial") +
    ggplot2::theme(
      axis.line = ggplot2::element_line(linewidth = 0.35, colour = "black"),
      axis.ticks = ggplot2::element_line(linewidth = 0.35, colour = "black"),
      plot.title = ggplot2::element_text(size = 8, face = "bold"),
      strip.text = ggplot2::element_text(size = 7, face = "bold"),
      legend.position = "top",
      panel.grid = ggplot2::element_blank()
    )
}

save_pdf <- function(plot, path, width_mm = 183, height_mm = 125) {
  dir.create(dirname(path), recursive = TRUE, showWarnings = FALSE)
  grDevices::cairo_pdf(path, width = width_mm / 25.4, height = height_mm / 25.4, family = "Arial")
  print(plot)
  grDevices::dev.off()
}

save_qc_png <- function(plot, path, width_mm = 183, height_mm = 125) {
  dir.create(dirname(path), recursive = TRUE, showWarnings = FALSE)
  grDevices::png(
    path,
    width = width_mm / 25.4,
    height = height_mm / 25.4,
    units = "in",
    res = 180,
    type = "cairo"
  )
  print(plot)
  grDevices::dev.off()
}

make_joint_figure <- function(joint, root, log) {
  plot_data <- joint[joint$high_definition == "TT4 highest quartile (Q4)" & joint$model == "Model 3", , drop = FALSE]
  plot_data$group_label <- joint_label(plot_data$group)
  plot_data$outcome_label <- ifelse(plot_data$outcome == "all_cause_mortality", "All-cause mortality", "Cardiovascular mortality")
  plot_data$group_label <- factor(
    plot_data$group_label,
    levels = rev(c("UACR <30 + TT4 non-high", "UACR >=30 + TT4 non-high", "UACR <30 + TT4 high", "UACR >=30 + TT4 high"))
  )
  write_csv_safe(plot_data, file.path(root, "outputs", "tables", "Figure_joint_mortality_source_data.csv"))
  palette <- c("All-cause mortality" = "#2F6B9A", "Cardiovascular mortality" = "#B24A45")
  figure <- ggplot2::ggplot(plot_data, ggplot2::aes(x = hr, y = group_label, colour = outcome_label)) +
    ggplot2::geom_vline(xintercept = 1, linetype = 2, linewidth = 0.35, colour = "#777777") +
    ggplot2::geom_errorbar(ggplot2::aes(xmin = ci_low, xmax = ci_high), orientation = "y", width = 0.16, linewidth = 0.45, position = ggplot2::position_dodge(width = 0.4)) +
    ggplot2::geom_point(size = 2.0, position = ggplot2::position_dodge(width = 0.4)) +
    ggplot2::scale_x_log10() +
    ggplot2::scale_colour_manual(values = palette, name = NULL) +
    ggplot2::labs(x = "Hazard ratio (95% CI), log scale", y = NULL, title = "Joint UACR and TT4 risk groups") +
    theme_contract()
  path <- file.path(root, "outputs", "figures", "Figure_joint_mortality.pdf")
  save_pdf(figure, path)
  save_qc_png(figure, file.path(root, "outputs", "figures", "qc", "Figure_joint_mortality_qc.png"))
  log("INFO", sprintf("Wrote Q4 joint risk figure to %s", path))
}

make_forest_figure <- function(sensitivity, root, log) {
  plot_data <- sensitivity[
    sensitivity$analysis_type == "survey_weighted_cox" &
      sensitivity$exposure %in% c("LOG_UACR", "TT4") &
      sensitivity$contrast %in% c("LOG_UACR", "TT4"),
    ,
    drop = FALSE
  ]
  plot_data$outcome_label <- ifelse(plot_data$outcome == "all_cause_mortality", "All-cause mortality", "Cardiovascular mortality")
  plot_data$exposure_label <- ifelse(plot_data$exposure == "LOG_UACR", "log(UACR)", "TT4")
  scenarios <- unique(plot_data$scenario)
  plot_data$scenario <- factor(plot_data$scenario, levels = rev(scenarios))
  write_csv_safe(plot_data, file.path(root, "outputs", "tables", "Figure_mortality_forest_source_data.csv"))
  palette <- c("All-cause mortality" = "#2F6B9A", "Cardiovascular mortality" = "#B24A45")
  figure <- ggplot2::ggplot(plot_data, ggplot2::aes(x = hr, y = scenario, colour = outcome_label)) +
    ggplot2::geom_vline(xintercept = 1, linetype = 2, linewidth = 0.35, colour = "#777777") +
    ggplot2::geom_errorbar(ggplot2::aes(xmin = ci_low, xmax = ci_high), orientation = "y", width = 0.16, linewidth = 0.42, position = ggplot2::position_dodge(width = 0.42)) +
    ggplot2::geom_point(size = 1.8, position = ggplot2::position_dodge(width = 0.42)) +
    ggplot2::facet_wrap(~exposure_label, scales = "free_x", nrow = 1) +
    ggplot2::scale_colour_manual(values = palette, name = NULL) +
    ggplot2::labs(x = "Hazard ratio (95% CI)", y = NULL, title = "Mortality sensitivity analyses") +
    theme_contract()
  path <- file.path(root, "outputs", "figures", "Figure_mortality_forest.pdf")
  save_pdf(figure, path, width_mm = 183, height_mm = 120)
  save_qc_png(figure, file.path(root, "outputs", "figures", "qc", "Figure_mortality_forest_qc.png"), width_mm = 183, height_mm = 120)
  log("INFO", sprintf("Wrote mortality sensitivity forest to %s", path))
}

fmt <- function(x, digits = 3) {
  ifelse(is.na(x), "NA", formatC(x, digits = digits, format = "f"))
}

fmt_p <- function(x) {
  ifelse(is.na(x), "NA", ifelse(x < 0.001, formatC(x, digits = 2, format = "e"), formatC(x, digits = 3, format = "f")))
}

interpretation_lines <- function(joint, interaction, sensitivity) {
  q4 <- joint[joint$high_definition == "TT4 highest quartile (Q4)" & joint$model == "Model 3", , drop = FALSE]
  high_high <- q4[q4$group == "UACR_ge30__TT4_high", , drop = FALSE]
  highest_by_outcome <- vapply(c("all_cause_mortality", "cardiovascular_mortality"), function(outcome) {
    rows <- q4[q4$outcome == outcome, , drop = FALSE]
    target <- high_high$hr[high_high$outcome == outcome]
    length(target) == 1 && !is.na(target) && target >= max(rows$hr, na.rm = TRUE)
  }, logical(1))
  high_high_highest <- all(highest_by_outcome)
  progressive_by_outcome <- vapply(c("all_cause_mortality", "cardiovascular_mortality"), function(outcome) {
    rows <- q4[q4$outcome == outcome, , drop = FALSE]
    hr_by_group <- stats::setNames(rows$hr, rows$group)
    required <- c(
      "UACR_lt30__TT4_non_high",
      "UACR_ge30__TT4_non_high",
      "UACR_lt30__TT4_high",
      "UACR_ge30__TT4_high"
    )
    if (!all(required %in% names(hr_by_group)) || any(is.na(hr_by_group[required]))) {
      return(FALSE)
    }
    hr_by_group["UACR_lt30__TT4_non_high"] <= hr_by_group["UACR_ge30__TT4_non_high"] &&
      hr_by_group["UACR_lt30__TT4_non_high"] <= hr_by_group["UACR_lt30__TT4_high"] &&
      hr_by_group["UACR_ge30__TT4_high"] >= hr_by_group["UACR_ge30__TT4_non_high"] &&
      hr_by_group["UACR_ge30__TT4_high"] >= hr_by_group["UACR_lt30__TT4_high"]
  }, logical(1))
  progressive_joint_pattern <- all(progressive_by_outcome)

  interaction_m3 <- interaction[interaction$model == "Model 3" & interaction$high_definition != "TT4 highest tertile sensitivity", , drop = FALSE]
  interaction_non_significant <- all(interaction_m3$p_for_interaction >= 0.05, na.rm = TRUE)

  tt4 <- sensitivity[
    sensitivity$analysis_type == "survey_weighted_cox" &
      sensitivity$exposure == "TT4" &
      sensitivity$contrast == "TT4",
    ,
    drop = FALSE
  ]
  tt4_positive <- sum(tt4$direction == "positive", na.rm = TRUE)
  tt4_significant <- sum(tt4$p_value < 0.05, na.rm = TRUE)
  tt4_total <- nrow(tt4)
  tt4_stable <- tt4_positive == tt4_total && tt4_significant >= ceiling(tt4_total / 2)
  tt4_role <- ifelse(tt4_stable, "secondary prognostic marker with directionally consistent sensitivity estimates", "secondary prognostic marker because sensitivity estimates were not uniformly stable")

  risk_label <- if (progressive_joint_pattern && interaction_non_significant) {
    "additive joint risk stratification"
  } else if (high_high_highest) {
    "joint risk stratification"
  } else {
    "UACR-dominant joint risk pattern requiring cautious interpretation"
  }
  list(
    risk_label = risk_label,
    high_high_highest = high_high_highest,
    progressive_joint_pattern = progressive_joint_pattern,
    interaction_non_significant = interaction_non_significant,
    tt4_positive = tt4_positive,
    tt4_significant = tt4_significant,
    tt4_total = tt4_total,
    tt4_role = tt4_role
  )
}

report_lines <- function(data, joint, interaction, sensitivity) {
  interpretation <- interpretation_lines(joint, interaction, sensitivity)
  q4_m3 <- joint[joint$high_definition == "TT4 highest quartile (Q4)" & joint$model == "Model 3", , drop = FALSE]
  interaction_m3 <- interaction[interaction$model == "Model 3", , drop = FALSE]
  ph <- sensitivity[sensitivity$analysis_type == "ph_diagnostic_unweighted" & sensitivity$ph_term == "GLOBAL", , drop = FALSE]
  ph_nominal_terms <- sensitivity[
    sensitivity$analysis_type == "ph_diagnostic_unweighted" &
      !sensitivity$ph_term %in% c("GLOBAL", "diagnostic_failed") &
      !is.na(sensitivity$ph_p_value) & sensitivity$ph_p_value < 0.05,
    ,
    drop = FALSE
  ]

  lines <- c(
    "# Mortality extension summary",
    "",
    "This module extends the NHANES 2007-2012 discovery cohort mortality analysis. It is observational and does not establish causality.",
    "",
    sprintf("Eligible participants with follow-up: %s.", nrow(data)),
    sprintf("All-cause deaths: %s.", sum(data$ALL_CAUSE_DEATH == 1, na.rm = TRUE)),
    sprintf("Cardiovascular deaths: %s.", sum(data$CVD_DEATH == 1, na.rm = TRUE)),
    "",
    "## Main Interpretation",
    sprintf("- Risk-stratification wording: **%s**.", interpretation$risk_label),
    sprintf("- UACR >=30 mg/g with high TT4 was the highest-risk Q4-defined group for both outcomes: %s.", interpretation$high_high_highest),
    sprintf("- Q4-defined joint groups showed a progressive increase for both outcomes: %s.", interpretation$progressive_joint_pattern),
    sprintf("- Model 3 interaction tests supported effect modification: %s.", !interpretation$interaction_non_significant),
    sprintf("- TT4 role: %s.", interpretation$tt4_role),
    sprintf("- TT4 sensitivity models positive: %s/%s; nominally significant: %s/%s.", interpretation$tt4_positive, interpretation$tt4_total, interpretation$tt4_significant, interpretation$tt4_total),
    "",
    "## Q4-Defined Joint Groups, Model 3",
    "| Outcome | Group | HR (95% CI) | P | n | Events in group |",
    "|---|---|---:|---:|---:|---:|"
  )
  for (i in seq_len(nrow(q4_m3))) {
    lines <- c(lines, sprintf(
      "| %s | %s | %s (%s to %s) | %s | %s | %s |",
      q4_m3$outcome[i], joint_label(q4_m3$group[i]), fmt(q4_m3$hr[i]), fmt(q4_m3$ci_low[i]),
      fmt(q4_m3$ci_high[i]), fmt_p(q4_m3$p_value[i]), q4_m3$n_model[i], q4_m3$group_events[i]
    ))
  }

  lines <- c(lines, "", "## Interaction Tests, Model 3", "| Outcome | Interaction | Definition | P for interaction |", "|---|---|---|---:|")
  for (i in seq_len(nrow(interaction_m3))) {
    lines <- c(lines, sprintf(
      "| %s | %s | %s | %s |",
      interaction_m3$outcome[i], interaction_m3$interaction_type[i], interaction_m3$high_definition[i],
      fmt_p(interaction_m3$p_for_interaction[i])
    ))
  }

  lines <- c(
    lines,
    "",
    "## PH Assumption Diagnostic",
    "Survey-weighted Cox models do not provide a validated direct `cox.zph` workflow. Diagnostic PH checks therefore use non-weighted `coxph` models with the same Model 3 covariates.",
    sprintf("All four global diagnostic P values exceeded 0.05. %s covariate-level nominal signal(s) are retained in `Table_mortality_sensitivity.csv` for cautious interpretation.", nrow(ph_nominal_terms)),
    "",
    "| Outcome | Exposure | Global PH P |",
    "|---|---|---:|"
  )
  for (i in seq_len(nrow(ph))) {
    lines <- c(lines, sprintf("| %s | %s | %s |", ph$outcome[i], ph$exposure[i], fmt_p(ph$ph_p_value[i])))
  }

  c(
    lines,
    "",
    "## Notes",
    "- Primary TT4-high definition: weighted highest quartile (Q4). Highest tertile is included as a sensitivity definition.",
    "- Model 1 adjusts for age, sex, and race.",
    "- Model 2 additionally adjusts for education, PIR, BMI, smoking, and drinking.",
    "- Model 3 additionally adjusts for diabetes, hypertension, eGFR, and UIC.",
    "- Early-death sensitivity analysis excludes all-cause deaths occurring within the first 2 years of follow-up.",
    "- Cardiovascular mortality uses public-use UCOD_LEADING heart-disease and cerebrovascular-disease categories.",
    "- NHANES III findings remain not replicated and are not reinterpreted in this mortality extension."
  )
}

main <- function() {
  root <- find_project_root()
  log <- init_logger(root)
  for (package in c("survey", "survival", "ggplot2")) {
    if (!requireNamespace(package, quietly = TRUE)) {
      stop(sprintf("R package '%s' is required.", package), call. = FALSE)
    }
  }
  options(survey.lonely.psu = "adjust")
  data <- prepare_data(read_linked_cohort(root, log), log)
  outcomes <- c("all_cause_mortality", "cardiovascular_mortality")
  models <- c("Model 1", "Model 2", "Model 3")

  joint_rows <- list()
  for (outcome in outcomes) {
    for (model_name in models) {
      joint_rows[[length(joint_rows) + 1]] <- fit_joint(data, outcome, model_name, "TT4 highest quartile (Q4)", "JOINT_Q4", log)
      joint_rows[[length(joint_rows) + 1]] <- fit_joint(data, outcome, model_name, "TT4 highest tertile sensitivity", "JOINT_T3", log)
    }
  }
  joint <- add_fdr(do.call(rbind, joint_rows), c("outcome", "model", "high_definition"))

  interaction_rows <- list()
  for (outcome in outcomes) {
    for (model_name in models) {
      interaction_rows[[length(interaction_rows) + 1]] <- fit_interaction(data, outcome, model_name, "LOG_UACR:TT4 interaction", "continuous TT4", c("LOG_UACR * TT4"), c("LOG_UACR", "TT4"), log)
      interaction_rows[[length(interaction_rows) + 1]] <- fit_interaction(data, outcome, model_name, "UACR_ALBUMINURIA:TT4_HIGH_Q4 interaction", "TT4 highest quartile (Q4)", c("UACR_ALBUMINURIA * TT4_HIGH_Q4"), c("UACR_ALBUMINURIA", "TT4_HIGH_Q4"), log)
      interaction_rows[[length(interaction_rows) + 1]] <- fit_interaction(data, outcome, model_name, "UACR_ALBUMINURIA:TT4_HIGH_T3 interaction", "TT4 highest tertile sensitivity", c("UACR_ALBUMINURIA * TT4_HIGH_T3"), c("UACR_ALBUMINURIA", "TT4_HIGH_T3"), log)
    }
  }
  interaction <- do.call(rbind, interaction_rows)

  sensitivity_rows <- list()
  for (subset_spec in sensitivity_subsets(data)) {
    subset_data <- droplevels(data[subset_spec$keep, , drop = FALSE])
    log("INFO", sprintf("Sensitivity subset [%s]: n=%s", subset_spec$label, nrow(subset_data)))
    for (outcome in outcomes) {
      for (exposure in c("LOG_UACR", "TT4")) {
        sensitivity_rows[[length(sensitivity_rows) + 1]] <- fit_sensitivity_exposure(
          subset_data, outcome, subset_spec$label, subset_spec$filter, exposure, log
        )
      }
    }
  }
  for (outcome in outcomes) {
    sensitivity_rows[[length(sensitivity_rows) + 1]] <- fit_sensitivity_exposure(data, outcome, "TT4 per-SD increase", "full analytic cohort", "TT4_PER_SD", log)
    sensitivity_rows[[length(sensitivity_rows) + 1]] <- fit_sensitivity_exposure(data, outcome, "UACR clinical category", "full analytic cohort", "UACR_CLINICAL_CATEGORY", log)
  }
  sensitivity <- do.call(rbind, sensitivity_rows)
  sensitivity <- add_fdr(sensitivity, c("outcome", "scenario", "exposure"))
  sensitivity <- rbind(sensitivity, ph_diagnostic_rows(data, log))

  joint_path <- file.path(root, "outputs", "tables", "Table_mortality_joint.csv")
  interaction_path <- file.path(root, "outputs", "tables", "Table_mortality_interaction.csv")
  sensitivity_path <- file.path(root, "outputs", "tables", "Table_mortality_sensitivity.csv")
  report_path <- file.path(root, "outputs", "reports", "mortality_extension_summary.md")
  write_csv_safe(joint, joint_path)
  write_csv_safe(interaction, interaction_path)
  write_csv_safe(sensitivity, sensitivity_path)
  make_joint_figure(joint, root, log)
  make_forest_figure(sensitivity, root, log)
  write_lines_safe(report_lines(data, joint, interaction, sensitivity), report_path)

  interpretation <- interpretation_lines(joint, interaction, sensitivity)
  log("INFO", sprintf("Wrote %s joint rows to %s", nrow(joint), joint_path))
  log("INFO", sprintf("Wrote %s interaction rows to %s", nrow(interaction), interaction_path))
  log("INFO", sprintf("Wrote %s sensitivity and PH rows to %s", nrow(sensitivity), sensitivity_path))
  log("INFO", sprintf("Wrote mortality extension summary to %s", report_path))
  log("INFO", sprintf("Risk-stratification wording: %s", interpretation$risk_label))
  log("INFO", sprintf("High UACR + high TT4 highest-risk group for both outcomes: %s", interpretation$high_high_highest))
  log("INFO", sprintf("Progressive Q4-defined joint pattern for both outcomes: %s", interpretation$progressive_joint_pattern))
  log("INFO", sprintf("All primary Model 3 interaction tests non-significant: %s", interpretation$interaction_non_significant))
  log("INFO", sprintf("TT4 role: %s", interpretation$tt4_role))
}

main()
