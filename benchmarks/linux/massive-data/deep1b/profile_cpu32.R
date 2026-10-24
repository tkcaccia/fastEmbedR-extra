args <- commandArgs(trailingOnly = TRUE)
if (length(args) != 4L || !args[[1L]] %in% c("pca", "tsne", "umap") ||
    !args[[2L]] %in% c("1", "8", "16", "32")) {
    stop("Usage: profile_cpu32.R METHOD CORES LIBRARY OUTPUT_DIR")
}
method <- args[[1L]]
cores <- as.integer(args[[2L]])
private <- normalizePath(args[[3L]], mustWork = TRUE)
root <- normalizePath(args[[4L]], mustWork = TRUE)
.libPaths(c(private, .libPaths()))
library(fastEmbedR)
if (!identical(normalizePath(find.package("fastEmbedR")),
    normalizePath(file.path(private, "fastEmbedR")))) {
    stop("Profile did not load its source-locked CPU package.")
}
base <- "/scratch/firenze/NN/fastEmbedR-results/massive-data/deep1b"
tsne <- file.path(base, "20261016T062350Z_full10000000_cpu_HCUL7d")
umap <- file.path(base, "20261016T062350Z_full10000000_cpu_mdPhWN")
output <- file.path(root, "layout.f32")
started <- proc.time()[[3L]]
if (method == "pca") {
    input <- paste0("/scratch/firenze/NN/Data/BigANN/deep/",
        "1000000000/base.1000000000.fbin")
    source <- massive_matrix(input)
    stopifnot(source$nrow == 1e9, source$ncol == 96L)
    view <- fastEmbedR:::massive_matrix_rows(source, 1000001, 1e7)
    fit <- pca(view, ncomp = 2L, backend = "cpu", n.cores = cores,
        massive = "out_of_core", output = output,
        chunk_rows = 100000L, seed = 4L, memory_limit = "4GB")
    stopifnot(identical(as.integer(fit$n_threads), cores),
        fit$scores$nrow == 1e7)
} else if (method == "tsne") {
    graph <- file.path(tsne, "work/affinity")
    paths <- paste0(graph, c(".offsets.u64", ".indices.u32",
        ".weights.f32"))
    init <- file.path(tsne, "work/tsne_init.f32")
    fit <- fastEmbedR:::massive_tsne_optimize_cpp(
        paths[[1L]], paths[[2L]], paths[[3L]], "stream",
        init, output, 10000000L, 2L, 0L, 2L, 12, 1,
        1, TRUE, 0.8, 0.8, 0.01, Inf, cores)
    stopifnot(identical(fit$n_threads, cores))
    phases <- unlist(fit$stage_seconds)
    stopifnot(length(phases) == 3L, all(is.finite(phases)))
    write.csv(data.frame(stage = names(phases), seconds = phases),
        file.path(root, "stage_seconds.csv"), row.names = FALSE)
} else {
    graph <- file.path(umap, "work/fuzzy")
    paths <- paste0(graph, c(".offsets.u64", ".indices.u32",
        ".weights.f32"))
    init <- file.path(umap,
        "results/cpu_pca_10000000_fullgraph/output.f32")
    fit <- fastEmbedR:::massive_umap_optimize_cpp(
        paths[[1L]], paths[[2L]], paths[[3L]], 10000000,
        init, "f32", 2L, output, 2L, 5L, 1, 0.01, 1,
        4L, 8192L, 8 * 1024^3, layout_storage = "memory",
        n_threads = cores, cpu_update = "synchronized")
}
elapsed <- unname(proc.time()[[3L]] - started)
bytes <- file.info(output)$size
stopifnot(bytes == 80000000)
write.csv(data.frame(method = method, cores = cores,
    elapsed_seconds = elapsed, output_bytes = bytes,
    positive_updates = if (method == "umap") fit$positive_updates
        else NA_real_,
    negative_updates = if (method == "umap") fit$negative_updates
        else NA_real_),
    file.path(root, "metrics.csv"), row.names = FALSE)
unlink(c(output, paste0(output, ".manifest.rds")))
