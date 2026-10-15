#!/usr/bin/env Rscript

args <- commandArgs(trailingOnly = TRUE)
if (length(args) != 1L) stop("Usage: benchmark_exact_index_reuse.R CSV")
library_path <- Sys.getenv("FASTEMBEDR_TEST_LIB")
if (!nzchar(library_path)) stop("FASTEMBEDR_TEST_LIB is required.")
library(fastEmbedR, lib.loc = library_path)

set.seed(42)
reference <- matrix(rnorm(3000L * 48L), 3000L)
query <- matrix(rnorm(2048L * 48L), 2048L)
starts <- seq.int(1L, nrow(query), by = 128L)
batch <- function(first) query[first:(first + 127L), , drop = FALSE]
old_search <- function() lapply(starts, function(first) {
    fastEmbedR:::native_exact_query_cpp(reference, batch(first), 15L, 1L)
})
new_search <- function(index) lapply(starts, function(first) {
    fastEmbedR:::native_exact_index_search_cpp(index, batch(first),
        15L, 1L)
})
elapsed <- function(expr) unname(system.time(expr)[["elapsed"]])

index <- fastEmbedR:::native_exact_index_build_cpp(reference)
invisible(old_search()[[1L]])
invisible(new_search(index)[[1L]])
results <- vector("list", 5L)
for (rep in seq_along(results)) {
    gc()
    old_time <- elapsed(old <- old_search())
    gc()
    build_time <- elapsed(index <-
        fastEmbedR:::native_exact_index_build_cpp(reference))
    search_time <- elapsed(new <- new_search(index))
    for (i in seq_along(starts)) {
        stopifnot(identical(old[[i]]$indices, new[[i]]$indices))
        stopifnot(isTRUE(all.equal(old[[i]]$distances,
            new[[i]]$distances, tolerance = 1e-6)))
    }
    results[[rep]] <- data.frame(
        repetition = rep, package_version = as.character(
            packageVersion("fastEmbedR", lib.loc = library_path)),
        reference_rows = nrow(reference), features = ncol(reference),
        query_rows = nrow(query), batch_rows = 128L, k = 15L,
        old_seconds = old_time, index_build_seconds = build_time,
        indexed_search_seconds = search_time,
        indexed_total_seconds = build_time + search_time)
}
write.csv(do.call(rbind, results), args[[1L]], row.names = FALSE)
