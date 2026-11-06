lib <- Sys.getenv("FASTEMBEDR_TEST_LIBRARY")
stopifnot(nzchar(lib))
.libPaths(c(lib, .libPaths()))
library(fastEmbedR)

set.seed(619)
x <- matrix(rnorm(36L * 4L), nrow = 36L)
fit <- tsne(
    x, n_components = 3L, landmarks = 18L,
    perplexity = 3, early_exaggeration_iter = 1L,
    n_iter = 1L, transform_iter = 1L,
    backend = "cpu", n.cores = 2L, seed = 15L
)
projected <- project_landmark_model(
    fit$model, x[1:4, , drop = FALSE],
    transform_k = 4L, transform_perplexity = 2,
    transform_iter = 1L
)
stopifnot(
    identical(dim(fit$layout), c(36L, 3L)),
    all(is.finite(fit$layout)),
    identical(dim(projected$layout), c(4L, 3L)),
    all(is.finite(projected$layout)),
    identical(projected$parameters$projection_backend, "cpu")
)
cat("3D CPU landmark t-SNE and model projection passed\n")
