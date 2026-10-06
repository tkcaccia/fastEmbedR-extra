args <- commandArgs(trailingOnly = TRUE)
if (length(args) != 3L) {
    stop("Usage: Rscript run_pca.R N P output.csv")
}

n <- as.integer(args[[1L]])
p <- as.integer(args[[2L]])
output <- args[[3L]]
if (is.na(n) || is.na(p) || n < 2L || p < 50L) {
    stop("N must be at least 2 and P at least 50")
}

library(fastEmbedR)
set.seed(22L)
x <- matrix(runif(n * p), nrow = n, ncol = p)
invisible(gc())
invisible(fastEmbedR::pca(
    x, ncomp = 50L, backend = "cpu", n.cores = 4L, seed = 4L
))
invisible(gc())
rows <- vector("list", 3L)
for (repeat_id in seq_len(3L)) {
    elapsed <- system.time(fit <- fastEmbedR::pca(
        x, ncomp = 50L, backend = "cpu", n.cores = 4L, seed = 4L
    ))[["elapsed"]]
    stages <- fit$timing
    stopifnot(
        all(c("prepare", "sketch", "project", "small_svd_and_scores",
              "total") %in% names(stages)),
        abs(sum(unlist(stages)[1:4]) - stages$total) < 1e-4
    )
    rows[[repeat_id]] <- data.frame(
        n = n,
        p = p,
        repeat_id = repeat_id,
        elapsed_sec = elapsed,
        prepare_sec = stages$prepare,
        sketch_sec = stages$sketch,
        project_sec = stages$project,
        small_svd_and_scores_sec = stages$small_svd_and_scores,
        pca_sec = stages$total,
        gemm_backend = if (is.null(fit$gemm_backend)) {
            fit$engine
        } else {
            fit$gemm_backend
        },
        blas_threads_requested = fit$blas.n.cores_requested,
        blas_threads_effective = fit$blas.n.cores
    )
    rm(fit)
}

result <- do.call(rbind, rows)
write.csv(result, output, row.names = FALSE)
print(result)
