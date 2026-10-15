#!/usr/bin/env Rscript
# Run one experimental file-backed scaling case; never materialize full input.

args <- commandArgs(trailingOnly = TRUE)
if (length(args) %% 2L != 0L || any(!grepl("^--", args[c(TRUE, FALSE)]))) {
    stop("Pass named --key value pairs.")
}
options <- setNames(as.list(args[c(FALSE, TRUE)]),
                    sub("^--", "", args[c(TRUE, FALSE)]))
required <- c("input", "rows", "columns", "backend", "mode", "output",
              "csv", "expected-version")
if (!all(required %in% names(options))) {
    stop("Required: --input --rows --columns --backend --mode --output ",
         "--csv --expected-version")
}
option <- function(key, default) options[[key]] %||% default
`%||%` <- function(a, b) if (is.null(a)) b else a
integer_option <- function(key, default) {
    value <- suppressWarnings(as.numeric(option(key, default)))
    if (length(value) != 1L || !is.finite(value) || value < 1 ||
        value != floor(value) || value > .Machine$integer.max) {
        stop("Invalid positive integer: ", key)
    }
    as.integer(value)
}
rows <- integer_option("rows", NA)
first_row <- integer_option("first-row", 1L)
columns <- integer_option("columns", NA)
chunk_rows <- integer_option("chunk-rows", 10000L)
ncores <- integer_option("n-cores", 1L)
seed <- integer_option("seed", 4L)
backend <- options$backend
mode <- options$mode
synthetic <- identical(options$input, "synthetic")
if (synthetic && first_row != 1L) {
    stop("--first-row requires .fbin input.")
}
reuse_model <- options[["reuse-nn-model"]]
build_m <- options[["hnsw-m"]]
build_ef <- options[["hnsw-ef-construction"]]
search_ef <- options[["hnsw-ef-search"]]
if (xor(is.null(build_m), is.null(build_ef))) {
    stop("HNSW M and efConstruction must be set together.")
}
if ((!is.null(build_m) || !is.null(search_ef)) &&
    (mode != "knn" || backend != "cpu")) {
    stop("Explicit HNSW settings require CPU KNN.")
}
hnsw_build <- if (is.null(build_m)) NULL else list(
    m = integer_option("hnsw-m", NA),
    ef_construction = integer_option("hnsw-ef-construction", NA))
ef_search <- if (is.null(search_ef)) 0L else
    integer_option("hnsw-ef-search", NA)
devices <- if (is.null(options$devices)) NULL else {
    values <- suppressWarnings(as.integer(strsplit(
        options$devices, ",", fixed = TRUE)[[1L]]))
    if (!length(values) || anyNA(values) || any(values < 0L) ||
        anyDuplicated(values)) stop("Invalid --devices list.")
    values
}
if (!is.null(devices) && backend != "cuda") {
    stop("--devices requires --backend cuda.")
}
if (!backend %in% c("cpu", "cuda") ||
    !mode %in% c("pca", "knn", "umap", "tsne", "cluster")) {
    stop("This runner supports CPU/CUDA PCA, KNN, embeddings, clustering.")
}
if (mode == "knn" && !is.null(devices)) {
    stop("The full KNN graph route does not accept --devices.")
}
if (!is.null(reuse_model) &&
    (!mode %in% c("umap", "tsne", "cluster") ||
        !file.exists(reuse_model))) {
    stop("--reuse-nn-model needs an embedding or cluster mode and ",
         "an existing model RDS.")
}
model_path <- option("model-rds", paste0(options$output, ".model.rds"))
save_model <- option("save-model", "true")
if (!save_model %in% c("true", "false")) {
    stop("--save-model must be true or false.")
}
result_path <- if (mode == "cluster") {
    paste0(options$output, ".clusters.u32")
} else if (mode == "knn") {
    paste0(options$output, ".indices.u32")
} else options$output
confidence_path <- if (mode == "cluster") {
    paste0(options$output, ".confidence.f32")
} else if (mode == "knn") {
    paste0(options$output, ".distances.f32")
} else NULL
for (path in c(if (!synthetic) options$input,
               result_path, confidence_path, options$csv,
               if (save_model == "true") model_path)) {
    if (!dir.exists(dirname(path))) stop("Missing parent directory: ", path)
}
if (any(file.exists(c(result_path, confidence_path,
                      options$csv,
                      if (save_model == "true") model_path)))) {
    stop("Output, model, or result CSV already exists; use a fresh run.")
}

