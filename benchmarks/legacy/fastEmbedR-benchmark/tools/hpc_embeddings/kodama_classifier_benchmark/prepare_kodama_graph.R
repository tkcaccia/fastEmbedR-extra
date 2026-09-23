#!/usr/bin/env Rscript

script_argument <- grep("^--file=", commandArgs(FALSE), value = TRUE)
script_path <- normalizePath(
  sub("^--file=", "", script_argument[[1L]]),
  mustWork = TRUE
)
source(file.path(dirname(script_path), "kodama_benchmark_common.R"))

args <- parse_cli(commandArgs(trailingOnly = TRUE))
dataset <- args$dataset %||% stop("--dataset is required.")
backend <- args$backend %||% stop("--backend is required.")
n.cores <- as_int(args$n_cores, 4L)
graph_neighbors <- as_int(args$graph_neighbors, 100L)
seed <- as_int(args$seed, 4L)
data_root <- args$data_root %||% "/scratch/firenze/NN/Data"
graph_file <- args$graph_file %||% stop("--graph-file is required.")
force <- as_flag(args$force, FALSE)

if (!backend %in% c("cpu", "cuda")) {
  stop("--backend must be cpu or cuda.", call. = FALSE)
}
dir.create(dirname(graph_file), recursive = TRUE, showWarnings = FALSE)
status_file <- file.path(dirname(graph_file), "graph_precompute_status.csv")

write_status <- function(stage, status = "running", details = NA_character_) {
  row <- data.frame(
    timestamp = format(Sys.time(), "%Y-%m-%dT%H:%M:%S%z"),
    pid = Sys.getpid(),
    dataset = dataset,
    backend = backend,
    n.cores = n.cores,
    stage = stage,
    status = status,
    details = details,
    stringsAsFactors = FALSE
  )
  write.table(
    row, status_file, sep = ",", row.names = FALSE,
    col.names = !file.exists(status_file), append = file.exists(status_file),
    quote = TRUE
  )
  cat(
    sprintf(
      "[%s] graph stage=%s status=%s%s\n",
      row$timestamp, stage, status,
      if (is.na(details) || !nzchar(details)) "" else paste0(" details=", details)
    )
  )
  flush.console()
}

dataset_data <- load_benchmark_dataset(dataset, data_root)
write_status(
  "dataset_loaded",
  "success",
  sprintf("n=%d p=%d source=%s", nrow(dataset_data$data),
          ncol(dataset_data$data), dataset_data$path)
)

if (file.exists(graph_file) && !force) {
  bundle <- load_kodama_graph_bundle(
    graph_file, dataset_data, dataset, backend, graph_neighbors
  )
  write_status(
    "graph_reused",
    "success",
    sprintf(
      "file=%s graph_build_elapsed_sec=%.6f",
      graph_file, as.numeric(bundle$graph_build_elapsed_sec)
    )
  )
  quit(save = "no", status = 0L)
}

if (!requireNamespace("kodamaR", quietly = TRUE)) {
  stop("kodamaR is not installed.", call. = FALSE)
}
write_status(
  "graph_build_started",
  details = sprintf("k=%d seed=%d", graph_neighbors, seed)
)
graph_fun <- getExportedValue("kodamaR", "KODAMA.graph")
graph_time <- system.time({
  graph <- call_supported(
    graph_fun,
    list(
      data = dataset_data$data,
      k = graph_neighbors,
      metric = "euclidean",
      backend = backend,
      n.cores = n.cores,
      gpu.device = 0L,
      seed = seed
    )
  )
})[["elapsed"]]

if (!inherits(graph, "kodama_graph")) {
  stop("KODAMA.graph did not return a kodama_graph object.", call. = FALSE)
}
if (!identical(as.character(graph$backend), backend)) {
  stop(
    "KODAMA.graph backend mismatch: requested ", backend,
    " but received ", graph$backend, ".", call. = FALSE
  )
}
if (!identical(as.integer(graph$graph_builds), 1L)) {
  stop(
    "KODAMA.graph must report exactly one graph build; received ",
    graph$graph_builds, ".", call. = FALSE
  )
}

bundle <- list(
  schema_version = 1L,
  dataset = dataset,
  source = dataset_file_identity(dataset_data),
  backend = backend,
  n.cores = n.cores,
  graph_neighbors = graph_neighbors,
  metric = "euclidean",
  seed = seed,
  graph = graph,
  graph_build_elapsed_sec = unname(graph_time),
  graph_runtime_sec = as_num(graph$runtime_seconds, NA_real_),
  graph_storage_bytes = as_num(graph$graph_storage_bytes, NA_real_),
  created_at = format(Sys.time(), "%Y-%m-%dT%H:%M:%S%z")
)
temporary <- tempfile(
  pattern = paste0(".", basename(graph_file), "."),
  tmpdir = dirname(graph_file),
  fileext = ".tmp"
)
on.exit(unlink(temporary), add = TRUE)
saveRDS(bundle, temporary, compress = FALSE)
if (!file.rename(temporary, graph_file)) {
  stop("Could not atomically install graph checkpoint: ", graph_file)
}

reloaded <- load_kodama_graph_bundle(
  graph_file, dataset_data, dataset, backend, graph_neighbors
)
manifest <- data.frame(
  schema_version = reloaded$schema_version,
  dataset = dataset,
  backend = backend,
  n.cores = n.cores,
  n = reloaded$source$n,
  p = reloaded$source$p,
  graph_neighbors = graph_neighbors,
  metric = reloaded$metric,
  seed = seed,
  graph_build_elapsed_sec = reloaded$graph_build_elapsed_sec,
  graph_runtime_sec = reloaded$graph_runtime_sec,
  graph_storage_bytes = reloaded$graph_storage_bytes,
  graph_file = normalizePath(graph_file, mustWork = TRUE),
  graph_file_bytes = file.info(graph_file)$size,
  graph_md5 = unname(tools::md5sum(graph_file)),
  source_file = reloaded$source$path,
  source_bytes = reloaded$source$size,
  source_mtime = reloaded$source$mtime,
  created_at = reloaded$created_at,
  stringsAsFactors = FALSE
)
atomic_write_csv(
  manifest,
  file.path(dirname(graph_file), "graph_precompute_manifest.csv")
)
write_status(
  "graph_checkpoint_validated",
  "success",
  sprintf(
    "file=%s elapsed_sec=%.6f md5=%s",
    graph_file, unname(graph_time), manifest$graph_md5
  )
)
