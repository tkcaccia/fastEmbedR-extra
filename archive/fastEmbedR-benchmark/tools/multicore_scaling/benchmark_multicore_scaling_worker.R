script_dir <- dirname(normalizePath(sub("^--file=", "", grep(
  "^--file=", commandArgs(trailingOnly = FALSE), value = TRUE
)[1L])))
source(file.path(script_dir, "multicore_scaling_common.R"))

dataset <- arg_value("dataset", "MetRef")
stage <- arg_value("stage", "knn")
data_root <- arg_value("data-root", "/scratch/firenze/NN/Data")
cache_root <- arg_value("cache-root", "/scratch/firenze/NN/fastEmbedR-input/multicore_scaling")
out_dir <- dir_create(arg_value("out-dir", file.path(tempdir(), "multicore_scaling")))
n.cores <- as_int(arg_value("n.cores", "1"), 1L)
blas_threads <- as_int(arg_value("blas-threads", "1"), 1L)
repeats <- as_int(arg_value("repeats", "5"), 5L)
warmups <- as_int(arg_value("warmups", "1"), 1L)
seed <- as_int(arg_value("seed", "4"), 4L)
run_id <- arg_value("run-id", format(Sys.time(), "%Y%m%d_%H%M%S"))
benchmark_scope <- arg_value("scope", "primary_scaling")

if (n.cores < 1L || blas_threads < 1L || repeats < 1L || warmups < 0L) {
  stop("Invalid thread, repeat, or warm-up count.", call. = FALSE)
}
valid_stages <- c(
  "knn", "pca_initialization", "tsne_embedding",
  "umap_graph", "umap_initialization", "umap_optimization",
  "full_opentsne", "full_umap"
)
if (!stage %in% valid_stages) {
  stop("Unknown stage: ", stage, call. = FALSE)
}

Sys.setenv(
  OMP_NUM_THREADS = blas_threads,
  OPENBLAS_NUM_THREADS = blas_threads,
  MKL_NUM_THREADS = blas_threads,
  VECLIB_MAXIMUM_THREADS = blas_threads,
  RCPP_PARALLEL_NUM_THREADS = n.cores
)
suppressPackageStartupMessages(library(fastEmbedR))

loaded <- load_scaling_dataset(dataset, data_root, seed)
x <- loaded$data
pars <- dataset_parameters(dataset, nrow(x))
paths <- cache_paths(cache_root, dataset)

needs_cache <- stage %in% c(
  "tsne_embedding", "umap_graph", "umap_initialization", "umap_optimization"
)
if (needs_cache && !all(file.exists(paths$knn, paths$pca, paths$umap))) {
  stop(
    "Fixed benchmark cache is missing for ", dataset,
    ". Run prepare_multicore_scaling_inputs.R first.", call. = FALSE
  )
}

knn <- if (needs_cache) readRDS(paths$knn) else NULL
pca_init <- if (identical(stage, "tsne_embedding")) readRDS(paths$pca) else NULL
umap_initialized <- if (stage %in% c("umap_initialization", "umap_optimization")) {
  readRDS(paths$umap)
} else NULL

subset_knn <- function(width) {
  list(
    indices = knn$indices[, seq_len(width), drop = FALSE],
    distances = knn$distances[, seq_len(width), drop = FALSE]
  )
}

