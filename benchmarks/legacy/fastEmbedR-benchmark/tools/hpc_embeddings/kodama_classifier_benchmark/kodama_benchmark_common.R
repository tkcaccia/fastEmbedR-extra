# Shared implementation for the classifier-specific KODAMA HPC benchmarks.

`%||%` <- function(x, y) {
  if (is.null(x) || !length(x)) y else x
}

parse_cli <- function(values) {
  out <- list()
  for (value in values) {
    if (!startsWith(value, "--")) next
    parts <- strsplit(sub("^--", "", value), "=", fixed = TRUE)[[1L]]
    key <- gsub("-", "_", parts[[1L]], fixed = TRUE)
    out[[key]] <- if (length(parts) == 1L) TRUE else {
      paste(parts[-1L], collapse = "=")
    }
  }
  out
}

as_flag <- function(x, default = FALSE) {
  if (is.null(x)) return(default)
  tolower(as.character(x)) %in% c("true", "1", "yes", "y")
}

as_int <- function(x, default) {
  value <- suppressWarnings(as.integer(x %||% default))
  if (!length(value) || is.na(value)) as.integer(default) else value
}

as_num <- function(x, default) {
  value <- suppressWarnings(as.numeric(x %||% default))
  if (!length(value) || !is.finite(value)) as.numeric(default) else value
}

safe_name <- function(x) gsub("[^A-Za-z0-9_.-]+", "_", x)

dataset_alias <- function(x) {
  if (identical(x, "FlowRepository_FR-FCM-ZYRM_files")) {
    "FlowRepository_FR-FCM-ZYRM_files"
  } else {
    x
  }
}

dataset_relative_path <- function(dataset) {
  paths <- c(
    COIL20 = "COIL20/COIL20.RData",
    USPS = "USPS/USPS.RData",
    FashionMNIST = "FashionMNIST/FashionMNIST.RData",
    `FlowRepository_FR-FCM-ZYRM_files` =
      "FlowRepository_FR-FCM-ZYRM_files/van_unen_FR-FCM-ZYRM.RData",
    flow18 = "flow18/flow18.RData",
    MNIST = "MNIST/MNIST.RData",
    imagenet = "imagenet/imagenet.RData",
    MetRef = "MetRef/MetRef.RData",
    mass41 = "mass41/mass41.RData",
    TabulaMuris = "TabulaMuris/TabulaMuris.RData",
    Macosko2015_retina =
      "Macosko2015_retina/Macosko2015_retina.RData"
  )
  value <- unname(paths[[dataset]])
  if (is.null(value)) {
    stop("Unknown dataset: ", dataset, call. = FALSE)
  }
  value
}

load_benchmark_dataset <- function(dataset, data_root) {
  path <- file.path(data_root, dataset_relative_path(dataset))
  if (!file.exists(path)) {
    stop("Dataset file not found: ", path, call. = FALSE)
  }
  environment <- new.env(parent = emptyenv())
  loaded <- load(path, envir = environment)
  candidate <- if ("dataset" %in% loaded) {
    environment$dataset
  } else {
    objects <- mget(loaded, envir = environment, inherits = FALSE)
    matches <- objects[vapply(
      objects,
      function(x) is.list(x) && !is.null(x$data),
      logical(1)
    )]
    if (length(matches)) matches[[1L]] else NULL
  }
  if (is.null(candidate) || is.null(candidate$data)) {
    stop("No list containing $data was found in ", path, call. = FALSE)
  }
  x <- candidate$data
  if (inherits(x, "float32")) {
    x <- as.matrix(x)
  } else if (is.data.frame(x)) {
    x <- data.matrix(x)
  } else {
    x <- as.matrix(x)
  }
  storage.mode(x) <- "double"
  if (!is.numeric(x) || length(dim(x)) != 2L || nrow(x) < 3L ||
      ncol(x) < 1L) {
    stop("Dataset $data must be a numeric matrix with at least three rows.")
  }
  if (anyNA(x) || any(!is.finite(x))) {
    stop("Dataset contains missing or non-finite values: ", dataset)
  }
  labels <- candidate$labels %||% candidate$label %||% NULL
  if (!is.null(labels)) {
    labels <- as.factor(labels)
    if (length(labels) != nrow(x)) {
      stop("Label length does not match the number of data rows.")
    }
  }
  list(
    data = x,
    labels = labels,
    metadata = candidate$metadata %||% list(),
    path = normalizePath(path, mustWork = TRUE)
  )
}

dataset_file_identity <- function(dataset_data) {
  info <- file.info(dataset_data$path)
  list(
    path = normalizePath(dataset_data$path, mustWork = TRUE),
    size = unname(as.numeric(info$size)),
    mtime = format(info$mtime, "%Y-%m-%dT%H:%M:%S%z"),
    n = nrow(dataset_data$data),
    p = ncol(dataset_data$data)
  )
}

validate_kodama_graph_bundle <- function(bundle, dataset_data, dataset,
                                         backend, graph_neighbors) {
  required <- c(
    "schema_version", "dataset", "source", "backend", "graph_neighbors",
    "graph", "graph_build_elapsed_sec", "created_at"
  )
  missing <- setdiff(required, names(bundle))
  if (length(missing)) {
    stop(
      "Shared KODAMA graph checkpoint is missing: ",
      paste(missing, collapse = ", "), call. = FALSE
    )
  }
  expected <- dataset_file_identity(dataset_data)
  observed <- bundle$source
  checks <- c(
    identical(as.integer(bundle$schema_version), 1L),
    identical(as.character(bundle$dataset), as.character(dataset)),
    identical(as.character(bundle$backend), as.character(backend)),
    identical(as.integer(bundle$graph_neighbors), as.integer(graph_neighbors)),
    identical(as.character(observed$path), as.character(expected$path)),
    identical(as.numeric(observed$size), as.numeric(expected$size)),
    identical(as.character(observed$mtime), as.character(expected$mtime)),
    identical(as.integer(observed$n), as.integer(expected$n)),
    identical(as.integer(observed$p), as.integer(expected$p))
  )
  if (!all(checks)) {
    stop(
      "Shared KODAMA graph checkpoint does not match the requested ",
      "dataset/backend configuration. Re-run the graph preparation job.",
      call. = FALSE
    )
  }
  graph <- bundle$graph
  if (!inherits(graph, "kodama_graph") ||
      is.null(graph$indices) || is.null(graph$distances) ||
      nrow(graph$indices) != expected$n ||
      ncol(graph$indices) < graph_neighbors ||
      !identical(dim(graph$indices), dim(graph$distances))) {
    stop("Shared KODAMA graph checkpoint contains an invalid graph.")
  }
  graph_backend <- as.character(graph$backend %||% NA_character_)
  if (!identical(graph_backend, backend)) {
    stop(
      "Shared graph backend mismatch: requested ", backend,
      " but checkpoint contains ", graph_backend, ".", call. = FALSE
    )
  }
  invisible(bundle)
}

