#!/usr/bin/env Rscript
package_root <- commandArgs(trailingOnly = TRUE)[[1L]]
.libPaths(c(file.path(package_root, "library"), .libPaths()))
stopifnot(startsWith(find.package("fastEmbedR"),
    file.path(package_root, "library")))
suppressPackageStartupMessages(library(fastEmbedR))

make_fixture <- function(root) {
    n <- 32L
    prefix <- file.path(root, "knn")
    ids <- outer(seq_len(n), 1:3,
        function(i, j) (i + j - 1L) %% n + 1L)
    distances <- matrix(rep(c(0.2, 0.5, 0.9), n),
        nrow = n, byrow = TRUE)
    writeBin(as.integer(t(ids)),
        paste0(prefix, ".indices.u32"),
        size = 4L, endian = "little")
    writeBin(as.vector(t(distances)),
        paste0(prefix, ".distances.f32"),
        size = 4L, endian = "little")
    graph <- massive_tsne_affinities(
        massive_knn_graph(prefix, n, 3L), 3,
        file.path(root, "affinity"), memory_limit = "64MB")
    initial <- matrix(seq_len(n * 2L) / 10000, nrow = n)
    init_path <- file.path(root, "init.f32")
    writeBin(as.numeric(t(initial)), init_path,
        size = 4L, endian = "little")
    start <- massive_matrix(init_path, n, 2L)
    list(graph = graph, start = start, n = n)
}

check <- function() {
    args <- commandArgs(trailingOnly = TRUE)
    stopifnot(length(args) == 1L, dir.exists(args[[1L]]))
    root <- tempfile("cuda-tsne-checkpoint-", tmpdir = args[[1L]])
    dir.create(root)
    on.exit(unlink(root, recursive = TRUE), add = TRUE)
    fixture <- make_fixture(root)
    graph <- fixture$graph
    start <- fixture$start
    n <- fixture$n
    output <- file.path(root, "resumed.f32")
    plan <- fastEmbedR:::massive_tsne_optimize_plan(
        graph, start, output, 2L, 3L, 12, 1, 1,
        0.8, 0.8, 0.01, Inf, "1GB", "cuda", 1L,
        devices = 0L)
    saved <- fastEmbedR:::massive_tsne_checkpoint_prepare(
        plan, TRUE, FALSE, 2L)
    interrupt <- function(iteration, snapshot, elapsed_seconds) {
        saved$progress(iteration, snapshot, elapsed_seconds)
        stop("forced interruption")
    }
    call <- fastEmbedR:::massive_tsne_optimize_cuda_cpp
    interrupted <- tryCatch(call(graph$offsets_path,
        graph$indices_path, graph$weights_path, graph$access,
        start$path, output, n, 2L, 2L, 3L, 12, 1, 1,
        FALSE, 0.8, 0.8, 0.01, Inf, 0L, "", 2L,
        interrupt, plan$edge_capacity, 0L),
        error = conditionMessage)
    stopifnot(identical(interrupted, "forced interruption"),
        file.exists(paste0(output, ".checkpoint.rds")))
    fit <- massive_tsne_optimize(graph, start, output,
        early_exaggeration_iter = 2L, n_iter = 3L,
        learning_rate = 1, memory_limit = "1GB",
        backend = "cuda", devices = 0L,
        checkpoint = TRUE, resume = TRUE,
        checkpoint_every = 2L)
    coordinates <- massive_read_rows(fit, 1L, n)
    stopifnot(identical(dim(coordinates), c(n, 2L)),
        all(is.finite(coordinates)),
        identical(fit$parameters$resumed_from_iteration, 2L),
        !file.exists(paste0(output, ".checkpoint.rds")))
    cat("CUDA_2D_CHECKPOINT_RESUME_PASS rows", n,
        "layout_md5", unname(tools::md5sum(output)), "\n")
}
check()
