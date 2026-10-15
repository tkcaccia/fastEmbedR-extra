#!/usr/bin/env Rscript

args <- commandArgs(trailingOnly = TRUE)
if (length(args) != 2L) {
    stop("Usage: prepare_pca_plot_input.R DATASET.RData OUTPUT_DIR")
}

source_file <- normalizePath(args[[1L]], mustWork = TRUE)
output_dir <- args[[2L]]
dir.create(output_dir, recursive = TRUE, showWarnings = FALSE)
environment <- new.env(parent = emptyenv())
objects <- load(source_file, envir = environment)
if (length(objects) != 1L) stop("Expected one dataset object.")
dataset <- environment[[objects[[1L]]]]
x <- dataset$data
labels <- as.character(dataset$labels)
n <- as.integer(dataset$metadata$n)
p <- as.integer(dataset$metadata$p)
if (!inherits(x, "float32") || length(n) != 1L ||
        length(p) != 1L || is.na(n) || is.na(p) ||
        !identical(dim(x@Data), c(n, p)) ||
        length(labels) != n || p < 2L) {
    stop("Dataset labels or dimensions are invalid.")
}

binary <- file(file.path(output_dir, "data_float32.bin"), "wb")
for (first in seq.int(1L, n, by = 1024L)) {
    last <- min(first + 1023L, n)
    block <- x[first:last, , drop = FALSE]
    if (inherits(block, "float32")) block <- float::dbl(block)
    writeBin(as.vector(t(as.matrix(block))), binary,
             size = 4L, endian = "little")
}
close(binary)

set.seed(4L)
sample_rows <- sample.int(n, min(2000L, n))
utils::write.csv(data.frame(
    row = seq_len(n), source_row = seq_len(n),
    label = labels, quality_sample = seq_len(n) %in% sample_rows
), file.path(output_dir, "rows_labels.csv"), row.names = FALSE)
utils::write.csv(data.frame(n = n, p = p,
                            quality_n = length(sample_rows)),
                 file.path(output_dir, "manifest.csv"), row.names = FALSE)
