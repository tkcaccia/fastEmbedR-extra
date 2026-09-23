#!/usr/bin/env Rscript

# Validate fastEmbedR graph construction and community detection against
# established CPU and CUDA references. Graph construction and clustering are
# timed separately. Louvain and Leiden use the requested native CPU or CUDA
# clustering backend; Walktrap is explicitly CPU-only.

parse_args <- function(args) {
  out <- list()
  for (arg in args) {
    if (!startsWith(arg, "--")) next
    pair <- strsplit(sub("^--", "", arg), "=", fixed = TRUE)[[1L]]
    out[[gsub("-", "_", pair[[1L]])]] <- if (length(pair) > 1L) {
      paste(pair[-1L], collapse = "=")
    } else {
      "TRUE"
    }
  }
  out
}

`%||%` <- function(x, y) {
  if (is.null(x) || !length(x) || (length(x) == 1L && is.na(x))) y else x
}
as_bool <- function(x, default = FALSE) {
  if (is.null(x)) return(default)
  tolower(as.character(x)) %in% c("1", "true", "yes", "y")
}
as_int <- function(x, default) {
  value <- suppressWarnings(as.integer(x %||% default))
  if (length(value) != 1L || is.na(value)) as.integer(default) else value
}
as_num <- function(x, default) {
  value <- suppressWarnings(as.numeric(x %||% default))
  if (length(value) != 1L || !is.finite(value)) as.numeric(default) else value
}
as_csv <- function(x, default) {
  value <- trimws(strsplit(as.character(x %||% default), ",", fixed = TRUE)[[1L]])
  value[nzchar(value)]
}

args <- parse_args(commandArgs(trailingOnly = TRUE))
base_dir <- normalizePath(args$base_dir %||% "/scratch/firenze/NN", mustWork = FALSE)
data_root <- normalizePath(args$data_root %||% file.path(base_dir, "Data"), mustWork = FALSE)
input_root <- normalizePath(
  args$input_root %||% file.path(base_dir, "fastEmbedR-input", "clustering"),
  mustWork = FALSE
)
out_dir <- normalizePath(
  args$out_dir %||% file.path(
    base_dir,
    "fastEmbedR-results",
    "clustering_validation",
    format(Sys.time(), "%Y%m%d_%H%M%S")
  ),
  mustWork = FALSE
)
backend_group <- match.arg(args$backend_group %||% "cpu", c("cpu", "cuda"))
threads <- as_int(args$threads, if (backend_group == "cpu") 4L else 1L)
k <- as_int(args$k, 30L)
metric <- match.arg(args$metric %||% "euclidean", c("euclidean", "cosine", "correlation"))
weight <- match.arg(args$weight %||% "snn", c("snn", "distance", "binary"))
resolution <- as_num(args$resolution, 1)
n_iterations <- as_int(args$n_iterations, 10L)
steps <- as_int(args$steps, 4L)
max_n <- as_int(args$max_n, 100000L)
walktrap_max_n <- as_int(args$walktrap_max_n, 4000L)
force <- as_bool(args$force, FALSE)
run_cugraph <- as_bool(args$run_cugraph, FALSE)
datasets <- as_csv(
  args$datasets,
  paste(
    "COIL20", "USPS", "FashionMNIST",
    "FlowRepository_FR-FCM-ZYRM_files", "flow18", "MNIST", "imagenet",
    "MetRef", "mass41", "TabulaMuris", "Macosko2015_retina",
    sep = ","
  )
)
seeds <- unique(as.integer(as_csv(args$seeds, "4,17,42")))
seeds <- seeds[is.finite(seeds)]
if (!length(seeds)) seeds <- c(4L, 17L, 42L)
methods <- as_csv(args$methods, "louvain,leiden,walktrap")
methods <- intersect(methods, c("louvain", "leiden", "walktrap"))
if (!length(methods)) stop("No valid clustering methods were requested.", call. = FALSE)

dir.create(out_dir, recursive = TRUE, showWarnings = FALSE)
dir.create(input_root, recursive = TRUE, showWarnings = FALSE)
dir.create(file.path(out_dir, "memberships"), recursive = TRUE, showWarnings = FALSE)

Sys.setenv(
  OMP_NUM_THREADS = threads,
  OPENBLAS_NUM_THREADS = threads,
  MKL_NUM_THREADS = threads,
  VECLIB_MAXIMUM_THREADS = threads,
  RCPP_PARALLEL_NUM_THREADS = threads
)

