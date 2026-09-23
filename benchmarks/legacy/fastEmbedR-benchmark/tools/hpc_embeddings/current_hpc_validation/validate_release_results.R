#!/usr/bin/env Rscript

parse_args <- function(x) {
  out <- list()
  for (arg in x) {
    if (!startsWith(arg, "--")) next
    fields <- strsplit(sub("^--", "", arg), "=", fixed = TRUE)[[1L]]
    out[[gsub("-", "_", fields[[1L]])]] <- paste(fields[-1L], collapse = "=")
  }
  out
}

`%||%` <- function(x, y) if (is.null(x) || !length(x)) y else x

read_env_file <- function(path) {
  lines <- trimws(readLines(path, warn = FALSE))
  lines <- lines[nzchar(lines) & !startsWith(lines, "#")]
  fields <- strsplit(lines, "=", fixed = TRUE)
  stats::setNames(
    vapply(fields, function(x) paste(x[-1L], collapse = "="), character(1)),
    vapply(fields, `[[`, character(1), 1L)
  )
}

sha256_file <- function(path) {
  command <- Sys.which("sha256sum")
  arguments <- path
  if (!nzchar(command)) {
    command <- Sys.which("shasum")
    arguments <- c("-a", "256", path)
  }
  if (!nzchar(command)) {
    stop("No SHA-256 utility is available.", call. = FALSE)
  }
  output <- system2(command, arguments, stdout = TRUE, stderr = TRUE)
  status <- attr(output, "status")
  if ((!is.null(status) && status != 0L) || !length(output)) {
    stop("SHA-256 calculation failed for ", path, ".", call. = FALSE)
  }
  strsplit(trimws(output[[1L]]), "[[:space:]]+")[[1L]][[1L]]
}

args <- parse_args(commandArgs(trailingOnly = TRUE))
run_root <- normalizePath(
  args$run_root %||% stop("--run-root is required.", call. = FALSE),
  mustWork = TRUE
)
identity_path <- normalizePath(
  args$identity %||% stop("--identity is required.", call. = FALSE),
  mustWork = TRUE
)

identity <- read_env_file(identity_path)
required_identity <- c(
  "FASTEMBEDR_RELEASE_TAG", "FASTEMBEDR_RELEASE_VERSION",
  "FASTEMBEDR_RELEASE_COMMIT",
  "FASTEMBEDR_SOURCE_ARCHIVE_SHA256", "FASTEMBEDR_PACKAGE_TARBALL_SHA256",
  "FASTEMBEDR_DLL_SHA256", "FASTEMBEDR_IMAGE_SHA256",
  "FASTEMBEDR_BENCHMARK_COMMIT", "FASTEMBEDR_RESULT_DOI"
)
missing_identity <- setdiff(required_identity, names(identity))
if (length(missing_identity) || any(!nzchar(identity[required_identity]))) {
  stop("The validated release identity is incomplete.", call. = FALSE)
}

files <- list.files(
  run_root, pattern = "^benchmark_runs\\.csv$", recursive = TRUE,
  full.names = TRUE
)
if (!length(files)) stop("No benchmark_runs.csv files were found.", call. = FALSE)

tables <- lapply(files, function(path) {
  value <- read.csv(
    path, stringsAsFactors = FALSE, check.names = FALSE,
    colClasses = "character"
  )
  value$result_file <- path
  value
})
common <- Reduce(intersect, lapply(tables, names))
tables <- lapply(tables, `[`, common)
runs <- do.call(rbind, tables)
fast <- runs[startsWith(runs$method, "fastEmbedR") & runs$status == "success", , drop = FALSE]
if (!nrow(fast)) stop("No successful fastEmbedR rows were found.", call. = FALSE)

required_columns <- c(
  "fastEmbedR_release_tag", "fastEmbedR_version", "fastEmbedR_commit",
  "fastEmbedR_dll_sha256",
  "fastEmbedR_source_archive_sha256", "fastEmbedR_package_tarball_sha256",
  "fastEmbedR_image_sha256", "benchmark_commit",
  "result_archive_doi", "quality_sample_rows_file",
  "quality_sample_sha256", "requested_backend", "actual_backend"
)
missing_columns <- setdiff(required_columns, names(fast))
if (length(missing_columns)) {
  stop("Result identity columns are missing: ", paste(missing_columns, collapse = ", "), call. = FALSE)
}

