#!/usr/bin/env Rscript

args <- commandArgs(trailingOnly = TRUE)
if (length(args) != 5L || !args[[2L]] %in% c("deep", "turing") ||
    !args[[3L]] %in% c("cpu", "cuda")) {
    stop("Usage: run_full_graph.R INPUT DATASET BACKEND ROWS ROOT")
}
library(fastEmbedR)
input <- normalizePath(args[[1L]], mustWork = TRUE)
dataset <- args[[2L]]
backend <- args[[3L]]
rows <- as.numeric(args[[4L]])
root <- normalizePath(args[[5L]], mustWork = TRUE)
script_arg <- grep("^--file=", commandArgs(), value = TRUE)
if (length(script_arg) != 1L) stop("Cannot locate benchmark script.")
source(file.path(dirname(sub("^--file=", "", script_arg)),
    "reclaim_fullgraph_storage.R"))
smoke <- identical(Sys.getenv("DEEP1B_SMOKE"), "1")
resume_text <- Sys.getenv("DEEP1B_RESUME", "0")
checkpoint_text <- Sys.getenv("DEEP1B_CHECKPOINT", "0")
if (!resume_text %in% c("0", "1") ||
    !checkpoint_text %in% c("0", "1") ||
    (resume_text == "1" && checkpoint_text != "1")) {
    stop("DEEP1B_RESUME requires DEEP1B_CHECKPOINT=1; use 0 or 1.")
}
resume <- resume_text == "1"
checkpoint <- checkpoint_text == "1"
first_row <- as.numeric(Sys.getenv("DEEP1B_FIRST_ROW",
    if (smoke) "1" else "1000001"))
fit_mode <- Sys.getenv("DEEP1B_FIT_MODE", "full")
rebuild_text <- Sys.getenv("DEEP1B_REBUILD_KNN_FOR_UMAP",
    if (fit_mode == "full" && rows >= 1e8) "1" else "0")
if (!rebuild_text %in% c("0", "1") ||
    (rebuild_text == "1" && fit_mode != "full")) {
    stop("DEEP1B_REBUILD_KNN_FOR_UMAP requires full mode and 0 or 1.")
}
rebuild_knn <- rebuild_text == "1"
memory_limit <- Sys.getenv("DEEP1B_MEMORY_LIMIT", "8GB")
cpu_cores <- as.integer(Sys.getenv("DEEP1B_CPU_CORES", "4"))
if (length(cpu_cores) != 1L || is.na(cpu_cores) ||
    !cpu_cores %in% c(1L, 4L, 8L, 16L, 32L)) {
    stop("DEEP1B_CPU_CORES must be 1, 4, 8, 16, or 32.")
}
umap_cpu_update <- Sys.getenv("DEEP1B_UMAP_CPU_UPDATE", "sgd")
if (!umap_cpu_update %in% c("sgd", "synchronized") ||
    (backend != "cpu" && umap_cpu_update != "sgd")) {
    stop("DEEP1B_UMAP_CPU_UPDATE requires cpu and sgd or synchronized.")
}
umap_cores <- if (umap_cpu_update == "synchronized") cpu_cores else 1L
device_text <- Sys.getenv("DEEP1B_GPU_DEVICES", "")
devices <- if (nzchar(device_text)) {
    as.integer(strsplit(device_text, ",", fixed = TRUE)[[1L]])
} else NULL
if (!is.null(devices) && (backend != "cuda" ||
    anyNA(devices) || anyDuplicated(devices) ||
    any(devices < 0L) || length(devices) > 4L ||
    (length(devices) > 1L && fit_mode == "classic"))) {
    stop("Invalid CUDA device request for full-graph fitting.")
}
prep_cores <- if (backend == "cpu") cpu_cores else 4L
knn_cores <- if (length(devices) > 1L) 1L else prep_cores
pca_chunk_rows <- if (backend == "cpu" && cpu_cores == 32L)
    1000000L else if (backend == "cpu") 100000L else 10000L
if (!fit_mode %in% c("full", "pca", "full_tsne", "full_umap")) {
    stop("Invalid fit mode.")
}
if (!is.finite(rows) || rows != floor(rows) || rows < 1000 ||
    !is.finite(first_row) || first_row < 1 ||
    first_row != floor(first_row) ||
    first_row + rows - 1 > 1e9) stop("Invalid row window.")
