library(fastEmbedR)
stopifnot(isTRUE(fastEmbedR:::embedding_cuda_available_cpp()))
stopifnot(isTRUE(fastEmbedR:::native_cuda_knn_available_cpp()))

x <- scale(as.matrix(iris[, 1:4]))
fit <- tsne(
    x, perplexity = 5, n_components = 3L,
    backend = "cuda", n.cores = 1L, landmarks = 0.2,
    transform_perplexity = 5,
    early_exaggeration_iter = 2L, n_iter = 3L,
    transform_iter = 2L, seed = 5L
)
projected <- project_landmark_model(
    fit$model, x[1:5, , drop = FALSE],
    transform_perplexity = 5, transform_iter = 2L
)
stopifnot(
    identical(dim(fit$layout), c(150L, 3L)),
    all(is.finite(fit$layout)),
    sd(fit$layout[, 3L]) > 0,
    identical(fit$parameters$transform_backend, "cuda"),
    identical(dim(projected$layout), c(5L, 3L)),
    all(is.finite(projected$layout)),
    identical(projected$parameters$projection_backend, "cuda")
)
cat("3D CUDA landmark t-SNE and model projection passed\n")
