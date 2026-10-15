#!/usr/bin/env Rscript

args <- commandArgs(trailingOnly = TRUE)
if (length(args) != 2L) stop("Usage: SCRIPT PACKAGE_LIBRARY OUTPUT_CSV")
library(fastEmbedR, lib.loc = args[[1L]])

agreement <- function(a, b) {
    counts <- table(a, b)
    pairs <- function(z) sum(z * (z - 1) / 2)
    shared <- pairs(counts)
    rows <- pairs(rowSums(counts))
    cols <- pairs(colSums(counts))
    expected <- rows * cols / choose(length(a), 2)
    (shared - expected) / ((rows + cols) / 2 - expected)
}

run_case <- function(x, truth, order_name, width) {
    directory <- tempfile("walktrap-order-")
    dir.create(directory)
    on.exit(unlink(directory, recursive = TRUE))
    n <- nrow(x)
    knn <- massive_full_knn_graph(massive_matrix(x), k = 15L,
        output = file.path(directory, "knn"), backend = "cpu",
        chunk_rows = 128L, memory_limit = "256MB")
    directed <- massive_umap_memberships(knn)
    graph <- massive_umap_fuzzy_graph(directed,
        file.path(directory, "fuzzy"), memory_limit = "256MB")
    edges <- massive_read_graph_edges(graph, 1L, n)
    keep <- edges$from < edges$to
    resident <- list(from = edges$from[keep], to = edges$to[keep],
        weight = edges$weight[keep], n_vertices = n)
    started <- proc.time()[[3L]]
    exact <- graph_cluster(resident, method = "walktrap", backend = "cpu")
    exact_seconds <- proc.time()[[3L]] - started
    started <- proc.time()[[3L]]
    fit <- tryCatch(massive_walktrap(graph,
        file.path(directory, "part.u32"), chunk_rows = width,
        memory_limit = "256MB"), error = identity)
    part_seconds <- proc.time()[[3L]] - started
    if (inherits(fit, "error")) return(data.frame(
        order = order_name, width = width, status = "failed",
        message = conditionMessage(fit), exact_seconds = exact_seconds,
        part_seconds = part_seconds))
    labels <- massive_read_walktrap_rows(fit, 1L, n)
    exact_path <- file.path(directory, "exact.u32")
    writeBin(as.integer(exact$membership), exact_path,
        size = 4L, endian = "little")
    exact_modularity <- massive_graph_modularity(graph, exact_path,
        exact$n_communities, memory_limit = "256MB")$modularity
    data.frame(order = order_name, width = width, status = "ok",
        message = "", exact_seconds = exact_seconds,
        part_seconds = part_seconds, exact_modularity = exact_modularity,
        part_modularity = fit$modularity_final,
        ari_vs_exact = agreement(exact$membership, labels),
        ari_vs_truth = agreement(truth, labels),
        exact_communities = exact$n_communities,
        part_communities = fit$n_communities,
        retained_weight_fraction = fit$initial_retained_weight_fraction,
        initial_blocks = fit$levels[[1L]]$blocks,
        hierarchy_levels = length(fit$levels))
}

set.seed(141)
truth <- rep(seq_len(3L), each = 200L)
x <- matrix(rnorm(600L * 8L, sd = 0.7), ncol = 8L)
x[, 1L] <- x[, 1L] + (truth - 1L) * 3
shuffled <- sample.int(nrow(x))
results <- list()
for (width in c(100L, 200L)) {
    results[[length(results) + 1L]] <- run_case(x, truth, "ordered", width)
    results[[length(results) + 1L]] <- run_case(x[shuffled, , drop = FALSE],
        truth[shuffled], "shuffled", width)
}
out <- do.call(rbind, results)
write.csv(out, args[[2L]], row.names = FALSE)
print(out)
