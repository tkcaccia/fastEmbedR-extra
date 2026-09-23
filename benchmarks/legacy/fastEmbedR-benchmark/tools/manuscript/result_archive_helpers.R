archive_path_parts <- function(path, results_root) {
  root <- normalizePath(results_root, mustWork = TRUE)
  full <- normalizePath(path, mustWork = TRUE)
  relative <- substring(full, nchar(root) + 2L)
  strsplit(relative, "/", fixed = TRUE)[[1L]]
}

archive_stat_summary <- function(values) {
  values <- suppressWarnings(as.numeric(values))
  values <- values[is.finite(values)]
  if (!length(values)) {
    return(c(
      median = NA_real_, q1 = NA_real_, q3 = NA_real_, iqr = NA_real_,
      sd = NA_real_, min = NA_real_, max = NA_real_
    ))
  }
  q1 <- as.numeric(stats::quantile(values, 0.25, names = FALSE))
  q3 <- as.numeric(stats::quantile(values, 0.75, names = FALSE))
  c(
    median = stats::median(values),
    q1 = q1,
    q3 = q3,
    iqr = q3 - q1,
    sd = if (length(values) > 1L) stats::sd(values) else NA_real_,
    min = min(values),
    max = max(values)
  )
}

archive_summarize_runs <- function(runs, expected_seeds = 3L) {
  if (is.null(runs) || !nrow(runs)) return(data.frame())

  group_columns <- c(
    "dataset", "method", "family", "backend", "timing_scope",
    "requested_threads", "effective_threads", "n", "p", "k", "perplexity",
    "input_type", "landmark_fraction"
  )
  metric_columns <- c(
    "total_runtime_sec", "preprocess_sec", "knn_sec", "init_sec",
    "graph_or_affinity_sec", "embedding_sec", "peak_ram_gb",
    "peak_gpu_mb", "peak_gpu_delta_mb", "trustworthiness",
    "knn_preservation_15", "knn_preservation_30", "knn_preservation_50",
    "silhouette", "label_knn_accuracy", "tsne_kl",
    "n_landmarks", "reference_embedding_sec", "landmark_projection_knn_sec",
    "landmark_refinement_sec", "landmark_transform_sec",
    "kodama_core_sec", "kodama_visualization_sec",
    "kodama_core_peak_ram_gb", "kodama_visualization_peak_ram_gb",
    "kodama_core_peak_gpu_delta_mb",
    "kodama_visualization_peak_gpu_delta_mb"
  )

  for (name in setdiff(group_columns, names(runs))) runs[[name]] <- NA
  for (name in setdiff(metric_columns, names(runs))) runs[[name]] <- NA_real_
  if (!"status" %in% names(runs)) runs$status <- "failed"

  key_parts <- lapply(runs[group_columns], function(value) {
    value <- as.character(value)
    value[is.na(value)] <- "<NA>"
    value
  })
  keys <- do.call(paste, c(key_parts, sep = "\r"))
  pieces <- split(runs, keys)

  rows <- lapply(pieces, function(piece) {
    base <- piece[1L, group_columns, drop = FALSE]
    base$n_runs <- nrow(piece)
    base$n_success <- sum(piece$status == "success")
    all_timeout <- nrow(piece) > 0L && all(piece$status == "timeout")
    base$status <- if (all_timeout) {
      "timeout"
    } else if (base$n_success >= expected_seeds) {
      "success"
    } else if (base$n_success > 0L) {
      "partial"
    } else {
      "failed"
    }
    for (metric in metric_columns) {
      values <- piece[[metric]]
      statistics <- archive_stat_summary(
        values[piece$status == "success"]
      )
      for (statistic in names(statistics)) {
        base[[paste0(metric, "_", statistic)]] <- statistics[[statistic]]
      }
    }
    base
  })
  out <- do.call(rbind, rows)
  rownames(out) <- NULL
  out[order(out$dataset, out$family, out$method, out$requested_threads), ,
      drop = FALSE]
}

