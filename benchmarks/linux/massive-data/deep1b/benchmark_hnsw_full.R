#!/usr/bin/env Rscript

args <- commandArgs(trailingOnly = TRUE)
if (length(args) < 4L || length(args) > 6L) {
    stop(paste("Usage: benchmark_hnsw_full.R INPUT OUTPUT",
        "ROWS BATCH_ROWS [EF_SEARCH] [AUDIT_ROWS]"))
}
test_lib <- Sys.getenv("FASTEMBEDR_TEST_LIB")
if (nzchar(test_lib)) .libPaths(c(test_lib, .libPaths()))
x <- fastEmbedR::massive_matrix(args[[1L]])
rows <- as.integer(args[[3L]])
batch_rows <- as.integer(args[[4L]])
ef_search <- if (length(args) >= 5L) as.integer(args[[5L]]) else 0L
audit_rows <- if (length(args) == 6L) as.integer(args[[6L]]) else 0L
if (is.na(rows) || rows < 100L || rows > x$nrow ||
    is.na(batch_rows) || batch_rows < 1L ||
    is.na(ef_search) || ef_search < 0L ||
    is.na(audit_rows) || audit_rows < 0L ||
    audit_rows > rows) stop("Invalid settings.")
view <- fastEmbedR:::massive_matrix_rows(x, 1L, rows)
started <- proc.time()[[3L]]
graph <- fastEmbedR::massive_full_knn_graph(view, 30L, args[[2L]],
    method = "hnsw_sharded", n.cores = 4L,
    reference_chunk_rows = 20000L, chunk_rows = batch_rows,
    memory_limit = "4GB", ef_search = ef_search,
    audit_rows = audit_rows)
result <- data.frame(rows = rows, batch_rows = batch_rows,
    ef_search = ef_search,
    observed_batch_rows = graph$resources$chunk_rows,
    total_seconds = unname(proc.time()[[3L]] - started),
    build_seconds = graph$build_seconds,
    graph_seconds = graph$total_seconds,
    backend = graph$backend, method = graph$method,
    recall_audited = graph$recall_audited,
    mean_recall = if (audit_rows > 0L) graph$observed_recall
        else NA_real_,
    min_recall = if (audit_rows > 0L) graph$minimum_row_recall
        else NA_real_)
utils::write.csv(result, paste0(args[[2L]], ".timing.csv"),
    row.names = FALSE)
print(result, row.names = FALSE)
