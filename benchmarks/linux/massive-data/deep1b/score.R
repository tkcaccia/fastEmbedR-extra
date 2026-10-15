#!/usr/bin/env Rscript

args <- commandArgs(trailingOnly = TRUE)
if (!length(args) %in% c(6L, 7L) ||
    !args[[6L]] %in% c("deep", "turing")) {
    stop("Usage: score.R INPUT_FBIN OUTPUT_F32 ROWS COMPONENTS ",
         "OUTPUT_DIR DATASET [FIRST_ROW]")
}
library(fastEmbedR)
source <- massive_matrix(args[[1L]])
rows <- as.numeric(args[[3L]])
components <- as.numeric(args[[4L]])
first_row <- if (length(args) == 7L) as.numeric(args[[7L]]) else 1
if (!is.finite(rows) || rows < 512 || rows > source$nrow ||
    rows != floor(rows)) stop("Invalid scored row count.")
if (!is.finite(first_row) || first_row < 1 ||
    first_row != floor(first_row) ||
    first_row + rows - 1 > source$nrow) {
    stop("Invalid scored first row.")
}
if (!is.finite(components) || components < 1 ||
    components != floor(components)) stop("Invalid component count.")
layout <- massive_matrix(args[[2L]], nrow = rows,
                         ncol = components)
sample_n <- min(4096L, rows)
ids <- floor((seq_len(sample_n) - 0.5) * rows / sample_n) + 1
high <- do.call(rbind, lapply(ids, function(i) {
    massive_read_rows(source, first = first_row + i - 1, n = 1L)
}))
low <- do.call(rbind, lapply(ids, function(i) {
    massive_read_rows(layout, first = i, n = 1L)
}))
if (!all(is.finite(high)) || !all(is.finite(low))) {
    stop("Quality sample contains non-finite values.")
}
colnames(low) <- paste0("dim", seq_len(ncol(low)))
plot_file <- gzfile(file.path(args[[5L]], "plot_sample.csv.gz"), "wt")
write.csv(data.frame(row_id = first_row + ids - 1, low),
    plot_file, row.names = FALSE)
close(plot_file)
visual_ids <- unique(floor((seq_len(min(10000L, rows)) - 0.5) *
    rows / min(10000L, rows)) + 1)
visual <- do.call(rbind, lapply(visual_ids, function(i) {
    massive_read_rows(layout, first = i, n = 1L)
}))
colnames(visual) <- paste0("dim", seq_len(ncol(visual)))
visual_file <- gzfile(file.path(args[[5L]],
    "plot_sample_10000.csv.gz"), "wt")
write.csv(data.frame(row_id = first_row + visual_ids - 1, visual),
    visual_file, row.names = FALSE)
close(visual_file)
metrics <- evaluate_embedding(high, low, k = c(15L, 30L),
    sample_size_for_global_metrics = sample_n,
    sample_size_for_local_metrics = sample_n,
    seed = 4L, backend = "cpu", n.cores = 1L,
    dataset = paste0(args[[6L]], "_1B_4096_row_sample"))
metrics$quality_scope <- "within_fixed_4096_row_sample"
metrics$rows_fitted <- rows
metrics$input_first_row <- first_row
write.csv(data.frame(row_id = first_row + ids - 1),
    file.path(args[[5L]], "quality_row_ids.csv"), row.names = FALSE)
write.csv(metrics, file.path(args[[5L]], "quality.csv"),
    row.names = FALSE)
