options(stringsAsFactors = FALSE)
options(survey.lonely.psu = "adjust")

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
  log_path <- file.path(root, "outputs", "logs", "12_polish_plos_figures.log")
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

write_csv_safe <- function(x, path) {
  dir.create(dirname(path), recursive = TRUE, showWarnings = FALSE)
  utils::write.csv(x, path, row.names = FALSE, na = "")
}

write_text <- function(path, lines) {
  dir.create(dirname(path), recursive = TRUE, showWarnings = FALSE)
  writeLines(lines, con = path, useBytes = TRUE)
}

palette_contract <- c(
  neutral_dark = "#333333",
  neutral_mid = "#767676",
  neutral_light = "#D9D9D9",
  signal_blue = "#2F6B9A",
  signal_blue_light = "#BFD3E2",
  accent_red = "#B24A45",
  accent_teal = "#3A7D78",
  accent_gold = "#C58B2B"
)

theme_plos <- function(base_size = 7) {
  ggplot2::theme_classic(base_size = base_size, base_family = "Arial") +
    ggplot2::theme(
      axis.line = ggplot2::element_line(linewidth = 0.35, colour = palette_contract[["neutral_dark"]]),
      axis.ticks = ggplot2::element_line(linewidth = 0.35, colour = palette_contract[["neutral_dark"]]),
      axis.title = ggplot2::element_text(size = base_size),
      axis.text = ggplot2::element_text(size = base_size - 0.3, colour = palette_contract[["neutral_dark"]]),
      legend.position = "top",
      legend.title = ggplot2::element_blank(),
      legend.text = ggplot2::element_text(size = base_size - 0.4),
      legend.key.width = grid::unit(10, "pt"),
      legend.key.height = grid::unit(7, "pt"),
      strip.background = ggplot2::element_blank(),
      strip.text = ggplot2::element_text(size = base_size + 0.1, face = "bold", hjust = 0),
      panel.grid = ggplot2::element_blank(),
      plot.margin = ggplot2::margin(5, 7, 5, 5)
    )
}