load_kodama_graph_bundle <- function(path, dataset_data, dataset, backend,
                                     graph_neighbors) {
  if (!file.exists(path)) {
    stop(
      "Required shared KODAMA graph checkpoint is absent: ", path,
      ". Submit the graph preparation job first.", call. = FALSE
    )
  }
  bundle <- readRDS(path)
  validate_kodama_graph_bundle(
    bundle, dataset_data, dataset, backend, graph_neighbors
  )
  bundle
}

call_supported <- function(fun, arguments) {
  formal_names <- names(formals(fun))
  if (!"..." %in% formal_names) {
    arguments <- arguments[names(arguments) %in% formal_names]
  }
  do.call(fun, arguments)
}

extract_layout <- function(x) {
  if (is.matrix(x) || is.data.frame(x)) {
    out <- as.matrix(x)
  } else if (is.list(x)) {
    fields <- c("layout", "embedding", "Y", "y", "coordinates")
    hit <- fields[vapply(fields, function(name) !is.null(x[[name]]), logical(1))]
    if (!length(hit)) {
      stop("KODAMA visualization did not return a recognizable layout.")
    }
    out <- as.matrix(x[[hit[[1L]]]])
  } else {
    stop("KODAMA visualization did not return a matrix-like object.")
  }
  storage.mode(out) <- "double"
  if (ncol(out) < 2L || anyNA(out) || any(!is.finite(out))) {
    stop("KODAMA visualization returned an invalid layout.")
  }
  out[, 1:2, drop = FALSE]
}

effective_landmark_count <- function(requested, n) {
  if (requested >= n) requested <- ceiling(0.75 * n)
  as.integer(max(2L, min(requested, n - 1L)))
}

resolve_landmarks <- function(n, mode, fraction, default_landmarks,
                              large_threshold) {
  if (identical(mode, "default")) {
    requested <- as.integer(default_landmarks)
    requested_fraction <- NA_real_
  } else if (identical(mode, "fraction")) {
    if (n <= large_threshold) {
      stop(
        "Fractional KODAMA landmark runs are limited to datasets with more than ",
        large_threshold, " samples.", call. = FALSE
      )
    }
    if (!is.finite(fraction) || fraction <= 0 || fraction >= 1) {
      stop("Landmark fraction must lie strictly between zero and one.")
    }
    requested <- as.integer(round(n * fraction))
    requested <- max(2L, min(requested, n - 1L))
    requested_fraction <- fraction
  } else {
    stop("landmark-mode must be default or fraction.", call. = FALSE)
  }
  effective <- effective_landmark_count(requested, n)
  list(
    mode = mode,
    requested = requested,
    effective = effective,
    requested_fraction = requested_fraction,
    effective_fraction = effective / n
  )
}

adjusted_rand_index <- function(truth, predicted) {
  if (is.null(truth) || length(truth) != length(predicted)) return(NA_real_)
  keep <- !is.na(truth) & !is.na(predicted)
  truth <- as.factor(truth[keep])
  predicted <- as.factor(predicted[keep])
  n <- length(truth)
  if (n < 2L) return(NA_real_)
  tab <- table(truth, predicted)
  choose2 <- function(x) x * (x - 1) / 2
  index <- sum(choose2(tab))
  row_sum <- sum(choose2(rowSums(tab)))
  col_sum <- sum(choose2(colSums(tab)))
  total <- choose2(n)
  expected <- row_sum * col_sum / total
  maximum <- (row_sum + col_sum) / 2
  denominator <- maximum - expected
  if (denominator == 0) {
    if (index == expected) 1 else 0
  } else {
    (index - expected) / denominator
  }
}

normalized_mutual_information <- function(truth, predicted) {
  if (is.null(truth) || length(truth) != length(predicted)) return(NA_real_)
  keep <- !is.na(truth) & !is.na(predicted)
  tab <- table(as.factor(truth[keep]), as.factor(predicted[keep]))
  n <- sum(tab)
  if (n == 0) return(NA_real_)
  joint <- tab / n
  row_prob <- rowSums(joint)
  col_prob <- colSums(joint)
  nonzero <- which(joint > 0, arr.ind = TRUE)
  mutual_information <- sum(vapply(seq_len(nrow(nonzero)), function(i) {
    r <- nonzero[i, 1L]
    c <- nonzero[i, 2L]
    joint[r, c] * log(joint[r, c] / (row_prob[r] * col_prob[c]))
  }, numeric(1)))
  entropy <- function(probability) {
    probability <- probability[probability > 0]
    -sum(probability * log(probability))
  }
  denominator <- sqrt(entropy(row_prob) * entropy(col_prob))
  if (denominator == 0) NA_real_ else mutual_information / denominator
}

finite_max <- function(x) {
  x <- suppressWarnings(as.numeric(x))
  x <- x[is.finite(x)]
  if (length(x)) max(x) else NA_real_
}

finite_median <- function(x) {
  x <- suppressWarnings(as.numeric(x))
  x <- x[is.finite(x)]
  if (length(x)) stats::median(x) else NA_real_
}

