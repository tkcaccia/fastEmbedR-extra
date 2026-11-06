identity <- readLines(
    "/opt/fastembedr-manifest/source-identity.txt", warn = FALSE)
stopifnot("FastEmbedRCommit=77b852fc496ad4665969c4f6771088f5b98da4fe"
    %in% identity)
suppressPackageStartupMessages(library(fastEmbedR))
x <- as.matrix(iris[, 1:4])
labels <- iris$Species
started <- proc.time()[[3L]]
fit <- fastEmbedR::tsne(x, n_components = 3L, perplexity = 10,
    early_exaggeration_iter = 50L, n_iter = 100L,
    auto_config = FALSE, backend = "cpu", n.cores = 8L,
    seed = 19L, massive = "off")
elapsed <- unname(proc.time()[[3L]] - started)
stopifnot(identical(dim(fit$layout), c(150L, 3L)),
    all(is.finite(fit$layout)),
    startsWith(fit$parameters$backend, "cpu"),
    identical(fit$parameters$n.cores_requested, 8L),
    identical(fit$parameters$n.cores_effective, 8L))
quality <- fastEmbedR::evaluate_embedding(x, fit$layout,
    labels = labels, k = 15L, primary_k = 15L,
    sample_size_for_global_metrics = 150L,
    sample_size_for_local_metrics = 150L,
    n.cores = 1L, seed = 19L)
stopifnot(is.finite(quality$trustworthiness),
    quality$trustworthiness >= 0, quality$trustworthiness <= 1)
cat(sprintf("source=77b852f backend=%s requested=8 effective=%d ",
    fit$parameters$backend, fit$parameters$n.cores_effective))
cat(sprintf("trustworthiness=%.6f elapsed=%.3f\n",
    quality$trustworthiness, elapsed))
