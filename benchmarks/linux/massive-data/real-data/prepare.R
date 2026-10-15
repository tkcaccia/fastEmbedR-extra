#!/usr/bin/env Rscript
args <- commandArgs(trailingOnly = TRUE)
if (length(args) != 3L) {
    stop("Usage: prepare.R DATA_ROOT DATASET OUTPUT_DIR")
}
common <- Sys.getenv("REAL_COMMON_R")
if (!nzchar(common)) stop("REAL_COMMON_R is required.")
source(common)
dataset <- args[[2L]]
if (!dataset %in% c("flow18", "imagenet",
        "FlowRepository_FR-FCM-ZYRM_files")) stop("Unknown dataset.")
target <- args[[3L]]
dir.create(target, recursive = TRUE, showWarnings = FALSE)
path <- file.path(target, "input.f32")
if (file.exists(path)) stop("Refusing to overwrite input.f32.")
value <- load_dataset(args[[1L]], dataset)
data <- value$data
rows <- nrow(data)
columns <- ncol(data)
expected <- c(flow18 = 1000021,
    imagenet = 1281167,
    `FlowRepository_FR-FCM-ZYRM_files` = 5220347)
if (!identical(as.numeric(rows), unname(expected[[dataset]]))) {
    stop("Unexpected row count for ", dataset)
}
con <- file(path, "wb")
for (first in seq.int(1L, rows, by = 10000L)) {
    last <- min(rows, first + 9999L)
    block <- data[first:last, , drop = FALSE]
    if (inherits(block, "float32")) block <- float::dbl(block)
    block <- as.matrix(block)
    if (any(!is.finite(block))) stop("Non-finite input block.")
    writeBin(as.numeric(t(block)), con, size = 4L, endian = "little")
}
close(con)
if (file.info(path)$size != as.double(rows) * columns * 4) {
    stop("Prepared input has incorrect size.")
}
labels <- value$labels
if (!is.null(labels)) {
    if (length(labels) != rows) stop("Label count differs from rows.")
    saveRDS(as.character(labels), file.path(target, "source_labels.rds"),
            compress = TRUE)
}
manifest <- data.frame(dataset = dataset, rows = rows, columns = columns,
    source = normalizePath(value$path),
    source_sha256 = strsplit(system2("sha256sum", value$path,
        stdout = TRUE), " +")[[1L]][1L],
    input_sha256 = strsplit(system2("sha256sum", path,
        stdout = TRUE), " +")[[1L]][1L],
    labels_kind = if (is.null(labels)) "none" else "source",
    stringsAsFactors = FALSE)
write.csv(manifest, file.path(target, "input_manifest.csv"),
          row.names = FALSE)
