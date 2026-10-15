#!/usr/bin/env Rscript

args <- commandArgs(trailingOnly = TRUE)
if (length(args) != 6L) {
    stop(paste("Usage: compare_hnsw_shard_engines.R",
        "MNIST.RData OUTPUT_CSV N_REFERENCE N_QUERY K CORES"))
}
path <- normalizePath(args[[1L]], mustWork = TRUE)
output <- args[[2L]]
counts <- as.integer(args[3:6])
if (anyNA(counts) || any(counts < 1L)) stop("Invalid counts.")
names(counts) <- c("reference", "query", "k", "cores")
if (counts[["k"]] >= counts[["reference"]]) stop("k is too large.")
if (packageVersion("faissR") < "0.99.48") {
    stop("This comparison needs persistent FAISS HNSW in faissR 0.99.48.")
}
if (!isTRUE(faissR::faiss_available())) stop("FAISS is unavailable.")

source_data <- new.env(parent = emptyenv())
loaded <- load(path, envir = source_data)
if (length(loaded) != 1L) stop("Expected one dataset object.")
matrix <- get(loaded[[1L]], envir = source_data)$data
needed <- counts[["reference"]] + counts[["query"]]
if (!(is.matrix(matrix) || is.data.frame(matrix)) ||
    nrow(matrix) < needed) {
    stop("Input lacks the requested rows.")
}
reference <- as.matrix(matrix[
    seq_len(counts[["reference"]]), , drop = FALSE
])
query <- as.matrix(matrix[
    counts[["reference"]] + seq_len(counts[["query"]]), ,
    drop = FALSE
])
if (!is.numeric(reference) || !is.numeric(query)) {
    stop("Input columns must be numeric.")
}
quality_rows <- unique(as.integer(round(seq(
    1, nrow(query), length.out = min(100L, nrow(query))
))))
distance <- outer(rowSums(reference^2),
    rowSums(query[quality_rows, , drop = FALSE]^2), "+") -
    2 * tcrossprod(reference, query[quality_rows, , drop = FALSE])
truth <- apply(distance, 2L, function(values) {
    order(values)[seq_len(counts[["k"]])]
})
rm(matrix, source_data, distance)
invisible(gc())
reference <- float::fl(reference)
query <- float::fl(query)
batch_starts <- seq.int(1L, nrow(query), by = 100L)

search_batches <- function(index, engine, tuning) {
    started <- proc.time()[[3L]]
    found <- lapply(batch_starts, function(first) {
        last <- min(first + 99L, nrow(query))
        block <- query[first:last, , drop = FALSE]
        if (engine == "native") {
            fastEmbedR:::native_hnsw_index_search_cpp(
                index$pointer, block, counts[["k"]],
                n_threads = counts[["cores"]]
            )
        } else {
            faissR:::nn_faiss_hnsw_index_search_float32_cpp(
                index, block, counts[["k"]], FALSE,
                tuning$efSearch, counts[["cores"]], "float"
            )
        }
    })
    list(indices = do.call(rbind, lapply(found, function(item) {
        item$indices
    })),
        seconds = unname(proc.time()[[3L]] - started))
}

measure_engine <- function(engine, tuning = NULL) {
    started <- proc.time()[[3L]]
    index <- if (engine == "native") {
        fastEmbedR:::native_hnsw_index_build_cpp(
            reference, counts[["k"]], n_threads = counts[["cores"]]
        )
    } else {
        faissR:::nn_faiss_hnsw_index_build_float32_cpp(
            reference, tuning$M, tuning$efConstruction,
            tuning$efSearch, "euclidean", "euclidean",
            counts[["cores"]]
        )
    }
    build <- unname(proc.time()[[3L]] - started)
    if (engine == "native") tuning <- index
    found <- search_batches(index, engine, tuning)
    overlap <- vapply(seq_along(quality_rows), function(j) {
        length(intersect(truth[, j],
            found$indices[quality_rows[[j]], ])) / counts[["k"]]
    }, numeric(1L))
    row <- data.frame(engine = engine,
        n_reference = nrow(reference), p = ncol(reference),
        n_query = nrow(query), k = counts[["k"]],
        cores = counts[["cores"]], m = tuning$M,
        ef_construction = tuning$efConstruction,
        ef_search = tuning$efSearch,
        build_sec = build, query_sec = found$seconds,
        total_sec = build + found$seconds,
        recall_at_k = mean(overlap),
        median_query_recall = stats::median(overlap))
    list(row = row, tuning = tuning)
}

native <- measure_engine("native")
faiss <- measure_engine("faiss", native$tuning)
comparison <- rbind(native$row, faiss$row)
utils::write.csv(comparison, output, row.names = FALSE)
print(comparison, row.names = FALSE)
