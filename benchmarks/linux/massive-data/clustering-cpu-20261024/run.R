args <- commandArgs(trailingOnly = TRUE)
if (length(args) != 5L ||
    !args[[1L]] %in% c("build", "resident", "file", "classic",
        "landmark1m", "landmark100m", "vote1", "vote8",
        "vote16", "vote32") ||
    !args[[2L]] %in% c("leiden", "louvain")) {
    stop("Usage: run.R MODE METHOD INPUT CAMPAIGN OUTPUT")
}
library(fastEmbedR)
mode <- args[[1L]]
method <- args[[2L]]
input <- normalizePath(args[[3L]], mustWork = TRUE)
campaign <- normalizePath(args[[4L]], mustWork = TRUE)
output <- normalizePath(args[[5L]], mustWork = TRUE)
rows <- if (mode == "landmark100m") 1e8 else 1e6
source <- massive_matrix(input)
stopifnot(source$nrow == 1e9, source$ncol == 96L)
view <- fastEmbedR:::massive_matrix_rows(source, 1000001, rows)
graph_root <- file.path(campaign, "graph")
dir.create(graph_root, showWarnings = FALSE)
prefix <- file.path(graph_root, "fuzzy")
started <- proc.time()[[3L]]
storage <- if (mode == "resident") "resident_graph" else if (
    mode == "classic") "resident_matrix" else if (
    grepl("^vote", mode)) "file_backed_knn" else "file_backed"
workers <- if (grepl("^vote", mode)) {
    as.integer(sub("^vote", "", mode))
} else if (mode == "file") 1L else if (mode == "resident") 8L else 32L
fit_workers <- if (mode == "build" || grepl("^vote", mode)) 0L else 1L
knn_workers <- if (mode %in% c("build", "classic",
    "landmark1m", "landmark100m")) 32L else 0L
assignment_workers <- if (grepl("^vote", mode)) workers else if (
    mode %in% c("landmark1m", "landmark100m")) 32L else 0L

