args <- commandArgs(trailingOnly = TRUE)
stopifnot(length(args) == 1L)
.libPaths(c(
    args[[1L]],
    "/Users/silvanopiazza/Documents/Stefano/data/Rlib",
    .libPaths()
))
library(fastEmbedR)
library(cluster)
file <- paste0(
    "/Users/silvanopiazza/Documents/Stefano/data/",
    "data/FashionMNIST_n5000/FashionMNIST_n5000_float32.RData"
)
e <- new.env(parent = emptyenv())
load(file, envir = e)
x <- float::dbl(e$dataset$data)
labels <- as.integer(e$dataset$labels)
init <- umap_init(x, n_neighbors = 30L, backend = "cpu", seed = 711L)
graph <- init$prepared$graph
cfg <- init$parameters
sample_rows <- seq.int(1L, length(labels), by = 5L)
score <- function(layout) as.numeric(summary(silhouette(
    labels[sample_rows],
    dist(as.matrix(layout)[sample_rows, , drop = FALSE])
))$avg.width)
for (seed in c(4L, 17L, 42L)) {
    cpu <- fastEmbedR:::fast_knn_umap_csr_clean_atomic_cpp(
        graph$offsets, graph$neighbors, graph$weights,
        init$layout, 400L, cfg$min_dist,
        cfg$negative_sample_rate, 0.25, 1,
        1L, seed, 0L, FALSE
    )
    for (epochs in c(400L, 600L, 800L, 1200L)) {
        mode <- 1L
        metal <- fastEmbedR:::knn_embed_metal_csr_cpp(
            graph$offsets, graph$neighbors, graph$weights,
            init$layout, epochs, cfg$negative_sample_rate,
            0.25, cfg$min_dist, graph$max_weight,
            1, seed, mode
        )
        cat("seed=", seed, " epochs=", epochs,
            " cpu=", score(cpu), " metal=", score(metal),
            " delta=", score(metal) - score(cpu), "\n", sep = "")
    }
}
cat("RNG_PARITY_FASHION_COMPLETE\n")
