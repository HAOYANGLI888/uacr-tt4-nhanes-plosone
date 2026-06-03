source("scripts/project_utils.R")

root <- find_project_root()
configs <- load_project_configs(root)
ensure_project_dirs(root, configs$analysis)
log <- init_logger(root, "06_bidirectional_mr_skeleton")

exposure_template <- project_path(root, configs$analysis$outputs$gwas_exposure_template)
outcome_template <- project_path(root, configs$analysis$outputs$gwas_outcome_template)
report_path <- file.path(root, "outputs", "reports", "06_bidirectional_mr_skeleton_report.md")

dir.create(dirname(exposure_template), recursive = TRUE, showWarnings = FALSE)

template <- data.frame(
  SNP = character(),
  effect_allele = character(),
  other_allele = character(),
  beta = numeric(),
  se = numeric(),
  pval = numeric(),
  eaf = numeric(),
  samplesize = numeric(),
  trait = character(),
  source = character(),
  stringsAsFactors = FALSE
)

if (!file.exists(exposure_template)) {
  utils::write.csv(template, exposure_template, row.names = FALSE)
  log("INFO", sprintf("Created %s", exposure_template))
}
if (!file.exists(outcome_template)) {
  utils::write.csv(template, outcome_template, row.names = FALSE)
  log("INFO", sprintf("Created %s", outcome_template))
}

optional_packages <- c("TwoSampleMR", "ieugwasr", "MRPRESSO")
available <- vapply(optional_packages, require_package, logical(1), logger = log)

write_text_report(report_path, c(
  "# Bidirectional MR Skeleton",
  "",
  "Status: GWAS templates created or confirmed.",
  "",
  "Direction A: genetically predicted thyroid traits -> UACR or albuminuria traits.",
  "Direction B: genetically predicted UACR or kidney traits -> thyroid traits.",
  "",
  sprintf("Exposure template: `%s`", exposure_template),
  sprintf("Outcome template: `%s`", outcome_template),
  "",
  "Optional MR package status:",
  paste(sprintf("- %s: %s", names(available), ifelse(available, "available", "missing")), collapse = "\n"),
  "",
  "No MR model is run until harmonized GWAS summary statistics are supplied."
))

log("INFO", sprintf("Wrote %s", report_path))