run_once <- function() {
  if (identical(stage, "knn")) {
    value <- fastEmbedR::precompute_knn(
      x, k = max(pars$k_umap, pars$k_tsne), metric = "euclidean",
      backend = "cpu", n.cores = n.cores
    )
    return(list(value = value, rows = list(list(
      measured_stage = "knn", elapsed_sec = value$elapsed_sec,
      effective_threads = n.cores,
      implementation = value$engine %||% "native_cpu_hnsw"
    ))))
  }
  if (identical(stage, "pca_initialization")) {
    started <- proc.time()[["elapsed"]]
    value <- fastEmbedR::pca(
      x, ncomp = 2L, center = TRUE, scale = FALSE, backend = "cpu",
      n.cores = n.cores, seed = seed, opentsne_init = TRUE
    )
    elapsed <- proc.time()[["elapsed"]] - started
    return(list(value = value, rows = list(list(
      measured_stage = "pca_initialization", elapsed_sec = elapsed,
      effective_threads = value$n.cores_effective %||% NA_integer_,
      implementation = value$backend %||% "native_cpu_rsvd"
    ))))
  }
  if (identical(stage, "tsne_embedding")) {
    input <- subset_knn(pars$k_tsne)
    started <- proc.time()[["elapsed"]]
    value <- fastEmbedR::opentsne_knn(
      input, n_neighbors = pars$k_tsne, perplexity = pars$perplexity,
      affinity_support = "standard", Y_init = pca_init,
      backend = "cpu", n.cores = n.cores, seed = seed,
      early_exaggeration_iter = 250L, early_exaggeration = 12,
      n_iter = 500L, exaggeration = 1, learning_rate = "auto",
      auto_config = FALSE, record_costs = FALSE
    )
    wrapper_elapsed <- proc.time()[["elapsed"]] - started
    cfg <- attr(value, "fastEmbedR_config")
    rows <- list(
      list(
        measured_stage = "tsne_affinity", elapsed_sec = cfg$affinity_elapsed_sec,
        effective_threads = cfg$n.cores,
        implementation = "native_sparse_affinity_float32"
      ),
      list(
        measured_stage = "tsne_optimization", elapsed_sec = cfg$optimization_elapsed_sec,
        effective_threads = cfg$n.cores,
        implementation = cfg$optimizer
      ),
      list(
        measured_stage = "tsne_affinity_plus_optimization",
        elapsed_sec = wrapper_elapsed, effective_threads = cfg$n.cores,
        implementation = cfg$optimizer
      )
    )
    return(list(value = value, rows = rows))
  }
  if (identical(stage, "umap_graph")) {
    input <- subset_knn(pars$k_umap)
    started <- proc.time()[["elapsed"]]
    value <- fastEmbedR::prepare_umap_knn(
      input, backend = "cpu", n.cores = n.cores, graph_mode = "fuzzy"
    )
    elapsed <- proc.time()[["elapsed"]] - started
    return(list(value = value, rows = list(list(
      measured_stage = "umap_graph", elapsed_sec = elapsed,
      effective_threads = value$config$n.cores_effective %||% value$config$n_threads,
      implementation = value$config$graph_builder
    ))))
  }
  if (identical(stage, "umap_initialization")) {
    prepared <- umap_initialized$prepared
    prepared$initialization <- NULL
    prepared$initialization_parameters <- NULL
    started <- proc.time()[["elapsed"]]
    value <- fastEmbedR::umap_init(
      prepared, backend = "cpu", n.cores = n.cores,
      graph_mode = "fuzzy", seed = seed
    )
    elapsed <- proc.time()[["elapsed"]] - started
    return(list(value = value, rows = list(list(
      measured_stage = "umap_initialization", elapsed_sec = elapsed,
      effective_threads = value$parameters$n.cores_effective %||%
        value$parameters$n_threads,
      implementation = value$parameters$init_backend
    ))))
  }
  if (identical(stage, "umap_optimization")) {
    started <- proc.time()[["elapsed"]]
    value <- getFromNamespace("fast_knn_umap_prepared_core", "fastEmbedR")(
      umap_initialized$prepared, n_components = 2L, seed = seed,
      verbose = FALSE, backend = "cpu", n_threads = n.cores
    )
    elapsed <- proc.time()[["elapsed"]] - started
    cfg <- attr(value, "fastEmbedR_config")
    return(list(value = value, rows = list(list(
      measured_stage = "umap_optimization", elapsed_sec = elapsed,
      effective_threads = cfg$n.cores_effective %||% cfg$n_threads,
      implementation = cfg$optimizer
    ))))
  }
  if (identical(stage, "full_opentsne")) {
    started <- proc.time()[["elapsed"]]
    value <- fastEmbedR::opentsne(
      x, perplexity = pars$perplexity, affinity_support = "standard",
      backend = "cpu", n.cores = n.cores, seed = seed,
      early_exaggeration_iter = 250L, n_iter = 500L,
      auto_config = FALSE, record_costs = FALSE
    )
    elapsed <- proc.time()[["elapsed"]] - started
    return(list(value = value, rows = list(list(
      measured_stage = "full_opentsne", elapsed_sec = elapsed,
      effective_threads = value$parameters$n.cores %||% n.cores,
      implementation = value$parameters$optimizer
    ))))
  }
  started <- proc.time()[["elapsed"]]
  value <- fastEmbedR::umap(
    x, n_neighbors = pars$k_umap, graph_mode = "fuzzy",
    backend = "cpu", n.cores = n.cores, seed = seed
  )
  elapsed <- proc.time()[["elapsed"]] - started
  list(value = value, rows = list(list(
    measured_stage = "full_umap", elapsed_sec = elapsed,
    effective_threads = value$parameters$n.cores_effective %||%
      value$parameters$n_threads %||% NA_integer_,
    implementation = value$parameters$optimizer
  )))
}

