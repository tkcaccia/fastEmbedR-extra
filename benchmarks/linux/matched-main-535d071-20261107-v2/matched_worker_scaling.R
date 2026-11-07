#!/usr/bin/env Rscript
args <- commandArgs(trailingOnly = TRUE)
if (length(args) != 3L) stop("Need CASE, DATA_ROOT, RESULT_DIR.")
case <- jsonlite::fromJSON(args[[1L]])
root <- args[[2L]]
out <- args[[3L]]
if (case$backend != "cpu" || case$gpus != 0L ||
    case$storage_mode != "in_memory" ||
    case$runtime_input != "resident" ||
    case$algorithm_state != "resident" ||
    isTRUE(case$spill) || case$fit_scope != "all_rows_optimized" ||
    case$scientific_tests != 1L || case$warmup_fits != 0L)
    stop("Matched worker rejects nonresident or non-CPU case.")
suppressPackageStartupMessages(library(fastEmbedR))
files <- c(COIL20 = "COIL20/COIL20_float32.RData",
    USPS = "USPS/USPS_float32.RData",
    MNIST = "MNIST/MNIST_float32.RData",
    `Fashion-MNIST` = "FashionMNIST/FashionMNIST_float32.RData",
    MetRef = "MetRef/MetRef_float32.RData",
    mass41 = "mass41/mass41_float32.RData",
    flow18 = "flow18/flow18_float32.RData",
    `ImageNet features` = "imagenet/imagenet_float32.RData",
    FlowRepository = paste0("FlowRepository_FR-FCM-ZYRM_files/",
        "van_unen_FR-FCM-ZYRM_float32.RData"),
    `Tabula Muris` = "TabulaMuris/TabulaMuris_float32.RData",
    `Macosko retina` =
        "Macosko2015_retina/Macosko2015_retina_float32.RData")
if (!case$dataset %in% names(files)) stop("Unknown dataset.")
path <- file.path(root, files[[case$dataset]])
load_started <- proc.time()[[3L]]
env <- new.env(parent = emptyenv())
keys <- load(path, envir = env)
items <- lapply(keys, function(key) get(key, envir = env))
items <- Filter(function(x) is.list(x) &&
    !is.null(x$data) && !is.null(x$labels), items)
if (length(items) != 1L) stop("Dataset object is ambiguous.")
item <- items[[1L]]
if (inherits(item$data, c("fastEmbedR_massive_matrix",
    "DelayedMatrix", "HDF5Matrix", "big.matrix", "ff")))
    stop("File-backed data forbidden on HPC.")
x <- float::dbl(item$data)
labels <- item$labels
if (!is.matrix(x) || nrow(x) != case$expected_rows ||
    ncol(x) != case$expected_columns ||
    length(labels) != nrow(x) || any(!is.finite(x)))
    stop("Input shape or values differ from manifest.")
load_seconds <- unname(proc.time()[[3L]] - load_started)
pre_started <- proc.time()[[3L]]
rank <- min(30L, nrow(x) - 1L, ncol(x) - 1L)
if (rank < 3L) stop("Insufficient preprocessing rank.")
scores <- if (case$method == "PCA") x else
    fastEmbedR::pca(x, ncomp = rank, backend = "cpu",
        n.cores = 1L, seed = case$seed,
        massive = "off")$scores
preprocess_seconds <- unname(proc.time()[[3L]] - pre_started)
graph_started <- proc.time()[[3L]]
graph <- if (case$method %in% c("Leiden", "Louvain"))
    fastEmbedR::knn_graph(scores, k = 30L, backend = "cpu",
        n.cores = case$cores) else NULL
graph_seconds <- unname(proc.time()[[3L]] - graph_started)
fit_started <- proc.time()[[3L]]
fit <- switch(case$method,
    PCA = fastEmbedR::pca(x, ncomp = case$dimensions,
        backend = "cpu", n.cores = case$cores, seed = case$seed,
        massive = "off"),
    `t-SNE` = fastEmbedR::tsne(scores,
        n_components = case$dimensions, perplexity = 30L,
        early_exaggeration_iter = 250L, n_iter = 300L,
        auto_config = FALSE, backend = "cpu", n.cores = case$cores,
        seed = case$seed, massive = "off"),
    UMAP = fastEmbedR::umap(scores, n_neighbors = 30L,
        n_components = case$dimensions, backend = "cpu",
        n.cores = case$cores, seed = case$seed,
        massive = "off"),
    Leiden = fastEmbedR::graph_cluster(graph, method = "leiden",
        backend = "cpu", n.cores = case$cores, seed = case$seed,
        parallel.mode = "fit"),
    Louvain = fastEmbedR::graph_cluster(graph, method = "louvain",
        backend = "cpu", n.cores = case$cores, seed = case$seed,
        parallel.mode = "fit"), stop("Unknown method."))
