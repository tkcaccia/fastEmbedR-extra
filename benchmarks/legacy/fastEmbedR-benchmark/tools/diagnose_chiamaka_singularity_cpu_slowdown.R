args <- commandArgs(trailingOnly = TRUE)
if (length(args) < 2L) {
  stop(
    "Usage: Rscript diagnose_chiamaka_singularity_cpu_slowdown.R ",
    "<output.csv> <environment-label> [seed]",
    call. = FALSE
  )
}

extra_lib <- Sys.getenv("FASTEMBEDR_TEST_LIB", unset = "")
if (nzchar(extra_lib)) {
  .libPaths(c(extra_lib, .libPaths()))
}

output_file <- normalizePath(args[[1L]], mustWork = FALSE)
environment_label <- args[[2L]]
seed <- if (length(args) >= 3L) as.integer(args[[3L]]) else 4L
threads <- 4L
k <- 30L
perplexity <- 30

data_root <- Sys.getenv(
  "FASTEMBEDR_COMPARE_DATA_ROOT",
  "/mnt/sata_ssd/fastEmbedR/Data/MNIST"
)
standard_file <- file.path(data_root, "MNIST.RData")
float_file <- file.path(data_root, "MNIST_float32.RData")

Sys.setenv(
  OMP_NUM_THREADS = threads,
  OPENBLAS_NUM_THREADS = 1L,
  MKL_NUM_THREADS = 1L,
  VECLIB_MAXIMUM_THREADS = 1L,
  RCPP_PARALLEL_NUM_THREADS = threads
)

suppressPackageStartupMessages({
  library(float)
  library(fastEmbedR)
})

load_dataset <- function(path) {
  env <- new.env(parent = emptyenv())
  loaded <- load(path, envir = env)
  if (!"dataset" %in% loaded || !is.list(env$dataset)) {
    stop("Expected a list named `dataset` in ", path, call. = FALSE)
  }
  env$dataset
}

standard <- load_dataset(standard_file)
float_data <- load_dataset(float_file)
x_ref <- standard$data
x_fast <- float_data$data
labels <- standard$labels
requested_methods <- strsplit(
  Sys.getenv(
    "FASTEMBEDR_COMPARE_METHODS",
    "opentsne,umap,rtsne,uwot"
  ),
  ",",
  fixed = TRUE
)[[1L]]
requested_methods <- trimws(requested_methods)

if (!identical(dim(x_ref), c(70000L, 784L))) {
  stop("The standard MNIST matrix is not 70000 x 784.", call. = FALSE)
}
if (!identical(dim(x_fast), c(70000L, 784L))) {
  stop("The float32 MNIST matrix is not 70000 x 784.", call. = FALSE)
}

scalar_or_na <- function(x) {
  if (is.null(x) || length(x) == 0L) {
    return(NA_real_)
  }
  as.numeric(x[[1L]])
}

text_or_na <- function(x) {
  if (is.null(x) || length(x) == 0L) {
    return(NA_character_)
  }
  as.character(x[[1L]])
}

fastembedr_row <- function(method, fit, elapsed) {
  metrics <- fit$metrics
  timings <- fit$timings
  parameters <- fit$parameters
  data.frame(
    environment = environment_label,
    method = method,
    seed = seed,
    threads = threads,
    n = nrow(fit$layout),
    p = ncol(x_ref),
    k = k,
    perplexity = perplexity,
    elapsed_sec = elapsed,
    reported_total_sec = scalar_or_na(metrics$elapsed),
    preprocess_sec = scalar_or_na(metrics$preprocess_elapsed),
    knn_sec = scalar_or_na(metrics$knn_elapsed),
    initialization_sec = scalar_or_na(metrics$initialization_elapsed),
    embedding_sec = scalar_or_na(metrics$embedding_elapsed),
    nn_engine = text_or_na(parameters$nn_engine),
    nn_backend = text_or_na(parameters$nn_backend),
    input_class = paste(class(x_fast), collapse = ","),
    package_version = as.character(packageVersion("fastEmbedR")),
    r_version = R.version.string,
    stringsAsFactors = FALSE
  )
}