archive_latest_run_dirs <- function(results_root, suites = NULL,
                                    profiles = NULL,
                                    exclude_kodama = TRUE) {
  candidates <- list.files(
    results_root,
    pattern = paste0(
      "^(benchmark_summary_median_variability|benchmark_runs|",
      "benchmark_runs_checkpoint)\\.csv$"
    ),
    recursive = TRUE,
    full.names = TRUE
  )
  if (exclude_kodama) {
    candidates <- candidates[
      !grepl("/kodama/", candidates, fixed = TRUE)
    ]
  }
  if (!length(candidates)) return(character())

  run_dirs <- unique(dirname(candidates))
  metadata <- lapply(run_dirs, function(run_dir) {
    parts <- archive_path_parts(run_dir, results_root)
    if (length(parts) < 4L) return(NULL)
    data.frame(
      run_dir = run_dir,
      dataset = parts[[1L]],
      suite = parts[[2L]],
      profile = parts[[3L]],
      run_id = parts[[4L]],
      key = paste(parts[c(1L, 2L, 3L)], collapse = "\r"),
      stringsAsFactors = FALSE
    )
  })
  metadata <- Filter(Negate(is.null), metadata)
  if (!length(metadata)) return(character())
  metadata <- do.call(rbind, metadata)
  if (!is.null(suites)) {
    metadata <- metadata[metadata$suite %in% suites, , drop = FALSE]
  }
  if (!is.null(profiles)) {
    metadata <- metadata[metadata$profile %in% profiles, , drop = FALSE]
  }
  metadata <- metadata[
    order(metadata$key, metadata$run_id),
    ,
    drop = FALSE
  ]
  metadata$run_dir[!duplicated(metadata$key, fromLast = TRUE)]
}

archive_collect_latest_summaries <- function(results_root, suites = NULL,
                                             profiles = NULL,
                                             expected_seeds = 3L,
                                             exclude_kodama = TRUE) {
  run_dirs <- archive_latest_run_dirs(
    results_root,
    suites = suites,
    profiles = profiles,
    exclude_kodama = exclude_kodama
  )
  rows <- lapply(run_dirs, function(run_dir) {
    parts <- archive_path_parts(run_dir, results_root)
    summary_path <- file.path(
      run_dir, "benchmark_summary_median_variability.csv"
    )
    final_runs_path <- file.path(run_dir, "benchmark_runs.csv")
    checkpoint_path <- file.path(run_dir, "benchmark_runs_checkpoint.csv")

    if (file.exists(summary_path)) {
      value <- read.csv(
        summary_path, stringsAsFactors = FALSE, check.names = FALSE
      )
      source_file <- summary_path
      archive_complete <- TRUE
    } else {
      source_file <- if (file.exists(final_runs_path)) {
        final_runs_path
      } else if (file.exists(checkpoint_path)) {
        checkpoint_path
      } else {
        NA_character_
      }
      if (is.na(source_file)) return(NULL)
      runs <- read.csv(
        source_file, stringsAsFactors = FALSE, check.names = FALSE
      )
      value <- archive_summarize_runs(runs, expected_seeds = expected_seeds)
      archive_complete <- FALSE
    }
    if (!nrow(value)) return(NULL)
    value$suite <- parts[[2L]]
    value$profile <- parts[[3L]]
    value$run_dir <- run_dir
    value$source_file <- source_file
    value$archive_complete <- archive_complete
    value
  })
  rows <- Filter(Negate(is.null), rows)
  if (!length(rows)) return(data.frame())

  all_names <- unique(unlist(lapply(rows, names), use.names = FALSE))
  rows <- lapply(rows, function(value) {
    for (name in setdiff(all_names, names(value))) value[[name]] <- NA
    value[all_names]
  })
  out <- do.call(rbind, rows)
  rownames(out) <- NULL
  out
}

archive_latest_run_files <- function(results_root, suites = NULL,
                                     profiles = NULL) {
  run_dirs <- archive_latest_run_dirs(
    results_root,
    suites = suites,
    profiles = profiles
  )
  vapply(run_dirs, function(run_dir) {
    final_path <- file.path(run_dir, "benchmark_runs.csv")
    checkpoint_path <- file.path(run_dir, "benchmark_runs_checkpoint.csv")
    if (file.exists(final_path)) final_path else checkpoint_path
  }, character(1L))
}
