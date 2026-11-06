args <- commandArgs(trailingOnly = TRUE)
stopifnot(length(args) == 2L)
root <- "/Users/silvanopiazza/Documents/Stefano"
lib <- args[[1L]]
tag <- args[[2L]]
.libPaths(c(lib, file.path(root, "data/Rlib"), .libPaths()))
library(fastEmbedR)
work <- file.path(root, "fastEmbedR-multicpu-reserve-20261105", tag)
dir.create(work, recursive = TRUE, showWarnings = FALSE)
cases <- list(
    low = list(prefix = file.path(root,
        "fastEmbedR-multicpu-batch262k-20261104",
        "benchmark-100k/fuzzy"), n = 100000L, passes = 4L),
    high = list(prefix = file.path(root,
        "fastEmbedR-multicpu-highdegree-20261104",
        "benchmark-50k-k200/fuzzy"), n = 50000L, passes = 2L)
)
results <- data.frame(method = character(), case = character(),
    seconds = numeric(), communities = integer(),
    modularity = numeric(), effective_workers = integer(),
    labels_sha = character())
for (case_name in names(cases)) {
    case <- cases[[case_name]]
    graph <- massive_fuzzy_graph(case$prefix, case$n)
    for (method in c("louvain", "leiden")) {
        output <- file.path(work, paste0(method, "-", case_name,
            ".clusters.u32"))
        start <- proc.time()[[3L]]
        fit <- if (method == "louvain") {
            massive_louvain_level(graph, output,
                max_passes = case$passes, seed = 4L,
                chunk_rows = 4096L, memory_limit = "512MB",
                n.cores = 4L)
        } else {
            massive_leiden(graph, output,
                max_passes = case$passes, seed = 4L,
                chunk_rows = 4096L, memory_limit = "1GB",
                n.cores = 4L)
        }
        elapsed <- unname(proc.time()[[3L]] - start)
        labels <- massive_read_rows(fit, 1L, case$n)
        hash <- digest::digest(labels, algo = "sha256",
            serialize = TRUE)
        results[nrow(results) + 1L, ] <- list(method,
            case_name, elapsed, fit$n_communities,
            fit$modularity_final, fit$cpu_workers_effective,
            hash)
        write.csv(results, file.path(work, "metrics.csv"),
            row.names = FALSE)
        cat("RESULT", tag, method, case_name, elapsed,
            fit$n_communities, fit$modularity_final,
            fit$cpu_workers_effective, hash, "\n")
    }
}
