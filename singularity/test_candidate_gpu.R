#!/usr/bin/env Rscript

args <- commandArgs(trailingOnly = TRUE)
if (!length(args) %in% 1:2) {
    stop("Usage: test_candidate_gpu.R DEEP1B_SUITE_DIR [1|2|3|4]")
}
suite <- normalizePath(args[[1L]], mustWork = TRUE)
device_count <- if (length(args) == 2L) as.integer(args[[2L]]) else 1L
if (is.na(device_count) || !device_count %in% 1:4) {
    stop("GPU count must be 1, 2, 3, or 4.")
}
device_text <- paste(seq_len(device_count) - 1L, collapse = ",")
memory_limit <- if (device_count == 1L) "1GB" else "8GB"
run_test <- function() {
root <- tempfile("fastembedr_cuda_smoke_", tmpdir =
    Sys.getenv("FASTEMBEDR_SMOKE_ROOT", "/tmp"))
dir.create(root)
keep <- FALSE
on.exit(if (!keep) unlink(root, recursive = TRUE), add = TRUE)
rows <- if (device_count == 1L) 4000L else 100000L
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
            "DEEP1B_FIT_MODE=full",
            paste0("DEEP1B_GPU_DEVICES=", device_text),
            "DEEP1B_CPU_CORES=4",
            paste0("DEEP1B_MEMORY_LIMIT=", memory_limit)))
if (status != 0L) {
    keep <- TRUE
    cat("Smoke artifacts: ", root, "\n", sep = "",
        file = stderr())
    cat(utils::tail(readLines(log), 20L), sep = "\n",
        file = stderr())
    stop("Candidate full-row smoke failed.")
}
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
stopifnot(nrow(devices) == device_count,
          length(unique(devices$uuid)) == device_count,
          all(nzchar(devices$uuid)),
          is.finite(knn$observed_recall[[1L]]))
if (device_count == 1L) {
    unsupported <- utils::read.delim(file.path(output,
        "unsupported_methods.tsv"))
    stopifnot(all(c("leiden", "louvain") %in% unsupported$method))
} else {
    stopifnot(!file.exists(file.path(output,
        "unsupported_methods.tsv")))
    for (method in c("knn", "tsne", "umap")) {
        work <- utils::read.csv(file.path(output,
            paste0(method, "_device_work.csv")))
        stopifnot(nrow(work) == device_count,
                  all(work[[2L]] > 0))
    }
    for (method in c("leiden", "louvain")) {
        metrics <- utils::read.csv(file.path(output, "results",
            paste0("cuda_", method, "_", rows, "_fullgraph"),
            "metrics.csv"))
        stopifnot(metrics$status[[1L]] == "ok",
                  metrics$rows[[1L]] == rows)
    }
}
cat("PASS: ", rows, " full rows on ", device_count,
    " CUDA device(s); ",
    "sampled kNN recall ", knn$observed_recall[[1L]], "\n", sep = "")
}

run_test()
