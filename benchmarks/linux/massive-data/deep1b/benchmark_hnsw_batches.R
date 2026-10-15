#!/usr/bin/env Rscript

args <- commandArgs(trailingOnly = TRUE)
if (length(args) != 2L) stop("Usage: benchmark_hnsw_batches.R INPUT OUT")
test_lib <- Sys.getenv("FASTEMBEDR_TEST_LIB")
if (nzchar(test_lib)) .libPaths(c(test_lib, .libPaths()))
x <- fastEmbedR::massive_matrix(args[[1L]])
if (x$nrow != 1000000L) stop("Expected a 1M-row input.")
reference <- fastEmbedR:::massive_matrix_rows(x, 1L, 20000L)
state <- fastEmbedR:::massive_knn_reference(
    reference, 30L, "hnsw", 4L, "cpu")
records <- list()
for (effort in c(120L, 240L)) {
    for (batch_rows in c(256L, 8192L)) {
        started <- proc.time()[[3L]]
        native_seconds <- 0
        for (first in seq.int(1L, 65536L, by = batch_rows)) {
            rows <- min(batch_rows, 65537L - first)
            query <- fastEmbedR:::massive_reference_buffer_cpp(
                fastEmbedR:::massive_matrix_rows(x, first, rows))
            found <- fastEmbedR:::massive_knn_query(
                state, query, 31L, "hnsw", 4L, "cpu", effort)
            if (!identical(found$method, "native_hnsw_query_reused")) {
                stop("Search changed algorithm.")
            }
            native_seconds <- native_seconds + found$query_seconds
        }
        records[[length(records) + 1L]] <- data.frame(
            effort = effort, batch_rows = batch_rows,
            rows = 65536L, calls = 65536L / batch_rows,
            wall_seconds = unname(proc.time()[[3L]] - started),
            native_seconds = native_seconds,
            build_seconds = state$build_seconds)
    }
}
result <- do.call(rbind, records)
utils::write.csv(result, args[[2L]], row.names = FALSE)
print(result, row.names = FALSE)
