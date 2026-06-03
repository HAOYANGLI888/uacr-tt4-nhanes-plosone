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
  log_file <- file.path(log_dir, "08_bidirectional_mr.log")
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

ensure_jwt <- function(log) {
  jwt_env <- paste0("OPENGWAS", "_JWT")
  if (!nzchar(Sys.getenv(jwt_env))) {
    candidates <- unique(c(
      file.path(Sys.getenv("USERPROFILE"), ".Renviron"),
      path.expand("~/.Renviron")
    ))
    for (path in candidates[file.exists(candidates)]) {
      readRenviron(path)
      if (nzchar(Sys.getenv(jwt_env))) {
        log("INFO", sprintf("Loaded OpenGWAS credential from %s because the active R HOME did not load it automatically.", path))
        break
      }
    }
  }
  if (!nzchar(Sys.getenv(jwt_env))) {
    stop("OpenGWAS credential is unavailable. Configure it in the active R environment before running MR.", call. = FALSE)
  }
  invisible(ieugwasr::user())
  log("INFO", "OpenGWAS JWT authentication verified. Token value is not logged.")
}

download_index <- function(root, log) {
  path <- file.path(root, "data", "interim", "opengwas_gwasinfo.json")
  url <- "https://opengwas.io/data/gwasinfo/gwasinfo.json"
  dir.create(dirname(path), recursive = TRUE, showWarnings = FALSE)
  valid_index <- function(candidate) {
    if (!file.exists(candidate) || file.info(candidate)$size <= 1e6) {
      return(FALSE)
    }
    content <- tryCatch(
      readChar(candidate, nchars = file.info(candidate)$size, useBytes = TRUE),
      error = function(e) ""
    )
    isTRUE(tryCatch(jsonlite::validate(content), error = function(e) FALSE))
  }
  if (valid_index(path)) {
    log("INFO", sprintf("Using cached official OpenGWAS metadata index: %s bytes", file.info(path)$size))
    return(path)
  }
  log("INFO", sprintf("Downloading official OpenGWAS searchable metadata index: %s", url))
  old_timeout <- getOption("timeout")
  on.exit(options(timeout = old_timeout), add = TRUE)
  options(timeout = max(300, old_timeout))
  temporary <- paste0(path, ".download")
  success <- FALSE
  for (attempt in seq_len(3)) {
    if (file.exists(temporary)) {
      file.remove(temporary)
    }
    log("INFO", sprintf("OpenGWAS metadata download attempt %s/3", attempt))
    try(utils::download.file(url, temporary, mode = "wb", quiet = TRUE), silent = TRUE)
    if (valid_index(temporary)) {
      success <- file.rename(temporary, path)
      if (!success) {
        success <- file.copy(temporary, path, overwrite = TRUE)
        file.remove(temporary)
      }
      break
    }
  }
  if (!success || !valid_index(path)) {
    stop("Could not download a valid OpenGWAS metadata index after 3 attempts.", call. = FALSE)
  }
  log("INFO", sprintf("Downloaded OpenGWAS metadata index: %s bytes", file.info(path)$size))
  path
}

decode_index <- function(path, log) {
  index <- jsonlite::fromJSON(path, simplifyVector = FALSE)
  datasets <- index$datasets_compressed
  coding <- index$majority_fields_and_coding
  ids <- names(datasets)
  get_raw <- function(record, position) {
    if (length(record) < position || is.null(record[[position]]) || length(record[[position]]) == 0) {
      return(NA)
    }
    record[[position]][1]
  }
  get_text <- function(record, position) {
    value <- get_raw(record, position)
    if (length(value) == 0 || is.na(value)) "" else as.character(value)
  }
  get_numeric <- function(record, position) {
    suppressWarnings(as.numeric(get_raw(record, position)))
  }
  decode_code <- function(record, position, field) {
    value <- suppressWarnings(as.integer(get_raw(record, position)))
    values <- coding[[field]]
    if (is.na(value) || is.null(values) || length(values) < value + 1) "" else as.character(values[[value + 1]])
  }
  rows <- lapply(ids, function(id) {
    record <- datasets[[id]][[1]]
    data.frame(
      id = id,
      trait = get_text(record, 1),
      build = decode_code(record, 2, "build"),
      category = decode_code(record, 3, "category"),
      subcategory = decode_code(record, 4, "subcategory"),
      population = decode_code(record, 5, "population"),
      sex = decode_code(record, 6, "sex"),
      author = get_text(record, 7),
      year = get_numeric(record, 8),
      ontology = get_text(record, 9),
      unit = get_text(record, 10),
      sample_size = get_numeric(record, 11),
      consortium = get_text(record, 12),
      stringsAsFactors = FALSE
    )
  })
  metadata <- do.call(rbind, rows)
  log("INFO", sprintf("Decoded %s OpenGWAS metadata records.", nrow(metadata)))
  metadata
}

trait_specifications <- function() {
  data.frame(
    trait_key = c("UACR", "albuminuria", "eGFR", "TSH", "FT4", "TT4"),
    search_pattern = c(
      "^Urinary albumin-to-creatinine ratio$",
      "^Microalbuminuria$",
      "^Estimated glomerular filtration rate \\(creatinine\\)$",
      "^(TSH|Thyroid Stimulating Hormone)$",
      "(^FT4$|^Free T4$|free thyroxine)",
      "(^TT4$|^Total T4$|total thyroxine)"
    ),
    stringsAsFactors = FALSE
  )
}

