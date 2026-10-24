#!/usr/bin/env Rscript

run_test <- function(cores, expected_chunk) {
source_files <- vapply(sys.frames(), function(frame) {
    if (is.null(frame$ofile)) "" else frame$ofile
}, character(1))
script <- grep("test_run_full_graph_failfast.R$", source_files,
    value = TRUE)
if (!length(script)) {
    script <- sub("^--file=", "", grep("^--file=",
        base::commandArgs(), value = TRUE))
}
suite <- dirname(normalizePath(tail(script, 1L)))
root <- tempfile("full_graph_failfast_")
dir.create(root)
on.exit(unlink(root, recursive = TRUE), add = TRUE)
input <- file.path(root, "input.fbin")
stream <- file(input, "wb")
writeBin(as.integer(c(1000L, 96L)), stream, size = 4L,
    endian = "little")
set.seed(4L)
writeBin(as.vector(t(matrix(rnorm(96000L), 1000L, 96L))),
    stream, size = 4L, endian = "little")
close(stream)

keys <- c("DEEP1B_SMOKE", "DEEP1B_FIRST_ROW", "DEEP1B_FIT_MODE",
    "DEEP1B_REBUILD_KNN_FOR_UMAP", "DEEP1B_MEMORY_LIMIT",
    "DEEP1B_CPU_CORES")
old <- Sys.getenv(keys, unset = NA_character_)
on.exit(for (i in seq_along(keys)) {
    if (is.na(old[[i]])) Sys.unsetenv(keys[[i]]) else
        do.call(Sys.setenv, setNames(list(old[[i]]), keys[[i]]))
}, add = TRUE)
Sys.setenv(DEEP1B_SMOKE = "1", DEEP1B_FIRST_ROW = "1",
    DEEP1B_FIT_MODE = "full", DEEP1B_REBUILD_KNN_FOR_UMAP = "1",
    DEEP1B_MEMORY_LIMIT = "512MB",
    DEEP1B_CPU_CORES = as.character(cores))

scope <- new.env(parent = environment())
builds <- 0L
scope$commandArgs <- function(trailingOnly = FALSE) {
    if (trailingOnly) c(input, "deep", "cpu", "1000", root) else
        paste0("--file=", file.path(suite, "run_full_graph.R"))
}
scope$massive_full_knn_graph <- function(...) {
    builds <<- builds + 1L
    list(k = 30L, backend = "cpu", method = "mock",
        observed_recall = 1, minimum_row_recall = 1,
        audit_rows = 4L, sampled_rows_below_target = 0L,
        sample_target_met = TRUE, build_seconds = 0,
        search_seconds = 0, audit_seconds = 0,
        audit_sample_rows = 1:4, audit_row_recall = rep(1, 4),
        hnsw_settings = list())
}
scope$massive_tsne_affinities <- function(...) {
    stop("injected affinity failure")
}
error <- tryCatch(source(file.path(suite, "run_full_graph.R"),
    local = scope), error = conditionMessage)
if (!grepl("injected affinity failure", error, fixed = TRUE)) stop(error)
identity <- readRDS(file.path(root, "work", "source_identity.rds"))
pca_metrics <- read.csv(file.path(root, "results",
    "cpu_pca_1000_fullgraph", "metrics.csv"))
stopifnot(grepl("injected affinity failure", error, fixed = TRUE),
    identity$pca_chunk_rows == expected_chunk,
    pca_metrics$pca_chunk_rows == 1000L,
    builds == 1L,
    !file.exists(file.path(root, "knn_rebuild.csv")))
cat("Failed t-SNE does not rebuild KNN at ", cores,
    " cores: PASS\n", sep = "")
}

run_test(4L, 100000L)
run_test(32L, 1000000L)
