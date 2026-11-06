args <- commandArgs(trailingOnly = TRUE)
stopifnot(length(args) == 2L, dir.exists(args[[1L]]),
    dir.exists(dirname(args[[2L]])), !file.exists(args[[2L]]))
.libPaths(c(args[[1L]],
    "/Users/silvanopiazza/Documents/Stefano/data/Rlib", .libPaths()))
library(fastEmbedR)
library(cluster)
setTimeLimit(elapsed = 240, transient = FALSE)

data_path <- paste0(
    "/Users/silvanopiazza/Documents/Stefano/data/data/",
    "FashionMNIST_n5000/FashionMNIST_n5000_float32.RData")
data <- new.env(parent = emptyenv())
load(data_path, envir = data)
x <- float::dbl(data$dataset$data)
labels <- as.integer(data$dataset$labels)
prepared <- umap_init(x, n_neighbors = 30L, backend = "cpu",
    seed = 711L)
graph <- prepared$prepared$graph
config <- prepared$parameters
sample_rows <- seq.int(1L, length(labels), by = 5L)
score <- function(layout) as.numeric(summary(cluster::silhouette(
    labels[sample_rows], stats::dist(as.matrix(layout)[
        sample_rows, , drop = FALSE])))$avg.width)
seeds <- c(4L, 17L, 42L)
baseline <- vapply(seeds, function(seed) {
    cpu <- fastEmbedR:::fast_knn_umap_csr_clean_atomic_cpp(
        graph$offsets, graph$neighbors, graph$weights,
        prepared$layout, 400L, config$min_dist,
        config$negative_sample_rate, 0.25, 1,
        1L, seed, 0L, FALSE)
    score(cpu)
}, 0.0)
settings <- expand.grid(negative_sample_rate = c(1L, 2L, 3L, 5L, 8L),
    repulsion_strength = c(0.5, 1, 2), seed = seeds)
results <- vector("list", nrow(settings))
for (i in seq_len(nrow(settings))) {
    row <- settings[i, ]
    started <- proc.time()[[3L]]
    metal <- fastEmbedR:::knn_embed_metal_csr_cpp(
        graph$offsets, graph$neighbors, graph$weights,
        prepared$layout, 400L, row$negative_sample_rate,
        0.25, config$min_dist, graph$max_weight,
        row$repulsion_strength, row$seed, 2L)
    metal_score <- score(metal)
    results[[i]] <- data.frame(
        negative_sample_rate = row$negative_sample_rate,
        repulsion_strength = row$repulsion_strength,
        seed = row$seed, cpu_reference_silhouette = baseline[
            match(row$seed, seeds)],
        metal_silhouette = metal_score,
        delta = metal_score - baseline[match(row$seed, seeds)],
        metal_seconds = proc.time()[[3L]] - started)
}
table <- do.call(rbind, results)
stopifnot(nrow(table) == 45L, all(is.finite(table$delta)))
summary <- aggregate(delta ~ negative_sample_rate + repulsion_strength,
    table, min)
summary <- summary[order(summary$delta, decreasing = TRUE), ]
write.csv(table, args[[2L]], row.names = FALSE)
cat("CPU_BASELINE ", paste(signif(baseline, 7), collapse = ","), "\n",
    sep = "")
print(utils::head(summary, 10L), row.names = FALSE)
cat("METAL_UMAP_PARAMETER_GRID_COMPLETE\n")