log_path <- file.path(out_dir, "clustering_validation.log")
log_message <- function(...) {
  line <- paste0(format(Sys.time(), "%Y-%m-%d %H:%M:%S"), " ", sprintf(...))
  cat(line, "\n")
  cat(line, "\n", file = log_path, append = TRUE)
  flush.console()
}

peak_rss_gb <- function() {
  if (file.exists("/proc/self/status")) {
    lines <- readLines("/proc/self/status", warn = FALSE)
    value <- sub("^VmHWM:\\s*([0-9]+).*", "\\1", grep("^VmHWM:", lines, value = TRUE))
    value <- suppressWarnings(as.numeric(value))
    if (length(value) && is.finite(value)) return(value / 1024^2)
  }
  if (requireNamespace("peakRAM", quietly = TRUE)) return(NA_real_)
  NA_real_
}

gpu_used_mb <- function() {
  command <- Sys.which("nvidia-smi")
  if (!nzchar(command)) return(NA_real_)
  output <- suppressWarnings(system2(
    command,
    c("--query-compute-apps=used_memory", "--format=csv,noheader,nounits"),
    stdout = TRUE,
    stderr = FALSE
  ))
  values <- suppressWarnings(as.numeric(trimws(output)))
  values <- values[is.finite(values)]
  if (length(values)) sum(values) else 0
}

read_rdata_object <- function(path) {
  environment <- new.env(parent = emptyenv())
  names <- load(path, envir = environment)
  objects <- mget(names, envir = environment, inherits = FALSE)
  for (name in names(objects)) {
    value <- objects[[name]]
    if (is.list(value) && !is.null(value$data)) {
      return(list(
        data = value$data,
        labels = value$labels %||% value$label %||% value$tissue %||% NULL,
        object_name = name,
        source_file = path
      ))
    }
  }
  for (name in names(objects)) {
    value <- objects[[name]]
    if (is.matrix(value) || is.data.frame(value) ||
        inherits(value, "Matrix") || inherits(value, "float32")) {
      labels <- NULL
      for (candidate in c("labels", "label", "tissue", "Y", "y", "class")) {
        if (candidate %in% names(objects) &&
            length(objects[[candidate]]) == nrow(value)) {
          labels <- objects[[candidate]]
          break
        }
      }
      return(list(
        data = value,
        labels = labels,
        object_name = name,
        source_file = path
      ))
    }
  }
  stop("No matrix-like dataset object found in ", path, call. = FALSE)
}

find_dataset_file <- function(dataset) {
  if (tolower(dataset) == "iris") return("__iris__")
  folder <- file.path(data_root, dataset)
  if (!dir.exists(folder)) stop("Dataset folder not found: ", folder, call. = FALSE)
  files <- list.files(folder, pattern = "\\.[Rr][Dd]ata$", full.names = TRUE)
  float_files <- files[grepl("float32", basename(files), ignore.case = TRUE)]
  if (length(float_files)) return(float_files[[order(nchar(basename(float_files)))[1L]]])
  files <- files[!grepl(
    "_nn|knn_|pca|manifest|summary|backup|reference|benchmark|worker",
    basename(files),
    ignore.case = TRUE
  )]
  if (!length(files)) stop("No source RData file found for ", dataset, call. = FALSE)
  exact <- files[
    tolower(tools::file_path_sans_ext(basename(files))) == tolower(dataset)
  ]
  if (length(exact)) return(exact[[1L]])
  files[[order(nchar(basename(files)))[1L]]]
}

load_dataset <- function(dataset) {
  if (tolower(dataset) == "iris") {
    return(list(
      data = as.matrix(datasets::iris[, 1:4]),
      labels = datasets::iris$Species,
      object_name = "iris",
      source_file = "datasets::iris"
    ))
  }
  read_rdata_object(find_dataset_file(dataset))
}