save_bundle <- function(plot, root, stem, width_mm, height_mm, log) {
  output_dir <- file.path(root, "outputs", "figures", "submission")
  qc_dir <- file.path(output_dir, "qc")
  dir.create(output_dir, recursive = TRUE, showWarnings = FALSE)
  dir.create(qc_dir, recursive = TRUE, showWarnings = FALSE)
  width_in <- width_mm / 25.4
  height_in <- height_mm / 25.4

  pdf_path <- file.path(output_dir, paste0(stem, ".pdf"))
  svg_path <- file.path(output_dir, paste0(stem, ".svg"))
  tiff_path <- file.path(output_dir, paste0(stem, ".tiff"))
  png_path <- file.path(qc_dir, paste0(stem, "_qc.png"))

  grDevices::cairo_pdf(pdf_path, width = width_in, height = height_in, family = "Arial")
  print(plot)
  grDevices::dev.off()

  svglite::svglite(svg_path, width = width_in, height = height_in, bg = "white")
  print(plot)
  grDevices::dev.off()

  ragg::agg_tiff(
    tiff_path,
    width = width_in,
    height = height_in,
    units = "in",
    res = 600,
    compression = "lzw",
    background = "white"
  )
  print(plot)
  grDevices::dev.off()

  ragg::agg_png(
    png_path,
    width = width_in,
    height = height_in,
    units = "in",
    res = 220,
    background = "white"
  )
  print(plot)
  grDevices::dev.off()

  log("INFO", sprintf("Exported %s at %s x %s mm", stem, width_mm, height_mm))
  data.frame(
    stem = stem,
    pdf = normalizePath(pdf_path, winslash = "/", mustWork = TRUE),
    svg = normalizePath(svg_path, winslash = "/", mustWork = TRUE),
    tiff = normalizePath(tiff_path, winslash = "/", mustWork = TRUE),
    qc_png = normalizePath(png_path, winslash = "/", mustWork = TRUE),
    width_mm = width_mm,
    height_mm = height_mm,
    stringsAsFactors = FALSE
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

typical_covariate_row <- function(data, covariates) {
  row <- data[1, , drop = FALSE]
  for (variable in covariates) {
    observed <- data[[variable]][!is.na(data[[variable]])]
    if (is.factor(data[[variable]])) {
      tab <- sort(table(observed), decreasing = TRUE)
      row[[variable]] <- factor(names(tab)[1], levels = levels(data[[variable]]))
    } else {
      row[[variable]] <- stats::median(observed, na.rm = TRUE)
    }
  }
  row
}

predict_svyglm <- function(fit, newdata) {
  prediction <- stats::predict(fit, newdata = newdata, se.fit = TRUE, type = "response")
  if (is.list(prediction)) {
    fit_values <- as.numeric(prediction$fit)
    se_values <- as.numeric(prediction$se.fit)
  } else {
    fit_values <- as.numeric(prediction)
    variance <- attr(prediction, "var")
    se_values <- if (is.null(variance)) rep(NA_real_, length(fit_values)) else sqrt(diag(as.matrix(variance)))
  }
  data.frame(
    predicted_tt4 = fit_values,
    se = se_values,
    ci_low = fit_values - 1.96 * se_values,
    ci_high = fit_values + 1.96 * se_values
  )
}

make_rcs_figure <- function(root, log) {
  data_path <- file.path(root, "data", "processed", "discovery_nhanes_2007_2012.csv")
  data <- utils::read.csv(data_path, check.names = FALSE)
  covariates <- c(
    "AGE_YEARS", "SEX", "RACE_ETHNICITY", "EDUCATION", "PIR", "BMI",
    "SMOKING_STATUS", "ALCOHOL_STATUS", "DIABETES_STATUS", "HYPERTENSION_STATUS",
    "EGFR_CKD_EPI_2021", "UIC_UG_L"
  )
  numeric_variables <- c(
    "TT4", "LOG_UACR", "UACR_MG_G", "ANALYTIC_WT6YR", "SDMVPSU", "SDMVSTRA",
    "AGE_YEARS", "PIR", "BMI", "EGFR_CKD_EPI_2021", "UIC_UG_L"
  )
  factor_variables <- c(
    "SEX", "RACE_ETHNICITY", "EDUCATION", "SMOKING_STATUS", "ALCOHOL_STATUS",
    "DIABETES_STATUS", "HYPERTENSION_STATUS"
  )
  for (variable in numeric_variables) {
    data[[variable]] <- suppressWarnings(as.numeric(data[[variable]]))
  }
  for (variable in factor_variables) {
    data[[variable]] <- factor(data[[variable]])
  }
  complete_vars <- c("TT4", "LOG_UACR", "UACR_MG_G", "ANALYTIC_WT6YR", "SDMVPSU", "SDMVSTRA", covariates)
  data <- data[stats::complete.cases(data[, complete_vars, drop = FALSE]), , drop = FALSE]
  knots <- as.numeric(stats::quantile(data$LOG_UACR, probs = c(0.05, 0.35, 0.65, 0.95), na.rm = TRUE, type = 7))
  data <- add_rcs_terms(data, knots)
  nonlinear_terms <- names(rcs_terms(data$LOG_UACR, knots))

  design <- survey::svydesign(
    ids = ~SDMVPSU,
    strata = ~SDMVSTRA,
    weights = ~ANALYTIC_WT6YR,
    nest = TRUE,
    data = data
  )
  formula <- stats::as.formula(
    paste("TT4 ~", paste(c("LOG_UACR", nonlinear_terms, covariates), collapse = " + "))
  )
  fit <- survey::svyglm(formula, design = design)
  p_overall <- as.numeric(survey::regTermTest(
    fit,
    stats::as.formula(paste("~", paste(c("LOG_UACR", nonlinear_terms), collapse = " + ")))
  )$p[1])
  p_nonlinearity <- as.numeric(survey::regTermTest(
    fit,
    stats::as.formula(paste("~", paste(nonlinear_terms, collapse = " + ")))
  )$p[1])

  display_limits <- as.numeric(stats::quantile(data$UACR_MG_G, probs = c(0.01, 0.99), na.rm = TRUE, type = 7))
  grid_log_uacr <- seq(base::log(display_limits[1]), base::log(display_limits[2]), length.out = 300)
  newdata <- typical_covariate_row(data, covariates)
  newdata <- newdata[rep(1, length(grid_log_uacr)), , drop = FALSE]
  newdata$LOG_UACR <- grid_log_uacr
  basis <- rcs_terms(grid_log_uacr, knots)
  for (name in names(basis)) {
    newdata[[name]] <- basis[[name]]
  }
  source_data <- cbind(
    data.frame(uacr_mg_g = exp(grid_log_uacr), log_uacr = grid_log_uacr),
    predict_svyglm(fit, newdata)
  )
  source_data$p_overall <- p_overall
  source_data$p_nonlinearity <- p_nonlinearity
  source_data$n_model <- nrow(data)
  write_csv_safe(source_data, file.path(root, "outputs", "tables", "Figure1_RCS_TT4_source_data.csv"))

  y_top <- max(source_data$ci_high, na.rm = TRUE)
  figure <- ggplot2::ggplot(source_data, ggplot2::aes(x = uacr_mg_g, y = predicted_tt4)) +
    ggplot2::geom_ribbon(
      ggplot2::aes(ymin = ci_low, ymax = ci_high),
      fill = palette_contract[["signal_blue_light"]],
      alpha = 0.55
    ) +
    ggplot2::geom_line(linewidth = 0.75, colour = palette_contract[["signal_blue"]]) +
    ggplot2::geom_vline(
      xintercept = c(30, 300),
      linewidth = 0.38,
      linetype = "22",
      colour = palette_contract[["accent_red"]]
    ) +
    ggplot2::annotate(
      "text",
      x = c(30, 300),
      y = y_top,
      label = c("30 mg/g", "300 mg/g"),
      angle = 90,
      vjust = -0.35,
      hjust = 1,
      size = 2.25,
      colour = palette_contract[["accent_red"]],
      family = "Arial"
    ) +
    ggplot2::annotate(
      "text",
      x = display_limits[1],
      y = Inf,
      label = sprintf("P overall = %.4f; P non-linearity = %.3f", p_overall, p_nonlinearity),
      hjust = 0,
      vjust = 1.35,
      size = 2.3,
      colour = palette_contract[["neutral_dark"]],
      family = "Arial"
    ) +
    ggplot2::scale_x_log10(
      breaks = c(1, 3, 10, 30, 100, 300, 1000),
      labels = c("1", "3", "10", "30", "100", "300", "1000")
    ) +
    ggplot2::labs(
      x = "UACR (mg/g, log scale)",
      y = "Predicted TT4 (ug/dL)"
    ) +
    theme_plos() +
    ggplot2::theme(legend.position = "none")

  if (abs(p_overall - 0.00463) > 0.001 || abs(p_nonlinearity - 0.518) > 0.01) {
    log("WARN", sprintf("RCS P values differ from frozen rounded values: overall=%.6f; non-linearity=%.6f", p_overall, p_nonlinearity))
  } else {
    log("INFO", sprintf("RCS P values reproduced: overall=%.6f; non-linearity=%.6f", p_overall, p_nonlinearity))
  }
  save_bundle(figure, root, "Figure1_RCS_TT4", 89, 78, log)
}

make_mortality_forest <- function(root, log) {
  source <- utils::read.csv(
    file.path(root, "outputs", "tables", "Table_mortality_sensitivity.csv"),
    check.names = FALSE
  )
  plot_data <- source[
    source$analysis_type == "survey_weighted_cox" &
      source$exposure %in% c("LOG_UACR", "TT4") &
      source$contrast %in% c("LOG_UACR", "TT4"),
    ,
    drop = FALSE
  ]
  plot_data <- plot_data[stats::complete.cases(plot_data[, c("hr", "ci_low", "ci_high")]), , drop = FALSE]
  scenarios <- c(
    "Full analytic cohort",
    "Exclude deaths within first 2 years",
    "Exclude eGFR <60",
    "Exclude diabetes",
    "Exclude hypertension",
    "Exclude UACR >=300",
    "Euthyroid participants"
  )
  plot_data$scenario <- factor(plot_data$scenario, levels = rev(scenarios))
  plot_data$outcome_label <- ifelse(
    plot_data$outcome == "all_cause_mortality",
    "All-cause mortality",
    "Cardiovascular mortality"
  )
  plot_data$exposure_label <- ifelse(plot_data$exposure == "LOG_UACR", "a  Natural-log UACR", "b  TT4")
  plot_data$exposure_label <- factor(plot_data$exposure_label, levels = c("a  Natural-log UACR", "b  TT4"))
  write_csv_safe(plot_data, file.path(root, "outputs", "tables", "Figure2_mortality_forest_source_data.csv"))

  outcome_palette <- c(
    "All-cause mortality" = palette_contract[["signal_blue"]],
    "Cardiovascular mortality" = palette_contract[["accent_red"]]
  )
  outcome_shapes <- c("All-cause mortality" = 16, "Cardiovascular mortality" = 17)
  dodge <- ggplot2::position_dodge(width = 0.45)
  figure <- ggplot2::ggplot(plot_data, ggplot2::aes(x = hr, y = scenario, colour = outcome_label, shape = outcome_label)) +
    ggplot2::geom_vline(xintercept = 1, linetype = "22", linewidth = 0.35, colour = palette_contract[["neutral_mid"]]) +
    ggplot2::geom_errorbar(
      ggplot2::aes(xmin = ci_low, xmax = ci_high),
      orientation = "y",
      width = 0.14,
      linewidth = 0.45,
      position = dodge
    ) +
    ggplot2::geom_point(size = 1.9, position = dodge) +
    ggplot2::facet_grid(cols = ggplot2::vars(exposure_label), scales = "free_x", space = "free_x") +
    ggplot2::scale_x_log10() +
    ggplot2::scale_colour_manual(values = outcome_palette) +
    ggplot2::scale_shape_manual(values = outcome_shapes) +
    ggplot2::labs(x = "Hazard ratio (95% CI)", y = NULL) +
    theme_plos() +
    ggplot2::theme(panel.spacing.x = grid::unit(9, "pt"))
  save_bundle(figure, root, "Figure2_mortality_forest", 183, 112, log)
}

make_joint_figure <- function(root, log) {
  source <- utils::read.csv(
    file.path(root, "outputs", "tables", "Table_mortality_joint.csv"),
    check.names = FALSE
  )
  plot_data <- source[
    source$high_definition == "TT4 highest quartile (Q4)" &
      source$model == "Model 3",
    ,
    drop = FALSE
  ]
  labels <- c(
    "UACR_lt30__TT4_non_high" = "UACR <30 + TT4 non-high",
    "UACR_ge30__TT4_non_high" = "UACR >=30 + TT4 non-high",
    "UACR_lt30__TT4_high" = "UACR <30 + TT4 high",
    "UACR_ge30__TT4_high" = "UACR >=30 + TT4 high"
  )
  plot_data$group_label <- labels[plot_data$group]
  plot_data$group_label <- factor(plot_data$group_label, levels = rev(unname(labels)))
  plot_data$outcome_label <- ifelse(
    plot_data$outcome == "all_cause_mortality",
    "All-cause mortality",
    "Cardiovascular mortality"
  )
  write_csv_safe(plot_data, file.path(root, "outputs", "tables", "FigureS1_joint_mortality_source_data.csv"))

  outcome_palette <- c(
    "All-cause mortality" = palette_contract[["signal_blue"]],
    "Cardiovascular mortality" = palette_contract[["accent_red"]]
  )
  outcome_shapes <- c("All-cause mortality" = 16, "Cardiovascular mortality" = 17)
  dodge <- ggplot2::position_dodge(width = 0.42)
  figure <- ggplot2::ggplot(plot_data, ggplot2::aes(x = hr, y = group_label, colour = outcome_label, shape = outcome_label)) +
    ggplot2::geom_vline(xintercept = 1, linetype = "22", linewidth = 0.35, colour = palette_contract[["neutral_mid"]]) +
    ggplot2::geom_errorbar(
      ggplot2::aes(xmin = ci_low, xmax = ci_high),
      orientation = "y",
      width = 0.14,
      linewidth = 0.45,
      position = dodge
    ) +
    ggplot2::geom_point(size = 1.9, position = dodge) +
    ggplot2::scale_x_log10(breaks = c(0.5, 1, 2, 3, 4)) +
    ggplot2::scale_colour_manual(values = outcome_palette) +
    ggplot2::scale_shape_manual(values = outcome_shapes) +
    ggplot2::labs(x = "Hazard ratio (95% CI, log scale)", y = NULL) +
    theme_plos()
  save_bundle(figure, root, "FigureS1_joint_mortality", 183, 95, log)
}

make_mr_figure <- function(root, log) {
  source <- utils::read.csv(file.path(root, "outputs", "tables", "Table_MR_main.csv"), check.names = FALSE)
  plot_data <- source[source$status == "complete" & !is.na(source$beta), , drop = FALSE]
  plot_data$trait_pair <- paste(plot_data$exposure_trait, "to", plot_data$outcome_trait)
  plot_data$trait_pair <- factor(plot_data$trait_pair, levels = rev(plot_data$trait_pair))
  plot_data$direction_label <- ifelse(
    plot_data$direction == "kidney_to_thyroid",
    "Kidney-related trait to thyroid proxy",
    "Thyroid proxy to kidney-related trait"
  )
  plot_data$instrument_label <- ifelse(plot_data$nsnp > 1, "Multi-SNP", "Single SNP")
  write_csv_safe(plot_data, file.path(root, "outputs", "tables", "FigureS2_MR_forest_source_data.csv"))

  direction_palette <- c(
    "Kidney-related trait to thyroid proxy" = palette_contract[["signal_blue"]],
    "Thyroid proxy to kidney-related trait" = palette_contract[["accent_teal"]]
  )
  instrument_shapes <- c("Single SNP" = 16, "Multi-SNP" = 15)
  figure <- ggplot2::ggplot(plot_data, ggplot2::aes(x = beta, y = trait_pair, colour = direction_label, shape = instrument_label)) +
    ggplot2::geom_vline(xintercept = 0, linetype = "22", linewidth = 0.35, colour = palette_contract[["neutral_mid"]]) +
    ggplot2::geom_errorbar(
      ggplot2::aes(xmin = ci_low, xmax = ci_high),
      orientation = "y",
      width = 0.12,
      linewidth = 0.45
    ) +
    ggplot2::geom_point(size = 1.9) +
    ggplot2::scale_colour_manual(values = direction_palette) +
    ggplot2::scale_shape_manual(values = instrument_shapes) +
    ggplot2::labs(x = "IVW beta (95% CI)", y = NULL) +
    theme_plos() +
    ggplot2::theme(legend.box = "vertical")
  save_bundle(figure, root, "FigureS2_exploratory_MR_forest", 183, 98, log)
}

make_figure_list <- function(root) {
  rows <- data.frame(
    label = c("Figure 1", "Figure 2", "Figure S1", "Figure S2"),
    placement = c("Main manuscript", "Main manuscript", "Supplementary Materials", "Supplementary Materials"),
    title = c(
      "Restricted cubic spline association between UACR and TT4",
      "Mortality sensitivity analyses for natural-log UACR and TT4",
      "Secondary descriptive joint UACR and TT4 mortality categories",
      "Supplementary exploratory genetic-analysis IVW estimates"
    ),
    source_data = c(
      "outputs/tables/Figure1_RCS_TT4_source_data.csv",
      "outputs/tables/Figure2_mortality_forest_source_data.csv",
      "outputs/tables/FigureS1_joint_mortality_source_data.csv",
      "outputs/tables/FigureS2_MR_forest_source_data.csv"
    ),
    submission_pdf = c(
      "outputs/figures/submission/Figure1_RCS_TT4.pdf",
      "outputs/figures/submission/Figure2_mortality_forest.pdf",
      "outputs/figures/submission/FigureS1_joint_mortality.pdf",
      "outputs/figures/submission/FigureS2_exploratory_MR_forest.pdf"
    ),
    role = c(
      "Primary thyroid association shape",
      "Primary and secondary mortality robustness",
      "Secondary descriptive analysis only",
      "Supplementary exploratory genetic analysis only"
    ),
    stringsAsFactors = FALSE
  )
  write_csv_safe(rows, file.path(root, "outputs", "tables", "final_figure_list.csv"))
}

make_audit_report <- function(root) {
  lines <- c(
    "# PLOS ONE figure audit and export report",
    "",
    "## Figure contract",
    "",
    "- Backend: R only for plotting, export, preview generation, and visual QA.",
    "- Target: PLOS ONE submission with restrained Nature-style visual discipline.",
    "- Palette: neutral greys, one signal blue, one muted red mortality contrast, and one restrained teal Supplementary accent.",
    "- Font: Arial family with compact journal-scale text.",
    "- Export bundle: editable PDF and SVG, 600 dpi TIFF, R-generated PNG preview, and clean CSV source data.",
    "- SVG exports use svglite and retain editable text nodes.",
    "",
    "## Evidence hierarchy",
    "",
    "1. Figure 1 is the hero thyroid-association figure: it shows the approximately linear UACR-TT4 association and clinical thresholds.",
    "2. Figure 2 is the main mortality figure: it separates the stable UACR signal from the more modest TT4 signal across sensitivity analyses.",
    "3. Figure S1 is secondary and descriptive: joint mortality groups do not support a monotonic combined-risk claim.",
    "4. Figure S2 is Supplementary exploratory genetic evidence only and is not part of the main causal argument.",
    "",
    "## Review-risk controls",
    "",
    "- No new models or exploratory analyses were added during figure polishing.",
    "- Source-data CSV files were generated for every polished figure.",
    "- Joint-group and genetic figures were explicitly retained as Supplementary outputs.",
    "- The mortality figure uses colour and shape, so interpretation does not depend on colour alone.",
    "- RCS clinical thresholds are directly labelled at 30 and 300 mg/g.",
    "- Final visual review should still be performed in the journal upload preview.",
    "",
    "## Submission outputs",
    "",
    "- `outputs/figures/submission/Figure1_RCS_TT4.pdf`",
    "- `outputs/figures/submission/Figure2_mortality_forest.pdf`",
    "- `outputs/figures/submission/FigureS1_joint_mortality.pdf`",
    "- `outputs/figures/submission/FigureS2_exploratory_MR_forest.pdf`",
    "- `outputs/tables/final_figure_list.csv`"
  )
  write_text(file.path(root, "outputs", "reports", "PLOS_ONE_figure_audit.md"), lines)
}

main <- function() {
  root <- find_project_root()
  log <- init_logger(root)
  for (package in c("survey", "ggplot2", "ragg", "svglite")) {
    if (!requireNamespace(package, quietly = TRUE)) {
      stop(sprintf("R package '%s' is required.", package), call. = FALSE)
    }
  }
  if (!capabilities("cairo")) {
    stop("R cairo graphics capability is required.", call. = FALSE)
  }
  log("INFO", sprintf("Project root: %s", root))
  log("INFO", "Figure contract: R-only drawing, export, preview generation, and QA.")

  make_rcs_figure(root, log)
  make_mortality_forest(root, log)
  make_joint_figure(root, log)
  make_mr_figure(root, log)
  make_figure_list(root)
  make_audit_report(root)
  log("INFO", "Completed PLOS ONE figure polishing without adding new exploratory analyses.")
}

tryCatch(
  main(),
  error = function(error) {
    cat(sprintf("ERROR: %s\n", conditionMessage(error)))
    quit(status = 1)
  }
)
