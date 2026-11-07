#!/usr/bin/env Rscript

args <- commandArgs(trailingOnly = TRUE)
root <- "/Users/silvanopiazza/Documents/Stefano"
release_library <- file.path(root,
    "fastEmbedR-release-535d071-20261107/library")
if (length(args) != 2L || !dir.exists(args[[1L]]) ||
        !dir.exists(dirname(args[[2L]])) || file.exists(args[[2L]])) {
    stop("Need an existing Stefano package library and new Stefano CSV path.")
}
inside <- function(path) startsWith(normalizePath(path), paste0(root, "/"))
if (!identical(normalizePath(args[[1L]]),
        normalizePath(release_library)) ||
        !inside(dirname(args[[2L]]))) {
    stop("All Mac experiment paths must stay under Stefano.")
}
.libPaths(c(args[[1L]], file.path(root, "data/Rlib"), .libPaths()))
library(fastEmbedR)
library(cluster)
setTimeLimit(elapsed = 900, transient = FALSE)

input <- file.path(root, "data/data/FashionMNIST_n5000",
    "FashionMNIST_n5000_float32.RData")
data <- new.env(parent = emptyenv())
load(input, envir = data)
x <- float::dbl(data$dataset$data)
labels <- as.integer(data$dataset$labels)
stopifnot(nrow(x) == 5000L, length(labels) == 5000L)
prepared <- umap_init(x, n_neighbors = 30L, backend = "cpu",
    seed = 711L)
graph <- prepared$prepared$graph
initial <- prepared$layout
min_dist <- prepared$parameters$min_dist
negative_rate <- as.integer(prepared$parameters$negative_sample_rate)
sample_rows <- seq.int(1L, 5000L, by = 5L)
epochs <- 400L
warm_epochs <- 200L

quality <- function(layout) {
    stopifnot(identical(dim(layout), c(5000L, 2L)),
        all(is.finite(layout)))
    sample <- as.matrix(layout)[sample_rows, , drop = FALSE]
    as.numeric(summary(cluster::silhouette(labels[sample_rows],
        stats::dist(sample)))$avg.width)
}

cpu_clean <- function(layout, n_epochs, seed, start_epoch = 0L) {
    fastEmbedR:::fast_knn_umap_csr_clean_atomic_cpp(
        graph$offsets, graph$neighbors, graph$weights,
        layout, n_epochs, min_dist, negative_rate, 0.25, 1,
        1L, seed, 0L, FALSE, start_epoch = start_epoch,
        total_epochs = epochs)
}

metal <- function(layout, n_epochs, seed, start_epoch = 0L) {
    fastEmbedR:::knn_embed_metal_csr_cpp(
        graph$offsets, graph$neighbors, graph$weights,
        layout, n_epochs, negative_rate, 0.25, min_dist,
        graph$max_weight, 1, seed, 1L,
        start_epoch = start_epoch, total_epochs = epochs)
}

run <- function(mode, seed) {
    started <- proc.time()[[3L]]
    layout <- switch(mode,
        cpu_reference = fastEmbedR:::fast_knn_umap_csr_init_cpp(
            graph$offsets, graph$neighbors, graph$weights,
            initial, epochs, min_dist, negative_rate, 0.25,
            1, 1L, seed, FALSE),
        cpu_clean = cpu_clean(initial, epochs, seed),
        cpu_split = cpu_clean(cpu_clean(initial, warm_epochs, seed),
            epochs - warm_epochs, seed, warm_epochs),
        metal_full = metal(initial, epochs, seed),
        hybrid = metal(cpu_clean(initial, warm_epochs, seed),
            epochs - warm_epochs, seed, warm_epochs))
    data.frame(seed = seed, mode = mode,
        silhouette = quality(layout),
        elapsed_seconds = unname(proc.time()[[3L]] - started),
        optimizer = as.character(attr(layout, "metal_optimizer") %||% "cpu"))
}

`%||%` <- function(x, y) if (is.null(x)) y else x
results <- data.frame()
for (seed in c(4L, 17L, 42L)) {
    for (mode in c("cpu_reference", "cpu_clean", "cpu_split",
            "metal_full", "hybrid")) {
        row <- run(mode, seed)
        results <- rbind(results, row)
        utils::write.csv(results, args[[2L]], row.names = FALSE)
        cat("RESULT", seed, mode, row$silhouette,
            row$elapsed_seconds, row$optimizer, "\n")
    }
}
stopifnot(nrow(results) == 15L)
cat("METAL_UMAP_OPTIMIZER_DIAGNOSTIC_COMPLETE\n")
