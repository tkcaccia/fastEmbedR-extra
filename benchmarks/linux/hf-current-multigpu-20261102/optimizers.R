args <- commandArgs(trailingOnly = TRUE)
stopifnot(length(args) >= 3L)
library(fastEmbedR)

mode <- args[[1L]]
work <- args[[2L]]
out <- args[[3L]]
if (!dir.exists(work) || !dir.exists(out)) stop("Missing work directory.")

source_data <- function() {
    n <- as.integer(Sys.getenv("FASTEMBEDR_ROWS", "17"))
    stopifnot(is.finite(n), n >= 17L)
    k <- if (n <= 17L) 3L else
        as.integer(Sys.getenv("FASTEMBEDR_K", "3"))
    stopifnot(is.finite(k), k >= 3L, k < n)
    prefix <- file.path(work, "ring")
    paths <- c(paste0(prefix, ".indices.u32"),
        paste0(prefix, ".distances.f32"),
        file.path(work, "init2.f32"),
        file.path(work, "init3.f32"))
    streams <- lapply(paths, file, open = "wb")
    on.exit(invisible(lapply(streams, function(stream)
        try(close(stream), silent = TRUE))))
    for (first in seq.int(1L, n, by = 8192L)) {
        rows <- seq.int(first, min(n, first + 8191L))
        ids <- outer(rows, seq_len(k), function(i, j)
            (i + j - 1L) %% n + 1L)
        distances <- matrix(rep(seq(0.2, 0.9,
            length.out = k), length(rows)),
            nrow = length(rows), byrow = TRUE)
        writeBin(as.integer(t(ids)), streams[[1L]],
            size = 4L, endian = "little")
        writeBin(as.vector(t(distances)), streams[[2L]],
            size = 4L, endian = "little")
        for (dimensions in 2:3) {
            initial <- outer(rows, seq_len(dimensions),
                function(i, j) sin(i * j / 7) * 0.02)
            writeBin(as.vector(t(initial)),
                streams[[dimensions + 1L]], size = 4L,
                endian = "little")
        }
    }
    invisible(lapply(streams, close))
    graph <- massive_knn_graph(prefix, n, k)
    umap <- massive_umap_fuzzy_graph(graph,
        file.path(work, "umap_graph"), memory_limit = "64MB",
        sort_method = "bucketed")
    tsne <- massive_tsne_affinities(graph, k,
        file.path(work, "tsne_graph"), memory_limit = "64MB")
    saveRDS(list(umap = umap, tsne = tsne, n = n, k = k),
        file.path(work, "graphs.rds"))
}

check_output <- function(result, rows) {
    stopifnot(file.info(result$path)$size ==
        as.double(rows) * result$ncol * 4)
    for (first in seq.int(1L, rows, by = 8192L)) {
        count <- min(8192L, rows - first + 1L)
        stopifnot(all(is.finite(massive_read_rows(
            result, first, count))))
    }
    rows
}

optimizer_evidence <- function(result, method, devices) {
    if (!method %in% c("umap", "tsne")) stop(
        "Unknown optimizer method.")
    positive <- function(value) is.numeric(value) &&
        length(value) == 1L && is.finite(value) && value > 0
    uuids <- result$gpu_identity
    work <- if (method == "umap")
        result$resources$per_device_edge_visits else
        result$resources$per_device_attraction_edges
    if (!is.character(uuids) || length(uuids) != length(devices) ||
        any(!nzchar(uuids)) || anyDuplicated(uuids) ||
        !is.numeric(work) || length(work) != length(devices) ||
        any(!is.finite(work)) || any(work <= 0)) stop(
        "Optimizer did not identify work on every requested GPU.")
    owner <- result$resources$owner_wall_seconds
    fft <- result$resources$fft_owner_device
    if (length(devices) > 1L &&
        (!positive(owner) ||
         (method == "tsne" &&
          (!identical(as.integer(fft), devices[[1L]]) ||
           !positive(result$gpu_stage_seconds$repulsion))) ||
         (method == "umap" &&
          !positive(result$resources$synchronization_seconds)))) stop(
        "Coordinated optimizer timing or FFT owner is incomplete.")
    list(uuids = paste(uuids, collapse = ";"),
         work = paste(work, collapse = ";"),
         owner_wall_seconds = if (length(devices) > 1L) owner
             else NA_real_,
         fft_owner_device = if (method == "tsne" &&
             length(devices) > 1L) fft else NA_integer_)
}

