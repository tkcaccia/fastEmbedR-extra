args <- commandArgs(trailingOnly = TRUE)
stopifnot(length(args) == 2L)
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
results <- list()
for (seed in c(4L, 17L, 42L)) {
    cpu <- fastEmbedR:::fast_knn_umap_csr_clean_atomic_cpp(
        graph$offsets, graph$neighbors, graph$weights,
        init$layout, 400L, cfg$min_dist,
        cfg$negative_sample_rate, 0.25, 1, 1L, seed, 0L, FALSE)
    baseline <- score(cpu)
    for (rate in c(3L, 5L, 10L)) {
        for (repulsion in c(0.5, 1, 2)) {
            for (learning in c(0.1, 0.25, 0.5, 1)) {
                before <- proc.time()[[3L]]
                metal <- fastEmbedR:::knn_embed_metal_csr_cpp(
                    graph$offsets, graph$neighbors, graph$weights,
                    init$layout, 400L, rate, learning,
                    cfg$min_dist, graph$max_weight,
                    repulsion, seed, 1L)
                seconds <- proc.time()[[3L]] - before
                results[[length(results) + 1L]] <- data.frame(
                    seed = seed, rate = rate, repulsion = repulsion,
                    learning = learning, cpu = baseline,
                    metal = score(metal), seconds = seconds)
            }
        }
    }
    cat("SEED_DONE", seed, "\n"); flush.console()
}
out <- do.call(rbind, results)
write.csv(out, args[[2L]], row.names = FALSE)
out$delta <- out$metal - out$cpu
summary <- aggregate(delta ~ rate + repulsion + learning,
                     data = out, FUN = min)
summary <- summary[order(-summary[[4L]]), ]
print(head(summary, 12L))
cat("ATOMIC_GRID_COMPLETE", nrow(out), "\n")
