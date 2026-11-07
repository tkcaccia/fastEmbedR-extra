#!/usr/bin/env Rscript

args <- commandArgs(trailingOnly = TRUE)
root <- "/Users/silvanopiazza/Documents/Stefano"
inside <- function(path) startsWith(normalizePath(path), paste0(root, "/"))
if (length(args) != 5L || !dir.exists(args[[1L]]) ||
        !dir.exists(args[[2L]]) ||
        any(!vapply(args[1:2], inside, FALSE)) ||
        any(!vapply(dirname(args[3:4]), dir.exists, FALSE)) ||
        any(!vapply(dirname(args[3:4]), inside, FALSE)) ||
        !grepl("^[0-9a-f]{32}$", args[[5L]])) {
    stop("Need Stefano library/output/graphs and expected native MD5.")
}
.libPaths(c(args[[1L]], file.path(root, "data/Rlib"), .libPaths()))
library(fastEmbedR)
setTimeLimit(elapsed = 1800, transient = FALSE)

work <- args[[2L]]
cases <- list(
    low = list(prefix = args[[3L]], n = 100000L, passes = 4L),
    high = list(prefix = args[[4L]], n = 50000L, passes = 2L))
result_file <- file.path(work, "results.csv")
if (file.exists(result_file)) stop("Result CSV already exists.")
package_dll <- getLoadedDLLs()[["fastEmbedR"]][["path"]]
package_md5 <- unname(tools::md5sum(package_dll))
stopifnot(identical(package_md5, args[[5L]]))

fit_one <- function(graph, method, case, cores, repetition, name) {
    output <- file.path(work, paste0(name, "-", method, "-cpu",
        cores, "-r", repetition, ".clusters.u32"))
    if (file.exists(output)) stop("Cluster output already exists.")
    started <- proc.time()[[3L]]
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
    seconds <- unname(proc.time()[[3L]] - started)
    labels <- massive_read_rows(fit, 1L, case$n)
    data.frame(graph = name, method = method, cores = cores,
        repetition = repetition, seconds = seconds,
        effective_workers = fit$cpu_workers_effective,
        communities = fit$n_communities,
        modularity = fit$modularity_final,
        labels_sha256 = digest::digest(labels, algo = "sha256",
            serialize = TRUE), package_dll_md5 = package_md5)
}

results <- data.frame()
for (name in names(cases)) {
    case <- cases[[name]]
    graph <- massive_fuzzy_graph(case$prefix, case$n)
    for (method in c("louvain", "leiden")) {
        for (cores in c(1L, 2L, 4L, 8L, 16L)) {
            for (repetition in seq_len(3L)) {
                row <- fit_one(graph, method, case, cores,
                    repetition, name)
                results <- rbind(results, row)
                utils::write.csv(results, result_file,
                    row.names = FALSE)
                cat("RESULT", name, method, cores,
                    repetition, row$seconds, row$labels_sha256, "\n")
            }
        }
        group <- results[results$graph == name &
            results$method == method, ]
        stopifnot(length(unique(group$labels_sha256)) == 1L,
            length(unique(group$communities)) == 1L,
            length(unique(group$modularity)) == 1L)
    }
}
stopifnot(nrow(results) == 60L)
cat("MULTICPU_BATCHCAP_PARITY_COMPLETE\n")
