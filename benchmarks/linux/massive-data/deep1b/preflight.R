#!/usr/bin/env Rscript

library(fastEmbedR)
if (utils::packageVersion("faissR") < package_version("0.99.52")) {
    stop("Deep/Turing HNSW requires faissR 0.99.52 or newer.")
}
probe <- float::fl(matrix(seq_len(24L) / 11, nrow = 6L))
index <- fastEmbedR:::faissr_hnsw_index_build_cpp(
    probe, 6L, 4L, 2L, 1L)
found <- fastEmbedR:::faissr_hnsw_index_search_cpp(
    index$pointer, probe[1:2, , drop = FALSE], 3L, 6L, 1L)
if (!identical(found$method, "faissr_hnsw_query_reused") ||
    !isTRUE(found$index_reused)) {
    stop("Persistent faissR HNSW bridge is unavailable.")
}
cat("Persistent faissR HNSW: PASS\n")
check_view_checkpoint <- function() {
    input <- tempfile(fileext = ".fbin")
    on.exit(unlink(input))
    values <- matrix(seq_len(48L) / 11, nrow = 12L)
    connection <- file(input, "wb")
    writeBin(as.integer(dim(values)), connection, size = 4L,
        endian = "little")
    writeBin(as.vector(t(values)), connection, size = 4L,
        endian = "little")
    close(connection)
    source <- massive_matrix(input)
    view <- fastEmbedR:::massive_matrix_rows(source, 2L, 10L)
    fastEmbedR:::massive_full_knn_controls(view, 2L, "cpu",
        "hnsw_sharded", 0L, 100L, TRUE, FALSE, "original", 0L)
    cat("Checkpointed file-backed row view: PASS\n")
}
check_view_checkpoint()
