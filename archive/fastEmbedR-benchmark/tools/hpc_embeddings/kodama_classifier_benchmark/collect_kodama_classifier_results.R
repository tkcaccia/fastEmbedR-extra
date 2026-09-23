#!/usr/bin/env Rscript

script_argument <- grep("^--file=", commandArgs(FALSE), value = TRUE)
script_path <- normalizePath(
  sub("^--file=", "", script_argument[[1L]]),
  mustWork = TRUE
)
source(file.path(dirname(script_path), "kodama_benchmark_common.R"))

args <- commandArgs(trailingOnly = TRUE)
results_root <- if (length(args)) args[[1L]] else {
  "/scratch/firenze/NN/fastEmbedR-results"
}
output <- if (length(args) >= 2L) args[[2L]] else {
  file.path(results_root, "KODAMA_classifier_landmark_summary.csv")
}
files <- list.files(
  results_root,
  pattern = "^kodama_(pls_lda|knn)_runs[.]csv$",
  recursive = TRUE,
  full.names = TRUE
)
if (!length(files)) {
  stop("No classifier-specific KODAMA summaries found under ", results_root)
}
rows <- lapply(files, function(path) {
  value <- read.csv(path, stringsAsFactors = FALSE, check.names = FALSE)
  value$source_file <- path
  value
})
columns <- unique(unlist(lapply(rows, names), use.names = FALSE))
rows <- lapply(rows, function(value) {
  missing <- setdiff(columns, names(value))
  for (name in missing) value[[name]] <- NA
  value[columns]
})
result <- do.call(rbind, rows)
result <- result[order(
  result$dataset, result$classifier, result$backend_requested,
  result$n.cores, result$landmark_fraction_effective,
  result$visualization, result$seed
), , drop = FALSE]
run_output <- sub("[.]csv$", "_runs.csv", output)
write.csv(result, run_output, row.names = FALSE)
summary <- aggregate_runs(result)
write.csv(summary, output, row.names = FALSE)
cat("Wrote ", run_output, "\n", sep = "")
cat("Wrote ", output, "\n", sep = "")
