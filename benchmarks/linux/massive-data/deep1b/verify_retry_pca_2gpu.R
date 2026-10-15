#!/usr/bin/env Rscript

args <- commandArgs(trailingOnly = TRUE)
if (length(args) != 1L) stop("Usage: verify_retry_pca_2gpu.R ROOT")
library(fastEmbedR)
root <- normalizePath(args[[1L]], mustWork = TRUE)
case <- file.path(root, "results", "cuda_pca_20000000_fullgraph")
output <- file.path(case, "output.f32")
manifest <- readRDS(paste0(output, ".manifest.rds"))
fit <- manifest$fit
resources <- fit$resources$per_device
devices <- vapply(resources, function(x) as.integer(x$gpu_device),
    integer(1))
if (!identical(as.integer(fit$gpu_devices), 0:1) ||
    !identical(as.integer(devices), 0:1) ||
    !identical(as.numeric(file.info(output)$size), 160000000) ||
    any(vapply(resources, function(x) x$status == "reused", FALSE))) {
    stop("Two-GPU PCA output or shard metadata is incomplete.")
}
scores <- massive_matrix(output, nrow = 20000000, ncol = 2L)
for (first in c(1, 10000000, 19999999)) {
    block <- massive_read_rows(scores, first, 2L)
    if (!all(is.finite(block))) stop("PCA scores are not finite.")
}
write.csv(data.frame(device = devices,
    estimated_peak_vram_bytes = vapply(resources,
        function(x) as.numeric(x$peak_vram_bytes), numeric(1)),
    estimated_peak_ram_bytes = vapply(resources,
        function(x) as.numeric(x$peak_ram_bytes), numeric(1)),
    status = vapply(resources, function(x) as.character(x$status),
        character(1))),
    file.path(root, "pca_per_device.csv"), row.names = FALSE)
cat("20M PCA rows and both shard identities verified.\n")
