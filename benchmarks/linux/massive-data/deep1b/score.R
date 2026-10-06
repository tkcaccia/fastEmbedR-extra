#!/usr/bin/env Rscript

args <- commandArgs(trailingOnly = TRUE)
if (length(args) != 5L || !args[[5L]] %in% c("deep", "turing")) {
    stop("Usage: score.R INPUT_FBIN MODEL_RDS ROWS OUTPUT_DIR DATASET")
}
library(fastEmbedR)
source <- massive_matrix(args[[1L]])
fit <- readRDS(args[[2L]])
rows <- as.numeric(args[[3L]])
if (!is.finite(rows) || rows < 512 || rows > source$nrow ||
    rows != floor(rows)) stop("Invalid scored row count.")
layout <- if (inherits(fit, "fastEmbedR_massive_graph")) {
    stop("KNN quality is reported by the exact-row recall audit.")
} else if (!is.null(fit$scores)) fit$scores else fit$layout
if (!inherits(layout, "fastEmbedR_massive_matrix") ||
    layout$nrow != rows) stop("Saved model has no matching layout.")
ids <- floor((seq_len(512L) - 0.5) * rows / 512L) + 1
high <- do.call(rbind, lapply(ids, function(i) {
    massive_read_rows(source, first = i, n = 1L)
}))
low <- do.call(rbind, lapply(ids, function(i) {
    massive_read_rows(layout, first = i, n = 1L)
}))
if (!all(is.finite(high)) || !all(is.finite(low))) {
    stop("Quality sample contains non-finite values.")
}
metrics <- evaluate_embedding(high, low, k = c(15L, 30L),
    sample_size_for_global_metrics = 512L,
    sample_size_for_local_metrics = 512L,
    seed = 4L, backend = "cpu", n.cores = 1L,
    dataset = paste0(args[[5L]], "_1B_512_row_sample"))
metrics$quality_scope <- "within_fixed_512_row_sample"
metrics$rows_fitted <- rows
write.csv(data.frame(row_id = ids),
    file.path(args[[4L]], "quality_row_ids.csv"), row.names = FALSE)
write.csv(metrics, file.path(args[[4L]], "quality.csv"),
    row.names = FALSE)