sample_rows <- function(n, size, seed) {
  if (n <= size) return(seq_len(n))
  set.seed(seed)
  sort(sample.int(n, size))
}

worker_status_path <- function(worker_out) {
  sub("\\.csv$", "_status.csv", worker_out)
}

write_worker_status <- function(worker_out, stage, status = "running",
                                details = NA_character_) {
  timestamp <- format(Sys.time(), "%Y-%m-%dT%H:%M:%S%z")
  path <- worker_status_path(worker_out)
  row <- data.frame(
    timestamp = timestamp,
    pid = Sys.getpid(),
    stage = as.character(stage),
    status = as.character(status),
    details = as.character(details),
    stringsAsFactors = FALSE
  )
  write.table(
    row,
    path,
    sep = ",",
    row.names = FALSE,
    col.names = !file.exists(path),
    append = file.exists(path),
    quote = TRUE
  )
  cat(
    sprintf(
      "[%s] stage=%s status=%s%s\n",
      timestamp,
      stage,
      status,
      if (is.na(details) || !nzchar(details)) {
        ""
      } else {
        paste0(" details=", details)
      }
    )
  )
  flush.console()
  invisible(path)
}

atomic_write_csv <- function(x, path) {
  temporary <- tempfile(
    pattern = paste0(".", basename(path), "."),
    tmpdir = dirname(path),
    fileext = ".tmp"
  )
  on.exit(unlink(temporary), add = TRUE)
  write.csv(x, temporary, row.names = FALSE)
  if (!file.rename(temporary, path)) {
    stop("Could not atomically write checkpoint: ", path, call. = FALSE)
  }
  invisible(path)
}

write_worker_checkpoint <- function(row, worker_out) {
  existing <- if (file.exists(worker_out)) {
    tryCatch(read.csv(worker_out, stringsAsFactors = FALSE), error = identity)
  } else {
    NULL
  }
  if (inherits(existing, "error") || is.null(existing) || !nrow(existing)) {
    return(atomic_write_csv(row, worker_out))
  }
  identity_names <- c("dataset", "classifier", "visualization", "seed")
  if (all(identity_names %in% names(existing)) &&
      all(identity_names %in% names(row))) {
    duplicate <- rep(TRUE, nrow(existing))
    for (name in identity_names) {
      duplicate <- duplicate &
        as.character(existing[[name]]) == as.character(row[[name]][[1L]])
    }
    existing <- existing[!duplicate, , drop = FALSE]
  }
  all_names <- union(names(existing), names(row))
  for (name in setdiff(all_names, names(existing))) existing[[name]] <- NA
  for (name in setdiff(all_names, names(row))) row[[name]] <- NA
  atomic_write_csv(
    rbind(existing[all_names], row[all_names]),
    worker_out
  )
}

score_layout <- function(x, layout, labels, dataset, seed, n.cores,
                         quality_sample_n) {
  output <- list(
    trustworthiness = NA_real_,
    knn_preservation_15 = NA_real_,
    knn_preservation_30 = NA_real_,
    knn_preservation_50 = NA_real_,
    silhouette = NA_real_,
    label_knn_accuracy = NA_real_,
    quality_sample_n = NA_integer_
  )
  if (!requireNamespace("fastEmbedR", quietly = TRUE)) return(output)
  rows <- sample_rows(nrow(x), min(quality_sample_n, nrow(x)), seed + 9109L)
  k_values <- c(15L, 30L, 50L)
  k_values <- k_values[k_values < length(rows)]
  if (!length(k_values)) return(output)
  scores <- tryCatch(
    call_supported(
      getExportedValue("fastEmbedR", "evaluate_embedding"),
      list(
        x_high = x[rows, , drop = FALSE],
        embedding = layout[rows, , drop = FALSE],
        labels = if (is.null(labels)) NULL else labels[rows],
        k = k_values,
        sample_size_for_global_metrics = min(2000L, length(rows)),
        sample_size_for_local_metrics = min(2000L, length(rows)),
        seed = seed,
        n.cores = n.cores,
        dataset = dataset
      )
    ),
    error = function(e) NULL
  )
  if (is.null(scores) || !nrow(scores)) return(output)
  first <- scores[1L, , drop = FALSE]
  read_metric <- function(name, alternate = NULL) {
    value <- if (name %in% names(first)) first[[name]][[1L]] else {
      if (!is.null(alternate) && alternate %in% names(first)) {
        first[[alternate]][[1L]]
      } else {
        NA_real_
      }
    }
    suppressWarnings(as.numeric(value))
  }
  output$trustworthiness <- read_metric("trustworthiness")
  output$knn_preservation_15 <- read_metric("knn_preservation_15")
  output$knn_preservation_30 <- read_metric(
    "knn_preservation_30", "knn_preservation"
  )
  output$knn_preservation_50 <- read_metric("knn_preservation_50")
  output$silhouette <- read_metric("silhouette")
  output$label_knn_accuracy <- read_metric(
    "label_knn_accuracy", "nn_accuracy"
  )
  output$quality_sample_n <- length(rows)
  output
}

clean_embedding_plot <- function(layout, labels, file, seed, max_points,
                                 title = NULL) {
  rows <- sample_rows(nrow(layout), min(max_points, nrow(layout)), seed + 71L)
  colors <- if (is.null(labels)) {
    rep("#2563EB", length(rows))
  } else {
    values <- droplevels(as.factor(labels[rows]))
    palette <- grDevices::hcl.colors(max(2L, nlevels(values)), "Dynamic")
    palette[as.integer(values)]
  }
  point_size <- if (length(rows) <= 2000L) {
    0.75
  } else if (length(rows) <= 20000L) {
    0.32
  } else {
    0.13
  }
  x_range <- range(layout[rows, 1L], finite = TRUE)
  y_range <- range(layout[rows, 2L], finite = TRUE)
  add_padding <- function(value) {
    width <- diff(value)
    if (!is.finite(width) || width <= 0) width <- 1
    value + c(-1, 1) * 0.04 * width
  }
  grDevices::png(
    file,
    width = 2400,
    height = 2000,
    res = 250,
    bg = "white"
  )
  old <- graphics::par(mar = c(0, 0, if (is.null(title)) 0 else 1.2, 0))
  on.exit({
    graphics::par(old)
    grDevices::dev.off()
  }, add = TRUE)
  graphics::plot(
    layout[rows, 1L],
    layout[rows, 2L],
    pch = 20,
    cex = point_size,
    col = colors,
    xlim = add_padding(x_range),
    ylim = add_padding(y_range),
    axes = FALSE,
    ann = FALSE,
    frame.plot = FALSE,
    asp = 1
  )
  if (!is.null(title)) {
    graphics::title(main = title, line = 0.1, cex.main = 0.7)
  }
  invisible(length(rows))
}

