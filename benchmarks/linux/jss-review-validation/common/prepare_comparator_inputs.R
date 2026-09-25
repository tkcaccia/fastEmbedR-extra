#!/usr/bin/env Rscript

args <- commandArgs(trailingOnly = TRUE)
arg_value <- function(name, default = NULL) {
    prefix <- paste0("--", name, "=")
    hit <- args[startsWith(args, prefix)]
    if (!length(hit)) return(default)
    sub(prefix, "", hit[[length(hit)]], fixed = TRUE)
}

script_file <- sub("^--file=", "", commandArgs(FALSE)[
    startsWith(commandArgs(FALSE), "--file=")
][[1L]])
script_dir <- dirname(normalizePath(script_file, mustWork = TRUE))
source(file.path(script_dir, "common.R"))
suppressPackageStartupMessages(library(fastEmbedR))
suppressPackageStartupMessages(library(float))

base_dir <- normalizePath(
    arg_value("base-dir", "/scratch/firenze/NN"), mustWork = TRUE
)
data_root <- arg_value("data-root", file.path(base_dir, "Data"))
input_root <- arg_value(
    "input-root", file.path(base_dir, "fastEmbedR-input", "jss_validation")
)
output_root <- arg_value(
    "output-root", file.path(base_dir, "fastEmbedR-results", "jss_validation")
)
dataset <- arg_value("dataset", "MNIST")

write_float32_matrix <- function(x, path) {
    connection <- file(path, "wb")
    on.exit(close(connection), add = TRUE)
    writeBin(
        as.vector(t(as_double_matrix(x))), connection,
        size = 4L, endian = "little"
    )
}

prepare_quality_affinity <- function(x, rows, perplexity) {
    sample <- x[rows, , drop = FALSE]
    distance <- exact_distance_matrix(sample)
    knn <- exact_knn_from_distances(
        distance, min(nrow(sample) - 1L, ceiling(perplexity))
    )
    symmetrized_affinities(knn, perplexity)
}

main <- function() {
    shared_path <- file.path(input_root, dataset, "matched_inputs.rds")
    if (!file.exists(shared_path)) {
        stop("Missing matched input: ", shared_path, call. = FALSE)
    }
    shared <- readRDS(shared_path)
    loaded <- load_dataset(data_root, dataset)
    x <- loaded$data[shared$rows, , drop = FALSE]
    directory <- file.path(input_root, dataset, "workflow_comparators")
    dir.create(directory, recursive = TRUE, showWarnings = FALSE)
    write_float32_matrix(x, file.path(directory, "data_float32.bin"))
    labels <- if (is.null(shared$labels)) {
        rep.int(NA_character_, nrow(x))
    } else {
        as.character(shared$labels)
    }
    write_csv_atomic(data.frame(
        row = seq_len(nrow(x)), label = labels,
        quality_sample = seq_len(nrow(x)) %in% shared$quality_rows
    ), file.path(directory, "rows_labels.csv"))
    affinity <- prepare_quality_affinity(
        x, shared$quality_rows, shared$perplexity
    )
    write_csv_atomic(
        affinity, file.path(directory, "quality_compact_affinity.csv")
    )
    write_csv_atomic(data.frame(
        dataset = dataset, n = nrow(x), p = ncol(x),
        quality_n = length(shared$quality_rows),
        perplexity = shared$perplexity,
        n_neighbors = ceiling(shared$perplexity),
        selected_rows_sha256 = sha256_file(
            file.path(input_root, dataset, "row_identifiers.csv")
        ), stringsAsFactors = FALSE
    ), file.path(directory, "manifest.csv"))
    status <- status_row(
        "comparator_inputs", dataset, "cpu", "success",
        n = nrow(x), p = ncol(x), quality_n = length(shared$quality_rows)
    )
    write_csv_atomic(status, file.path(
        output_root, "comparator_inputs", dataset, "cpu", "status.csv"
    ))
}

tryCatch(
    main(),
    error = function(error) {
        status <- status_row(
            "comparator_inputs", dataset, "cpu", "failed",
            conditionMessage(error)
        )
        write_csv_atomic(status, file.path(
            output_root, "comparator_inputs", dataset, "cpu", "status.csv"
        ))
        stop(error)
    }
)
