args <- commandArgs(trailingOnly = TRUE)
if (length(args) != 2L) stop("Usage: run_scale10m.R CORES OUTPUT")
library(fastEmbedR)
cores <- as.integer(args[[1L]])
stopifnot(cores %in% c(1L, 4L, 8L, 16L, 32L))
output <- normalizePath(args[[2L]], mustWork = TRUE)
input <- paste0("/scratch/firenze/NN/Data/BigANN/deep/",
    "1000000000/base.1000000000.fbin")
source <- massive_matrix(input)
stopifnot(source$nrow == 1e9, source$ncol == 96L)
view <- fastEmbedR:::massive_matrix_rows(source, 1000001, 1e7)
started <- proc.time()[[3L]]
fit <- massive_cluster(view, method = "leiden",
    massive = "landmark", landmarks = 50000L, k = 30L,
    output = file.path(output, "labels"), backend = "cpu",
    n.cores = cores, chunk_rows = 50000L,
    memory_limit = "8GB", knn_method = "hnsw",
    seed = 4L, checkpoint = TRUE)
elapsed <- unname(proc.time()[[3L]] - started)
stopifnot(fit$nrow == 1e7,
    file.info(fit$membership_path)$size == 4e7,
    file.info(fit$confidence_path)$size == 4e7,
    fit$assignment_workers == cores,
    fit$fitting_cpu_workers == 1L)
settings <- fit$knn$hnsw_settings
write.csv(data.frame(rows = fit$nrow, cores = cores,
    mode = "landmark_file_backed", landmarks = 50000L,
    source_window_bytes = 4 * 1e7 * 96,
    elapsed_seconds = elapsed,
    knn_build_seconds = fit$knn$build_seconds,
    knn_query_seconds = fit$knn$query_seconds,
    cluster_and_vote_seconds = fit$elapsed_sec,
    communities = fit$n_communities,
    M = settings$M, efConstruction = settings$efConstruction,
    efSearch = settings$efSearch,
    hnsw_build_threads = settings$build_threads,
    assignment_workers = fit$assignment_workers),
    file.path(output, "metrics.csv"), row.names = FALSE)
writeLines(unname(tools::md5sum(c(fit$membership_path,
    fit$confidence_path))), file.path(output, "output.md5"))
cat("CLUSTER_SCALE10M_PASS\n")