safe_embedding_plot <- function(layout, labels, file, seed, max_points,
                                title = NULL) {
  tryCatch(
    list(
      sample_n = clean_embedding_plot(
        layout, labels, file, seed, max_points, title
      ),
      file = file,
      error = NA_character_
    ),
    error = function(error) {
      message <- conditionMessage(error)
      writeLines(message, paste0(file, ".error.txt"))
      list(sample_n = NA_integer_, file = NA_character_, error = message)
    }
  )
}

stored_visual_init <- function(fit, method) {
  key <- if (identical(method, "UMAP")) "umap" else "opentsne"
  if (is.list(fit$visual_init)) {
    fit$visual_init[[key]] %||% NULL
  } else {
    fit$visual_init %||% NULL
  }
}

run_visualization <- function(fit, method, backend, n.cores, k, perplexity,
                              n.epochs, n.iter, seed) {
  fun <- getExportedValue("kodamaR", "KODAMA.visualization")
  arguments <- list(
    x = fit,
    method = method,
    init = stored_visual_init(fit, method),
    k = as.integer(k),
    metric = "euclidean",
    backend = backend,
    n.cores = as.integer(n.cores),
    gpu.device = 0L,
    n.epochs = as.integer(n.epochs),
    n.iter = as.integer(n.iter),
    perplexity = as.numeric(perplexity),
    seed = as.integer(seed)
  )
  timing <- system.time(value <- call_supported(fun, arguments))[["elapsed"]]
  list(layout = extract_layout(value), elapsed_sec = unname(timing))
}

worker_failure_rows <- function(dataset, classifier, backend, seed, n.cores,
                                landmark, error) {
  do.call(rbind, lapply(c("openTSNE", "UMAP"), function(visualization) {
    data.frame(
      dataset = dataset,
      classifier = classifier,
      visualization = visualization,
      backend_requested = backend,
      backend_used = NA_character_,
      status = "failed",
      error = as.character(error),
      seed = seed,
      n.cores = n.cores,
      n = NA_integer_,
      p = NA_integer_,
      graph_checkpoint_file = NA_character_,
      graph_precompute_sec = NA_real_,
      graph_reused = NA,
      internal_graph_builds = NA_integer_,
      internal_graph_sec = NA_real_,
      M = NA_integer_,
      Tcycle = NA_integer_,
      ncomp = NA_integer_,
      k = NA_integer_,
      perplexity = NA_real_,
      landmark_mode = landmark$mode %||% NA_character_,
      landmarks_requested = landmark$requested %||% NA_integer_,
      landmarks_effective = landmark$effective %||% NA_integer_,
      landmark_fraction_requested =
        landmark$requested_fraction %||% NA_real_,
      landmark_fraction_effective =
        landmark$effective_fraction %||% NA_real_,
      core_runtime_sec = NA_real_,
      visualization_runtime_sec = NA_real_,
      total_workflow_runtime_sec = NA_real_,
      best_cv_accuracy = NA_real_,
      median_cv_accuracy = NA_real_,
      best_run = NA_integer_,
      selected_clusters = NA_integer_,
      selected_ari = NA_real_,
      selected_nmi = NA_real_,
      trustworthiness = NA_real_,
      knn_preservation_15 = NA_real_,
      knn_preservation_30 = NA_real_,
      knn_preservation_50 = NA_real_,
      silhouette = NA_real_,
      label_knn_accuracy = NA_real_,
      quality_sample_n = NA_integer_,
      plot_sample_n = NA_integer_,
      model_summary_file = NA_character_,
      layout_file = NA_character_,
      truth_plot_file = NA_character_,
      kodama_label_plot_file = NA_character_,
      stringsAsFactors = FALSE
    )
  }))
}

