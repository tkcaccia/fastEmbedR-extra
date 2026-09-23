#!/usr/bin/env Rscript

# Matched CPU PCA benchmark for fastEmbedR and irlba.
#
# Both methods receive the same ordinary double R matrix, centering/scaling
# settings, requested rank, seed, and CPU-thread limit. Run-level timings and
# numerical agreement are retained so that medians are not mistaken for single
# measurements.

parse_args <- function(x) {
  out <- list(
    data_root = "/Users/stefano/Documents/fastEmbedR/Data",
    output_dir = file.path("results", paste0(
      "pca_cpu_vs_irlba_", format(Sys.time(), "%Y%m%d_%H%M%S")
    )),
    datasets = paste(
      c(
        "MetRef", "COIL20", "USPS", "Macosko2015_retina",
        "TabulaMuris", "FashionMNIST", "MNIST", "flow18"
      ),
      collapse = ","
    ),
    ranks = "2,50",
    cores = "1,4",
    repeats = 3L,
    seed = 4L,
    scale = FALSE
  )
  for (arg in x) {
    if (!startsWith(arg, "--") || !grepl("=", arg, fixed = TRUE)) next
    pair <- strsplit(sub("^--", "", arg), "=", fixed = TRUE)[[1L]]
    key <- gsub("-", "_", pair[[1L]], fixed = TRUE)
    value <- paste(pair[-1L], collapse = "=")
    out[[key]] <- value
  }
  out$repeats <- as.integer(out$repeats)
  out$seed <- as.integer(out$seed)
  out$scale <- tolower(as.character(out$scale)) %in% c("true", "t", "1", "yes")
  out
}

split_values <- function(x) {
  trimws(strsplit(as.character(x), ",", fixed = TRUE)[[1L]])
}

dataset_paths <- function(root) {
  c(
    MetRef = file.path(root, "MetRef", "MetRef.RData"),
    COIL20 = file.path(root, "COIL20", "COIL20.RData"),
    USPS = file.path(root, "USPS", "USPS.RData"),
    Macosko2015_retina = file.path(
      root, "Macosko2015_retina", "Macosko2015_retina.RData"
    ),
    TabulaMuris = file.path(root, "TabulaMuris", "TabulaMuris.RData"),
    FashionMNIST = file.path(root, "FashionMNIST", "FashionMNIST.RData"),
    MNIST = file.path(root, "MNIST", "MNIST.RData"),
    flow18 = file.path(root, "flow18", "flow18.RData"),
    mass41 = file.path(root, "mass41", "mass41.RData"),
    imagenet = file.path(root, "imagenet", "imagenet.RData"),
    FlowRepository_FR_FCM_ZYRM = file.path(
      root,
      "FlowRepository_FR-FCM-ZYRM_files",
      "van_unen_FR-FCM-ZYRM.RData"
    )
  )
}

load_dataset_matrix <- function(path) {
  env <- new.env(parent = emptyenv())
  load(path, envir = env)
  objects <- as.list(env)
  object <- if ("dataset" %in% names(objects)) {
    objects$dataset
  } else if (length(objects) == 1L) {
    objects[[1L]]
  } else {
    objects
  }
  x <- if (is.list(object) && !is.null(object$data)) {
    object$data
  } else if (is.matrix(object) || is.data.frame(object)) {
    object
  } else {
    stop("No data matrix was found in ", path, call. = FALSE)
  }
  x <- as.matrix(x)
  storage.mode(x) <- "double"
  x
}

with_thread_limit <- function(cores, code) {
  variables <- c(
    "OMP_NUM_THREADS", "OPENBLAS_NUM_THREADS", "MKL_NUM_THREADS",
    "VECLIB_MAXIMUM_THREADS", "BLIS_NUM_THREADS",
    "RCPP_PARALLEL_NUM_THREADS"
  )
  old <- Sys.getenv(variables, unset = NA_character_)
  on.exit({
    for (i in seq_along(variables)) {
      if (is.na(old[[i]])) {
        Sys.unsetenv(variables[[i]])
      } else {
        do.call(Sys.setenv, setNames(list(old[[i]]), variables[[i]]))
      }
    }
  }, add = TRUE)
  do.call(
    Sys.setenv,
    setNames(rep(list(as.character(cores)), length(variables)), variables)
  )
  if (requireNamespace("RhpcBLASctl", quietly = TRUE)) {
    old_blas <- tryCatch(RhpcBLASctl::blas_get_num_procs(), error = function(e) NA)
    old_omp <- tryCatch(RhpcBLASctl::omp_get_max_threads(), error = function(e) NA)
    on.exit({
      if (!is.na(old_blas)) try(RhpcBLASctl::blas_set_num_threads(old_blas), silent = TRUE)
      if (!is.na(old_omp)) try(RhpcBLASctl::omp_set_num_threads(old_omp), silent = TRUE)
    }, add = TRUE)
    try(RhpcBLASctl::blas_set_num_threads(cores), silent = TRUE)
    try(RhpcBLASctl::omp_set_num_threads(cores), silent = TRUE)
  }
  force(code)
}

