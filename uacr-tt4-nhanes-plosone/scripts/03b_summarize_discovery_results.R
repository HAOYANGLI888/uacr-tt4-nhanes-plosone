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
  log_file <- file.path(log_dir, "03b_summarize_discovery_results.log")
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

read_result_table <- function(path, log) {
  if (!file.exists(path)) {
    log("WARN", sprintf("Input table not found: %s", path))
    return(data.frame())
  }
  data <- utils::read.csv(path, check.names = FALSE)
  log("INFO", sprintf("Loaded %s rows from %s", nrow(data), path))
  data
}

to_numeric_if_present <- function(data, variables) {
  for (variable in intersect(variables, names(data))) {
    data[[variable]] <- suppressWarnings(as.numeric(data[[variable]]))
  }
  data
}

normalize_exposure_definition <- function(exposure_type, contrast) {
  ifelse(
    exposure_type == "log_UACR" | contrast == "LOG_UACR",
    "LOG_UACR",
    ifelse(
      exposure_type == "UACR quartile" | grepl("^UACR_QUARTILE", contrast),
      "UACR_QUARTILE",
      ifelse(
        exposure_type == "UACR clinical category" | grepl("^UACR_CLINICAL_CATEGORY", contrast),
        "UACR_CLINICAL_CATEGORY",
        NA_character_
      )
    )
  )
}

direction_from_beta <- function(beta) {
  ifelse(
    is.na(beta),
    NA_character_,
    ifelse(beta > 0, "positive", ifelse(beta < 0, "negative", "null"))
  )
}

format_number <- function(x, digits = 3) {
  ifelse(is.na(x), "", formatC(x, digits = digits, format = "f"))
}

format_p <- function(x) {
  ifelse(
    is.na(x),
    "",
    ifelse(x < 0.001, formatC(x, digits = 2, format = "e"), formatC(x, digits = 3, format = "f"))
  )
}

representative_row <- function(rows, exposure_definition) {
  if (nrow(rows) == 0) {
    return(NULL)
  }
  if (exposure_definition == "LOG_UACR") {
    preferred <- rows[rows$contrast == "LOG_UACR", , drop = FALSE]
  } else if (exposure_definition == "UACR_QUARTILE") {
    preferred <- rows[grepl("Q4", rows$contrast, fixed = TRUE), , drop = FALSE]
  } else if (exposure_definition == "UACR_CLINICAL_CATEGORY") {
    preferred <- rows[grepl(">=300", rows$contrast, fixed = TRUE), , drop = FALSE]
  } else {
    preferred <- rows[0, , drop = FALSE]
  }

  if (nrow(preferred) == 0) {
    preferred <- rows[nrow(rows), , drop = FALSE]
  }
  preferred[1, , drop = FALSE]
}

outcome_summary <- function(rows) {
  outcomes <- unique(rows$outcome)
  summaries <- lapply(outcomes, function(outcome_name) {
    outcome_rows <- rows[rows$outcome == outcome_name, , drop = FALSE]
    exposure_definitions <- c("LOG_UACR", "UACR_QUARTILE", "UACR_CLINICAL_CATEGORY")

    definition_rows <- lapply(exposure_definitions, function(definition) {
      subset_rows <- outcome_rows[outcome_rows$exposure_definition == definition, , drop = FALSE]
      representative <- representative_row(subset_rows, definition)
      representative_beta <- if (is.null(representative)) NA_real_ else representative$beta[1]
      data.frame(
        outcome = outcome_name,
        exposure_definition = definition,
        representative_direction = direction_from_beta(representative_beta),
        any_significant_before_fdr = any(subset_rows$p_value < 0.05, na.rm = TRUE),
        any_significant_after_fdr = any(subset_rows$p_fdr < 0.05, na.rm = TRUE)
      )
    })
    definition_summary <- do.call(rbind, definition_rows)
    available_directions <- definition_summary$representative_direction[
      !is.na(definition_summary$representative_direction) &
        definition_summary$representative_direction != "null"
    ]
    directionally_consistent <- length(available_directions) == length(exposure_definitions) &&
      length(unique(available_directions)) == 1

    significant_before_count <- sum(definition_summary$any_significant_before_fdr, na.rm = TRUE)
    significant_after_count <- sum(definition_summary$any_significant_after_fdr, na.rm = TRUE)

    evidence_grade <- if (directionally_consistent && significant_after_count == 3) {
      "Strong evidence"
    } else if (directionally_consistent && significant_after_count >= 2) {
      "Moderate evidence"
    } else if (significant_after_count >= 1 || significant_before_count >= 2) {
      "Weak evidence"
    } else {
      "No evidence"
    }

    dominant_direction <- if (directionally_consistent) available_directions[1] else "mixed"
    conclusion_sentence <- sprintf(
      "%s for a %s association between UACR and %s in Model 3.",
      evidence_grade,
      dominant_direction,
      outcome_name
    )

    data.frame(
      outcome = outcome_name,
      directionally_consistent_across_exposure_definitions = directionally_consistent,
      exposure_definitions_significant_before_fdr = significant_before_count,
      exposure_definitions_significant_after_fdr = significant_after_count,
      evidence_grade = evidence_grade,
      conclusion_sentence = conclusion_sentence
    )
  })

  do.call(rbind, summaries)
}