worker_main <- function(classifier, args) {
  dataset <- args$dataset %||% stop("--dataset is required.")
  backend <- args$backend %||% "cpu"
  n.cores <- as_int(args$n_cores, 1L)
  seed <- as_int(args$seed, 4L)
  data_root <- args$data_root %||% "/scratch/firenze/NN/Data"
  out_dir <- args$out_dir %||% stop("--out-dir is required.")
  layout_dir <- args$layout_dir %||% stop("--layout-dir is required.")
  worker_out <- args$worker_out %||% stop("--worker-out is required.")
  M <- as_int(args$M, 100L)
  Tcycle <- as_int(args$Tcycle, 100L)
  ncomp <- as_int(args$ncomp, 50L)
  k <- as_int(args$k, 30L)
  perplexity <- as_num(args$perplexity, 30)
  graph_neighbors <- as_int(args$graph_neighbors, 100L)
  graph_file <- args$graph_file %||%
    stop("--graph-file is required; graph construction is a separate job.")
  n.epochs <- as_int(args$n_epochs, 200L)
  n.iter <- as_int(args$n_iter, 500L)
  quality_sample_n <- as_int(args$quality_sample_n, 5000L)
  plot_max_points <- as_int(args$plot_max_points, 250000L)
  landmark_mode <- args$landmark_mode %||% "default"
  landmark_fraction <- as_num(args$landmark_fraction, NA_real_)
  default_landmarks <- as_int(args$default_landmarks, 10000000L)
  large_threshold <- as_int(args$large_threshold, 10000L)

  dir.create(out_dir, recursive = TRUE, showWarnings = FALSE)
  dir.create(layout_dir, recursive = TRUE, showWarnings = FALSE)
  dir.create(file.path(out_dir, "plots"), recursive = TRUE, showWarnings = FALSE)
  set.seed(seed)
  write_worker_status(
    worker_out,
    "worker_started",
    details = sprintf(
      "dataset=%s classifier=%s backend=%s seed=%d",
      dataset, classifier, backend, seed
    )
  )

  landmark <- list(mode = landmark_mode)
  result <- tryCatch({
    if (!requireNamespace("kodamaR", quietly = TRUE)) {
      stop("kodamaR is not installed.")
    }
    if (!backend %in% c("cpu", "cuda")) {
      stop("KODAMA backend must be cpu or cuda.")
    }
    dataset_data <- load_benchmark_dataset(dataset, data_root)
    x <- dataset_data$data
    labels <- dataset_data$labels
    n <- nrow(x)
    p <- ncol(x)
    write_worker_status(
      worker_out,
      "shared_graph_loading",
      details = graph_file
    )
    graph_bundle <- load_kodama_graph_bundle(
      graph_file, dataset_data, dataset, backend, graph_neighbors
    )
    shared_graph <- graph_bundle$graph
    write_worker_status(
      worker_out,
      "shared_graph_loaded",
      "success",
      sprintf(
        "file=%s graph_build_elapsed_sec=%.6f",
        graph_file, as.numeric(graph_bundle$graph_build_elapsed_sec)
      )
    )
    landmark <- resolve_landmarks(
      n, landmark_mode, landmark_fraction, default_landmarks, large_threshold
    )
    effective_ncomp <- max(1L, min(ncomp, p, n - 1L))
    effective_graph_neighbors <- max(
      1L, min(graph_neighbors, landmark$effective, floor(0.75 * n - 1L))
    )
    effective_k <- max(1L, min(k, landmark$effective - 1L))
    matrix_fun <- getExportedValue("kodamaR", "KODAMA.matrix")
    matrix_formals <- names(formals(matrix_fun))
    if (!"graph" %in% matrix_formals) {
      stop(
        "Installed kodamaR predates the KODAMA.matrix(data, graph, ...) API. ",
        "Rebuild the runtime with the updated kodamaR wrapper; the benchmark ",
        "will not silently rebuild the supplied graph.",
        call. = FALSE
      )
    }
    matrix_arguments <- list(
      data = x,
      graph = shared_graph,
      M = as.integer(M),
      Tcycle = as.integer(Tcycle),
      ncomp = as.integer(effective_ncomp),
      landmarks = as.integer(landmark$requested),
      n.cores = as.integer(n.cores),
      graph.neighbors = as.integer(effective_graph_neighbors),
      knn.k = as.integer(effective_k),
      metric = "euclidean",
      classifier = classifier,
      backend = backend,
      seed = as.integer(seed),
      visual.init = TRUE,
      progress = TRUE,
      apply.kodama.dissimilarity = TRUE
    )
    write_worker_status(
      worker_out,
      "kodama_core_started",
      details = sprintf(
        "n=%d p=%d landmarks=%d M=%d Tcycle=%d",
        n, p, landmark$effective, M, Tcycle
      )
    )
    core_time <- system.time({
      fit <- call_supported(matrix_fun, matrix_arguments)
    })[["elapsed"]]
    internal_graph_builds <- as_int(fit$graph_builds, NA_integer_)
    if (is.na(internal_graph_builds) || internal_graph_builds != 0L) {
      stop(
        "KODAMA.matrix did not reuse the supplied graph: graph_builds=",
        internal_graph_builds, ".", call. = FALSE
      )
    }
    internal_graph_sec <- as_num(
      fit$timing$graph_seconds %||% fit$graph_seconds,
      NA_real_
    )
    write_worker_status(
      worker_out,
      "kodama_core_completed",
      "success",
      sprintf("elapsed_sec=%.6f", unname(core_time))
    )
    backend_used <- as.character(fit$backend %||% NA_character_)
    if (!identical(backend_used, backend)) {
      stop(
        "KODAMA backend mismatch: requested ", backend,
        " but the result reports ", backend_used, "."
      )
    }
    selected <- as.integer(fit$best_labels %||% integer())
    if (length(selected) != n) {
      stop("KODAMA did not return one selected label per sample.")
    }
    accuracy <- suppressWarnings(as.numeric(fit$acc %||% NA_real_))
    best_run <- as_int(fit$best_run, which.max(accuracy))
    selected_ari <- adjusted_rand_index(labels, selected)
    selected_nmi <- normalized_mutual_information(labels, selected)
    model_file <- file.path(
      layout_dir,
      sprintf(
        "%s_%s_%s_seed%d_model_summary.rds",
        safe_name(dataset), safe_name(classifier),
        safe_name(if (landmark_mode == "default") {
          "default"
        } else {
          sprintf("landmark%02d", round(100 * landmark_fraction))
        }),
        seed
      )
    )
    saveRDS(
      list(
        best_labels = selected,
        accuracy = accuracy,
        best_run = best_run,
        class_counts = fit$class_counts %||% NULL,
        timing = fit$timing %||% NULL,
        runtime_seconds = fit$runtime_seconds %||% unname(core_time),
        parameters = fit$parameters %||% matrix_arguments,
        classifier = classifier,
        backend = backend_used,
        dataset = dataset,
        dataset_path = dataset_data$path,
        graph_checkpoint_file = graph_file,
        graph_precompute_sec = graph_bundle$graph_build_elapsed_sec,
        graph_reused = TRUE,
        internal_graph_builds = internal_graph_builds,
        internal_graph_sec = internal_graph_sec,
        landmarks_requested = landmark$requested,
        landmarks_effective = landmark$effective
      ),
      model_file,
      compress = FALSE
    )
    write_worker_status(
      worker_out,
      "model_checkpoint_saved",
      "success",
      model_file
    )

    rows <- lapply(c("opentsne", "UMAP"), function(visualization) {
      visualization_label <- if (visualization == "UMAP") {
        "UMAP"
      } else {
        "openTSNE"
      }
      write_worker_status(
        worker_out,
        paste0(tolower(visualization_label), "_started")
      )
      visualization_result <- tryCatch(
        run_visualization(
          fit, visualization, backend, n.cores, effective_k, perplexity,
          n.epochs, n.iter, seed
        ),
        error = identity
      )
      if (inherits(visualization_result, "error")) {
        row <- worker_failure_rows(
          dataset, classifier, backend, seed, n.cores, landmark,
          conditionMessage(visualization_result)
        )
        row <- row[row$visualization == visualization_label, , drop = FALSE]
        row$n <- n
        row$p <- p
        row$graph_checkpoint_file <- graph_file
        row$graph_precompute_sec <- graph_bundle$graph_build_elapsed_sec
        row$graph_reused <- TRUE
        row$internal_graph_builds <- internal_graph_builds
        row$internal_graph_sec <- internal_graph_sec
        row$M <- M
        row$Tcycle <- Tcycle
        row$ncomp <- effective_ncomp
        row$k <- effective_k
        row$perplexity <- perplexity
        row$core_runtime_sec <- unname(core_time)
        row$best_cv_accuracy <- finite_max(accuracy)
        row$median_cv_accuracy <- finite_median(accuracy)
        row$best_run <- best_run
        row$selected_clusters <- length(unique(selected))
        row$selected_ari <- selected_ari
        row$selected_nmi <- selected_nmi
        row$model_summary_file <- model_file
        write_worker_checkpoint(row, worker_out)
        write_worker_status(
          worker_out,
          paste0(tolower(visualization_label), "_failed"),
          "failed",
          conditionMessage(visualization_result)
        )
        return(row)
      }
      layout <- visualization_result$layout
      method_tag <- if (visualization == "UMAP") "umap" else "opentsne"
      variant_tag <- if (landmark_mode == "default") {
        "default"
      } else {
        sprintf("landmark%02d", round(100 * landmark_fraction))
      }
      stem <- sprintf(
        "%s_%s_%s_%s_seed%d",
        safe_name(dataset), safe_name(classifier), method_tag, variant_tag, seed
      )
      layout_file <- file.path(layout_dir, paste0(stem, "_layout.rds"))
      truth_plot <- file.path(out_dir, "plots", paste0(stem, "_truth.png"))
      kodama_plot <- file.path(
        out_dir, "plots", paste0(stem, "_kodama_labels.png")
      )
      saveRDS(
        list(
          layout = layout,
          labels = labels,
          kodama_labels = selected,
          dataset = dataset,
          classifier = classifier,
          visualization = visualization_label,
          backend = backend_used,
          seed = seed,
          landmarks_requested = landmark$requested,
          landmarks_effective = landmark$effective
        ),
        layout_file,
        compress = FALSE
      )
      write_worker_status(
        worker_out,
        paste0(tolower(visualization_label), "_layout_saved"),
        "success",
        layout_file
      )
      truth_plot_result <- safe_embedding_plot(
        layout, labels, truth_plot, seed, plot_max_points
      )
      kodama_plot_result <- safe_embedding_plot(
        layout, as.factor(selected), kodama_plot, seed, plot_max_points
      )
      plot_errors <- c(
        truth_plot_result$error,
        kodama_plot_result$error
      )
      plot_errors <- plot_errors[!is.na(plot_errors) & nzchar(plot_errors)]
      row <- data.frame(
        dataset = dataset,
        classifier = classifier,
        visualization = visualization_label,
        backend_requested = backend,
        backend_used = backend_used,
        status = if (length(plot_errors)) "partial" else "success",
        error = if (length(plot_errors)) {
          paste(unique(plot_errors), collapse = " | ")
        } else {
          NA_character_
        },
        seed = seed,
        n.cores = n.cores,
        n = n,
        p = p,
        graph_checkpoint_file = graph_file,
        graph_precompute_sec = graph_bundle$graph_build_elapsed_sec,
        graph_reused = TRUE,
        internal_graph_builds = internal_graph_builds,
        internal_graph_sec = internal_graph_sec,
        M = M,
        Tcycle = Tcycle,
        ncomp = effective_ncomp,
        k = effective_k,
        perplexity = perplexity,
        landmark_mode = landmark$mode,
        landmarks_requested = landmark$requested,
        landmarks_effective = landmark$effective,
        landmark_fraction_requested = landmark$requested_fraction,
        landmark_fraction_effective = landmark$effective_fraction,
        core_runtime_sec = unname(core_time),
        visualization_runtime_sec = visualization_result$elapsed_sec,
        total_workflow_runtime_sec =
          unname(core_time) + visualization_result$elapsed_sec,
        best_cv_accuracy = finite_max(accuracy),
        median_cv_accuracy = finite_median(accuracy),
        best_run = best_run,
        selected_clusters = length(unique(selected)),
        selected_ari = selected_ari,
        selected_nmi = selected_nmi,
        trustworthiness = NA_real_,
        knn_preservation_15 = NA_real_,
        knn_preservation_30 = NA_real_,
        knn_preservation_50 = NA_real_,
        silhouette = NA_real_,
        label_knn_accuracy = NA_real_,
        quality_sample_n = NA_integer_,
        plot_sample_n = truth_plot_result$sample_n,
        model_summary_file = model_file,
        layout_file = layout_file,
        truth_plot_file = truth_plot_result$file,
        kodama_label_plot_file = kodama_plot_result$file,
        stringsAsFactors = FALSE
      )
      write_worker_checkpoint(row, worker_out)
      write_worker_status(
        worker_out,
        paste0(tolower(visualization_label), "_artifacts_saved"),
        row$status,
        sprintf(
          "layout=%s truth_plot=%s kodama_plot=%s",
          layout_file,
          truth_plot_result$file %||% NA_character_,
          kodama_plot_result$file %||% NA_character_
        )
      )
      quality <- score_layout(
        x, layout, labels, dataset, seed, n.cores, quality_sample_n
      )
      row$trustworthiness <- quality$trustworthiness
      row$knn_preservation_15 <- quality$knn_preservation_15
      row$knn_preservation_30 <- quality$knn_preservation_30
      row$knn_preservation_50 <- quality$knn_preservation_50
      row$silhouette <- quality$silhouette
      row$label_knn_accuracy <- quality$label_knn_accuracy
      row$quality_sample_n <- quality$quality_sample_n
      write_worker_checkpoint(row, worker_out)
      write_worker_status(
        worker_out,
        paste0(tolower(visualization_label), "_completed"),
        row$status
      )
      row
    })
    do.call(rbind, rows)
  }, error = function(error) {
    write_worker_status(
      worker_out,
      "worker_failed",
      "failed",
      conditionMessage(error)
    )
    worker_failure_rows(
      dataset, classifier, backend, seed, n.cores, landmark,
      conditionMessage(error)
    )
  })
  atomic_write_csv(result, worker_out)
  final_status <- if (all(result$status == "failed")) {
    "failed"
  } else if (any(result$status != "success")) {
    "partial"
  } else {
    "success"
  }
  write_worker_status(worker_out, "worker_completed", final_status)
  invisible(result)
}

