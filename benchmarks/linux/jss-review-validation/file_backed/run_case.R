#!/usr/bin/env Rscript

args <- commandArgs(trailingOnly = TRUE)
if (length(args) != 3L) {
    stop("Usage: run_case.R CASE_ID INPUT_ROOT OUTPUT_ROOT")
}
script <- sub("^--file=", "", grep("^--file=", commandArgs(FALSE),
    value = TRUE)[[1L]])
suite <- dirname(dirname(normalizePath(script)))
cases <- utils::read.csv(file.path(suite, "file_backed", "cases.csv"),
    stringsAsFactors = FALSE)
selected <- cases[cases$id == args[[1L]], , drop = FALSE]
if (nrow(selected) != 1L) stop("Unknown file-backed case")
case <- as.list(selected[1L, ])
root <- normalizePath(args[[2L]], mustWork = TRUE)
out <- file.path(args[[3L]], "file_backed", case$id)
dir.create(out, recursive = TRUE, showWarnings = FALSE)
if (file.exists(file.path(out, "result.csv"))) {
    stop("Case already has a result; use a fresh campaign")
}
suppressPackageStartupMessages(library(fastEmbedR))
expected <- Sys.getenv("EXPECTED_VERSION", "0.1")
if (as.character(packageVersion("fastEmbedR")) != expected) {
    stop("Loaded fastEmbedR version differs from campaign")
}
dll <- getLoadedDLLs()[["fastEmbedR"]][["path"]]
hash <- strsplit(system2("sha256sum", dll, stdout = TRUE), " +")[[1L]][1L]
if (!identical(hash, Sys.getenv("FASTEMBEDR_DLL_SHA256"))) {
    stop("Loaded fastEmbedR DLL differs from campaign")
}

peak_rss <- function() {
    line <- grep("^VmHWM:", readLines("/proc/self/status"), value = TRUE)
    as.numeric(gsub("[^0-9]", "", line)) * 1024
}

memory_budget <- function() {
    line <- grep("^MemTotal:", readLines("/proc/meminfo"),
        value = TRUE)
    physical <- as.numeric(gsub("[^0-9]", "", line)) * 1024
    cgroup <- if (file.exists("/sys/fs/cgroup/memory.max")) {
        "/sys/fs/cgroup/memory.max"
    } else "/sys/fs/cgroup/memory/memory.limit_in_bytes"
    limit <- if (file.exists(cgroup)) {
        suppressWarnings(as.numeric(readLines(cgroup, n = 1L)))
    } else NA_real_
    slurm <- suppressWarnings(as.numeric(Sys.getenv(
        "SLURM_MEM_PER_NODE", NA_character_))) * 1024^2
    budget <- min(c(physical, limit, slurm), na.rm = TRUE)
    list(physical = physical, effective = budget)
}

blocked <- function(message) {
    condition <- structure(list(message = message, call = NULL),
        class = c("file_backed_blocked", "error", "condition"))
    stop(condition)
}

input_source <- function(case, root) {
    if (case$dataset %in% c("turing", "deep")) {
        path <- file.path(Sys.getenv("BIGANN_DATA_ROOT",
            "/scratch/firenze/NN/Data/BigANN"), case$dataset,
            "1000000000", "base.1000000000.fbin")
        manifest <- file.path(dirname(path), "manifest.json")
        if (!file.exists(manifest) || !file.exists(path)) {
            blocked("BigANN file or download manifest is missing")
        }
        expected_bytes <- if (case$dataset == "turing") {
            400000000008
        } else 384000000008
        if (file.info(path)$size != expected_bytes) {
            blocked("BigANN 1-billion-row download is incomplete")
        }
        identity <- jsonlite::fromJSON(manifest)
        expected_cols <- if (case$dataset == "turing") 100L else 96L
        if (identity$dataset != case$dataset ||
            identity$rows != 1000000000 ||
            identity$columns != expected_cols ||
            identity$target_bytes != expected_bytes ||
            !grepl("^[0-9a-f]{64}$", identity$sha256)) {
            blocked("BigANN download manifest does not match the input")
        }
        data_sha256 <- identity$sha256
        source <- massive_matrix(path, access = "stream")
    } else {
        base <- file.path(root, case$dataset, "workflow_comparators")
        manifest <- file.path(base, "manifest.csv")
        if (!file.exists(manifest)) blocked("Comparator input is missing")
        meta <- utils::read.csv(manifest)
        path <- file.path(base, "data_float32.bin")
        if (!file.exists(path)) blocked("Comparator float32 data is missing")
        if (file.info(path)$size != 4 * meta$n[[1L]] * meta$p[[1L]]) {
            blocked("Comparator float32 data is incomplete")
        }
        source <- massive_matrix(path, nrow = meta$n[[1L]],
            ncol = meta$p[[1L]], format = "f32", access = "stream")
        data_sha256 <- ""
    }
    if (case$rows > source$nrow) stop("Case exceeds available rows")
    view <- if (case$rows == source$nrow) source else {
        fastEmbedR:::massive_matrix_rows(source, 1L, case$rows)
    }
    list(data = view, path = path, manifest = manifest,
        data_sha256 = data_sha256,
        source_rows = source$nrow)
}

