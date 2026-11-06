#!/usr/bin/env Rscript
suppressPackageStartupMessages(library(fastEmbedR))
args <- commandArgs(trailingOnly = TRUE)
stopifnot(length(args) == 2L, args[[2L]] %in% c("tsne", "umap"))
source(args[[1L]], local = TRUE)
root <- dirname(args[[1L]])
x <- matrix(readBin(file.path(root, "digits.f32"), "numeric",
    n = 300L * 784L, size = 4L, endian = "little"),
    nrow = 300L, byrow = TRUE)
labels <- readBin(file.path(root, "digits.i32"), "integer",
    n = 300L, size = 4L, endian = "little")
stopifnot(identical(dim(x), c(300L, 784L)),
    length(labels) == 300L, identical(sort(unique(labels)), 0:9),
    all(is.finite(x)))

score <- function(fit, method, scope) {
    layout <- layout_matrix(fit)
    stopifnot(identical(dim(layout), c(300L, 3L)),
        all(is.finite(layout)), all(apply(layout, 2L, sd) > 0))
    q <- quality_metrics(x, layout, labels,
        perplexity = 15, support_multiplier = 3, k = 15L)
    stopifnot(all(is.finite(as.numeric(q))))
    cat("LANDMARK_QUALITY", method, scope,
        "trust", q$trustworthiness,
        "preserve15", q$preserve_at_30,
        "label_accuracy", q$label_knn_accuracy,
        "sampled_kl", q$sampled_kl, "\n")
    q
}

fit_one <- function(method, scope) {
    common <- list(data = x, backend = "cuda", seed = 42L,
        n_components = 3L, n.cores = 1L)
    if (identical(scope, "landmark")) common$landmarks <- 0.5
    started <- proc.time()[[3L]]
    fit <- if (identical(method, "tsne")) {
        do.call(tsne, c(common, list(perplexity = 15,
            pca_dims = 50L, affinity_k = 45L,
            early_exaggeration_iter = 50L, n_iter = 250L,
            transform_iter = 100L, auto_config = FALSE)))
    } else {
        do.call(umap, c(common, list(n_neighbors = 30L)))
    }
    elapsed <- unname(proc.time()[[3L]] - started)
    stopifnot(identical(fit$parameters$backend, "cuda"))
    if (identical(scope, "landmark")) {
        stopifnot(length(fit$landmarks$indices) == 150L,
            identical(dim(fit$landmarks$layout), c(150L, 3L)))
    }
    q <- score(fit, method, scope)
    cat("LANDMARK_FIT_SECONDS", method, scope, elapsed, "\n")
    q
}

method <- args[[2L]]
full <- fit_one(method, "full")
landmark <- fit_one(method, "landmark")
delta <- landmark$trustworthiness - full$trustworthiness
cat("LANDMARK_TRUST_DELTA", method, delta, "\n")
stopifnot(is.finite(delta), delta >= -0.1,
    landmark$trustworthiness >= 0.7,
    landmark$label_knn_accuracy >= 0.4)
cat("CUDA_MNIST_LANDMARK_3D_PASS", method, "\n")
