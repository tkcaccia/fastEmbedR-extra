#!/usr/bin/env Rscript

args <- commandArgs(trailingOnly = TRUE)
if (length(args) != 3L) stop("Need inventory, dataset, output folder.")
inventory_path <- normalizePath(args[[1L]], mustWork = TRUE)
dataset <- args[[2L]]
output_dir <- args[[3L]]
root <- "/Users/silvanopiazza/Documents/Stefano/"
if (!startsWith(inventory_path, root) ||
    !startsWith(output_dir, root) || dir.exists(output_dir))
    stop("Input and new output must be under Stefano.")
inventory <- jsonlite::fromJSON(inventory_path, simplifyVector = FALSE)
item <- inventory[[dataset]]
if (is.null(item)) stop("Dataset missing from source inventory.")
path <- normalizePath(item$input_path, mustWork = TRUE)
if (!startsWith(path, root)) stop("Input path is outside Stefano.")
sha256 <- function(path) {
    result <- system2("shasum", c("-a", "256", shQuote(path)),
        stdout = TRUE)
    if (length(result) != 1L ||
        !grepl("^[0-9a-f]{64} ", result))
        stop("File checksum could not be read.")
    substr(result, 1L, 64L)
}
if (sha256(path) != item$input_sha256)
    stop("Input checksum differs from the resident benchmark.")
env <- new.env(parent = emptyenv())
keys <- load(path, envir = env)
objects <- lapply(keys, function(key) get(key, envir = env))
objects <- Filter(function(x) is.list(x) &&
    !is.null(x$data) && !is.null(x$labels), objects)
if (length(objects) != 1L) stop("Dataset object is ambiguous.")
x <- objects[[1L]]$data
labels <- objects[[1L]]$labels
if (nrow(x) != item$expected_rows ||
    ncol(x) != item$expected_columns ||
    length(labels) != nrow(x))
    stop("Input shape or labels differ from inventory.")
write_f32 <- function(x, path, block_rows = 8192L) {
    con <- file(path, open = "wb")
    connection_open <- TRUE
    on.exit(if (connection_open) close(con), add = TRUE)
    for (first in seq.int(1L, nrow(x), by = block_rows)) {
        last <- min(nrow(x), first + block_rows - 1L)
        block <- x[first:last, , drop = FALSE]
        if (inherits(block, "float32")) block <- float::dbl(block)
        if (!is.matrix(block) || any(!is.finite(block)))
            stop("Nonfinite or nonmatrix source block.")
        writeBin(as.numeric(t(block)), con, size = 4L,
            endian = "little")
    }
    close(con)
    connection_open <- FALSE
}
expected <- as.double(nrow(x)) * ncol(x) * 4
available <- fastEmbedR:::massive_disk_available_cpp(output_dir)
if (!is.finite(available) || available - expected < 100 * 1024^3)
    stop("Conversion would cross the 100 GiB free-disk floor.")
dir.create(output_dir, recursive = TRUE, showWarnings = FALSE)
if (!dir.exists(output_dir)) stop("Output directory unavailable.")
part <- file.path(output_dir, "features.f32.part")
final <- file.path(output_dir, "features.f32")
if (file.exists(part) || file.exists(final))
    stop("Output or partial file already exists.")
write_f32(x, part)
if (file.info(part)$size != expected)
    stop("Float32 output length differs from expected.")
if (!file.rename(part, final)) stop("Cannot finalize float32 output.")
source <- fastEmbedR::massive_matrix(final, nrow(x), ncol(x),
    format = "f32", access = "stream")
for (first in unique(c(1L, max(1L, nrow(x) - 3L)))) {
    count <- min(4L, nrow(x) - first + 1L)
    got <- fastEmbedR::massive_read_rows(source, first, count)
    block <- x[first:(first + count - 1L), , drop = FALSE]
    if (inherits(block, "float32")) block <- float::dbl(block)
    if (!isTRUE(all.equal(got, block, tolerance = 1e-5)))
        stop("Float32 row-order validation failed.")
}
saveRDS(labels, file.path(output_dir, "labels.rds"))
identity <- list(dataset = dataset, source_path = path,
    source_sha256 = item$input_sha256,
    output_path = final, output_sha256 = sha256(final),
    rows = nrow(x), columns = ncol(x), bytes = expected,
    package_commit = "afeaffc39a607c00db5899c284451c6cdbf741bb")
jsonlite::write_json(identity,
    file.path(output_dir, "identity.json"),
    auto_unbox = TRUE, pretty = TRUE)