if (mode == "build") {
    knn <- massive_full_knn_graph(view, 30L,
        file.path(graph_root, "knn"), backend = "cpu",
        method = "hnsw_sharded", n.cores = 32L,
        chunk_rows = 10000L, reference_chunk_rows = 200000L,
        memory_limit = "8GB", checkpoint = TRUE, audit_rows = 128L,
        hnsw_build = list(m = 32L, ef_construction = 200L),
        ef_search = 150L)
    saveRDS(list(recall = knn$observed_recall,
        minimum_row_recall = knn$minimum_row_recall,
        effective_hnsw = knn$hnsw_settings),
        file.path(output, "knn_audit.rds"))
    stopifnot(is.finite(knn$observed_recall),
        knn$observed_recall >= 0.99)
    graph <- massive_umap_fuzzy_graph(knn, prefix,
        memory_limit = "8GB", sort_method = "bucketed",
        consume_knn = TRUE)
    stopifnot(graph$n_vertices == rows)
} else if (mode %in% c("landmark1m", "landmark100m")) {
    fit <- massive_cluster(view, method = method,
        massive = "landmark", landmarks = 50000L, k = 30L,
        output = file.path(output, "labels"), backend = "cpu",
        n.cores = 32L, chunk_rows = 50000L,
        memory_limit = "8GB", knn_method = "hnsw",
        seed = 4L, checkpoint = TRUE,
        resume = identical(Sys.getenv("CLUSTER_RESUME"), "1"))
    stopifnot(fit$nrow == rows,
        file.info(fit$membership_path)$size == 4 * rows,
        file.info(fit$confidence_path)$size == 4 * rows,
        fit$assignment_workers == 32L,
        fit$fitting_cpu_workers == 1L)
    saveRDS(fit, file.path(output, "fit.rds"))
} else if (grepl("^vote", mode)) {
    fit <- readRDS(file.path(campaign, "landmark1m_leiden", "fit.rds"))
    stopifnot(fit$nrow == rows, fit$knn$nrow == rows)
    labels <- file.path(output, "labels.u32")
    confidence <- file.path(output, "confidence.f32")
    label_out <- file(labels, "wb")
    confidence_out <- file(confidence, "wb")
    for (first in seq(1, rows, by = 50000)) {
        knn <- massive_read_knn_rows(fit$knn, first,
            min(50000, rows - first + 1))
        assigned <- fastEmbedR:::massive_vote_landmarks_cpp(
            knn$indices, knn$distances,
            fit$reference_membership, workers)
        writeBin(assigned$membership, label_out, size = 4L,
            endian = "little")
        writeBin(assigned$confidence, confidence_out, size = 4L,
            endian = "little")
    }
    close(label_out)
    close(confidence_out)
    stopifnot(file.info(labels)$size == 4 * rows,
        file.info(confidence)$size == 4 * rows)
    writeLines(unname(tools::md5sum(c(labels, confidence))),
        file.path(output, "output.md5"))
} else if (mode == "classic") {
    fit <- massive_cluster(view, method = method,
        massive = "auto", backend = "cpu", n.cores = 32L,
        memory_limit = "64GB", seed = 4L)
    stopifnot(identical(fit$mode, "in_memory"),
        length(fit$membership) == rows)
} else {
    graph <- massive_fuzzy_graph(prefix, rows)
    if (mode == "file") {
        fit <- massive_cluster(graph, method = method,
            massive = "out_of_core_graph", backend = "cpu",
            n.cores = 1L, output = file.path(output, "labels.u32"),
            memory_limit = "8GB", seed = 4L, checkpoint = TRUE)
        stopifnot(fit$n_vertices == rows,
            file.info(fit$membership_path)$size == 4 * rows)
    } else {
        starts <- seq(1, rows, by = 10000)
        blocks <- lapply(starts, function(first) {
            massive_read_graph_edges(graph, first,
                min(10000, rows - first + 1))
        })
        edges <- list(from = unlist(lapply(blocks, `[[`, "from")),
            to = unlist(lapply(blocks, `[[`, "to")),
            weight = unlist(lapply(blocks, `[[`, "weight")),
            n_vertices = rows)
        rm(blocks)
        fit <- graph_cluster(edges, method = method,
            backend = "cpu", seed = 4L)
        stopifnot(length(fit$membership) == rows)
        writeBin(as.integer(fit$membership),
            file.path(output, "labels.u32"), size = 4L,
            endian = "little")
    }
}
elapsed <- unname(proc.time()[[3L]] - started)
membership <- if (mode == "resident" || grepl("^vote", mode)) {
    file.path(output, "labels.u32")
} else if (mode == "file" || mode == "landmark100m") {
    fit$membership_path
} else NA_character_
score <- if (mode == "resident") {
    massive_graph_modularity(graph, membership,
        fit$n_communities, memory_limit = "8GB")$modularity
} else if (mode == "file") fit$modularity_final else NA_real_
peak_rss <- if (file.exists("/proc/self/status")) {
    line <- grep("^VmHWM:", readLines("/proc/self/status"),
        value = TRUE)
    as.numeric(sub("^VmHWM:[[:space:]]*([0-9]+).*", "\\1",
        line)) * 1024
} else NA_real_
write.csv(data.frame(mode = mode, method = method, rows = rows,
    input_storage = storage,
    source_file_bytes = file.info(input)$size,
    source_window_bytes = 4 * rows * 96,
    matched_graph_bytes = if (mode %in% c("build", "resident", "file") &&
        file.exists(paste0(prefix,
        ".indices.u32"))) sum(file.info(paste0(prefix,
        c(".offsets.u64", ".indices.u32", ".weights.f32")))$size)
        else NA_real_,
    requested_cores = workers, fit_workers = fit_workers,
    knn_workers = knn_workers,
    assignment_workers = assignment_workers,
    seconds = elapsed, peak_rss_bytes = peak_rss,
    label_bytes = if (!is.na(membership)) file.info(membership)$size
        else NA_real_, modularity_on_matched_graph = score),
    file.path(output, "metrics.csv"), row.names = FALSE)
