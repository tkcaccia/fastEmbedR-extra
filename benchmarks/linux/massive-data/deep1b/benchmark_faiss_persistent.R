#!/usr/bin/env Rscript

args <- commandArgs(trailingOnly = TRUE)
if (length(args) < 4L || length(args) > 6L) {
    stop(paste("Usage: benchmark_faiss_persistent.R INPUT ROWS",
        "BATCH EF_SEARCH [M] [EF_CONSTRUCTION]"))
}
libs <- c(Sys.getenv("FASTEMBEDR_TEST_LIB"),
    Sys.getenv("FAISSR_TEST_LIB"))
.libPaths(c(libs[nzchar(libs)], .libPaths()))
if (!requireNamespace("float", quietly = TRUE)) {
    stop("The float package is required for the persistent FAISS test.")
}
input <- fastEmbedR::massive_matrix(args[[1L]])
rows <- as.integer(args[[2L]])
batch <- as.integer(args[[3L]])
ef_search <- as.integer(args[[4L]])
m <- if (length(args) >= 5L) as.integer(args[[5L]]) else 12L
ef_construction <- if (length(args) >= 6L) {
    as.integer(args[[6L]])
} else 80L
if (anyNA(c(rows, batch, ef_search)) || rows < 20000L ||
    rows > input$nrow || batch < 1L || ef_search < 30L) {
    stop("Invalid benchmark settings.")
}
if (is.na(m) || m < 2L || is.na(ef_construction) ||
    ef_construction < m) stop("Invalid HNSW build settings.")
x <- fastEmbedR:::massive_matrix_rows(input, 1L, rows)
shard_rows <- 20000L
threads <- 4L
started <- proc.time()[[3L]]
build_seconds <- 0
search_seconds <- 0
queries <- 0L
for (first in seq.int(1L, rows, by = shard_rows)) {
    count <- as.integer(min(shard_rows, rows - first + 1L))
    ref <- fastEmbedR:::massive_matrix_rows(x, first, count)
    data <- fastEmbedR:::massive_read_rows_cpp(ref, 1L, count,
        4 * count * x$ncol, TRUE)
    step <- proc.time()[[3L]]
    index <- faissR:::nn_faiss_hnsw_index_build_float32_cpp(
        data, m, ef_construction, ef_search, "euclidean", "euclidean",
        threads)
    build_seconds <- build_seconds + proc.time()[[3L]] - step
    for (query_first in seq.int(1L, rows, by = batch)) {
        n <- as.integer(min(batch, rows - query_first + 1L))
        query <- fastEmbedR:::massive_matrix_rows(x, query_first, n)
        q <- fastEmbedR:::massive_read_rows_cpp(query, 1L, n,
            4 * n * x$ncol, TRUE)
        step <- proc.time()[[3L]]
        found <- faissR:::nn_faiss_hnsw_index_search_float32_cpp(
            index, q, 31L, FALSE, ef_search, threads, "double")
        search_seconds <- search_seconds + proc.time()[[3L]] - step
        if (!isTRUE(found$index_reused) ||
            found$ef_search != ef_search) stop("FAISS index not reused.")
        queries <- queries + n
    }
}
print(data.frame(rows = rows, batch = batch, m = m,
    ef_construction = ef_construction, ef_search = ef_search,
    build_seconds = build_seconds, search_seconds = search_seconds,
    total_seconds = proc.time()[[3L]] - started,
    queries = queries))