empty_summary_table <- function() {
  data.frame(
    outcome = character(),
    exposure_definition = character(),
    contrast = character(),
    model = character(),
    beta = numeric(),
    ci_low = numeric(),
    ci_high = numeric(),
    ci_95 = character(),
    p_value = numeric(),
    p_fdr = numeric(),
    p_trend = numeric(),
    direction = character(),
    statistically_significant_before_fdr = logical(),
    statistically_significant_after_fdr = logical(),
    n_model_unweighted = integer(),
    directionally_consistent_across_exposure_definitions = logical(),
    exposure_definitions_significant_before_fdr = integer(),
    exposure_definitions_significant_after_fdr = integer(),
    evidence_grade = character(),
    conclusion_sentence = character()
  )
}

build_summary_table <- function(results) {
  if (nrow(results) == 0) {
    return(empty_summary_table())
  }

  results$exposure_definition <- normalize_exposure_definition(results$exposure_type, results$contrast)
  keep <- results$cohort == "discovery" &
    results$outcome %in% c("TT4", "TGAB") &
    results$model == "Model 3" &
    results$exposure_definition %in% c("LOG_UACR", "UACR_QUARTILE", "UACR_CLINICAL_CATEGORY")
  filtered <- results[keep, , drop = FALSE]
  if (nrow(filtered) == 0) {
    return(empty_summary_table())
  }

  key <- paste(filtered$outcome, filtered$exposure_definition, filtered$contrast, filtered$model, sep = "||")
  filtered <- filtered[!duplicated(key), , drop = FALSE]
  filtered$direction <- direction_from_beta(filtered$beta)
  filtered$statistically_significant_before_fdr <- !is.na(filtered$p_value) & filtered$p_value < 0.05
  filtered$statistically_significant_after_fdr <- !is.na(filtered$p_fdr) & filtered$p_fdr < 0.05
  filtered$ci_95 <- paste0(
    format_number(filtered$ci_low), " to ", format_number(filtered$ci_high)
  )

  outcome_level <- outcome_summary(filtered)
  merged <- merge(filtered, outcome_level, by = "outcome", all.x = TRUE, sort = FALSE)

  n_column <- if ("n_model_unweighted" %in% names(merged)) "n_model_unweighted" else "n"
  summary <- data.frame(
    outcome = merged$outcome,
    exposure_definition = merged$exposure_definition,
    contrast = merged$contrast,
    model = merged$model,
    beta = merged$beta,
    ci_low = merged$ci_low,
    ci_high = merged$ci_high,
    ci_95 = merged$ci_95,
    p_value = merged$p_value,
    p_fdr = merged$p_fdr,
    p_trend = if ("p_trend" %in% names(merged)) merged$p_trend else NA_real_,
    direction = merged$direction,
    statistically_significant_before_fdr = merged$statistically_significant_before_fdr,
    statistically_significant_after_fdr = merged$statistically_significant_after_fdr,
    n_model_unweighted = merged[[n_column]],
    directionally_consistent_across_exposure_definitions =
      merged$directionally_consistent_across_exposure_definitions,
    exposure_definitions_significant_before_fdr =
      merged$exposure_definitions_significant_before_fdr,
    exposure_definitions_significant_after_fdr =
      merged$exposure_definitions_significant_after_fdr,
    evidence_grade = merged$evidence_grade,
    conclusion_sentence = merged$conclusion_sentence
  )

  order_key <- match(summary$outcome, c("TT4", "TGAB")) * 100 +
    match(summary$exposure_definition, c("LOG_UACR", "UACR_QUARTILE", "UACR_CLINICAL_CATEGORY")) * 10 +
    seq_len(nrow(summary)) / 10000
  summary[order(order_key), , drop = FALSE]
}

