#!/usr/bin/env Rscript
args <- commandArgs(trailingOnly = TRUE)
if (length(args) != 3L) stop("Need CASE, DATA_ROOT, RESULT_DIR.")
case <- jsonlite::fromJSON(args[[1L]])
root <- args[[2L]]
out <- args[[3L]]
if (case$backend != "cuda" || !case$gpus %in% 1:3 ||
    case$storage_mode != "in_memory" ||
    case$runtime_input != "resident" ||
    case$algorithm_state != "resident" ||
    isTRUE(case$spill) || case$fit_scope != "all_rows_optimized" ||
    case$scientific_tests != 1L || case$warmup_fits != 0L ||
    case$preprocessing_rank != 30L ||
    case$quality_sample != 600L)
    stop("Matched CUDA worker rejects this case.")
visible <- Sys.getenv("CUDA_VISIBLE_DEVICES", unset = "")
if (!nzchar(visible) ||
    length(strsplit(visible, ",", fixed = TRUE)[[1L]]) !=
        case$gpus) stop("CUDA visibility differs from case.")
devices <- if (case$gpus > 1L)
    seq.int(0L, case$gpus - 1L) else NULL
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
digest <- system2("sha256sum", shQuote(path),
    stdout = TRUE, stderr = TRUE)
if (length(digest) != 1L ||
    !identical(substr(digest, 1L, 64L), case$input_sha256))
    stop("Resident input identity differs from manifest.")
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
        n.cores = 1L, seed = case$seed)$scores
preprocess_seconds <- unname(proc.time()[[3L]] - pre_started)
graph_started <- proc.time()[[3L]]
graph <- if (case$method %in% c("Leiden", "Louvain"))
    fastEmbedR::knn_graph(scores, k = 30L, backend = "cuda",
        n.cores = case$cores) else NULL
graph_seconds <- unname(proc.time()[[3L]] - graph_started)
fit_started <- proc.time()[[3L]]
fit <- switch(case$method,
    PCA = fastEmbedR::pca(x, ncomp = case$dimensions,
        backend = "cuda", n.cores = case$cores, seed = case$seed,
        devices = devices),
    `t-SNE` = fastEmbedR::tsne(scores,
        n_components = case$dimensions, perplexity = 30L,
        n_iter = 300L, backend = "cuda", n.cores = case$cores,
        seed = case$seed, devices = devices),
    UMAP = fastEmbedR::umap(scores, n_neighbors = 30L,
        n_components = case$dimensions, backend = "cuda",
        n.cores = case$cores, seed = case$seed,
        devices = devices),
    Leiden = fastEmbedR::graph_cluster(graph, method = "leiden",
        backend = "cuda", n.cores = 1L, seed = case$seed,
        devices = devices, parallel.mode = "restarts"),
    Louvain = fastEmbedR::graph_cluster(graph, method = "louvain",
        backend = "cuda", n.cores = 1L, seed = case$seed,
        devices = devices, parallel.mode = "restarts"),
    stop("Unknown method."))
fit_seconds <- unname(proc.time()[[3L]] - fit_started)
if (inherits(fit, "massive_matrix") ||
    identical(fit$mode, "out_of_core")) stop(
    "File-backed CUDA result is forbidden on HPC.")
observed <- if (case$method %in% c("t-SNE", "UMAP"))
    fit$parameters$backend else fit$backend
if (!identical(observed, "cuda")) stop("CUDA backend fell back.")
observed_devices <- if (case$method %in% c("t-SNE", "UMAP"))
    fit$parameters$gpu_devices else fit$gpu_devices
if (case$gpus > 1L &&
    !identical(as.integer(observed_devices), devices)) stop(
    "Coordinated CUDA fit did not report all devices.")
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
    backend = case$backend, observed_backend = observed,
    gpu_devices = observed_devices, requested_gpus = case$gpus,
    cores = case$cores, seed = case$seed,
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
