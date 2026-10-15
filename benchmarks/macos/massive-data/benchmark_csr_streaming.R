#!/usr/bin/env Rscript

args <- commandArgs(trailingOnly = TRUE)
if (length(args) != 5L) stop(
    "Usage: benchmark_csr_streaming.R LIB GRAPH_PREFIX N INIT OUT"
)
library_path <- normalizePath(args[[1L]], mustWork = TRUE)
graph_prefix <- args[[2L]]
n <- as.integer(args[[3L]])
init_path <- normalizePath(args[[4L]], mustWork = TRUE)
output <- args[[5L]]
.libPaths(c(library_path, .libPaths()))
library(fastEmbedR)
graph <- massive_affinity_graph(graph_prefix, n, access = "stream")
init <- massive_matrix(init_path, n, 2L)
started <- proc.time()[[3L]]
fit <- massive_tsne_optimize(graph, init, output,
    early_exaggeration_iter = 0L, n_iter = 5L,
    learning_rate = 1, n.cores = 1L, memory_limit = "2GB")
elapsed <- unname(proc.time()[[3L]] - started)
cat("version=", as.character(packageVersion("fastEmbedR")), "\n",
    "rows=", n, "\n", "edges=", graph$n_edges, "\n",
    "elapsed_seconds=", elapsed, "\n",
    "output_md5=", unname(tools::md5sum(output)), "\n",
    "optimizer=", fit$optimizer, "\n", sep = "")