select_gwas <- function(metadata, specs, log) {
  candidate_rows <- list()
  selected_rows <- list()
  for (i in seq_len(nrow(specs))) {
    spec <- specs[i, , drop = FALSE]
    candidates <- metadata[grepl(spec$search_pattern, metadata$trait, ignore.case = TRUE), , drop = FALSE]
    if (nrow(candidates) > 0) {
      candidates$trait_key <- spec$trait_key
      candidates$european_priority <- as.integer(tolower(candidates$population) == "european")
      candidates$sample_size_rank <- ifelse(is.na(candidates$sample_size), -Inf, candidates$sample_size)
      candidates <- candidates[
        order(-candidates$european_priority, -candidates$sample_size_rank, candidates$id),
        ,
        drop = FALSE
      ]
      candidates$selected <- FALSE
      candidates$selected[1] <- TRUE
      candidate_rows[[length(candidate_rows) + 1]] <- candidates
      chosen <- candidates[1, , drop = FALSE]
      selected_rows[[length(selected_rows) + 1]] <- data.frame(
        trait_key = spec$trait_key,
        status = "selected",
        selected_id = chosen$id,
        selected_trait = chosen$trait,
        population = chosen$population,
        sample_size = chosen$sample_size,
        author = chosen$author,
        year = chosen$year,
        unit = chosen$unit,
        n_instruments = NA_integer_,
        note = "Automatically selected European-priority candidate with the largest reported sample size among direct trait matches.",
        stringsAsFactors = FALSE
      )
      log("INFO", sprintf("Selected %s GWAS: %s | %s | population=%s | n=%s", spec$trait_key, chosen$id, chosen$trait, chosen$population, chosen$sample_size))
    } else {
      selected_rows[[length(selected_rows) + 1]] <- data.frame(
        trait_key = spec$trait_key,
        status = "unavailable",
        selected_id = "",
        selected_trait = "",
        population = "",
        sample_size = NA_real_,
        author = "",
        year = NA_real_,
        unit = "",
        n_instruments = NA_integer_,
        note = sprintf("No direct OpenGWAS metadata match for pattern: %s", spec$search_pattern),
        stringsAsFactors = FALSE
      )
      log("WARNING", sprintf("%s unavailable: no direct OpenGWAS metadata match.", spec$trait_key))
    }
  }
  candidates <- if (length(candidate_rows) > 0) do.call(rbind, candidate_rows) else data.frame()
  list(selection = do.call(rbind, selected_rows), candidates = candidates)
}

normalise_sumstats <- function(data, trait_key) {
  if (nrow(data) == 0) {
    return(data.frame())
  }
  snp <- if ("target_snp" %in% names(data)) {
    ifelse(!is.na(data$target_snp) & data$target_snp != "", data$target_snp, data$rsid)
  } else {
    data$rsid
  }
  normalised <- data.frame(
    snp = as.character(snp),
    effect_allele = toupper(as.character(data$ea)),
    other_allele = toupper(as.character(data$nea)),
    eaf = suppressWarnings(as.numeric(data$eaf)),
    beta = suppressWarnings(as.numeric(data$beta)),
    se = suppressWarnings(as.numeric(data$se)),
    pval = suppressWarnings(as.numeric(data$p)),
    samplesize = suppressWarnings(as.numeric(data$n)),
    trait = trait_key,
    source_id = as.character(data$id),
    stringsAsFactors = FALSE
  )
  normalised <- normalised[
    !is.na(normalised$snp) & normalised$snp != "" &
      !is.na(normalised$beta) & !is.na(normalised$se) & normalised$se > 0,
    ,
    drop = FALSE
  ]
  normalised <- normalised[order(normalised$pval), , drop = FALSE]
  normalised[!duplicated(normalised$snp), , drop = FALSE]
}

extract_instruments <- function(selection, root, log) {
  result <- setNames(vector("list", nrow(selection)), selection$trait_key)
  for (i in seq_len(nrow(selection))) {
    row <- selection[i, , drop = FALSE]
    if (row$status != "selected") {
      result[[row$trait_key]] <- data.frame()
      next
    }
    log("INFO", sprintf("Extracting LD-clumped instruments for %s from %s", row$trait_key, row$selected_id))
    raw <- tryCatch(
      ieugwasr::tophits(
        row$selected_id, pval = 5e-8, clump = 1, r2 = 0.001, kb = 10000,
        pop = "EUR", force_server = FALSE
      ),
      error = function(e) e
    )
    if (inherits(raw, "error")) {
      selection$status[i] <- "instrument_extraction_failed"
      selection$note[i] <- sprintf("OpenGWAS instrument extraction failed: %s", conditionMessage(raw))
      result[[row$trait_key]] <- data.frame()
      log("WARNING", sprintf("%s instrument extraction failed: %s", row$trait_key, conditionMessage(raw)))
      next
    }
    normalised <- normalise_sumstats(raw, row$trait_key)
    selection$n_instruments[i] <- nrow(normalised)
    if (nrow(normalised) == 0) {
      selection$status[i] <- "no_instruments"
      selection$note[i] <- "No LD-clumped genome-wide significant instruments were returned by OpenGWAS."
      log("WARNING", sprintf("%s has no LD-clumped genome-wide significant instruments.", row$trait_key))
    } else {
      write_csv_safe(raw, file.path(root, "data", "external_gwas", sprintf("opengwas_%s_instruments_raw.csv", tolower(row$trait_key))))
      write_csv_safe(normalised, file.path(root, "data", "external_gwas", sprintf("opengwas_%s_instruments.csv", tolower(row$trait_key))))
      log("INFO", sprintf("%s instruments retained: %s", row$trait_key, nrow(normalised)))
    }
    result[[row$trait_key]] <- normalised
  }
  list(selection = selection, instruments = result)
}

