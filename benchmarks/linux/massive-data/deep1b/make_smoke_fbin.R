#!/usr/bin/env Rscript
args <- commandArgs(trailingOnly = TRUE)
if (length(args) != 1L) {
    stop("Usage: make_smoke_fbin.R OUTPUT.fbin")
}
set.seed(4L)
rows <- 2000L
columns <- 96L
group <- rep(seq_len(4L), length.out = rows)
centers <- matrix(rnorm(4L * columns), nrow = 4L)
values <- centers[group, ] +
    matrix(rnorm(rows * columns, sd = 0.35), nrow = rows)
stream <- file(args[[1L]], "wb")
on.exit(close(stream))
writeBin(c(rows, columns), stream, size = 4L, endian = "little")
writeBin(as.vector(t(values)), stream, size = 4L,
    endian = "little")
