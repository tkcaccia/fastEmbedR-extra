lib <- Sys.getenv("FASTEMBEDR_TEST_LIBRARY")
stopifnot(nzchar(lib))
.libPaths(c(lib, .libPaths()))
library(fastEmbedR)
stopifnot(isTRUE(fastEmbedR:::embedding_cuda_available_cpp()))
stopifnot(isTRUE(fastEmbedR:::native_cuda_knn_available_cpp()))

x <- scale(as.matrix(iris[, 1:4]))
started <- proc.time()[["elapsed"]]
fit <- tsne(
    x, perplexity = 5, n_components = 2L,
    backend = "cuda", n.cores = 1L, landmarks = 0.2,
    transform_perplexity = 5,
    early_exaggeration_iter = 2L, n_iter = 3L,
    transform_iter = 2L, seed = 4L
)
stopifnot(
    identical(dim(fit$layout), c(150L, 2L)),
    all(is.finite(fit$layout)),
    identical(fit$parameters$transform_backend, "cuda")
)
cat("2D CUDA landmark t-SNE passed; elapsed=",
    proc.time()[["elapsed"]] - started, " seconds\n", sep = "")