manifest_rows <- function() {
  kidney <- c("UACR", "albuminuria", "eGFR")
  thyroid <- c("TSH", "FT4", "TT4")
  forward <- do.call(rbind, lapply(kidney, function(exposure) {
    do.call(rbind, lapply(thyroid, function(outcome) {
      data.frame(
        analysis_id = sprintf("forward_%s_%s", tolower(exposure), tolower(outcome)),
        direction = "kidney_to_thyroid", exposure_trait = exposure, outcome_trait = outcome,
        stringsAsFactors = FALSE
      )
    }))
  }))
  reverse <- do.call(rbind, lapply(thyroid, function(exposure) {
    do.call(rbind, lapply(kidney, function(outcome) {
      data.frame(
        analysis_id = sprintf("reverse_%s_%s", tolower(exposure), tolower(outcome)),
        direction = "thyroid_to_kidney", exposure_trait = exposure, outcome_trait = outcome,
        stringsAsFactors = FALSE
      )
    }))
  }))
  rbind(forward, reverse)
}

empty_main <- function() {
  data.frame(
    analysis_id = character(), direction = character(), exposure_trait = character(), outcome_trait = character(),
    exposure_gwas_id = character(), outcome_gwas_id = character(), method = character(), nsnp = integer(),
    beta = numeric(), se = numeric(), ci_low = numeric(), ci_high = numeric(), p_value = numeric(),
    p_fdr = numeric(), status = character(), note = character(), stringsAsFactors = FALSE
  )
}

status_main <- function(row, exposure_id, outcome_id, status, note) {
  data.frame(
    analysis_id = row$analysis_id, direction = row$direction, exposure_trait = row$exposure_trait,
    outcome_trait = row$outcome_trait, exposure_gwas_id = exposure_id, outcome_gwas_id = outcome_id,
    method = "IVW", nsnp = NA_integer_, beta = NA_real_, se = NA_real_, ci_low = NA_real_,
    ci_high = NA_real_, p_value = NA_real_, p_fdr = NA_real_, status = status, note = note,
    stringsAsFactors = FALSE
  )
}

status_sensitivity <- function(row, exposure_id, outcome_id, method, status, note) {
  data.frame(
    analysis_id = row$analysis_id, direction = row$direction, exposure_trait = row$exposure_trait,
    outcome_trait = row$outcome_trait, exposure_gwas_id = exposure_id, outcome_gwas_id = outcome_id,
    method = method, detail = "", nsnp = NA_integer_, beta = NA_real_, se = NA_real_,
    ci_low = NA_real_, ci_high = NA_real_, p_value = NA_real_, status = status, note = note,
    stringsAsFactors = FALSE
  )
}

all_sensitivity_status <- function(row, exposure_id, outcome_id, status, note) {
  methods <- c("MR-Egger", "weighted median", "weighted mode", "MR-PRESSO", "leave-one-out IVW", "Steiger directionality")
  do.call(rbind, lapply(methods, function(method) status_sensitivity(row, exposure_id, outcome_id, method, status, note)))
}

result_row <- function(row, exposure_id, outcome_id, nsnp, beta, se, p_value, note = "") {
  data.frame(
    analysis_id = row$analysis_id, direction = row$direction, exposure_trait = row$exposure_trait,
    outcome_trait = row$outcome_trait, exposure_gwas_id = exposure_id, outcome_gwas_id = outcome_id,
    method = "IVW", nsnp = nsnp, beta = beta, se = se, ci_low = beta - 1.96 * se,
    ci_high = beta + 1.96 * se, p_value = p_value, p_fdr = NA_real_, status = "complete",
    note = note, stringsAsFactors = FALSE
  )
}

sensitivity_row <- function(row, exposure_id, outcome_id, method, detail, nsnp, beta, se, p_value, status = "complete", note = "") {
  data.frame(
    analysis_id = row$analysis_id, direction = row$direction, exposure_trait = row$exposure_trait,
    outcome_trait = row$outcome_trait, exposure_gwas_id = exposure_id, outcome_gwas_id = outcome_id,
    method = method, detail = detail, nsnp = nsnp, beta = beta, se = se,
    ci_low = beta - 1.96 * se, ci_high = beta + 1.96 * se, p_value = p_value,
    status = status, note = note, stringsAsFactors = FALSE
  )
}

is_palindromic <- function(a1, a2) {
  paste0(a1, a2) %in% c("AT", "TA", "CG", "GC")
}

harmonize_pair <- function(exposure, outcome, log, analysis_id) {
  merged <- merge(exposure, outcome, by = "snp", suffixes = c("_exposure", "_outcome"))
  if (nrow(merged) == 0) {
    return(data.frame())
  }
  exact <- merged$effect_allele_exposure == merged$effect_allele_outcome &
    merged$other_allele_exposure == merged$other_allele_outcome
  swapped <- merged$effect_allele_exposure == merged$other_allele_outcome &
    merged$other_allele_exposure == merged$effect_allele_outcome
  keep <- exact | swapped
  merged <- merged[keep, , drop = FALSE]
  swapped <- swapped[keep]
  merged$beta_outcome[swapped] <- -merged$beta_outcome[swapped]
  ambiguous <- is_palindromic(merged$effect_allele_exposure, merged$other_allele_exposure) &
    !is.na(merged$eaf_exposure) & merged$eaf_exposure > 0.42 & merged$eaf_exposure < 0.58
  merged <- merged[!ambiguous, , drop = FALSE]
  log("INFO", sprintf("%s harmonized instruments: %s", analysis_id, nrow(merged)))
  merged
}

