args <- commandArgs(trailingOnly = TRUE)
if (length(args) != 3L) stop("Need input, output directory, library.")
.libPaths(c(args[[3L]], .libPaths()))
library(fastEmbedR)
source <- massive_matrix(args[[1L]], nrow = 70000, ncol = 784)
output <- args[[2L]]
fit <- readRDS(file.path(output, "fit.rds"))
expected <- massive_read_rows(source, 1L, 1000L)
expected <- sweep(sweep(expected, 2L, fit$center),
    2L, fit$scale, "/") %*% fit$loadings
inspect <- function(name) {
    scores <- massive_matrix(file.path(output, paste0(name, ".f32")),
        nrow = source$nrow, ncol = 2L)
    observed <- massive_read_rows(scores, 1L, 1000L)
    error <- abs(observed - expected)
    data.frame(case = name, max_abs = max(error),
        mean_abs = mean(error), rmse = sqrt(mean(error^2)),
        p99_abs = unname(quantile(error, 0.99)),
        max_expected = max(abs(expected)),
        normalized_max = max(error) / max(abs(expected)))
}
audit <- do.call(rbind, lapply(c("cpu1", "cpu8", "cuda"), inspect))
audit$tolerance <- 1e-4 + 1e-6 * audit$max_expected
audit$pass <- audit$max_abs <= audit$tolerance
if (!all(audit$pass)) stop("PCA projection accuracy audit failed.")
cpu_hash <- unname(tools::md5sum(file.path(output,
    c("cpu1.f32", "cpu8.f32"))))
if (!identical(cpu_hash[[1L]], cpu_hash[[2L]])) stop(
    "CPU worker counts changed the projection scores.")
write.csv(audit, file.path(output, "audit.csv"), row.names = FALSE)
print(audit)
