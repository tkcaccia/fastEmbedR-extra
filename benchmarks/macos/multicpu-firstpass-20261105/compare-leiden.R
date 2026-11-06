args <- commandArgs(trailingOnly = TRUE)
stopifnot(length(args) == 2L)
root <- "/Users/silvanopiazza/Documents/Stefano"
.libPaths(c(args[[1L]], file.path(root, "data/Rlib"), .libPaths()))
library(fastEmbedR)
tag <- args[[2L]]
work <- file.path(root, "fastembedr-louvain-firstpass-20261105", tag)
dir.create(work, recursive = TRUE, showWarnings = FALSE)
graph <- massive_fuzzy_graph(file.path(root,
    "fastEmbedR-multicpu-batch262k-20261104",
    "benchmark-100k/fuzzy"), 100000L)
for (cores in c(1L, 4L)) {
    output <- file.path(work,
        paste0("leiden-cpu", cores, ".clusters.u32"))
    start <- proc.time()[[3L]]
    fit <- massive_leiden(graph, output,
        max_passes = 4L, seed = 4L, chunk_rows = 4096L,
        memory_limit = "1GB", n.cores = cores)
    elapsed <- unname(proc.time()[[3L]] - start)
    labels <- massive_read_rows(fit, 1L, 100000L)
    hash <- digest::digest(labels, algo = "sha256", serialize = TRUE)
    cat("RESULT", tag, cores, elapsed, fit$n_communities,
        fit$modularity_final, fit$cpu_workers_effective, hash, "\n")
}
