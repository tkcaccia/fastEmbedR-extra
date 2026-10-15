#!/usr/bin/env Rscript

args <- commandArgs(trailingOnly = TRUE)
if (length(args) < 10L || length(args) > 12L) {
    stop(paste("Usage: compare_hnsw_full_graph.R",
        "INPUT NROW NCOL K REFERENCE_ROWS QUERY_ROWS AUDIT_ROWS",
        "CORES MEMORY_LIMIT OUTPUT.csv [f32|fbin] [EF_SEARCH]"))
}
input <- normalizePath(args[[1L]], mustWork = TRUE)
counts <- as.integer(args[2:8])
if (anyNA(counts) || any(counts < 1L)) stop("Invalid counts.")
names(counts) <- c("n", "p", "k", "reference", "query", "audit",
    "cores")
format <- if (length(args) >= 11L) args[[11L]] else "f32"
ef_search <- if (length(args) >= 12L) as.integer(args[[12L]]) else 0L
if (is.na(ef_search) || ef_search < 0L) stop("Invalid ef_search.")
if (!format %in% c("f32", "fbin")) stop("Invalid input format.")
if (!requireNamespace("float", quietly = TRUE)) stop("float is required.")
if (!faissR::faiss_available()) stop("FAISS is unavailable.")

source <- fastEmbedR::massive_matrix(input, counts[["n"]],
    counts[["p"]], format = format)

run_route <- function(method) {
    prefix <- tempfile()
    on.exit(unlink(paste0(prefix, c(".indices.u32",
        ".distances.f32", ".indices.u32.part",
        ".distances.f32.part"))))
    graph <- fastEmbedR::massive_full_knn_graph(source, counts[["k"]],
        prefix, method = method, n.cores = counts[["cores"]],
        reference_chunk_rows = counts[["reference"]],
        chunk_rows = counts[["query"]], audit_rows = counts[["audit"]],
        memory_limit = args[[9L]], ef_search = ef_search)
    data.frame(input = input, format = format,
        method = graph$method, n = source$nrow,
        p = source$ncol, k = graph$k, cores = counts[["cores"]],
        reference_rows = counts[["reference"]],
        query_rows = counts[["query"]],
        memory_limit = args[[9L]],
        n_shards = graph$resources$n_shards,
        query_batches = graph$resources$query_batches,
        total_seconds = graph$total_seconds,
        build_seconds = graph$build_seconds,
        audit_seconds = graph$audit_seconds,
        mean_recall = graph$observed_recall,
        minimum_row_recall = graph$minimum_row_recall,
        all_audited_rows_pass = graph$sample_target_met,
        estimated_peak_ram_bytes = graph$resources$peak_ram_bytes,
        ef_search = ef_search,
        fastEmbedR_version = as.character(
            utils::packageVersion("fastEmbedR")),
        faissR_version = as.character(utils::packageVersion("faissR")))
}

results <- do.call(rbind, lapply(c("hnsw_sharded",
    "faiss_hnsw_sharded"), run_route))
utils::write.csv(results, args[[10L]], row.names = FALSE)
print(results, row.names = FALSE)