fit <- function() {
    stopifnot(length(args) == 6L)
    method <- args[[4L]]
    if (!method %in% c("umap", "tsne")) stop(
        "Unknown optimizer method.")
    devices <- as.integer(strsplit(args[[5L]], ",", fixed = TRUE)[[1L]])
    label <- args[[6L]]
    graphs <- readRDS(file.path(work, "graphs.rds"))
    dims <- if (method == "umap") 3L else 2L
    init <- massive_matrix(file.path(work,
        paste0("init", dims, ".f32")), graphs$n, dims)
    output <- file.path(work, paste0(label, ".f32"))
    before <- proc.time()[[3L]]
    epochs <- as.integer(Sys.getenv("FASTEMBEDR_UMAP_EPOCHS", "8"))
    iterations <- as.integer(Sys.getenv("FASTEMBEDR_TSNE_ITER", "3"))
    chunk_rows <- if (graphs$n <= 17L) 4L else
        as.integer(Sys.getenv("FASTEMBEDR_CHUNK_ROWS", "8192"))
    stopifnot(epochs > 0L, iterations > 0L, chunk_rows > 0L)
    result <- if (method == "umap") massive_umap_optimize(
        graphs$umap, init, output, n_epochs = epochs,
        negative_sample_rate = 1L, chunk_rows = chunk_rows,
        memory_limit = "1GB", backend = "cuda",
        devices = devices) else massive_tsne_optimize(
        graphs$tsne, init, output, early_exaggeration_iter = 2L,
        n_iter = iterations, learning_rate = 1, memory_limit = "1GB",
        backend = "cuda", devices = devices)
    seconds <- proc.time()[[3L]] - before
    output_rows <- check_output(result, graphs$n)
    stopifnot(identical(result$gpu_devices, devices))
    evidence <- optimizer_evidence(result, method, devices)
    if (Sys.getenv("FASTEMBEDR_SAVE_LAYOUT", "0") == "1")
        stopifnot(file.copy(output, file.path(out,
            paste0(label, ".f32"))))
    if (method == "umap")
        stopifnot(identical(result$optimizer,
            "synchronized_cuda_nccl"),
            all(result$resources$per_device_edge_visits > 0))
    if (method == "umap") stopifnot(
        is.finite(result$stage_seconds$graph_visit),
        result$stage_seconds$graph_visit > 0,
        is.finite(result$stage_seconds$device_step),
        result$stage_seconds$device_step > 0)
    if (method == "tsne" && length(devices) > 1L)
        stopifnot(identical(result$backend,
            "native_cuda_fft_graph_coordinated_nccl"),
            identical(result$resources$graph_feeder,
                "concurrent_owner"),
            all(result$resources$
            per_device_attraction_edges > 0))
    finalization_seconds <- if (method == "umap")
        result$resources$finalization_block_seconds else
        result$stage_seconds$update_sync
    if (is.null(finalization_seconds))
        finalization_seconds <- NA_real_
    stage_value <- function(name) {
        value <- result$stage_seconds[[name]]
        if (is.null(value)) NA_real_ else value
    }
    write.csv(data.frame(method = method, devices = args[[5L]],
        neighbors = graphs$k, epochs = if (method == "umap")
            epochs else NA_integer_, iterations = if (method == "tsne")
            iterations else NA_integer_, chunk_rows = if (method ==
            "umap") chunk_rows else NA_integer_,
        seconds = seconds, synchronization_seconds = if (
            method == "umap") result$resources$
            synchronization_seconds else NA_real_,
        finalization_block_seconds = finalization_seconds,
        repulsion_enqueue_seconds = stage_value("repulsion_enqueue"),
        repulsion_gpu_seconds = if (is.null(
            result$gpu_stage_seconds$repulsion)) NA_real_ else
            result$gpu_stage_seconds$repulsion,
        attraction_block_seconds = stage_value("attraction_sync"),
        graph_visit_seconds = stage_value("graph_visit"),
        device_step_seconds = stage_value("device_step"),
        output_rows = output_rows,
        output_bytes = file.info(output)$size,
        optimizer = result$optimizer,
        graph_feeder = result$resources$graph_feeder,
        per_device_work = evidence$work,
        gpu_uuids = evidence$uuids,
        owner_wall_seconds = evidence$owner_wall_seconds,
        fft_owner_device = evidence$fft_owner_device),
        file.path(out, paste0(label, ".csv")), row.names = FALSE)
}