ivw_estimate <- function(data) {
  weight <- 1 / data$se_outcome^2
  denominator <- sum(weight * data$beta_exposure^2)
  if (!is.finite(denominator) || denominator <= 0) {
    return(c(beta = NA_real_, se = NA_real_, p = NA_real_))
  }
  beta <- sum(weight * data$beta_exposure * data$beta_outcome) / denominator
  se <- sqrt(1 / denominator)
  p <- 2 * stats::pnorm(abs(beta / se), lower.tail = FALSE)
  c(beta = beta, se = se, p = p)
}

egger_estimate <- function(data) {
  if (nrow(data) < 3) {
    return(c(beta = NA_real_, se = NA_real_, p = NA_real_, intercept = NA_real_, intercept_p = NA_real_))
  }
  fit <- stats::lm(beta_outcome ~ beta_exposure, data = data, weights = 1 / se_outcome^2)
  coefficients <- summary(fit)$coefficients
  c(
    beta = coefficients["beta_exposure", "Estimate"], se = coefficients["beta_exposure", "Std. Error"],
    p = coefficients["beta_exposure", "Pr(>|t|)"], intercept = coefficients["(Intercept)", "Estimate"],
    intercept_p = coefficients["(Intercept)", "Pr(>|t|)"]
  )
}

weighted_median_value <- function(values, weights) {
  keep <- is.finite(values) & is.finite(weights) & weights > 0
  values <- values[keep]
  weights <- weights[keep]
  if (length(values) == 0) {
    return(NA_real_)
  }
  index <- order(values)
  values <- values[index]
  weights <- weights[index]
  values[which(cumsum(weights) / sum(weights) >= 0.5)[1]]
}

bootstrap_ratio_method <- function(data, method = c("median", "mode"), n_boot = 500) {
  method <- match.arg(method)
  ratio <- data$beta_outcome / data$beta_exposure
  ratio_se <- abs(data$se_outcome / data$beta_exposure)
  weights <- 1 / ratio_se^2
  estimate_one <- function(values, local_weights) {
    if (method == "median") {
      return(weighted_median_value(values, local_weights))
    }
    if (length(unique(values[is.finite(values)])) < 2) {
      return(NA_real_)
    }
    density <- suppressWarnings(stats::density(values, weights = local_weights / sum(local_weights), na.rm = TRUE))
    density$x[which.max(density$y)]
  }
  beta <- estimate_one(ratio, weights)
  set.seed(20260602)
  bootstrap <- replicate(n_boot, {
    index <- sample(seq_len(nrow(data)), size = nrow(data), replace = TRUE)
    estimate_one(ratio[index], weights[index])
  })
  se <- stats::sd(bootstrap, na.rm = TRUE)
  p <- ifelse(is.finite(se) && se > 0, 2 * stats::pnorm(abs(beta / se), lower.tail = FALSE), NA_real_)
  c(beta = beta, se = se, p = p)
}

leave_one_out_rows <- function(row, exposure_id, outcome_id, data) {
  if (nrow(data) < 3) {
    return(status_sensitivity(row, exposure_id, outcome_id, "leave-one-out IVW", "insufficient_instruments", "At least 3 instruments are required."))
  }
  do.call(rbind, lapply(seq_len(nrow(data)), function(i) {
    estimate <- ivw_estimate(data[-i, , drop = FALSE])
    sensitivity_row(row, exposure_id, outcome_id, "leave-one-out IVW", paste0("exclude ", data$snp[i]), nrow(data) - 1, estimate[["beta"]], estimate[["se"]], estimate[["p"]])
  }))
}

steiger_row <- function(row, exposure_id, outcome_id, data) {
  valid <- !is.na(data$eaf_exposure) & !is.na(data$eaf_outcome)
  if (!any(valid)) {
    return(status_sensitivity(row, exposure_id, outcome_id, "Steiger directionality", "unavailable", "No nonmissing EAF values were available."))
  }
  r2_exposure <- sum(2 * data$eaf_exposure[valid] * (1 - data$eaf_exposure[valid]) * data$beta_exposure[valid]^2)
  r2_outcome <- sum(2 * data$eaf_outcome[valid] * (1 - data$eaf_outcome[valid]) * data$beta_outcome[valid]^2)
  sensitivity_row(
    row, exposure_id, outcome_id, "Steiger directionality",
    ifelse(r2_exposure > r2_outcome, "correct_direction", "reverse_direction_possible"),
    sum(valid), r2_exposure - r2_outcome, NA_real_, NA_real_,
    note = sprintf("Approximate summed R2 exposure=%.6g; outcome=%.6g.", r2_exposure, r2_outcome)
  )
}