sample_rows <- function(source, out, count) {
    indices <- unique(as.integer(round(seq(1, source$nrow,
        length.out = count))))
    blocks <- lapply(indices, function(i) massive_read_rows(source, i, 1L))
    values <- do.call(rbind, blocks)
    path <- file.path(out, "matched.f32")
    con <- file(path, "wb")
    writeBin(as.vector(t(values)), con, size = 4L, endian = "little")
    close(con)
    utils::write.csv(data.frame(source_row = indices),
        file.path(out, "matched_rows.csv"), row.names = FALSE)
    list(matrix = values, source = massive_matrix(path,
        nrow = nrow(values), ncol = ncol(values), format = "f32"))
}

neighbor_overlap <- function(high, low, k = 30L) {
    indices <- function(x) {
        distance <- as.matrix(stats::dist(x))
        diag(distance) <- Inf
        vapply(seq_len(nrow(x)), function(i) {
            order(distance[i, ], method = "radix")[seq_len(k)]
        }, integer(k))
    }
    a <- indices(high)
    b <- indices(low)
    mean(vapply(seq_len(ncol(a)), function(i) {
        length(intersect(a[, i], b[, i])) / k
    }, 0.0))
}

run_matched <- function(source, out, case) {
    sampled <- sample_rows(source, out, case$rows)
    x <- sampled$matrix
    knn <- massive_full_knn_graph(sampled$source, k = 30L,
        output = file.path(out, "exact_knn"), backend = "cpu",
        method = "exact", n.cores = 4L, chunk_rows = 128L,
        memory_limit = "1GB")
    edges <- massive_read_graph_edges(knn, first = 1L, n = nrow(x))
    observed <- matrix(edges$to, nrow = 30L)
    distance <- as.matrix(stats::dist(x))
    diag(distance) <- Inf
    reference <- vapply(seq_len(nrow(x)), function(i) {
        order(distance[i, ], method = "radix")[seq_len(30L)]
    }, integer(30L))
    recall <- mean(vapply(seq_len(nrow(x)), function(i) {
        length(intersect(reference[, i], observed[, i])) / 30
    }, 0.0))
    pca_fit <- fastEmbedR::pca(sampled$source, ncomp = 2L,
        backend = "cpu", n.cores = 4L, massive = "out_of_core",
        output = file.path(out, "pca.f32"), chunk_rows = 128L,
        memory_limit = "1GB", seed = 4L)
    scores <- massive_read_rows(pca_fit$scores, 1L, nrow(x))
    reference_scores <- stats::prcomp(x, center = TRUE,
        scale. = FALSE, rank. = 2L)$x[, 1:2, drop = FALSE]
    indices <- unique(as.integer(round(seq(1, nrow(x), length.out = 256L))))
    agreement <- stats::cor(as.vector(stats::dist(scores[indices, ])),
        as.vector(stats::dist(reference_scores[indices, ])))
    if (!is.finite(recall) || recall < 0.99 ||
        !is.finite(agreement) || agreement < 0.95) {
        stop(sprintf("Matched thresholds failed: recall %.4f, PCA %.4f",
            recall, agreement))
    }
    layout_quality <- matched_layouts(x, knn, pca_fit, out)
    c(list(knn_recall = recall,
        pca_distance_correlation = agreement,
        backend_observed = knn$backend), layout_quality)
}

