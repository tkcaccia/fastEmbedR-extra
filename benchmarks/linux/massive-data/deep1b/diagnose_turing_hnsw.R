#!/usr/bin/env Rscript

args <- commandArgs(trailingOnly = TRUE)
if (length(args) < 5L || length(args) > 7L) {
    stop(paste("Usage: diagnose_turing_hnsw.R INPUT.fbin",
        "OUTPUT_DIR SHARD_ROWS AUDIT_ROWS native|faiss|persistent",
        "[M] [efConstruction]"))
}
test_lib <- Sys.getenv("FASTEMBEDR_TEST_LIB")
faiss_lib <- Sys.getenv("FAISSR_TEST_LIB")
.libPaths(c(test_lib[nzchar(test_lib)],
    faiss_lib[nzchar(faiss_lib)], .libPaths()))
input <- normalizePath(args[[1L]], mustWork = TRUE)
dir.create(args[[2L]], recursive = TRUE, showWarnings = FALSE)
output <- normalizePath(args[[2L]], mustWork = TRUE)
shard_rows <- as.integer(args[[3L]])
audit_rows <- as.integer(args[[4L]])
if (is.na(shard_rows) || shard_rows < 2L ||
    1000000L %% shard_rows != 0L) stop("Invalid shard size.")
if (is.na(audit_rows) || audit_rows < 1L ||
    audit_rows > 1000L) stop("Invalid audit size.")
engine <- match.arg(args[[5L]], c("native", "faiss", "persistent"))
m <- if (length(args) >= 6L) as.integer(args[[6L]]) else 12L
ef_construction <- if (length(args) >= 7L) {
    as.integer(args[[7L]])
} else 80L
if (is.na(m) || m < 2L || is.na(ef_construction) ||
    ef_construction < m) stop("Invalid HNSW build settings.")
x <- fastEmbedR::massive_matrix(input)
if (x$nrow != 1000000 || !x$ncol %in% c(96L, 100L)) {
    stop("Expected a one-million-row Deep or Turing prefix.")
}
fit_rows <- as.integer(Sys.getenv("TURING_FIT_ROWS", "1000000"))
if (is.na(fit_rows) || fit_rows < shard_rows ||
    fit_rows > x$nrow || fit_rows %% shard_rows != 0L) {
    stop("Invalid Turing fit rows.")
}
x <- fastEmbedR:::massive_matrix_rows(x, 1L, fit_rows)

k <- 30L
threads <- 4L
rows <- as.integer(floor((seq_len(audit_rows) - 0.5) *
    x$nrow / audit_rows) + 1)
query <- do.call(rbind, lapply(rows, function(i) {
    fastEmbedR::massive_read_rows(x, first = i, n = 1L)
}))
efforts <- if (engine == "faiss") 0L else
    c(0L, 60L, 120L, 240L, 480L, 960L, 1920L)
if (engine == "persistent") query_float <- float::fl(query)
shards <- as.integer(x$nrow / shard_rows)
choices <- lapply(efforts, function(ef) list(
    indices = matrix(integer(), nrow = audit_rows),
    distances = matrix(numeric(), nrow = audit_rows)))
build_seconds <- 0
query_seconds <- numeric(length(efforts))
tuning <- NULL

