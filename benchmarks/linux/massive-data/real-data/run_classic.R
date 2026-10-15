#!/usr/bin/env Rscript
args <- commandArgs(trailingOnly = TRUE)
if (length(args) != 7L) {
    stop("Usage: run_classic.R INPUT ROWS COLS MODE BACKEND CORES OUT")
}
suppressPackageStartupMessages(library(fastEmbedR))
expected_version <- Sys.getenv("FASTEMBEDR_EXPECTED_VERSION", "0.1")
if (as.character(packageVersion("fastEmbedR")) != expected_version) {
    stop("Unexpected fastEmbedR package version.")
}
dll <- getLoadedDLLs()[["fastEmbedR"]][["path"]]
dll_hash <- strsplit(system2("sha256sum", dll, stdout = TRUE),
                     " +")[[1L]][1L]
path <- normalizePath(args[[1L]], mustWork = TRUE)
rows <- as.integer(args[[2L]])
columns <- as.integer(args[[3L]])
mode <- match.arg(args[[4L]], c("pca", "umap", "tsne"))
backend <- match.arg(args[[5L]], c("cpu", "cuda"))
cores <- as.integer(args[[6L]])
out <- args[[7L]]
if (backend == "cuda" && cores != 1L && mode != "pca") {
    stop("CUDA embedding requires one R worker.")
}
if (file.info(path)$size != as.double(rows) * columns * 4) {
    stop("Input bytes differ from declared dimensions.")
}
if (file.exists(out)) stop("Refusing to overwrite an output.")
peak_rss <- function() {
    if (!file.exists("/proc/self/status")) return(NA_real_)
    line <- grep("^VmHWM:", readLines("/proc/self/status"), value = TRUE)
    if (!length(line)) return(NA_real_)
    as.numeric(sub("^VmHWM:[[:space:]]*([0-9]+).*", "\\1", line)) * 1024
}
started <- proc.time()[[3L]]
con <- file(path, "rb")
values <- readBin(con, "numeric", n = as.double(rows) * columns,
                  size = 4L, endian = "little")
close(con)
if (length(values) != as.double(rows) * columns) {
    stop("Could not read the complete input.")
}
input <- float::fl(matrix(values, nrow = rows, ncol = columns,
                          byrow = TRUE))
rm(values)
if (mode == "pca") {
    fit <- pca(input, ncomp = 2L, backend = backend,
               n.cores = cores, seed = 4L)
    layout <- fit$scores
    observed <- if (startsWith(fit$backend, backend)) backend else "other"
} else if (mode == "umap") {
    fit <- umap(input, n_neighbors = 30L, n_components = 2L,
                backend = backend, n.cores = cores, seed = 4L)
    layout <- fit$layout
    observed <- fit$parameters$backend
} else {
    fit <- tsne(input, perplexity = 30L, n_components = 2L,
                early_exaggeration_iter = 250L, n_iter = 750L,
                auto_config = FALSE, backend = backend,
                n.cores = cores, seed = 4L)
    layout <- fit$layout
    observed <- fit$parameters$backend
}
if (!identical(observed, backend)) stop("Backend changed during fit.")
if (inherits(layout, "float32")) layout <- float::dbl(layout)
layout <- as.matrix(layout)
if (!identical(dim(layout), c(rows, 2L)) ||
    any(!is.finite(layout))) stop("Invalid layout dimensions or values.")
con <- file(out, "wb")
for (first in seq.int(1L, rows, by = 100000L)) {
    last <- min(rows, first + 99999L)
    writeBin(as.numeric(t(layout[first:last, , drop = FALSE])),
             con, size = 4L, endian = "little")
}
close(con)
if (file.info(out)$size != as.double(rows) * 8) {
    stop("Layout bytes differ from expected dimensions.")
}
metrics <- data.frame(status = "ok", route = "classic_float32",
    mode = mode, backend = observed, rows = rows, columns = columns,
    cores = cores, seconds_including_input_load =
        unname(proc.time()[[3L]] - started),
    rss_peak_bytes = peak_rss(), output_bytes = file.info(out)$size,
    package_version = as.character(packageVersion("fastEmbedR")),
    dll_sha256 = dll_hash)
write.csv(metrics, sub("\\.f32$", ".metrics.csv", out),
          row.names = FALSE)
