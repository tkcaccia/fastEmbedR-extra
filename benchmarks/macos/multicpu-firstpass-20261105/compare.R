args <- commandArgs(trailingOnly = TRUE)
stopifnot(length(args) == 2L)
root <- "/Users/silvanopiazza/Documents/Stefano"
.libPaths(c(args[[1L]], file.path(root, "data/Rlib"), .libPaths()))
library(fastEmbedR)
tag <- args[[2L]]
work <- file.path(root, "fastembedr-louvain-firstpass-20261105", tag)
dir.create(work, recursive = TRUE, showWarnings = FALSE)
cases <- list(
    low = list(prefix = file.path(root,
        "fastEmbedR-multicpu-batch262k-20261104",
        "benchmark-100k/fuzzy"), n = 100000L, passes = 4L),
    high = list(prefix = file.path(root,
        "fastEmbedR-multicpu-highdegree-20261104",
        "benchmark-50k-k200/fuzzy"), n = 50000L, passes = 2L)
)
results <- data.frame(case = character(), cores = integer(),
    seconds = numeric(), communities = integer(),
    modularity = numeric(), moves = numeric(),
    effective_workers = integer(), labels_sha = character())
for (case_name in names(cases)) {
    case <- cases[[case_name]]
    graph <- massive_fuzzy_graph(case$prefix, case$n)
    for (cores in c(1L, 4L)) {
        output <- file.path(work,
            paste0(case_name, "-cpu", cores, ".clusters.u32"))
        start <- proc.time()[[3L]]
        fit <- massive_louvain_level(graph, output,
            max_passes = case$passes, seed = 4L,
            chunk_rows = 4096L, memory_limit = "512MB",
            n.cores = cores)
        seconds <- unname(proc.time()[[3L]] - start)
        labels <- massive_read_rows(fit, 1L, case$n)
        label_hash <- digest::digest(labels, algo = "sha256",
            serialize = TRUE)
        results[nrow(results) + 1L, ] <- list(case_name, cores,
            seconds, fit$n_communities, fit$modularity_final,
            fit$moves, fit$cpu_workers_effective, label_hash)
        write.csv(results, file.path(work, "metrics.csv"),
            row.names = FALSE)
        cat("RESULT", tag, case_name, cores, seconds,
            fit$n_communities, fit$modularity_final,
            fit$moves, fit$cpu_workers_effective,
            label_hash, "\n")
    }
    group <- results[results$case == case_name, ]
    stopifnot(length(unique(group$labels_sha)) == 1L)
}
