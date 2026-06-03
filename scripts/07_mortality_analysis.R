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
  log_file <- file.path(log_dir, "07_mortality_analysis.log")
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

read_mortality_cohort <- function(root, log) {
  path <- file.path(root, "data", "processed", "discovery_nhanes_2007_2012_mortality.csv")
  if (!file.exists(path)) {
    stop(sprintf("Linked mortality cohort not found: %s. Run python scripts/07_build_mortality_linkage.py first.", path), call. = FALSE)
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

prepare_data <- function(data, log) {
  numeric_vars <- c(
    "AGE", "PIR", "BMI", "EGFR", "UIC_UG_L", "LOG_UACR", "UACR", "TT4",
    "ANALYTIC_WT6YR", "SDMVPSU", "SDMVSTRA", "ELIGSTAT", "MORTSTAT",
    "UCOD_LEADING", "PERMTH_EXM", "ALL_CAUSE_DEATH", "CVD_DEATH"
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
  log("INFO", sprintf("Mortality analysis rows after eligibility and follow-up checks: %s", nrow(data)))
  log("INFO", sprintf("All-cause deaths: %s", sum(data$ALL_CAUSE_DEATH == 1, na.rm = TRUE)))
  log("INFO", sprintf("Cardiovascular deaths: %s", sum(data$CVD_DEATH == 1, na.rm = TRUE)))
  data
}

weighted_quantile <- function(x, weights, probs) {
  keep <- !is.na(x) & !is.na(weights) & weights > 0
  x <- x[keep]
  weights <- weights[keep]
  order_index <- order(x)
  x <- x[order_index]
  weights <- weights[order_index]
  cumulative <- cumsum(weights) / sum(weights)
  vapply(probs, function(prob) x[which(cumulative >= prob)[1]], numeric(1))
}

add_joint_categories <- function(data, log) {
  breaks <- weighted_quantile(data$TT4, data$ANALYTIC_WT6YR, c(0, 1 / 3, 2 / 3, 1))
  breaks[1] <- -Inf
  breaks[length(breaks)] <- Inf
  if (length(unique(breaks)) != 4) {
    stop("Unable to create distinct weighted TT4 tertile breaks.", call. = FALSE)
  }
  data$TT4_TERTILE <- cut(data$TT4, breaks = breaks, include.lowest = TRUE, labels = c("T1", "T2", "T3"))
  clinical <- ifelse(
    data$UACR < 30,
    "UACR_lt30",
    ifelse(data$UACR < 300, "UACR_30_299", "UACR_ge300")
  )
  data$JOINT_CATEGORY <- factor(
    paste(clinical, data$TT4_TERTILE, sep = "__"),
    levels = c(
      "UACR_lt30__T1", "UACR_lt30__T2", "UACR_lt30__T3",
      "UACR_30_299__T1", "UACR_30_299__T2", "UACR_30_299__T3",
      "UACR_ge300__T1", "UACR_ge300__T2", "UACR_ge300__T3"
    )
  )
  log("INFO", sprintf("Weighted TT4 tertile cut points: %s", paste(formatC(breaks[2:3], digits = 3, format = "f"), collapse = ", ")))
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
  h1 <- c("AGE", "SEX", "RACE")
  if (model_name == "H1") {
    return(h1)
  }
  c(h1, "EDUCATION", "PIR", "BMI", "SMOKE", "DRINK", "DIABETES", "HYPERTENSION", "EGFR", "UIC_UG_L")
}

formula_for <- function(event, exposure, covariates) {
  stats::as.formula(
    paste0("survival::Surv(FOLLOWUP_YEARS, ", event, ") ~ ", paste(c(exposure, covariates), collapse = " + "))
  )
}

fit_cox_safe <- function(formula, design, log, context) {
  tryCatch(
    survey::svycoxph(formula, design = design),
    error = function(e) {
      log("WARN", sprintf("Cox model failed for %s: %s", context, conditionMessage(e)))
      NULL
    }
  )
}

complete_design <- function(data, event, exposure, covariates) {
  variables <- c("FOLLOWUP_YEARS", event, exposure, covariates)
  mask <- stats::complete.cases(data[, variables, drop = FALSE])
  subset <- droplevels(data[mask, , drop = FALSE])
  list(data = subset, design = make_design(subset))
}

extract_cox_rows <- function(fit, pattern, outcome, exposure, model_name, data, note) {
  if (is.null(fit)) {
    return(data.frame())
  }
  coefficients <- stats::coef(fit)
  vcov_matrix <- stats::vcov(fit)
  wanted <- grep(pattern, names(coefficients), value = TRUE)
  if (length(wanted) == 0) {
    return(data.frame())
  }
  event_variable <- if (outcome == "all_cause_mortality") "ALL_CAUSE_DEATH" else "CVD_DEATH"
  rows <- lapply(wanted, function(term) {
    beta <- as.numeric(coefficients[term])
    se <- sqrt(as.numeric(vcov_matrix[term, term]))
    z <- beta / se
    data.frame(
      outcome = outcome,
      exposure = exposure,
      contrast = term,
      model = model_name,
      beta_log_hr = beta,
      hr = exp(beta),
      ci_low = exp(beta - 1.96 * se),
      ci_high = exp(beta + 1.96 * se),
      p_value = 2 * stats::pnorm(abs(z), lower.tail = FALSE),
      p_fdr = NA_real_,
      n_model = nrow(data),
      events = sum(data[[event_variable]] == 1, na.rm = TRUE),
      weighted_population_estimate = sum(data$ANALYTIC_WT6YR, na.rm = TRUE),
      note = note,
      stringsAsFactors = FALSE
    )
  })
  do.call(rbind, rows)
}

fit_one <- function(data, outcome, event, exposure, model_name, log) {
  covariates <- model_covariates(model_name)
  ad <- complete_design(data, event, exposure, covariates)
  fit <- fit_cox_safe(
    formula_for(event, exposure, covariates),
    ad$design,
    log,
    paste(outcome, exposure, model_name)
  )
  pattern <- if (exposure == "LOG_UACR") {
    "^LOG_UACR$"
  } else if (exposure == "TT4") {
    "^TT4$"
  } else {
    "^JOINT_CATEGORY"
  }
  extract_cox_rows(
    fit,
    pattern,
    outcome,
    exposure,
    model_name,
    ad$data,
    ifelse(
      exposure == "JOINT_CATEGORY",
      "Joint category reference: UACR <30 mg/g and TT4 tertile T1.",
      "Survey-weighted Cox proportional hazards model."
    )
  )
}

add_fdr <- function(results) {
  if (nrow(results) == 0) {
    return(results)
  }
  key <- paste(results$outcome, results$model, results$exposure, sep = "||")
  results$p_fdr <- ave(results$p_value, key, FUN = function(p) stats::p.adjust(p, method = "fdr"))
  results
}

joint_labels <- function(x) {
  x <- sub("^JOINT_CATEGORY", "", x)
  x <- gsub("UACR_lt30", "UACR <30", x, fixed = TRUE)
  x <- gsub("UACR_30_299", "UACR 30-299", x, fixed = TRUE)
  x <- gsub("UACR_ge300", "UACR >=300", x, fixed = TRUE)
  gsub("__", " / ", x, fixed = TRUE)
}

make_joint_plot <- function(results, root, log) {
  plot_data <- results[
    results$exposure == "JOINT_CATEGORY" &
      results$model == "Full",
    ,
    drop = FALSE
  ]
  plot_data$label <- joint_labels(plot_data$contrast)
  plot_data$outcome_label <- ifelse(plot_data$outcome == "all_cause_mortality", "All-cause mortality", "Cardiovascular mortality")
  plot_data$label <- factor(plot_data$label, levels = rev(unique(plot_data$label)))

  source_path <- file.path(root, "outputs", "tables", "Figure_joint_mortality_source_data.csv")
  write_csv_safe(plot_data, source_path)

  palette <- c("All-cause mortality" = "#2F6B9A", "Cardiovascular mortality" = "#B24A45")
  figure <- ggplot2::ggplot(plot_data, ggplot2::aes(x = hr, y = label, colour = outcome_label)) +
    ggplot2::geom_vline(xintercept = 1, linewidth = 0.35, linetype = 2, colour = "#777777") +
    ggplot2::geom_errorbar(ggplot2::aes(xmin = ci_low, xmax = ci_high), width = 0.16, linewidth = 0.45, orientation = "y", position = ggplot2::position_dodge(width = 0.35)) +
    ggplot2::geom_point(size = 1.9, position = ggplot2::position_dodge(width = 0.35)) +
    ggplot2::scale_x_log10() +
    ggplot2::scale_colour_manual(values = palette, name = NULL) +
    ggplot2::labs(
      x = "Hazard ratio (95% CI), log scale",
      y = NULL,
      title = "Joint UACR and TT4 categories in mortality analysis"
    ) +
    ggplot2::theme_classic(base_size = 7, base_family = "Arial") +
    ggplot2::theme(
      legend.position = "top",
      axis.line = ggplot2::element_line(linewidth = 0.35),
      axis.ticks = ggplot2::element_line(linewidth = 0.35),
      plot.title = ggplot2::element_text(size = 8, face = "bold")
    )

  figure_path <- file.path(root, "outputs", "figures", "Figure_joint_mortality.pdf")
  dir.create(dirname(figure_path), recursive = TRUE, showWarnings = FALSE)
  grDevices::cairo_pdf(figure_path, width = 183 / 25.4, height = 120 / 25.4, family = "Arial")
  print(figure)
  grDevices::dev.off()
  log("INFO", sprintf("Wrote joint mortality figure to %s", figure_path))
  log("INFO", sprintf("Wrote figure source data to %s", source_path))
}

fmt <- function(x, digits = 3) {
  ifelse(is.na(x), "NA", formatC(x, digits = digits, format = "f"))
}

fmt_p <- function(x) {
  ifelse(is.na(x), "NA", ifelse(x < 0.001, formatC(x, digits = 2, format = "e"), formatC(x, digits = 3, format = "f")))
}

summary_lines <- function(results, data) {
  continuous <- results[results$model == "Full" & results$exposure %in% c("LOG_UACR", "TT4"), , drop = FALSE]
  rows <- c(
    "# NHANES 2007-2012 mortality analysis summary",
    "",
    "This exploratory mortality module links the discovery cohort to the CDC public-use linked mortality file with follow-up through December 31, 2019.",
    "",
    sprintf("Eligible participants with follow-up: %s.", nrow(data)),
    sprintf("All-cause deaths: %s.", sum(data$ALL_CAUSE_DEATH == 1, na.rm = TRUE)),
    sprintf("Cardiovascular deaths: %s.", sum(data$CVD_DEATH == 1, na.rm = TRUE)),
    "",
    "## Continuous Exposures, Full Model",
    "| Outcome | Exposure | HR (95% CI) | P | FDR | n | Events |",
    "|---|---|---:|---:|---:|---:|---:|"
  )
  for (i in seq_len(nrow(continuous))) {
    rows <- c(rows, sprintf(
      "| %s | %s | %s (%s to %s) | %s | %s | %s | %s |",
      continuous$outcome[i], continuous$exposure[i], fmt(continuous$hr[i]),
      fmt(continuous$ci_low[i]), fmt(continuous$ci_high[i]),
      fmt_p(continuous$p_value[i]), fmt_p(continuous$p_fdr[i]),
      continuous$n_model[i], continuous$events[i]
    ))
  }
  c(
    rows,
    "",
    "## Model Notes",
    "- H1 adjusts for age, sex, and race.",
    "- Full adjusts for age, sex, race, education, PIR, BMI, smoking, drinking, diabetes, hypertension, eGFR, and UIC.",
    "- Cardiovascular mortality is defined from UCOD_LEADING as diseases of heart or cerebrovascular diseases.",
    "- Joint categories use UACR clinical groups and weighted TT4 tertiles. The reference is UACR <30 mg/g with TT4 tertile T1.",
    "- This is an observational survival extension. It does not establish causality.",
    "- CDC public-use linked mortality files protect confidentiality by perturbing selected information; estimates should be interpreted accordingly.",
    "",
    "## Official Data Source",
    "- CDC public-use linked mortality documentation: https://www.cdc.gov/nchs/data-linkage/mortality-public.htm",
    "- CDC linked mortality FTP directory: https://ftp.cdc.gov/pub/Health_Statistics/NCHS/datalinkage/linked_mortality/"
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

  data <- add_joint_categories(prepare_data(read_mortality_cohort(root, log), log), log)
  results <- list()
  outcome_map <- list(all_cause_mortality = "ALL_CAUSE_DEATH", cardiovascular_mortality = "CVD_DEATH")
  for (outcome in names(outcome_map)) {
    for (exposure in c("LOG_UACR", "TT4", "JOINT_CATEGORY")) {
      for (model_name in c("H1", "Full")) {
        rows <- fit_one(data, outcome, outcome_map[[outcome]], exposure, model_name, log)
        if (nrow(rows) > 0) {
          results[[length(results) + 1]] <- rows
        }
      }
    }
  }
  results <- add_fdr(do.call(rbind, results))

  table_path <- file.path(root, "outputs", "tables", "Table_mortality_main.csv")
  report_path <- file.path(root, "outputs", "reports", "mortality_summary.md")
  write_csv_safe(results, table_path)
  make_joint_plot(results, root, log)
  write_lines_safe(summary_lines(results, data), report_path)
  log("INFO", sprintf("Wrote %s mortality result rows to %s", nrow(results), table_path))
  log("INFO", sprintf("Wrote mortality report to %s", report_path))
}

main()
