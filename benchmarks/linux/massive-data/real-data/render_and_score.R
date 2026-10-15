#!/usr/bin/env Rscript
args <- commandArgs(trailingOnly = TRUE)
if (length(args) != 5L) {
    stop("Usage: render_and_score.R INPUT OUTPUT ROWS COLS CASE_DIR")
}
suppressPackageStartupMessages(library(fastEmbedR))
rows <- as.integer(args[[3L]])
columns <- as.integer(args[[4L]])
case_dir <- args[[5L]]
layout <- massive_matrix(args[[2L]], rows, 2L)
source <- massive_matrix(args[[1L]], rows, columns)
labels_path <- file.path(dirname(args[[1L]]), "source_labels.rds")
labels <- if (file.exists(labels_path)) readRDS(labels_path) else NULL
if (!is.null(labels) && length(labels) != rows) {
    stop("Source labels do not match the fitted rows.")
}
sample_n <- min(2048L, rows)
ids <- unique(as.integer(floor((seq_len(sample_n) - 0.5) *
    rows / sample_n) + 1L))
high <- do.call(rbind, lapply(ids, function(i) {
    massive_read_rows(source, i, 1L)
}))
low <- do.call(rbind, lapply(ids, function(i) {
    massive_read_rows(layout, i, 1L)
}))
quality <- evaluate_embedding(high, low, k = c(15L, 30L),
    sample_size_for_global_metrics = length(ids),
    sample_size_for_local_metrics = length(ids),
    seed = 4L, backend = "cpu", n.cores = 1L)
quality$quality_scope <- "same_fixed_2048_row_sample"
quality$rows_fitted <- rows
write.csv(quality, file.path(case_dir, "quality.csv"),
          row.names = FALSE)
width <- 1200L
height <- 1200L
chunk <- 100000L
limits <- c(Inf, -Inf, Inf, -Inf)
for (first in seq.int(1L, rows, by = chunk)) {
    block <- massive_read_rows(layout, first,
                              min(chunk, rows - first + 1L))
    if (any(!is.finite(block))) stop("Non-finite layout.")
    limits <- c(min(limits[1L], block[, 1L]),
                max(limits[2L], block[, 1L]),
                min(limits[3L], block[, 2L]),
                max(limits[4L], block[, 2L]))
}
if (limits[2L] <= limits[1L] || limits[4L] <= limits[3L]) {
    stop("Degenerate layout.")
}
categories <- if (is.null(labels)) character() else {
    names(sort(table(labels), decreasing = TRUE))[seq_len(
        min(23L, length(unique(labels))))]
}
label_counts <- if (length(categories)) {
    matrix(0L, nrow = width * height,
           ncol = length(categories) + 1L)
} else NULL
total <- integer(width * height)
for (first in seq.int(1L, rows, by = chunk)) {
    n <- min(chunk, rows - first + 1L)
    block <- massive_read_rows(layout, first, n)
    x <- pmin(width, pmax(1L, as.integer(
        (block[, 1L] - limits[1L]) /
        (limits[2L] - limits[1L]) * (width - 1L)) + 1L))
    y <- pmin(height, pmax(1L, as.integer(
        (block[, 2L] - limits[3L]) /
        (limits[4L] - limits[3L]) * (height - 1L)) + 1L))
    cell <- (height - y) * width + x
    total <- total + tabulate(cell, nbins = length(total))
    if (!is.null(label_counts)) {
        group <- match(labels[first:(first + n - 1L)], categories)
        group[is.na(group)] <- ncol(label_counts)
        for (j in seq_len(ncol(label_counts))) {
            label_counts[, j] <- label_counts[, j] +
                tabulate(cell[group == j], nbins = length(total))
        }
    }
}
if (sum(total) != rows) stop("Not all fitted points were plotted.")
occupied <- total > 0L
cap <- as.numeric(quantile(total[occupied], 0.99, names = FALSE))
shade <- rep(1, length(total))
shade[occupied] <- 1 - 0.9 * pmin(1,
    log1p(total[occupied]) / log1p(max(2, cap)))
colors <- grDevices::gray(shade)
render <- function(values, filename, subtitle) {
    grDevices::png(file.path(case_dir, filename), 1400L, 1500L,
                   res = 150L)
    par(mar = c(1, 1, 3, 1))
    plot.new()
    plot.window(xlim = c(0, 1), ylim = c(0, 1), asp = 1)
    rasterImage(as.raster(matrix(values, nrow = height,
                                 byrow = TRUE)), 0, 0, 1, 1,
                interpolate = FALSE)
    title(main = paste(basename(case_dir), format(rows, big.mark = ","),
                       "points"), sub = subtitle)
    grDevices::dev.off()
}
render(colors, "plot_density.png", "All fitted rows; point density")
if (!is.null(label_counts)) {
    dominant <- max.col(label_counts, ties.method = "first")
    palette <- grDevices::hcl.colors(ncol(label_counts), "Dark 3")
    colors[occupied] <- palette[dominant[occupied]]
    render(colors, "plot_source_labels.png",
           "All rows; top 23 source labels plus Other")
    legend <- data.frame(color = palette,
        source_label = c(categories, "Other"))
    write.csv(legend, file.path(case_dir, "source_label_legend.csv"),
              row.names = FALSE)
}
write.csv(data.frame(rows_fitted = rows, plotted_rows = sum(total),
    occupied_pixels = sum(occupied),
    color_semantics = if (is.null(label_counts)) "none" else
        "dominant_source_label_top23_plus_other"),
    file.path(case_dir, "visual_manifest.csv"), row.names = FALSE)