if (!is.null(options$library)) {
    library_path <- normalizePath(options$library, mustWork = TRUE)
    .libPaths(c(library_path, .libPaths()))
}
library(fastEmbedR)
version <- as.character(packageVersion("fastEmbedR"))
if (!identical(version, options[["expected-version"]])) {
    stop("Loaded fastEmbedR ", version, ", expected ",
         options[["expected-version"]])
}
dll <- getLoadedDLLs()[["fastEmbedR"]][["path"]]
dll_hash <- strsplit(system2("sha256sum", dll, stdout = TRUE), " +")[[1L]][1L]
if (length(dll_hash) != 1L || !grepl("^[0-9a-f]{64}$", dll_hash)) {
    stop("Could not hash the loaded fastEmbedR shared library.")
}
if (!is.null(options[["expected-dll-sha256"]]) &&
    !identical(dll_hash, options[["expected-dll-sha256"]])) {
    stop("Loaded fastEmbedR DLL does not match expected SHA-256.")
}
source <- if (synthetic) {
    fastEmbedR:::massive_synthetic_matrix(rows, columns)
} else if (endsWith(options$input, ".fbin")) {
    original <- massive_matrix(options$input)
    if (original$ncol != columns ||
        as.double(first_row) + rows - 1 > original$nrow) {
        stop("Requested .fbin view exceeds the source dimensions.")
    }
    if (rows == original$nrow && first_row == 1L) original else {
        fastEmbedR:::massive_matrix_rows(original, first_row, rows)
    }
} else {
    if (first_row != 1L) stop("--first-row requires .fbin input.")
    massive_matrix(options$input, nrow = rows, ncol = columns)
}
peak_rss <- function() {
    if (!file.exists("/proc/self/status")) return(NA_real_)
    status <- readLines("/proc/self/status", warn = FALSE)
    match <- grep("^VmHWM:", status, value = TRUE)
    if (!length(match)) return(NA_real_)
    as.numeric(sub("^VmHWM:[[:space:]]*([0-9]+).*", "\\1", match)) * 1024
}
process_io <- function() {
    keys <- c("rchar", "wchar", "read_bytes", "write_bytes")
    values <- setNames(rep(NA_real_, length(keys)), keys)
    if (!file.exists("/proc/self/io")) return(values)
    lines <- tryCatch(readLines("/proc/self/io", warn = FALSE),
                      error = function(e) character())
    for (key in keys) {
        line <- grep(paste0("^", key, ":"), lines, value = TRUE)
        if (length(line) == 1L) {
            values[[key]] <- as.numeric(sub("^[^:]+:[[:space:]]*", "", line))
        }
    }
    values
}
effective_hnsw_table <- function(graph) {
    count <- graph$resources$n_shards
    settings <- graph$hnsw_settings
    if (is.null(count) || count < 1L || !length(settings)) {
        stop("CPU HNSW graph did not report effective shard settings.")
    }
    size <- floor(graph$n_vertices / count)
    extra <- graph$n_vertices %% count
    sizes <- size + as.integer(seq_len(count) <= extra)
    selected <- lapply(sizes, function(rows) {
        matches <- Filter(function(item) {
            identical(as.numeric(item$reference_rows), as.numeric(rows))
        }, settings)
        if (length(matches) != 1L) {
            stop("Ambiguous effective HNSW settings for shard size ", rows)
        }
        matches[[1L]]
    })
    data.frame(shard = seq_len(count), reference_rows = sizes,
        m = vapply(selected, function(item) as.integer(item$m),
            integer(1)),
        ef_construction = vapply(selected, function(item) {
            as.integer(item$ef_construction)
        }, integer(1)),
        ef_search = vapply(selected, function(item) {
            as.integer(item$ef_search)
        }, integer(1)),
        tuning_rule = vapply(selected, function(item) {
            as.character(item$tuning_rule)
        }, character(1)))
}
baseline_rss <- peak_rss()
io_before <- process_io()
time_before <- proc.time()
error <- ""
warning_count <- 0L
warning_messages <- character()
result <- withCallingHandlers(tryCatch({
    previous <- if (is.null(reuse_model)) NULL else readRDS(reuse_model)
    if (mode == "pca") {
        pca(source, ncomp = integer_option("components", 30L),
            backend = backend, n.cores = ncores, seed = seed,
            devices = devices,
            massive = "out_of_core", output = options$output,
            chunk_rows = chunk_rows,
            memory_limit = option("memory-limit", "256MB"))
    } else if (mode == "knn") {
        massive_full_knn_graph(source,
            k = integer_option("neighbors", 30L),
            output = options$output, backend = backend,
            n.cores = ncores, chunk_rows = chunk_rows,
            reference_chunk_rows = integer_option(
                "reference-chunk-rows", 20000L),
            memory_limit = option("memory-limit", "256MB"),
            method = if (backend == "cpu") "hnsw_sharded" else
                "ivf_sharded",
            hnsw_build = hnsw_build, ef_search = ef_search,
            audit_rows = integer_option("audit-rows", 16L),
            checkpoint = TRUE,
            resume = identical(option("resume", "false"), "true"))
    } else if (mode == "umap") {
        umap(source, n_neighbors = integer_option("neighbors", 10L),
             n_components = integer_option("components", 2L),
             landmarks = integer_option("landmarks", 100L),
             nn = previous,
             transform_k = if (is.null(options[["transform-k"]])) NULL else
                 integer_option("transform-k", NA),
             backend = backend, n.cores = ncores, seed = seed,
             devices = devices,
             massive = "landmark", output = options$output,
             chunk_rows = chunk_rows,
             memory_limit = option("memory-limit", "256MB"))
    } else if (mode == "tsne") {
        tsne(source, perplexity = integer_option("perplexity", 30L),
             n_components = integer_option("components", 2L),
             landmarks = integer_option("landmarks", 100L),
             nn = previous,
             transform_k = if (is.null(options[["transform-k"]])) NULL else
                 integer_option("transform-k", NA),
             transform_iter = integer_option("transform-iter", 10L),
             early_exaggeration_iter = integer_option(
                 "early-iterations", 250L),
             n_iter = integer_option("normal-iterations", 500L),
             backend = backend, n.cores = ncores, seed = seed,
             devices = devices,
             massive = "landmark", output = options$output,
             chunk_rows = chunk_rows,
             memory_limit = option("memory-limit", "256MB"))
    } else {
        massive_cluster(source, method = option("cluster-method", "leiden"),
             landmarks = if (is.null(previous) ||
                 !is.null(options$landmarks)) {
                 integer_option("landmarks", 100L)
             } else NULL,
             nn = previous,
             k = integer_option("neighbors", 10L),
             backend = backend, n.cores = ncores, seed = seed,
             devices = devices,
             massive = "landmark", output = options$output,
             chunk_rows = chunk_rows,
             memory_limit = option("memory-limit", "256MB"))
    }
}, error = function(e) {
    error <<- conditionMessage(e)
    NULL
}), warning = function(w) {
    warning_count <<- warning_count + 1L
    if (length(warning_messages) < 100L) {
        warning_messages <<- unique(c(warning_messages,
            conditionMessage(w)))
    }
    invokeRestart("muffleWarning")
})
writeLines(c(paste("warning_count", warning_count, sep = "="),
    warning_messages), file.path(dirname(options$csv),
    "warnings.txt"))
