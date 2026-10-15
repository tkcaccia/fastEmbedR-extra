#!/usr/bin/env Rscript

args <- commandArgs(FALSE)
file <- sub("^--file=", "", args[startsWith(args, "--file=")][[1L]])
root <- dirname(dirname(normalizePath(file, mustWork = TRUE)))
source(file.path(root, "common", "common.R"))

fixture <- list(data = matrix(seq_len(24L), nrow = 6L),
    labels = rep(c("a", "b"), each = 3L))
all_rows <- full_benchmark_rows(fixture)
stopifnot(identical(all_rows, seq_len(nrow(fixture$data))))
selected <- subset_dataset(fixture, all_rows)
stopifnot(identical(selected$data, fixture$data),
    identical(selected$labels, fixture$labels),
    identical(selected$rows, all_rows))
large_fixture <- list(data = matrix(0, nrow = 70001L, ncol = 2L))
stopifnot(length(full_benchmark_rows(large_fixture)) == 70001L)
scratch <- tempfile("comparator-full-source-")
dir.create(file.path(scratch, "Data", "COIL20"), recursive = TRUE)
dir.create(file.path(scratch, "input", "COIL20"), recursive = TRUE)
data <- matrix(seq_len(32L), nrow = 8L)
labels <- rep(c("a", "b"), each = 4L)
save(data, labels, file = file.path(
    scratch, "Data", "COIL20", "COIL20_float32.RData"))
saveRDS(list(rows = c(1L, 3L, 5L, 7L),
    quality_rows = c(2L, 3L, 4L),
    labels = labels[c(1L, 3L, 5L, 7L)],
    perplexity = 2L, source_n = 8L),
    file.path(scratch, "input", "COIL20", "matched_inputs.rds"))
prepare <- file.path(root, "common", "prepare_comparator_inputs.R")
prepare_args <- c(prepare, paste0("--base-dir=", scratch),
    paste0("--data-root=", file.path(scratch, "Data")),
    paste0("--input-root=", file.path(scratch, "input")),
    paste0("--output-root=", file.path(scratch, "output")),
    "--dataset=COIL20", "--full-dataset=TRUE")
prepared <- suppressWarnings(system2(
    file.path(R.home("bin"), "Rscript"), prepare_args,
    stdout = TRUE, stderr = TRUE))
if (!identical(attr(prepared, "status") %||% 0L, 0L)) {
    stop(paste(prepared, collapse = "\n"))
}
full_dir <- file.path(scratch, "input", "COIL20",
    "workflow_comparators")
full_manifest <- utils::read.csv(file.path(full_dir, "manifest.csv"))
full_rows <- utils::read.csv(file.path(full_dir, "rows_labels.csv"))
stopifnot(full_manifest$n == 8L, full_manifest$source_n == 8L,
    isTRUE(full_manifest$full_source),
    identical(full_rows$source_row, seq_len(8L)),
    identical(which(full_rows$quality_sample), c(3L, 5L, 7L)),
    file.info(file.path(full_dir, "data_float32.bin"))$size == 128)
unlink(scratch, recursive = TRUE)
load_functions_path <- file.path(root, "common", "pca_clustering_validation.R")
for (expression in parse(load_functions_path)) {
    if (is.call(expression) && identical(expression[[1L]], as.name("<-")) &&
            identical(as.character(expression[[2L]]),
                "prepare_clustering_dataset")) {
        eval(expression, envir = .GlobalEnv)
    }
}
cluster_rows <- prepare_clustering_dataset(fixture)
stopifnot(identical(cluster_rows$rows, all_rows),
    nrow(cluster_rows$x) == nrow(fixture$data))
walktrap_rows <- prepare_clustering_dataset(fixture, 4L)
stopifnot(length(walktrap_rows$rows) == 4L,
    identical(walktrap_rows$labels, fixture$labels[walktrap_rows$rows]))

load_functions <- function(path, names) {
    for (expression in parse(path)) {
        if (is.call(expression) && identical(expression[[1L]], as.name("<-")) &&
                as.character(expression[[2L]]) %in% names) {
            eval(expression, envir = .GlobalEnv)
        }
    }
}

