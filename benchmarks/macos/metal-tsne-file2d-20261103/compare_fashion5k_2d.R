#!/usr/bin/env Rscript
suppressPackageStartupMessages(library(fastEmbedR))

score_layout <- function(layout, labels, high) {
    sample_rows <- seq.int(1L, nrow(layout), by = 5L)
    silhouette <- as.numeric(summary(cluster::silhouette(
        labels[sample_rows], stats::dist(layout[
            sample_rows, , drop = FALSE])))$avg.width)
    low <- fastEmbedR:::native_exact_knn_cpp(
        layout, 30L, 1L, "euclidean", 0.99)
    overlap <- vapply(seq_len(nrow(layout)), function(row) {
        length(intersect(high[row, 1:30],
            low$indices[row, ])) / 30
    }, 0.0)
    c(silhouette = silhouette, preserve30 = mean(overlap))
}

probe <- function() {
    args <- commandArgs(trailingOnly = TRUE)
    stopifnot(length(args) %in% 1:2, dir.exists(args[[1L]]))
    seed <- if (length(args) == 2L) as.integer(args[[2L]]) else 17L
    stopifnot(!is.na(seed), seed > 0L)
    root <- tempfile("metal-tsne-file2d-", tmpdir = args[[1L]])
    dir.create(root)
    on.exit(unlink(root, recursive = TRUE), add = TRUE)
    setTimeLimit(elapsed = 300, transient = FALSE)
    input <- paste0(
        "/Users/silvanopiazza/Documents/Stefano/data/data/",
        "FashionMNIST_n5000/FashionMNIST_n5000_float32.RData")
    data <- new.env(parent = emptyenv())
    load(input, envir = data)
    x <- float::dbl(data$dataset$data)
    labels <- as.integer(data$dataset$labels)
    stopifnot(identical(dim(x), c(5000L, 784L)),
        length(labels) == 5000L)
    knn <- precompute_knn(x, k = 90L, backend = "metal")
    stopifnot(identical(knn$method, "native_metal_exact"))
    prefix <- file.path(root, "knn")
    writeBin(as.integer(t(knn$indices)),
        paste0(prefix, ".indices.u32"),
        size = 4L, endian = "little")
    writeBin(as.vector(t(knn$distances)),
        paste0(prefix, ".distances.f32"),
        size = 4L, endian = "little")
    source <- massive_knn_graph(prefix, 5000L, 90L)
    graph <- massive_tsne_affinities(source, perplexity = 30,
        output = file.path(root, "affinity"),
        memory_limit = "256MB")
    set.seed(seed)
    initial <- matrix(rnorm(5000L * 2L, sd = 0.0001),
        5000L, 2L)
    init_path <- file.path(root, "init.f32")
    writeBin(as.numeric(t(initial)), init_path,
        size = 4L, endian = "little")
    start <- massive_matrix(init_path, 5000L, 2L)
    cat("input_md5", unname(tools::md5sum(input)),
        "seed", seed, "edges", graph$n_edges, "graph_md5",
        paste(unname(tools::md5sum(c(graph$offsets_path,
            graph$indices_path, graph$weights_path,
            init_path))), collapse = ","), "\n")
    for (method in c("cpu", "mmap1", "mmap2", "mmap3",
            "stream1", "stream2")) {
        output <- file.path(root, paste0(method, ".f32"))
        backend <- if (method == "cpu") "cpu" else "metal"
        mode <- if (startsWith(method, "mmap")) "mmap" else
            if (startsWith(method, "stream")) "stream" else "auto"
        elapsed <- system.time({
            fit <- massive_tsne_optimize(graph, start, output,
                early_exaggeration_iter = 50L, n_iter = 200L,
                learning_rate = "auto", memory_limit = "2GB",
                backend = backend, n.cores = 1L,
                graph_access = mode,
                edge_chunk_capacity = if (backend == "metal")
                    131072L else 8388608L)
        })[["elapsed"]]
        layout <- massive_read_rows(fit, 1L, 5000L)
        stopifnot(identical(dim(layout), c(5000L, 2L)),
            all(is.finite(layout)))
        quality <- score_layout(layout, labels, knn$indices)
        cat("fit", method, "seconds", elapsed,
            "silhouette", quality[["silhouette"]],
            "preserve30", quality[["preserve30"]],
            "backend", fit$backend,
            "fft_grid", fit$fft_grid_size,
            "layout_md5", unname(tools::md5sum(output)), "\n")
    }
}
probe()
