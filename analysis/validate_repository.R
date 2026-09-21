#!/usr/bin/env Rscript

required <- c(
  "results/aggregate/runtime_tsne_all_methods.csv",
  "results/aggregate/runtime_umap_all_methods.csv",
  "results/aggregate/key_dataset_runtime_quality.csv",
  "results/tables/runtime_summary.csv",
  "results/tables/runtime_summary.md",
  "results/figures/runtime_tsne_all_methods.pdf",
  "results/figures/runtime_tsne_all_methods.png",
  "results/figures/runtime_umap_all_methods.pdf",
  "results/figures/runtime_umap_all_methods.png",
  "provenance/source_manifest.csv",
  "provenance/artifact_sha256.csv"
)
missing <- required[!file.exists(required) | file.info(required)$size <= 0L]
if (length(missing)) {
  stop("Missing or empty repository artifacts: ",
       paste(missing, collapse = ", "), call. = FALSE)
}

validate_runtime <- function(path) {
  data <- read.csv(path, stringsAsFactors = FALSE, check.names = FALSE)
  needed <- c(
    "dataset", "method", "backend", "timing_scope", "runtime_measure",
    "n_runs", "runtime", "runtime_q1", "runtime_q3"
  )
  absent <- setdiff(needed, names(data))
  if (length(absent)) {
    stop(path, " lacks columns: ", paste(absent, collapse = ", "),
         call. = FALSE)
  }
  finite <- is.finite(data$runtime)
  if (any(data$runtime[finite] < 0)) {
    stop(path, " contains a negative runtime.", call. = FALSE)
  }
  direct <- grepl("direct_python", data$timing_scope)
  if (any(direct & data$runtime_measure != "direct_python_fit_sec")) {
    stop(path, " merges direct-Python and total-call timing.",
         call. = FALSE)
  }
  invisible(TRUE)
}

validate_runtime(required[[1L]])
validate_runtime(required[[2L]])

manifest <- read.csv(
  "provenance/artifact_sha256.csv",
  stringsAsFactors = FALSE,
  check.names = FALSE
)
if (!all(c("sha256", "path") %in% names(manifest))) {
  stop("The artifact manifest has an invalid schema.", call. = FALSE)
}
if (anyDuplicated(manifest$path)) {
  stop("The artifact manifest contains duplicate paths.", call. = FALSE)
}
missing_manifest_paths <- manifest$path[!file.exists(manifest$path)]
if (length(missing_manifest_paths)) {
  stop("The artifact manifest references missing files: ",
       paste(missing_manifest_paths, collapse = ", "), call. = FALSE)
}

message("fastEmbedR-extra repository validation passed.")
