#!/usr/bin/env Rscript

run_test <- function() {
suite <- dirname(normalizePath(sub("^--file=", "",
    grep("^--file=", commandArgs(), value = TRUE))))
root <- tempfile("deep1b_full_smoke_")
dir.create(root)
on.exit(unlink(root, recursive = TRUE), add = TRUE)
input <- file.path(root, "input.fbin")
stream <- file(input, "wb")
writeBin(c(1000L, 96L), stream, size = 4L, endian = "little")
set.seed(4L)
points <- matrix(rnorm(96000L), 1000L, 96L)
writeBin(as.vector(t(points)), stream, size = 4L,
    endian = "little")
close(stream)
output <- file.path(root, "result")
dir.create(output)
script <- file.path(suite, "run_full_graph.R")
log <- file.path(root, "fit.log")
status <- system2(file.path(R.home("bin"), "Rscript"),
    c(shQuote(script), shQuote(input), "deep", "cpu", "1000",
        shQuote(output)), stdout = log, stderr = log,
    env = c("DEEP1B_SMOKE=1", "DEEP1B_FIRST_ROW=1",
        "DEEP1B_CPU_CORES=1", "DEEP1B_FIT_MODE=full_umap",
        "DEEP1B_REBUILD_KNN_FOR_UMAP=0",
        "DEEP1B_MEMORY_LIMIT=512MB"))
if (status != 0L) stop(paste(readLines(log), collapse = "\n"))
for (method in c("pca", "umap", "leiden", "louvain")) {
    case <- file.path(output, "results", paste0("cpu_", method,
        "_1000_fullgraph"))
    stopifnot(file.exists(file.path(case, "metrics.csv")))
    result <- if (method %in% c("leiden", "louvain"))
        file.path(output, "work", paste0(method, "_labels.u32")) else
        file.path(case, "output.f32")
    stopifnot(file.info(result)$size == 1000 *
        if (method %in% c("leiden", "louvain")) 4 else 8)
}
cat("Full-row CPU PCA, UMAP, Leiden, Louvain: PASS\n")
}

run_test()