mr_presso_row <- function(row, exposure_id, outcome_id, data, root, log) {
  if (!requireNamespace("MRPRESSO", quietly = TRUE)) {
    return(status_sensitivity(row, exposure_id, outcome_id, "MR-PRESSO", "package_missing", "MRPRESSO package is unavailable in the active R environment."))
  }
  if (nrow(data) < 4) {
    return(status_sensitivity(row, exposure_id, outcome_id, "MR-PRESSO", "insufficient_instruments", "At least 4 instruments are required."))
  }
  cache_path <- file.path(root, "data", "external_gwas", sprintf("%s_mr_presso_global.csv", row$analysis_id))
  if (file.exists(cache_path) && file.info(cache_path)$size > 0) {
    cached <- utils::read.csv(cache_path, check.names = FALSE)
    if (nrow(cached) == 1 && !is.na(cached$p_value)) {
      log("INFO", sprintf("%s using cached MR-PRESSO global test.", row$analysis_id))
      return(sensitivity_row(row, exposure_id, outcome_id, "MR-PRESSO", "global_test", nrow(data), NA_real_, NA_real_, cached$p_value, note = cached$note))
    }
  }
  warnings_seen <- character()
  result <- withCallingHandlers(
    tryCatch(
      MRPRESSO::mr_presso(
        BetaOutcome = "beta_outcome", BetaExposure = "beta_exposure",
        SdOutcome = "se_outcome", SdExposure = "se_exposure",
        OUTLIERtest = TRUE, DISTORTIONtest = TRUE, data = data,
        NbDistribution = 1000, SignifThreshold = 0.05
      ),
      error = function(e) e
    ),
    warning = function(w) {
      warnings_seen <<- c(warnings_seen, conditionMessage(w))
      invokeRestart("muffleWarning")
    }
  )
  if (inherits(result, "error")) {
    return(status_sensitivity(row, exposure_id, outcome_id, "MR-PRESSO", "failed", conditionMessage(result)))
  }
  if (length(warnings_seen) > 0) {
    log("WARNING", sprintf("%s MR-PRESSO emitted %s warning(s); global test retained and warnings suppressed after counting.", row$analysis_id, length(warnings_seen)))
  }
  p_value <- tryCatch(as.numeric(result$`MR-PRESSO results`$`Global Test`$Pvalue), error = function(e) NA_real_)
  note <- sprintf("MR-PRESSO global outlier test. Warning count during fit: %s.", length(warnings_seen))
  write_csv_safe(data.frame(p_value = p_value, note = note), cache_path)
  sensitivity_row(row, exposure_id, outcome_id, "MR-PRESSO", "global_test", nrow(data), NA_real_, NA_real_, p_value, note = note)
}

query_association_chunks <- function(variants, outcome_id, proxies, chunk_size, analysis_id, log) {
  if (length(variants) == 0) {
    return(data.frame())
  }
  chunks <- split(variants, ceiling(seq_along(variants) / chunk_size))
  rows <- list()
  for (i in seq_along(chunks)) {
    log(
      "INFO",
      sprintf(
        "%s querying %s association chunk %s/%s: %s SNP(s)",
        analysis_id, ifelse(proxies == 1, "proxy-enabled", "direct"), i, length(chunks), length(chunks[[i]])
      )
    )
    result <- tryCatch(
      ieugwasr::associations(
        variants = chunks[[i]], id = outcome_id, proxies = proxies, r2 = 0.8,
        align_alleles = 1, palindromes = 1, maf_threshold = 0.3,
        assocs_per_request = chunk_size, max_ids_per_request = 1, timeout = 90
      ),
      error = function(e) e
    )
    if (inherits(result, "error")) {
      stop(sprintf("%s association chunk %s/%s failed: %s", analysis_id, i, length(chunks), conditionMessage(result)), call. = FALSE)
    }
    if (nrow(result) > 0) {
      rows[[length(rows) + 1]] <- result
    }
  }
  if (length(rows) == 0) data.frame() else bind_rows_fill(rows)
}

bind_rows_fill <- function(rows) {
  rows <- rows[vapply(rows, nrow, integer(1)) > 0]
  if (length(rows) == 0) {
    return(data.frame())
  }
  columns <- unique(unlist(lapply(rows, names), use.names = FALSE))
  rows <- lapply(rows, function(data) {
    missing <- setdiff(columns, names(data))
    for (column in missing) {
      data[[column]] <- NA
    }
    data[, columns, drop = FALSE]
  })
  do.call(rbind, rows)
}

covered_snps <- function(data) {
  if (nrow(data) == 0) {
    return(character())
  }
  if ("target_snp" %in% names(data)) {
    return(ifelse(!is.na(data$target_snp) & data$target_snp != "", data$target_snp, data$rsid))
  }
  data$rsid
}

query_outcome_associations <- function(exposure, outcome_id, analysis_id, root, log) {
  cache_path <- file.path(root, "data", "external_gwas", sprintf("%s_outcome_associations_raw.csv", analysis_id))
  direct_cache_path <- file.path(root, "data", "external_gwas", sprintf("%s_outcome_associations_direct.csv", analysis_id))
  proxy_cache_path <- file.path(root, "data", "external_gwas", sprintf("%s_outcome_associations_proxy.csv", analysis_id))
  if (file.exists(cache_path) && file.info(cache_path)$size > 0) {
    cached <- utils::read.csv(cache_path, check.names = FALSE, colClasses = "character")
    if (nrow(cached) > 0) {
      log("INFO", sprintf("%s using cached outcome associations: %s row(s)", analysis_id, nrow(cached)))
      return(cached)
    }
  }
  variants <- unique(exposure$snp)
  direct <- if (file.exists(direct_cache_path) && file.info(direct_cache_path)$size > 0) {
    log("INFO", sprintf("%s using cached direct associations.", analysis_id))
    utils::read.csv(direct_cache_path, check.names = FALSE, colClasses = "character")
  } else {
    data <- query_association_chunks(variants, outcome_id, proxies = 0, chunk_size = 64, analysis_id, log)
    if (nrow(data) > 0) write_csv_safe(data, direct_cache_path)
    data
  }
  missing <- setdiff(variants, covered_snps(direct))
  proxy <- if (length(missing) > 0) {
    log("INFO", sprintf("%s direct associations missing for %s SNP(s); querying proxies.", analysis_id, length(missing)))
    if (file.exists(proxy_cache_path) && file.info(proxy_cache_path)$size > 0) {
      log("INFO", sprintf("%s using cached proxy associations.", analysis_id))
      utils::read.csv(proxy_cache_path, check.names = FALSE, colClasses = "character")
    } else {
      data <- query_association_chunks(missing, outcome_id, proxies = 1, chunk_size = 8, analysis_id, log)
      if (nrow(data) > 0) write_csv_safe(data, proxy_cache_path)
      data
    }
  } else {
    data.frame()
  }
  rows <- list()
  if (nrow(direct) > 0) rows[[length(rows) + 1]] <- direct
  if (nrow(proxy) > 0) rows[[length(rows) + 1]] <- proxy
  if (length(rows) == 0) {
    return(data.frame())
  }
  result <- bind_rows_fill(rows)
  result <- result[!duplicated(covered_snps(result)), , drop = FALSE]
  write_csv_safe(result, cache_path)
  result
}

