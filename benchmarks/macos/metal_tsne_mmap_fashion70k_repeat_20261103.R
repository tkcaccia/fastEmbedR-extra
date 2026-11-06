#!/usr/bin/env Rscript
suppressPackageStartupMessages(library(fastEmbedR))

prepare_graph <- function(root) {
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
    paths <- c(graph$offsets_path, graph$indices_path,
        graph$weights_path, init_path)
    cat("input_md5", paste(unname(tools::md5sum(paths)),
        collapse = ","), "\n")
    list(graph = graph, start = massive_matrix(init_path, 70000L, 3L))
}

load_labels <- function() {
    data <- new.env(parent = emptyenv())
    load(paste0(
        "/Users/silvanopiazza/Documents/Stefano/data/data/",
        "FashionMNIST/FashionMNIST_float32.RData"),
        envir = data)
    labels <- as.integer(data$dataset$labels)
    stopifnot(length(labels) == 70000L)
    labels
}

run_repeat <- function(root, graph, start, labels, index,
        iterations) {
    output <- file.path(root, paste0("metal", index, ".f32"))
    early <- min(50L, iterations)
    elapsed <- system.time({
        fit <- massive_tsne_optimize(graph, start, output,
            early_exaggeration_iter = early,
            n_iter = iterations - early,
            learning_rate = "auto", memory_limit = "2GB",
            backend = "metal")
    })[["elapsed"]]
    layout <- massive_read_rows(fit, 1L, 70000L)
    stopifnot(all(is.finite(layout)))
    sample_rows <- seq.int(1L, 70000L, by = 70L)
    score <- as.numeric(summary(cluster::silhouette(
        labels[sample_rows], stats::dist(layout[
            sample_rows, , drop = FALSE])))$avg.width)
    cat("repeat", index, "seconds", elapsed,
        "silhouette", score,
        "layout_md5", unname(tools::md5sum(output)), "\n")
    layout
}

probe <- function() {
    args <- commandArgs(trailingOnly = TRUE)
    stopifnot(length(args) == 3L, dir.exists(args[[1L]]))
    repeats <- suppressWarnings(as.integer(args[[2L]]))
    iterations <- suppressWarnings(as.integer(args[[3L]]))
    stopifnot(!is.na(repeats), repeats >= 2L, repeats <= 10L,
        !is.na(iterations), iterations >= 1L, iterations <= 250L)
    root <- tempfile("metal-tsne-repeat70k-", tmpdir = args[[1L]])
    dir.create(root)
    on.exit(unlink(root, recursive = TRUE), add = TRUE)
    setTimeLimit(elapsed = 300, transient = FALSE)
    prepared <- prepare_graph(root)
    labels <- load_labels()
    first <- NULL
    for (index in seq_len(repeats)) {
        layout <- run_repeat(root, prepared$graph, prepared$start,
            labels, index, iterations)
        if (is.null(first)) first <- layout else {
            delta <- layout - first
            cat("delta_from_first", index,
                "max_abs", max(abs(delta)),
                "relative_rms", sqrt(mean(delta^2)) /
                    max(sqrt(mean(first^2)), 1e-8), "\n")
        }
    }
}
probe()
