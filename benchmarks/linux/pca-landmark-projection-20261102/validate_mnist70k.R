args <- commandArgs(trailingOnly = TRUE)
if (length(args) != 3L) stop("Need input, output directory, library.")
input <- args[[1L]]
output <- args[[2L]]
.libPaths(c(args[[3L]], .libPaths()))
library(fastEmbedR)
records <- c("SHA256_INPUTS", "run.log", "run.exit")
if (!dir.exists(output) ||
    any(!list.files(output) %in% records)) {
    stop("Output directory contains unexpected files.")
}
source <- massive_matrix(input, nrow = 70000, ncol = 784)
selection <- massive_select_landmarks(source, 7000L,
    file.path(output, "landmarks.f32"), seed = 42L,
    chunk_rows = 1024L, memory_limit = "512MB",
    landmark_method = "random")
fit <- pca(selection$data, ncomp = 2L, backend = "cpu",
    n.cores = 4L, massive = "out_of_core",
    output = file.path(output, "landmark-scores.f32"),
    chunk_rows = 1024L, memory_limit = "512MB")
saveRDS(selection$indices, file.path(output, "landmark-indices.rds"))
saveRDS(fit, file.path(output, "fit.rds"))
expected <- massive_read_rows(source, 1L, 1000L)
expected <- sweep(sweep(expected, 2L, fit$center),
    2L, fit$scale, "/") %*% fit$loadings
run <- function(name, backend, workers) {
    started <- proc.time()[[3L]]
    result <- massive_project_pca(fit, source,
        file.path(output, paste0(name, ".f32")),
        backend = backend, n.cores = workers,
        chunk_rows = 1024L, memory_limit = "512MB",
        landmarks = selection)
    elapsed <- unname(proc.time()[[3L]] - started)
    actual <- massive_read_rows(result$scores, 1L, 1000L)
    error <- max(abs(actual - expected))
    tolerance <- 1e-4 + 1e-6 * max(abs(expected))
    if (!is.finite(error) || error > tolerance) stop(
        name, " projection differs from reference: ", error)
    saveRDS(result, file.path(output, paste0(name, ".rds")))
    data.frame(case = name, backend = backend, workers = workers,
        rows = source$nrow, columns = source$ncol, elapsed_sec = elapsed,
        max_abs_error = error,
        score_bytes = file.info(result$scores$path)$size)
}
cases <- rbind(run("cpu1", "cpu", 1L),
    run("cpu8", "cpu", 8L), run("cuda", "cuda", 1L))
write.csv(cases, file.path(output, "results.csv"), row.names = FALSE)
writeLines(capture.output(sessionInfo()),
    file.path(output, "session-info.txt"))
print(cases)