markdown_table <- function(summary) {
  if (nrow(summary) == 0) {
    return("No eligible Model 3 discovery rows were available.")
  }

  lines <- c(
    "| Outcome | Exposure | Contrast | Beta (95% CI) | P | FDR | Direction | Significant before FDR | Significant after FDR |",
    "|---|---|---|---:|---:|---:|---|---|---|"
  )
  for (i in seq_len(nrow(summary))) {
    line <- sprintf(
      "| %s | %s | %s | %s (%s) | %s | %s | %s | %s | %s |",
      summary$outcome[i],
      summary$exposure_definition[i],
      summary$contrast[i],
      format_number(summary$beta[i]),
      summary$ci_95[i],
      format_p(summary$p_value[i]),
      format_p(summary$p_fdr[i]),
      summary$direction[i],
      summary$statistically_significant_before_fdr[i],
      summary$statistically_significant_after_fdr[i]
    )
    lines <- c(lines, line)
  }
  lines
}

build_markdown_report <- function(summary) {
  if (nrow(summary) == 0) {
    return(c(
      "# Discovery main result summary",
      "",
      "No eligible discovery Model 3 rows were found for TT4 or TGAB."
    ))
  }

  outcome_conclusions <- unique(summary[, c(
    "outcome",
    "directionally_consistent_across_exposure_definitions",
    "exposure_definitions_significant_before_fdr",
    "exposure_definitions_significant_after_fdr",
    "evidence_grade",
    "conclusion_sentence"
  ), drop = FALSE])

  conclusion_lines <- paste0("- ", outcome_conclusions$conclusion_sentence)
  consistency_lines <- sprintf(
    "- %s: directionally consistent across exposure definitions = %s; exposure definitions significant before FDR = %s; after FDR = %s.",
    outcome_conclusions$outcome,
    outcome_conclusions$directionally_consistent_across_exposure_definitions,
    outcome_conclusions$exposure_definitions_significant_before_fdr,
    outcome_conclusions$exposure_definitions_significant_after_fdr
  )

  c(
    "# Discovery main result summary",
    "",
    "Source tables:",
    "- outputs/tables/Table2_discovery_main_results.csv",
    "- outputs/tables/TableS_full_thyroid_results.csv",
    "",
    "Filter: discovery cohort, primary outcomes TT4 and TGAB, Model 3.",
    "",
    "Direction consistency rule: LOG_UACR uses its beta; UACR_QUARTILE uses Q4 vs Q1; UACR_CLINICAL_CATEGORY uses >=300 vs <30.",
    "",
    "## Evidence conclusion",
    conclusion_lines,
    "",
    "Evidence grading rule: Strong evidence requires directional consistency and FDR significance in all three exposure definitions; Moderate evidence requires directional consistency and FDR significance in at least two exposure definitions; Weak evidence requires any FDR-significant exposure definition or at least two nominally significant exposure definitions; otherwise No evidence.",
    "",
    "## Direction and significance checks",
    consistency_lines,
    "",
    "## Model 3 results",
    markdown_table(summary)
  )
}

main <- function() {
  root <- find_project_root()
  log <- init_logger(root)

  input_paths <- c(
    file.path(root, "outputs", "tables", "Table2_discovery_main_results.csv"),
    file.path(root, "outputs", "tables", "TableS_full_thyroid_results.csv")
  )
  tables <- lapply(input_paths, read_result_table, log = log)
  results <- do.call(rbind, tables)
  results <- to_numeric_if_present(results, c("beta", "ci_low", "ci_high", "p_value", "p_fdr", "p_trend", "n", "n_model_unweighted"))

  required <- c("cohort", "outcome", "exposure_type", "contrast", "model", "beta", "ci_low", "ci_high", "p_value", "p_fdr")
  missing_required <- setdiff(required, names(results))
  if (length(missing_required) > 0) {
    stop(sprintf("Missing required result columns: %s", paste(missing_required, collapse = ", ")), call. = FALSE)
  }

  summary <- build_summary_table(results)
  csv_path <- file.path(root, "outputs", "tables", "discovery_primary_outcome_summary.csv")
  report_path <- file.path(root, "outputs", "reports", "discovery_main_result_summary.md")

  write_csv_safe(summary, csv_path)
  write_lines_safe(build_markdown_report(summary), report_path)

  log("INFO", sprintf("Wrote %s summary rows to %s", nrow(summary), csv_path))
  log("INFO", sprintf("Wrote markdown report to %s", report_path))
  if (nrow(summary) > 0) {
    conclusions <- unique(summary$conclusion_sentence)
    for (sentence in conclusions) {
      log("INFO", sentence)
    }
  }
}

main()