matched_layouts <- function(x, knn, pca_fit, out) {
    memberships <- massive_umap_memberships(knn,
        backend = "cpu", n.cores = 4L)
    fuzzy <- massive_umap_fuzzy_graph(memberships,
        output = file.path(out, "fuzzy"), backend = "cpu",
        memory_limit = "1GB")
    file_umap <- massive_umap_optimize(fuzzy, pca_fit$scores,
        output = file.path(out, "umap.f32"), backend = "cpu",
        n.cores = 1L, n_epochs = 200L, min_dist = 0.01,
        memory_limit = "1GB", seed = 4L)
    resident_umap <- fastEmbedR::umap(x, n_neighbors = 30L,
        backend = "cpu", n.cores = 4L, seed = 4L)
    affinity <- massive_tsne_affinities(knn, perplexity = 30,
        output = file.path(out, "affinity"), backend = "cpu",
        n.cores = 4L, memory_limit = "1GB")
    scaled <- scaled_tsne_init(pca_fit$scores,
        file.path(out, "tsne_init.f32"))
    file_tsne <- massive_tsne_optimize(affinity, scaled,
        output = file.path(out, "tsne.f32"), backend = "cpu",
        n.cores = 4L, early_exaggeration_iter = 250L,
        n_iter = 750L, learning_rate = "auto",
        memory_limit = "1GB")
    resident_tsne <- fastEmbedR::tsne(x, perplexity = 30,
        backend = "cpu", n.cores = 4L, seed = 4L,
        early_exaggeration_iter = 250L, n_iter = 750L,
        auto_config = FALSE)
    stopifnot(file_umap$backend == "cpu",
        file_tsne$backend == "native_cpu_fft_graph_stream")
    layouts <- list(umap_file = as.matrix(file_umap),
        umap_resident = as.matrix(resident_umap$layout),
        tsne_file = as.matrix(file_tsne),
        tsne_resident = as.matrix(resident_tsne$layout))
    stopifnot(all(vapply(layouts, function(y) {
        identical(dim(y), c(nrow(x), 2L)) && all(is.finite(y))
    }, FALSE)))
    saveRDS(layouts[c("umap_resident", "tsne_resident")],
        file.path(out, "resident_layouts.rds"))
    quality <- vapply(layouts, function(y) {
        neighbor_overlap(x, y, k = 30L)
    }, 0.0)
    if (quality[["umap_file"]] < quality[["umap_resident"]] - 0.10 ||
        quality[["tsne_file"]] < quality[["tsne_resident"]] - 0.10) {
        stop("File-backed layout loses >0.10 Preserve@30")
    }
    as.list(setNames(quality, paste0(names(quality), "_preserve_at_30")))
}

run_pca <- function(source, out, case, devices) {
    fit <- fastEmbedR::pca(source, ncomp = 2L, backend = case$backend,
        n.cores = if (case$backend == "cpu") 4L else 1L,
        massive = "out_of_core", output = file.path(out, "scores.f32"),
        chunk_rows = 5000L, memory_limit = "4GB", seed = 4L,
        devices = devices, checkpoint = TRUE)
    stopifnot(fit$backend == case$backend,
        fit$scores$nrow == source$nrow,
        all(is.finite(massive_read_rows(fit$scores, 1L, 6L))))
    check_devices(fit, devices)
    list(backend_observed = fit$backend, pca_method = fit$method,
        output_bytes = file.info(fit$scores$path)$size,
        output_path = fit$scores$path,
        gpu_devices_observed = paste(fit$gpu_devices, collapse = ":"))
}

check_devices <- function(fit, devices) {
    if (is.null(devices)) return(invisible(NULL))
    stopifnot(identical(as.integer(fit$gpu_devices), devices))
    resources <- if (!is.null(fit$per_device)) fit$per_device else {
        fit$resources$per_device
    }
    used <- if (!is.null(resources)) {
        vapply(resources, function(item) {
            if (!is.null(item$resources)) item$resources$gpu_device else {
                item$gpu_device
            }
        }, 0L)
    } else fit$resources$gpu_device
    stopifnot(identical(as.integer(used), devices))
}

