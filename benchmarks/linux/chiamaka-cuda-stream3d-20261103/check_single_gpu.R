args <- commandArgs(trailingOnly = TRUE)
stopifnot(length(args) == 1L)
.libPaths(c(file.path(args[[1L]], "library"), .libPaths()))
suppressPackageStartupMessages(library(fastEmbedR))
set.seed(41)
x <- matrix(rnorm(1024L), nrow = 64L)
stats <- fastEmbedR:::pca_cuda_resident_covariance_cpp(x, 0L, TRUE)
expected <- stats::cov(x)
stopifnot(max(abs(stats$center - colMeans(x))) < 1e-6)
stopifnot(max(abs(stats$covariance - expected)) < 1e-4)
loadings <- eigen(expected, symmetric = TRUE)$vectors[, 1:3]
scores <- fastEmbedR:::pca_cuda_resident_project_cpp(x, 0L,
    stats$center, rep(1, ncol(x)), loadings)
expected_scores <- sweep(x, 2L, colMeans(x)) %*% loadings
stopifnot(max(abs(scores - expected_scores)) < 1e-4)
cat("PCA_RESIDENT_SINGLE_GPU_PASS\n")
