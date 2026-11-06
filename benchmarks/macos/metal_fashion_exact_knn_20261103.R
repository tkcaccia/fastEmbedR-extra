args <- commandArgs(trailingOnly = TRUE)
stopifnot(length(args) == 1L, dir.exists(args[[1L]]))
.libPaths(c(args[[1L]],
    "/Users/silvanopiazza/Documents/Stefano/data/Rlib", .libPaths()))
library(fastEmbedR)
setTimeLimit(elapsed = 300, transient = FALSE)
path <- paste0(
    "/Users/silvanopiazza/Documents/Stefano/data/data/",
    "FashionMNIST_n5000/FashionMNIST_n5000_float32.RData")
data <- new.env(parent = emptyenv())
load(path, envir = data)
x <- float::dbl(data$dataset$data)
cat("SHAPE", nrow(x), ncol(x), "\n")
policy <- fastEmbedR:::fastembedr_embedding_nn_policy(
    "metal", nrow(x), ncol(x))
stopifnot(identical(policy$method, "exact"))
run <- function(method) {
    started <- proc.time()[[3L]]
    fit <- fastEmbedR:::native_metal_knn_cpp(
        x, 30L, method, "euclidean", 0.99)
    seconds <- proc.time()[[3L]] - started
    stopifnot(identical(dim(fit$indices), c(nrow(x), 30L)),
        identical(fit$method, paste0("native_metal_", method)),
        all(is.finite(fit$distances)))
    cat("RESULT", method, signif(seconds, 7),
        fit$method, "\n")
    fit
}
exact <- run("exact")
approx <- run("ivf")
started <- proc.time()[[3L]]
api <- precompute_knn(x, k = 30L, backend = "metal")
api_seconds <- proc.time()[[3L]] - started
stopifnot(identical(api$method, "native_metal_exact"),
    identical(api$indices, exact$indices))
cat("API exact", signif(api_seconds, 7), api$method, "\n")
recall <- vapply(seq_len(nrow(x)), function(i) {
    length(intersect(exact$indices[i, ], approx$indices[i, ])) / 30
}, 0.0)
cat("RECALL mean", signif(mean(recall), 7),
    "minimum", signif(min(recall), 7), "\n")
cat("METAL_FASHION_EXACT_KNN_COMPLETE\n")
