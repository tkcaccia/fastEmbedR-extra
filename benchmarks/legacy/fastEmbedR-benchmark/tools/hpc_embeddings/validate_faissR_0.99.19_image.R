options(warn = 1)

library(faissR)
stopifnot(
  identical(as.character(packageVersion("faissR")), "0.99.19"),
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
  x,
  k = 15L,
  exclude_self = TRUE,
  backend = "cpu",
  method = "exact",
  metric = "euclidean",
  n_threads = 2L
)
validate_host_knn(cpu)

cuda_exact <- nn(
  x,
  k = 15L,
  exclude_self = TRUE,
  backend = "cuda",
  method = "exact",
  metric = "euclidean",
  target_recall = 0.99
)
validate_host_knn(cuda_exact)

cuda_auto <- nn(
  x,
  k = 15L,
  exclude_self = TRUE,
  backend = "cuda",
  method = "auto",
  metric = "euclidean",
  tuning = "auto",
  target_recall = 0.99
)
validate_host_knn(cuda_auto)

resident <- nn_gpu(
  x,
  k = 15L,
  exclude_self = TRUE,
  method = "auto",
  metric = "euclidean",
  target_recall = 0.99
)
stopifnot(
  inherits(resident, "faissR_gpu_knn"),
  identical(resident$result_residency, "cuda"),
  identical(as.integer(resident$device_to_host_result_copies), 0L)
)
resident_host <- gpu_knn_to_host(resident)
validate_host_knn(resident_host)

library(fastEmbedR)
fast_knn <- precompute_knn(
  x,
  k = 15L,
  backend = "cuda",
  metric = "euclidean",
  n.cores = 2L
)
stopifnot(inherits(fast_knn, "fastEmbedR_knn"))

library(kodamaR)
matrix_formals <- names(formals(KODAMA.matrix))
stopifnot("data" %in% matrix_formals, "graph" %in% matrix_formals)

summary <- data.frame(
  check = c(
    "cpu_exact",
    "cuda_exact",
    "cuda_auto",
    "cuda_resident",
    "fastEmbedR_precompute_knn",
    "kodama_data_graph_api"
  ),
  status = "passed",
  stringsAsFactors = FALSE
)
print(summary, row.names = FALSE)