if (!is.null(devices)) {
    ids <- fastEmbedR:::massive_cuda_device_uuids(devices)
    write.csv(data.frame(logical_device = devices, uuid = ids),
        file.path(root, "gpu_device_map.csv"), row.names = FALSE)
}
source <- massive_matrix(input)
if ((!smoke && source$nrow != 1e9) ||
    (smoke && source$nrow < rows) ||
    source$ncol != if (dataset == "deep") 96 else 100) {
    stop("BigANN input dimensions do not match the dataset.")
}
view <- fastEmbedR:::massive_matrix_rows(source, first_row, rows)
work <- file.path(root, "work")
dir.create(work, recursive = TRUE, showWarnings = FALSE)
resume_path <- file.path(work, "source_identity.rds")
identity <- list(
    source = fastEmbedR:::massive_checkpoint_source_identity(view),
    implementation = fastEmbedR:::
        massive_checkpoint_implementation_identity(),
    backend = backend, rows = rows, first_row = first_row,
    mode = fit_mode, rebuild_knn = rebuild_knn,
    checkpoint = checkpoint,
    memory_limit = memory_limit, cpu_cores = cpu_cores,
    pca_chunk_rows = pca_chunk_rows,
    umap_cpu_update = umap_cpu_update,
    devices = devices, gpu_identity = if (length(devices))
        fastEmbedR:::massive_cuda_device_uuids(devices) else NULL)
if (resume) {
    saved_identity <- tryCatch(readRDS(resume_path),
        error = function(e) NULL)
    if (!identical(saved_identity, identity)) stop(
        "Full-graph resume identity does not match the input or build.")
} else {
    if (file.exists(resume_path)) stop(
        "Existing full-graph identity requires DEEP1B_RESUME=1.")
    saveRDS(identity, resume_path)
}
case <- function(method) file.path(root, "results", paste0(
    backend, "_", method, "_", sprintf("%.0f", rows), "_fullgraph"))
if (resume && file.exists(file.path(root, "knn.csv"))) stop(
    "This runner resumes interrupted KNN only, not later stages.")
methods <- c("pca", if (fit_mode %in% c("full", "full_tsne"))
    "tsne", if (fit_mode %in% c("full", "full_umap")) "umap")