`%||%` <- function(x, y) if (is.null(x) || length(x) == 0L) y else x

for (i in seq_len(warmups)) {
  invisible(run_once())
  gc()
}

records <- list()
status <- "success"
error_message <- NA_character_
for (replicate in seq_len(repeats)) {
  gc()
  result <- tryCatch(run_once(), error = identity)
  if (inherits(result, "error")) {
    status <- "failed"
    error_message <- conditionMessage(result)
    records[[length(records) + 1L]] <- data.frame(
      dataset = dataset, profile = loaded$profile, benchmark_scope = benchmark_scope,
      requested_stage = stage,
      measured_stage = stage, n = nrow(x), p = ncol(x),
      requested_threads = n.cores, effective_threads = NA_integer_,
      blas_threads_requested = blas_threads,
      blas_threads_observed = blas_threads_observed(),
      timing_replicate = replicate, seed = seed, warmups = warmups,
      elapsed_sec = NA_real_, peak_process_rss_kb = peak_rss_kb(),
      implementation = NA_character_, status = status,
      error = error_message, run_id = run_id,
      source = loaded$source, source_md5 = loaded$source_md5,
      stringsAsFactors = FALSE
    )
    break
  }
  for (row in result$rows) {
    records[[length(records) + 1L]] <- data.frame(
      dataset = dataset, profile = loaded$profile, benchmark_scope = benchmark_scope,
      requested_stage = stage,
      measured_stage = row$measured_stage, n = nrow(x), p = ncol(x),
      requested_threads = n.cores,
      effective_threads = as.integer(row$effective_threads),
      blas_threads_requested = blas_threads,
      blas_threads_observed = blas_threads_observed(),
      timing_replicate = replicate, seed = seed, warmups = warmups,
      elapsed_sec = as.numeric(row$elapsed_sec),
      peak_process_rss_kb = peak_rss_kb(),
      implementation = as.character(row$implementation %||% NA_character_),
      status = "success", error = NA_character_, run_id = run_id,
      source = loaded$source, source_md5 = loaded$source_md5,
      stringsAsFactors = FALSE
    )
  }
  rm(result)
}

output <- do.call(rbind, records)
name <- sprintf(
  "%s_%s_workers%02d_blas%02d_%s.csv",
  dataset, stage, n.cores, blas_threads, run_id
)
write.csv(output, file.path(out_dir, name), row.names = FALSE)
write_session_manifest(file.path(
  out_dir,
  sprintf("session_%s_workers%02d_blas%02d_%s.txt", dataset, n.cores, blas_threads, run_id)
))
print(output)
