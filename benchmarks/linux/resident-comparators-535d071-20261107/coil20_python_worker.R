#!/usr/bin/env Rscript
args <- commandArgs(trailingOnly = TRUE)
if (length(args) != 2L) stop("Need METHOD and RESULT_DIR.")
method <- args[[1L]]
out <- args[[2L]]
if (!method %in% c("opentsne", "umaplearn") ||
    !dir.exists(out) ||
    Sys.getenv("SLURM_CPUS_PER_TASK") != "4" ||
    !Sys.getenv("CUDA_VISIBLE_DEVICES") %in% c("", "NoDevFiles"))
    stop("Comparator allocation or case differs from the reviewed pilot.")
worker_sha <- Sys.getenv("FASTEMBEDR_WORKER_SHA256")
image_sha <- Sys.getenv("FASTEMBEDR_IMAGE_SHA256")
if (!grepl("^[0-9a-f]{64}$", worker_sha) ||
    !identical(image_sha,
        "15b494004966c5e8ae4ada72db28024356cfa8a981333a37484ce75a09d08bf2"))
    stop("Comparator worker or image identity is missing.")
suppressPackageStartupMessages(library(fastEmbedR))
suppressPackageStartupMessages(library(float))
path <- "/scratch/firenze/NN/Data/COIL20/COIL20_float32.RData"
input_sha <- "8e53030869bcfbc228edc06ca970e69b78ddae13fb188327e8899194d5841d66"
started <- proc.time()[[3L]]
env <- new.env(parent = emptyenv())
keys <- load(path, envir = env)
items <- lapply(keys, function(key) get(key, envir = env))
items <- Filter(function(x) is.list(x) &&
    !is.null(x$data) && !is.null(x$labels), items)
if (length(items) != 1L) stop("Dataset object is ambiguous.")
x <- items[[1L]]$data
labels <- items[[1L]]$labels
if (!inherits(x, "float32") || nrow(x) != 1440L ||
    ncol(x) != 16384L || length(labels) != 1440L)
    stop("COIL20 float32 source differs from reviewed case.")
load_seconds <- unname(proc.time()[[3L]] - started)
started <- proc.time()[[3L]]
scores <- fastEmbedR::pca(x, ncomp = 30L, backend = "cpu",
    n.cores = 1L, seed = 4L, massive = "off")$scores
if (!inherits(scores, "float32") ||
    nrow(scores) != 1440L || ncol(scores) != 30L)
    stop("Shared preprocessing is not the reviewed float32 rank-30 PCA.")
preprocess_seconds <- unname(proc.time()[[3L]] - started)
started <- proc.time()[[3L]]
input_double <- float::dbl(scores)
if (!is.matrix(input_double) || !is.double(input_double) ||
    !identical(dim(input_double), c(1440L, 30L)))
    stop("Comparator input conversion failed.")
conversion_seconds <- unname(proc.time()[[3L]] - started)
Sys.setenv(RETICULATE_PYTHON = "/opt/conda/bin/python")
reticulate::use_python("/opt/conda/bin/python", required = TRUE)
started <- proc.time()[[3L]]
python_input <- reticulate::r_to_py(input_double, convert = FALSE)
python_conversion_seconds <- unname(proc.time()[[3L]] - started)
module <- reticulate::import(
    if (method == "opentsne") "openTSNE" else "umap",
    convert = FALSE)
seed <- 4L
set.seed(seed)
fit_started <- proc.time()[[3L]]
fit <- switch(method,
    opentsne = {
        model <- module$TSNE(n_components = 2L, perplexity = 30L,
            n_iter = 300L, initialization = "pca",
            random_state = seed, n_jobs = 4L, verbose = FALSE)
        model$fit(python_input)
    },
    umaplearn = {
        model <- module$UMAP(n_neighbors = 30L, n_components = 2L,
            n_epochs = 500L, init = "spectral",
            random_state = seed, n_jobs = 4L, verbose = FALSE)
        model$fit_transform(python_input)
    })
fit_seconds <- unname(proc.time()[[3L]] - fit_started)
layout <- reticulate::py_to_r(fit)
if (!is.matrix(layout)) layout <- as.matrix(layout)
if (!identical(dim(layout), c(1440L, 2L)) ||
    any(!is.finite(layout)))
    stop("Comparator output is nonfinite or has the wrong shape.")
quality_started <- proc.time()[[3L]]
score <- fastEmbedR::evaluate_embedding(scores, layout,
    labels = labels, k = 15L, primary_k = 15L,
    sample_size_for_global_metrics = 600L,
    sample_size_for_local_metrics = 600L,
    n.cores = 1L, seed = seed)
quality_seconds <- unname(proc.time()[[3L]] - quality_started)
if (!is.finite(score$trustworthiness) ||
    !is.finite(score$label_knn_accuracy))
    stop("Comparator quality scoring failed.")
write_started <- proc.time()[[3L]]
saveRDS(layout, file.path(out, "layout.rds"), compress = "xz")
write_seconds <- unname(proc.time()[[3L]] - write_started)
version <- switch(method,
    opentsne = reticulate::py_to_r(
        reticulate::import("importlib.metadata", convert = FALSE)$
            version("openTSNE")),
    umaplearn = reticulate::py_to_r(
        reticulate::import("importlib.metadata", convert = FALSE)$
            version("umap-learn")))
metrics <- list(dataset = "COIL20", method = method,
    backend = "cpu", requested_cores = 4L, seed = seed,
    dimensions = 2L, n_rows = nrow(x), n_columns = ncol(x),
    preprocessing_rank = 30L,
    input_sha256 = input_sha,
    source_precision = "float32",
    comparator_precision = "double",
    package_commit = "535d071849945db3fa550d3c50f80633b91748cc",
    worker_sha256 = worker_sha, image_sha256 = image_sha,
    slurm_job_id = Sys.getenv("SLURM_JOB_ID"),
    slurm_array_task_id = Sys.getenv("SLURM_ARRAY_TASK_ID"),
    comparator_version = version,
    parallel_note = if (method == "umaplearn")
        "random_state_may_force_serial_numba" else
        "four_requested_jobs",
    load_seconds = load_seconds,
    preprocess_seconds = preprocess_seconds,
    conversion_seconds = conversion_seconds,
    python_conversion_seconds = python_conversion_seconds,
    fit_seconds = fit_seconds,
    quality_seconds = quality_seconds,
    write_seconds = write_seconds,
    quality = list(trustworthiness = score$trustworthiness,
        label_accuracy = score$label_knn_accuracy),
    output_file = "layout.rds")
jsonlite::write_json(metrics, file.path(out, "metrics.json"),
    auto_unbox = TRUE, pretty = TRUE, null = "null")