cluster_supported <- backend == "cpu" || length(devices) >= 2L
if ("umap" %in% methods && cluster_supported) {
    methods <- c(methods, "leiden", "louvain")
} else if ("umap" %in% methods) {
    write.table(data.frame(method = c("leiden", "louvain"),
        status = "unsupported",
        reason = "Full-graph CUDA clustering requires 2-4 GPUs"),
        file.path(root, "unsupported_methods.tsv"), sep = "\t",
        quote = FALSE, row.names = FALSE)
}
for (method in methods) {
    dir.create(case(method), recursive = TRUE, showWarnings = FALSE)
}
peak_rss <- function() {
    if (!file.exists("/proc/self/status")) return(NA_real_)
    status <- readLines("/proc/self/status", warn = FALSE)
    line <- grep("^VmHWM:", status, value = TRUE)
    as.numeric(sub("^VmHWM:[[:space:]]*([0-9]+).*", "\\1", line)) *
        1024
}
check_devices <- function(fit, method) {
    if (!is.null(devices) &&
        !identical(as.integer(fit$gpu_devices), devices)) {
        stop(method, " did not report the requested GPU devices.")
    }
}
record_optimizer <- function(fit, method, key) {
    if (backend == "cpu" && method %in% c("tsne", "umap")) {
        workers <- fit$resources$effective_cpu_workers
        expected <- if (method == "tsne") cpu_cores else umap_cores
        if (!identical(workers, expected)) stop(
            "CPU optimizer worker accounting is invalid.")
    }
    if (backend == "cpu" && method == "tsne") {
        stages <- unlist(fit$stage_seconds)
        if (length(stages) != 3L || any(!is.finite(stages)) ||
            any(stages < 0)) stop(
            "CPU t-SNE phase accounting is invalid.")
        write.csv(data.frame(stage = names(stages), seconds = stages),
            file.path(root, "tsne_stage_seconds.csv"),
            row.names = FALSE)
        return(invisible(NULL))
    }
    if (length(devices) < 2L) return(invisible(NULL))
    work <- as.numeric(fit$resources[[key]])
    if (length(work) != length(devices) ||
        any(!is.finite(work)) || any(work <= 0)) {
        stop(method, " did not report work on every GPU.")
    }
    write.csv(data.frame(logical_device = devices, edge_work = work),
        file.path(root, paste0(method, "_device_work.csv")),
        row.names = FALSE)
    stages <- unlist(fit$stage_seconds)
    if (!is.null(fit$resources$owner_wall_seconds)) {
        stages <- c(stages,
            owner_wall = fit$resources$owner_wall_seconds)
    }
    if (!length(stages) || any(!is.finite(stages))) {
        stop(method, " did not report optimizer stage times.")
    }
    owner <- fit$resources$owner_wall_seconds
    if (!is.numeric(owner) || length(owner) != 1L ||
        !is.finite(owner) || owner <= 0) {
        stop(method, " did not report concurrent owner wall time.")
    }
    write.csv(data.frame(stage = names(stages), seconds = stages),
        file.path(root, paste0(method, "_stage_seconds.csv")),
        row.names = FALSE)
}
record_knn_devices <- function(graph) {
    if (length(devices) < 2L) return(invisible(NULL))
    shards <- graph$per_device
    if (length(shards) != length(devices)) {
        stop("KNN did not report every GPU shard.")
    }
    bytes <- vapply(shards, function(item) {
        as.numeric(item$resources$output_bytes)
    }, 0)
    if (any(!is.finite(bytes)) || any(bytes <= 0)) {
        stop("KNN GPU shards reported no candidate output.")
    }
    write.csv(data.frame(logical_device = devices,
        candidate_bytes = bytes),
        file.path(root, "knn_device_work.csv"), row.names = FALSE)
}
record_knn_audit <- function(graph, output) {
    if (!length(graph$per_device_audit)) return(invisible(NULL))
    audit <- do.call(rbind, lapply(graph$per_device_audit,
        function(item) data.frame(device = item$device,
            first_row = item$query_row_range[[1L]],
            last_row = item$query_row_range[[2L]],
            audit_rows = length(item$sampled_rows),
            recall_mean = item$recall_mean,
            recall_min = item$recall_min,
            rows_below_target = item$rows_below_target)))
    write.csv(audit, file.path(root, output), row.names = FALSE)
}
record_pca_fit <- function(fit) {
    if (length(devices) < 2L) return(invisible(NULL))
    parts <- fit$fit_per_device
    if (!identical(as.integer(fit$fit_devices), devices) ||
        length(parts) != length(devices)) {
        stop("PCA did not distribute fitting across the requested GPUs.")
    }
    rows_fit <- vapply(parts, function(item) as.numeric(item$rows), 0)
    seconds <- vapply(parts, function(item)
        as.numeric(item$seconds), 0)
    if (any(!is.finite(rows_fit)) || any(rows_fit <= 0) ||
        sum(rows_fit) != rows || any(!is.finite(seconds)) ||
        any(seconds <= 0)) stop("PCA fit-device work is invalid.")
    write.csv(data.frame(logical_device = devices,
        fitted_rows = rows_fit, fit_seconds = seconds),
        file.path(root, "pca_fit_device_work.csv"), row.names = FALSE)
}
stages_path <- file.path(root, "stages.csv")
timings <- if (resume && file.exists(stages_path)) {
    previous <- read.csv(stages_path)
    stats::setNames(lapply(seq_len(nrow(previous)), function(i)
        previous[i, , drop = FALSE]), previous$stage)
} else list()
measure <- function(stage, expr) {
    start <- proc.time()[[3L]]
    value <- force(expr)
    stage_backend <- if (stage %in% c("memberships", "fuzzy",
        "affinity", "tsne_init")) "cpu" else backend
    stage_cores <- if (stage %in% c("umap", "leiden", "louvain", "fuzzy",
        "tsne_init") || (backend == "cuda" &&
        stage %in% c("pca", "tsne"))) 1L else
        if (stage == "knn") knn_cores else prep_cores
    timings[[stage]] <<- data.frame(stage = stage,
        seconds = unname(proc.time()[[3L]] - start),
        peak_rss_bytes = peak_rss(), backend = stage_backend,
        effective_cores = stage_cores,
        devices = if (stage_backend == "cuda" &&
            !is.null(devices))
            paste(devices, collapse = ",") else "",
        rows = rows, first_row = first_row, smoke = smoke)
    write.csv(do.call(rbind, timings), stages_path,
        row.names = FALSE)
    value
}
make_tsne_init <- function(scores, output) {
    sums <- squares <- numeric(2L)
    for (first in seq(1, rows, by = 10000)) {
        block <- massive_read_rows(scores, first,
            min(10000, rows - first + 1))
        sums <- sums + colSums(block)
        squares <- squares + colSums(block * block)
    }
    center <- sums / rows
    variance <- (squares - rows * center^2) / (rows - 1)
    scale <- 1e-4 / sqrt(max(variance))
    if (!is.finite(scale) || scale <= 0) stop("Invalid PCA init scale.")
    stream <- file(output, "wb")
    on.exit(close(stream))
    for (first in seq(1, rows, by = 10000)) {
        block <- massive_read_rows(scores, first,
            min(10000, rows - first + 1))
        block <- sweep(block, 2L, center, "-") * scale
        writeBin(as.vector(t(block)), stream, size = 4L,
            endian = "little")
    }
}
pca_path <- file.path(case("pca"), "output.f32")
pca_done <- resume && file.exists(pca_path) &&
    file.exists(paste0(pca_path, ".manifest.rds"))
