#!/usr/bin/env Rscript

args <- commandArgs(trailingOnly = TRUE)
value_after <- function(prefix, default = NULL) {
  hit <- args[startsWith(args, prefix)]
  if (!length(hit)) return(default)
  sub(prefix, "", hit[[length(hit)]], fixed = TRUE)
}

backend <- tolower(value_after("--backend=", ""))
if (!backend %in% c("metal", "cuda")) {
  stop("Use --backend=metal or --backend=cuda.")
}

root <- normalizePath(value_after("--root=", "."), mustWork = TRUE)
stamp <- format(Sys.time(), "%Y%m%d_%H%M%S")
out_dir <- value_after(
  "--out-dir=",
  file.path(root, "docs", "validation", paste0(backend, "_", stamp))
)
dir.create(out_dir, recursive = TRUE, showWarnings = FALSE)
out_dir <- normalizePath(out_dir, mustWork = TRUE)

log_path <- file.path(out_dir, "hardware-test.log")
log_connection <- file(log_path, open = "wt")
sink(log_connection, split = TRUE)
sink(log_connection, type = "message")
on.exit({
  sink(type = "message")
  sink()
  close(log_connection)
}, add = TRUE)

cat("fastEmbedR real-hardware validation\n")
cat("timestamp_utc=", format(Sys.time(), tz = "UTC", usetz = TRUE), "\n", sep = "")
cat("backend=", backend, "\n", sep = "")
cat("root=", root, "\n", sep = "")
cat("git_commit=", system2(
  "git", c("-C", shQuote(root), "rev-parse", "HEAD"),
  stdout = TRUE, stderr = TRUE
), "\n", sep = "")
git_describe <- system2(
  "git",
  c("-C", root, "describe", "--tags", "--always", "--dirty"),
  stdout = TRUE,
  stderr = TRUE
)
git_status <- system2(
  "git", c("-C", root, "status", "--porcelain"),
  stdout = TRUE,
  stderr = TRUE
)
cat("git_describe=", paste(git_describe, collapse = " "), "\n", sep = "")
cat("working_tree_dirty=", length(git_status) > 0L, "\n", sep = "")

suppressPackageStartupMessages(library(fastEmbedR))
if (!requireNamespace("testthat", quietly = TRUE)) {
  stop("The testthat package is required.")
}

availability_name <- paste0("embedding_", backend, "_available_cpp")
availability <- get(availability_name, envir = asNamespace("fastEmbedR"))()
cat("backend_available=", availability, "\n", sep = "")
if (!isTRUE(availability)) {
  stop("Requested hardware backend is unavailable in this build.")
}

cat("\nbackend_info:\n")
backend_details <- get("backend_info", envir = asNamespace("fastEmbedR"))()
print(backend_details)

x <- scale(as.matrix(iris[, 1:4]))
fit_tsne <- fastEmbedR::opentsne(
  x,
  perplexity = 10,
  backend = backend,
  n.cores = 2,
  seed = 4
)
fit_umap <- fastEmbedR::umap(
  x,
  n_neighbors = 15,
  graph_mode = "fuzzy",
  backend = backend,
  n.cores = 2,
  seed = 4
)

actual_tsne <- if (is.null(fit_tsne$parameters$backend)) {
  NA_character_
} else {
  as.character(fit_tsne$parameters$backend)
}
actual_umap <- if (is.null(fit_umap$parameters$backend)) {
  NA_character_
} else {
  as.character(fit_umap$parameters$backend)
}
if (!identical(actual_tsne, backend) || !identical(actual_umap, backend)) {
  stop(
    "Backend identity mismatch: openTSNE=", actual_tsne,
    ", UMAP=", actual_umap, ", requested=", backend
  )
}

test_results <- testthat::test_dir(
  file.path(root, "tests", "testthat"),
  filter = backend,
  reporter = "summary",
  stop_on_failure = FALSE,
  stop_on_warning = FALSE
)
failed <- sum(vapply(
  test_results,
  function(x) length(x$results) &&
    any(vapply(x$results, inherits, logical(1), "expectation_failure")),
  logical(1)
))

summary_row <- data.frame(
  timestamp_utc = format(Sys.time(), tz = "UTC", usetz = TRUE),
  git_commit = system2(
    "git", c("-C", root, "rev-parse", "HEAD"),
    stdout = TRUE
  ),
  git_describe = paste(git_describe, collapse = " "),
  working_tree_dirty = length(git_status) > 0L,
  backend_requested = backend,
  backend_available = availability,
  opentsne_backend_used = actual_tsne,
  umap_backend_used = actual_umap,
  opentsne_elapsed_sec = as.numeric(fit_tsne$metrics$elapsed),
  umap_elapsed_sec = as.numeric(fit_umap$metrics$elapsed),
  failed_expectations = failed,
  stringsAsFactors = FALSE
)
utils::write.csv(
  summary_row,
  file.path(out_dir, "hardware-test-summary.csv"),
  row.names = FALSE
)
writeLines(
  capture.output(sessionInfo()),
  file.path(out_dir, "sessionInfo.txt")
)
writeLines(
  capture.output(backend_details),
  file.path(out_dir, "backend_info.txt")
)

if (failed > 0L) stop("Hardware test suite reported failures.")
cat("\nHardware validation completed successfully.\n")