stratified_rows <- function(labels, n, max_n, seed) {
  if (n <= max_n) return(seq_len(n))
  set.seed(seed)
  if (is.null(labels) || length(labels) != n) return(sort(sample.int(n, max_n)))
  groups <- split(seq_len(n), as.character(labels), drop = TRUE)
  allocation <- pmax(1L, floor(max_n * lengths(groups) / n))
  while (sum(allocation) > max_n) {
    index <- which.max(allocation)
    if (allocation[[index]] <= 1L) break
    allocation[[index]] <- allocation[[index]] - 1L
  }
  while (sum(allocation) < max_n) {
    room <- lengths(groups) - allocation
    index <- which.max(room)
    if (room[[index]] <= 0L) break
    allocation[[index]] <- allocation[[index]] + 1L
  }
  rows <- unlist(Map(
    function(index, count) sample(index, min(count, length(index))),
    groups,
    allocation
  ), use.names = FALSE)
  sort(rows[seq_len(min(length(rows), max_n))])
}

adjusted_rand_index <- function(left, right) {
  if (is.null(left) || is.null(right) || length(left) != length(right)) return(NA_real_)
  tab <- table(left, right)
  choose2 <- function(x) x * (x - 1) / 2
  n <- sum(tab)
  if (n < 2L) return(NA_real_)
  index <- sum(choose2(tab))
  row_pairs <- sum(choose2(rowSums(tab)))
  col_pairs <- sum(choose2(colSums(tab)))
  total <- choose2(n)
  expected <- row_pairs * col_pairs / total
  maximum <- (row_pairs + col_pairs) / 2
  if (maximum == expected) return(1)
  (index - expected) / (maximum - expected)
}

normalized_mutual_information <- function(left, right) {
  if (is.null(left) || is.null(right) || length(left) != length(right)) return(NA_real_)
  tab <- table(left, right)
  n <- sum(tab)
  if (!n) return(NA_real_)
  joint <- tab / n
  px <- rowSums(joint)
  py <- colSums(joint)
  nz <- which(joint > 0, arr.ind = TRUE)
  mutual <- sum(joint[nz] * log(joint[nz] / (px[nz[, 1L]] * py[nz[, 2L]])))
  hx <- -sum(px[px > 0] * log(px[px > 0]))
  hy <- -sum(py[py > 0] * log(py[py > 0]))
  if (hx + hy == 0) return(1)
  2 * mutual / (hx + hy)
}

as_igraph <- function(graph) {
  igraph::graph_from_data_frame(
    data.frame(
      from = graph$from,
      to = graph$to,
      weight = graph$weight
    ),
    directed = FALSE,
    vertices = seq_len(graph$n_vertices)
  )
}

run_native <- function(graph, method, seed) {
  cluster_backend <- if (identical(method, "walktrap")) "cpu" else backend_group
  started <- proc.time()[[3L]]
  fit <- fastEmbedR::graph_cluster(
    graph,
    method = method,
    backend = cluster_backend,
    resolution = resolution,
    n_iterations = n_iterations,
    n_runs = 1L,
    steps = steps,
    seed = seed
  )
  list(
    membership = fit$membership,
    modularity = fit$modularity,
    n_communities = fit$n_communities,
    connected_communities = fit$connected_communities %||% NA,
    elapsed_sec = unname(proc.time()[[3L]] - started),
    implementation = fit$implementation %||% paste0("fastEmbedR_", method),
    backend_used = fit$backend
  )
}

run_igraph <- function(graph_igraph, method, seed) {
  set.seed(seed)
  started <- proc.time()[[3L]]
  fit <- switch(
    method,
    louvain = igraph::cluster_louvain(
      graph_igraph,
      weights = igraph::E(graph_igraph)$weight,
      resolution = resolution
    ),
    leiden = igraph::cluster_leiden(
      graph_igraph,
      objective_function = "modularity",
      weights = igraph::E(graph_igraph)$weight,
      resolution = resolution,
      n_iterations = n_iterations
    ),
    walktrap = igraph::cluster_walktrap(
      graph_igraph,
      weights = igraph::E(graph_igraph)$weight,
      steps = steps
    )
  )
  membership <- igraph::membership(fit)
  modularity <- igraph::modularity(
    graph_igraph,
    membership,
    weights = igraph::E(graph_igraph)$weight,
    resolution = if (method == "walktrap") 1 else resolution
  )
  list(
    membership = as.integer(membership),
    modularity = modularity,
    n_communities = length(unique(membership)),
    connected_communities = NA,
    elapsed_sec = unname(proc.time()[[3L]] - started),
    implementation = paste0("igraph::cluster_", method)
  )
}

