#!/usr/bin/env Rscript
suppressPackageStartupMessages(library(fastEmbedR))

probe <- function() {
    args <- commandArgs(trailingOnly = TRUE)
    stopifnot(length(args) == 1L, dir.exists(args[[1L]]))
    root <- tempfile("metal-tsne-usps2d-", tmpdir = args[[1L]])
    dir.create(root)
    on.exit(unlink(root, recursive = TRUE), add = TRUE)
    input <- paste0(
        "/Users/silvanopiazza/Documents/Stefano/data/data/",
        "USPS/USPS_float32.RData")
    data <- new.env(parent = emptyenv())
    load(input, envir = data)
    x <- float::dbl(data$dataset$data)
    labels <- as.integer(data$dataset$labels)
    stopifnot(identical(dim(x), c(11000L, 256L)),
        length(labels) == 11000L)
    knn <- precompute_knn(x, k = 90L, backend = "metal")
    stopifnot(identical(knn$method, "native_metal_exact"))
    prefix <- file.path(root, "knn")
    writeBin(as.integer(t(knn$indices)),
        paste0(prefix, ".indices.u32"),
        size = 4L, endian = "little")
    writeBin(as.vector(t(knn$distances)),
        paste0(prefix, ".distances.f32"),
        size = 4L, endian = "little")
    source <- massive_knn_graph(prefix, 11000L, 90L)
    graph <- massive_tsne_affinities(source, perplexity = 30,
        output = file.path(root, "affinity"),
        memory_limit = "256MB")
    set.seed(17L)
    initial <- matrix(rnorm(11000L * 2L, sd = 0.0001),
        11000L, 2L)
    init_path <- file.path(root, "init.f32")
    writeBin(as.numeric(t(initial)), init_path,
        size = 4L, endian = "little")
    start <- massive_matrix(init_path, 11000L, 2L)
    cat("input_md5", unname(tools::md5sum(input)),
        "edges", graph$n_edges, "graph_md5",
        paste(unname(tools::md5sum(c(graph$offsets_path,
            graph$indices_path, graph$weights_path,
            init_path))), collapse = ","), "\n")
    metal_md5 <- NULL
    for (method in c("cpu", "mmap1", "mmap2", "stream")) {
        output <- file.path(root, paste0(method, ".f32"))
        backend <- if (method == "cpu") "cpu" else "metal"
        mode <- if (startsWith(method, "mmap")) "mmap" else
            if (method == "stream") "stream" else "auto"
        elapsed <- system.time({
            fit <- massive_tsne_optimize(graph, start, output,
                early_exaggeration_iter = 50L, n_iter = 200L,
                learning_rate = "auto", memory_limit = "2GB",
                backend = backend, n.cores = 1L,
                graph_access = mode,
                edge_chunk_capacity = if (backend == "metal")
                    131072L else 8388608L)
        })[["elapsed"]]
        layout <- massive_read_rows(fit, 1L, 11000L)
        stopifnot(identical(dim(layout), c(11000L, 2L)),
            all(is.finite(layout)))
        sample_rows <- seq.int(1L, 11000L, by = 11L)
        silhouette <- as.numeric(summary(cluster::silhouette(
            labels[sample_rows], stats::dist(layout[
                sample_rows, , drop = FALSE])))$avg.width)
        checksum <- unname(tools::md5sum(output))
        cat("fit", method, "seconds", elapsed,
            "silhouette", silhouette, "backend", fit$backend,
            "fft_grid", fit$fft_grid_size,
            "layout_md5", checksum, "\n")
        if (backend == "metal") {
            if (is.null(metal_md5)) metal_md5 <- checksum
            else stopifnot(identical(checksum, metal_md5))
        }
    }
}
probe()