pca_fit <- if (pca_done) {
    message("Reopening verified completed PCA scores.")
    fastEmbedR::massive_open_pca(pca_path)
} else measure("pca", fastEmbedR::pca(view, ncomp = 2L,
    massive = "out_of_core", output = pca_path, backend = backend,
    n.cores = if (backend == "cuda") 1L else cpu_cores,
    seed = 4L, chunk_rows = pca_chunk_rows,
    memory_limit = memory_limit, devices = devices))
if (!identical(pca_fit$implementation_identity,
        identity$implementation) || pca_fit$backend != backend ||
    pca_fit$scores$nrow != rows) stop(
    "Completed PCA does not match the requested run.")
scores <- pca_fit$scores
check_devices(pca_fit, "PCA")
record_pca_fit(pca_fit)
write.csv(data.frame(status = "ok", rows = rows, components = 2L,
    first_row = first_row, backend = backend, mode = "full_graph",
    fit_mode = fit_mode,
    pca_chunk_rows = pca_fit$resources$chunk_rows,
    effective_cores = if (backend == "cpu")
        cpu_cores else 1L,
    devices = if (is.null(devices)) "" else
        paste(devices, collapse = ",")),
    file.path(case("pca"), "metrics.csv"), row.names = FALSE)
if (fit_mode == "pca") quit(status = 0L)
build_knn <- function() {
    prefix <- file.path(work, "knn")
    sidecar <- paste0(prefix, if (length(devices) > 1L)
        ".multigpu.checkpoint.rds" else ".checkpoint.rds")
    knn_resume <- resume && file.exists(sidecar)
    orphan <- any(file.exists(c(
            paste0(prefix, c(".indices.u32", ".distances.f32")),
            paste0(prefix, c(".indices.u32.part",
                ".distances.f32.part"))))) ||
        length(Sys.glob(paste0(prefix, ".candidates*"))) > 0L
    if (resume && !knn_resume && orphan) stop(
        "KNN files have no checkpoint; cannot safely resume.")
    massive_full_knn_graph(view, k = 30L,
    output = file.path(work, "knn"), backend = backend,
    method = if (backend == "cpu") "hnsw_sharded" else "ivf_sharded",
    n.cores = knn_cores, chunk_rows = 10000L,
    reference_chunk_rows = 200000L, memory_limit = memory_limit,
    audit_rows = if (smoke) 4L else 128L, devices = devices,
    checkpoint = checkpoint, resume = knn_resume)
}
knn <- measure("knn", build_knn())
check_devices(knn, "KNN")
record_knn_devices(knn)
if (length(devices) > 1L &&
    length(knn$per_device_audit) != length(devices)) stop(
    "Multi-GPU KNN lacks per-device exact-neighbor audit.")
