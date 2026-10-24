args <- commandArgs(trailingOnly = TRUE)
if (length(args) != 1L) stop("Usage: smoke_cpu.R OUTPUT_DIR")
root <- normalizePath(args[[1L]], mustWork = TRUE)
library(fastEmbedR)
stopifnot(as.character(packageVersion("fastEmbedR")) == "0.1",
    as.character(packageVersion("faissR")) == "0.1",
    as.character(packageVersion("gpuinfo")) == "0.2.0")

set.seed(20261024)
x <- cbind(c(rnorm(512L, -2, 0.2), rnorm(512L, 2, 0.2)),
    rnorm(1024L, 0, 1), rnorm(1024L, 0, 0.3),
    rnorm(1024L, 0, 0.1))
input <- file.path(root, "input.f32")
writeBin(as.vector(t(x)), input, size = 4L, endian = "little")
source <- massive_matrix(input, nrow(x), ncol(x))
timed <- function(label, expr) {
    start <- proc.time()[[3L]]
    result <- force(expr)
    timings[[label]] <<- proc.time()[[3L]] - start
    result
}
timings <- list()

stopifnot(isTRUE(faissR:::faiss_available()))
hnsw <- timed("faissr_hnsw", faissR::nn(x, k = 8L,
    backend = "cpu", method = "hnsw", tuning = "none",
    exclude_self = TRUE, n_threads = 8L))
stopifnot(identical(dim(hnsw$indices), c(nrow(x), 8L)),
    all(is.finite(hnsw$distances)))

fit_pca <- function(workers, name) pca(source, ncomp = 2L,
    backend = "cpu", n.cores = workers,
    massive = "out_of_core", output = file.path(root, name),
    chunk_rows = 256L, memory_limit = "256MB")
pca8 <- timed("pca8", fit_pca(8L, "pca8.f32"))
pca32 <- timed("pca32", fit_pca(32L, "pca32.f32"))
stopifnot(identical(pca32$n_threads, 32L),
    isTRUE(all.equal(as.matrix(pca8$scores),
        as.matrix(pca32$scores), tolerance = 1e-4)))

knn <- timed("exact_graph", massive_full_knn_graph(source,
    k = 8L, output = file.path(root, "knn"), method = "exact",
    chunk_rows = 128L, reference_chunk_rows = 256L,
    memory_limit = "256MB"))
affinity <- timed("affinity", massive_tsne_affinities(
    knn, 3, file.path(root, "affinity"), memory_limit = "64MB"))
fit_tsne <- function(workers, name) massive_tsne_optimize(
    affinity, pca8$scores, file.path(root, name),
    early_exaggeration_iter = 1L, n_iter = 1L,
    learning_rate = 1, memory_limit = "1GB", n.cores = workers)
tsne1 <- timed("tsne1", fit_tsne(1L, "tsne1.f32"))
tsne32 <- timed("tsne32", fit_tsne(32L, "tsne32.f32"))
stopifnot(identical(tsne32$resources$effective_cpu_workers, 2L),
    isTRUE(all.equal(massive_read_rows(tsne1, 1L, nrow(x)),
        massive_read_rows(tsne32, 1L, nrow(x)),
        tolerance = 1e-4)))

n_big <- 32768L
ring <- file.path(root, "ring")
ring_ids <- outer(seq_len(n_big), 1:3,
    function(i, j) (i + j - 1L) %% n_big + 1L)
writeBin(as.integer(t(ring_ids)), paste0(ring, ".indices.u32"),
    size = 4L, endian = "little")
writeBin(rep(c(0.2, 0.5, 0.9), n_big),
    paste0(ring, ".distances.f32"), size = 4L,
    endian = "little")
ring_graph <- timed("ring_affinity", massive_tsne_affinities(
    massive_knn_graph(ring, n_big, 3L), 3,
    file.path(root, "ring_affinity"), memory_limit = "64MB"))
ring_init <- file.path(root, "ring_init.f32")
writeBin(as.vector(t(cbind(sin(seq_len(n_big)),
    cos(seq_len(n_big))) * 0.02)), ring_init,
    size = 4L, endian = "little")
ring_fit <- timed("tsne32_large", massive_tsne_optimize(
    ring_graph, massive_matrix(ring_init, n_big, 2L),
    file.path(root, "ring_tsne32.f32"),
    early_exaggeration_iter = 1L, n_iter = 0L,
    learning_rate = 1, memory_limit = "1GB", n.cores = 32L))
stopifnot(identical(ring_fit$resources$effective_cpu_workers, 32L),
    identical(file.info(ring_fit$path)$size,
        as.numeric(n_big * 2L * 4L)),
    all(is.finite(massive_read_rows(ring_fit, 1L, n_big))))

fuzzy <- timed("fuzzy_graph", massive_umap_fuzzy_graph(
    massive_umap_memberships(knn), file.path(root, "fuzzy"),
    memory_limit = "64MB"))
fit_umap <- function(workers, name) massive_umap_optimize(
    fuzzy, pca8$scores, file.path(root, name), n_epochs = 5L,
    negative_sample_rate = 2L, learning_rate = 0.05,
    memory_limit = "256MB", cpu_update = "synchronized",
    n.cores = workers)
umap1 <- timed("umap1", fit_umap(1L, "umap1.f32"))
umap32 <- timed("umap32", fit_umap(32L, "umap32.f32"))
stopifnot(identical(umap32$resources$effective_cpu_workers, 32L),
    identical(massive_read_rows(umap1, 1L, nrow(x)),
        massive_read_rows(umap32, 1L, nrow(x))))

write.csv(data.frame(stage = names(timings),
    seconds = as.numeric(unlist(timings))),
    file.path(root, "smoke_timings.csv"), row.names = FALSE)
writeLines(c("status=PASS", "backend=cpu", "workers=32",
    "faissR=0.1", "fastEmbedR=0.1", "gpuinfo=0.2.0"),
    file.path(root, "smoke_status.txt"))
