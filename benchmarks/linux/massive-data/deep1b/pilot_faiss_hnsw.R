#!/usr/bin/env Rscript

args <- commandArgs(trailingOnly = TRUE)
if (length(args) != 3L) {
    stop("Usage: pilot_faiss_hnsw.R INPUT FIT_ROWS SHARD_ROWS")
}
libs <- c(Sys.getenv("FASTEMBEDR_TEST_LIB"),
    Sys.getenv("FAISSR_TEST_LIB"))
.libPaths(c(libs[nzchar(libs)], .libPaths()))
if (!requireNamespace("float", quietly = TRUE)) stop("float missing")
input <- fastEmbedR::massive_matrix(args[[1L]])
fit_rows <- as.integer(args[[2L]])
shard_rows <- as.integer(args[[3L]])
if (anyNA(c(fit_rows, shard_rows)) || fit_rows < shard_rows ||
    fit_rows > input$nrow || fit_rows %% shard_rows != 0L) {
    stop("Invalid fit or shard rows.")
}
x <- fastEmbedR:::massive_matrix_rows(input, 1L, fit_rows)
output <- list()
for (shard in seq_len(fit_rows / shard_rows)) {
    first <- as.integer((shard - 1L) * shard_rows + 1L)
    ref <- fastEmbedR:::massive_matrix_rows(x, first, shard_rows)
    sample <- as.integer(floor((seq_len(16L) - 0.5) *
        shard_rows / 16L) + 1L)
    exact <- fastEmbedR:::massive_exact_sample_batch_cpp(
        ref, ref, sample, 30L, shard_rows, 4L, TRUE)
    data <- fastEmbedR:::massive_read_rows_cpp(ref, 1L,
        shard_rows, 4 * shard_rows * x$ncol, TRUE)
    query <- data[sample, , drop = FALSE]
    for (m in c(12L, 16L)) {
        index <- faissR:::nn_faiss_hnsw_index_build_float32_cpp(
            data, m, if (m == 12L) 80L else 100L, 60L,
            "euclidean", "euclidean", 4L)
        for (ef in c(60L, 120L, 240L, 480L)) {
            found <- faissR:::nn_faiss_hnsw_index_search_float32_cpp(
                index, query, 31L, FALSE, ef, 4L, "double")
            recall <- vapply(seq_along(sample), function(i) {
                ids <- found$indices[i, ]
                ids <- ids[ids != sample[[i]]][seq_len(30L)]
                sum(ids %in% exact$indices[i, ]) / 30L
            }, numeric(1))
            output[[length(output) + 1L]] <- data.frame(
                shard = shard, m = m, ef = ef,
                mean_recall = mean(recall), min_recall = min(recall))
        }
    }
    message("Pilot shard ", shard, "/", fit_rows / shard_rows)
}
print(do.call(rbind, output), row.names = FALSE)
