#!/usr/bin/env Rscript

args <- commandArgs(trailingOnly = TRUE)
if (length(args) != 5L || args[[2L]] != "deep" ||
    !args[[3L]] %in% c("cpu", "cuda")) {
    stop("Usage: run_classic_1m.R INPUT deep BACKEND ROWS ROOT")
}
library(fastEmbedR)
input <- normalizePath(args[[1L]], mustWork = TRUE)
backend <- args[[3L]]
smoke <- identical(Sys.getenv("DEEP1B_SMOKE"), "1")
rows <- if (smoke) 2000L else 1000000L
if (as.numeric(args[[4L]]) != rows) stop("Classic row count mismatch.")
columns <- 96L
first_row <- as.numeric(Sys.getenv("DEEP1B_FIRST_ROW",
    if (smoke) "1" else "1000001"))
root <- normalizePath(args[[5L]], mustWork = TRUE)
source <- massive_matrix(input)
if (!is.finite(first_row) || first_row < 1 ||
    first_row != floor(first_row) ||
    first_row + rows - 1 > source$nrow || source$ncol != columns) {
    stop("Classic input window does not match Deep1B.")
}
con <- file(input, "rb")
seek(con, where = 8 + (first_row - 1) * columns * 4)
values <- readBin(con, "numeric", n = rows * columns,
    size = 4L, endian = "little")
close(con)
if (length(values) != rows * columns) stop("Short Deep1B read.")
data <- matrix(values, nrow = rows, ncol = columns, byrow = TRUE)
rm(values)
gc(verbose = FALSE)
if (!all(is.finite(data))) stop("Deep1B contains nonfinite values.")
cores <- if (backend == "cuda") 1L else 4L
stages <- list()
peak_rss <- function() {
    if (!file.exists("/proc/self/status")) return(NA_real_)
    line <- grep("^VmHWM:", readLines("/proc/self/status"), value = TRUE)
    as.numeric(sub("^VmHWM:[[:space:]]*([0-9]+).*", "\\1", line)) * 1024
}
save_layout <- function(layout, path) {
    if (!is.matrix(layout) || !identical(dim(layout), c(rows, 2L))) {
        stop("Classic fit returned the wrong layout shape.")
    }
    stream <- file(path, "wb")
    on.exit(close(stream))
    for (first in seq(1L, rows, by = 10000L)) {
        last <- min(rows, first + 9999L)
        block <- layout[first:last, , drop = FALSE]
        if (!all(is.finite(block))) stop("Nonfinite classic layout.")
        writeBin(as.vector(t(block)), stream, size = 4L,
            endian = "little")
    }
}
fit_one <- function(method, expression) {
    out <- file.path(root, "results", paste0(backend, "_", method,
        "_", rows, "_classic"))
    dir.create(out, recursive = TRUE, showWarnings = FALSE)
    start <- proc.time()[[3L]]
    error <- ""
    fit <- tryCatch(force(expression), error = function(e) {
        error <<- conditionMessage(e)
        NULL
    })
    if (!is.null(fit)) tryCatch({
        layout <- if (method == "pca") fit$scores else fit$layout
        save_layout(layout, file.path(out, "output.f32"))
    }, error = function(e) error <<- conditionMessage(e))
    stages[[method]] <<- data.frame(stage = method,
        seconds = proc.time()[[3L]] - start,
        peak_rss_bytes = peak_rss(), backend = backend,
        rows = rows, first_row = first_row)
    write.csv(do.call(rbind, stages), file.path(root, "stages.csv"),
        row.names = FALSE)
    write.csv(data.frame(status = if (nzchar(error)) "failed" else "ok",
        error = error, rows = rows, components = 2L,
        first_row = first_row, backend = backend, mode = "classic"),
        file.path(out, "metrics.csv"), row.names = FALSE)
    if (nzchar(error)) message(method, ": ", error)
    fit
}
pca_fit <- fit_one("pca", pca(data, ncomp = 2L,
    backend = backend, n.cores = cores, seed = 4L))
fit_one("umap", umap(data, n_neighbors = 30L,
    n_components = 2L, backend = backend, n.cores = cores, seed = 4L))
if (!is.null(pca_fit)) {
    initial <- pca_fit$scores
    center <- colMeans(initial)
    initial <- sweep(initial, 2L, center, "-")
    initial <- initial * (1e-4 / sqrt(max(apply(initial, 2L, var))))
    fit_one("tsne", tsne(data, perplexity = 30L,
        n_components = 2L, Y_init = initial, backend = backend,
        n.cores = cores, seed = 4L, negative_gradient_method = "fft",
        early_exaggeration_iter = 250L, n_iter = 750L,
        auto_config = FALSE))
}
methods <- c("pca", "umap", "tsne")
statuses <- vapply(methods, function(method) {
    path <- file.path(root, "results", paste0(backend, "_", method,
        "_", rows, "_classic"), "metrics.csv")
    if (!file.exists(path)) return("missing")
    read.csv(path, nrows = 1L)$status[[1L]]
}, character(1L))
if (any(statuses != "ok")) {
    quit(status = 1L)
}
