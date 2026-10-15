#!/usr/bin/env Rscript

args <- commandArgs(trailingOnly = TRUE)
if (length(args) != 2L) stop("Usage: SCRIPT PACKAGE_LIBRARY OUTPUT_CSV")
library(fastEmbedR, lib.loc = args[[1L]])
output <- args[[2L]]
set.seed(141)
labels <- rep(seq_len(3L), each = 120L)
x <- matrix(rnorm(360L * 8L, sd = 0.7), ncol = 8L)
x[, 1L] <- x[, 1L] + (labels - 1L) * 3
order <- sample.int(nrow(x))
x <- x[order, , drop = FALSE]
truth <- labels[order]
n <- nrow(x)
scratch <- tempfile("walktrap-")
dir.create(scratch)
source <- massive_matrix(x)
knn <- massive_full_knn_graph(source, k = 15L,
    output = file.path(scratch, "knn"), backend = "cpu",
    chunk_rows = 128L, memory_limit = "256MB")
directed <- massive_umap_memberships(knn)
disk_graph <- massive_umap_fuzzy_graph(directed,
    file.path(scratch, "fuzzy"), memory_limit = "256MB")
edges <- massive_read_graph_edges(disk_graph, 1L, n)
keep <- edges$from < edges$to
graph <- list(from = edges$from[keep], to = edges$to[keep],
    weight = edges$weight[keep], n_vertices = n)

agreement <- function(a, b) {
    counts <- table(a, b)
    pairs <- function(z) sum(z * (z - 1) / 2)
    shared <- pairs(counts)
    rows <- pairs(rowSums(counts))
    cols <- pairs(colSums(counts))
    expected <- rows * cols / choose(length(a), 2)
    (shared - expected) / ((rows + cols) / 2 - expected)
}

modularity <- function(membership) {
    w <- graph$weight
    degree <- numeric(n)
    for (i in seq_along(w)) {
        degree[graph$from[[i]]] <- degree[graph$from[[i]]] + w[[i]]
        degree[graph$to[[i]]] <- degree[graph$to[[i]]] + w[[i]]
    }
    volume <- tapply(degree, membership, sum)
    sum(w[membership[graph$from] == membership[graph$to]]) /
        sum(w) - sum((volume / (2 * sum(w)))^2)
}

start <- proc.time()[[3L]]
reference <- graph_cluster(graph, method = "walktrap", backend = "cpu")
reference_seconds <- proc.time()[[3L]] - start

partitioned <- function(width) {
    start <- proc.time()[[3L]]
    fit <- massive_walktrap(disk_graph,
        file.path(scratch, paste0("walktrap-", width, ".u32")),
        chunk_rows = width, memory_limit = "256MB")
    elapsed <- proc.time()[[3L]] - start
    final <- massive_read_walktrap_rows(fit, 1L, n)
    data.frame(width = width, blocks = ceiling(n / width),
        full_seconds = reference_seconds,
        partition_seconds = elapsed,
        full_communities = reference$n_communities,
        result_communities = fit$n_communities,
        full_modularity = modularity(reference$membership),
        result_modularity = fit$modularity_final,
        ari_vs_full = agreement(reference$membership, final),
        ari_vs_truth = agreement(truth, final))
}

result <- do.call(rbind, lapply(c(60L, 120L, 180L), partitioned))
write.csv(result, output, row.names = FALSE)
print(result)
unlink(scratch, recursive = TRUE)