load_functions(file.path(root, "common", "run_validation.R"), c(
    "workflow_timing_eligibility", "cuda_workflow_ratios",
    "umap_binary_vs_fuzzy", "scaling_stages",
    "scaling_stage_size", "summarize_scaling"
))
scaling_fixture <- expand.grid(
    threads = c(1L, 2L, 4L, 8L, 12L), replicate = 1:2
)
scaling_fixture$dataset <- "fixture"
scaling_fixture$n <- 1000L
scaling_fixture$cluster_n <- 800L
scaling_fixture$walktrap_n <- 500L
for (stage in scaling_stages()) {
    serial <- stage %in% c(
        "louvain_fit_sec", "leiden_fit_sec", "walktrap_fit_sec"
    )
    scaling_fixture[[stage]] <- if (serial) 1 else {
        12 / scaling_fixture$threads
    }
}
scaling_check <- summarize_scaling(scaling_fixture)
knn_check <- scaling_check[scaling_check$stage == "knn_sec" &
    scaling_check$threads == 12L, ]
walk_check <- scaling_check[
    scaling_check$stage == "walktrap_fit_sec" &
    scaling_check$threads == 12L, ]
pca_check <- scaling_check[
    scaling_check$stage == "pca_rank50_sec" &
    scaling_check$threads == 12L, ]
stopifnot(
    nrow(scaling_check) == 5L * length(scaling_stages()),
    knn_check$speedup == 12, knn_check$n_observations == 1000L,
    pca_check$n_observations == 800L,
    walk_check$speedup == 1, walk_check$fit_threads == 1L,
    walk_check$n_observations == 500L
)
load_functions(load_functions_path, "clustering_methods")
load_functions(load_functions_path, c(
    "adjusted_rand_index", "clustering_label_ari",
    "clustering_result_row"
))
stopifnot(identical(clustering_methods("cpu", 1440L),
    c("louvain", "leiden", "walktrap")))
stopifnot(identical(clustering_methods("cpu", 4001L),
    c("louvain", "leiden")))
stopifnot(identical(clustering_methods("cuda", 1440L),
    c("louvain", "leiden")))
stopifnot(identical(clustering_methods("metal", 1440L),
    c("louvain", "leiden")))
dataset <- "fixture"
result <- list(membership = c(1L, 1L, 2L, 2L), modularity = 0.5)
row <- clustering_result_row("louvain", "fastEmbedR", "cpu",
    4L, 0.01, result, c(1L, 1L, 2L, 2L),
    c(2L, 2L, 1L, 1L))
stopifnot(row$label_ari == 1, row$reference_membership_ari == 1,
    row$graph_scope == "full")
load_functions(file.path(root, "common", "run_r_comparator.R"),
    c("stage_seconds", "can_fit_repetitions", "timed_fits",
      "fitsne_grid_policy", "rtsne_pca_initialization", "fit_tsne"))

stopifnot(
    fitsne_grid_policy(1440L)$boxes == 50L,
    fitsne_grid_policy(70000L)$boxes == 90L,
    3L * fitsne_grid_policy(70000L)$boxes == 270L
)
n_components <- 2L
tsne_total_iterations <- 1000L
threads <- 4L
seed <- 4L
mock_fitsne <- list(fun = function(...) list(...), executable = "mock")
grid_call <- fit_tsne("fitsne", matrix(0, 70000L, 1L), 30,
    mock_fitsne)
stopifnot(grid_call$min_num_intervals == 86L,
    grid_call$nterms == 3L,
    grid_call$theta == 0.5,
    grid_call$intervals_per_integer == 1e6)
n_components <- 3L
bh_call <- fit_tsne("fitsne", matrix(0, 70000L, 1L), 30,
    mock_fitsne)
stopifnot(bh_call$theta == 0.2, !bh_call$fft_not_bh)
n_components <- 2L

set.seed(seed)
raw <- matrix(stats::rnorm(120L * 60L), nrow = 120L)
init <- rtsne_pca_initialization(raw)
stopifnot(identical(dim(init), c(120L, 2L)),
    all(is.finite(init)),
    max(abs(colMeans(init))) < 1e-10,
    abs(max(apply(init, 2L, stats::sd)) - 1e-4) < 1e-10)
rtsne_fit <- fit_tsne("rtsne", raw, 5)
stopifnot(rtsne_fit$origD == ncol(raw),
    identical(dim(rtsne_fit$Y), c(120L, 2L)),
    all(is.finite(rtsne_fit$Y)))
n_components <- 3L
stopifnot(identical(dim(rtsne_pca_initialization(raw)),
    c(120L, 3L)))
n_components <- 2L

timeout_seconds <- 7200
stopifnot(can_fit_repetitions(100, 3L, 7200))
stopifnot(!can_fit_repetitions(1900, 3L, 5200))
counter <- new.env(parent = emptyenv())
counter$n <- 0L
fit_once <- function(...) {
    counter$n <- counter$n + 1L
    list(metrics = list())
}
assert_fastembedr_backend <- function(fit) invisible(fit)
stage_seconds <- function(fit) {
    c(preprocess = 0, knn = 0, initialization = 0, embedding = 0)
}
dataset <- "fixture"
method <- "fastembedr_tsne"
timing_reps <- 3L
full_dataset <- FALSE
deadline_epoch <- as.numeric(Sys.time()) + 120
single <- timed_fits(matrix(0, 2L, 2L), 1L, NULL)
stopifnot(counter$n == 1L, length(single$elapsed) == 1L,
    !single$warmup_excluded)