reference_row <- function(method, elapsed, package_name) {
  data.frame(
    environment = environment_label,
    method = method,
    seed = seed,
    threads = threads,
    n = nrow(x_ref),
    p = ncol(x_ref),
    k = k,
    perplexity = perplexity,
    elapsed_sec = elapsed,
    reported_total_sec = NA_real_,
    preprocess_sec = NA_real_,
    knn_sec = NA_real_,
    initialization_sec = NA_real_,
    embedding_sec = NA_real_,
    nn_engine = "package_internal",
    nn_backend = "cpu",
    input_class = paste(class(x_ref), collapse = ","),
    package_version = as.character(packageVersion(package_name)),
    r_version = R.version.string,
    stringsAsFactors = FALSE
  )
}

run_timed <- function(expr) {
  gc()
  start <- proc.time()[["elapsed"]]
  value <- force(expr)
  elapsed <- proc.time()[["elapsed"]] - start
  list(value = value, elapsed = elapsed)
}

rows <- list()
layouts <- list()

if ("opentsne" %in% requested_methods) {
  set.seed(seed)
  timed <- run_timed(
    fastEmbedR::opentsne(
      x_fast,
      perplexity = perplexity,
      backend = "cpu",
      n_threads = threads,
      seed = seed
    )
  )
  rows[[length(rows) + 1L]] <- fastembedr_row(
    "fastEmbedR openTSNE CPU",
    timed$value,
    timed$elapsed
  )
  layouts$fastembedr_opentsne <- timed$value$layout
}

if ("umap" %in% requested_methods) {
  set.seed(seed)
  timed <- run_timed(
    fastEmbedR::umap(
      x_fast,
      n_neighbors = k,
      graph_mode = "fuzzy",
      backend = "cpu",
      n_threads = threads,
      seed = seed
    )
  )
  rows[[length(rows) + 1L]] <- fastembedr_row(
    "fastEmbedR UMAP CPU fuzzy",
    timed$value,
    timed$elapsed
  )
  layouts$fastembedr_umap <- timed$value$layout
}

if ("rtsne" %in% requested_methods && requireNamespace("Rtsne", quietly = TRUE)) {
  set.seed(seed)
  timed <- run_timed(
    Rtsne::Rtsne(
      x_ref,
      dims = 2L,
      perplexity = perplexity,
      check_duplicates = FALSE,
      pca = TRUE,
      num_threads = threads,
      verbose = FALSE
    )
  )
  rows[[length(rows) + 1L]] <- reference_row(
    "Rtsne full",
    timed$elapsed,
    "Rtsne"
  )
  layouts$rtsne <- timed$value$Y
}

if ("uwot" %in% requested_methods && requireNamespace("uwot", quietly = TRUE)) {
  set.seed(seed)
  timed <- run_timed(
    uwot::umap(
      x_ref,
      n_neighbors = k,
      fast_sgd = TRUE,
      n_threads = threads,
      n_sgd_threads = threads,
      init = "spectral",
      verbose = FALSE,
      ret_model = FALSE
    )
  )
  rows[[length(rows) + 1L]] <- reference_row(
    "uwot UMAP fast_sgd full",
    timed$elapsed,
    "uwot"
  )
  layouts$uwot <- timed$value
}

results <- do.call(rbind, rows)
dir.create(dirname(output_file), recursive = TRUE, showWarnings = FALSE)
write.csv(results, output_file, row.names = FALSE)
saveRDS(
  list(
    results = results,
    layouts = layouts,
    labels = labels,
    session_info = utils::sessionInfo(),
    environment = Sys.getenv(),
    command = commandArgs()
  ),
  sub("\\.csv$", "_details.rds", output_file)
)

print(results)
