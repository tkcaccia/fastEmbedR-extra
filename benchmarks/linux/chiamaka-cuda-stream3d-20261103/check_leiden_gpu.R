args <- commandArgs(trailingOnly = TRUE)
stopifnot(length(args) == 1L)
root <- args[[1L]]
.libPaths(c(file.path(root, "library"), .libPaths()))
suppressPackageStartupMessages(library(fastEmbedR))
pairs <- rbind(t(combn(1:4, 2L)), t(combn(5:8, 2L)))
resident <- list(from = as.integer(pairs[, 1L]),
    to = as.integer(pairs[, 2L]),
    weight = rep(1, nrow(pairs)), n_vertices = 8L)
for (method in c("louvain", "leiden")) {
    fit <- graph_cluster(resident, method = method,
        backend = "cuda", n_iterations = 4L, seed = 4L)
    stopifnot(identical(fit$backend, "cuda"),
        identical(fit$n_communities, 2L),
        is.finite(fit$modularity))
}
cat("CUDA_RESIDENT_GRAPH_CLUSTER_PASS\n")
run_file <- function() {
work <- tempfile("cuda-leiden-", tmpdir = root)
dir.create(work)
on.exit(unlink(work, recursive = TRUE))
source <- file.path(work, "knn")
fuzzy <- file.path(work, "fuzzy")
neighbors <- t(vapply(seq_len(8L), function(row) {
    setdiff(if (row <= 4L) 1:4 else 5:8, row)
}, integer(3L)))
distances <- matrix(rep(c(0.1, 0.3, 0.7), 8L),
    nrow = 8L, byrow = TRUE)
writeBin(as.integer(t(neighbors)), paste0(source,
    ".indices.u32"), size = 4L, endian = "little")
writeBin(as.numeric(t(distances)), paste0(source,
    ".distances.f32"), size = 4L, endian = "little")
knn <- massive_knn_graph(source, 8L, 3L)
directed <- massive_umap_memberships(knn)
graph <- massive_umap_fuzzy_graph(directed, fuzzy,
    memory_limit = "64MB")
parent <- massive_louvain_level(graph,
    file.path(work, "parent.u32"), backend = "cuda",
    seed = 4L, chunk_rows = 2L, memory_limit = "128MB")
stopifnot(identical(parent$backend, "cuda"),
    identical(parent$n_communities, 2L))
cat("CUDA_LOUVAIN_LEVEL_PASS\n")
refined <- massive_leiden_refine_level(graph, parent,
    file.path(work, "refined.u32"), backend = "cuda",
    seed = 4L, chunk_rows = 2L, memory_limit = "128MB")
stopifnot(identical(refined$backend, "cuda"),
    refined$n_refined >= parent$n_communities,
    identical(refined$n_parent, parent$n_communities))
score <- massive_graph_modularity(graph,
    refined$membership_path, refined$n_refined,
    chunk_rows = 2L, memory_limit = "128MB",
    connectivity = TRUE)
stopifnot(identical(score$disconnected_communities, 0L))
cat("CUDA_LEIDEN_REFINEMENT_PASS\n")
full <- massive_leiden(graph, file.path(work, "full.u32"),
    backend = "cuda", seed = 4L, chunk_rows = 2L,
    memory_limit = "128MB")
stopifnot(identical(full$backend, "cuda"),
    full$n_communities >= 2L,
    length(full$gpu_identity) == 1L)
cat("CUDA_STREAMING_LEIDEN_FULL_PASS\n")
}
run_file()
