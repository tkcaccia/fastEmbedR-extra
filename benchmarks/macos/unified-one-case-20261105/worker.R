#!/usr/bin/env Rscript

args <- commandArgs(trailingOnly = TRUE)
if (length(args) != 2L) stop("Need CASE.json and RESULT_DIR.")
case <- jsonlite::fromJSON(args[[1L]])
result_dir <- args[[2L]]
root <- "/Users/silvanopiazza/Documents/Stefano/"
if (!all(startsWith(c(case$input_path, case$source_dir,
        result_dir), root)) || case$storage_mode != "resident" ||
        case$fit_scope != "full" || isTRUE(case$spill) ||
        case$scientific_tests != 1L || case$warmup_fits != 0L ||
        !case$backend %in% c("cpu", "metal") ||
        !case$method %in% c("PCA", "t-SNE", "UMAP",
            "Leiden", "Louvain") ||
        case$cores < 1L || case$pca_rank < 1L ||
        case$expected_rows < 2L || case$expected_columns < 1L ||
        (case$backend == "metal" && case$cores != 1L)) stop(
        "Mac worker rejects this case before calculation.")
sha256 <- function(path) {
    value <- system2("shasum", c("-a", "256", shQuote(path)),
        stdout = TRUE, stderr = TRUE)
    if (length(value) != 1L || !grepl("^[0-9a-f]{64} ", value))
        stop("Cannot verify file hash: ", path)
    substr(value, 1L, 64L)
}
archive <- file.path(case$source_dir, "source.tar.xz")
dll <- file.path(case$source_dir,
    "library/fastEmbedR/libs/fastEmbedR.so")
if (!identical(sha256(case$input_path), case$input_sha256) ||
    !identical(sha256(archive), case$source_sha256) ||
    !identical(sha256(dll), case$dll_sha256)) stop(
    "Mac worker input or package identity mismatch.")
suppressPackageStartupMessages(library(fastEmbedR))
started <- proc.time()[[3L]]
environment <- new.env(parent = emptyenv())
loaded <- load(case$input_path, envir = environment)
matches <- lapply(loaded, function(name) {
    item <- get(name, envir = environment, inherits = FALSE)
    if (is.list(item) && !is.null(item$data) &&
        !is.null(item$labels)) item else NULL
})
matches <- Filter(Negate(is.null), matches)
if (length(matches) != 1L) stop("Dataset object is ambiguous.")
x <- float::dbl(matches[[1L]]$data)
labels <- matches[[1L]]$labels
if (nrow(x) != case$expected_rows ||
    ncol(x) != case$expected_columns ||
    length(labels) != nrow(x)) stop("Dataset shape or labels changed.")
load_seconds <- unname(proc.time()[[3L]] - started)
started <- proc.time()[[3L]]
scores <- if (case$method == "PCA" ||
    ncol(x) == case$pca_rank) x else
    fastEmbedR::pca(x, ncomp = case$pca_rank,
        backend = "cpu", n.cores = 1L,
        seed = case$seed)$scores
preprocess_seconds <- unname(proc.time()[[3L]] - started)
if (nrow(scores) != nrow(x) ||
    ncol(scores) != if (case$method == "PCA")
        ncol(x) else case$pca_rank) stop(
        "Preprocessing output has wrong shape.")
started <- proc.time()[[3L]]
graph <- if (case$method %in% c("Leiden", "Louvain"))
    fastEmbedR::knn_graph(scores, k = 30L,
        backend = case$backend, n.cores = case$cores) else NULL
graph_seconds <- unname(proc.time()[[3L]] - started)
if (!is.null(graph) && case$backend == "metal" &&
    !startsWith(graph$parameters$knn_backend, "metal")) stop(
    "Metal graph KNN fell back.")
fit_case <- function(case, x, scores, graph) {
    switch(case$method,
        PCA = fastEmbedR::pca(x, ncomp = case$dimensions,
            backend = case$backend, n.cores = case$cores,
            seed = case$seed),
        `t-SNE` = fastEmbedR::tsne(scores,
            n_components = case$dimensions, perplexity = 30L,
            n_iter = 300L, backend = case$backend,
            n.cores = case$cores, seed = case$seed),
        UMAP = fastEmbedR::umap(scores, n_neighbors = 30L,
            n_components = case$dimensions,
            backend = case$backend, n.cores = case$cores,
            seed = case$seed),
        Leiden = fastEmbedR::graph_cluster(graph,
            method = "leiden", backend = case$backend,
            n.cores = case$cores, seed = case$seed,
            parallel.mode = if (case$backend == "cpu")
                "fit" else "restarts"),
        Louvain = fastEmbedR::graph_cluster(graph,
            method = "louvain", backend = case$backend,
            n.cores = case$cores, seed = case$seed,
            parallel.mode = if (case$backend == "cpu")
                "fit" else "restarts"),
        stop("Unknown method."))
}
started <- proc.time()[[3L]]
fit <- fit_case(case, x, scores, graph)
fit_seconds <- unname(proc.time()[[3L]] - started)
observed <- if (case$method %in% c("t-SNE", "UMAP"))
    fit$parameters$backend else fit$backend
