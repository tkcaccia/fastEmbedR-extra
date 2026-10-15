#!/usr/bin/env Rscript

args <- commandArgs(trailingOnly = TRUE)
if (length(args) != 4L) {
    stop("Usage: score_fullgraph_leiden.R LABELS ROWS CASE_DIR FIGURE")
}
labels_path <- normalizePath(args[[1L]], mustWork = TRUE)
rows <- as.numeric(args[[2L]])
case_dir <- normalizePath(args[[3L]], mustWork = TRUE)
figure <- args[[4L]]
method <- if (grepl("_louvain_", basename(case_dir), fixed = TRUE))
    "Louvain" else "Leiden"
if (!is.finite(rows) || rows != floor(rows) || rows < 1 ||
    file.info(labels_path)$size != rows * 4) {
    stop(method, " labels do not cover every fitted row.")
}
set.seed(4L)
indices <- sort(sample.int(rows, min(rows, 10000L)))
stream <- file(labels_path, "rb")
on.exit(close(stream))
labels <- vapply(indices, function(index) {
    seek(stream, where = (index - 1) * 4)
    readBin(stream, integer(), n = 1L, size = 4L,
        endian = "little")
}, integer(1L))
if (anyNA(labels) || any(labels < 1L)) stop("Invalid cluster labels.")
counts <- sort(table(labels), decreasing = TRUE)
write.csv(data.frame(community = names(counts),
    sample_count = as.integer(counts)),
    file.path(case_dir, "sample_community_counts.csv"),
    row.names = FALSE)
dir.create(dirname(figure), recursive = TRUE, showWarnings = FALSE)
png(figure, width = 1800L, height = 1100L, res = 180L)
top <- head(counts, 20L)
barplot(top, las = 2L, col = "#257E86", border = NA,
    ylab = "Rows in sample", xlab = "Community ID",
    main = paste(method, "community sizes"))
mtext(sprintf("Random sample of %s from %s fitted rows",
    format(length(indices), big.mark = ","),
    format(rows, big.mark = ",")), side = 3L, line = 0L)
dev.off()
