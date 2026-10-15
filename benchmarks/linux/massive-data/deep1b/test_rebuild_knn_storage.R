#!/usr/bin/env Rscript

suppressPackageStartupMessages(library(fastEmbedR))
run_storage_test <- function() {
    root <- tempfile("rebuild_knn_storage_")
    dir.create(root)
    on.exit(unlink(root, recursive = TRUE), add = TRUE)
    set.seed(4L)
    rows <- 300L
    k <- 10L
    source <- massive_matrix(matrix(rnorm(rows * 8L), rows, 8L))
    prefix <- file.path(root, "knn")
    build <- function() {
        massive_full_knn_graph(source, k, prefix,
            memory_limit = "512MB", chunk_rows = 100L,
            reference_chunk_rows = 150L, audit_rows = 4L
        )
    }
    knn <- build()
    regular_tsne <- massive_tsne_affinities(knn, 10,
        file.path(root, "regular_tsne"), "64MB",
        sort_method = "bucketed"
    )
    regular_umap <- massive_umap_fuzzy_graph(knn,
        file.path(root, "regular_umap"), "64MB",
        sort_method = "bucketed", consume_knn = TRUE
    )
    knn <- build()
    first_recall <- knn$observed_recall
    compact_tsne <- massive_tsne_affinities(knn, 10,
        file.path(root, "compact_tsne"), "64MB",
        sort_method = "bucketed", consume_knn = TRUE
    )
    paths <- paste0(prefix, c(".indices.u32", ".distances.f32"))
    stopifnot(!any(file.exists(paths)))
    knn <- build()
    stopifnot(
        all(file.exists(paths)), knn$n_vertices == rows,
        knn$k == k, identical(knn$observed_recall, first_recall)
    )
    compact_umap <- massive_umap_fuzzy_graph(knn,
        file.path(root, "compact_umap"), "64MB",
        sort_method = "bucketed", consume_knn = TRUE
    )
    cat("t-SNE graph-stage peaks:",
        regular_tsne$peak_graph_stage_bytes,
        compact_tsne$peak_graph_stage_bytes, "\n")
    stopifnot(!any(file.exists(paths)))
    suffix <- c(".offsets.u64", ".indices.u32", ".weights.f32")
    same_graph <- function(a, b) {
        identical(
            unname(tools::md5sum(paste0(file.path(root, a), suffix))),
            unname(tools::md5sum(paste0(file.path(root, b), suffix)))
        )
    }
    stopifnot(
        same_graph("regular_tsne", "compact_tsne"),
        same_graph("regular_umap", "compact_umap"),
        regular_tsne$consumed_knn_bytes == 0,
        compact_tsne$consumed_knn_bytes == 8 * rows * k,
        regular_umap$consumed_knn_bytes == 8 * rows * k,
        compact_umap$consumed_knn_bytes == 8 * rows * k,
        regular_tsne$peak_graph_stage_bytes >
            compact_tsne$peak_graph_stage_bytes,
        regular_tsne$peak_graph_stage_bytes -
            compact_tsne$peak_graph_stage_bytes <= 8 * rows * k
    )
    init_path <- file.path(root, "init.f32")
    stream <- file(init_path, "wb")
    writeBin(as.vector(t(matrix(rnorm(rows * 2L) * 1e-4,
        rows, 2L))), stream, size = 4L, endian = "little")
    close(stream)
    init <- massive_matrix(init_path, rows, 2L)
    fit_tsne <- function(graph, name) massive_tsne_optimize(
        graph, init, file.path(root, paste0(name, ".f32")),
        early_exaggeration_iter = 2L, n_iter = 5L,
        n.cores = 1L)
    fit_umap <- function(graph, name) massive_umap_optimize(
        graph, init, file.path(root, paste0(name, ".f32")),
        n_epochs = 5L, seed = 4L)
    fit_tsne(regular_tsne, "regular_tsne_layout")
    fit_tsne(compact_tsne, "compact_tsne_layout")
    fit_umap(regular_umap, "regular_umap_layout")
    fit_umap(compact_umap, "compact_umap_layout")
    same_layout <- function(method) identical(
        unname(tools::md5sum(file.path(root,
            paste0("regular_", method, "_layout.f32")))),
        unname(tools::md5sum(file.path(root,
            paste0("compact_", method, "_layout.f32")))))
    stopifnot(same_layout("tsne"), same_layout("umap"))
    cat("Combined KNN consume/rebuild storage: PASS\n")
}
run_storage_test()
