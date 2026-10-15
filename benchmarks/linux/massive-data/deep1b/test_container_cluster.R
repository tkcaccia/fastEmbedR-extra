#!/usr/bin/env Rscript
# Tiny runtime check of the image's file-backed clustering routes.
args <- commandArgs(trailingOnly = TRUE)
if (length(args) != 2L || !args[[1L]] %in% c("cpu", "cuda")) {
    stop("Usage: test_container_cluster.R cpu|cuda SCORE_SCRIPT")
}
backend <- args[[1L]]
score_script <- normalizePath(args[[2L]], mustWork = TRUE)
library(fastEmbedR)
set.seed(7L)
root <- tempfile()
dir.create(root)
input <- file.path(root, "input.f32")
prefix <- file.path(root, "output")
connection <- file(input, "wb")
writeBin(as.vector(t(matrix(rnorm(4096L), ncol = 4L))),
         connection, size = 4L, endian = "little")
close(connection)
source <- massive_matrix(input, nrow = 1024L, ncol = 4L)
for (method in c("leiden", "louvain",
                 if (backend == "cpu") "walktrap")) {
    output <- paste0(prefix, "_", method)
    fit <- massive_cluster(source, method = method, landmarks = 100L,
        k = 10L, backend = backend,
        n.cores = if (backend == "cpu") 2L else 4L,
        devices = if (backend == "cuda") 0L else NULL,
        output = output, chunk_rows = 128L,
        memory_limit = "512MB", seed = 7L)
    sample <- massive_read_cluster_rows(fit, 1L, 1024L)
    stopifnot(fit$backend == backend, fit$graph_backend == backend,
              length(sample$membership) == 1024L,
              all(sample$membership >= 1L),
              all(is.finite(sample$confidence)))
    scored <- file.path(root, paste0("scored_", method))
    dir.create(scored)
    stream <- gzfile(file.path(scored, "landmark_labels.csv.gz"), "wt")
    write.csv(data.frame(row_id = fit$selection$indices,
        membership = fit$reference_membership), stream, row.names = FALSE)
    close(stream)
    status <- system2("/opt/r46/bin/Rscript", c(score_script, output,
        "1024", scored, "1"), stdout = TRUE, stderr = TRUE)
    stopifnot(is.null(attr(status, "status")))
    quality <- read.csv(file.path(scored, "quality.csv"))
    stopifnot(quality$scanned_rows == 1024L,
              quality$communities == fit$n_communities)
    cat(backend, method, "PASS\n")
}
unlink(root, recursive = TRUE)