run_cugraph_oracle <- function(graph, method, seed) {
  if (method == "walktrap") {
    stop("cuGraph does not implement Pons-Latapy Walktrap.", call. = FALSE)
  }
  if (!requireNamespace("reticulate", quietly = TRUE)) {
    stop("reticulate is unavailable.", call. = FALSE)
  }
  cugraph <- reticulate::import("cugraph", delay_load = FALSE)
  cudf <- reticulate::import("cudf", delay_load = FALSE)
  py_time <- reticulate::import("time", delay_load = FALSE)
  transfer_started <- proc.time()[[3L]]
  edge_frame <- cudf$DataFrame(reticulate::dict(
    src = as.integer(graph$from - 1L),
    dst = as.integer(graph$to - 1L),
    weight = as.numeric(graph$weight)
  ))
  gpu_graph <- cugraph$Graph(directed = FALSE)
  gpu_graph$from_cudf_edgelist(
    edge_frame,
    source = "src",
    destination = "dst",
    edge_attr = "weight",
    renumber = FALSE
  )
  transfer_sec <- unname(proc.time()[[3L]] - transfer_started)
  started <- py_time$perf_counter()
  fit <- if (method == "louvain") {
    cugraph$louvain(
      gpu_graph,
      max_level = as.integer(100L),
      resolution = resolution
    )
  } else {
    cugraph$leiden(
      gpu_graph,
      max_iter = as.integer(n_iterations),
      resolution = resolution,
      random_state = as.integer(seed)
    )
  }
  elapsed <- as.numeric(py_time$perf_counter() - started)
  parts <- fit[[1L]]$sort_values("vertex")
  membership <- as.integer(
    reticulate::py_to_r(parts[["partition"]]$to_pandas()$to_numpy())
  ) + 1L
  list(
    membership = membership,
    modularity = as.numeric(fit[[2L]]),
    n_communities = length(unique(membership)),
    connected_communities = NA,
    elapsed_sec = elapsed,
    transfer_sec = transfer_sec,
    implementation = paste0("RAPIDS cuGraph ", method)
  )
}

empty_row <- function(dataset, method, engine, seed, status, error = "") {
  requested_cluster_backend <- if (engine == "cugraph") {
    "cuda"
  } else if (engine == "fastEmbedR" && !identical(method, "walktrap")) {
    backend_group
  } else {
    "cpu"
  }
  data.frame(
    dataset = dataset,
    method = method,
    engine = engine,
    graph_backend_requested = backend_group,
    graph_backend_used = NA_character_,
    clustering_backend_requested = requested_cluster_backend,
    clustering_backend_used = NA_character_,
    requested_threads = threads,
    clustering_threads = if (engine == "cugraph") NA_integer_ else 1L,
    seed = seed,
    n_original = NA_integer_,
    n_benchmark = NA_integer_,
    p = NA_integer_,
    k = k,
    metric = metric,
    weight = weight,
    resolution = resolution,
    graph_sec = NA_real_,
    graph_peak_rss_gb = NA_real_,
    graph_gpu_memory_delta_mb = NA_real_,
    graph_reused = NA,
    cluster_sec = NA_real_,
    transfer_sec = NA_real_,
    peak_rss_gb = NA_real_,
    modularity = NA_real_,
    n_communities = NA_integer_,
    connected_communities = NA,
    label_ari = NA_real_,
    label_nmi = NA_real_,
    reference_ari = NA_real_,
    reference_nmi = NA_real_,
    modularity_delta_from_igraph = NA_real_,
    status = status,
    error_message = error,
    stringsAsFactors = FALSE
  )
}

