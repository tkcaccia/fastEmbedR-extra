args <- commandArgs(trailingOnly = TRUE)
if (length(args) != 2L) stop("Usage: worker.R STAGE RUN_ROOT")
stage <- args[[1L]]
root <- normalizePath(args[[2L]], mustWork = TRUE)
stefano <- "/Users/silvanopiazza/Documents/Stefano/"
if (!startsWith(root, stefano)) stop("Output must be under Stefano")
campaign <- dirname(root)
input <- file.path(campaign, "data/BigANN/deep/mod10-100000000",
    "base.mod10.100000000.fbin")
if (!file.exists(input)) stop("Verified 100M source is missing")
library(fastEmbedR)
x <- massive_matrix(input, access = "stream")
if (x$nrow != 100000000 || x$ncol != 96L) {
    stop("Unexpected Deep1B subset dimensions")
}
case <- file.path(root, "cases", stage)
dir.create(case, recursive = TRUE, showWarnings = FALSE)
if (file.exists(file.path(case, "result.rds"))) {
    stop("Stage already has a result")
}
descriptor <- function(name) {
    path <- file.path(root, "cases", name, "result.rds")
    if (!file.exists(path)) stop("Prior stage result is missing: ", name)
    readRDS(path)$fit
}
init <- function() massive_matrix(file.path(root, "cases",
    "pca_cpu20", "scores.f32"), 100000000, 2L)
