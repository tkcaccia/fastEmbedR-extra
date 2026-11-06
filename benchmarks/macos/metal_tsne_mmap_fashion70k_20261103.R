#!/usr/bin/env Rscript
suppressPackageStartupMessages(library(fastEmbedR))

probe <- function() {
    args <- commandArgs(trailingOnly = TRUE)
    stopifnot(length(args) == 1L, dir.exists(args[[1L]]))
    root <- tempfile("metal-tsne-fashion70k-", tmpdir = args[[1L]])
    dir.create(root)
    on.exit(unlink(root, recursive = TRUE), add = TRUE)
    setTimeLimit(elapsed = 300, transient = FALSE)
    prefix <- paste0(
        "/Users/silvanopiazza/Documents/Stefano/data/results/",
        "fashion70k-metal-exact-knn-v1/knn")
    source <- massive_knn_graph(prefix, 70000L, 30L)
    graph <- massive_tsne_affinities(source, perplexity = 10,
        output = file.path(root, "affinity"),
        memory_limit = "256MB")
    set.seed(17)
    initial <- matrix(rnorm(70000L * 3L, sd = 0.0001),
        70000L, 3L)
    init_path <- file.path(root, "init.f32")
    writeBin(as.numeric(t(initial)), init_path,
        size = 4L, endian = "little")
    start <- massive_matrix(init_path, 70000L, 3L)
    elapsed <- system.time({
        fit <- massive_tsne_optimize(graph, start,
            file.path(root, "metal.f32"),
            early_exaggeration_iter = 50L, n_iter = 200L,
            learning_rate = "auto", memory_limit = "2GB",
            backend = "metal")
    })[["elapsed"]]
    data <- new.env(parent = emptyenv())
    load(paste0(
        "/Users/silvanopiazza/Documents/Stefano/data/data/",
        "FashionMNIST/FashionMNIST_float32.RData"),
        envir = data)
    labels <- as.integer(data$dataset$labels)
    sample_rows <- seq.int(1L, 70000L, by = 70L)
    layout <- massive_read_rows(fit, 1L, 70000L)
    stopifnot(length(labels) == 70000L,
        all(is.finite(layout)))
    silhouette <- as.numeric(summary(cluster::silhouette(
        labels[sample_rows], stats::dist(layout[
            sample_rows, , drop = FALSE])))$avg.width)
    cat("rows", 70000L, "edges", graph$n_edges,
        "iterations", 250L, "optimizer_seconds", elapsed, "\n")
    cat("sampled_silhouette", silhouette,
        "backend", fit$backend,
        "graph_access", fit$resources$graph_access,
        "planned_peak_ram_bytes",
        fit$resources$estimated_peak_ram_bytes, "\n")
}
probe()
