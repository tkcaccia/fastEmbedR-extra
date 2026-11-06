#!/usr/bin/env Rscript

args <- commandArgs(trailingOnly = TRUE)
if (length(args) != 1L) stop("Usage: smoke_m3_ultra_routes_v1.R ROOT")
library(fastEmbedR)
library(float)
root <- normalizePath(args[[1L]], mustWork = TRUE)
private_library <- Sys.getenv("FASTEMBEDR_MAC_EXPECTED_LIBRARY")
if (!startsWith(root, "/Users/silvanopiazza/Documents/Stefano/") ||
    !nzchar(private_library) ||
    !identical(dirname(normalizePath(
        system.file(package = "fastEmbedR"))),
        normalizePath(private_library, mustWork = TRUE))) {
    stop("Mac route smoke loaded the wrong package library")
}
set.seed(410)
x <- fl(matrix(rnorm(256L * 8L), nrow = 256L))
knn <- precompute_knn(x, k = 30L, backend = "metal", n.cores = 1L)
if (!grepl("metal", attr(knn, "backend"), fixed = TRUE)) {
    stop("Native Metal KNN did not run")
}
pca_fit <- pca(x, ncomp = 2L, backend = "metal",
    seed = 4L, tsne_init = TRUE)
tsne_fit <- tsne(x, perplexity = 30L, backend = "metal",
    n.cores = 1L, seed = 4L, record_costs = FALSE)
umap_fit <- umap(x, n_neighbors = 30L, backend = "metal",
    n.cores = 1L, graph_mode = "fuzzy", seed = 4L)
fits <- list(pca = pca_fit, tsne = tsne_fit, umap = umap_fit)
for (method in names(fits)) {
    fit <- fits[[method]]
    backend <- if (method == "pca") fit$backend else if
        (method == "tsne") fit$parameters$backend else
        fit$parameters$optimizer_backend
    observed <- if (method == "pca") {
        fit$metal_allocated_bytes_observed
    } else fit$parameters$metal_allocated_bytes_observed
    layout <- if (method == "pca") fit$scores else fit$layout
    expected_backend <- if (method == "pca")
        "metal_mps_rsvd" else "metal"
    if (!identical(backend, expected_backend) ||
        length(observed) != 1L || !is.finite(observed) ||
        observed <= 0 ||
        !identical(dim(as.matrix(layout)), c(256L, 2L)) ||
        any(!is.finite(as.matrix(layout)))) {
        stop("Metal route, allocation or layout failed: ", method)
    }
    print(data.frame(method = method, backend = backend,
        metal_allocated_bytes_observed = observed))
}
