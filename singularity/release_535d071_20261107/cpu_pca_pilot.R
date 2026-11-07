identity <- readLines(
    "/opt/fastembedr-manifest/source-identity.txt", warn = FALSE
)
stopifnot(
    "FastEmbedRCommit=535d071849945db3fa550d3c50f80633b91748cc"
        %in% identity
)
suppressPackageStartupMessages(library(fastEmbedR))
set.seed(401)
x <- matrix(rnorm(384L * 784L), 384L, 784L)
single <- pca(x, ncomp = 2L, backend = "cpu", n.cores = 1L,
              seed = 401L)
fit <- pca(x, ncomp = 2L, backend = "cpu", n.cores = 32L,
           seed = 401L)
difference <- max(abs(fit$scores - single$scores))
stopifnot(identical(fit$backend, "cpu_rsvd"),
          identical(fit$n.cores_requested, 32L),
          identical(fit$n.cores_effective, 32L),
          identical(fit$n_threads, 32L),
          identical(dim(fit$scores), c(384L, 2L)),
          all(is.finite(fit$scores)), difference < 1e-3)
cat(sprintf("source=535d071 backend=%s requested=32 effective=%d ",
            fit$backend, fit$n.cores_effective))
cat(sprintf("max_score_difference=%.8g\n", difference))
