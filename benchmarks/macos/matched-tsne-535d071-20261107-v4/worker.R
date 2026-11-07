#!/usr/bin/env Rscript

args <- commandArgs(trailingOnly = TRUE)
if (length(args) != 2L) stop("Need CASE.json and RESULT_DIR.")
case <- jsonlite::fromJSON(args[[1L]])
result_dir <- args[[2L]]
root <- "/Users/silvanopiazza/Documents/Stefano/"
controls <- case$fit_controls
if (!all(startsWith(c(case$input_path, case$source_dir,
        result_dir), root)) || case$storage_mode != "resident" ||
        case$fit_scope != "full" || isTRUE(case$spill) ||
        case$method != "t-SNE" ||
        !case$backend %in% c("cpu", "metal") ||
        !case$dimensions %in% c(2L, 3L) ||
        !identical(controls$perplexity, 30L) ||
        !identical(controls$early_exaggeration_iter, 250L) ||
        !identical(controls$n_iter, 300L) ||
        !identical(controls$auto_config, FALSE)) stop(
        "Matched Mac t-SNE worker rejects this case.")

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
suppressPackageStartupMessages(library(float))

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
x <- matches[[1L]]$data
labels <- matches[[1L]]$labels
if (!inherits(x, "float32") ||
    nrow(x) != case$expected_rows ||
    ncol(x) != case$expected_columns ||
    length(labels) != nrow(x)) stop(
    "Input precision, shape, or labels differ from manifest.")
load_seconds <- unname(proc.time()[[3L]] - started)

started <- proc.time()[[3L]]
scores <- if (ncol(x) == case$pca_rank) x else
    fastEmbedR::pca(x, ncomp = case$pca_rank,
        backend = "cpu", n.cores = 1L,
        seed = case$seed, massive = "off")$scores
if (!inherits(scores, "float32") ||
    nrow(scores) != nrow(x) ||
    ncol(scores) != case$pca_rank) stop(
    "PCA preprocessing changed precision or shape.")
preprocess_seconds <- unname(proc.time()[[3L]] - started)

started <- proc.time()[[3L]]
fit <- fastEmbedR::tsne(scores,
    n_components = case$dimensions,
    perplexity = controls$perplexity,
    early_exaggeration_iter = controls$early_exaggeration_iter,
    n_iter = controls$n_iter,
    auto_config = controls$auto_config,
    backend = case$backend, n.cores = case$cores,
    seed = case$seed, massive = "off")
fit_seconds <- unname(proc.time()[[3L]] - started)
observed <- fit$parameters$backend
if (!is.character(observed) || length(observed) != 1L ||
    !startsWith(observed, case$backend)) stop(
    "Effective backend differs from request.")
if (case$backend == "metal" &&
    !identical(fit$parameters$nn_backend, "metal")) stop(
    "Metal nearest neighbors fell back.")
layout <- fit$layout
if (nrow(layout) != nrow(x) ||
    ncol(layout) != case$dimensions ||
    any(!is.finite(layout))) stop(
    "Embedding output is missing, nonfinite, or wrong-shaped.")
effective <- fit$parameters$n.cores_effective
if (case$backend == "cpu" &&
    !identical(as.integer(effective), as.integer(case$cores))) stop(
    "Effective CPU worker count differs from request.")

started <- proc.time()[[3L]]
quality_fit <- fastEmbedR::evaluate_embedding(scores, layout,
    labels = labels, k = 15L, primary_k = 15L,
    sample_size_for_global_metrics = case$quality_sample,
    sample_size_for_local_metrics = case$quality_sample,
    n.cores = 1L, seed = case$seed)
quality <- list(trustworthiness = quality_fit$trustworthiness,
    label_accuracy = quality_fit$label_knn_accuracy)
if (any(!is.finite(unlist(quality))) ||
    any(unlist(quality) < 0 | unlist(quality) > 1)) stop(
    "Embedding quality is missing or invalid.")
quality_seconds <- unname(proc.time()[[3L]] - started)

started <- proc.time()[[3L]]
saveRDS(layout, file.path(result_dir, "output.rds"),
    compress = "xz")
write_seconds <- unname(proc.time()[[3L]] - started)
metrics <- list(case_id = case$case_id, dataset = case$dataset,
    method = case$method, backend = case$backend,
    observed_backend = observed, cores = case$cores,
    effective_cpu_workers = if (case$backend == "cpu")
        as.integer(effective) else NULL,
    seed = case$seed, repetition = case$repetition,
    package_version = as.character(packageVersion("fastEmbedR")),
    storage_mode = "resident", fit_scope = "full",
    input_precision = "float32", preprocess_precision = "float32",
    input_sha256 = case$input_sha256,
    scientific_controls = controls,
    n_rows = nrow(x), n_columns = ncol(x),
    dimensions = case$dimensions,
    load_seconds = load_seconds,
    preprocess_seconds = preprocess_seconds,
    graph_seconds = 0,
    fit_seconds = fit_seconds,
    quality_seconds = quality_seconds,
    write_seconds = write_seconds,
    quality = quality, result_file = "output.rds")
jsonlite::write_json(metrics, file.path(result_dir, "metrics.json"),
    auto_unbox = TRUE, pretty = TRUE, null = "null")