check_layout <- function(path) {
    if (file.info(path)$size != 800000000) {
        stop("Layout has an unexpected byte count")
    }
    stream <- file(path, "rb")
    on.exit(close(stream))
    count <- 0
    repeat {
        block <- readBin(stream, "numeric", n = 1000000L,
            size = 4L, endian = "little")
        if (!length(block)) break
        if (any(!is.finite(block))) stop("Layout contains nonfinite values")
        count <- count + length(block)
    }
    if (count != 200000000) stop("Layout row count changed")
}
started <- proc.time()[[3L]]
fit <- NULL
if (stage == "smoke_fullgraph") {
    view <- fastEmbedR:::massive_matrix_rows(x, 1, 1000)
    small <- massive_full_knn_graph(view, k = 30L,
        output = file.path(case, "knn"), backend = "cpu",
        method = "hnsw_sharded", n.cores = 2L,
        chunk_rows = 128L, reference_chunk_rows = 500L,
        memory_limit = "256MB", checkpoint = TRUE,
        audit_rows = 2L, ef_search = 45L,
        hnsw_build = list(m = 24L, ef_construction = 160L))
    affinity <- massive_tsne_affinities(small, 30,
        output = file.path(case, "affinity"),
        memory_limit = "64MB", sort_method = "global")
    set.seed(4)
    init_path <- file.path(case, "init.f32")
    writeBin(rnorm(2000), init_path, size = 4L, endian = "little")
    small_init <- massive_matrix(init_path, 1000, 2L)
    tsne <- massive_tsne_optimize(affinity, small_init,
        output = file.path(case, "tsne.f32"),
        early_exaggeration_iter = 1L, n_iter = 1L,
        backend = "cpu", n.cores = 2L, memory_limit = "1GB")
    fuzzy <- massive_umap_fuzzy_graph(small,
        output = file.path(case, "fuzzy"),
        memory_limit = "64MB", sort_method = "global")
    umap <- massive_umap_optimize(fuzzy, small_init,
        output = file.path(case, "umap.f32"), n_epochs = 2L,
        backend = "metal", memory_limit = "1GB")
    fit <- list(knn_rows = small$n_vertices,
        tsne_rows = tsne$nrow, umap_rows = umap$nrow)
    if (!identical(unlist(fit), c(knn_rows = 1000,
            tsne_rows = 1000, umap_rows = 1000))) {
        stop("Full-graph smoke row counts changed")
    }
} else if (grepl("^pca_cpu(1|8|20|28)$", stage)) {
    workers <- as.integer(sub("^pca_cpu", "", stage))
    fit <- pca(x, ncomp = 2L, massive = "out_of_core",
        output = file.path(case, "scores.f32"), backend = "cpu",
        n.cores = workers, seed = 4L, chunk_rows = 100000L,
        memory_limit = "8GB")
    if (fit$backend != "cpu" || fit$scores$nrow != x$nrow) {
        stop("CPU PCA backend or row count changed")
    }
} else if (stage == "pca_metal") {
    fit <- pca(x, ncomp = 2L, massive = "out_of_core",
        output = file.path(case, "scores.f32"), backend = "metal",
        n.cores = 1L, seed = 4L, chunk_rows = 100000L,
        memory_limit = "8GB")
    if (fit$backend != "metal" || fit$scores$nrow != x$nrow) {
        stop("Metal PCA backend or row count changed")
    }
} else if (stage == "knn_cpu20") {
    fit <- massive_full_knn_graph(x, k = 30L,
        output = file.path(case, "knn"), backend = "cpu",
        method = "hnsw_sharded", n.cores = 20L,
        chunk_rows = 8192L, reference_chunk_rows = 25000000L,
        memory_limit = "180GB", checkpoint = TRUE,
        checkpoint_every = 100L, audit_rows = 32L,
        ef_search = 45L,
        hnsw_build = list(m = 24L, ef_construction = 160L))
    if (fit$n_vertices != x$nrow || fit$k != 30L ||
        fit$backend != "cpu" || fit$method !=
        "faissr_cpu_hnsw_sharded" || !isTRUE(fit$recall_audited)) {
        stop("Full KNN graph or recall audit changed")
    }
} else if (stage == "tsne_affinity") {
    fit <- massive_tsne_affinities(descriptor("knn_cpu20"),
        perplexity = 30, output = file.path(case, "affinity"),
        memory_limit = "8GB", backend = "cpu", n.cores = 20L,
        checkpoint = TRUE, sort_method = "global")
    if (fit$n_vertices != x$nrow || fit$source_k != 30L) {
        stop("Full t-SNE affinity graph changed")
    }
} else if (stage == "tsne_cpu20") {
    fit <- massive_tsne_optimize(descriptor("tsne_affinity"),
        init(), output = file.path(case, "layout.f32"),
        early_exaggeration_iter = 250L, n_iter = 500L,
        backend = "cpu", n.cores = 20L, memory_limit = "8GB",
        checkpoint = TRUE, checkpoint_every = 100L)
    if (fit$nrow != x$nrow || fit$ncol != 2L) {
        stop("Full t-SNE output dimensions changed")
    }
} else if (stage == "umap_fuzzy") {
    fit <- massive_umap_fuzzy_graph(descriptor("knn_cpu20"),
        output = file.path(case, "fuzzy"), memory_limit = "8GB",
        backend = "cpu", checkpoint = TRUE,
        sort_method = "global")
    if (fit$n_vertices != x$nrow || fit$source_k != 30L) {
        stop("Full UMAP fuzzy graph changed")
    }
} else if (stage %in% c("umap_metal", "umap_cpu20",
        "umap_cpu1")) {
    backend <- if (stage == "umap_metal") "metal" else "cpu"
    workers <- if (stage == "umap_cpu20") 20L else 1L
    update <- if (stage == "umap_cpu20") "synchronized" else "sgd"
    fit <- massive_umap_optimize(descriptor("umap_fuzzy"),
        init(), output = file.path(case, "layout.f32"),
        n_epochs = 200L, backend = backend, n.cores = workers,
        cpu_update = update, seed = 4L, memory_limit = "16GB",
        layout_storage = "memory", checkpoint = TRUE,
        checkpoint_every = 10L)
    if (fit$nrow != x$nrow || fit$ncol != 2L) {
        stop("Full UMAP output dimensions changed")
    }
} else if (stage == "leiden_cpu") {
    fit <- massive_leiden(descriptor("umap_fuzzy"),
        output = file.path(case, "communities.u32"),
        backend = "cpu", memory_limit = "8GB",
        max_passes = 10L, seed = 4L, checkpoint = TRUE)
    if (fit$n_vertices != x$nrow || fit$backend != "cpu") {
        stop("Full Leiden output dimensions or backend changed")
    }
} else stop("Unknown Deep1B 100M stage: ", stage)
elapsed <- unname(proc.time()[[3L]] - started)
if (grepl("^pca_", stage)) {
    check_layout(file.path(case, "scores.f32"))
} else if (stage %in% c("tsne_cpu20", "umap_metal",
        "umap_cpu20", "umap_cpu1")) {
    check_layout(file.path(case, "layout.f32"))
}
saveRDS(list(stage = stage, fit = fit, seconds = elapsed,
    input_path = input, input_rows = x$nrow, input_columns = x$ncol),
    file.path(case, "result.rds"))
cat("stage=", stage, " seconds=", elapsed, "\n", sep = "")