counter$n <- 0L
deadline_epoch <- as.numeric(Sys.time()) + 7200
repeated <- timed_fits(matrix(0, 2L, 2L), 1L, NULL)
stopifnot(counter$n == 4L, length(repeated$elapsed) == 3L,
    repeated$warmup_excluded)
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
stopifnot(contract$n_neighbors[contract$method == "cuml_tsne"] == 90L)
stopifnot(contract$affinity_support[
    contract$method == "cuml_tsne"] == "cuml_default_90")
stopifnot(contract$min_grad_norm[contract$method == "cuml_tsne"] == 0)
stopifnot(contract$learning_rate_policy[
    contract$method == "cuml_tsne"] ==
    "capped_auto_n_over_48_50_to_200")
stopifnot(contract$optimizer[
    contract$method == "sklearn_tsne"] == "barnes_hut_theta_0.2")
stopifnot(contract$initialization_requested[
    contract$method == "rtsne"] == "pca")
stopifnot(contract$pca_preprocessing[
    contract$method == "rtsne"] == "none")
stopifnot(contract$optimizer[
    contract$method == "fastembedr_umap_binary"] == "native_binary_sgd")

identical_rows <- rbind(
    c(0, 0, 1), c(0, 0, 1), c(1, 1, 0), c(2, 1, 0)
)
distances <- exact_distance_matrix(identical_rows)
stopifnot(
    is.finite(trustworthiness_from_distances(distances, distances, 1L)),
    abs(trustworthiness_from_distances(distances, distances, 1L) - 1) < 1e-12
)
stopifnot(
    abs(neighborhood_quality_score(0.9, 0.5) - 0.642857142857) < 1e-10,
    identical(neighborhood_quality_score(0, 0), 0),
    is.na(neighborhood_quality_score(NA_real_, 0.5)),
    inherits(try(neighborhood_quality_score(1.1, 0.5), silent = TRUE),
        "try-error")
)
sample_quality <- quality_metrics(identical_rows, identical_rows[, 1:2],
    NULL, 1, 1, 1L)
stopifnot(is.finite(sample_quality$neighborhood_quality_score),
    is.na(sample_quality$label_knn_accuracy))
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
        comparator_mode = if (fast) "r_cuda" else "python_cuda",
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
        cuml_tsne_min_observed_iterations = if (method ==
                "cuml_tsne") 1000L else NA_integer_,
        n_neighbors = if (family == "umap") 30L else if (!fast) {
            90L
        } else NA_integer_,
        initialization_requested = if (family == "tsne") "pca" else {
            "spectral"
        },
        affinity_support = if (family == "tsne") {
            if (fast) "compact_k_30" else "cuml_default_90"
        } else "k_30",
        knn_median_sec = if (fast) 0.2 else NA_real_,
        embedding_median_sec = if (fast) 0.4 else NA_real_,
        trustworthiness = 0.9, preserve_at_30 = 0.5,
        neighborhood_quality_score = neighborhood_quality_score(0.9, 0.5),
        quality_sample_n = 80L,
        graph_mode = if (method == "fastembedr_umap_binary") {
            "binary"
        } else if (family == "umap") "fuzzy" else NA_character_,
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
tsne_rows <- rbind(row("fastembedr_tsne", "tsne"),
    row("cuml_tsne", "tsne"))
tsne_rows$cuml_tsne_min_observed_iterations[[2L]] <- 0L
stopifnot(nrow(cuda_workflow_ratios(tsne_rows, "tsne")) == 0L)
tsne_rows$cuml_tsne_min_observed_iterations <- NULL
stopifnot(nrow(cuda_workflow_ratios(tsne_rows, "tsne")) == 0L)
tsne_rows <- rbind(row("fastembedr_tsne", "tsne"),
    row("cuml_tsne", "tsne"))
tsne_rows$n_neighbors[[2L]] <- 91L
stopifnot(nrow(cuda_workflow_ratios(tsne_rows, "tsne")) == 0L)
tsne_rows$n_neighbors[[2L]] <- 90L
tsne_rows$affinity_support[[2L]] <- "n_neighbors_91"
stopifnot(nrow(cuda_workflow_ratios(tsne_rows, "tsne")) == 0L)
umap_rows <- rbind(row("fastembedr_umap", "umap"),
    row("fastembedr_umap_binary", "umap"))