run_recovery <- function(source, out, case) {
    sampled <- sample_rows(source, out, case$rows)
    output <- file.path(out, "resumed.f32")
    fresh <- file.path(out, "fresh.f32")
    fit <- function(path, resume = FALSE, checkpoint = FALSE) {
        fastEmbedR::pca(sampled$source, ncomp = 2L,
            backend = case$backend, n.cores = 2L,
            massive = "out_of_core", output = path,
            chunk_rows = 32L, memory_limit = "256MB",
            checkpoint = checkpoint, resume = resume)
    }
    child <- file.path(suite, "file_backed", "recovery_child.R")
    child_log <- file.path(out, "interrupted_child.log")
    command <- file.path(R.home("bin"), "Rscript")
    status <- suppressWarnings(system2(command, shQuote(c(child,
        sampled$source$path, output, case$backend, case$rows)),
        stdout = child_log, stderr = child_log))
    if (status == 0L) stop("Recovery child was not interrupted")
    sidecar <- paste0(output, ".checkpoint.rds")
    if (!file.exists(sidecar)) stop("Checkpoint was not persisted")
    state <- readRDS(sidecar)
    if (state$stage != "covariance_partial" ||
        state$cross_rows <= 0) stop("No partial covariance progress")
    resumed <- fit(output, resume = TRUE, checkpoint = TRUE)
    reference <- fit(fresh)
    left <- massive_read_rows(resumed$scores, 1L, case$rows)
    right <- massive_read_rows(reference$scores, 1L, case$rows)
    error <- max(abs(left - right))
    if (!is.finite(error) || error > 1e-5 || file.exists(sidecar)) {
        stop("Resume differs from fresh PCA or checkpoint remains")
    }
    stopifnot(resumed$backend == case$backend)
    list(backend_observed = resumed$backend,
        child_exit_status = status,
        completed_rows_before_interrupt = state$cross_rows,
        max_score_error = error)
}

run_knn <- function(source, out, case, devices) {
    if (case$analysis == "multi_gpu") {
        reference <- fastEmbedR:::massive_matrix_rows(
            source, 1L, case$landmarks)
        fit <- massive_landmark_knn(source, reference, k = 30L,
            output = file.path(out, "knn"), backend = "cuda",
            method = "exact", devices = devices, n.cores = 1L,
            chunk_rows = 5000L, memory_limit = "4GB")
    } else {
        method <- if (case$backend == "cpu") {
            "hnsw_sharded"
        } else "ivf_sharded"
        fit <- massive_full_knn_graph(source, k = 30L,
            output = file.path(out, "knn"), backend = case$backend,
            method = method, n.cores = 4L, chunk_rows = 5000L,
            reference_chunk_rows = 200000L, memory_limit = "4GB",
            audit_rows = 64L, checkpoint = TRUE)
    }
    stopifnot(fit$backend == case$backend)
    if (case$analysis == "multi_gpu") check_devices(fit, devices)
    observed <- if (case$analysis == "multi_gpu") {
        massive_read_knn_rows(fit, first = 1L, n = 6L)$distances
    } else massive_read_graph_edges(fit, first = 1L, n = 6L)$distance
    stopifnot(all(is.finite(observed)))
    list(backend_observed = fit$backend, knn_method = fit$method,
        exact = if (is.null(fit$exact)) NA else fit$exact,
        output_path = fit$indices_path,
        gpu_devices_observed = paste(fit$gpu_devices, collapse = ":"))
}

quality_sample <- function(source, layout, out, size = 256L) {
    rows <- unique(as.integer(round(seq(1, source$nrow,
        length.out = size))))
    high <- do.call(rbind, lapply(rows, function(i) {
        massive_read_rows(source, i, 1L)
    }))
    low <- if (is.matrix(layout)) layout[rows, , drop = FALSE] else {
        do.call(rbind, lapply(rows, function(i) {
            massive_read_rows(layout, i, 1L)
        }))
    }
    utils::write.csv(data.frame(source_row = rows),
        file.path(out, "quality_rows.csv"), row.names = FALSE)
    neighbor_overlap(high, low, k = 30L)
}

