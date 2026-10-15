#!/usr/bin/env Rscript

args <- commandArgs(trailingOnly = TRUE)
if (length(args) != 1L) {
    stop("Usage: test_candidate_gpu.R DEEP1B_SUITE_DIR")
}
suite <- normalizePath(args[[1L]], mustWork = TRUE)
run_test <- function() {
root <- tempfile("fastembedr_cuda_smoke_")
dir.create(root)
on.exit(unlink(root, recursive = TRUE), add = TRUE)
rows <- 4000L
input <- file.path(root, "input.fbin")
stream <- file(input, "wb")
writeBin(c(rows, 96L), stream, size = 4L, endian = "little")
set.seed(4L)
for (first in seq.int(1L, rows, by = 500L)) {
    count <- min(500L, rows - first + 1L)
    block <- matrix(rnorm(count * 96L), count, 96L)
    writeBin(as.vector(t(block)), stream, size = 4L,
             endian = "little")
}
close(stream)
output <- file.path(root, "fit")
dir.create(output)
log <- file.path(root, "fit.log")
status <- system2(file.path(R.home("bin"), "Rscript"),
    c(shQuote(file.path(suite, "run_full_graph.R")),
      shQuote(input), "deep", "cuda", rows, shQuote(output)),
    stdout = log, stderr = log,
    env = c("DEEP1B_SMOKE=1", "DEEP1B_FIRST_ROW=1",
            "DEEP1B_FIT_MODE=full", "DEEP1B_GPU_DEVICES=0",
            "DEEP1B_CPU_CORES=4", "DEEP1B_MEMORY_LIMIT=1GB"))
if (status != 0L) stop(paste(readLines(log), collapse = "\n"))
library(fastEmbedR)
for (method in c("pca", "tsne", "umap")) {
    case <- file.path(output, "results", paste0(
        "cuda_", method, "_", rows, "_fullgraph"))
    metrics <- utils::read.csv(file.path(case, "metrics.csv"))
    stopifnot(identical(metrics$status[[1L]], "ok"),
              metrics$rows[[1L]] == rows)
    path <- file.path(case, "output.f32")
    stopifnot(file.info(path)$size == rows * 8)
    layout <- massive_matrix(path, nrow = rows, ncol = 2L)
    for (first in seq.int(1L, rows, by = 500L)) {
        block <- massive_read_rows(layout, first,
            min(500L, rows - first + 1L))
        stopifnot(all(is.finite(block)))
    }
}
knn <- utils::read.csv(file.path(output, "knn.csv"))
devices <- utils::read.csv(file.path(output, "gpu_device_map.csv"))
unsupported <- utils::read.delim(file.path(output,
    "unsupported_methods.tsv"))
stopifnot(nrow(devices) == 1L, nzchar(devices$uuid[[1L]]),
          all(c("leiden", "louvain") %in% unsupported$method),
          is.finite(knn$observed_recall[[1L]]))
cat("PASS: 4000 full rows on CUDA device ", devices$uuid[[1L]],
    "; sampled kNN recall ", knn$observed_recall[[1L]], "\n", sep = "")
}

run_test()