all_rows <- list()
row_index <- 0L
for (dataset in datasets) {
  log_message("Loading %s", dataset)
  loaded <- tryCatch(load_dataset(dataset), error = identity)
  if (inherits(loaded, "error")) {
    for (method in methods) for (engine in c("fastEmbedR", "igraph")) for (seed in seeds) {
      row_index <- row_index + 1L
      all_rows[[row_index]] <- empty_row(
        dataset, method, engine, seed, "failed", conditionMessage(loaded)
      )
    }
    next
  }
  x <- loaded$data
  labels <- loaded$labels
  n_original <- nrow(x)
  rows <- stratified_rows(labels, n_original, max_n, seeds[[1L]])
  if (length(rows) < n_original) {
    x <- x[rows, , drop = FALSE]
    if (!is.null(labels)) labels <- labels[rows]
  }
  n <- nrow(x)
  p <- ncol(x)
  if (!is.null(labels)) labels <- as.factor(labels)

  graph_id <- paste(
    dataset, backend_group, paste0("t", threads), paste0("k", k),
    metric, weight, paste0("n", n), sep = "_"
  )
  graph_path <- file.path(input_root, paste0(graph_id, ".rds"))
  graph_reused <- file.exists(graph_path) && !force
  graph_before_gpu <- gpu_used_mb()
  graph_started <- proc.time()[[3L]]
  graph <- tryCatch({
    if (graph_reused) {
      readRDS(graph_path)
    } else {
      value <- fastEmbedR::knn_graph(
        x,
        k = k,
        backend = backend_group,
        metric = metric,
        weight = weight,
        n.cores = threads
      )
      saveRDS(value, graph_path, compress = FALSE)
      value
    }
  }, error = identity)
  graph_sec <- unname(proc.time()[[3L]] - graph_started)
  graph_after_gpu <- gpu_used_mb()
  graph_gpu_delta <- if (
    is.finite(graph_before_gpu) && is.finite(graph_after_gpu)
  ) max(0, graph_after_gpu - graph_before_gpu) else NA_real_
  graph_rss <- peak_rss_gb()
  if (inherits(graph, "error")) {
    for (method in methods) for (engine in c("fastEmbedR", "igraph")) for (seed in seeds) {
      row_index <- row_index + 1L
      all_rows[[row_index]] <- empty_row(
        dataset, method, engine, seed, "failed", conditionMessage(graph)
      )
    }
    next
  }
  graph_backend_used <- graph$parameters$knn_backend %||% backend_group
  log_message(
    "%s graph ready: n=%d p=%d edges=%d backend=%s %.3fs",
    dataset, n, p, graph$n_edges, graph_backend_used, graph_sec
  )

  if (!requireNamespace("igraph", quietly = TRUE)) {
    stop("The clustering validation requires the igraph reference package.", call. = FALSE)
  }
  igraph_graph <- as_igraph(graph)
  for (method in methods) {
    if (method == "walktrap" && n > walktrap_max_n) {
      for (engine in c("fastEmbedR", "igraph")) for (seed in seeds) {
        row_index <- row_index + 1L
        row <- empty_row(
          dataset, method, engine, seed, "not_supported",
          sprintf("Walktrap validation is limited to n <= %d.", walktrap_max_n)
        )
        row$n_original <- n_original
        row$n_benchmark <- n
        row$p <- p
        row$graph_backend_used <- graph_backend_used
        row$graph_sec <- graph_sec
        row$graph_reused <- graph_reused
        row$graph_peak_rss_gb <- graph_rss
        row$graph_gpu_memory_delta_mb <- graph_gpu_delta
        all_rows[[row_index]] <- row
      }
      next
    }
    for (seed in seeds) {
      fits <- list()
      fits$fastEmbedR <- tryCatch(run_native(graph, method, seed), error = identity)
      fits$igraph <- tryCatch(run_igraph(igraph_graph, method, seed), error = identity)
      if (run_cugraph && method != "walktrap") {
        fits$cugraph <- tryCatch(
          run_cugraph_oracle(graph, method, seed),
          error = identity
        )
      }
      reference <- fits$igraph
      for (engine in names(fits)) {
        fit <- fits[[engine]]
        row_index <- row_index + 1L
        if (inherits(fit, "error")) {
          row <- empty_row(
            dataset, method, engine, seed, "failed", conditionMessage(fit)
          )
        } else {
          membership_path <- file.path(
            out_dir,
            "memberships",
            paste(dataset, method, engine, paste0("seed", seed), sep = "_")
          )
          saveRDS(fit$membership, paste0(membership_path, ".rds"), compress = FALSE)
          row <- empty_row(dataset, method, engine, seed, "success")
          row$clustering_backend_used <- fit$backend_used %||%
            if (engine == "cugraph") "cuda" else "cpu"
          row$cluster_sec <- fit$elapsed_sec
          row$transfer_sec <- fit$transfer_sec %||% 0
          row$peak_rss_gb <- peak_rss_gb()
          row$modularity <- fit$modularity
          row$n_communities <- fit$n_communities
          row$connected_communities <- fit$connected_communities
          row$label_ari <- adjusted_rand_index(fit$membership, labels)
          row$label_nmi <- normalized_mutual_information(fit$membership, labels)
          if (!inherits(reference, "error")) {
            row$reference_ari <- adjusted_rand_index(
              fit$membership, reference$membership
            )
            row$reference_nmi <- normalized_mutual_information(
              fit$membership, reference$membership
            )
            row$modularity_delta_from_igraph <-
              fit$modularity - reference$modularity
          }
        }
        row$n_original <- n_original
        row$n_benchmark <- n
        row$p <- p
        row$graph_backend_used <- graph_backend_used
        row$graph_sec <- graph_sec
        row$graph_reused <- graph_reused
        row$graph_peak_rss_gb <- graph_rss
        row$graph_gpu_memory_delta_mb <- graph_gpu_delta
        all_rows[[row_index]] <- row
      }
      log_message("%s/%s/seed%d complete", dataset, method, seed)
    }
  }
  rm(x, graph, igraph_graph)
  gc()
}