compare_layouts <- function(baseline, candidate, rows, columns,
                            method) {
    sample_rows <- unique(as.integer(seq(1L, rows,
        length.out = min(rows, 512L))))
    sample_baseline <- matrix(NA_real_, length(sample_rows), columns)
    sample_candidate <- sample_baseline
    maximum <- error_sq <- reference_sq <- 0
    for (first in seq.int(1L, rows, by = 8192L)) {
        count <- min(8192L, rows - first + 1L)
        reference <- massive_read_rows(baseline, first, count)
        observed <- massive_read_rows(candidate, first, count)
        stopifnot(all(is.finite(reference)), all(is.finite(observed)))
        difference <- observed - reference
        maximum <- max(maximum, abs(difference))
        error_sq <- error_sq + sum(difference^2)
        reference_sq <- reference_sq + sum(reference^2)
        selected <- which(sample_rows >= first &
            sample_rows < first + count)
        local <- sample_rows[selected] - first + 1L
        sample_baseline[selected, ] <- reference[local, , drop = FALSE]
        sample_candidate[selected, ] <- observed[local, , drop = FALSE]
    }
    shape <- suppressWarnings(stats::cor(
        as.vector(stats::dist(sample_baseline)),
        as.vector(stats::dist(sample_candidate)),
        method = "spearman"))
    ring_gap <- abs(outer(sample_rows, sample_rows, "-"))
    ring_gap <- pmin(ring_gap, rows - ring_gap)
    ring_gap <- ring_gap[lower.tri(ring_gap)]
    ring_quality <- function(layout) suppressWarnings(stats::cor(
        ring_gap, as.vector(stats::dist(layout)),
        method = "spearman"))
    baseline_quality <- ring_quality(sample_baseline)
    candidate_quality <- ring_quality(sample_candidate)
    stopifnot(reference_sq > 0, is.finite(shape),
        is.finite(baseline_quality), is.finite(candidate_quality))
    if (method == "tsne") stopifnot(maximum < 1e-3)
    list(maximum = maximum, relative_rmse = sqrt(error_sq / reference_sq),
        shape = shape, sample_rows = length(sample_rows),
        baseline_ring_quality = baseline_quality,
        candidate_ring_quality = candidate_quality)
}

compare <- function() {
    graphs <- readRDS(file.path(work, "graphs.rds"))
    methods <- if (Sys.getenv("FASTEMBEDR_CASES") == "umap")
        "umap" else c("umap", "tsne")
    for (method in methods) {
        columns <- if (method == "umap") 3L else 2L
        baseline <- massive_matrix(file.path(work,
            sprintf("%s_gpu1.f32", method)), graphs$n, columns)
        for (count in c(2L, 4L)) {
            path <- file.path(work,
                sprintf("%s_gpu%d.f32", method, count))
            if (!file.exists(path)) next
            candidate <- massive_matrix(path, graphs$n, columns)
            compared <- compare_layouts(baseline, candidate,
                graphs$n, columns, method)
            write.csv(data.frame(method = method, devices = count,
                execution_status = "complete_finite_rows",
                quality_status = "diagnostic_only",
                comparison_scope = if (method == "umap")
                    "same_synchronized_owner_update" else
                    "same_optimizer_numerical_agreement",
                max_absolute_difference = compared$maximum,
                relative_rmse = compared$relative_rmse,
                pairwise_distance_spearman = compared$shape,
                baseline_ring_quality =
                    compared$baseline_ring_quality,
                candidate_ring_quality =
                    compared$candidate_ring_quality,
                ring_quality_delta = compared$candidate_ring_quality -
                    compared$baseline_ring_quality,
                shape_sample_rows = compared$sample_rows,
                strict_coordinate_match = compared$maximum < 1e-3,
                output_rows = graphs$n),
                file.path(out, sprintf("%s_gpu%d_comparison.csv",
                    method, count)), row.names = FALSE)
        }
    }
}

reference_steps <- function() {
    graphs <- readRDS(file.path(work, "graphs.rds"))
    stopifnot(graphs$n == 17L)
    for (dimensions in 2:3) {
        init <- massive_matrix(file.path(work,
            sprintf("init%d.f32", dimensions)), graphs$n,
            dimensions)
        for (profile in c("attraction", "signed")) {
            negative <- identical(profile, "signed")
            output <- file.path(work, sprintf(
                "umap%d_gpu2_%s.f32", dimensions, profile))
            result <- massive_umap_optimize(graphs$umap, init,
                output, n_epochs = if (negative) 3L else 2L,
                negative_sample_rate = as.integer(negative),
                chunk_rows = 4L, memory_limit = "1GB",
                backend = "cuda", devices = c(0L, 1L))
            stopifnot(check_output(result, graphs$n) == 17L,
                identical(result$optimizer,
                    "synchronized_cuda_nccl"),
                all(result$resources$per_device_edge_visits > 0))
        }
    }
}

switch(mode, prepare = source_data(), fit = fit(),
    compare = compare(), reference_steps = reference_steps(),
    stop("Unknown mode."))
