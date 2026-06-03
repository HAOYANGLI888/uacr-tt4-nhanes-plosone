source("scripts/project_utils.R")

root <- find_project_root()
configs <- load_project_configs(root)
ensure_project_dirs(root, configs$analysis)
log <- init_logger(root, "04_discovery_survey_skeleton")

dataset_path <- project_path(root, configs$analysis$outputs$discovery_dataset)
report_path <- file.path(root, "outputs", "reports", "04_discovery_survey_skeleton_report.md")
table_path <- file.path(root, "outputs", "tables", "04_discovery_survey_skeleton_summary.csv")

if (!file.exists(dataset_path)) {
  log("WARN", sprintf("Discovery dataset not found: %s", dataset_path))
  write_text_report(report_path, c(
    "# Discovery Survey Skeleton",
    "",
    "Status: waiting for discovery dataset.",
    "",
    "Run `python scripts/02_build_discovery_dataset.py` first."
  ))
  quit(save = "no", status = 0)
}

needed <- c("readr", "survey")
missing <- needed[!vapply(needed, require_package, logical(1), logger = log)]
if (length(missing) > 0) {
  write_text_report(report_path, c(
    "# Discovery Survey Skeleton",
    "",
    sprintf("Status: missing R packages: %s.", paste(missing, collapse = ", "))
  ))
  quit(save = "no", status = 0)
}

data <- readr::read_csv(dataset_path, show_col_types = FALSE)
weight <- if ("ANALYTIC_WT6YR" %in% names(data)) {
  "ANALYTIC_WT6YR"
} else {
  configs$discovery$survey_design$combined_weight
}
strata <- configs$discovery$survey_design$strata
psu <- configs$discovery$survey_design$psu
log_uacr <- configs$discovery$exposure$derived_log_uacr

required <- c(weight, strata, psu, log_uacr)
missing_cols <- setdiff(required, names(data))
if (length(missing_cols) > 0) {
  log("WARN", sprintf("Missing required columns: %s", paste(missing_cols, collapse = ", ")))
  write_text_report(report_path, c(
    "# Discovery Survey Skeleton",
    "",
    sprintf("Status: missing required columns: `%s`.", paste(missing_cols, collapse = "`, `"))
  ))
  quit(save = "no", status = 0)
}

design <- survey::svydesign(
  ids = stats::as.formula(paste0("~", psu)),
  strata = stats::as.formula(paste0("~", strata)),
  weights = stats::as.formula(paste0("~", weight)),
  nest = TRUE,
  data = data
)

mean_log_uacr <- survey::svymean(stats::as.formula(paste0("~", log_uacr)), design, na.rm = TRUE)
summary <- data.frame(
  metric = "weighted_mean_log_uacr",
  estimate = as.numeric(mean_log_uacr),
  stringsAsFactors = FALSE
)

readr::write_csv(summary, table_path)
write_text_report(report_path, c(
  "# Discovery Survey Skeleton",
  "",
  "Status: completed initial survey design smoke test.",
  "",
  sprintf("Rows: %s", nrow(data)),
  sprintf("Output table: `%s`", table_path)
))

log("INFO", sprintf("Wrote %s", table_path))
log("INFO", sprintf("Wrote %s", report_path))
