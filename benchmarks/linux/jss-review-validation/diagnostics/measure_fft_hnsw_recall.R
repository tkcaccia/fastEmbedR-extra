args <- commandArgs(trailingOnly = TRUE)
if (length(args) != 3L) {
    stop("Usage: measure_fft_hnsw_recall.R INPUT DATASET OUTPUT")
}

input <- normalizePath(args[[1L]], mustWork = TRUE)
dataset <- args[[2L]]
output <- args[[3L]]
library_path <- Sys.getenv("FASTEMBEDR_TEST_LIB")
if (!nzchar(library_path)) stop("FASTEMBEDR_TEST_LIB is required")
.libPaths(c(library_path, .libPaths()))
if (normalizePath(find.package("fastEmbedR")) !=
    normalizePath(file.path(library_path, "fastEmbedR"))) {
    stop("The private fastEmbedR installation was not selected")
}

if (grepl("[.]bin$", input)) {
    if (dataset != "Retina") stop("Unknown binary matrix shape")
    values <- readBin(input, what = "numeric", n = 44808L * 50L,
                      size = 4L, endian = "little")
    if (length(values) != 44808L * 50L) stop("Truncated binary input")
    x <- matrix(values, nrow = 44808L, ncol = 50L, byrow = TRUE)
} else {
    loaded <- new.env(parent = emptyenv())
    load(input, envir = loaded)
    object <- if (exists("dataset_float32", envir = loaded,
                         inherits = FALSE)) {
        loaded$dataset_float32
    } else loaded$dataset
    x <- float::dbl(object$data)
}
if (!is.matrix(x) || any(!is.finite(x))) stop("Invalid matrix")

k <- 30L
set.seed(31337L)
query_rows <- sort(sample.int(nrow(x), 128L))
elapsed <- system.time({
    knn <- fastEmbedR::precompute_knn(
        x, k = k, backend = "cpu", n.cores = 4L
    )
})[["elapsed"]]
if (!identical(knn$execution_backend, "cpu") ||
    !identical(knn$method, "native_hnsw") ||
    !identical(knn$exclude_self, TRUE)) {
    stop("The measured search did not use CPU self-excluding HNSW")
}

reference_time <- system.time({
    norms <- rowSums(x * x)
    recall <- numeric(length(query_rows))
    for (j in seq_along(query_rows)) {
        row <- query_rows[[j]]
        distances <- norms + sum(x[row, ]^2) -
            2 * as.vector(x %*% x[row, ])
        distances[[row]] <- Inf
        exact <- order(distances, method = "radix")[seq_len(k)]
        recall[[j]] <- length(intersect(knn$indices[row, ], exact)) / k
    }
})[["elapsed"]]

result <- data.frame(
    dataset = dataset, n = nrow(x), p = ncol(x), k = k,
    threads = 4L, query_n = length(query_rows), query_seed = 31337L,
    M = knn$M, efConstruction = knn$efConstruction,
    efSearch = knn$efSearch, tuning_rule = knn$tuning_rule,
    knn_elapsed_sec = elapsed, exact_reference_sec = reference_time,
    mean_recall = mean(recall), median_recall = median(recall),
    q05_recall = unname(quantile(recall, 0.05)),
    minimum_recall = min(recall),
    queries_below_099 = sum(recall < 0.99)
)
write.csv(result, output, row.names = FALSE)
message(dataset, ": recall=", signif(result$mean_recall, 5),
        " KNN=", signif(elapsed, 5), " seconds")