record_knn_audit(knn, "knn_device_audit.csv")
write.csv(data.frame(rows = rows, k = knn$k,
    observed_recall = knn$observed_recall,
    minimum_row_recall = knn$minimum_row_recall,
    audit_rows = knn$audit_rows, backend = knn$backend,
    method = knn$method,
    sampled_rows_below_target = knn$sampled_rows_below_target,
    sample_target_met = knn$sample_target_met,
    build_seconds = knn$build_seconds,
    search_seconds = knn$search_seconds,
    audit_seconds = knn$audit_seconds),
    file.path(root, "knn.csv"),
    row.names = FALSE)
write.csv(data.frame(row = knn$audit_sample_rows,
    source_row = first_row + knn$audit_sample_rows - 1,
    recall = knn$audit_row_recall),
    file.path(root, "knn_audit_rows.csv"), row.names = FALSE)
if (length(knn$hnsw_settings)) {
    settings <- do.call(rbind, lapply(knn$hnsw_settings,
        as.data.frame))
    write.csv(settings, file.path(root, "hnsw_settings.csv"),
        row.names = FALSE)
}
errors <- character()
attempt <- function(method, expression) {
    tryCatch(force(expression), error = function(e) {
        error <- conditionMessage(e)
        writeLines(error, file.path(case(method), "fit.error.txt"))
        errors <<- c(errors, paste(method, error, sep = ": "))
    })
}
if ("tsne" %in% methods) attempt("tsne", {
    affinity <- measure("affinity", massive_tsne_affinities(knn,
        perplexity = 30, output = file.path(work, "affinity"),
        backend = "cpu", n.cores = prep_cores,
        memory_limit = memory_limit, sort_method = "bucketed",
        consume_knn = fit_mode == "full_tsne" || rebuild_knn))
    if (fit_mode == "full_tsne" || rebuild_knn) {
        deep1b_record_consumed_knn(root, "tsne_only_knn", affinity)
    }
    write.csv(data.frame(method = "tsne",
        consumed_knn_bytes = affinity$consumed_knn_bytes,
        peak_graph_stage_bytes = affinity$peak_graph_stage_bytes),
        file.path(root, "tsne_graph_space.csv"), row.names = FALSE)
    init_path <- file.path(work, "tsne_init.f32")
    invisible(measure("tsne_init", make_tsne_init(scores, init_path)))
    init <- massive_matrix(init_path, rows, 2L)
    tsne <- measure("tsne", massive_tsne_optimize(affinity, init,
        output = file.path(case("tsne"), "output.f32"),
        early_exaggeration_iter = 250L, n_iter = 750L,
        learning_rate = "auto", backend = backend,
        n.cores = if (backend == "cpu") cpu_cores else 1L,
        memory_limit = memory_limit, devices = devices))
    check_devices(tsne, "t-SNE")
    record_optimizer(tsne, "tsne", "per_device_attraction_edges")
    stopifnot(tsne$nrow == rows,
        file.info(tsne$path)$size == rows * 8)
    write.csv(data.frame(status = "ok", rows = rows,
        components = 2L, first_row = first_row, backend = backend,
        mode = "full_graph",
        effective_cores = if (backend == "cpu")
            tsne$resources$effective_cpu_workers else 1L,
        devices = if (is.null(devices)) "" else
            paste(devices, collapse = ",")),
        file.path(case("tsne"), "metrics.csv"), row.names = FALSE)
    deep1b_reclaim_files(root, "tsne")
})
if (rebuild_knn && length(errors)) {
    stop(paste(errors, collapse = "; "))
}
if (rebuild_knn) {
    paths <- file.path(work, c("knn.indices.u32",
        "knn.distances.f32"))
    if (any(file.exists(paths))) stop(
        "The t-SNE KNN pair was not consumed before rebuilding.")
    knn <- measure("knn_rebuild", build_knn())
    check_devices(knn, "Rebuilt KNN")
    if (knn$n_vertices != rows || knn$k != 30L ||
        (length(devices) > 1L &&
        length(knn$per_device_audit) != length(devices))) {
        stop("Rebuilt KNN did not pass the row/device contract.")
    }
    record_knn_audit(knn, "knn_rebuild_device_audit.csv")
    write.csv(data.frame(rows = rows, k = knn$k,
        observed_recall = knn$observed_recall,
        minimum_row_recall = knn$minimum_row_recall,
        sample_target_met = knn$sample_target_met,
        backend = knn$backend, method = knn$method,
        build_seconds = knn$build_seconds,
        search_seconds = knn$search_seconds,
        audit_seconds = knn$audit_seconds),
        file.path(root, "knn_rebuild.csv"), row.names = FALSE)
    if (length(knn$hnsw_settings)) {
        write.csv(do.call(rbind, lapply(knn$hnsw_settings,
            as.data.frame)), file.path(root, "hnsw_settings_rebuild.csv"),
            row.names = FALSE)
    }
}
if ("umap" %in% methods) {
    fuzzy <- tryCatch({
        measure("fuzzy", massive_umap_fuzzy_graph(knn,
            output = file.path(work, "fuzzy"), backend = "cpu",
            memory_limit = memory_limit,
            sort_method = "bucketed", consume_knn = TRUE))
    }, error = function(e) {
        message <- conditionMessage(e)
        for (method in intersect(c("umap", "leiden", "louvain"),
            methods)) {
            writeLines(message,
                file.path(case(method), "fit.error.txt"))
            errors <<- c(errors, paste(method, message, sep = ": "))
        }
        NULL
    })
}
if ("umap" %in% methods && !is.null(fuzzy)) {
    deep1b_record_consumed_knn(root, "fuzzy_bucketed", fuzzy)
}
if ("umap" %in% methods && !is.null(fuzzy)) write.csv(data.frame(method = "umap",
    consumed_knn_bytes = fuzzy$consumed_knn_bytes,
    peak_graph_stage_bytes = fuzzy$peak_graph_stage_bytes),
    file.path(root, "umap_graph_space.csv"), row.names = FALSE)
