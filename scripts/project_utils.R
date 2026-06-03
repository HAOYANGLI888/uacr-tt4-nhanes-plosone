find_project_root <- function(start = NULL) {
  if (is.null(start)) {
    start <- normalizePath(getwd(), winslash = "/", mustWork = TRUE)
  }
  current <- normalizePath(start, winslash = "/", mustWork = TRUE)
  repeat {
    markers <- c(
      file.path(current, "config", "analysis_plan.yaml"),
      file.path(current, "config", "variables_discovery.yaml"),
      file.path(current, "config", "variables_validation_nhanes3.yaml")
    )
    if (all(file.exists(markers))) {
      return(current)
    }
    parent <- dirname(current)
    if (identical(parent, current)) {
      stop("Could not find thyroid_uacr_routeB project root.", call. = FALSE)
    }
    current <- parent
  }
}

require_package <- function(package, logger = NULL) {
  ok <- requireNamespace(package, quietly = TRUE)
  if (!ok && !is.null(logger)) {
    logger("WARN", sprintf("R package '%s' is not installed.", package))
  }
  ok
}

load_yaml_config <- function(path) {
  if (!require_package("yaml")) {
    stop("R package 'yaml' is required.", call. = FALSE)
  }
  yaml::read_yaml(path)
}

load_project_configs <- function(root) {
  list(
    analysis = load_yaml_config(file.path(root, "config", "analysis_plan.yaml")),
    discovery = load_yaml_config(file.path(root, "config", "variables_discovery.yaml")),
    validation = load_yaml_config(file.path(root, "config", "variables_validation_nhanes3.yaml"))
  )
}

project_path <- function(root, path) {
  if (grepl("^([A-Za-z]:|/|\\\\)", path)) {
    normalizePath(path, winslash = "/", mustWork = FALSE)
  } else {
    file.path(root, path)
  }
}

ensure_project_dirs <- function(root, analysis_config) {
  for (path in unlist(analysis_config$paths, use.names = FALSE)) {
    dir.create(project_path(root, path), recursive = TRUE, showWarnings = FALSE)
  }
}

init_logger <- function(root, script_stem) {
  log_dir <- file.path(root, "outputs", "logs")
  dir.create(log_dir, recursive = TRUE, showWarnings = FALSE)
  log_file <- file.path(log_dir, sprintf("%s_%s.log", script_stem, format(Sys.time(), "%Y%m%d_%H%M%S")))

  logger <- function(level, message) {
    line <- sprintf("%s | %s | %s", format(Sys.time(), "%Y-%m-%d %H:%M:%S"), level, message)
    cat(line, "\n")
    cat(line, "\n", file = log_file, append = TRUE)
  }

  logger("INFO", sprintf("Logging to %s", log_file))
  logger
}

write_text_report <- function(path, lines) {
  dir.create(dirname(path), recursive = TRUE, showWarnings = FALSE)
  writeLines(lines, con = path, useBytes = TRUE)
}
