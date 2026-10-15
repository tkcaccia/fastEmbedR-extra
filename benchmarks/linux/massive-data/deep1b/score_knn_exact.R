#!/usr/bin/env Rscript

args <- commandArgs(trailingOnly = TRUE)
if (length(args) != 7L) {
    stop("Usage: score_knn_exact.R PREFIX TRUTH_RDS INPUT ",
         "FIRST_ROW ROWS K OUTPUT_CSV")
}
prefix <- args[[1L]]
truth <- readRDS(args[[2L]])
input <- normalizePath(args[[3L]], mustWork = TRUE)
first_row <- as.numeric(args[[4L]])
rows <- as.numeric(args[[5L]])
k <- as.integer(args[[6L]])
if (!identical(truth$input, input) ||
    truth$input_bytes != file.info(input)$size ||
    truth$fit_rows != rows || truth$first_row != first_row ||
    nrow(truth$indices) != 8192L || ncol(truth$indices) < k) {
    stop("Exact truth does not match the graph input window.")
}
if (length(truth$rows) != 8192L ||
    anyNA(truth$rows) || any(truth$rows < 1L) ||
    any(truth$rows > rows) || anyDuplicated(truth$rows) ||
    !identical(as.character(truth$split),
        rep(c("tune", "holdout"), each = 4096L))) {
    stop("Tune and holdout queries must be distinct, valid rows.")
}
path <- paste0(prefix, ".indices.u32")
if (file.info(path)$size != rows * k * 4) {
    stop("KNN index file has an unexpected size.")
}
connection <- file(path, "rb")
on.exit(close(connection))
recall <- vapply(seq_along(truth$rows), function(i) {
    row <- truth$rows[[i]]
    seek(connection, where = (row - 1) * k * 4, origin = "start")
    found <- readBin(connection, integer(), n = k, size = 4L,
        endian = "little")
    if (length(found) != k || any(found < 1L | found > rows) ||
        anyDuplicated(found)) stop("Invalid KNN graph row ", row)
    sum(found %in% truth$indices[i, seq_len(k)]) / k
}, numeric(1))
record <- do.call(rbind, lapply(c("tune", "holdout"), function(split) {
    selected <- recall[truth$split == split]
    if (length(selected) != 4096L) stop("Invalid truth split.")
    data.frame(status = "ok", split = split, input = input,
        first_row = first_row, rows = rows, k = k,
        truth = normalizePath(args[[2L]]),
        query_count = length(selected), mean_recall = mean(selected),
        min_recall = min(selected),
        p10_recall = unname(quantile(selected, 0.1)),
        fraction_below_099 = mean(selected < 0.99),
        lower95_recall = max(0, mean(selected) -
            1.645 * sd(selected) / sqrt(length(selected))))
}))
write.csv(record, args[[7L]], row.names = FALSE)
print(record)
