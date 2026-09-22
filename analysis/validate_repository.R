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
  "provenance/artifact_sha256.csv",
  "provenance/JSS_VALIDATION_INVENTORY.md",
  paste0(
    "benchmarks/linux/jss-review-validation/",
    "submit_complete_campaign.sh"
  ),
  paste0(
    "benchmarks/linux/jss-review-validation/",
    "common/run_complete_campaign_controller.sh"
  ),
  "benchmarks/linux/jss-review-validation/FILES.sha256"
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

campaign <- "benchmarks/linux/jss-review-validation"
checksum_tool <- if (nzchar(Sys.which("sha256sum"))) {
  c("sha256sum", "-c", "FILES.sha256")
} else if (nzchar(Sys.which("shasum"))) {
  c("shasum", "-a", "256", "-c", "FILES.sha256")
} else {
  stop("Neither sha256sum nor shasum is available.", call. = FALSE)
}
checksum_status <- local({
  previous <- setwd(campaign)
  on.exit(setwd(previous), add = TRUE)
  system2(
    checksum_tool[[1L]], checksum_tool[-1L],
    stdout = FALSE, stderr = FALSE
  )
})
if (!identical(checksum_status, 0L)) {
  stop("The JSS campaign checksum validation failed.", call. = FALSE)
}

tracked <- system2("git", "ls-files", stdout = TRUE, stderr = TRUE)
forbidden <- grepl(
  "([.]sif|[.]RData|[.]rds|[.]npz|[.]key|[.]tar[.]gz)$",
  tracked, ignore.case = TRUE
)
forbidden <- forbidden | grepl("(^|/)credentials", tracked)
if (any(forbidden)) {
  stop(
    "Forbidden generated or sensitive artifacts are tracked: ",
    paste(tracked[forbidden], collapse = ", "),
    call. = FALSE
  )
}

message("fastEmbedR-extra repository validation passed.")
