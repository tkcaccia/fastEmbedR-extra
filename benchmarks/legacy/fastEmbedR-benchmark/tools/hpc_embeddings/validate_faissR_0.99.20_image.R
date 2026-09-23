options(warn = 1)

library(faissR)
stopifnot(
  identical(as.character(packageVersion("faissR")), "0.99.20"),
  isTRUE(faiss_available()),
  isTRUE(cuda_available()),
  isTRUE(faiss_gpu_available()),
  isTRUE(cuvs_available())
)

set.seed(4)
x <- matrix(rnorm(2000L * 24L), nrow = 2000L, ncol = 24L)

validate_host_knn <- function(result, n = 2000L, k = 15L) {
  stopifnot(
    identical(dim(result$indices), c(n, k)),
    identical(dim(result$distances), c(n, k)),
    all(is.finite(result$distances)),
    all(result$indices >= 1L),
    all(result$indices <= n)
  )
}

cpu <- nn(
  x, k = 15L, exclude_self = TRUE, backend = "cpu",
  method = "exact", metric = "euclidean", n_threads = 2L
)
validate_host_knn(cpu)

cuda_exact <- nn(
  x, k = 15L, exclude_self = TRUE, backend = "cuda",
  method = "exact", metric = "euclidean", target_recall = 0.99
)
validate_host_knn(cuda_exact)

cuda_auto <- nn(
  x, k = 15L, exclude_self = TRUE, backend = "cuda",
  method = "auto", metric = "euclidean", tuning = "auto",
  target_recall = 0.99
)
validate_host_knn(cuda_auto)

resident <- nn_gpu(
  x, k = 15L, exclude_self = TRUE, method = "auto",
  metric = "euclidean", target_recall = 0.99
)
stopifnot(
  inherits(resident, "faissR_gpu_knn"),
  identical(resident$result_residency, "cuda"),
  identical(as.integer(resident$device_to_host_result_copies), 0L)
)
validate_host_knn(gpu_knn_to_host(resident))

library(fastEmbedR)
fast_knn <- precompute_knn(
  x, k = 15L, backend = "cuda", metric = "euclidean", n.cores = 2L
)
stopifnot(inherits(fast_knn, "fastEmbedR_knn"))

small <- x[seq_len(800L), , drop = FALSE]
umap_fit <- umap(small, n_neighbors = 15L, backend = "cuda", seed = 4L)
tsne_fit <- opentsne(
  small, perplexity = 15L, backend = "cuda", seed = 4L,
  n_iter = 50L, auto_config = FALSE
)
stopifnot(
  identical(dim(umap_fit$layout), c(800L, 2L)),
  identical(dim(tsne_fit$layout), c(800L, 2L)),
  all(is.finite(umap_fit$layout)),
  all(is.finite(tsne_fit$layout))
)

library(kodamaR)
matrix_formals <- names(formals(KODAMA.matrix))
stopifnot("data" %in% matrix_formals, "graph" %in% matrix_formals)

print(data.frame(
  check = c(
    "cpu_exact", "cuda_exact", "cuda_auto", "cuda_resident",
    "fastEmbedR_precompute_knn", "fastEmbedR_umap_cuda",
    "fastEmbedR_opentsne_cuda", "kodama_data_graph_api"
  ),
  status = "passed"
), row.names = FALSE)
