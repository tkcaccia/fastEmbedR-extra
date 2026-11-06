#!/usr/bin/env Rscript
suppressPackageStartupMessages(library(fastEmbedR))

prepare_probe <- function(root, n, k) {
    prefix <- file.path(root, "knn")
    affinity <- file.path(root, "affinity")
    init_path <- file.path(root, "init.f32")
    rows <- seq_len(n)
    indices <- vapply(seq_len(k), function(j) {
        ((rows + j - 1L) %% n) + 1L
    }, integer(n))
    distances <- matrix(rep(seq_len(k) / k, n), n, k,
        byrow = TRUE)
    writeBin(as.integer(t(indices)), paste0(prefix, ".indices.u32"),
        size = 4L, endian = "little")
    writeBin(as.vector(t(distances)),
        paste0(prefix, ".distances.f32"),
        size = 4L, endian = "little")
    knn <- massive_knn_graph(prefix, n, k)
    graph <- massive_tsne_affinities(knn, perplexity = 10,
        output = affinity, memory_limit = "256MB")
    set.seed(17)
    initial <- matrix(rnorm(n * 3L, sd = 0.0001), n, 3L)
    writeBin(as.numeric(t(initial)), init_path,
        size = 4L, endian = "little")
    list(graph = graph, start = massive_matrix(init_path, n, 3L),
        indices = indices)
}

run_probe_fit <- function(root, graph, start, n, backend) {
    output <- file.path(root, paste0(backend, ".f32"))
    elapsed <- system.time({
        result <- massive_tsne_optimize(graph, start, output,
            early_exaggeration_iter = 25L, n_iter = 75L,
            learning_rate = 50, memory_limit = "2GB",
            backend = backend, n.cores = 1L)
    })[["elapsed"]]
    layout <- massive_read_rows(result, 1L, n)
    stopifnot(all(is.finite(layout)))
    list(elapsed = elapsed, result = result, layout = layout)
}

aligned_relative_rms <- function(cpu, metal) {
    x <- scale(cpu, center = TRUE, scale = FALSE)
    y <- scale(metal, center = TRUE, scale = FALSE)
    alignment <- svd(crossprod(y, x))
    aligned <- y %*% alignment$u %*% t(alignment$v)
    aligned <- aligned * sum(x * aligned) / sum(aligned^2)
    sqrt(mean((x - aligned)^2)) / max(sqrt(mean(x^2)), 1e-8)
}

neighbor_ratio <- function(layout, indices) {
    n <- nrow(layout)
    rows <- seq_len(n)
    near <- sqrt(rowSums((layout - layout[indices[, 1L], ])^2))
    far <- sqrt(rowSums((layout -
        layout[((rows + n / 2L - 1L) %% n) + 1L, ])^2))
    mean(near) / mean(far)
}

probe <- function() {
    args <- commandArgs(trailingOnly = TRUE)
    stopifnot(length(args) == 1L, dir.exists(args[[1L]]))
    root <- tempfile("metal-tsne-5k-", tmpdir = args[[1L]])
    dir.create(root)
    on.exit(unlink(root, recursive = TRUE), add = TRUE)
    n <- 5000L
    setup <- prepare_probe(root, n, 30L)
    cpu <- run_probe_fit(root, setup$graph, setup$start, n, "cpu")
    metal <- run_probe_fit(root, setup$graph, setup$start, n,
        "metal")
    cat("rows", n, "edges", setup$graph$n_edges,
        "iterations", 100L, "\n")
    cat("cpu_seconds", cpu$elapsed,
        "metal_seconds", metal$elapsed,
        "aligned_relative_rms",
        aligned_relative_rms(cpu$layout, metal$layout), "\n")
    cat("cpu_near_far",
        neighbor_ratio(cpu$layout, setup$indices),
        "metal_near_far",
        neighbor_ratio(metal$layout, setup$indices), "\n")
    cat("metal_backend", metal$result$backend,
        "graph_access", metal$result$resources$graph_access,
        "fft_grid", metal$result$fft_grid_size, "\n")
}
probe()