for (shard in seq_len(shards)) {
    first <- as.integer((shard - 1L) * shard_rows + 1L)
    ref <- fastEmbedR:::massive_matrix_rows(x, first, shard_rows)
    if (engine == "native") {
        state <- fastEmbedR:::massive_knn_reference(
            ref, k, "hnsw", threads, "cpu")
        build_seconds <- build_seconds + state$build_seconds
        if (is.null(tuning)) {
            tuning <- list(rule = state$index$tuning_rule)
        }
    } else if (engine == "persistent") {
        reference_float <- fastEmbedR:::massive_read_rows_cpp(
            ref, 1L, shard_rows, 4 * shard_rows * x$ncol, TRUE)
        started <- proc.time()[[3L]]
        index <- faissR:::nn_faiss_hnsw_index_build_float32_cpp(
            reference_float, m, ef_construction, 120L,
            "euclidean", "euclidean", threads)
        build_seconds <- build_seconds +
            unname(proc.time()[[3L]] - started)
        if (is.null(tuning)) tuning <- list(
            rule = paste0("faissR_persistent_M", m,
                "_efC", ef_construction), default_ef = 120L)
    }
    for (j in seq_along(efforts)) {
        if (engine == "native") {
            found <- fastEmbedR:::massive_knn_query(state, query,
                k + 1L, "hnsw", threads, "cpu", efforts[[j]])
            if (!identical(found$method,
                    "native_hnsw_query_reused")) stop(
                "Native HNSW diagnostic changed algorithm.")
            seconds <- found$query_seconds
        } else if (engine == "persistent") {
            started <- proc.time()[[3L]]
            used <- if (efforts[[j]] == 0L) 120L else efforts[[j]]
            found <- faissR:::nn_faiss_hnsw_index_search_float32_cpp(
                index, query_float, k + 1L, FALSE, used,
                threads, "double")
            seconds <- unname(proc.time()[[3L]] - started)
            if (!isTRUE(found$index_reused) ||
                found$ef_search != used) stop(
                "Persistent FAISS diagnostic changed algorithm.")
        } else {
            started <- proc.time()[[3L]]
            found <- fastEmbedR:::run_faissr_hnsw(
                fastEmbedR::massive_read_rows(ref, 1L,
                    shard_rows), query, k + 1L,
                "double", 0.99, threads)
            seconds <- unname(proc.time()[[3L]] - started)
            if (!identical(found$index_type, "IndexHNSWFlat")) {
                stop("FAISS HNSW diagnostic changed algorithm.")
            }
            if (is.null(tuning)) tuning <- list(
                rule = found$tuning_rule,
                default_ef = found$ef_search)
        }
        choices[[j]]$indices <- cbind(choices[[j]]$indices,
            found$indices + first - 1L)
        choices[[j]]$distances <- cbind(choices[[j]]$distances,
            found$distances)
        if (engine == "native" && j == 1L &&
            is.null(tuning$default_ef)) {
            tuning$default_ef <- found$ef_search_used
        }
        query_seconds[[j]] <- query_seconds[[j]] + seconds
    }
    if (shard %% 10L == 0L) {
        message("Indexed ", shard, "/", shards, " shards")
    }
}

exact <- fastEmbedR:::massive_exact_sample_batch_cpp(
    x, x, rows, k, 20000L, threads, TRUE)
if (!isTRUE(exact$exact) ||
    !identical(exact$backend_used, "native_cpu_exact_stream")) {
    stop("Independent exact reference was not used.")
}

score <- function(j) {
    recall <- vapply(seq_along(rows), function(i) {
        ids <- choices[[j]]$indices[i, ]
        distances <- choices[[j]]$distances[i, ]
        valid <- is.finite(distances) & ids != rows[[i]]
        order_ids <- order(distances[valid], ids[valid])
        observed <- ids[valid][order_ids][seq_len(k)]
        sum(observed %in% exact$indices[i, ]) / k
    }, numeric(1))
    data.frame(ef_search = efforts[[j]], row = rows,
        recall = recall)
}
details <- do.call(rbind, lapply(seq_along(efforts), score))
summary <- do.call(rbind, lapply(seq_along(efforts), function(j) {
    values <- details$recall[details$ef_search == efforts[[j]]]
    data.frame(engine = engine, shard_rows = shard_rows,
        audit_rows = audit_rows,
        ef_search = efforts[[j]],
        mean_recall = mean(values), min_recall = min(values),
        rows_at_099 = sum(values >= 0.99),
        build_seconds_shared = if (engine != "faiss") {
            build_seconds
        } else NA_real_,
        sample_route_seconds = query_seconds[[j]],
        tuning_rule = tuning$rule,
        default_efSearch = tuning$default_ef)
}))
utils::write.csv(details, file.path(output, "row_recall.csv"),
    row.names = FALSE)
utils::write.csv(summary, file.path(output, "summary.csv"),
    row.names = FALSE)
print(summary, row.names = FALSE)
