#!/usr/bin/env Rscript

args <- commandArgs(trailingOnly = TRUE)
if (length(args) != 4L ||
    !args[[1L]] %in% c("prepare", "stream", "resident", "compare")) {
    stop("Usage: benchmark_full_tsne_mnist.R MODE PACKAGE_ROOT ",
        "MATCHED_INPUTS_RDS OUTPUT_DIRECTORY")
}
mode <- args[[1L]]
package_root <- normalizePath(args[[2L]], mustWork = TRUE)
input_path <- normalizePath(args[[3L]], mustWork = TRUE)
output <- normalizePath(args[[4L]], mustWork = TRUE)
pkgload::load_all(package_root, quiet = TRUE)
prefix <- file.path(output, "mnist_knn30")
affinity_path <- file.path(output, "mnist_affinity")
init_path <- file.path(output, "mnist_init.f32")
stream_path <- file.path(output, "mnist_stream.f32")
reference_path <- file.path(output, "mnist_resident.rds")
source_head <- system2("git", c("-C", package_root,
    "rev-parse", "HEAD"), stdout = TRUE)
source_dirty <- length(system2("git", c("-C", package_root,
    "status", "--porcelain"), stdout = TRUE)) > 0L
identity <- list(package_version = as.character(
    packageVersion("fastEmbedR")), source_head = source_head,
    source_dirty = source_dirty,
    input_md5 = unname(tools::md5sum(input_path)))
if (mode == "prepare") {
    x <- readRDS(input_path)
    n <- nrow(x$knn$indices)
    k <- 30L
    stopifnot(n == 70000L, nrow(x$init@Data) == n,
        ncol(x$knn$indices) >= k)
    indices <- x$knn$indices[, seq_len(k)]
    distances <- float::dbl(x$knn$distances[, seq_len(k)])
    init <- float::dbl(x$init)
    writeBin(as.integer(t(indices)), paste0(prefix, ".indices.u32"),
        size = 4L, endian = "little")
    writeBin(as.numeric(t(distances)),
        paste0(prefix, ".distances.f32"),
        size = 4L, endian = "little")
    writeBin(as.numeric(t(init)), init_path,
        size = 4L, endian = "little")
    graph <- massive_knn_graph(prefix, n, k)
    started <- proc.time()[[3L]]
    affinity <- massive_tsne_affinities(graph, 30, affinity_path,
        memory_limit = "512MB")
    elapsed <- unname(proc.time()[[3L]] - started)
    saveRDS(c(identity, list(rows = n, k = k,
        affinity_edges = affinity$n_edges,
        affinity_elapsed_seconds = elapsed)),
        file.path(output, "prepare.rds"))
    cat("Affinity seconds:", elapsed, "edges:",
        affinity$n_edges, "\n")
} else if (mode == "stream") {
    graph <- massive_affinity_graph(affinity_path, 70000L)
    init <- massive_matrix(init_path, 70000L, 2L)
    started <- proc.time()[[3L]]
    fit <- massive_tsne_optimize(graph, init, stream_path,
        early_exaggeration_iter = 5L, n_iter = 20L,
        learning_rate = 1, n.cores = 1L,
        memory_limit = "2GB", checkpoint = TRUE,
        checkpoint_every = 10L)
    elapsed <- unname(proc.time()[[3L]] - started)
    saveRDS(c(identity, list(fit = fit, elapsed_seconds = elapsed)),
        file.path(output, "stream.rds"))
    cat("Stream seconds:", elapsed, "\n")
} else if (mode == "resident") {
    x <- readRDS(input_path)
    indices <- x$knn$indices[, 1:30]
    distances <- float::dbl(x$knn$distances[, 1:30])
    init <- float::dbl(x$init)
    started <- proc.time()[[3L]]
    fit <- fastEmbedR:::knn_tsne_opentsne_float_cpp(
        indices, distances, init, TRUE, 2L, 30, 0.5,
        5L, 20L, 12, 1, 1, FALSE, 0.8, 0.8, 0.01, Inf,
        "fft", 1L, 4L, FALSE, FALSE, FALSE, 5000)
    elapsed <- unname(proc.time()[[3L]] - started)
    saveRDS(c(identity, list(fit = fit, elapsed_seconds = elapsed)),
        reference_path)
    cat("Resident seconds:", elapsed, "\n")
} else {
    streamed <- readRDS(file.path(output, "stream.rds"))
    resident <- readRDS(reference_path)
    layout <- massive_read_rows(streamed$fit, 1L, 70000L)
    difference <- max(abs(layout - resident$fit$Y))
    result <- data.frame(rows = 70000L, k = 30L,
        iterations = 25L, stream_seconds = streamed$elapsed_seconds,
        resident_seconds = resident$elapsed_seconds,
        max_abs_coordinate_difference = difference,
        source_head = source_head, source_dirty = source_dirty,
        input_md5 = identity$input_md5)
    utils::write.csv(result, file.path(output, "comparison.csv"),
        row.names = FALSE)
    print(result)
    stopifnot(difference < 1e-3)
}
