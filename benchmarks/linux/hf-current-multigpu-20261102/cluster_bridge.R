args <- commandArgs(trailingOnly = TRUE)
stopifnot(length(args) == 1L, dir.exists(args[[1L]]))
library(fastEmbedR)

out <- normalizePath(args[[1L]])
work <- tempfile("cugraph-bridge-")
dir.create(work)
n <- as.integer(Sys.getenv("FASTEMBEDR_CLUSTER_ROWS", "1024"))
devices <- as.integer(strsplit(Sys.getenv("FASTEMBEDR_CLUSTER_DEVICES",
    "0,1"), ",", fixed = TRUE)[[1L]])
stopifnot(is.finite(n), n >= 1024L, n %% 4L == 0L,
    length(devices) %in% 2:4, !anyNA(devices),
    identical(devices, seq.int(0L, length(devices) - 1L)))
group_size <- n %/% 4L
k <- 12L
row <- seq_len(n)
group <- (row - 1L) %/% group_size
offset <- (row - 1L) %% group_size
ids <- outer(offset, seq_len(k), function(i, j)
    (i + j) %% group_size + 1L)
ids <- ids + group * group_size
distances <- matrix(rep(seq(0.2, 0.9, length.out = k), n),
    nrow = n, byrow = TRUE)
prefix <- file.path(work, "knn")
writeBin(as.integer(t(ids)), paste0(prefix, ".indices.u32"),
    size = 4L, endian = "little")
writeBin(as.vector(t(distances)), paste0(prefix, ".distances.f32"),
    size = 4L, endian = "little")
graph <- massive_umap_fuzzy_graph(massive_umap_memberships(
    massive_knn_graph(prefix, n, k)),
    file.path(work, "graph"), memory_limit = "256MB")

results <- list()
for (method in c("louvain", "leiden")) {
    path <- file.path(work, method)
    started <- proc.time()[[3L]]
    fit <- tryCatch(massive_cluster(graph, method = method,
        massive = "out_of_core_graph", output = path,
        backend = "cuda", devices = devices,
        chunk_rows = 256L, memory_limit = "4GB",
        n_iterations = 10L, seed = 1L), error = function(error) {
        file.copy(Sys.glob(paste0(path, ".*")), out)
        stop(error)
    })
    seconds <- proc.time()[[3L]] - started
    labels <- readBin(fit$membership_path, "integer", n = n,
        size = 4L, endian = "little")
    workers <- fit$cugraph$gpu_memory$workers
    worker_uuids <- vapply(workers, `[[`, "", "uuid")
    stopifnot(length(labels) == n, all(labels > 0L),
        identical(fit$gpu_devices, devices),
        identical(fit$resources$measured_vram_scope,
            "whole_physical_gpu"),
        length(fit$resources$measured_vram_peak_per_device) ==
            length(devices), length(workers) == length(devices),
        setequal(worker_uuids, vapply(fit$gpu_identity,
            `[[`, "", "uuid")),
        identical(fit$resources$measured_ram_scope,
            "launcher_and_workers"),
        is.finite(fit$resources$measured_ram_peak_bytes))
    mixed <- sum(vapply(split(group, labels), function(values)
        length(unique(values)) > 1L, FALSE))
    positions <- split((row - 1L) %% group_size, labels)
    disconnected <- sum(vapply(positions, function(values) {
        if (length(values) < 2L) return(FALSE)
        gaps <- diff(c(values, values[[1L]] + group_size))
        sum(gaps > k) > 1L
    }, FALSE))
    stopifnot(mixed == 0L, disconnected == 0L,
        is.finite(fit$modularity_final))
    file.copy(fit$membership_path,
        file.path(out, paste0(method, ".clusters.u32")))
    file.copy(paste0(path, ".cugraph.json"),
        file.path(out, paste0(method, ".cugraph.json")))
    results[[method]] <- data.frame(method = method, rows = n,
        communities = fit$n_communities,
        mixed_communities = mixed,
        disconnected_communities = disconnected,
        modularity = fit$modularity_final,
        reported_modularity = fit$modularity_reported,
        seconds = seconds, devices = length(devices),
        ram_peak_bytes = fit$resources$measured_ram_peak_bytes,
        worker_uuids = paste(worker_uuids, collapse = ";"),
        gpu_peaks_bytes = paste(vapply(fit$resources$
            measured_vram_peak_per_device, function(device)
            device$peak_used_bytes, numeric(1L)), collapse = ";"))
    write.csv(do.call(rbind, results), file.path(out, "bridge.csv"),
        row.names = FALSE)
}
cat("MULTIGPU_cluster_BRIDGE_PASS\n")