if (case$backend == "metal" && !startsWith(observed, "metal") ||
    case$backend == "cpu" && !startsWith(observed, "cpu")) stop(
    "Effective backend differs from request.")
if (case$backend == "metal" && case$method == "PCA" &&
    fit$engine != "native_metal_mps") stop(
    "Metal PCA engine differs from request.")
if (case$method %in% c("t-SNE", "UMAP") &&
    (nrow(fit$layout) != nrow(x) ||
     ncol(fit$layout) != case$dimensions)) stop(
    "Embedding output shape is wrong.")
if (case$method == "PCA" &&
    (nrow(fit$scores) != nrow(x) ||
     ncol(fit$scores) != case$dimensions)) stop(
    "PCA output shape is wrong.")
if (case$method %in% c("Leiden", "Louvain") &&
    length(fit$membership) != nrow(x)) stop(
    "Clustering output shape is wrong.")
if (case$backend == "metal" &&
    case$method %in% c("t-SNE", "UMAP") &&
    fit$parameters$nn_backend != "metal") stop(
    "Metal nearest neighbors fell back.")
if (case$backend == "metal" && case$method == "UMAP" &&
    fit$parameters$optimizer_backend != "metal") stop(
    "Metal UMAP optimizer fell back.")
if (case$backend == "cpu" && case$cores > 1L &&
    case$method %in% c("Leiden", "Louvain") &&
    fit$effective_cpu_workers != case$cores) stop(
    "Clustering effective worker count is wrong.")
if (case$backend == "cpu" && case$cores > 1L &&
    case$method == "UMAP" &&
    fit$parameters$n.cores_effective != case$cores) stop(
    "UMAP effective worker count is wrong.")
started <- proc.time()[[3L]]
quality <- if (case$method %in% c("t-SNE", "UMAP")) {
    test <- fastEmbedR::evaluate_embedding(scores, fit$layout,
        labels = labels, k = 15L, primary_k = 15L,
        sample_size_for_global_metrics = case$quality_sample,
        sample_size_for_local_metrics = case$quality_sample,
        n.cores = 1L, seed = case$seed)
    list(trustworthiness = test$trustworthiness,
        label_accuracy = test$label_knn_accuracy)
} else if (case$method %in% c("Leiden", "Louvain")) {
    list(ari = fastEmbedR:::adjusted_rand_index(
        labels, fit$membership),
        communities = fit$n_communities,
        modularity = fit$modularity)
} else list(singular_values = fit$singular_values)
quality_seconds <- unname(proc.time()[[3L]] - started)
output <- if (case$method == "PCA") fit$scores else
    if (case$method %in% c("t-SNE", "UMAP")) fit$layout else
    fit$membership
saveRDS(output, file.path(result_dir, "output.rds"),
    compress = "xz")
effective <- if (!is.null(fit$effective_cpu_workers))
    fit$effective_cpu_workers else if (!is.null(fit$n.cores_effective))
    fit$n.cores_effective else fit$parameters$n.cores_effective
if (length(effective) != 1L || is.na(effective) ||
    identical(effective, "NA")) effective <- NULL
metrics <- list(case_id = case$case_id, dataset = case$dataset,
    method = case$method, backend = case$backend,
    observed_backend = observed, cores = case$cores,
    effective_cpu_workers = effective,
    seed = case$seed, repetition = case$repetition,
    storage_mode = "resident", fit_scope = "full",
    n_rows = nrow(x), n_columns = ncol(x),
    dimensions = case$dimensions,
    load_seconds = load_seconds,
    preprocess_seconds = preprocess_seconds,
    graph_seconds = graph_seconds,
    fit_seconds = fit_seconds,
    quality_seconds = quality_seconds,
    quality = quality, result_file = "output.rds")
jsonlite::write_json(metrics, file.path(result_dir, "metrics.json"),
    auto_unbox = TRUE, pretty = TRUE, null = "null")
