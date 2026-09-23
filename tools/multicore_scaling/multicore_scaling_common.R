arg_value <- function(name, default = NULL) {
  args <- commandArgs(trailingOnly = TRUE)
  prefix <- paste0("--", name, "=")
  hit <- args[startsWith(args, prefix)]
  if (!length(hit)) return(default)
  sub(prefix, "", hit[[length(hit)]], fixed = TRUE)
}

as_int <- function(x, default = NA_integer_) {
  out <- suppressWarnings(as.integer(x))
  if (length(out) != 1L || is.na(out)) default else out
}

dir_create <- function(path) {
  if (!dir.exists(path) && !dir.create(path, recursive = TRUE, showWarnings = FALSE)) {
    stop("Cannot create directory: ", path, call. = FALSE)
  }
  normalizePath(path, mustWork = TRUE)
}

is_float32 <- function(x) inherits(x, "float32")

as_float32 <- function(x) {
  if (is_float32(x)) return(x)
  if (!requireNamespace("float", quietly = TRUE)) {
    stop("The float package is required for the release benchmark.", call. = FALSE)
  }
  float::fl(as.matrix(x))
}

extract_matrix <- function(env) {
  candidates <- c("dataset", "data", "x", "X", "u")
  for (name in candidates) {
    if (!exists(name, envir = env, inherits = FALSE)) next
    object <- get(name, envir = env, inherits = FALSE)
    if (is.list(object) && !is.null(object$data)) object <- object$data
    if (is.matrix(object) || is.data.frame(object) || is_float32(object)) return(object)
  }
  for (name in ls(env, all.names = TRUE)) {
    object <- get(name, envir = env, inherits = FALSE)
    if (is.list(object) && !is.null(object$data)) object <- object$data
    if (is.matrix(object) || is.data.frame(object) || is_float32(object)) return(object)
  }
  stop("No matrix-like dataset object was found.", call. = FALSE)
}

dataset_file <- function(data_root, dataset) {
  folder <- file.path(data_root, dataset)
  if (!dir.exists(folder)) stop("Dataset folder not found: ", folder, call. = FALSE)
  preferred <- c(
    file.path(folder, paste0(dataset, "_float32.RData")),
    file.path(folder, paste0(dataset, ".RData"))
  )
  hit <- preferred[file.exists(preferred)]
  if (length(hit)) return(hit[[1L]])
  files <- list.files(folder, pattern = "[.]RData$", full.names = TRUE)
  if (!length(files)) stop("No .RData file found in ", folder, call. = FALSE)
  float_hit <- files[grepl("float32", basename(files), ignore.case = TRUE)]
  if (length(float_hit)) float_hit[[1L]] else files[[1L]]
}

load_scaling_dataset <- function(dataset, data_root, seed = 4L) {
  if (identical(dataset, "simulated_1M_2D")) {
    set.seed(seed)
    x <- matrix(runif(2000000L), ncol = 2L)
    colnames(x) <- c("x", "y")
    return(list(
      data = as_float32(x), source = "deterministic_runif_1M_by_2",
      source_md5 = NA_character_, profile = "million_observation"
    ))
  }
  path <- dataset_file(data_root, dataset)
  env <- new.env(parent = emptyenv())
  load(path, envir = env)
  x <- extract_matrix(env)
  if (is.data.frame(x)) x <- as.matrix(x)
  list(
    data = as_float32(x), source = normalizePath(path),
    source_md5 = unname(tools::md5sum(path)),
    profile = switch(
      dataset,
      MetRef = "small_wide",
      MNIST = "medium_image",
      TabulaMuris = "medium_single_cell",
      "observed"
    )
  )
}

dataset_parameters <- function(dataset, n) {
  if (identical(dataset, "simulated_1M_2D")) {
    return(list(k_umap = 15L, perplexity = 15, k_tsne = 45L))
  }
  perplexity <- if (n < 3000L) 15 else 30
  k_umap <- if (n < 3000L) 15L else 30L
  list(
    k_umap = min(k_umap, n - 1L),
    perplexity = min(perplexity, floor((n - 1L) / 3L)),
    k_tsne = min(as.integer(ceiling(3 * perplexity)), n - 1L)
  )
}

peak_rss_kb <- function() {
  if (file.exists("/proc/self/status")) {
    lines <- readLines("/proc/self/status", warn = FALSE)
    hit <- grep("^VmHWM:", lines, value = TRUE)
    if (length(hit)) return(as.numeric(sub("^VmHWM:[[:space:]]*([0-9]+).*", "\\1", hit[[1L]])))
  }
  value <- suppressWarnings(as.numeric(system(
    sprintf("ps -o rss= -p %d", Sys.getpid()), intern = TRUE
  )))
  if (length(value) == 1L && is.finite(value)) value else NA_real_
}

blas_threads_observed <- function() {
  if (!requireNamespace("RhpcBLASctl", quietly = TRUE)) return(NA_integer_)
  suppressWarnings(tryCatch(
    as.integer(RhpcBLASctl::blas_get_num_procs()),
    error = function(e) NA_integer_
  ))
}

layout_matrix <- function(x) {
  if (is.list(x) && !is.null(x$layout)) x <- x$layout
  if (is_float32(x)) x <- as.matrix(x)
  as.matrix(x)
}

cache_paths <- function(cache_root, dataset) {
  folder <- file.path(cache_root, dataset)
  list(
    folder = folder,
    knn = file.path(folder, "knn_support.rds"),
    pca = file.path(folder, "opentsne_pca_init.rds"),
    umap = file.path(folder, "umap_prepared_init.rds"),
    manifest = file.path(folder, "cache_manifest.csv")
  )
}

write_session_manifest <- function(path) {
  lines <- c(
    paste0("timestamp_utc=", format(Sys.time(), tz = "UTC", usetz = TRUE)),
    paste0("r_version=", R.version.string),
    paste0("platform=", R.version$platform),
    paste0("fastEmbedR_version=", as.character(utils::packageVersion("fastEmbedR"))),
    paste0("blas=", extSoftVersion()[["BLAS"]]),
    paste0("OMP_NUM_THREADS=", Sys.getenv("OMP_NUM_THREADS", unset = "")),
    paste0("OPENBLAS_NUM_THREADS=", Sys.getenv("OPENBLAS_NUM_THREADS", unset = "")),
    paste0("MKL_NUM_THREADS=", Sys.getenv("MKL_NUM_THREADS", unset = "")),
    paste0("VECLIB_MAXIMUM_THREADS=", Sys.getenv("VECLIB_MAXIMUM_THREADS", unset = "")),
    paste0("RCPP_PARALLEL_NUM_THREADS=", Sys.getenv("RCPP_PARALLEL_NUM_THREADS", unset = "")),
    capture.output(sessionInfo())
  )
  writeLines(lines, path)
}