read_key_values <- function(path) {
  if (!file.exists(path)) return(list())
  values <- strsplit(readLines(path, warn = FALSE), "=", fixed = TRUE)
  values <- values[vapply(values, length, integer(1)) >= 2L]
  output <- lapply(values, function(value) paste(value[-1L], collapse = "="))
  names(output) <- vapply(values, `[[`, character(1), 1L)
  output
}

parse_memory <- function(time_file, gpu_file) {
  lines <- if (file.exists(time_file)) readLines(time_file, warn = FALSE) else character()
  rss <- grep("Maximum resident set size", lines, value = TRUE)
  rss <- if (length(rss)) {
    suppressWarnings(as.numeric(sub(".*: *", "", tail(rss, 1L))))
  } else NA_real_
  gpu <- read_key_values(gpu_file)
  list(
    peak_ram_kb = rss,
    peak_ram_gb = rss / 1024^2,
    gpu_memory_scope = gpu$gpu_memory_scope %||% NA_character_,
    gpu_baseline_mb = suppressWarnings(as.numeric(
      gpu$gpu_baseline_mb %||% NA_real_
    )),
    peak_gpu_mb = suppressWarnings(as.numeric(gpu$gpu_peak_mb %||% NA_real_)),
    peak_gpu_delta_mb = suppressWarnings(as.numeric(
      gpu$gpu_peak_delta_mb %||% NA_real_
    ))
  )
}

