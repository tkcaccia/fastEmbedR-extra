#!/usr/bin/env Rscript
args <- commandArgs(trailingOnly = TRUE)
if (length(args) != 2L) stop("Need METHOD and RESULT_DIR.")
method <- args[[1L]]
out <- args[[2L]]
if (!method %in% c("rtsne", "fitsne") ||
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
seed <- 4L
set.seed(seed)
fit_started <- proc.time()[[3L]]
fit <- switch(method,
    rtsne = Rtsne::Rtsne(input_double, dims = 2L,
        perplexity = 30, max_iter = 550L, pca = FALSE,
        check_duplicates = FALSE, theta = 0.5,
        stop_lying_iter = 250L, mom_switch_iter = 250L,
        eta = 200, num_threads = 4L, verbose = FALSE),
    fitsne = {
        wrapper_env <- new.env(parent = globalenv())
        sys.source("/opt/fit-sne/bin/fast_tsne.R",
            envir = wrapper_env, chdir = TRUE)
        if (!exists("fftRtsne", envir = wrapper_env,
                inherits = FALSE))
            stop("FIt-SNE wrapper lacks fftRtsne().")
        wrapper <- get("fftRtsne", envir = wrapper_env,
            inherits = FALSE)
        controls <- list(X = input_double, dims = 2L,
            perplexity = 30, max_iter = 550L,
            rand_seed = seed, theta = 0.5, nthreads = 4L,
            stop_early_exag_iter = 250L,
            mom_switch_iter = 250L,
            fast_tsne_path = "/opt/fit-sne/bin/fast_tsne",
            verbose = FALSE)
        names_available <- names(formals(wrapper))
        if (!all(c("X", "dims", "perplexity", "max_iter",
                "stop_early_exag_iter", "mom_switch_iter") %in%
                names_available))
            stop("FIt-SNE wrapper cannot honor the parameter contract.")
        do.call(wrapper, controls[names(controls) %in%
            names_available])
    })
fit_seconds <- unname(proc.time()[[3L]] - fit_started)
layout <- switch(method,
    rtsne = fit$Y, fitsne = fit)
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
    rtsne = as.character(packageVersion("Rtsne")),
    fitsne = "bundled_fftRtsne_wrapper")
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
    early_exaggeration_iterations = 250L,
    normal_iterations = 300L,
    total_iterations = 550L,
    load_seconds = load_seconds,
    preprocess_seconds = preprocess_seconds,
    conversion_seconds = conversion_seconds,
    fit_seconds = fit_seconds,
    quality_seconds = quality_seconds,
    write_seconds = write_seconds,
    quality = list(trustworthiness = score$trustworthiness,
        label_accuracy = score$label_knn_accuracy),
    output_file = "layout.rds")
jsonlite::write_json(metrics, file.path(out, "metrics.json"),
    auto_unbox = TRUE, pretty = TRUE, null = "null")
