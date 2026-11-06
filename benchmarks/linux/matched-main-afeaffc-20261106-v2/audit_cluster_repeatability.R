#!/usr/bin/env Rscript
path <- "/scratch/firenze/NN/Data/USPS/USPS_float32.RData"
expected <- paste0(
    "b4cc55441bde1e61a3588bba172762e11d14463a06b1869d2b",
    "b3d16e719d6811")
digest <- system2("sha256sum", shQuote(path), stdout = TRUE)
if (length(digest) != 1L ||
    substr(digest, 1L, 64L) != expected)
    stop("USPS resident input identity differs.")
env <- new.env(parent = emptyenv())
keys <- load(path, envir = env)
items <- lapply(keys, function(key) get(key, envir = env))
items <- Filter(function(item) is.list(item) &&
    !is.null(item$data) && !is.null(item$labels), items)
if (length(items) != 1L) stop("USPS data object is ambiguous.")
if (inherits(items[[1L]]$data, c("fastEmbedR_massive_matrix",
    "DelayedMatrix", "HDF5Matrix", "big.matrix", "ff")))
    stop("File-backed data is forbidden on HPC.")
x <- float::dbl(items[[1L]]$data)
if (!is.matrix(x) || nrow(x) != 11000L || ncol(x) != 256L)
    stop("USPS shape differs from manifest.")
scores <- fastEmbedR::pca(x, ncomp = 30L, backend = "cpu",
    n.cores = 1L, seed = 4L, massive = "off")$scores
make_graph <- function(workers) fastEmbedR::knn_graph(scores,
    k = 30L, backend = "cpu", n.cores = workers)
graph_4a <- make_graph(4L)
graph_4b <- make_graph(4L)
graph_1a <- make_graph(1L)
graph_1b <- make_graph(1L)
same_graph <- function(a, b) {
    identical(a$from, b$from) && identical(a$to, b$to) &&
        identical(a$weight, b$weight)
}
fit <- function(graph) fastEmbedR::graph_cluster(graph,
    method = "leiden", backend = "cpu", n.cores = 4L,
    seed = 4L, parallel.mode = "fit")
fit_4a <- fit(graph_4a)
fit_4a_repeat <- fit(graph_4a)
fit_4b <- fit(graph_4b)
fit_1a <- fit(graph_1a)
fit_1b <- fit(graph_1b)
partition <- function(x) list(communities = x$n_communities,
    modularity = x$modularity)
result <- list(
    input_sha256 = expected,
    rows = nrow(x), columns = ncol(x),
    graph_4core_equal = same_graph(graph_4a, graph_4b),
    graph_1core_equal = same_graph(graph_1a, graph_1b),
    same_graph_fit_equal = identical(
        fit_4a$membership, fit_4a_repeat$membership),
    graph_4core_fit_equal = identical(
        fit_4a$membership, fit_4b$membership),
    graph_1core_fit_equal = identical(
        fit_1a$membership, fit_1b$membership),
    graph_4core_knn_backend = graph_4a$parameters$knn_backend,
    graph_1core_knn_backend = graph_1a$parameters$knn_backend,
    fit_4a = partition(fit_4a),
    fit_4b = partition(fit_4b),
    fit_1a = partition(fit_1a),
    fit_1b = partition(fit_1b))
cat(jsonlite::toJSON(result, auto_unbox = TRUE, pretty = TRUE), "\n")
