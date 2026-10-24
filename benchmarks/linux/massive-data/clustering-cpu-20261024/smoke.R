library(fastEmbedR)
stopifnot(as.character(packageVersion("fastEmbedR")) == "0.1",
    as.character(packageVersion("faissR")) == "0.1",
    requireNamespace("float", quietly = TRUE))
set.seed(4L)
root <- tempfile("cluster-cpu-smoke-")
dir.create(root)
x <- matrix(rnorm(1000 * 16), 1000, 16)
path <- file.path(root, "input.f32")
writeBin(as.numeric(t(x)), path, size = 4L, endian = "little")
source <- massive_matrix(path, nrow = 1000, ncol = 16)
knn <- massive_full_knn_graph(source, 10L, file.path(root, "knn"),
    backend = "cpu", method = "hnsw_sharded", n.cores = 4L,
    chunk_rows = 500L, reference_chunk_rows = 1000L,
    memory_limit = "1GB", audit_rows = 32L,
    hnsw_build = list(m = 16L, ef_construction = 100L),
    ef_search = 100L)
stopifnot(knn$nrow == 1000, knn$observed_recall > 0.95,
    length(knn$hnsw_settings) > 0L)
graph <- massive_umap_fuzzy_graph(knn, file.path(root, "graph"),
    memory_limit = "1GB", sort_method = "bucketed",
    consume_knn = TRUE)
fit <- massive_cluster(graph, method = "leiden",
    massive = "out_of_core_graph", backend = "cpu", n.cores = 1L,
    output = file.path(root, "full.u32"), memory_limit = "1GB")
stopifnot(fit$n_vertices == 1000,
    file.info(fit$membership_path)$size == 4000)
landmark <- massive_cluster(source, method = "leiden",
    massive = "landmark", landmarks = 100L, k = 10L,
    output = file.path(root, "landmark"), backend = "cpu",
    n.cores = 4L, chunk_rows = 500L, memory_limit = "1GB",
    knn_method = "hnsw", seed = 4L)
stopifnot(landmark$nrow == 1000,
    file.info(landmark$membership_path)$size == 4000,
    landmark$assignment_workers == 4L,
    landmark$fitting_cpu_workers == 1L)
unlink(root, recursive = TRUE)
cat("CLUSTER_CPU_SMOKE_PASS\n")
