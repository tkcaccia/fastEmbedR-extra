args <- commandArgs(trailingOnly = TRUE)
if (length(args) != 5L) {
    stop("Usage: Rscript run_mnist_graph_options.R BACKEND METHOD ",
         "KNN_RDS LAYOUT_RDATA OUTPUT_DIR")
}
backend <- match.arg(args[[1L]], c("cpu", "cuda"))
method <- match.arg(args[[2L]], c("leiden", "louvain"))
knn_path <- normalizePath(args[[3L]], mustWork = TRUE)
layout_path <- normalizePath(args[[4L]], mustWork = TRUE)
output <- normalizePath(args[[5L]], mustWork = TRUE)
if (length(list.files(output, all.files = TRUE, no.. = TRUE))) {
    stop("Output directory must be empty.")
}
expected_lib <- Sys.getenv("FASTEMBEDR_CANDIDATE_LIB")
if (!nzchar(expected_lib) || !dir.exists(expected_lib)) {
    stop("Set FASTEMBEDR_CANDIDATE_LIB to the isolated package library.")
}
.libPaths(c(expected_lib, .libPaths()))
if (!requireNamespace("fastEmbedR", quietly = TRUE)) {
    stop("The isolated fastEmbedR candidate is unavailable.")
}
library(fastEmbedR)
if (!nzchar(expected_lib) ||
    !startsWith(find.package("fastEmbedR"), expected_lib)) {
    stop("fastEmbedR did not load from the isolated candidate library.")
}
if (backend == "cuda" &&
    !fastEmbedR:::graph_clustering_cuda_available_cpp()) {
    stop("CUDA clustering is unavailable; no fallback permitted.")
}

choose2 <- function(x) x * (x - 1) / 2
or_else <- function(x, y) if (is.null(x)) y else x
adjusted_rand <- function(x, y) {
    counts <- table(x, y)
    pairs <- choose2(sum(counts))
    same <- sum(choose2(counts))
    rows <- sum(choose2(rowSums(counts)))
    cols <- sum(choose2(colSums(counts)))
    expected <- rows * cols / pairs
    (same - expected) / ((rows + cols) / 2 - expected)
}

input <- readRDS(knn_path)
nn <- input$knn
env <- new.env(parent = emptyenv())
load(layout_path, envir = env)
layout <- env$pca_init$layout
labels <- env$pca_init$labels
stopifnot(identical(dim(nn$indices), c(70000L, 15L)),
          identical(dim(layout), c(70000L, 2L)),
          length(labels) == 70000L)
graph_time <- system.time({
    graph <- knn_graph(nn, k = 15L, weight = "snn", mutual = TRUE)
})
fit_time <- system.time({
    fit <- graph_cluster(graph, method = method, backend = backend,
        resolution = c(0.5, 1), seed = c(1L, 2L),
        n_iterations = 5L, projection = list(layout = layout, k = 15L),
        small_groups = list(knn = nn, min_size = 20L))
})
stopifnot(identical(fit$backend, backend),
          identical(length(fit$membership), 70000L),
          all(is.finite(fit$membership)),
          identical(fit$parameters$processing_order,
              c("consensus", "projection", "clustering", "small_groups")))
summary <- data.frame(
    dataset = "MNIST70k", method = method, backend = backend,
    n = graph$n_vertices, graph_edges = graph$n_edges,
    weighted_edges = fit$parameters$weighted_edges,
    graph_elapsed_sec = unname(graph_time[["elapsed"]]),
    fit_elapsed_sec = unname(fit_time[["elapsed"]]),
    modularity = fit$modularity,
    communities = fit$n_communities,
    unassigned = length(fit$unassigned),
    ari_labels = adjusted_rand(fit$membership, labels),
    implementation = fit$implementation,
    consensus_implementation = fit$parameters$consensus$implementation,
    projection_execution = or_else(
        fit$parameters$projection$execution, "cpu"),
    small_groups_execution =
        or_else(fit$parameters$small_groups$execution, "cpu"),
    package_path = find.package("fastEmbedR"),
    stringsAsFactors = FALSE)
write.csv(summary, file.path(output, "summary.csv.tmp"),
          row.names = FALSE)
saveRDS(fit, file.path(output, "fit.rds.tmp"))
if (!file.rename(file.path(output, "fit.rds.tmp"),
                 file.path(output, "fit.rds")) ||
    !file.rename(file.path(output, "summary.csv.tmp"),
                 file.path(output, "summary.csv"))) {
    stop("Could not finalize benchmark outputs.")
}
print(summary)
