#!/usr/bin/env Rscript

args <- commandArgs(FALSE)
file <- sub("^--file=", "", args[startsWith(args, "--file=")][[1L]])
root <- dirname(dirname(normalizePath(file, mustWork = TRUE)))
source(file.path(root, "common", "common.R"))

load_functions <- function(path, names) {
    for (expression in parse(path)) {
        if (is.call(expression) && identical(expression[[1L]], as.name("<-")) &&
                as.character(expression[[2L]]) %in% names) {
            eval(expression, envir = .GlobalEnv)
        }
    }
}

load_functions(file.path(root, "common", "run_validation.R"), c(
    "workflow_timing_eligibility", "cuda_workflow_ratios"
))
load_functions(file.path(root, "common", "run_r_comparator.R"),
    "stage_seconds")

contract <- utils::read.csv(file.path(root, "common",
    "workflow_parameter_contract.csv"))
for (name in c("fastembedr_tsne", "cuml_tsne")) {
    policy <- contract$iterations_policy[contract$method == name]
    stopifnot(identical(policy, if (name == "fastembedr_tsne") {
        "250_early+750_normal=1000_total"
    } else "1000_total"))
}
stopifnot(contract$n_neighbors[contract$method == "cuml_tsne"] == 91L)
stopifnot(contract$min_grad_norm[contract$method == "cuml_tsne"] == 0)

identical_rows <- rbind(
    c(0, 0, 1), c(0, 0, 1), c(1, 1, 0), c(2, 1, 0)
)
distances <- exact_distance_matrix(identical_rows)
stopifnot(
    is.finite(trustworthiness_from_distances(distances, distances, 1L)),
    abs(trustworthiness_from_distances(distances, distances, 1L) - 1) < 1e-12
)

method <- "uwot"
stopifnot(all(is.na(stage_seconds(matrix(0, 2L, 2L)))))
method <- "fastembedr_tsne"
fit <- list(metrics = data.frame(
    preprocess_elapsed = 0.1, knn_elapsed = 0.2,
    initialization_elapsed = 0.3, embedding_elapsed = 0.4
))
stopifnot(identical(unname(stage_seconds(fit)), c(0.1, 0.2, 0.3, 0.4)))

row <- function(method, family, n = 100L) {
    fast <- startsWith(method, "fastembedr_")
    data.frame(
        dataset = "test", seed = 4L, n = n, p = 8L,
        n_components = 2L, family = family, backend = "cuda",
        method = method, timing_eligible = TRUE, timing_reps = 5L,
        warmup_count = 1L, warmup_excluded = TRUE,
        output_materialized_on_host_before_timer = TRUE,
        device_synchronized = TRUE, elapsed_median_sec = 1,
        timing_scope = if (fast) "R_public_fit" else "direct_Python_fit",
        timing_boundary = "host_float32_to_host_result",
        input_precision = "float32",
        comparison_contract = if (family == "tsne") {
            "workflow_1000_total_iterations"
        } else "workflow_package_policy",
        total_iterations = if (family == "tsne") 1000L else NA_integer_,
        n_neighbors = if (family == "umap") 30L else NA_integer_,
        initialization_requested = if (family == "tsne") "pca" else {
            "spectral"
        },
        affinity_support = if (family == "tsne") {
            if (fast) "compact_k_30" else "n_neighbors_91"
        } else "k_30",
        knn_median_sec = if (fast) 0.2 else NA_real_,
        embedding_median_sec = if (fast) 0.4 else NA_real_,
        trustworthiness = 0.9, preserve_at_30 = 0.5,
        min_dist_value = if (fast) 0.01 else 0.1
    )
}

for (family in c("tsne", "umap")) {
    rows <- rbind(row(paste0("fastembedr_", family), family),
                  row(paste0("cuml_", family), family))
    stopifnot(nrow(cuda_workflow_ratios(rows, family)) == 1L)
    rows$n[[2L]] <- 101L
    stopifnot(nrow(cuda_workflow_ratios(rows, family)) == 0L)
}

test_cuda_pair_plot <- function() {
pair_root <- tempfile("cuda-pair-test-")
on.exit(unlink(pair_root, recursive = TRUE), add = TRUE)
pair_input <- file.path(pair_root, "input")
pair_output <- file.path(pair_root, "output")
dataset <- "test"
rows_file <- file.path(pair_input, dataset, "workflow_comparators",
    "rows_labels.csv")
write_csv_atomic(data.frame(
    row = 1:5, source_row = 1:5, label = c("A", "A", "B", "B", "B"),
    quality_sample = c(TRUE, TRUE, TRUE, TRUE, FALSE)
), rows_file)
for (mode in c("r_cuda", "python_cuda")) {
    comparator <- if (mode == "r_cuda") "fastembedr_tsne" else "cuml_tsne"
    directory <- file.path(pair_output, "workflow_comparators", mode,
        dataset, comparator)
    write_csv_atomic(data.frame(status = "success"),
        file.path(directory, "status.csv"))
    write_csv_atomic(data.frame(
        timing_scope = if (mode == "r_cuda") {
            "R_public_fit"
        } else "direct_Python_fit",
        timing_boundary = "host_float32_to_host_result",
        elapsed_median_sec = 1, trustworthiness = 0.9,
        preserve_at_30 = 0.8, sampled_kl = 1.2
    ), file.path(directory, "result.csv"))
    write_csv_atomic(data.frame(
        benchmark_row = 1:5,
        dimension_1 = c(0, 0, 1, 1, 2),
        dimension_2 = c(0, 1, 0, 1, 2)
    ), file.path(directory, "embedding.csv"))
}
plot_script <- file.path(root, "common", "plot_cuda_pair.R")
plot_args <- c(plot_script, "--dataset=test", "--family=tsne",
    paste0("--input-root=", pair_input),
    paste0("--output-root=", pair_output))
run_plot <- function() {
    suppressWarnings(system2(file.path(R.home("bin"), "Rscript"),
        plot_args, stdout = TRUE, stderr = TRUE))
}
stopifnot(is.null(attr(run_plot(), "status")))
pair_dir <- file.path(pair_output, "cuda_comparison_live", dataset,
    "tsne")
stopifnot(file.info(file.path(pair_dir, "comparison.png"))$size > 0)
stopifnot(all(utils::read.csv(file.path(pair_dir, "comparison.csv"))$
    status == "success"))
summary <- utils::read.csv(file.path(pair_dir, "comparison.csv"))
stopifnot(all(summary$plotted_n == 5L))
stopifnot(all(summary$quality_sample_n == 4L))
missing <- file.path(pair_output, "workflow_comparators", "python_cuda",
    dataset, "cuml_tsne", "status.csv")
unlink(missing)
stopifnot(identical(attr(run_plot(), "status"), 1L))
stopifnot(utils::read.csv(file.path(pair_dir, "status.csv"))$status ==
    "incomplete")
}
test_cuda_pair_plot()
cat("Benchmark logic: PASS\n")
