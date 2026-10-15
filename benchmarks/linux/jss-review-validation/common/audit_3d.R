#!/usr/bin/env Rscript

root <- Sys.getenv("OUTPUT_ROOT")
if (!nzchar(root)) stop("OUTPUT_ROOT is required.")
datasets <- c(
    "COIL20", "USPS", "FashionMNIST",
    "FlowRepository_FR-FCM-ZYRM_files", "flow18", "MNIST",
    "imagenet", "MetRef", "mass41", "TabulaMuris",
    "Macosko2015_retina"
)
methods <- list(
    r_cpu = c("fastembedr_tsne", "rtsne", "fitsne",
              "fastembedr_umap", "fastembedr_umap_binary", "uwot",
              "uwot_fast_sgd", "r_umap"),
    r_cuda = c("fastembedr_tsne", "fastembedr_umap",
               "fastembedr_umap_binary"),
    python_cpu = c("sklearn_tsne", "python_opentsne", "python_umap"),
    python_cuda = c("cuml_tsne", "cuml_umap")
)
expected_unsupported <- function(mode, method) {
    mode == "python_cuda" && method == "cuml_tsne"
}
records <- list()
metrics <- list()
for (mode in names(methods)) {
    for (dataset in datasets) {
        for (method in methods[[mode]]) {
            baseline_dir <- file.path(
                root, "workflow_comparators", mode, dataset, method
            )
            baseline_status_file <- file.path(baseline_dir, "status.csv")
            baseline_result_file <- file.path(baseline_dir, "result.csv")
            baseline_status <- if (file.exists(baseline_status_file)) {
                utils::read.csv(baseline_status_file, check.names = FALSE)
            } else NULL
            baseline_state <- if (is.null(baseline_status) ||
                    !nrow(baseline_status)) {
                "missing"
            } else as.character(baseline_status$status[[1L]])
            baseline_valid <- baseline_state == "success" &&
                file.exists(baseline_result_file)
            baseline <- if (baseline_valid) {
                utils::read.csv(baseline_result_file)
            } else NULL
            baseline_valid <- baseline_valid && nrow(baseline) == 1L &&
                baseline$n_components[[1L]] == 2L
            directory <- file.path(
                root, "workflow_comparators_3d", mode, dataset, method
            )
            status_file <- file.path(directory, "status.csv")
            status <- if (file.exists(status_file)) {
                utils::read.csv(status_file, check.names = FALSE)
            } else NULL
            state <- if (is.null(status) || !nrow(status)) {
                "missing"
            } else as.character(status$status[[1L]])
            expected <- expected_unsupported(mode, method)
            valid <- if (expected) {
                baseline_valid && state == "unsupported"
            } else {
                baseline_valid && state == "success"
            }
            result_file <- file.path(directory, "result.csv")
            embedding_file <- embedding_csv_path(directory)
            plot_file <- file.path(directory, "embedding.png")
            if (state == "success") {
                valid <- valid && file.exists(result_file) &&
                    file.exists(embedding_file) && file.exists(plot_file)
                if (valid) {
                    header <- strsplit(readLines(embedding_file, n = 1L),
                                       ",", fixed = TRUE)[[1L]]
                    result <- utils::read.csv(result_file)
                    valid <- "dimension_3" %in% header &&
                        nrow(result) == 1L &&
                        result$n_components[[1L]] == 3L &&
                        result$n[[1L]] == baseline$n[[1L]] &&
                        result$seed[[1L]] == baseline$seed[[1L]] &&
                        result$timing_scope[[1L]] ==
                            baseline$timing_scope[[1L]] &&
                        isTRUE(as.logical(result$timing_eligible[[1L]])) &&
                        isTRUE(as.logical(baseline$timing_eligible[[1L]]))
                    if (valid && method == "fastembedr_tsne" &&
                            mode == "r_cuda") {
                        valid <- identical(
                            result$optimizer[[1L]],
                            "fft_grid_3d_cuda_cufft"
                        )
                    }
                    if (valid) {
                        metrics[[length(metrics) + 1L]] <- result
                    }
                }
            }
            records[[length(records) + 1L]] <- data.frame(
                dataset = dataset, mode = mode, method = method,
                baseline_status = baseline_state,
                status = state, expected_unsupported = expected,
                valid = valid, directory = directory
            )
        }
    }
}
summary <- do.call(rbind, records)
directory <- file.path(root, "workflow_comparators_3d")
dir.create(directory, recursive = TRUE, showWarnings = FALSE)
utils::write.csv(summary, file.path(directory, "audit.csv"),
                 row.names = FALSE)
if (length(metrics)) {
    columns <- Reduce(union, lapply(metrics, names))
    aligned <- lapply(metrics, function(row) {
        row[setdiff(columns, names(row))] <- NA
        row[columns]
    })
    utils::write.csv(do.call(rbind, aligned),
                     file.path(directory, "metrics.csv"), row.names = FALSE)
}
print(table(summary$mode, summary$status))
if (!all(summary$valid)) {
    stop(sum(!summary$valid), " three-dimensional results need attention.")
}
