args <- commandArgs(trailingOnly = TRUE)
stopifnot(length(args) == 1L)
stopifnot(fastEmbedR:::embedding_cuda_available_cpp())
stopifnot(fastEmbedR:::native_cuda_knn_available_cpp())

x <- scale(as.matrix(datasets::iris[seq_len(45L), 1:4]))
started <- proc.time()[[3L]]
umap_fit <- fastEmbedR::umap(x, n_neighbors = 10L,
    n_components = 2L, landmarks = 0.5, backend = "cuda",
    seed = 11L)
stopifnot(identical(dim(umap_fit$layout), c(45L, 2L)),
    all(is.finite(as.matrix(umap_fit$layout))),
    identical(umap_fit$parameters$landmark_refinement_backend, "cuda"))
umap_elapsed <- proc.time()[[3L]] - started

started <- proc.time()[[3L]]
tsne_fit <- fastEmbedR::tsne(x, landmarks = 0.5,
    perplexity = 3, early_exaggeration_iter = 2L,
    n_iter = 2L, transform_iter = 2L,
    negative_gradient_method = "fft", backend = "cuda",
    seed = 11L)
stopifnot(identical(dim(tsne_fit$layout), c(45L, 2L)),
    all(is.finite(as.matrix(tsne_fit$layout))))
tsne_elapsed <- proc.time()[[3L]] - started

result <- data.frame(method = c("umap", "tsne"),
    n = 45L, dimensions = 2L,
    elapsed_sec = c(umap_elapsed, tsne_elapsed))
utils::write.csv(result, args[[1L]], row.names = FALSE)
print(result)