comparison <- umap_binary_vs_fuzzy(umap_rows)
stopifnot(nrow(comparison) == 1L,
    comparison$binary_over_fuzzy_time == 1,
    comparison$binary_quality == comparison$fuzzy_quality)
umap_rows$graph_mode[[2L]] <- "fuzzy"
stopifnot(inherits(try(umap_binary_vs_fuzzy(umap_rows), silent = TRUE),
    "try-error"))

test_cuda_pair_plot <- function() {
old_nomad <- Sys.getenv("INCLUDE_NOMAD", unset = NA_character_)
on.exit(if (is.na(old_nomad)) Sys.unsetenv("INCLUDE_NOMAD") else {
    Sys.setenv(INCLUDE_NOMAD = old_nomad)
}, add = TRUE)
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
        preserve_at_30 = 0.8,
        neighborhood_quality_score = neighborhood_quality_score(0.9, 0.8),
        sampled_kl = 1.2
    ), file.path(directory, "result.csv"))
    write_csv_atomic(data.frame(
        benchmark_row = 1:5,
        dimension_1 = c(0, 0, 1, 1, 2),
        dimension_2 = c(0, 1, 0, 1, 2)
    ), file.path(directory, "embedding.csv.gz"))
    compressed <- embedding_csv_path(directory)
    stopifnot(endsWith(compressed, ".csv.gz"),
        nrow(utils::read.csv(compressed)) == 5L)
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
stopifnot(all(abs(summary$neighborhood_quality_score -
    neighborhood_quality_score(0.9, 0.8)) < 1e-12))
for (name in c("fastembedr_umap", "fastembedr_umap_binary",
        "cuml_umap")) {
    mode <- if (name == "cuml_umap") "python_cuda" else "r_cuda"
    directory <- file.path(pair_output, "workflow_comparators", mode,
        dataset, name)
    write_csv_atomic(data.frame(status = "success"),
        file.path(directory, "status.csv"))
    write_csv_atomic(data.frame(
        timing_scope = "R_public_fit", elapsed_median_sec = 1,
        trustworthiness = 0.9, preserve_at_30 = 0.8,
        neighborhood_quality_score = neighborhood_quality_score(0.9, 0.8)
    ), file.path(directory, "result.csv"))
    write_csv_atomic(data.frame(
        benchmark_row = 1:5, dimension_1 = c(0, 0, 1, 1, 2),
        dimension_2 = c(0, 1, 0, 1, 2)
    ), file.path(directory, "embedding.csv.gz"))
}
plot_args[[3L]] <- "--family=umap"
stopifnot(is.null(attr(run_plot(), "status")))
umap_summary <- utils::read.csv(file.path(pair_output,
    "cuda_comparison_live", dataset, "umap", "comparison.csv"))
stopifnot(identical(umap_summary$method, c("fastembedr_umap",
    "fastembedr_umap_binary", "cuml_umap")))
stopifnot(identical(umap_summary$graph_mode,
    c("fuzzy", "binary", "fuzzy")))
plot_args[[3L]] <- "--family=tsne"
nomad_dir <- file.path(pair_output, "workflow_comparators",
    "python_cuda", dataset, "nomad")
dir.create(nomad_dir, recursive = TRUE)
file.copy(file.path(dirname(nomad_dir), "cuml_tsne",
    c("status.csv", "result.csv", "embedding.csv.gz")), nomad_dir)
Sys.setenv(INCLUDE_NOMAD = "TRUE")
stopifnot(is.null(attr(run_plot(), "status")))
nomad_summary <- utils::read.csv(file.path(pair_dir,
    "comparison.csv"))
stopifnot(nrow(nomad_summary) == 3L)
stopifnot(identical(nomad_summary$method_family[[3L]], "nomad"))
stopifnot(is.na(nomad_summary$sampled_kl[[3L]]))
legacy_dir <- file.path(pair_root, "legacy")
write_csv_atomic(data.frame(benchmark_row = 1L),
    file.path(legacy_dir, "embedding.csv"))
stopifnot(identical(basename(embedding_csv_path(legacy_dir)),
    "embedding.csv"))
missing <- file.path(pair_output, "workflow_comparators", "python_cuda",
    dataset, "cuml_tsne", "status.csv")
unlink(missing)
stopifnot(identical(attr(run_plot(), "status"), 1L))
stopifnot(utils::read.csv(file.path(pair_dir, "status.csv"))$status ==
    "incomplete")
}
test_cuda_pair_plot()
cat("Benchmark logic: PASS\n")
