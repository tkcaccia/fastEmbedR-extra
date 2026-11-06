#!/usr/bin/env Rscript
suppressPackageStartupMessages(library(fastEmbedR))

arguments <- commandArgs(trailingOnly = TRUE)
stopifnot(length(arguments) == 1L)
case <- arguments[[1L]]
stopifnot(case %in% c("resident2d", "resident3d",
    "umap2d", "umap3d", "pca", "file3d"))
stopifnot(fastEmbedR:::massive_cuda_device_count_cpp() == 2L)
stopifnot(fastEmbedR:::massive_nccl_available_cpp())

fixture <- function(n = 64L) {
    ids <- outer(seq_len(n), 1:3,
        function(i, j) (i + j - 1L) %% n + 1L)
    distances <- matrix(rep(c(0.2, 0.5, 0.9), n),
        nrow = n, byrow = TRUE)
    list(ids = ids, distances = distances, n = n)
}

resident <- function(dimensions) {
    data <- fixture()
    initial <- matrix(seq_len(data$n * dimensions) / 10000,
        nrow = data$n)
    args <- list(data$ids, data$distances, perplexity = 3,
        n_components = dimensions, Y_init = initial,
        backend = "cuda", early_exaggeration_iter = 2L,
        n_iter = 3L, learning_rate = 1, auto_config = FALSE,
        n.cores = 2L)
    one <- do.call(tsne_knn, args)
    two <- do.call(tsne_knn, c(args,
        list(devices = c(0L, 1L))))
    cfg <- attr(two, "fastEmbedR_config")
    stopifnot(identical(cfg$optimizer,
        "cuda_resident_coordinated_nccl"),
        identical(cfg$gpu_devices, c(0L, 1L)),
        length(cfg$gpu_identity) == 2L,
        identical(cfg$input_storage, "resident_knn"),
        identical(cfg$layout_storage, "resident"),
        all(cfg$per_device_attraction_edges > 0L),
        identical(dim(two), c(data$n, dimensions)),
        all(is.finite(two)), all(apply(two, 2L, sd) > 0))
    delta <- max(abs(as.matrix(two) - as.matrix(one)))
    stopifnot(is.finite(delta), delta < 0.02)
    cat("PASS", case, "max_delta", format(delta, digits = 8),
        "edges", paste(cfg$per_device_attraction_edges,
            collapse = ","), "\n")
}

umap_resident <- function(dimensions) {
    data <- fixture()
    args <- list(data$ids, data$distances,
        n_components = dimensions, backend = "cuda",
        n_epochs = 10L, seed = 7L)
    one <- do.call(fastEmbedR:::fast_knn_umap_core, args)
    two <- do.call(fastEmbedR:::fast_knn_umap_core, c(args,
        list(devices = c(0L, 1L))))
    cfg <- attr(two, "fastEmbedR_config")
    coordinates <- matrix(as.numeric(two), nrow = data$n)
    stopifnot(identical(cfg$optimizer,
        "cuda_resident_umap_coordinated_nccl"),
        identical(cfg$gpu_devices, c(0L, 1L)),
        length(cfg$gpu_identity) == 2L,
        identical(cfg$input_storage, "resident_knn"),
        identical(cfg$layout_storage, "resident"),
        all(cfg$per_device_edge_visits > 0),
        identical(dim(coordinates), c(data$n, dimensions)),
        all(is.finite(coordinates)),
        all(apply(coordinates, 2L, sd) > 0),
        all(is.finite(as.numeric(one))))
    cat("PASS", case, "edge_visits",
        paste(cfg$per_device_edge_visits, collapse = ","),
        "delta_scale", cfg$delta_scale, "\n")
}

pca_resident <- function() {
    set.seed(41)
    x <- matrix(rnorm(1024L), nrow = 64L)
    fit <- pca(x, ncomp = 3L, backend = "cuda",
        devices = c(0L, 1L), scale = TRUE,
        xtest = x[1:2, , drop = FALSE])
    reference <- sweep(x, 2L, fit$center)
    reference <- sweep(reference, 2L, fit$scale, "/")
    expected <- reference %*% fit$loadings
    test_scores <- expected[1:2, , drop = FALSE]
    delta <- max(abs(unname(fit$scores) - unname(expected)))
    test_delta <- max(abs(unname(fit$scores_test) -
        unname(test_scores)))
    stopifnot(identical(fit$gpu_devices, c(0L, 1L)),
        length(fit$gpu_identity) == 2L,
        identical(fit$engine,
            "native_cuda_multigpu_covariance"),
        identical(fit$test_projection_devices, c(0L, 1L)),
        all(is.finite(fit$scores)),
        all(fit$singular_values > 0),
        is.finite(delta), delta < 0.001,
        is.finite(test_delta), test_delta < 0.001)
    cat("PASS pca score_delta", format(delta, digits = 8),
        "test_delta", format(test_delta, digits = 8), "\n")
}

