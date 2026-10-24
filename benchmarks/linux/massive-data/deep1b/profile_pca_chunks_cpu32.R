args <- commandArgs(trailingOnly = TRUE)
if (length(args) != 4L || !args[[1L]] %in% c("16", "32") ||
    !args[[2L]] %in% c("100000", "500000", "1000000")) {
    stop("Usage: profile_pca_chunks_cpu32.R CORES CHUNK LIBRARY OUTPUT")
}
cores <- as.integer(args[[1L]])
chunk <- as.integer(args[[2L]])
private <- normalizePath(args[[3L]], mustWork = TRUE)
root <- normalizePath(args[[4L]], mustWork = TRUE)
.libPaths(c(private, .libPaths()))
library(fastEmbedR)
if (!identical(normalizePath(find.package("fastEmbedR")),
    normalizePath(file.path(private, "fastEmbedR")))) {
    stop("PCA chunk profile did not load the pinned package build.")
}
input <- paste0("/scratch/firenze/NN/Data/BigANN/deep/",
    "1000000000/base.1000000000.fbin")
source <- massive_matrix(input)
stopifnot(source$nrow == 1e9, source$ncol == 96L)
view <- fastEmbedR:::massive_matrix_rows(source, 1000001, 1e7)
output <- file.path(root, "scores.f32")
started <- proc.time()[[3L]]
fit <- pca(view, ncomp = 2L, backend = "cpu", n.cores = cores,
    massive = "out_of_core", output = output,
    chunk_rows = chunk, seed = 4L, memory_limit = "4GB")
elapsed <- unname(proc.time()[[3L]] - started)
stopifnot(identical(as.integer(fit$n_threads), cores),
    fit$scores$nrow == 1e7, file.info(output)$size == 80000000)
write.csv(data.frame(cores = cores,
    requested_chunk_rows = chunk,
    effective_chunk_rows = fit$resources$chunk_rows,
    elapsed_seconds = elapsed,
    singular_value_1 = fit$singular_values[[1L]],
    singular_value_2 = fit$singular_values[[2L]],
    output_bytes = 80000000),
    file.path(root, "metrics.csv"), row.names = FALSE)
unlink(c(output, paste0(output, ".manifest.rds")))
