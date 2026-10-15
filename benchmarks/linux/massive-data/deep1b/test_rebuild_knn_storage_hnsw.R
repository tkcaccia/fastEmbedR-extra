#!/usr/bin/env Rscript

suppressPackageStartupMessages(library(fastEmbedR))
run <- function() {
    set.seed(17L)
    rows <- 6000L
    k <- 30L
    root <- tempfile("rebuild_knn_hnsw_")
    dir.create(root)
    on.exit(unlink(root, recursive = TRUE), add = TRUE)
    input <- file.path(root, "input.f32")
    stream <- file(input, "wb")
    writeBin(as.vector(t(matrix(rnorm(rows * 32L), rows, 32L))),
        stream, size = 4L, endian = "little")
    close(stream)
    source <- massive_matrix(input, rows, 32L)
    knn <- massive_full_knn_graph(source, k,
        file.path(root, "knn"), backend = "cpu",
        method = "hnsw_sharded", n.cores = 1L,
        memory_limit = "1GB", chunk_rows = 1000L,
        reference_chunk_rows = 3000L, audit_rows = 16L)
    stopifnot(knn$method == "faissr_cpu_hnsw_sharded")
    regular <- massive_tsne_affinities(knn, 30,
        file.path(root, "regular"), "128MB",
        sort_method = "bucketed")
    compact <- massive_tsne_affinities(knn, 30,
        file.path(root, "compact"), "128MB",
        sort_method = "bucketed", consume_knn = TRUE)
    suffix <- c(".offsets.u64", ".indices.u32", ".weights.f32")
    hashes <- function(name) unname(tools::md5sum(paste0(
        file.path(root, name), suffix)))
    saved <- regular$peak_graph_stage_bytes -
        compact$peak_graph_stage_bytes
    stopifnot(identical(hashes("regular"), hashes("compact")),
        saved == 8 * rows * k,
        !file.exists(file.path(root, "knn.indices.u32")),
        !file.exists(file.path(root, "knn.distances.f32")))
    cat("rows=", rows, " k=", k,
        " recall=", knn$observed_recall,
        " regular_peak_bytes=", regular$peak_graph_stage_bytes,
        " compact_peak_bytes=", compact$peak_graph_stage_bytes,
        " saved_bytes=", saved, "\n", sep = "")
}
run()