run_landmark <- function(source, out, case, devices) {
    common <- list(data = source, backend = case$backend, n.cores = 1L,
        seed = 4L, massive = "landmark", output = file.path(out, "layout.f32"),
        landmarks = as.integer(case$landmarks),
        landmark_method = "random", transform_k = 30L,
        chunk_rows = 5000L, memory_limit = "4GB", devices = devices)
    fit <- if (case$method == "umap") {
        do.call(fastEmbedR::umap, c(common, list(n_neighbors = 30L)))
    } else do.call(fastEmbedR::tsne, c(common, list(perplexity = 30,
        early_exaggeration_iter = 250L, n_iter = 750L,
        transform_perplexity = 5, transform_iter = 250L,
        auto_config = FALSE)))
    stopifnot(fit$backend == case$backend,
        fit$layout$nrow == source$nrow,
        fit$graph$backend == case$backend)
    check_devices(fit, devices)
    sample <- massive_read_rows(fit$layout, 1L, 6L)
    stopifnot(all(is.finite(sample)))
    list(backend_observed = fit$backend,
        output_bytes = file.info(fit$layout$path)$size,
        output_path = fit$layout$path,
        landmark_rows = length(fit$selection$indices),
        preserve_at_30_sample = quality_sample(source, fit$layout, out),
        gpu_devices_observed = paste(fit$gpu_devices, collapse = ":"))
}

run_full <- function(source, out, case) {
    rows <- as.integer(source$nrow)
    started <- proc.time()[[3L]]
    knn <- massive_full_knn_graph(source, k = 30L,
        output = file.path(out, "knn"), backend = "cuda",
        method = "ivf_sharded", n.cores = 4L,
        chunk_rows = 5000L, reference_chunk_rows = 50000L,
        memory_limit = "4GB", audit_rows = 64L,
        checkpoint = TRUE)
    knn_seconds <- proc.time()[[3L]] - started
    init <- fastEmbedR::pca(source, ncomp = 2L,
        massive = "out_of_core", output = file.path(out, "pca.f32"),
        backend = "cuda", n.cores = 1L, seed = 4L,
        chunk_rows = 5000L, memory_limit = "4GB")
    pca_seconds <- proc.time()[[3L]] - started - knn_seconds
    if (case$method == "umap") {
        memberships <- massive_umap_memberships(knn,
            backend = "cpu", n.cores = 4L, checkpoint = TRUE)
        graph <- massive_umap_fuzzy_graph(memberships,
            output = file.path(out, "fuzzy"), memory_limit = "1GB",
            backend = "cpu", checkpoint = TRUE)
        graph_seconds <- proc.time()[[3L]] - started -
            knn_seconds - pca_seconds
        fit <- massive_umap_optimize(graph, init$scores,
            output = file.path(out, "layout.f32"), n_epochs = 200L,
            min_dist = 0.01, seed = 4L, backend = "cuda",
            n.cores = 1L, chunk_rows = 8192L,
            memory_limit = "4GB", checkpoint = TRUE,
            checkpoint_every = 50L)
    } else {
        graph <- massive_tsne_affinities(knn, perplexity = 30,
            output = file.path(out, "affinity"),
            memory_limit = "1GB", backend = "cpu",
            n.cores = 4L, checkpoint = TRUE)
        scaled <- scaled_tsne_init(init$scores,
            file.path(out, "tsne_init.f32"))
        graph_seconds <- proc.time()[[3L]] - started -
            knn_seconds - pca_seconds
        fit <- massive_tsne_optimize(graph, scaled,
            output = file.path(out, "layout.f32"),
            early_exaggeration_iter = 250L, n_iter = 750L,
            learning_rate = "auto", backend = "cuda", n.cores = 1L,
            memory_limit = "4GB", checkpoint = TRUE,
            checkpoint_every = 250L)
    }
    optimize_seconds <- proc.time()[[3L]] - started -
        knn_seconds - pca_seconds - graph_seconds
    stopifnot(knn$backend == "cuda", init$backend == "cuda",
        fit$nrow == rows, fit$ncol == 2L,
        all(is.finite(massive_read_rows(fit, 1L, 6L))),
        fit$backend %in% c("cuda", "native_cuda_fft_graph_stream"))
    list(backend_observed = fit$backend,
        knn_method = knn$method,
        knn_seconds = knn_seconds, pca_seconds = pca_seconds,
        graph_seconds = graph_seconds,
        optimize_seconds = optimize_seconds,
        output_bytes = file.info(fit$path)$size,
        output_path = fit$path,
        preserve_at_30_sample = quality_sample(source, fit, out))
}