fit_seconds <- unname(proc.time()[[3L]] - fit_started)
observed <- if (case$method %in% c("t-SNE", "UMAP"))
    fit$parameters$backend else fit$backend
if (!startsWith(observed, "cpu")) stop("CPU backend fell back.")
output <- if (case$method == "PCA") fit$scores else
    if (case$method %in% c("t-SNE", "UMAP")) fit$layout else
    fit$membership
if (length(output) == 0L || any(!is.finite(output)))
    stop("Output is missing or nonfinite.")
if (case$method %in% c("PCA", "t-SNE", "UMAP") &&
    (nrow(output) != nrow(x) ||
     ncol(output) != case$dimensions))
    stop("Embedding shape differs from manifest.")
if (case$method %in% c("Leiden", "Louvain") &&
    length(output) != nrow(x))
    stop("Membership length differs from input.")
effective_cores <- switch(case$method,
    PCA = fit$n.cores_effective,
    `t-SNE` = fit$parameters$n.cores_effective,
    UMAP = fit$parameters$n.cores_effective,
    Leiden = fit$effective_cpu_workers,
    Louvain = fit$effective_cpu_workers)
expected_effective_cores <- if (case$method == "PCA")
    min(case$cores, ncol(x)) else case$cores
if (!identical(as.integer(effective_cores),
    as.integer(expected_effective_cores)))
    stop("Effective CPU worker count differs from request.")
quality_started <- proc.time()[[3L]]
quality <- if (case$method %in% c("t-SNE", "UMAP")) {
    result <- fastEmbedR::evaluate_embedding(scores, output,
        labels = labels, k = 15L, primary_k = 15L,
        sample_size_for_global_metrics =
            min(600L, nrow(x)),
        sample_size_for_local_metrics =
            min(600L, nrow(x)),
        n.cores = 1L, seed = case$seed)
    list(trustworthiness = result$trustworthiness,
        label_accuracy = result$label_knn_accuracy)
} else if (case$method %in% c("Leiden", "Louvain")) {
    list(ari = fastEmbedR:::adjusted_rand_index(
        labels, output), communities = fit$n_communities,
        modularity = fit$modularity)
} else list(singular_values = fit$singular_values)
quality_seconds <- unname(proc.time()[[3L]] - quality_started)
write_started <- proc.time()[[3L]]
saveRDS(output, file.path(out, "output.rds"), compress = "xz")
write_seconds <- unname(proc.time()[[3L]] - write_started)
metrics <- list(case_id = case$case_id,
    dataset = case$dataset, method = case$method,
    package_version = as.character(packageVersion("fastEmbedR")),
    fit_scope = case$fit_scope, storage_mode = case$storage_mode,
    input_sha256 = case$input_sha256,
    backend = case$backend, observed_backend = observed,
    cores = case$cores, cores_effective = as.integer(effective_cores),
    pca_native_shape_limited = if (case$method == "PCA")
        effective_cores < case$cores else NULL,
    pca_blas_cores_requested = if (case$method == "PCA")
        as.integer(fit$blas.n.cores_requested) else NULL,
    pca_blas_cores_observed = if (case$method == "PCA")
        as.integer(fit$blas.n.cores) else NULL,
    seed = case$seed,
    dimensions = case$dimensions,
    n_rows = nrow(x), n_columns = ncol(x),
    preprocessing_rank = if (case$method == "PCA")
        NULL else rank,
    load_seconds = load_seconds,
    preprocess_seconds = preprocess_seconds,
    graph_seconds = graph_seconds,
    fit_seconds = fit_seconds,
    quality_seconds = quality_seconds,
    write_seconds = write_seconds,
    quality = quality, result_file = "output.rds")
jsonlite::write_json(metrics, file.path(out, "metrics.json"),
    auto_unbox = TRUE, pretty = TRUE, null = "null")
