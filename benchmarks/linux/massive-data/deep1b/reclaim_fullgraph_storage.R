deep1b_reclaim_files <- function(root, stage) {
    work <- normalizePath(file.path(root, "work"), mustWork = TRUE)
    names <- if (stage == "leiden_work") {
        if (!file.exists(file.path(work, "leiden_labels.u32"))) {
            stop("Leiden labels are missing; refusing reclaim.")
        }
        candidates <- list.files(work,
            pattern = "^leiden_labels\\.u32\\.level[0-9]+\\.")
        allowed <- paste0("^leiden_labels\\.u32\\.level[0-9]+\\.",
            "(coarse\\.edges\\.bin|csr\\.(indices\\.u32|",
            "offsets\\.u64|weights\\.f64)|parent\\.u32|",
            "refined\\.u32(\\.parent\\.u32)?)$")
        if (any(!grepl(allowed, candidates))) {
            stop("Unknown Leiden level file; refusing reclaim.")
        }
        candidates
    } else switch(stage,
        tsne = c("affinity.offsets.u64", "affinity.indices.u32",
            "affinity.weights.f32", "affinity.affinity.rds",
            "tsne_init.f32"),
        tsne_only_knn = c("knn.indices.u32", "knn.distances.f32"),
        memberships = "knn.distances.f32",
        fuzzy = c("knn.indices.u32", "knn.weights.f32"),
        fuzzy_bucketed = c("knn.indices.u32", "knn.distances.f32"),
        fuzzy_graph = c("fuzzy.offsets.u64", "fuzzy.indices.u32",
            "fuzzy.weights.f32", "fuzzy.fuzzy.rds"),
        stop("Unknown full-graph reclaim stage."))
    if (!length(names)) return(invisible(0))
    paths <- file.path(work, names)
    if (!all(file.exists(paths))) {
        stop("A full-graph intermediate is missing; refusing reclaim.")
    }
    sizes <- file.info(paths)$size
    if (anyNA(sizes) || any(sizes < 1)) {
        stop("A full-graph intermediate is empty; refusing reclaim.")
    }
    for (path in paths) {
        if (unlink(path) != 0L || file.exists(path)) {
            stop("Could not reclaim full-graph intermediate: ", path)
        }
    }
    record <- data.frame(stage = stage, file = names, bytes = sizes)
    ledger <- file.path(root, "reclaimed_payloads.csv")
    existing <- file.exists(ledger)
    write.table(record, ledger, sep = ",", row.names = FALSE,
        col.names = !existing, append = existing,
        quote = TRUE)
    invisible(sum(sizes))
}

deep1b_record_consumed_knn <- function(root, stage, graph) {
    if (!stage %in% c("tsne_only_knn", "fuzzy_bucketed") ||
        !is.numeric(graph$consumed_knn_bytes) ||
        length(graph$consumed_knn_bytes) != 1L ||
        !is.finite(graph$consumed_knn_bytes) ||
        graph$consumed_knn_bytes <= 0) {
        stop("Graph did not report consumed KNN files.")
    }
    names <- c("knn.indices.u32", "knn.distances.f32")
    work <- normalizePath(file.path(root, "work"), mustWork = TRUE)
    if (any(file.exists(file.path(work, names)))) {
        stop("Consumed KNN files are still present.")
    }
    record <- data.frame(stage = stage, file = names,
        bytes = rep(graph$consumed_knn_bytes / 2, 2L))
    ledger <- file.path(root, "reclaimed_payloads.csv")
    write.table(record, ledger, sep = ",", row.names = FALSE,
        col.names = !file.exists(ledger), append = file.exists(ledger),
        quote = TRUE)
    invisible(graph$consumed_knn_bytes)
}
