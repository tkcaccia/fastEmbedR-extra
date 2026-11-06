args <- commandArgs(trailingOnly = TRUE)
stopifnot(length(args) == 3L)
.libPaths(c(args[[1L]], .libPaths()))
suppressPackageStartupMessages(library(fastEmbedR))
source(args[[3L]], local = TRUE)
source_path <- "/mnt/sata_ssd/fastEmbedR_Data/MNIST/MNIST_float32.RData"
env <- new.env(parent = emptyenv())
loaded <- load(source_path, envir = env)
stopifnot(identical(loaded, "dataset"))
labels_all <- as.integer(env$dataset$labels) - 1L
set.seed(42L)
rows <- unlist(lapply(0:9, function(label) {
    sample(which(labels_all == label), 30L)
}), use.names = FALSE)
x <- float::dbl(env$dataset$data[rows, , drop = FALSE])
labels <- labels_all[rows]
stopifnot(identical(dim(x), c(300L, 784L)),
    identical(sort(unique(labels)), 0:9), all(is.finite(x)))
rm(env, labels_all)
gc(verbose = FALSE)

measure <- function(fit, method, scope) {
    layout <- layout_matrix(fit)
    stopifnot(identical(dim(layout), c(300L, 3L)),
        all(is.finite(layout)), all(apply(layout, 2L, sd) > 0))
    q <- quality_metrics(x, layout, labels, 10, 3, k = 15L)
    stopifnot(all(is.finite(as.numeric(q))),
        q$trustworthiness >= 0.7,
        q$label_knn_accuracy >= 0.4)
    cat("QUALITY", method, scope,
        "trust", q$trustworthiness,
        "preserve15", q$preserve_at_30,
        "label_accuracy", q$label_knn_accuracy,
        "sampled_kl", q$sampled_kl, "\n")
    q
}

run_one <- function(method, scope) {
    common <- list(data = x, backend = "cuda", seed = 42L,
        n_components = 3L, n.cores = 1L)
    if (identical(scope, "landmark")) common$landmarks <- 0.5
    started <- proc.time()[[3L]]
    fit <- if (identical(method, "tsne")) {
        do.call(tsne, c(common, list(perplexity = 10,
            early_exaggeration_iter = 50L, n_iter = 250L,
            transform_iter = 100L, auto_config = FALSE)))
    } else {
        do.call(umap, c(common, list(n_neighbors = 30L)))
    }
    elapsed <- unname(proc.time()[[3L]] - started)
    stopifnot(identical(fit$parameters$backend, "cuda"))
    if (identical(scope, "landmark")) {
        stopifnot(length(fit$landmarks$indices) == 150L,
            identical(dim(fit$landmarks$layout), c(150L, 3L)),
            identical(dim(fit$layout), c(300L, 3L)))
    }
    quality <- measure(fit, method, scope)
    cat("FIT_SECONDS", method, scope, elapsed, "\n")
    list(quality = quality, elapsed = elapsed,
        landmarks = if (identical(scope, "landmark"))
            fit$landmarks$indices else integer())
}

results <- list()
for (method in c("tsne", "umap")) {
    full <- run_one(method, "full")
    landmark <- run_one(method, "landmark")
    delta <- landmark$quality$trustworthiness -
        full$quality$trustworthiness
    cat("LANDMARK_TRUST_DELTA", method, delta, "\n")
    stopifnot(is.finite(delta), delta >= -0.1)
    results[[method]] <- list(full = full, landmark = landmark,
        trust_delta = delta)
}
saveRDS(list(results = results, rows = rows, labels = labels),
    args[[2L]])
cat("CUDA_MNIST_LANDMARK_3D_QUALITY_PASS\n")