procrustes_correlation <- function(reference, candidate) {
  reference <- scale(reference, center = TRUE, scale = FALSE)
  candidate <- scale(candidate, center = TRUE, scale = FALSE)
  numerator <- sum(svd(crossprod(reference, candidate), nu = 0L, nv = 0L)$d)
  numerator / sqrt(sum(reference * reference) * sum(candidate * candidate))
}

principal_angle_cosines <- function(reference_loadings, candidate_loadings) {
  svd(crossprod(reference_loadings, candidate_loadings),
    nu = 0L, nv = 0L
  )$d
}

args <- parse_args(commandArgs(trailingOnly = TRUE))
if (!requireNamespace("fastEmbedR", quietly = TRUE)) {
  stop("Install fastEmbedR before running this benchmark.", call. = FALSE)
}
if (!requireNamespace("irlba", quietly = TRUE)) {
  stop("Install irlba before running this benchmark.", call. = FALSE)
}

datasets <- split_values(args$datasets)
ranks <- as.integer(split_values(args$ranks))
cores_grid <- as.integer(split_values(args$cores))
stopifnot(
  args$repeats >= 1L,
  all(ranks >= 1L),
  all(cores_grid >= 1L)
)
dir.create(args$output_dir, recursive = TRUE, showWarnings = FALSE)

paths <- dataset_paths(args$data_root)
unknown <- setdiff(datasets, names(paths))
if (length(unknown)) {
  stop("Unknown dataset(s): ", paste(unknown, collapse = ", "), call. = FALSE)
}

run_rows <- list()
summary_rows <- list()
row_id <- 0L

for (dataset_name in datasets) {
  path <- unname(paths[[dataset_name]])
  if (!file.exists(path)) {
    warning("Skipping missing dataset: ", path)
    next
  }
  message("Loading ", dataset_name)
  x <- load_dataset_matrix(path)
  n <- nrow(x)
  p <- ncol(x)

  for (rank in ranks) {
    if (rank >= min(n, p)) {
      message("Skipping ", dataset_name, " rank ", rank, ": rank is not truncated")
      next
    }
    for (cores in cores_grid) {
      fits <- list()
      timings <- list(fastEmbedR = numeric(args$repeats), irlba = numeric(args$repeats))
      for (repeat_id in seq_len(args$repeats)) {
        order <- if ((repeat_id + cores + rank) %% 2L) {
          c("fastEmbedR", "irlba")
        } else {
          c("irlba", "fastEmbedR")
        }
        for (method in order) {
          gc()
          set.seed(args$seed)
          elapsed <- with_thread_limit(cores, system.time({
            fit <- if (identical(method, "fastEmbedR")) {
              fastEmbedR::pca(
                x,
                ncomp = rank,
                center = TRUE,
                scale = args$scale,
                backend = "cpu",
                n.cores = cores,
                seed = args$seed
              )
            } else {
              irlba::prcomp_irlba(
                x,
                n = rank,
                center = TRUE,
                scale. = args$scale
              )
            }
          })[["elapsed"]])
          timings[[method]][[repeat_id]] <- elapsed
          fits[[method]] <- fit
          row_id <- row_id + 1L
          run_rows[[row_id]] <- data.frame(
            dataset = dataset_name,
            n = n,
            p = p,
            rank = rank,
            cores = cores,
            replicate = repeat_id,
            method = method,
            elapsed_sec = elapsed,
            input_precision = "R double",
            center = TRUE,
            scale = args$scale,
            seed = args$seed,
            stringsAsFactors = FALSE
          )
        }
      }

      irlba_scores <- fits$irlba$x
      fast_scores <- as.matrix(fits$fastEmbedR$scores)
      angle_cosines <- principal_angle_cosines(
        fits$irlba$rotation,
        as.matrix(fits$fastEmbedR$loadings)
      )
      summary_rows[[length(summary_rows) + 1L]] <- data.frame(
        dataset = dataset_name,
        n = n,
        p = p,
        rank = rank,
        cores = cores,
        repeats = args$repeats,
        irlba_median_sec = median(timings$irlba),
        fastembedr_median_sec = median(timings$fastEmbedR),
        speedup_vs_irlba = median(timings$irlba) / median(timings$fastEmbedR),
        procrustes_correlation = procrustes_correlation(
          irlba_scores, fast_scores
        ),
        median_principal_angle_cosine = median(angle_cosines),
        minimum_principal_angle_cosine = min(angle_cosines),
        captured_variance_ratio = sum(fast_scores * fast_scores) /
          sum(irlba_scores * irlba_scores),
        fastembedr_engine = fits$fastEmbedR$engine,
        fastembedr_precision = fits$fastEmbedR$precision,
        input_precision = "R double",
        center = TRUE,
        scale = args$scale,
        seed = args$seed,
        stringsAsFactors = FALSE
      )
      write.csv(
        do.call(rbind, run_rows),
        file.path(args$output_dir, "pca_cpu_vs_irlba_runs.csv"),
        row.names = FALSE
      )
      write.csv(
        do.call(rbind, summary_rows),
        file.path(args$output_dir, "pca_cpu_vs_irlba_summary.csv"),
        row.names = FALSE
      )
    }
  }
  rm(x)
  gc()
}

summary <- do.call(rbind, summary_rows)
print(summary, row.names = FALSE)
writeLines(capture.output(sessionInfo()), file.path(args$output_dir, "session_info.txt"))
