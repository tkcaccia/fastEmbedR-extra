#!/usr/bin/env Rscript
suppressPackageStartupMessages(library(fastEmbedR))
args <- commandArgs(trailingOnly = TRUE)
stopifnot(length(args) == 2L)
source(args[[1L]], local = TRUE)
case <- args[[2L]]
root <- dirname(args[[1L]])
x <- matrix(readBin(file.path(root, "digits.f32"), "numeric",
    n = 300L * 784L, size = 4L, endian = "little"),
    nrow = 300L, byrow = TRUE)
labels <- readBin(file.path(root, "digits.i32"), "integer",
    n = 300L, size = 4L, endian = "little")
stopifnot(identical(dim(x), c(300L, 784L)),
    length(labels) == 300L, identical(sort(unique(labels)), 0:9),
    all(is.finite(x)))

score_embedding <- function(fit, method, backend, devices, dimensions) {
    layout <- layout_matrix(fit)
    stopifnot(identical(dim(layout), c(300L, dimensions)),
        all(is.finite(layout)), all(apply(layout, 2L, sd) > 0))
    quality <- quality_metrics(x, layout, labels,
        perplexity = 15, support_multiplier = 3, k = 15L)
    stopifnot(all(is.finite(as.numeric(quality))),
        quality$trustworthiness >= 0.7,
        quality$label_knn_accuracy >= 0.45)
    cat("QUALITY", method, dimensions, backend,
        if (is.null(devices)) "default" else
            paste(devices, collapse = ","),
        "trust", format(quality$trustworthiness, digits = 5),
        "preserve15", format(quality$preserve_at_30, digits = 5),
        "label_accuracy", format(quality$label_knn_accuracy, digits = 5),
        "sampled_kl", format(quality$sampled_kl, digits = 5), "\n")
    quality
}

fit_embedding <- function(method, dimensions, backend, devices) {
    common <- list(data = x, n_components = dimensions,
        backend = backend, devices = devices, seed = 42L,
        n.cores = 2L)
    if (identical(method, "tsne")) {
        do.call(tsne, c(common, list(perplexity = 15,
            pca_dims = 50L, early_exaggeration_iter = 50L,
            n_iter = 250L, learning_rate = "auto",
            auto_config = FALSE)))
    } else {
        do.call(umap, c(common, list(n_neighbors = 30L)))
    }
}

adjusted_rand <- function(a, b) {
    tab <- table(a, b)
    choose2 <- function(x) x * (x - 1) / 2
    observed <- sum(choose2(tab))
    row_pairs <- sum(choose2(rowSums(tab)))
    col_pairs <- sum(choose2(colSums(tab)))
    total <- choose2(length(a))
    expected <- row_pairs * col_pairs / total
    denominator <- (row_pairs + col_pairs) / 2 - expected
    if (denominator == 0) return(NA_real_)
    (observed - expected) / denominator
}

if (startsWith(case, "embed_")) {
    fields <- strsplit(case, "_", fixed = TRUE)[[1L]]
    stopifnot(length(fields) == 3L,
        fields[[2L]] %in% c("tsne", "umap"),
        fields[[3L]] %in% c("2d", "3d"))
    method <- fields[[2L]]
    dimensions <- as.integer(substr(fields[[3L]], 1L, 1L))
    results <- list()
    for (backend in c("cpu", "cuda1", "cuda2")) {
        device <- switch(backend, cpu = NULL, cuda1 = NULL,
            cuda2 = c(0L, 1L))
        type <- if (backend == "cpu") "cpu" else "cuda"
        fit <- fit_embedding(method, dimensions, type, device)
        results[[backend]] <- score_embedding(fit, method,
            type, device, dimensions)
    }
    for (backend in c("cuda1", "cuda2")) {
        delta <- results[[backend]]$trustworthiness -
            results$cpu$trustworthiness
        cat("TRUST_DELTA", method, dimensions, backend,
            format(delta, digits = 5), "\n")
        stopifnot(is.finite(delta), delta >= -0.12)
    }
} else if (identical(case, "cluster")) {
    graph <- knn_graph(x, k = 20L, backend = "cpu")
    for (method in c("louvain", "leiden")) {
        results <- list()
        for (backend in c("cpu", "cuda1", "cuda2")) {
            device <- if (backend == "cuda2") c(0L, 1L) else NULL
            type <- if (backend == "cpu") "cpu" else "cuda"
            fit <- graph_cluster(graph, method = method,
                backend = type, n_runs = 1L, seed = 42L,
                devices = device)
            ari <- adjusted_rand(fit$membership, labels)
            stopifnot(length(fit$membership) == 300L,
                all(!is.na(fit$membership)), is.finite(ari),
                is.finite(fit$modularity),
                isTRUE(fit$connected_communities))
            cat("CLUSTER_QUALITY", method, backend,
                "ari", format(ari, digits = 5),
                "modularity", format(fit$modularity, digits = 5),
                "communities", fit$n_communities, "\n")
            results[[backend]] <- ari
        }
        stopifnot(results$cuda1 >= results$cpu - 0.2,
            results$cuda2 >= results$cpu - 0.2)
    }
} else stop("Unknown quality case: ", case)
cat("MNIST_QUALITY_CASE_PASS", case, "\n")
