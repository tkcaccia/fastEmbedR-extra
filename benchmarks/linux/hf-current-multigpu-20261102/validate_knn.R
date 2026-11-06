library(fastEmbedR)

stopifnot(fastEmbedR:::massive_cuda_device_count_cpp() == 2L)
previous <- fastEmbedR:::native_cuda_memory_info_cpp()$device
fastEmbedR:::massive_cuda_select_cpp(1L)

set.seed(51L)
reference <- matrix(rnorm(400L * 8L), nrow = 400L)
query <- matrix(rnorm(24L * 8L), nrow = 24L)
index <- fastEmbedR:::native_cuda_index_build_cpp(
    reference, 8L, "exact")
observed <- fastEmbedR:::native_cuda_index_search_cpp(
    index, query, 8L)
truth <- t(vapply(seq_len(nrow(query)), function(i) {
    distances <- rowSums((reference - matrix(query[i, ],
        nrow(reference), ncol(reference), byrow = TRUE))^2)
    order(distances)[seq_len(8L)]
}, integer(8L)))
stopifnot(identical(fastEmbedR:::native_cuda_memory_info_cpp()$device,
    1L), identical(unname(observed$indices), unname(truth)),
    all(is.finite(observed$distances)))
rm(index)
gc()
fastEmbedR:::massive_cuda_select_cpp(previous)

path <- tempfile(fileext = ".f32")
writeBin(as.vector(t(reference)), path, size = 4L,
    endian = "little")
source <- massive_matrix(path, 400L, 8L)
graph <- massive_full_knn_graph(source, 8L, tempfile(),
    backend = "cuda", devices = c(0L, 1L), n.cores = 1L,
    chunk_rows = 128L, reference_chunk_rows = 256L,
    memory_limit = "1GB", audit_rows = 32L)
stopifnot(identical(graph$gpu_devices, c(0L, 1L)),
    identical(graph$observed_recall, 1),
    length(graph$per_device) == 2L)
cat("EXACT_TWO_GPU_KNN_PASS\n")