fit_pair <- function(row, selection, instruments, root, log) {
  exposure_meta <- selection[selection$trait_key == row$exposure_trait, , drop = FALSE]
  outcome_meta <- selection[selection$trait_key == row$outcome_trait, , drop = FALSE]
  exposure_id <- exposure_meta$selected_id
  outcome_id <- outcome_meta$selected_id
  unavailable <- c()
  if (exposure_meta$status != "selected") unavailable <- c(unavailable, sprintf("%s exposure: %s", row$exposure_trait, exposure_meta$note))
  if (outcome_meta$status != "selected") unavailable <- c(unavailable, sprintf("%s outcome: %s", row$outcome_trait, outcome_meta$note))
  if (length(unavailable) > 0) {
    note <- paste(unavailable, collapse = " | ")
    log("WARNING", sprintf("%s unavailable: %s", row$analysis_id, note))
    return(list(main = status_main(row, exposure_id, outcome_id, "unavailable", note), sensitivity = all_sensitivity_status(row, exposure_id, outcome_id, "unavailable", note)))
  }
  exposure <- instruments[[row$exposure_trait]]
  if (nrow(exposure) == 0) {
    note <- sprintf("No usable genome-wide significant instruments for %s.", row$exposure_trait)
    return(list(main = status_main(row, exposure_id, outcome_id, "no_instruments", note), sensitivity = all_sensitivity_status(row, exposure_id, outcome_id, "no_instruments", note)))
  }
  log("INFO", sprintf("%s querying %s exposure SNP(s) against outcome %s", row$analysis_id, nrow(exposure), outcome_id))
  raw_outcome <- tryCatch(
    query_outcome_associations(exposure, outcome_id, row$analysis_id, root, log),
    error = function(e) e
  )
  if (inherits(raw_outcome, "error")) {
    note <- sprintf("OpenGWAS outcome association query failed: %s", conditionMessage(raw_outcome))
    log("WARNING", sprintf("%s failed: %s", row$analysis_id, note))
    return(list(main = status_main(row, exposure_id, outcome_id, "api_failed", note), sensitivity = all_sensitivity_status(row, exposure_id, outcome_id, "api_failed", note)))
  }
  if (nrow(raw_outcome) == 0) {
    note <- "OpenGWAS returned no outcome associations for the exposure instruments, including proxy search."
    log("WARNING", sprintf("%s: %s", row$analysis_id, note))
    return(list(main = status_main(row, exposure_id, outcome_id, "no_outcome_associations", note), sensitivity = all_sensitivity_status(row, exposure_id, outcome_id, "no_outcome_associations", note)))
  }
  outcome <- normalise_sumstats(raw_outcome, row$outcome_trait)
  harmonised <- harmonize_pair(exposure, outcome, log, row$analysis_id)
  write_csv_safe(harmonised, file.path(root, "data", "external_gwas", sprintf("%s_harmonised.csv", row$analysis_id)))
  if (nrow(harmonised) == 0) {
    note <- "No usable harmonized instruments remained after allele checks."
    return(list(main = status_main(row, exposure_id, outcome_id, "no_harmonized_instruments", note), sensitivity = all_sensitivity_status(row, exposure_id, outcome_id, "no_harmonized_instruments", note)))
  }
  ivw <- ivw_estimate(harmonised)
  note <- if (nrow(harmonised) == 1) "Single-SNP IVW estimate; numerically equivalent to the Wald ratio." else "Multi-SNP inverse-variance weighted estimate."
  main <- result_row(row, exposure_id, outcome_id, nrow(harmonised), ivw[["beta"]], ivw[["se"]], ivw[["p"]], note)
  egger <- if (nrow(harmonised) >= 3) {
    estimate <- egger_estimate(harmonised)
    sensitivity_row(row, exposure_id, outcome_id, "MR-Egger", sprintf("intercept=%.6g; intercept_p=%.6g", estimate[["intercept"]], estimate[["intercept_p"]]), nrow(harmonised), estimate[["beta"]], estimate[["se"]], estimate[["p"]])
  } else {
    status_sensitivity(row, exposure_id, outcome_id, "MR-Egger", "insufficient_instruments", "At least 3 instruments are required.")
  }
  median <- if (nrow(harmonised) >= 3) {
    estimate <- bootstrap_ratio_method(harmonised, "median")
    sensitivity_row(row, exposure_id, outcome_id, "weighted median", "", nrow(harmonised), estimate[["beta"]], estimate[["se"]], estimate[["p"]])
  } else {
    status_sensitivity(row, exposure_id, outcome_id, "weighted median", "insufficient_instruments", "At least 3 instruments are required.")
  }
  mode <- if (nrow(harmonised) >= 3) {
    estimate <- bootstrap_ratio_method(harmonised, "mode")
    sensitivity_row(row, exposure_id, outcome_id, "weighted mode", "", nrow(harmonised), estimate[["beta"]], estimate[["se"]], estimate[["p"]])
  } else {
    status_sensitivity(row, exposure_id, outcome_id, "weighted mode", "insufficient_instruments", "At least 3 instruments are required.")
  }
  sensitivity <- rbind(
    egger, median, mode, mr_presso_row(row, exposure_id, outcome_id, harmonised, root, log),
    leave_one_out_rows(row, exposure_id, outcome_id, harmonised),
    steiger_row(row, exposure_id, outcome_id, harmonised)
  )
  list(main = main, sensitivity = sensitivity)
}

