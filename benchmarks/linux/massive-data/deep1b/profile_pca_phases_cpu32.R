args <- commandArgs(trailingOnly = TRUE)
if (length(args) != 3L || !args[[1L]] %in% c("8", "16", "32")) {
    stop("Usage: profile_pca_phases_cpu32.R CORES LIBRARY OUTPUT_DIR")
}
cores <- as.integer(args[[1L]])
private <- normalizePath(args[[2L]], mustWork = TRUE)
root <- normalizePath(args[[3L]], mustWork = TRUE)
.libPaths(c(private, .libPaths()))
library(fastEmbedR)
if (!identical(normalizePath(find.package("fastEmbedR")),
    normalizePath(file.path(private, "fastEmbedR")))) {
    stop("PCA phase profile did not load the pinned package build.")
}
input <- paste0("/scratch/firenze/NN/Data/BigANN/deep/",
    "1000000000/base.1000000000.fbin")
source <- massive_matrix(input)
stopifnot(source$nrow == 1e9, source$ncol == 96L)
view <- fastEmbedR:::massive_matrix_rows(source, 1000001, 1e7)
started <- proc.time()[[3L]]
covariance <- fastEmbedR:::massive_pca_covariance_cpp(
    view, 100000L, cores, TRUE)
fitting <- unname(proc.time()[[3L]] - started)
stopifnot(length(covariance$center) == 96L,
    identical(dim(covariance$covariance), c(96L, 96L)))
loading <- eigen(covariance$covariance, symmetric = TRUE)$vectors[, 1:2]
output <- file.path(root, "scores.f32")
started <- proc.time()[[3L]]
fastEmbedR:::massive_pca_project_cpp(view, output, loading,
    covariance$center, rep(1, 96L), 100000L, cores)
projection <- unname(proc.time()[[3L]] - started)
stopifnot(file.info(output)$size == 80000000)
write.csv(data.frame(cores = cores, fitting_seconds = fitting,
    projection_seconds = projection,
    output_bytes = 80000000),
    file.path(root, "metrics.csv"), row.names = FALSE)
unlink(output)
