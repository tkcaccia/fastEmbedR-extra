#!/usr/bin/env Rscript
root <- commandArgs(trailingOnly = TRUE)[[1L]]
.libPaths(c(file.path(root, "library"), .libPaths()))
stopifnot(startsWith(find.package("fastEmbedR"),
    file.path(root, "library")))
suppressPackageStartupMessages(library(fastEmbedR))
stopifnot(fastEmbedR:::embedding_cuda_available_cpp())

n <- 32L
indices <- outer(seq_len(n), 1:3,
    function(i, j) (i + j - 1L) %% n + 1L)
distances <- matrix(rep(c(0.2, 0.5, 0.9), n),
    nrow = n, byrow = TRUE)
for (dimensions in c(2L, 3L)) {
    fit <- fastEmbedR:::fast_knn_umap_core(indices,
        distances, n_components = dimensions,
        backend = "cuda", n_epochs = 10L, seed = 7L)
    observed <- matrix(as.numeric(fit), nrow = n)
    cfg <- attr(fit, "fastEmbedR_config")
    stopifnot(identical(dim(observed), c(n, dimensions)),
        all(is.finite(observed)),
        all(apply(observed, 2L, sd) > 0),
        identical(cfg$backend, "cuda"))
    cat("UMAP_SINGLE_GPU_PASS", dimensions, "D", "\n")
}