expected <- c(
  fastEmbedR_release_tag = identity[["FASTEMBEDR_RELEASE_TAG"]],
  fastEmbedR_version = identity[["FASTEMBEDR_RELEASE_VERSION"]],
  fastEmbedR_commit = identity[["FASTEMBEDR_RELEASE_COMMIT"]],
  fastEmbedR_source_archive_sha256 =
    identity[["FASTEMBEDR_SOURCE_ARCHIVE_SHA256"]],
  fastEmbedR_package_tarball_sha256 =
    identity[["FASTEMBEDR_PACKAGE_TARBALL_SHA256"]],
  fastEmbedR_dll_sha256 = identity[["FASTEMBEDR_DLL_SHA256"]],
  fastEmbedR_image_sha256 = identity[["FASTEMBEDR_IMAGE_SHA256"]],
  benchmark_commit = identity[["FASTEMBEDR_BENCHMARK_COMMIT"]],
  result_archive_doi = identity[["FASTEMBEDR_RESULT_DOI"]]
)
for (column in names(expected)) {
  bad <- is.na(fast[[column]]) | fast[[column]] != expected[[column]]
  if (any(bad)) stop("Mixed or missing release identity in column ", column, ".", call. = FALSE)
}
if (any(is.na(fast$actual_backend) | fast$requested_backend != fast$actual_backend)) {
  stop("Requested and observed backends differ in successful fastEmbedR rows.", call. = FALSE)
}

sample_files <- unique(fast$quality_sample_rows_file)
sample_files <- sample_files[!is.na(sample_files) & nzchar(sample_files)]
if (!length(sample_files) || any(!file.exists(sample_files))) {
  stop("One or more archived quality-sample row files are missing.", call. = FALSE)
}
for (path in sample_files) {
  rows <- fast[fast$quality_sample_rows_file == path, , drop = FALSE]
  observed <- sha256_file(path)
  if (!length(observed) || any(rows$quality_sample_sha256 != observed)) {
    stop("Quality-sample SHA-256 mismatch for ", path, ".", call. = FALSE)
  }
}

comparator_for_method <- function(method) {
  if (startsWith(method, "fastEmbedR")) return("fastEmbedR")
  if (startsWith(method, "Rtsne")) return("Rtsne")
  if (grepl("FItSNE", method, fixed = TRUE)) return("FIt-SNE")
  if (startsWith(method, "uwot")) return("uwot")
  if (identical(method, "umap_package")) return("R umap")
  if (startsWith(method, "python_opentsne")) return("Python openTSNE")
  if (startsWith(method, "python_umap_learn")) return("Python umap-learn")
  if (startsWith(method, "rapids_cuml")) return("RAPIDS cuML")
  NA_character_
}

for (result_path in files) {
  result <- read.csv(
    result_path, stringsAsFactors = FALSE, check.names = FALSE,
    colClasses = "character"
  )
  successful <- result$method[result$status == "success"]
  required_comparators <- unique(vapply(
    successful, comparator_for_method, character(1)
  ))
  required_comparators <- required_comparators[!is.na(required_comparators)]
  if (!length(required_comparators)) next

  comparator_path <- file.path(
    dirname(result_path), "comparator_identity.csv"
  )
  if (!file.exists(comparator_path)) {
    stop("Comparator identity file is missing beside ", result_path, ".",
         call. = FALSE)
  }
  comparator <- read.csv(
    comparator_path, stringsAsFactors = FALSE, check.names = FALSE,
    colClasses = "character"
  )
  missing_comparators <- setdiff(
    required_comparators, comparator$comparator
  )
  if (length(missing_comparators)) {
    stop(
      "Comparator identities are missing for ",
      paste(missing_comparators, collapse = ", "), ".",
      call. = FALSE
    )
  }
  required_rows <- comparator[
    match(required_comparators, comparator$comparator), , drop = FALSE
  ]
  missing_values <- is.na(required_rows$version_or_commit) |
    !nzchar(required_rows$version_or_commit) |
    required_rows$version_or_commit %in% c("NA", "not_available")
  if (any(missing_values)) {
    stop(
      "Successful comparators lack an exact version, commit, or artifact ",
      "SHA-256: ",
      paste(required_rows$comparator[missing_values], collapse = ", "), ".",
      call. = FALSE
    )
  }
}

summary <- data.frame(
  release_tag = expected[["fastEmbedR_release_tag"]],
  release_version = expected[["fastEmbedR_version"]],
  release_commit = expected[["fastEmbedR_commit"]],
  benchmark_commit = expected[["benchmark_commit"]],
  result_files = length(files),
  successful_fastEmbedR_rows = nrow(fast),
  backends = paste(sort(unique(fast$actual_backend)), collapse = ","),
  result_archive_doi = expected[["result_archive_doi"]],
  quality_sample_files = length(sample_files),
  status = "identity_validated",
  stringsAsFactors = FALSE
)
write.csv(summary, file.path(run_root, "release_identity_validation.csv"), row.names = FALSE)
print(summary)
