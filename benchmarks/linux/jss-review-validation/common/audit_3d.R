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
              "fastembedr_umap", "uwot", "uwot_fast_sgd", "r_umap"),
    r_cuda = c("fastembedr_tsne", "fastembedr_umap"),
    python_cpu = c("sklearn_tsne", "python_opentsne", "python_umap"),
    python_cuda = c("cuml_tsne", "cuml_umap")
)
expected_unsupported <- function(mode, method) {
    mode == "r_cuda" ||
        (mode == "python_cuda" && method == "cuml_tsne")
}
records <- list()
metrics <- list()
for (mode in names(methods)) {
    for (dataset in datasets) {
        for (method in methods[[mode]]) {
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
                state == "unsupported"
            } else {
                state == "success"
            }
            result_file <- file.path(directory, "result.csv")
            embedding_file <- file.path(directory, "embedding.csv")
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
                        result$n_components[[1L]] == 3L
                    if (valid) {
                        metrics[[length(metrics) + 1L]] <- result
                    }
                }
            }
            records[[length(records) + 1L]] <- data.frame(
                dataset = dataset, mode = mode, method = method,
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