if ("umap" %in% methods && !is.null(fuzzy)) attempt("umap", {
    umap <- measure("umap", massive_umap_optimize(fuzzy, scores,
        output = file.path(case("umap"), "output.f32"),
        n_epochs = 200L, min_dist = 0.01, seed = 4L,
        backend = backend, n.cores = umap_cores,
        cpu_update = umap_cpu_update, memory_limit = memory_limit,
        layout_storage = if (backend == "cpu") "mmap" else "memory",
        devices = devices))
    check_devices(umap, "UMAP")
    record_optimizer(umap, "umap", "per_device_edge_visits")
    stopifnot(umap$nrow == rows,
        file.info(umap$path)$size == rows * 8)
    write.csv(data.frame(status = "ok", rows = rows,
        components = 2L, first_row = first_row, backend = backend,
        mode = "full_graph",
        optimizer = umap$optimizer,
        effective_cores = if (backend == "cpu")
            umap$resources$effective_cpu_workers else 1L,
        devices = if (is.null(devices)) "" else
            paste(devices, collapse = ",")),
        file.path(case("umap"), "metrics.csv"), row.names = FALSE)
})
if ("umap" %in% methods && !is.null(fuzzy)) {
    for (method in intersect(c("leiden", "louvain"), methods))
        attempt(method, {
        labels <- file.path(work, paste0(method, "_labels.u32"))
        cluster_seed <- if (method == "louvain") 1L else 4L
        clusters <- measure(method, massive_cluster(fuzzy,
            method = method, massive = "out_of_core_graph",
            output = labels, backend = backend, devices = devices,
            n.cores = 1L, memory_limit = memory_limit,
            seed = cluster_seed))
        check_devices(clusters, method)
        stopifnot(clusters$n_vertices == rows,
            file.info(clusters$membership_path)$size == rows * 4)
        write.csv(data.frame(status = "ok", rows = rows,
            first_row = first_row, backend = backend,
            mode = "full_graph", method = method,
            seed = cluster_seed,
            devices = if (is.null(devices)) "" else
                paste(devices, collapse = ","),
            n_communities = clusters$n_communities,
            modularity = clusters$modularity_final),
            file.path(case(method), "metrics.csv"),
            row.names = FALSE)
        if (method == "leiden" && backend == "cpu") {
            deep1b_reclaim_files(root, "leiden_work")
        }
        })
}
if (length(errors)) stop(paste(errors, collapse = "; "))
if ("umap" %in% methods) {
    if (is.null(fuzzy)) stop("Fuzzy graph was not built.")
    deep1b_reclaim_files(root, "fuzzy_graph")
}
cat("Full-graph fitting completed for", dataset, backend, rows,
    "rows.\n")