time_after <- proc.time()
io_after <- process_io()
elapsed <- unname(time_after[[3L]] - time_before[[3L]])
cpu_seconds <- unname(sum(time_after[1:2] - time_before[1:2]))
io_bytes <- io_after - io_before
if (!is.null(result) && !identical(result$backend, backend)) {
    error <- "Reported backend differs from requested backend."
}
if (!is.null(result) && !is.null(devices) &&
    !identical(as.integer(result$gpu_devices), devices)) {
    error <- "Reported CUDA devices differ from requested devices."
}
if (!is.null(result) && !is.null(reuse_model) &&
    !isTRUE(result$graph_reused)) {
    error <- "Requested landmark KNN reuse was not reported by the fit."
}
graph_backend <- if (is.null(result)) NA_character_ else {
    if (mode == "knn") result$backend else if (mode == "cluster") {
        result$graph_backend
    } else {
        if (mode %in% c("umap", "tsne")) result$graph$backend else NA_character_
    }
}
if (!is.null(result) && mode %in% c("knn", "umap", "tsne", "cluster") &&
    !identical(graph_backend, backend)) {
    error <- "KNN backend differs from requested backend."
}
layout <- if (is.null(result)) NULL else {
    if (mode == "knn") NULL else if (mode == "pca") result$scores else {
        if (mode == "cluster") result else result$layout
    }
}
finite_sample <- mode == "knn" && !is.null(result)
if (finite_sample && !nzchar(error)) {
    edges <- massive_read_graph_edges(result, first = 1L, n = 1L)
    finite_sample <- length(edges$to) == result$k &&
        all(edges$to >= 1L & edges$to <= rows) &&
        all(is.finite(edges$distance))
    if (!finite_sample) error <- "KNN sample contains invalid edges."
}
if (!is.null(layout) && !nzchar(error)) {
    first <- unique(c(1, floor(rows / 2), rows))
    finite_sample <- all(vapply(first, function(i) {
        if (mode == "cluster") {
            value <- massive_read_cluster_rows(layout, first = i, n = 1L)
            return(all(value$membership >= 1L) &&
                all(is.finite(value$confidence)) &&
                all(value$confidence >= 0 & value$confidence <= 1))
        }
        all(is.finite(massive_read_rows(layout, first = i, n = 1L)))
    }, logical(1)))
    if (!finite_sample) error <- "Output sample contains non-finite values."
}
if (!is.null(result) && mode == "cluster" && !nzchar(error)) {
    selected <- result$selection$indices
    labels <- result$reference_membership
    if (length(selected) != length(labels) || !length(selected)) {
        error <- "Clustering landmark labels are incomplete."
    } else {
        path <- file.path(dirname(options$csv),
                          "landmark_labels.csv.gz")
        stream <- gzfile(path, "wt")
        utils::write.csv(data.frame(row_id = first_row + selected - 1,
            membership = labels), stream, row.names = FALSE)
        close(stream)
    }
}
expected_bytes <- if (mode == "knn") {
    as.double(rows) * integer_option("neighbors", 30L) * 4
} else if (is.null(layout)) NA_real_ else {
    as.double(rows) * if (mode == "cluster") 4 else layout$ncol * 4
}
output_bytes <- if (file.exists(result_path)) {
    file.info(result_path)$size
} else NA_real_
confidence_bytes <- if (!is.null(confidence_path) &&
                        file.exists(confidence_path)) {
    file.info(confidence_path)$size
} else NA_real_
if (!is.null(result) && !nzchar(error) &&
    !identical(as.numeric(output_bytes), as.numeric(expected_bytes))) {
    error <- "Output file size differs from expected dimensions."
}
if (!is.null(result) && mode %in% c("knn", "cluster") &&
    !nzchar(error) && !identical(as.numeric(confidence_bytes),
        if (mode == "knn") expected_bytes else as.double(rows) * 4)) {
    error <- "Secondary output file size differs from expected bytes."
}
hnsw_table <- NULL
hnsw_path <- file.path(dirname(options$csv), "hnsw_shards.csv.gz")
if (!is.null(result) && mode == "knn" && backend == "cpu" &&
    !nzchar(error)) {
    tryCatch({
        hnsw_table <- effective_hnsw_table(result)
        local({
            stream <- gzfile(hnsw_path, "wt")
            on.exit(close(stream))
            utils::write.csv(hnsw_table, stream, row.names = FALSE)
        })
    }, error = function(e) {
        error <<- paste("HNSW settings evidence:", conditionMessage(e))
    })
}
audit_path <- file.path(dirname(options$csv), "knn_audit_rows.csv.gz")
if (!is.null(result) && mode == "knn" && !nzchar(error)) {
    tryCatch({
        if (!isTRUE(result$recall_audited) ||
            length(result$audit_sample_rows) !=
                length(result$audit_row_recall)) {
            stop("KNN recall audit did not report its sampled rows.")
        }
        local({
            stream <- gzfile(audit_path, "wt")
            on.exit(close(stream))
            utils::write.csv(data.frame(
                row = first_row + result$audit_sample_rows - 1,
                recall = result$audit_row_recall),
                stream, row.names = FALSE)
        })
    }, error = function(e) {
        error <<- paste("KNN exact audit evidence:", conditionMessage(e))
    })
}
if (!is.null(result) && !nzchar(error) && save_model == "true") {
    tryCatch(saveRDS(result, model_path), error = function(e) {
        error <<- paste("Could not save model:", conditionMessage(e))
    })
}
record <- data.frame(
    status = if (nzchar(error)) "failed" else "ok",
    error = error, mode = mode, backend_requested = backend,
    backend_observed = if (is.null(result)) NA_character_ else result$backend,
    devices_requested = if (is.null(devices)) NA_character_ else
        paste(devices, collapse = ","),
    pca_method = if (mode == "pca" && !is.null(result)) {
        result$method
    } else NA_character_,
    pca_sketch_size = if (mode == "pca" && !is.null(result)) {
        result$sketch_size %||% NA_integer_
    } else NA_integer_,
    pca_moments_backend = if (mode == "pca" && !is.null(result)) {
        result$moments_backend %||% NA_character_
    } else NA_character_,
    pca_sketch_backend = if (mode == "pca" && !is.null(result)) {
        result$sketch_backend %||% NA_character_
    } else NA_character_,
    knn_backend = graph_backend,
    knn_method = if (mode == "knn" && !is.null(result)) {
        result$method
    } else NA_character_,
    hnsw_m_requested = if (is.null(hnsw_build)) NA_integer_ else
        hnsw_build$m,
    hnsw_ef_construction_requested = if (is.null(hnsw_build)) {
        NA_integer_
    } else hnsw_build$ef_construction,
    hnsw_ef_search_requested = if (ef_search == 0L) NA_integer_ else
        ef_search,
    hnsw_shard_count = if (is.null(hnsw_table)) NA_integer_ else
        nrow(hnsw_table),
    hnsw_m_effective = if (is.null(hnsw_table)) NA_character_ else
        paste(sort(unique(hnsw_table$m)), collapse = ","),
    hnsw_ef_construction_effective = if (is.null(hnsw_table)) {
        NA_character_
    } else paste(sort(unique(hnsw_table$ef_construction)), collapse = ","),
    hnsw_ef_search_effective = if (is.null(hnsw_table)) NA_character_ else
        paste(sort(unique(hnsw_table$ef_search)), collapse = ","),
    hnsw_tuning_rule_effective = if (is.null(hnsw_table)) {
        NA_character_
    } else paste(sort(unique(hnsw_table$tuning_rule)), collapse = ","),
    hnsw_shards_csv_gz = if (is.null(hnsw_table)) NA_character_ else
        hnsw_path,
    knn_recall_mean = if (mode == "knn" && !is.null(result)) {
        result$observed_recall %||% NA_real_
    } else NA_real_,
    knn_recall_min = if (mode == "knn" && !is.null(result)) {
        result$minimum_row_recall %||% NA_real_
    } else NA_real_,
    knn_audit_rows = if (mode == "knn" && !is.null(result)) {
        result$audit_rows %||% NA_integer_
    } else NA_integer_,
    knn_audit_rows_csv_gz = if (mode == "knn" && !nzchar(error)) {
        audit_path
    } else NA_character_,
    graph_reused = if (is.null(result) ||
        !mode %in% c("umap", "tsne", "cluster")) NA else
        result$graph_reused,
    reused_model = if (is.null(reuse_model)) NA_character_ else
        normalizePath(reuse_model),
    cluster_method = if (mode == "cluster" && !is.null(result)) {
        result$method
    } else NA_character_,
    n_communities = if (mode == "cluster" && !is.null(result)) {
        result$n_communities
    } else NA_integer_,
    transform_iter = if (mode == "tsne") {
        integer_option("transform-iter", 10L)
    } else NA_integer_,
    fastembedr_version = version, package_path = find.package("fastEmbedR"),
    dll_sha256 = dll_hash,
    input = if (synthetic) "synthetic" else normalizePath(options$input),
    input_kind = if (synthetic) "virtual" else if (
        endsWith(options$input, ".fbin")
    ) if (first_row == 1L) "fbin_prefix_view" else
        "fbin_row_view" else "file",
    input_bytes = if (synthetic) as.double(rows) * columns * 4 else {
        file.info(options$input)$size
    },
    selected_input_bytes = as.double(rows) * columns * 4,
    rows = rows, first_row = first_row, columns = columns,
    chunk_rows = chunk_rows, ncores = ncores, seed = seed,
    memory_limit = option("memory-limit", "256MB"),
    elapsed_seconds = elapsed,
    rows_per_second = if (elapsed > 0) rows / elapsed else NA_real_,
    cpu_seconds = cpu_seconds,
    cpu_equivalent_cores = if (elapsed > 0) {
        cpu_seconds / elapsed
    } else NA_real_,
    process_read_bytes = unname(io_bytes[["read_bytes"]]),
    process_write_bytes = unname(io_bytes[["write_bytes"]]),
    logical_read_bytes = unname(io_bytes[["rchar"]]),
    logical_write_bytes = unname(io_bytes[["wchar"]]),
    process_read_mib_per_second = if (elapsed > 0) {
        unname(io_bytes[["read_bytes"]]) / elapsed / 1024^2
    } else NA_real_,
    process_write_mib_per_second = if (elapsed > 0) {
        unname(io_bytes[["write_bytes"]]) / elapsed / 1024^2
    } else NA_real_,
    rss_baseline_bytes = baseline_rss,
    rss_peak_bytes = peak_rss(),
    rss_delta_bytes = peak_rss() - baseline_rss,
    algorithm_ram_estimate_bytes = if (is.null(result)) NA_real_ else {
        result$resources$peak_ram_bytes
    },
    vram_estimate_bytes = if (is.null(result)) NA_real_ else {
        result$resources$peak_vram_bytes %||% NA_real_
    },
    output_bytes = output_bytes, confidence_bytes = confidence_bytes,
    components = if (mode %in% c("pca", "umap", "tsne")) {
        integer_option("components", 2L)
    } else NA_integer_,
    finite_sample = finite_sample,
    model_rds = if (save_model == "true" && file.exists(model_path)) {
        model_path
    } else NA_character_
)
write.csv(record, options$csv, row.names = FALSE, na = "")
print(record)
if (nzchar(error)) quit(status = 1L)
