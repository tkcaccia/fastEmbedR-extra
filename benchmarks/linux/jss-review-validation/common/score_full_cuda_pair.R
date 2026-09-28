#!/usr/bin/env Rscript
script_arg <- commandArgs(FALSE)
script_file <- sub("^--file=", "", script_arg[
    startsWith(script_arg, "--file=")
][[1L]])
source(file.path(dirname(script_file), "common.R"))
suppressPackageStartupMessages(library(float))
args <- parse_cli()
dataset <- args$dataset
data_root <- args[["data-root"]]
input_root <- args[["input-root"]]
output_root <- args[["output-root"]]
stopifnot(nzchar(dataset), nzchar(data_root), nzchar(input_root),
    nzchar(output_root))

methods <- data.frame(
    mode = c("r_cuda", "python_cuda", "r_cuda", "python_cuda"),
    method = c("fastembedr_tsne", "cuml_tsne",
        "fastembedr_umap", "cuml_umap")
)
if (identical(Sys.getenv("INCLUDE_NOMAD"), "TRUE")) {
    methods <- rbind(methods, data.frame(
        mode = "python_cuda", method = "nomad"))
}

score_method <- function(index, high, labels, quality_rows, source_n,
                         perplexity) {
    mode <- methods$mode[[index]]
    method <- methods$method[[index]]
    directory <- file.path(output_root, "workflow_comparators", mode,
        dataset, method)
    fit_status <- file.path(directory, "status.csv")
    if (!file.exists(fit_status) ||
            utils::read.csv(fit_status)$status[[1L]] != "success") {
        return(data.frame(method = method, status = "fit_unavailable",
            error = NA_character_))
    }
    embedding <- utils::read.csv(file.path(directory, "embedding.csv"),
        colClasses = c("integer", "NULL", "NULL", "numeric", "numeric"))
    if (nrow(embedding) != source_n ||
            any(embedding$benchmark_row != seq_len(source_n))) {
        stop("Embedding row identities do not match the full dataset: ",
            method)
    }
    layout <- as.matrix(embedding[quality_rows,
        c("dimension_1", "dimension_2")])
    if (any(!is.finite(layout))) {
        stop("Non-finite saved embedding: ", method)
    }
    quality <- quality_metrics(high, layout, labels, perplexity, 1, 30L)
    if (grepl("umap", method, fixed = TRUE) || method == "nomad") {
        quality$sampled_kl <- NA_real_
    }
    result <- utils::read.csv(file.path(directory, "result.csv"),
        check.names = FALSE)
    if (nrow(result) != 1L || result$n[[1L]] != source_n) {
        stop("Fit result does not match the full dataset: ", method)
    }
    for (field in names(quality)) result[[field]] <- quality[[field]]
    result$quality_sample_n <- length(quality_rows)
    result$quality_analysis <- "posthoc_R"
    write_csv_atomic(result, file.path(directory,
        "result_with_quality.csv"))
    write_csv_atomic(cbind(data.frame(
        dataset = dataset, method = method, source_n = source_n,
        quality_sample_n = length(quality_rows),
        analysis = "posthoc_R"
    ), quality), file.path(directory, "quality.csv"))
    data.frame(method = method, status = "success",
        error = NA_character_)
}

main <- function() {
    shared <- readRDS(file.path(input_root, dataset, "matched_inputs.rds"))
    loaded <- load_dataset(data_root, dataset)
    n <- nrow(loaded$data)
    if (n != shared$source_n || length(shared$rows) != n ||
            any(shared$rows != seq_len(n))) {
        stop("This campaign does not contain every source row.")
    }
    rows <- shared$quality_rows
    high <- as_double_matrix(loaded$data[rows, , drop = FALSE])
    labels <- if (is.null(loaded$labels)) NULL else loaded$labels[rows]
    reports <- lapply(seq_len(nrow(methods)), function(index) {
        tryCatch(score_method(index, high, labels, rows, n,
            shared$perplexity), error = function(error) {
            data.frame(method = methods$method[[index]],
                status = "failed", error = conditionMessage(error))
        })
    })
    summary <- do.call(rbind, reports)
    directory <- file.path(output_root, "posthoc_quality", dataset)
    write_csv_atomic(summary, file.path(directory, "status.csv"))
    if (!all(summary$status == "success")) {
        stop("Full-row quality pass has missing or failed methods.")
    }
}

main()
