args <- commandArgs(trailingOnly = TRUE)
stopifnot(length(args) == 2L, dir.exists(args[[1L]]),
    dir.exists(args[[2L]]))
library(fastEmbedR)
work <- args[[1L]]
out <- args[[2L]]
shape <- readRDS(file.path(work, "pca_shape.rds"))
source <- massive_matrix(file.path(work, "pca_input.f32"),
    shape$n, shape$columns)
selection <- massive_select_landmarks(source, 1000L,
    file.path(work, "landmarks.f32"), seed = 71L,
    chunk_rows = 256L, memory_limit = "512MB",
    landmark_method = "random")
fit <- pca(selection$data, ncomp = 3L, backend = "cpu",
    massive = "out_of_core", output = file.path(work,
        "landmark-fit.f32"), chunk_rows = 256L,
    memory_limit = "512MB")
fit <- massive_open_pca(fit$scores$path)
output <- file.path(work, "landmark-all-gpu2.f32")
started <- proc.time()[[3L]]
result <- massive_project_pca(fit, source, output,
    backend = "cuda", devices = c(0L, 1L),
    landmarks = selection, checkpoint = TRUE,
    chunk_rows = 256L, memory_limit = "2GB")
seconds <- unname(proc.time()[[3L]] - started)
parts <- result$resources$per_device
paths <- result$resources$shard_paths
stopifnot(identical(result$backend, "cuda"),
    identical(result$mode, "landmark"),
    identical(result$landmarks$indices, selection$indices),
    identical(result$resources$gpu_devices, c(0L, 1L)),
    identical(vapply(parts, `[[`, 0L, "gpu_device"), c(0L, 1L)),
    length(paths) == 2L, all(file.exists(paths)),
    file.info(output)$size == shape$n * 3L * 4L,
    !file.exists(paste0(output, ".checkpoint.rds")))
bytes <- as.numeric(file.info(paths)$size)
fastEmbedR:::massive_verify_merged_shards(paths, output, bytes)
positions <- c(1L, as.integer(shape$n / 2), shape$n - 63L)
errors <- vapply(positions, function(first) {
    input <- massive_read_rows(source, first, 64L)
    expected <- sweep(sweep(input, 2L, fit$center),
        2L, fit$scale, "/") %*% fit$loadings
    observed <- massive_read_rows(result$scores, first, 64L)
    stopifnot(all(is.finite(observed)))
    error <- max(abs(observed - expected))
    stopifnot(error <= 1e-4 + 1e-6 * max(abs(expected)))
    error
}, 0)
uuids <- fastEmbedR:::massive_cuda_device_uuids(c(0L, 1L))
stopifnot(length(uuids) == 2L, all(nzchar(uuids)))
write.csv(data.frame(method = "landmark_pca_projection",
    rows = shape$n, landmark_rows = 1000L,
    seconds = seconds, devices = "0,1",
    uuids = paste(uuids, collapse = ";"),
    shard_bytes = paste(bytes, collapse = ";"),
    max_abs_error = max(errors),
    model_identity = result$model_identity),
    file.path(out, "landmark_pca_gpu2.csv"), row.names = FALSE)
cat("LANDMARK_PCA_TWO_GPU_PASS\n")
