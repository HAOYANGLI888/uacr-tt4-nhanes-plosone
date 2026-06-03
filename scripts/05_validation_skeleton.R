source("scripts/project_utils.R")

root <- find_project_root()
configs <- load_project_configs(root)
ensure_project_dirs(root, configs$analysis)
log <- init_logger(root, "05_validation_skeleton")

dataset_path <- project_path(root, configs$analysis$outputs$validation_dataset)
report_path <- file.path(root, "outputs", "reports", "05_validation_skeleton_report.md")

if (!file.exists(dataset_path)) {
  log("WARN", sprintf("Validation dataset not found: %s", dataset_path))
  write_text_report(report_path, c(
    "# NHANES III Validation Skeleton",
    "",
    "Status: waiting for harmonized NHANES III validation dataset.",
    "",
    "Current validation step is intentionally limited to file checks and harmonization planning.",
    "Run `python scripts/03_prepare_validation_nhanes3.py` to create the source-file manifest."
  ))
  quit(save = "no", status = 0)
}

if (!require_package("readr", log)) {
  write_text_report(report_path, c(
    "# NHANES III Validation Skeleton",
    "",
    "Status: missing R package `readr`."
  ))
  quit(save = "no", status = 0)
}

data <- readr::read_csv(dataset_path, show_col_types = FALSE)
write_text_report(report_path, c(
  "# NHANES III Validation Skeleton",
  "",
  "Status: harmonized validation dataset detected.",
  "",
  sprintf("Rows: %s", nrow(data)),
  sprintf("Columns: %s", ncol(data)),
  "",
  "Next step: add simple weighted descriptive validation tables before fitting any models."
))

log("INFO", sprintf("Wrote %s", report_path))