scaled_tsne_init <- function(scores, path) {
    rows <- scores$nrow
    sums <- numeric(2L)
    squares <- numeric(2L)
    for (first in seq(1L, rows, by = 5000L)) {
        block <- massive_read_rows(scores, first,
            min(5000L, rows - first + 1L))
        sums <- sums + colSums(block)
        squares <- squares + colSums(block^2)
    }
    center <- sums / rows
    variance <- (squares - rows * center^2) / (rows - 1L)
    scale <- 1e-4 / sqrt(max(variance))
    if (!is.finite(scale) || scale <= 0) stop("Invalid PCA init")
    con <- file(path, "wb")
    for (first in seq(1L, rows, by = 5000L)) {
        block <- massive_read_rows(scores, first,
            min(5000L, rows - first + 1L))
        block <- sweep(block, 2L, center, "-") * scale
        writeBin(as.vector(t(block)), con, size = 4L,
            endian = "little")
    }
    close(con)
    massive_matrix(path, rows, 2L, format = "f32")
}

run_case <- function(case, input, out) {
    source <- input$data
    devices <- if (is.na(case$devices) || !nzchar(case$devices)) NULL else {
        as.integer(strsplit(case$devices, ":", fixed = TRUE)[[1L]])
    }
    if (length(devices) > 1L &&
        fastEmbedR:::massive_cuda_device_count_cpp() < length(devices)) {
        blocked("This node does not expose the requested GPU count")
    }
    if (case$analysis == "boundary") {
        budget <- memory_budget()
        if (source$nrow * source$ncol * 4 <= budget$effective) {
            blocked("Real input does not exceed job memory budget")
        }
    }
    if (case$analysis == "recovery") {
        return(run_recovery(source, out, case))
    }
    if (case$analysis == "matched") return(run_matched(source, out, case))
    if (case$analysis == "boundary") {
        result <- run_pca(source, out, case, devices)
        result$physical_ram_bytes <- budget$physical
        result$memory_budget_bytes <- budget$effective
        return(result)
    }
    if (case$route == "full") return(run_full(source, out, case))
    switch(case$method,
        pca = run_pca(source, out, case, devices),
        knn = run_knn(source, out, case, devices),
        umap = run_landmark(source, out, case, devices),
        tsne = run_landmark(source, out, case, devices),
        stop("Unsupported file-backed case"))
}

started <- proc.time()[[3L]]
input <- tryCatch(input_source(case, root), error = identity)
result <- if (inherits(input, "error")) input else {
    tryCatch(run_case(case, input, out), error = identity)
}
failed <- inherits(result, "error")
blocked_case <- inherits(result, "file_backed_blocked")
manifest_hash <- if (inherits(input, "error")) "" else {
    strsplit(system2("sha256sum", input$manifest,
        stdout = TRUE), " +")[[1L]][1L]
}
record <- data.frame(id = case$id, analysis = case$analysis,
    dataset = case$dataset, method = case$method, route = case$route,
    backend_requested = case$backend, rows = case$rows,
    source_rows = if (inherits(input, "error")) NA_real_ else
        input$source_rows,
    source_manifest = if (inherits(input, "error")) "" else
        input$manifest,
    source_manifest_sha256 = manifest_hash,
    source_data_sha256 = if (inherits(input, "error")) "" else
        input$data_sha256,
    source_path = if (inherits(input, "error")) "" else input$path,
    devices = case$devices, landmarks = case$landmarks,
    elapsed_seconds = unname(proc.time()[[3L]] - started),
    peak_rss_bytes = peak_rss(), package_version = expected,
    dll_sha256 = hash,
    status = if (blocked_case) "BLOCKED" else
        if (failed) "FAIL" else "PASS",
    error = if (failed) conditionMessage(result) else "")
if (!failed) record <- cbind(record, as.data.frame(result))
if (!failed && case$analysis == "boundary" &&
    record$peak_rss_bytes >= result$memory_budget_bytes) {
    record$status <- "FAIL"
    record$error <- "Peak RSS did not stay below job memory budget"
    failed <- TRUE
}
utils::write.csv(record, file.path(out, "result.csv"), row.names = FALSE)
print(record)
if (failed) quit(status = 1L)
