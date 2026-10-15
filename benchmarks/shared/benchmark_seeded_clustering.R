#!/usr/bin/env Rscript

args <- commandArgs(trailingOnly = TRUE)
if (length(args) != 4L) stop(paste(
    "Usage: benchmark_seeded_clustering.R PCA_F32 FUZZY_PREFIX",
    "OUTPUT_DIR PACKAGE_SOURCE"))
source_file <- normalizePath(args[[1L]], mustWork = TRUE)
graph_prefix <- file.path(normalizePath(dirname(args[[2L]]),
    mustWork = TRUE), basename(args[[2L]]))
output <- file.path(normalizePath(dirname(args[[3L]]),
    mustWork = TRUE), basename(args[[3L]]))
package_source <- normalizePath(args[[4L]], mustWork = TRUE)
if (file.exists(output) || !dir.create(output, recursive = TRUE)) {
    stop("Output directory must be new.")
}
setwd(package_source)
pkgload::load_all(package_source, quiet = TRUE)
if (file.info(source_file)$size != 70000 * 30 * 4) {
    stop("Expected the complete 70,000 by 30 float32 PCA matrix.")
}
source <- massive_matrix(source_file, nrow = 70000, ncol = 30)
graph <- massive_fuzzy_graph(graph_prefix, n_vertices = 70000)
if (graph$n_edges != 2949906) stop("Unexpected fuzzy graph identity.")
stamp <- function(expr) {
    start <- proc.time()[[3L]]
    value <- force(expr)
    list(value = value, seconds = unname(proc.time()[[3L]] - start))
}
agreement <- function(a, b) {
    counts <- table(a, b)
    pairs <- function(x) sum(x * (x - 1) / 2)
    shared <- pairs(counts)
    row_pairs <- pairs(rowSums(counts))
    col_pairs <- pairs(colSums(counts))
    total <- choose(length(a), 2)
    expected <- row_pairs * col_pairs / total
    (shared - expected) / ((row_pairs + col_pairs) / 2 - expected)
}
selection <- stamp(massive_select_landmarks(source, 2000L,
    file.path(output, "landmarks.f32"), seed = 4L,
    chunk_rows = 4096L, memory_limit = "512MB"))
neighbors <- stamp(massive_landmark_knn(source, selection$value,
    k = 15L, output = file.path(output, "landmark_knn"),
    method = "hnsw", backend = "cpu", n.cores = 4L,
    chunk_rows = 4096L, memory_limit = "512MB"))
reference <- massive_read_rows(selection$value$data, 1L, 2000L)
reference_graph <- knn_graph(reference, k = 15L,
    backend = "cpu", n.cores = 4L)
records <- lapply(c("louvain", "leiden"), function(method) {
    initial <- stamp(massive_cluster_landmarks(reference_graph,
        neighbors$value, file.path(output, paste0(method, "_landmark")),
        method = method, selection = selection$value,
        backend = "cpu", n.cores = 4L, chunk_rows = 4096L,
        memory_limit = "512MB", seed = 4L))
    baseline <- stamp(massive_cluster(graph, method = method,
        massive = "out_of_core_graph",
        output = file.path(output, paste0(method, "_baseline.u32")),
        backend = "cpu", n.cores = 1L, chunk_rows = 8192L,
        memory_limit = "512MB", seed = 4L))
    seeded <- stamp(massive_cluster(graph, method = method,
        massive = "out_of_core_graph",
        output = file.path(output, paste0(method, "_seeded.u32")),
        initial = initial$value, backend = "cpu", n.cores = 1L,
        chunk_rows = 8192L, memory_limit = "512MB", seed = 4L))
    first <- massive_read_cluster_rows(initial$value, 1L, 70000L)$membership
    a <- readBin(baseline$value$membership_path, integer(),
        n = 70000L, size = 4L, endian = "little")
    b <- readBin(seeded$value$membership_path, integer(),
        n = 70000L, size = 4L, endian = "little")
    before <- massive_graph_modularity(graph,
        initial$value$membership_path, initial$value$n_communities,
        memory_limit = "512MB")$modularity
    if (length(a) != 70000L || length(b) != 70000L ||
        abs(seeded$value$modularity_final -
            massive_graph_modularity(graph,
                seeded$value$membership_path,
                seeded$value$n_communities,
                memory_limit = "512MB")$modularity) > 1e-6) {
        stop("Seeded full-graph result failed independent validation.")
    }
    data.frame(method = method,
        rows = graph$n_vertices, edges = graph$n_edges,
        landmark_count = 2000L, search_method = "hnsw",
        landmark_seconds = initial$seconds,
        baseline_seconds = baseline$seconds,
        seeded_seconds = seeded$seconds,
        landmark_modularity = before,
        baseline_modularity = baseline$value$modularity_final,
        seeded_modularity = seeded$value$modularity_final,
        baseline_communities = baseline$value$n_communities,
        seeded_communities = seeded$value$n_communities,
        landmark_to_seeded_ari = agreement(first, b),
        baseline_to_seeded_ari = agreement(a, b))
})
result <- do.call(rbind, records)
result$selection_seconds <- selection$seconds
result$knn_seconds <- neighbors$seconds
result$package_version <- as.character(packageVersion("fastEmbedR"))
result$source_commit <- system2("git", c("rev-parse", "HEAD"),
    stdout = TRUE)
result$source_dirty <- length(system2("git", c("status", "--porcelain"),
    stdout = TRUE)) > 0L
result$pca_md5 <- unname(tools::md5sum(source_file))
result$graph_offsets_md5 <- unname(tools::md5sum(paste0(
    graph_prefix, ".offsets.u64")))
result$dll_md5 <- unname(tools::md5sum(
    getLoadedDLLs()[["fastEmbedR"]][["path"]]))
write.csv(result, file.path(output, "summary.csv"), row.names = FALSE)
print(result)
