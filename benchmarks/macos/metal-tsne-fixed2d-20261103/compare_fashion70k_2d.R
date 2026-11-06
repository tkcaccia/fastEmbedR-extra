#!/usr/bin/env Rscript
suppressPackageStartupMessages(library(fastEmbedR))

probe <- function() {
    args <- commandArgs(trailingOnly = TRUE)
    stopifnot(length(args) == 1L, dir.exists(args[[1L]]))
    root <- tempfile("metal-tsne-70k2d-", tmpdir = args[[1L]])
    dir.create(root)
    on.exit(unlink(root, recursive = TRUE), add = TRUE)
    setTimeLimit(elapsed = 600, transient = FALSE)
    prefix <- paste0(
        "/Users/silvanopiazza/Documents/Stefano/data/results/",
        "fashion70k-metal-exact-knn-v1/knn")
    knn <- massive_knn_graph(prefix, 70000L, 30L)
    graph <- massive_tsne_affinities(knn, perplexity = 10,
        output = file.path(root, "affinity"),
        memory_limit = "256MB")
    set.seed(17)
    initial <- matrix(rnorm(70000L * 2L, sd = 0.0001),
        70000L, 2L)
    init_path <- file.path(root, "init.f32")
    writeBin(as.numeric(t(initial)), init_path,
        size = 4L, endian = "little")
    start <- massive_matrix(init_path, 70000L, 2L)
    cat("graph_md5", paste(unname(tools::md5sum(c(
        graph$offsets_path, graph$indices_path,
        graph$weights_path, init_path))), collapse = ","),
        "edges", graph$n_edges, "\n")
    data <- new.env(parent = emptyenv())
    load(paste0(
        "/Users/silvanopiazza/Documents/Stefano/data/data/",
        "FashionMNIST/FashionMNIST_float32.RData"),
        envir = data)
    labels <- as.integer(data$dataset$labels)
    stopifnot(length(labels) == 70000L)
    sample_rows <- seq.int(1L, 70000L, by = 70L)
    metal_md5 <- NULL
    for (method in c("cpu", "mmap", "stream")) {
        output <- file.path(root, paste0(method, ".f32"))
        backend <- if (method == "cpu") "cpu" else "metal"
        mode <- if (backend == "metal") method else "auto"
        elapsed <- system.time({
            fit <- massive_tsne_optimize(graph, start, output,
                early_exaggeration_iter = 50L, n_iter = 200L,
                learning_rate = "auto", memory_limit = "4GB",
                backend = backend, n.cores = 1L,
                graph_access = mode,
                edge_chunk_capacity = if (backend == "metal")
                    262144L else 8388608L)
        })[["elapsed"]]
        layout <- massive_read_rows(fit, 1L, 70000L)
        stopifnot(identical(dim(layout), c(70000L, 2L)),
            all(is.finite(layout)))
        score <- as.numeric(summary(cluster::silhouette(
            labels[sample_rows], stats::dist(layout[
                sample_rows, , drop = FALSE])))$avg.width)
        checksum <- unname(tools::md5sum(output))
        cat("fit", method, "seconds", elapsed,
            "silhouette", score, "backend", fit$backend,
            "fft_grid", fit$fft_grid_size,
            "layout_md5", checksum, "\n")
        if (backend == "metal") {
            if (is.null(metal_md5)) metal_md5 <- checksum
            else stopifnot(identical(checksum, metal_md5))
        }
    }
}
probe()
