#!/usr/bin/env Rscript
suppressPackageStartupMessages(library(fastEmbedR))

prepare_fashion <- function(root, seed) {
    path <- paste0(
        "/Users/silvanopiazza/Documents/Stefano/data/data/",
        "FashionMNIST_n5000/FashionMNIST_n5000_float32.RData")
    data <- new.env(parent = emptyenv())
    load(path, envir = data)
    x <- float::dbl(data$dataset$data)
    labels <- as.integer(data$dataset$labels)
    stopifnot(identical(dim(x), c(5000L, 784L)),
        length(labels) == nrow(x))
    knn <- precompute_knn(x, k = 90L, backend = "metal")
    stopifnot(identical(knn$method, "native_metal_exact"))
    prefix <- file.path(root, "knn")
    affinity <- file.path(root, "affinity")
    writeBin(as.integer(t(knn$indices)),
        paste0(prefix, ".indices.u32"),
        size = 4L, endian = "little")
    writeBin(as.vector(t(knn$distances)),
        paste0(prefix, ".distances.f32"),
        size = 4L, endian = "little")
    source <- massive_knn_graph(prefix, nrow(x), 90L)
    graph <- massive_tsne_affinities(source, perplexity = 30,
        output = affinity, memory_limit = "256MB")
    set.seed(seed)
    init <- matrix(rnorm(nrow(x) * 3L, sd = 0.0001),
        nrow(x), 3L)
    init_path <- file.path(root, "init.f32")
    writeBin(as.numeric(t(init)), init_path,
        size = 4L, endian = "little")
    list(graph = graph,
        start = massive_matrix(init_path, nrow(x), 3L),
        x = x, labels = labels, knn = knn, input = path)
}

run_fashion_fit <- function(root, graph, start, backend) {
    output <- file.path(root, paste0(backend, ".f32"))
    elapsed <- system.time({
        result <- massive_tsne_optimize(graph, start, output,
            early_exaggeration_iter = 50L, n_iter = 200L,
            learning_rate = "auto", memory_limit = "2GB",
            backend = backend, n.cores = 1L)
    })[["elapsed"]]
    layout <- massive_read_rows(result, 1L, 5000L)
    stopifnot(all(is.finite(layout)))
    list(elapsed = elapsed, result = result, layout = layout)
}

score_fashion <- function(layout, labels, reference) {
    sample_rows <- seq.int(1L, nrow(layout), by = 5L)
    silhouette <- as.numeric(summary(cluster::silhouette(
        labels[sample_rows], stats::dist(layout[
            sample_rows, , drop = FALSE])))$avg.width)
    embedded <- fastEmbedR:::native_exact_knn_cpp(
        layout, 30L, 1L, "euclidean", 0.99)
    overlap <- vapply(seq_len(nrow(layout)), function(i) {
        length(intersect(reference[i, 1:30],
            embedded$indices[i, ])) / 30
    }, 0.0)
    c(silhouette = silhouette, preserve30 = mean(overlap))
}

probe <- function() {
    args <- commandArgs(trailingOnly = TRUE)
    stopifnot(length(args) == 2L, dir.exists(args[[1L]]))
    seed <- suppressWarnings(as.integer(args[[2L]]))
    stopifnot(!is.na(seed), seed > 0L)
    root <- tempfile("metal-tsne-fashion5k-", tmpdir = args[[1L]])
    dir.create(root)
    on.exit(unlink(root, recursive = TRUE), add = TRUE)
    setup <- prepare_fashion(root, seed)
    cpu <- run_fashion_fit(root, setup$graph, setup$start, "cpu")
    metal <- run_fashion_fit(root, setup$graph, setup$start,
        "metal")
    cpu_score <- score_fashion(cpu$layout, setup$labels,
        setup$knn$indices)
    metal_score <- score_fashion(metal$layout, setup$labels,
        setup$knn$indices)
    cat("input", setup$input, "seed", seed,
        "rows", nrow(setup$x),
        "edges", setup$graph$n_edges, "iterations", 250L, "\n")
    cat("cpu_seconds", cpu$elapsed,
        "metal_seconds", metal$elapsed, "\n")
    cat("cpu_silhouette", cpu_score[["silhouette"]],
        "metal_silhouette", metal_score[["silhouette"]], "\n")
    cat("cpu_preserve30", cpu_score[["preserve30"]],
        "metal_preserve30", metal_score[["preserve30"]], "\n")
    cat("metal_backend", metal$result$backend,
        "graph_access", metal$result$resources$graph_access,
        "fft_grid", metal$result$fft_grid_size, "\n")
}
probe()
