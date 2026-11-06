root <- "/Users/silvanopiazza/Documents/Stefano"
work <- file.path(root, "fastEmbedR-multicpu-scaling-20261105")
.libPaths(c(file.path(root, "fastEmbedR-auto-route-20261105",
    "library"), file.path(root, "data/Rlib"), .libPaths()))
library(fastEmbedR)
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
    cores = integer(), seconds = numeric(),
    communities = integer(), modularity = numeric(),
    moves = numeric(), effective_workers = integer(),
    labels_sha = character())
prior <- file.path(work, "metrics.csv")
if (file.exists(prior)) results <- read.csv(prior,
    stringsAsFactors = FALSE)
for (case_name in names(cases)) {
    case <- cases[[case_name]]
    graph <- massive_fuzzy_graph(case$prefix, case$n)
    for (method in c("louvain", "leiden")) {
        for (cores in c(1L, 2L, 4L, 8L, 16L)) {
            if (any(results$method == method &
                    results$case == case_name &
                    results$cores == cores)) next
            output <- file.path(work, paste0(method, "-", case_name,
                "-cpu", cores, "-v2.clusters.u32"))
            start <- proc.time()[[3L]]
            fit <- if (method == "louvain") {
                massive_louvain_level(graph, output,
                    max_passes = case$passes, seed = 4L,
                    chunk_rows = 4096L, memory_limit = "512MB",
                    n.cores = cores)
            } else {
                massive_leiden(graph, output,
                    max_passes = case$passes, seed = 4L,
                    chunk_rows = 4096L, memory_limit = "1GB",
                    n.cores = cores)
            }
            elapsed <- unname(proc.time()[[3L]] - start)
            labels <- massive_read_rows(fit, 1L, case$n)
            hash <- digest::digest(labels, algo = "sha256",
                serialize = TRUE)
            moves <- if (is.null(fit$moves)) NA_real_ else fit$moves
            results[nrow(results) + 1L, ] <- list(method,
                case_name, cores, elapsed, fit$n_communities,
                fit$modularity_final, moves,
                fit$cpu_workers_effective, hash)
            write.csv(results, file.path(work, "metrics_v2.csv"),
                row.names = FALSE)
            cat("RESULT", method, case_name, cores, elapsed,
                fit$n_communities, fit$modularity_final,
                fit$cpu_workers_effective, hash, "\n")
        }
        group <- results[results$case == case_name &
            results$method == method, ]
        stopifnot(length(unique(group$labels_sha)) == 1L)
    }
}
