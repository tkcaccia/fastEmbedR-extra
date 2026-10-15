library(fastEmbedR)

script <- file.path("benchmarks", "linux", "massive-data",
    "validate_multigpu_knn_matched.R")
source(script, local = TRUE)

parts <- list(
    list(query_row_range = c(1L, 4L),
        resources = list(chunk_rows = 1L, gpu_device = 0L),
        ivf_settings = list(list(nlist = 8L, nprobe = 4L,
            pilot_rows = 1L, pilot_recall = 1))),
    list(query_row_range = c(5L, 8L),
        resources = list(chunk_rows = 1L, gpu_device = 1L),
        ivf_settings = list(list(nlist = 8L, nprobe = 8L,
            pilot_rows = 1L, pilot_recall = 1)))
)
rows <- holdout_rows(8L, list(per_device = parts), 4L)
stopifnot(length(rows) == 4L, !any(rows %in% c(1L, 5L)))
single <- list(ivf_settings = parts[[1L]]$ivf_settings,
    gpu_devices = 0L, n_vertices = 8L)
settings <- settings_table(single, list(per_device = parts))
stopifnot(nrow(settings) == 3L,
    identical(settings$nprobe, c(4L, 4L, 8L)))

local({
    directory <- tempfile("matched_knn_")
    dir.create(directory)
    on.exit(unlink(directory, recursive = TRUE))
    path <- file.path(directory, "input.f32")
    values <- matrix(c(0, 0, 1, 0, 2, 0, 3, 0,
        4, 0, 5, 0, 6, 0, 7, 0), ncol = 2L, byrow = TRUE)
    writeBin(as.numeric(t(values)), path, size = 4L)
    input <- massive_matrix(path, 8L, 2L)
    graph <- massive_full_knn_graph(input, 2L,
        file.path(directory, "exact"), backend = "cpu",
        method = "exact", n.cores = 1L, chunk_rows = 2L,
        reference_chunk_rows = 4L, memory_limit = "1GB")
    observed <- score_matched(input, graph, graph,
        c(2L, 4L, 6L, 8L), 4L)
    stopifnot(all(observed$one_gpu == 1),
        all(observed$two_gpu == 1))
})
cat("MATCHED_KNN_FIXTURE=PASS\n")
