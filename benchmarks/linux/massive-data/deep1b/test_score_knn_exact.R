#!/usr/bin/env Rscript

this_file <- sub("^--file=", "", grep("^--file=", commandArgs(FALSE),
    value = TRUE)[[1L]])
script <- file.path(dirname(normalizePath(this_file)),
    "score_knn_exact.R")
root <- tempfile()
dir.create(root)
on.exit(unlink(root, recursive = TRUE))
input <- file.path(root, "input.fbin")
writeBin(as.raw(1:8), input)
rows <- 8192L
k <- 2L
graph <- cbind((seq_len(rows) %% rows) + 1L,
    ((seq_len(rows) + 1L) %% rows) + 1L)
prefix <- file.path(root, "graph")
writeBin(as.integer(t(graph)), paste0(prefix, ".indices.u32"),
    size = 4L, endian = "little")
query_rows <- seq_len(rows)
truth <- list(input = normalizePath(input),
    input_bytes = file.info(input)$size, fit_rows = rows,
    first_row = 1L, rows = query_rows,
    indices = graph[query_rows, , drop = FALSE],
    split = rep(c("tune", "holdout"), each = 4096L))
truth_path <- file.path(root, "truth.rds")
saveRDS(truth, truth_path)
stopifnot(identical(truth$input, normalizePath(input)),
    truth$input_bytes == file.info(input)$size,
    truth$fit_rows == rows, truth$first_row == 1,
    nrow(truth$indices) == 8192L, ncol(truth$indices) >= k)
output <- file.path(root, "quality.csv")
args <- c(script, prefix, truth_path, input, "1", "8192", "2", output)
result <- suppressWarnings(system2("Rscript", args,
    stdout = TRUE, stderr = TRUE))
if (!is.null(attr(result, "status"))) stop(paste(result, collapse = "\n"))
quality <- read.csv(output)
stopifnot(nrow(quality) == 2L,
    identical(quality$split, c("tune", "holdout")),
    all(quality$mean_recall == 1))
truth$rows[[4097L]] <- truth$rows[[1L]]
saveRDS(truth, truth_path)
result <- suppressWarnings(system2("Rscript", args,
    stdout = TRUE, stderr = TRUE))
stopifnot(!is.null(attr(result, "status")),
    any(grepl("must be distinct", result, fixed = TRUE)))
cat("KNN_EXACT_SCORE_PASS\n")
