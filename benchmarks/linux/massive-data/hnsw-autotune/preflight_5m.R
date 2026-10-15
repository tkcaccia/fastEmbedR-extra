#!/usr/bin/env Rscript

if (packageVersion("faissR") < package_version("0.99.52")) stop(
    "The 5M campaign requires faissR >= 0.99.52")
if (packageVersion("fastEmbedR") < package_version("0.1")) stop(
    "The 5M campaign requires fastEmbedR >= 0.1")
set.seed(413)
x <- float::fl(matrix(rnorm(600), nrow = 100L))
index <- fastEmbedR:::faissr_hnsw_index_build_cpp(
    x, 100L, 6L, 5L, 1L, 16L, 80L)
found <- fastEmbedR:::faissr_hnsw_index_search_cpp(
    index$pointer, x[1:4, , drop = FALSE], 6L, 80L, 1L)
if (!identical(index$tuning_rule, "explicit") ||
    !identical(index$M, 16L) ||
    !identical(index$efConstruction, 80L) ||
    !isTRUE(found$index_reused) ||
    !identical(found$ef_search, 80L) ||
    any(found$indices < 1L | found$indices > 100L)) stop(
        "Explicit persistent HNSW preflight failed")
worker_index <- faissR:::nn_faiss_hnsw_index_build_float32_cpp(
    x, 16L, 80L, 120L, "euclidean", "euclidean", 1L)
worker_found <- faissR:::nn_faiss_hnsw_index_search_float32_cpp(
    worker_index, x[1:4, , drop = FALSE], 6L, FALSE,
    80L, 1L, "double")
if (!isTRUE(worker_found$index_reused) ||
    !identical(worker_found$ef_search, 80L)) stop(
        "Calibration worker HNSW preflight failed")
pilot <- faissR::hnsw_tune(x, k = 5L, target_recall = 0.9,
    reference_size = 100L, tune_queries = 20L,
    holdout_queries = 20L, seed = 19L,
    build_grid = data.frame(m = 16L, ef_construction = 80L),
    ef_search = 80L, safety_margin = 0,
    bootstrap_repetitions = 25L, timing_repetitions = 1L,
    workload_query_rows = 100L, expected_query_batches = 10L,
    n_threads = 1L, time_limit = 60, build_index = FALSE)
if (!identical(pilot$selected$ef_search, 80L) ||
    !isTRUE(pilot$selected$holdout_confirmed)) stop(
        "Singleton-grid HNSW tuning preflight failed")
cat("faissR", as.character(packageVersion("faissR")),
    "fastEmbedR", as.character(packageVersion("fastEmbedR")),
    "persistent explicit HNSW: PASS\n")