file_graph <- function(root, data, dimensions) {
    prefix <- file.path(root, "knn")
    writeBin(as.integer(t(data$ids)),
        paste0(prefix, ".indices.u32"),
        size = 4L, endian = "little")
    writeBin(as.vector(t(data$distances)),
        paste0(prefix, ".distances.f32"),
        size = 4L, endian = "little")
    graph <- massive_tsne_affinities(
        massive_knn_graph(prefix, data$n, 3L), 3,
        file.path(root, "affinity"), memory_limit = "64MB")
    initial <- matrix(seq_len(data$n * dimensions) / 10000,
        nrow = data$n)
    path <- file.path(root, "init.f32")
    writeBin(as.vector(t(initial)), path,
        size = 4L, endian = "little")
    list(graph = graph, init = massive_matrix(path,
        data$n, dimensions))
}

file_case <- function() {
    root <- tempfile("multi3d-")
    dir.create(root)
    on.exit(unlink(root, recursive = TRUE))
    data <- fixture(17L)
    pair <- file_graph(root, data, 3L)
    args <- list(pair$graph, pair$init,
        early_exaggeration_iter = 2L, n_iter = 3L,
        learning_rate = 1, memory_limit = "1GB",
        backend = "cuda")
    one <- do.call(massive_tsne_optimize, c(args,
        list(output = file.path(root, "one.f32"), devices = 0L)))
    two <- do.call(massive_tsne_optimize, c(args,
        list(output = file.path(root, "two.f32"),
            devices = c(0L, 1L))))
    observed <- massive_read_rows(two, 1L, data$n)
    expected <- massive_read_rows(one, 1L, data$n)
    stopifnot(identical(dim(observed), c(data$n, 3L)),
        all(is.finite(observed)),
        identical(two$backend,
            "native_cuda_fft_graph_coordinated_nccl"),
        all(two$resources$per_device_attraction_edges > 0))
    delta <- max(abs(observed - expected))
    stopifnot(is.finite(delta), delta < 0.001)
    path <- file.path(root, "resumed.f32")
    plan <- fastEmbedR:::massive_tsne_optimize_plan(
        pair$graph, pair$init, path, 2L, 3L, 12, 1, 1,
        0.8, 0.8, 0.01, Inf, "1GB", "cuda", 1L,
        devices = c(0L, 1L))
    saved <- fastEmbedR:::massive_tsne_checkpoint_prepare(
        plan, TRUE, FALSE, 2L)
    interrupt <- function(iteration, snapshot, elapsed) {
        saved$progress(iteration, snapshot, elapsed)
        stop("forced interruption")
    }
    interrupted <- tryCatch(
        fastEmbedR:::massive_tsne_optimize_cuda_cpp(
            pair$graph$offsets_path, pair$graph$indices_path,
            pair$graph$weights_path, pair$graph$access,
            pair$init$path, path, data$n, 3L, 2L, 3L,
            12, 1, 1, FALSE, 0.8, 0.8, 0.01, Inf,
            0L, "", 2L, interrupt, plan$edge_capacity,
            c(0L, 1L)), error = conditionMessage)
    stopifnot(identical(interrupted, "forced interruption"))
    resumed <- do.call(massive_tsne_optimize, c(args,
        list(output = path, devices = c(0L, 1L),
            checkpoint = TRUE, resume = TRUE,
            checkpoint_every = 2L)))
    resumed_delta <- max(abs(massive_read_rows(
        resumed, 1L, data$n) - observed))
    stopifnot(is.finite(resumed_delta), resumed_delta < 0.001)
    cat("PASS file3d max_delta", format(delta, digits = 8),
        "resume_delta", format(resumed_delta, digits = 8), "\n")
}

if (case == "resident2d") resident(2L)
if (case == "resident3d") resident(3L)
if (case == "umap2d") umap_resident(2L)
if (case == "umap3d") umap_resident(3L)
if (case == "pca") pca_resident()
if (case == "file3d") file_case()
