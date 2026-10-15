set.seed(4)
x <- matrix(rnorm(128 * 8), 128, 8)
options(backend = "cpu", n.cores = 2L)
fit <- fastEmbedR::umap(x, n_neighbors = 15, seed = 4)
knn <- fastEmbedR::precompute_knn(x, k = 15)
from_knn <- fastEmbedR::umap_knn(
    knn$indices, knn$distances, seed = 4
)
stopifnot(
    identical(dim(fit$layout), c(128L, 2L)),
    identical(dim(from_knn), c(128L, 2L)),
    all(is.finite(as.matrix(from_knn))),
    identical(fit$parameters$backend, "cpu")
)