aggregate_runs <- function(runs) {
  if (!nrow(runs)) return(data.frame())
  group_names <- c(
    "dataset", "classifier", "visualization", "backend_requested",
    "backend_used", "n.cores", "n", "p", "M", "Tcycle", "ncomp", "k",
    "perplexity", "landmark_mode", "landmarks_requested",
    "landmarks_effective", "landmark_fraction_requested",
    "landmark_fraction_effective", "graph_checkpoint_file", "graph_reused"
  )
  numeric_names <- c(
    "graph_precompute_sec", "internal_graph_builds", "internal_graph_sec",
    "core_runtime_sec", "visualization_runtime_sec",
    "total_workflow_runtime_sec", "peak_ram_gb", "peak_gpu_delta_mb",
    "best_cv_accuracy", "median_cv_accuracy", "selected_clusters",
    "selected_ari", "selected_nmi", "trustworthiness",
    "knn_preservation_15", "knn_preservation_30", "knn_preservation_50",
    "silhouette", "label_knn_accuracy"
  )
  keys <- do.call(
    paste,
    c(lapply(runs[group_names], function(x) {
      x <- as.character(x)
      x[is.na(x)] <- "<NA>"
      x
    }), sep = "\r")
  )
  pieces <- split(runs, keys)
  output <- lapply(pieces, function(piece) {
    row <- piece[1L, group_names, drop = FALSE]
    row$n_runs <- nrow(piece)
    row$n_success <- sum(piece$status == "success")
    row$status <- if (row$n_success == row$n_runs) {
      "success"
    } else if (row$n_success > 0L) {
      "partial"
    } else {
      "failed"
    }
    for (name in numeric_names) {
      values <- suppressWarnings(as.numeric(piece[[name]]))
      values <- values[is.finite(values)]
      row[[paste0(name, "_median")]] <- if (length(values)) {
        stats::median(values)
      } else NA_real_
      row[[paste0(name, "_q1")]] <- if (length(values)) {
        unname(stats::quantile(values, 0.25, names = FALSE))
      } else NA_real_
      row[[paste0(name, "_q3")]] <- if (length(values)) {
        unname(stats::quantile(values, 0.75, names = FALSE))
      } else NA_real_
    }
    row
  })
  result <- do.call(rbind, output)
  rownames(result) <- NULL
  result
}

