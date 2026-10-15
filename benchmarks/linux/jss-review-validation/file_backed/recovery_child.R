#!/usr/bin/env Rscript

args <- commandArgs(trailingOnly = TRUE)
if (length(args) != 4L) {
    stop("Usage: recovery_child.R INPUT OUTPUT BACKEND ROWS")
}
suppressPackageStartupMessages(library(fastEmbedR))
dll <- getLoadedDLLs()[["fastEmbedR"]][["path"]]
hash <- strsplit(system2("sha256sum", dll,
    stdout = TRUE), " +")[[1L]][1L]
if (hash != Sys.getenv("FASTEMBEDR_DLL_SHA256")) {
    stop("Recovery child loaded a different package DLL")
}
source <- massive_matrix(args[[1L]], nrow = as.integer(args[[4L]]),
    ncol = as.integer(file.info(args[[1L]])$size /
        (4 * as.integer(args[[4L]]))), format = "f32")
backend <- match.arg(args[[3L]], c("cpu", "cuda"))
native <- if (backend == "cuda") {
    fastEmbedR:::massive_pca_covariance_cuda_cpp
} else fastEmbedR:::massive_pca_covariance_cpp
interrupted <- function(spec, chunk_rows, n_threads, center, means,
        rows, sums, progress, every) {
    abort <- function(done, current) {
        progress(done, current)
        tools::pskill(Sys.getpid(), signal = 9L)
        stop("SIGKILL failed")
    }
    native(spec, chunk_rows, n_threads, center, means,
        rows, sums, abort, every)
}
run <- function() fastEmbedR::pca(source, ncomp = 2L,
    backend = backend, n.cores = 2L, massive = "out_of_core",
    output = args[[2L]], chunk_rows = 32L, memory_limit = "256MB",
    checkpoint = TRUE)
if (backend == "cuda") {
    testthat::with_mocked_bindings(
        massive_pca_covariance_cuda_cpp = interrupted,
        run(), .package = "fastEmbedR")
} else testthat::with_mocked_bindings(
    massive_pca_covariance_cpp = interrupted,
    run(), .package = "fastEmbedR")
stop("Recovery worker completed without interruption")