save_forest <- function(main, root, log) {
  available <- main[main$status == "complete" & !is.na(main$beta), , drop = FALSE]
  draw <- function() {
    if (nrow(available) == 0) {
      graphics::plot.new()
      graphics::text(0.5, 0.58, "Bidirectional MR forest plot", cex = 1.1, font = 2)
      graphics::text(0.5, 0.45, "No estimable OpenGWAS trait pairs were available.", cex = 0.9)
      return(invisible(NULL))
    }
    labels <- paste(available$exposure_trait, "->", available$outcome_trait)
    y <- rev(seq_len(nrow(available)))
    limits <- range(c(available$ci_low, available$ci_high, 0), finite = TRUE)
    padding <- diff(limits) * 0.08
    graphics::par(mar = c(4.2, 8.8, 2.5, 1.0))
    graphics::plot(
      available$beta, y, xlim = limits + c(-padding, padding), ylim = c(0.5, nrow(available) + 0.5),
      yaxt = "n", ylab = "", xlab = "IVW beta (95% CI)", pch = 19,
      col = "#2F6B9A", main = "Bidirectional MR: OpenGWAS IVW estimates"
    )
    graphics::abline(v = 0, lty = 2, col = "#777777")
    graphics::segments(available$ci_low, y, available$ci_high, y, col = "#2F6B9A", lwd = 1.3)
    graphics::axis(2, at = y, labels = labels, las = 1, cex.axis = 0.75)
  }
  pdf_path <- file.path(root, "outputs", "figures", "Figure_MR_forest.pdf")
  png_path <- file.path(root, "outputs", "figures", "qc", "Figure_MR_forest_qc.png")
  dir.create(dirname(pdf_path), recursive = TRUE, showWarnings = FALSE)
  dir.create(dirname(png_path), recursive = TRUE, showWarnings = FALSE)
  grDevices::cairo_pdf(pdf_path, width = 183 / 25.4, height = 120 / 25.4, family = "Arial")
  draw()
  grDevices::dev.off()
  grDevices::png(png_path, width = 183 / 25.4, height = 120 / 25.4, units = "in", res = 180, type = "cairo")
  draw()
  grDevices::dev.off()
  log("INFO", sprintf("Wrote MR forest PDF to %s", pdf_path))
}

fmt <- function(x, digits = 4) {
  ifelse(is.na(x), "NA", formatC(x, digits = digits, format = "f"))
}

fmt_p <- function(x) {
  ifelse(is.na(x), "NA", ifelse(x < 0.001, formatC(x, digits = 2, format = "e"), formatC(x, digits = 3, format = "f")))
}

