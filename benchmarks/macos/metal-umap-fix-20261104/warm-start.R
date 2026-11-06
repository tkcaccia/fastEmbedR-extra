args <- commandArgs(trailingOnly = TRUE)
stopifnot(length(args) == 1L)
.libPaths(c(args[[1L]], "/Users/silvanopiazza/Documents/Stefano/data/Rlib",
            .libPaths()))
library(fastEmbedR)
library(cluster)
e <- new.env(parent = emptyenv())
load(paste0("/Users/silvanopiazza/Documents/Stefano/data/data/",
            "FashionMNIST_n5000/FashionMNIST_n5000_float32.RData"),
     envir = e)
x <- float::dbl(e$dataset$data)
labels <- as.integer(e$dataset$labels)
init <- umap_init(x, n_neighbors = 30L, backend = "cpu", seed = 711L)
graph <- init$prepared$graph
cfg <- init$parameters
sample_rows <- seq.int(1L, length(labels), by = 5L)
score <- function(layout) as.numeric(summary(silhouette(
    labels[sample_rows], dist(as.matrix(layout)[sample_rows, , drop = FALSE])
))$avg.width)
cpu_fit <- function(start, epochs, seed) {
    fastEmbedR:::fast_knn_umap_csr_clean_atomic_cpp(
        graph$offsets, graph$neighbors, graph$weights,
        start, epochs, cfg$min_dist, cfg$negative_sample_rate,
        0.25, 1, 1L, seed, 0L, FALSE)
}
metal_fit <- function(start, epochs, seed) {
    fastEmbedR:::knn_embed_metal_csr_cpp(
        graph$offsets, graph$neighbors, graph$weights,
        start, epochs, cfg$negative_sample_rate, 0.25,
        cfg$min_dist, graph$max_weight, 1, seed, 1L)
}
for (seed in c(4L, 17L, 42L)) {
    cpu <- cpu_fit(init$layout, 400L, seed)
    cat("BASE", seed, score(cpu), "\n")
    for (warm_epochs in c(100L, 200L)) {
        a <- proc.time()[[3L]]
        warm <- cpu_fit(init$layout, warm_epochs, seed)
        warm_sec <- proc.time()[[3L]] - a
        for (metal_epochs in c(200L, 400L)) {
            b <- proc.time()[[3L]]
            metal <- metal_fit(warm, metal_epochs, seed)
            metal_sec <- proc.time()[[3L]] - b
            cat("HYBRID", seed, warm_epochs, metal_epochs,
                score(warm), score(metal), warm_sec, metal_sec, "\n")
        }
    }
}