parent_main <- function(classifier, script_path, args) {
  dataset <- args$dataset %||% stop("--dataset is required.")
  backend <- args$backend %||% "cpu"
  n.cores <- as_int(args$n_cores, 1L)
  seeds <- as.integer(strsplit(args$seeds %||% "4,17,42", ",", fixed = TRUE)[[1L]])
  seeds <- seeds[!is.na(seeds)]
  if (!length(seeds)) stop("No valid seeds were provided.")
  out_dir <- args$out_dir %||% stop("--out-dir is required.")
  layout_dir <- args$layout_dir %||% stop("--layout-dir is required.")
  monitor_script <- args$monitor_script %||%
    file.path(dirname(script_path), "..", "benchmark_worker_monitor.sh")
  timeout <- as_int(args$timeout, 172800L)
  force <- as_flag(args$force, FALSE)
  dir.create(out_dir, recursive = TRUE, showWarnings = FALSE)
  dir.create(layout_dir, recursive = TRUE, showWarnings = FALSE)
  for (folder in c("worker_results", "logs", "memory", "plots")) {
    dir.create(file.path(out_dir, folder), recursive = TRUE, showWarnings = FALSE)
  }

  common_arguments <- c(
    paste0("--dataset=", dataset),
    paste0("--backend=", backend),
    paste0("--n-cores=", n.cores),
    paste0("--data-root=", args$data_root %||% "/scratch/firenze/NN/Data"),
    paste0("--out-dir=", out_dir),
    paste0("--layout-dir=", layout_dir),
    paste0("--M=", args$M %||% "100"),
    paste0("--Tcycle=", args$Tcycle %||% "100"),
    paste0("--ncomp=", args$ncomp %||% "50"),
    paste0("--k=", args$k %||% "30"),
    paste0("--perplexity=", args$perplexity %||% "30"),
    paste0("--graph-neighbors=", args$graph_neighbors %||% "100"),
    paste0("--graph-file=", args$graph_file %||%
      stop("--graph-file is required.")),
    paste0("--n-epochs=", args$n_epochs %||% "200"),
    paste0("--n-iter=", args$n_iter %||% "500"),
    paste0("--quality-sample-n=", args$quality_sample_n %||% "5000"),
    paste0("--plot-max-points=", args$plot_max_points %||% "250000"),
    paste0("--landmark-mode=", args$landmark_mode %||% "default"),
    paste0("--landmark-fraction=", args$landmark_fraction %||% "NA"),
    paste0("--default-landmarks=", args$default_landmarks %||% "10000000"),
    paste0("--large-threshold=", args$large_threshold %||% "10000")
  )

  runs <- list()
  for (seed in seeds) {
    tag <- if (identical(args$landmark_mode %||% "default", "default")) {
      "default"
    } else {
      sprintf(
        "landmark%02d",
        round(100 * as_num(args$landmark_fraction, NA_real_))
      )
    }
    stem <- sprintf(
      "%s_%s_%s_%s_seed%d",
      safe_name(dataset), safe_name(classifier), backend, tag, seed
    )
    csv <- file.path(out_dir, "worker_results", paste0(stem, ".csv"))
    log <- file.path(out_dir, "logs", paste0(stem, ".log"))
    time_file <- file.path(out_dir, "memory", paste0(stem, "_ram.txt"))
    gpu_file <- file.path(out_dir, "memory", paste0(stem, "_gpu.txt"))
    if (!force && file.exists(csv)) {
      existing <- tryCatch(read.csv(csv, stringsAsFactors = FALSE), error = identity)
      if (!inherits(existing, "error") && nrow(existing)) {
        runs[[length(runs) + 1L]] <- existing
        next
      }
    }
    command <- c(
      normalizePath(monitor_script, mustWork = TRUE),
      time_file,
      gpu_file,
      as.character(timeout),
      file.path(R.home("bin"), "Rscript"),
      normalizePath(script_path, mustWork = TRUE),
      "--worker=true",
      paste0("--seed=", seed),
      paste0("--worker-out=", csv),
      common_arguments
    )
    status <- system2("bash", command, stdout = log, stderr = log)
    row <- if (file.exists(csv)) {
      read.csv(csv, stringsAsFactors = FALSE)
    } else {
      worker_failure_rows(
        dataset, classifier, backend, seed, n.cores,
        list(mode = args$landmark_mode %||% "default"),
        sprintf("Worker exited with status %s; see %s", status, log)
      )
    }
    memory <- parse_memory(time_file, gpu_file)
    for (name in names(memory)) row[[name]] <- memory[[name]]
    runs[[length(runs) + 1L]] <- row
    write.csv(
      do.call(rbind, runs),
      file.path(out_dir, paste0("kodama_", classifier, "_runs_checkpoint.csv")),
      row.names = FALSE
    )
  }
  runs <- do.call(rbind, runs)
  summary <- aggregate_runs(runs)
  write.csv(
    runs,
    file.path(out_dir, paste0("kodama_", classifier, "_runs.csv")),
    row.names = FALSE
  )
  write.csv(
    summary,
    file.path(out_dir, paste0("kodama_", classifier, "_summary.csv")),
    row.names = FALSE
  )
  commit <- tryCatch(
    suppressWarnings(
      system2(
        "git",
        c("-C", dirname(script_path), "rev-parse", "HEAD"),
        stdout = TRUE,
        stderr = FALSE
      )
    ),
    error = function(e) character()
  )
  if (!length(commit)) commit <- NA_character_
  manifest <- data.frame(
    dataset = dataset,
    classifier = classifier,
    backend = backend,
    n.cores = n.cores,
    seeds = paste(seeds, collapse = ","),
    landmark_mode = args$landmark_mode %||% "default",
    landmark_fraction = as_num(args$landmark_fraction, NA_real_),
    graph_checkpoint_file = args$graph_file %||% NA_character_,
    M = as_int(args$M, 100L),
    Tcycle = as_int(args$Tcycle, 100L),
    ncomp = as_int(args$ncomp, 50L),
    k = as_int(args$k, 30L),
    perplexity = as_num(args$perplexity, 30),
    git_commit = commit[[1L]],
    R_version = R.version.string,
    timestamp = format(Sys.time(), "%Y-%m-%dT%H:%M:%S%z"),
    stringsAsFactors = FALSE
  )
  write.csv(manifest, file.path(out_dir, "run_manifest.csv"), row.names = FALSE)
  print(summary)
  invisible(summary)
}

run_kodama_benchmark <- function(classifier, script_path) {
  if (!classifier %in% c("knn", "pls_lda")) {
    stop("classifier must be knn or pls_lda.")
  }
  args <- parse_cli(commandArgs(trailingOnly = TRUE))
  if (as_flag(args$worker, FALSE)) {
    worker_main(classifier, args)
  } else {
    parent_main(classifier, script_path, args)
  }
}