results <- do.call(rbind, all_rows)
write.csv(
  results,
  file.path(out_dir, "clustering_validation_runs.csv"),
  row.names = FALSE,
  na = ""
)

successful <- results[results$status == "success", , drop = FALSE]
if (nrow(successful)) {
  key <- interaction(
    successful$dataset,
    successful$method,
    successful$engine,
    successful$graph_backend_requested,
    successful$requested_threads,
    drop = TRUE
  )
  summary <- do.call(rbind, lapply(split(successful, key), function(x) {
    summarize <- function(value) {
      value <- suppressWarnings(as.numeric(value))
      value <- value[is.finite(value)]
      if (!length(value)) return(c(median = NA, q1 = NA, q3 = NA))
      c(
        median = median(value),
        q1 = unname(quantile(value, 0.25)),
        q3 = unname(quantile(value, 0.75))
      )
    }
    runtime <- summarize(x$cluster_sec)
    data.frame(
      dataset = x$dataset[[1L]],
      method = x$method[[1L]],
      engine = x$engine[[1L]],
      graph_backend_requested = x$graph_backend_requested[[1L]],
      graph_backend_used = x$graph_backend_used[[1L]],
      clustering_backend_used = x$clustering_backend_used[[1L]],
      requested_threads = x$requested_threads[[1L]],
      clustering_threads = x$clustering_threads[[1L]],
      n_benchmark = x$n_benchmark[[1L]],
      n_runs = nrow(x),
      graph_sec = median(x$graph_sec, na.rm = TRUE),
      cluster_sec_median = runtime[["median"]],
      cluster_sec_q1 = runtime[["q1"]],
      cluster_sec_q3 = runtime[["q3"]],
      modularity_median = median(x$modularity, na.rm = TRUE),
      label_ari_median = median(x$label_ari, na.rm = TRUE),
      label_nmi_median = median(x$label_nmi, na.rm = TRUE),
      reference_ari_median = median(x$reference_ari, na.rm = TRUE),
      reference_nmi_median = median(x$reference_nmi, na.rm = TRUE),
      modularity_delta_from_igraph_median =
        median(x$modularity_delta_from_igraph, na.rm = TRUE),
      stringsAsFactors = FALSE
    )
  }))
  rownames(summary) <- NULL
  write.csv(
    summary,
    file.path(out_dir, "clustering_validation_summary.csv"),
    row.names = FALSE,
    na = ""
  )
}

capture.output(
  {
    cat("fastEmbedR clustering validation\n")
    cat("Generated:", format(Sys.time(), tz = "UTC"), "UTC\n")
    cat("Backend group:", backend_group, "\n")
    cat("Requested CPU threads:", threads, "\n")
    cat("Louvain/Leiden use the requested native fastEmbedR clustering backend.\n")
    cat("Walktrap is explicitly CPU-only; GPU requests are not relabeled.\n")
    cat("Optional cuGraph rows are external benchmark oracles only.\n\n")
    print(sessionInfo())
    if (backend_group == "cuda") {
      cat("\nNVIDIA information\n")
      print(try(system2("nvidia-smi", stdout = TRUE, stderr = TRUE), silent = TRUE))
    }
  },
  file = file.path(out_dir, "reproducibility.txt")
)

log_message("Finished. Results: %s", out_dir)
