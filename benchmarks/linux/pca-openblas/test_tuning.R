args <- commandArgs(trailingOnly = TRUE)
if (length(args) != 4L) {
    stop("Usage: Rscript test_tuning.R DATA ROWS REFERENCE OUTPUT")
}

library(fastEmbedR)
library(float)
rows <- utils::read.csv(args[[2L]])$source_row
saved <- utils::read.csv(args[[3L]])$singular_value
source <- new.env(parent = emptyenv())
load(args[[1L]], envir = source)
object <- get(ls(source)[[1L]], envir = source)
if (!is.list(object) || is.null(object$data)) {
    stop("ImageNet source must contain a list with a data matrix")
}
x <- object$data[rows, , drop = FALSE]
rm(object, source)
invisible(gc())
matrix_double <- function(value) {
    if (inherits(value, "float32")) float::dbl(value) else value
}
centered <- scale(matrix_double(x), center = TRUE, scale = FALSE)
reference <- svd(centered, nu = 50L, nv = 50L)
reference_scores <- reference$u %*% diag(reference$d[seq_len(50L)])
reference_loadings <- reference$v[, seq_len(50L), drop = FALSE]
total_ss <- sum(centered^2)
reference_match <- max(abs(reference$d[seq_len(50L)] -
    saved)) / max(saved)
if (reference_match > 1e-5) {
    stop("ImageNet input differs from the archived accuracy sample: ",
        reference_match)
}

score_fit <- function(fit, rank, oversample, power, seed, elapsed) {
    scores <- matrix_double(fit$scores)
    loadings <- matrix_double(fit$loadings)
    basis <- qr.Q(qr(scores))
    reference_basis <- qr.Q(qr(reference_scores[, seq_len(rank)]))
    cosine <- svd(crossprod(reference_basis, basis), nu = 0L,
                  nv = 0L)$d
    reconstructed <- scores %*% t(loadings)
    reference_variance <- sum(reference$d[seq_len(rank)]^2) / total_ss
    variance <- sum(fit$singular_values^2) / total_ss
    data.frame(
        rank = rank, oversample = oversample, power = power, seed = seed,
        elapsed_sec = elapsed, native_sec = fit$timing$total,
        sketch_sec = fit$timing$sketch,
        project_sec = fit$timing$project,
        subspace_cosine_mean = mean(cosine),
        subspace_cosine_min = min(cosine),
        captured_variance = variance,
        captured_variance_gap = reference_variance - variance,
        reconstruction_error = sqrt(
            sum((centered - reconstructed)^2) / total_ss
        ),
        singular_relative_error = sqrt(sum((
            fit$singular_values - reference$d[seq_len(rank)]
        )^2)) / sqrt(sum(reference$d[seq_len(rank)]^2)),
        gemm_backend = fit$gemm_backend
    )
}

run_fit <- function(rank, oversample, power, seed) {
    set.seed(seed)
    width <- rank + oversample
    omega <- matrix(stats::rnorm(ncol(x) * width), ncol(x), width)
    elapsed <- system.time({
        fit <- fastEmbedR:::with_pca_cpu_threads(
            4L,
            fastEmbedR:::pca_rsvd_cpu_cpp(
                x, rank, TRUE, FALSE, omega, power, 4L
            )
        )$value
    })[["elapsed"]]
    score_fit(fit, rank, oversample, power, seed, elapsed)
}

invisible(run_fit(2L, 20L, 1L, 4L))
results <- list()
for (rank in c(2L, 50L)) {
    for (oversample in c(10L, 20L, 40L, 80L)) {
        for (power in 0:3) {
            for (seed in c(4L, 17L, 29L)) {
                results[[length(results) + 1L]] <- run_fit(
                    rank, oversample, power, seed
                )
            }
        }
    }
}
output <- do.call(rbind, results)
output$source_rows <- length(rows)
output$reference_relative_difference <- reference_match
utils::write.csv(output, args[[4L]], row.names = FALSE)
print(aggregate(cbind(elapsed_sec, subspace_cosine_mean,
    captured_variance_gap, reconstruction_error) ~
    rank + oversample + power, output, median))
