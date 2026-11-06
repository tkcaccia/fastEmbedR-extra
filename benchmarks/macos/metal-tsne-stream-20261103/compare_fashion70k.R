#!/usr/bin/env Rscript
suppressPackageStartupMessages(library(fastEmbedR))

probe <- function() {
args <- commandArgs(trailingOnly = TRUE)
stopifnot(length(args) == 1L, dir.exists(args[[1L]]))
root <- tempfile("metal-tsne-stream70k-", tmpdir = args[[1L]])
dir.create(root)
on.exit(unlink(root, recursive = TRUE), add = TRUE)
setTimeLimit(elapsed = 300, transient = FALSE)

prefix <- paste0(
    "/Users/silvanopiazza/Documents/Stefano/data/results/",
    "fashion70k-metal-exact-knn-v1/knn")
source <- massive_knn_graph(prefix, 70000L, 30L)
graph <- massive_tsne_affinities(source, perplexity = 10,
    output = file.path(root, "affinity"), memory_limit = "256MB")
set.seed(17)
initial <- matrix(rnorm(70000L * 3L, sd = 0.0001), 70000L, 3L)
init_path <- file.path(root, "init.f32")
writeBin(as.numeric(t(initial)), init_path,
    size = 4L, endian = "little")
start <- massive_matrix(init_path, 70000L, 3L)
cat("input_md5", paste(unname(tools::md5sum(c(
    graph$offsets_path, graph$indices_path,
    graph$weights_path, init_path))), collapse = ","), "\n")

run_fit <- function(mode) {
    output <- file.path(root, paste0(mode, ".f32"))
    elapsed <- system.time({
        fit <- massive_tsne_optimize(graph, start, output,
            early_exaggeration_iter = 2L, n_iter = 3L,
            memory_limit = "2GB", backend = "metal",
            graph_access = mode, edge_chunk_capacity = 65536L)
    })[["elapsed"]]
    cat("fit", mode, "seconds", elapsed, "backend", fit$backend,
        "access", fit$resources$graph_access, "md5",
        unname(tools::md5sum(output)), "\n")
    massive_read_rows(fit, 1L, 70000L)
}

mapped <- run_fit("mmap")
streamed <- run_fit("stream")
stopifnot(all(is.finite(streamed)))
delta <- streamed - mapped
cat("max_abs_difference", max(abs(delta)), "\n")
stopifnot(identical(mapped, streamed))
}
probe()