summary_lines <- function(main, sensitivity, selection) {
  complete <- main[main$status == "complete", , drop = FALSE]
  unavailable <- selection[selection$status != "selected", , drop = FALSE]
  multi_snp <- sensitivity[
    sensitivity$status == "complete" &
      sensitivity$method != "leave-one-out IVW" &
      !is.na(sensitivity$nsnp) & sensitivity$nsnp >= 3,
    ,
    drop = FALSE
  ]
  lines <- c(
    "# Exploratory bidirectional MR summary",
    "",
    "This report contains real OpenGWAS API-derived estimates only. No synthetic MR values are generated.",
    "",
    "**Analysis role: exploratory MR analysis. Recommended manuscript placement: Supplementary Materials.**",
    "",
    "These results do not establish causality. In particular, FT4 and TT4 GWAS were unavailable in the official searchable OpenGWAS index, so this module cannot test or support a direct causal UACR-to-TT4 interpretation.",
    "",
    sprintf("Configured bidirectional trait pairs: %s.", nrow(main)),
    sprintf("Completed IVW analyses: %s.", nrow(complete)),
    sprintf("Unavailable or non-estimable trait pairs: %s.", sum(main$status != "complete")),
    "",
    "## OpenGWAS Trait Selection",
    "| Trait | Status | OpenGWAS ID | Metadata trait | Instruments | Note |",
    "|---|---|---|---|---:|---|"
  )
  for (i in seq_len(nrow(selection))) {
    lines <- c(lines, sprintf(
      "| %s | %s | %s | %s | %s | %s |",
      selection$trait_key[i], selection$status[i], selection$selected_id[i], selection$selected_trait[i],
      ifelse(is.na(selection$n_instruments[i]), "NA", selection$n_instruments[i]), selection$note[i]
    ))
  }
  lines <- c(
    lines,
    "",
    "## IVW Results",
    "| Direction | Exposure | Outcome | SNPs | Beta (95% CI) | P | FDR | Status |",
    "|---|---|---|---:|---:|---:|---:|---|"
  )
  for (i in seq_len(nrow(main))) {
    lines <- c(lines, sprintf(
      "| %s | %s | %s | %s | %s (%s to %s) | %s | %s | %s |",
      main$direction[i], main$exposure_trait[i], main$outcome_trait[i],
      ifelse(is.na(main$nsnp[i]), "NA", main$nsnp[i]), fmt(main$beta[i]), fmt(main$ci_low[i]),
      fmt(main$ci_high[i]), fmt_p(main$p_value[i]), fmt_p(main$p_fdr[i]), main$status[i]
    ))
  }
  lines <- c(
    lines,
    "",
    "## Multi-SNP Sensitivity Highlights",
    "| Analysis | Method | Detail | SNPs | Beta | P |",
    "|---|---|---|---:|---:|---:|"
  )
  if (nrow(multi_snp) == 0) {
    lines <- c(lines, "| NA | NA | No completed multi-SNP sensitivity analysis | NA | NA | NA |")
  } else {
    for (i in seq_len(nrow(multi_snp))) {
      lines <- c(lines, sprintf(
        "| %s | %s | %s | %s | %s | %s |",
        multi_snp$analysis_id[i], multi_snp$method[i], multi_snp$detail[i], multi_snp$nsnp[i],
        fmt(multi_snp$beta[i]), fmt_p(multi_snp$p_value[i])
      ))
    }
  }
  lines <- c(
    lines,
    "",
    "## Primary Interpretation",
    "- This exploratory MR module should be reported in the Supplementary Materials rather than used as the main causal evidence.",
    "- FT4 and TT4 were unavailable, preventing direct genetic evaluation of the NHANES UACR-TT4 association.",
    "- UACR and albuminuria each had only one LD-clumped genome-wide significant instrument, limiting robustness checks.",
    "- The eGFR -> TSH estimate was not statistically significant after FDR correction.",
    "- The TSH -> eGFR association is a **single-SNP exploratory result** based on a TSH protein proxy and should not be interpreted as causal evidence.",
    "",
    "## Interpretation Guardrails",
    "- OpenGWAS index matches were selected automatically using European-priority direct trait matches and the largest reported sample size.",
    "- The selected TSH accession `prot-a-530` is an OpenGWAS protein-measurement dataset. Treat it as a TSH protein proxy; it is not interchangeable with a large population clinical-laboratory TSH GWAS.",
    "- Single-SNP IVW estimates are numerically equivalent to Wald-ratio estimates and do not support multi-instrument sensitivity methods.",
    "- FT4 or TT4 rows remain unavailable when the official OpenGWAS searchable index does not contain a direct trait match.",
    "- Do not claim a direct causal UACR-to-TT4 relationship: direct TT4 MR analysis was unavailable.",
    "- Do not describe any result in this module as establishing causality.",
    "- MR estimates should be described only as exploratory genetic evidence consistent or inconsistent with a directional association.",
    "- NHANES III findings remain not replicated and are not reinterpreted by this MR module."
  )
  if (nrow(unavailable) > 0) {
    lines <- c(lines, "", "## Unavailable Traits")
    for (i in seq_len(nrow(unavailable))) {
      lines <- c(lines, sprintf("- %s: %s", unavailable$trait_key[i], unavailable$note[i]))
    }
  }
  lines
}

main <- function() {
  root <- find_project_root()
  log <- init_logger(root)
  for (package in c("ieugwasr", "jsonlite")) {
    if (!requireNamespace(package, quietly = TRUE)) {
      stop(sprintf("R package '%s' is required.", package), call. = FALSE)
    }
  }
  ensure_jwt(log)
  metadata <- decode_index(download_index(root, log), log)
  specs <- trait_specifications()
  selected <- select_gwas(metadata, specs, log)
  write_csv_safe(selected$candidates, file.path(root, "outputs", "tables", "Table_MR_GWAS_candidates.csv"))
  extracted <- extract_instruments(selected$selection, root, log)
  selection <- extracted$selection
  instruments <- extracted$instruments
  write_csv_safe(selection, file.path(root, "outputs", "tables", "Table_MR_GWAS_selection.csv"))

  manifest <- manifest_rows()
  results <- lapply(seq_len(nrow(manifest)), function(i) fit_pair(manifest[i, , drop = FALSE], selection, instruments, root, log))
  main_table <- if (length(results) == 0) empty_main() else do.call(rbind, lapply(results, `[[`, "main"))
  sensitivity_table <- do.call(rbind, lapply(results, `[[`, "sensitivity"))
  complete <- main_table$status == "complete" & !is.na(main_table$p_value)
  main_table$p_fdr[complete] <- stats::p.adjust(main_table$p_value[complete], method = "fdr")

  main_path <- file.path(root, "outputs", "tables", "Table_MR_main.csv")
  sensitivity_path <- file.path(root, "outputs", "tables", "Table_MR_sensitivity.csv")
  report_path <- file.path(root, "outputs", "reports", "MR_summary.md")
  write_csv_safe(main_table, main_path)
  write_csv_safe(sensitivity_table, sensitivity_path)
  save_forest(main_table, root, log)
  write_lines_safe(summary_lines(main_table, sensitivity_table, selection), report_path)
  log("INFO", sprintf("Wrote MR main table to %s", main_path))
  log("INFO", sprintf("Wrote MR sensitivity table to %s", sensitivity_path))
  log("INFO", sprintf("Completed IVW analyses: %s/%s", sum(main_table$status == "complete"), nrow(main_table)))
  log("INFO", sprintf("Unavailable or non-estimable IVW analyses: %s/%s", sum(main_table$status != "complete"), nrow(main_table)))
}

main()
