args <- commandArgs(trailingOnly = TRUE)
stopifnot(length(args) == 3L)
.libPaths(c(args[[1L]], .libPaths()))
suppressPackageStartupMessages(library(fastEmbedR))
x <- readRDS(args[[2L]])
stopifnot(is.matrix(x), nrow(x) == 160L, ncol(x) == 5L)
ids <- seq.int(1L, nrow(x), by = 2L)
started <- proc.time()[[3L]]
fit <- cluster_landmarks(x, ids, method = "leiden", k = 10L,
    vote_k = 5L, backend = "cuda", n.cores = 1L, seed = 121L)
elapsed <- unname(proc.time()[[3L]] - started)
stopifnot(identical(fit$backend, "cuda"),
    identical(fit$reference_fit$backend, "cuda"),
    identical(fit$query_knn_backend, "cuda_to_host"),
    identical(fit$graph_assembly_backend, "cpu"),
    identical(fit$vote_backend, "cpu"),
    length(fit$membership) == 160L,
    all(fit$membership > 0L),
    identical(fit$membership[ids], fit$reference_fit$membership),
    all(is.finite(fit$confidence)))
saveRDS(list(elapsed_seconds = elapsed, backend = fit$backend,
    fit_backend = fit$reference_fit$backend,
    query_knn_backend = fit$query_knn_backend,
    membership = fit$membership,
    confidence = fit$confidence), args[[3L]])
cat("CUDA_CLUSTER_LANDMARK_PROBE_PASS\n")
