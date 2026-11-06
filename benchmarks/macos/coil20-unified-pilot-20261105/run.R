options(warn = 1)
library(fastEmbedR)
root <- "/Users/silvanopiazza/Documents/Stefano"
work <- file.path(root, "fastEmbedR-coil20-unified-pilot-20261105")
input <- file.path(root, "fastEmbedR-mac-20261031/data/COIL20",
    "COIL20_float32.RData")
set.seed(4)
e <- new.env(parent = emptyenv())
load(input, envir = e)
x <- float::dbl(e$dataset$data)
labels <- e$dataset$labels
stopifnot(identical(dim(x), c(1440L, 16384L)), length(labels) == 1440L)
results <- data.frame(case = character(), seconds = numeric(),
    status = character(), trustworthiness = numeric(),
    label_accuracy = numeric(), ari = numeric(),
    n_groups = integer(), message = character())
record <- function(name, action, quality = FALSE, cluster = FALSE) {
    cat("START", name, format(Sys.time(), tz = "UTC"), "\n")
    start <- proc.time()[[3L]]
    error <- NULL
    fit <- tryCatch(action(), error = function(e) {
        error <<- conditionMessage(e)
        NULL
    })
    seconds <- unname(proc.time()[[3L]] - start)
    trust <- accuracy <- ari <- NA_real_
    groups <- NA_integer_
    if (is.null(error) && quality) {
        metrics <- tryCatch(evaluate_embedding(scores, fit$layout,
            labels = labels, k = 15L, primary_k = 15L,
            sample_size_for_global_metrics = 600L,
            sample_size_for_local_metrics = 600L,
            n.cores = 1L, seed = 4L), error = function(e) {
            error <<- paste("quality:", conditionMessage(e))
            NULL
        })
        if (!is.null(metrics)) {
            trust <- metrics$trustworthiness
            accuracy <- metrics$label_knn_accuracy
        }
    }
    if (is.null(error) && cluster) {
        membership <- fit$membership
        groups <- length(unique(membership))
        ari <- fastEmbedR:::adjusted_rand_index(labels, membership)
    }
    results[nrow(results) + 1L, ] <<- list(name, seconds,
        if (is.null(error)) "ok" else "error", trust, accuracy, ari,
        groups, if (is.null(error)) "" else error)
    write.csv(results, file.path(work, "metrics.csv"), row.names = FALSE)
    if (is.null(error) && !is.null(fit))
        saveRDS(fit, file.path(work, paste0(name, ".rds")),
            compress = "xz")
    cat("END", name, "seconds", seconds,
        if (is.null(error)) "ok" else error, "\n")
    fit
}
cat("fastEmbedR", as.character(packageVersion("fastEmbedR")), "\n")
cat("input", input, "rows", nrow(x), "columns", ncol(x), "\n")
fit_pca <- record("pca_cpu1", function()
    pca(x, ncomp = 30L, backend = "cpu", n.cores = 1L, seed = 4L))
if (is.null(fit_pca)) quit(status = 1L)
scores <- fit_pca$scores
stopifnot(identical(dim(scores), c(1440L, 30L)))
rm(x, fit_pca)
gc()
record("tsne_cpu1_2d", function()
    tsne(scores, perplexity = 30L, n_iter = 300L,
        backend = "cpu", n.cores = 1L, seed = 4L), quality = TRUE)
record("tsne_metal_2d", function()
    tsne(scores, perplexity = 30L, n_iter = 300L,
        backend = "metal", seed = 4L), quality = TRUE)
record("umap_cpu1_2d", function()
    umap(scores, n_neighbors = 30L, backend = "cpu",
        n.cores = 1L, seed = 4L), quality = TRUE)
record("umap_cpu4_2d", function()
    umap(scores, n_neighbors = 30L, backend = "cpu",
        n.cores = 4L, seed = 4L), quality = TRUE)
record("umap_metal_2d", function()
    umap(scores, n_neighbors = 30L, backend = "metal",
        seed = 4L), quality = TRUE)
graph <- knn_graph(scores, k = 30L, backend = "cpu",
    n.cores = 1L)
record("louvain_cpu1", function()
    graph_cluster(graph, method = "louvain", backend = "cpu",
        n.cores = 1L, seed = 4L), cluster = TRUE)
record("louvain_cpu4", function()
    graph_cluster(graph, method = "louvain", backend = "cpu",
        n.cores = 4L, parallel.mode = "fit", seed = 4L), cluster = TRUE)
record("louvain_metal", function()
    graph_cluster(graph, method = "louvain", backend = "metal",
        seed = 4L), cluster = TRUE)
record("leiden_cpu1", function()
    graph_cluster(graph, method = "leiden", backend = "cpu",
        n.cores = 1L, seed = 4L), cluster = TRUE)
record("leiden_cpu4", function()
    graph_cluster(graph, method = "leiden", backend = "cpu",
        n.cores = 4L, parallel.mode = "fit", seed = 4L), cluster = TRUE)
record("leiden_metal", function()
    graph_cluster(graph, method = "leiden", backend = "metal",
        seed = 4L), cluster = TRUE)
if (any(results$status != "ok")) quit(status = 2L)
