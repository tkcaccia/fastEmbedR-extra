args <- commandArgs(trailingOnly = TRUE)
if (length(args) != 3L) {
  stop(
    "Usage: Rscript benchmark_native_hnsw_construction.R ",
    "<MNIST_float32.RData> <output-prefix> <repeats>",
    call. = FALSE
  )
}

extra_lib <- Sys.getenv("FASTEMBEDR_TEST_LIB", unset = "")
if (nzchar(extra_lib)) {
  .libPaths(c(extra_lib, .libPaths()))
}

suppressPackageStartupMessages({
  library(fastEmbedR)
  library(float)
})

load(args[[1L]])
if (!exists("dataset") || is.null(dataset$data)) {
  stop("Input must contain dataset$data.", call. = FALSE)
}

output_prefix <- args[[2L]]
repeats <- as.integer(args[[3L]])
if (is.na(repeats) || repeats < 1L) {
  stop("`repeats` must be a positive integer.", call. = FALSE)
}

dir.create(dirname(output_prefix), recursive = TRUE, showWarnings = FALSE)
records <- vector("list", repeats)
reference <- NULL

for (run in seq_len(repeats)) {
  gc()
  started <- proc.time()[["elapsed"]]
  observed <- fastEmbedR:::native_hnsw_knn_cpp(
    dataset$data,
    30L,
    4L,
    "euclidean",
    0.99
  )
  total <- proc.time()[["elapsed"]] - started
  timing <- observed$timing
  records[[run]] <- data.frame(
    run = run,
    total_sec = total,
    convert_sec = unname(timing[["convert"]]),
    build_sec = unname(timing[["build"]]),
    query_sec = unname(timing[["query"]]),
    index_checksum = sum(as.double(observed$indices)),
    distance_checksum = sum(observed$distances),
    stringsAsFactors = FALSE
  )
  if (is.null(reference)) {
    reference <- list(
      indices = observed$indices,
      distances = observed$distances
    )
  } else {
    stopifnot(
      identical(observed$indices, reference$indices),
      identical(observed$distances, reference$distances)
    )
  }
  message(
    sprintf(
      "run=%d total=%.3f build=%.3f query=%.3f",
      run,
      total,
      timing[["build"]],
      timing[["query"]]
    )
  )
}

out <- do.call(rbind, records)
utils::write.csv(out, paste0(output_prefix, ".csv"), row.names = FALSE)
saveRDS(reference, paste0(output_prefix, "_knn.rds"), compress = FALSE)
print(out)
