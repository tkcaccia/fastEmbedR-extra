args <- commandArgs(trailingOnly = TRUE)
stopifnot(length(args) == 5L)
library_path <- normalizePath(args[[1L]], mustWork = TRUE)
rows <- as.integer(args[[2L]])
seed <- as.integer(args[[3L]])
block_rows <- as.integer(args[[4L]])
source_identity <- args[[5L]]
stopifnot(rows %in% c(300L, 5000L),
    seed %in% c(4L, 17L, 42L),
    block_rows >= 1L, block_rows <= 4096L,
    nzchar(source_identity))
.libPaths(c(library_path,
    '/Users/silvanopiazza/Documents/Stefano/data/Rlib',
    .libPaths()))
library(fastEmbedR)
library(cluster)
stopifnot(startsWith(find.package('fastEmbedR'), library_path))

file <- paste0('/Users/silvanopiazza/Documents/Stefano/data/',
    'data/FashionMNIST_n5000/FashionMNIST_n5000_float32.RData')
e <- new.env(parent = emptyenv())
load(file, envir = e)
x <- float::dbl(e$dataset$data)[seq_len(rows), , drop = FALSE]
labels <- as.integer(e$dataset$labels)[seq_len(rows)]
init <- umap_init(x, n_neighbors = 30L, backend = 'cpu', seed = 711L)
graph <- init$prepared$graph
cfg <- init$parameters
sample_rows <- seq.int(1L, rows, by = 5L)
score <- function(layout) as.numeric(summary(silhouette(
    labels[sample_rows],
    dist(as.matrix(layout)[sample_rows, , drop = FALSE])
))$avg.width)

cpu_time <- system.time(cpu <- fastEmbedR:::
    fast_knn_umap_csr_clean_atomic_cpp(
        graph$offsets, graph$neighbors, graph$weights,
        init$layout, 400L, cfg$min_dist,
        cfg$negative_sample_rate, 0.25, 1,
        1L, seed, 0L, FALSE))
Sys.setenv(FASTEMBEDR_METAL_UMAP_ORDERED_ROWS = block_rows)
metal_time <- system.time(metal <- fastEmbedR:::
    knn_embed_metal_csr_cpp(
        graph$offsets, graph$neighbors, graph$weights,
        init$layout, 400L, cfg$negative_sample_rate,
        0.25, cfg$min_dist, graph$max_weight,
        1, seed, 3L))
stopifnot(identical(dim(cpu), c(rows, 2L)),
    identical(dim(metal), c(rows, 2L)),
    all(is.finite(cpu)), all(is.finite(metal)),
    identical(attr(metal, 'metal_optimizer'),
        'ordered_row_blocks_atomic_inplace'),
    identical(as.integer(attr(metal, 'metal_ordered_rows')),
        block_rows))
cpu_quality <- score(cpu)
metal_quality <- score(metal)
result <- list(source_identity = source_identity,
    dataset = 'FashionMNIST_n5000', rows = rows,
    method = 'UMAP', dimensions = 2L, neighbors = 30L,
    epochs = 400L, graph_backend = 'cpu',
    graph_edges = length(graph$weights),
    graph_max_weight = graph$max_weight,
    seed = seed, ordered_rows = block_rows,
    cpu_optimizer = 'clean_atomic',
    metal_optimizer = attr(metal, 'metal_optimizer'),
    cpu_elapsed = unname(cpu_time[['elapsed']]),
    metal_elapsed = unname(metal_time[['elapsed']]),
    cpu_silhouette = cpu_quality,
    metal_silhouette = metal_quality,
    silhouette_delta = metal_quality - cpu_quality,
    gate_pass = metal_quality >= cpu_quality - 0.01)
cat(jsonlite::toJSON(result, auto_unbox = TRUE), '\n')
