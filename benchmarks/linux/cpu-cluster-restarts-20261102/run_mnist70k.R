args <- commandArgs(trailingOnly = TRUE)
if (length(args) != 2L) {
    stop("Usage: Rscript run_mnist70k.R KNN_RDS OUTPUT_DIR")
}
knn_path <- normalizePath(args[[1L]], mustWork = TRUE)
output <- args[[2L]]
if (dir.exists(output) && length(list.files(output))) {
    stop("Output directory must be empty.")
}
dir.create(output, recursive = TRUE, showWarnings = FALSE)
library_path <- Sys.getenv("FASTEMBEDR_TEST_LIB")
if (nzchar(library_path)) .libPaths(c(library_path, .libPaths()))
library(fastEmbedR)
stopifnot("n.cores" %in% names(formals(graph_cluster)))
input <- readRDS(knn_path)
graph <- knn_graph(input$knn, k = 15L, weight = "snn",
                   mutual = TRUE)
stopifnot(graph$n_vertices == 70000L, graph$n_edges > 0L)
rows <- list()
for (method in c("leiden", "louvain")) {
    reference <- NULL
    for (order in c("forward", "reverse")) {
        workers <- if (order == "forward") c(1L, 2L, 4L, 8L)
                   else c(8L, 4L, 2L, 1L)
        for (n.cores in workers) {
            timing <- system.time({
                fit <- graph_cluster(graph, method = method,
                    backend = "cpu", n_iterations = 5L,
                    n_runs = 8L, n.cores = n.cores, seed = 17L)
            })
            if (is.null(reference)) {
                reference <- fit$membership
                saveRDS(reference, file.path(output,
                    paste0(method, "_membership.rds")))
            }
            stopifnot(identical(fit$membership, reference),
                is.finite(fit$modularity),
                identical(fit$effective_cpu_workers, n.cores),
                identical(fit$parameters$n.cores, n.cores))
            rows[[length(rows) + 1L]] <- data.frame(
                method = method, order = order, n.cores = n.cores,
                n_runs = 8L, elapsed_sec = unname(timing[[3L]]),
                user_sec = unname(timing[[1L]]),
                system_sec = unname(timing[[2L]]),
                modularity = fit$modularity,
                communities = fit$n_communities,
                edges = graph$n_edges,
                source = knn_path)
            write.csv(do.call(rbind, rows),
                file.path(output, "summary.csv"), row.names = FALSE)
        }
    }
}
