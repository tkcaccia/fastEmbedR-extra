`%||%` <- function(x, y) if (is.null(x) || !length(x)) y else x

parse_cli <- function(x = commandArgs(trailingOnly = TRUE)) {
  out <- list()
  for (arg in x) {
    if (!startsWith(arg, "--")) next
    z <- strsplit(sub("^--", "", arg), "=", fixed = TRUE)[[1L]]
    out[[gsub("-", "_", z[[1L]])]] <- if (length(z) == 1L) TRUE else paste(z[-1L], collapse = "=")
  }
  out
}
as_int <- function(x, d) { z <- suppressWarnings(as.integer(x %||% d)); if (is.na(z)) as.integer(d) else z }
as_num <- function(x, d) { z <- suppressWarnings(as.numeric(x %||% d)); if (!is.finite(z)) as.numeric(d) else z }
as_flag <- function(x, d = FALSE) if (is.null(x)) d else tolower(as.character(x)) %in% c("1", "true", "yes")
split_int <- function(x, d) as.integer(strsplit(as.character(x %||% d), ",", fixed = TRUE)[[1L]])
safe_name <- function(x) gsub("[^A-Za-z0-9_.-]", "_", x)

script_path <- function() {
  a <- commandArgs(FALSE)
  hit <- sub("^--file=", "", a[grepl("^--file=", a)])
  if (length(hit)) normalizePath(hit[[1L]], mustWork = TRUE) else normalizePath(".")
}
suite_dir <- function() dirname(script_path())

sha256 <- function(path) {
  if (!file.exists(path)) return(NA_character_)
  out <- suppressWarnings(system2("sha256sum", shQuote(path), stdout = TRUE, stderr = TRUE))
  if (!length(out)) return(NA_character_)
  strsplit(out[[1L]], "[[:space:]]+")[[1L]][[1L]]
}

read_release_lock <- function(path, image = NULL) {
  if (!file.exists(path)) stop("Release lock not found: ", path)
  x <- read.csv(path, stringsAsFactors = FALSE, check.names = FALSE)
  if (nrow(x) != 1L) stop("Release lock must contain exactly one row.")
  required <- c("release_version", "core_tag", "core_commit", "r_tag", "r_commit",
                "python_tag", "python_commit", "core_archive", "core_archive_sha256",
                "r_archive", "r_archive_sha256", "python_archive", "python_archive_sha256",
                "container_path", "container_sha256")
  if (length(setdiff(required, names(x)))) stop("Release lock is missing required columns.")
  bad <- vapply(x[required], function(z) is.na(z[[1L]]) || !nzchar(z[[1L]]) || z[[1L]] == "REQUIRED", logical(1))
  if (any(bad)) stop("Unfrozen release lock fields: ", paste(required[bad], collapse = ", "))
  files <- c(core_archive = x$core_archive, r_archive = x$r_archive, python_archive = x$python_archive,
             container = image %||% x$container_path)
  expected <- c(x$core_archive_sha256, x$r_archive_sha256, x$python_archive_sha256, x$container_sha256)
  observed <- vapply(files, sha256, character(1))
  if (any(is.na(observed)) || any(tolower(observed) != tolower(expected))) {
    stop("Release archive/container SHA-256 mismatch. Refusing to benchmark mutable inputs.")
  }
  x$validated_at <- format(Sys.time(), "%Y-%m-%dT%H:%M:%S%z")
  x
}

api_capabilities <- function() {
  if (!requireNamespace("kodamaR", quietly = TRUE)) stop("kodamaR is not installed.")
  matrix_args <- names(formals(kodamaR::KODAMA.matrix))
  graph_args <- names(formals(kodamaR::KODAMA.graph))
  data.frame(
    capability = c("folds", "ablation", "landmark.selection", "search.mode"),
    available = c("folds" %in% matrix_args, "ablation" %in% matrix_args,
                  "landmark.selection" %in% matrix_args, "search.mode" %in% graph_args),
    required_for = c("confirmatory", "ablation", "landmark sampling", "backend parity"),
    stringsAsFactors = FALSE
  )
}

require_capability <- function(name) {
  caps <- api_capabilities()
  ok <- caps$available[caps$capability == name]
  if (!length(ok) || !ok) stop("Required public KODAMA capability is absent: ", name,
    ". Update the wrapper; do not approximate this experiment in the benchmark script.")
}

load_registry <- function(path = file.path(suite_dir(), "datasets.csv")) {
  x <- read.csv(path, stringsAsFactors = FALSE)
  x[x$enabled, , drop = FALSE]
}

load_dataset <- function(dataset, data_root, registry = load_registry()) {
  row <- registry[registry$dataset == dataset, , drop = FALSE]
  if (nrow(row) != 1L) stop("Dataset is absent or duplicated in registry: ", dataset)
  path <- file.path(data_root, row$relative_path)
  if (!file.exists(path)) stop("Dataset file not found: ", path)
  env <- new.env(parent = emptyenv()); loaded <- load(path, envir = env)
  obj <- if ("dataset" %in% loaded) env$dataset else {
    vals <- mget(loaded, env, inherits = FALSE)
    hit <- vals[vapply(vals, function(z) is.list(z) && !is.null(z$data), logical(1))]
    if (length(hit)) hit[[1L]] else NULL
  }
  if (is.null(obj)) stop("No dataset list with $data in ", path)
  x <- if (inherits(obj$data, "float32")) as.matrix(obj$data) else as.matrix(obj$data)
  storage.mode(x) <- "double"
  if (anyNA(x) || any(!is.finite(x))) stop("Non-finite input in ", dataset)
  labels <- obj$labels %||% obj$label %||% NULL
  if (!is.null(labels)) labels <- factor(labels)
  if (!is.null(labels) && length(labels) != nrow(x)) stop("Label length mismatch.")
  list(x = x, labels = labels, path = normalizePath(path), n = nrow(x), p = ncol(x))
}

extract_layout <- function(z) {
  if (is.matrix(z)) y <- z else {
    keys <- c("layout", "embedding", "Y", "y", "coordinates")
    key <- keys[vapply(keys, function(k) !is.null(z[[k]]), logical(1))]
    if (!length(key)) stop("Embedding result has no recognized layout.")
    y <- as.matrix(z[[key[[1L]]]])
  }
  if (ncol(y) < 2L || any(!is.finite(y))) stop("Invalid embedding layout.")
  y[, 1:2, drop = FALSE]
}

ari <- function(a, b) {
  if (is.null(a) || is.null(b) || length(a) != length(b)) return(NA_real_)
  tab <- table(factor(a), factor(b)); n <- sum(tab); c2 <- function(z) z * (z - 1) / 2
  i <- sum(c2(tab)); r <- sum(c2(rowSums(tab))); c <- sum(c2(colSums(tab))); t <- c2(n)
  e <- r * c / t; m <- (r + c) / 2
  if (m == e) as.numeric(i == e) else (i - e) / (m - e)
}

sample_rows <- function(n, size, seed) { if (n <= size) seq_len(n) else { set.seed(seed); sort(sample.int(n, size)) } }

layout_metrics <- function(x, y, labels, seed, k = 30L, sample_n = 5000L) {
  rows <- sample_rows(nrow(x), min(sample_n, nrow(x)), seed + 9001L)
  out <- list(trustworthiness = NA_real_, preserve30 = NA_real_, silhouette = NA_real_,
              label_knn_accuracy = NA_real_, distance_spearman = NA_real_)
  if (requireNamespace("fastEmbedR", quietly = TRUE)) {
    q <- tryCatch(fastEmbedR::evaluate_embedding(x[rows,,drop=FALSE], y[rows,,drop=FALSE],
      labels = if (is.null(labels)) NULL else labels[rows], k = min(k, length(rows)-1L),
      seed = seed, n.cores = 1L), error = function(e) NULL)
    if (!is.null(q) && nrow(q)) {
      get1 <- function(primary, alternate = NULL) {
        z <- if (primary %in% names(q)) q[[primary]] else if (!is.null(alternate) && alternate %in% names(q)) q[[alternate]] else NA_real_
        suppressWarnings(as.numeric(z[[1L]]))
      }
      out$trustworthiness <- get1("trustworthiness")
      out$preserve30 <- get1("knn_preservation_30", "knn_preservation")
      out$silhouette <- get1("silhouette")
      out$label_knn_accuracy <- get1("label_knn_accuracy", "nn_accuracy")
    }
  }
  g <- sample_rows(length(rows), min(2000L, length(rows)), seed + 17L)
  out$distance_spearman <- suppressWarnings(cor(as.vector(dist(x[rows[g],,drop=FALSE])),
    as.vector(dist(y[rows[g],,drop=FALSE])), method = "spearman"))
  out
}

run_timed <- function(expr) {
  gc(); start <- proc.time(); value <- force(expr); elapsed <- (proc.time() - start)[["elapsed"]]
  list(value = value, elapsed = unname(elapsed))
}

fit_accuracy <- function(fit) {
  a <- suppressWarnings(as.numeric(fit$acc %||% fit$accuracy %||% NA_real_))
  c(best = if (any(is.finite(a))) max(a, na.rm = TRUE) else NA_real_,
    median = if (any(is.finite(a))) median(a, na.rm = TRUE) else NA_real_)
}

active_classes <- function(fit) length(unique(as.integer(fit$best_labels %||% integer())))

write_manifest <- function(dir, lock, dataset, backend, seed, extra = list()) {
  dir.create(dir, recursive = TRUE, showWarnings = FALSE)
  hw <- list(timestamp = format(Sys.time(), "%Y-%m-%dT%H:%M:%S%z"),
    host = Sys.info()[["nodename"]], os = paste(Sys.info()[c("sysname", "release", "machine")], collapse = " "),
    r = R.version.string, cpu = paste(system2("sh", c("-c", shQuote("lscpu 2>/dev/null | head -n 20")), stdout=TRUE), collapse=" | "),
    gpu = paste(system2("sh", c("-c", shQuote("nvidia-smi --query-gpu=name,driver_version,memory.total,compute_cap --format=csv,noheader 2>/dev/null || true")), stdout=TRUE), collapse=" | "))
  saveRDS(c(list(release = lock, dataset = dataset, backend = backend, seed = seed, hardware = hw), extra),
          file.path(dir, "run_manifest.rds"))
  capture.output(sessionInfo(), file = file.path(dir, "sessionInfo.txt"))
}

classic_embedding <- function(x, method, backend, ncores, seed) {
  if (!requireNamespace("fastEmbedR", quietly = TRUE)) stop("fastEmbedR is required.")
  set.seed(seed)
  if (method == "UMAP") {
    extract_layout(fastEmbedR::umap(x, n_neighbors = 30L, graph_mode = "fuzzy", backend = backend,
                                    n.cores = ncores, seed = seed))
  } else {
    extract_layout(fastEmbedR::opentsne(x, perplexity = 30, backend = backend,
                                        n.cores = ncores, seed = seed))
  }
}

kodama_embedding <- function(fit, method, backend, ncores, seed) {
  extract_layout(kodamaR::KODAMA.visualization(fit, method = method, k = 30L,
    perplexity = 30, graph.mode = "fuzzy", backend = backend, n.cores = ncores, seed = seed))
}

result_row <- function(dataset, seed, classifier, method, variant, backend, data, fit,
                       layout, runtime, graph_runtime, metrics) {
  acc <- if (is.null(fit)) c(best=NA, median=NA) else fit_accuracy(fit)
  data.frame(dataset=dataset, seed=seed, classifier=classifier, visualization=method,
    variant=variant, backend=backend, status="success", error=NA_character_, n=data$n, p=data$p,
    M=if (is.null(fit)) NA else 100L, Tcycle=if (is.null(fit)) NA else 100L, folds=5L,
    splitting=if (data$n < 40000) 100L else 300L, knn_k=30L, ncomp=50L,
    graph_runtime_sec=graph_runtime, workflow_runtime_sec=runtime,
    best_cv_accuracy=acc[["best"]], median_cv_accuracy=acc[["median"]],
    active_classes=if (is.null(fit)) NA_integer_ else active_classes(fit),
    ari=if (is.null(fit)) NA_real_ else ari(data$labels, fit$best_labels),
    trustworthiness=metrics$trustworthiness, preserve30=metrics$preserve30,
    silhouette=metrics$silhouette, label_knn_accuracy=metrics$label_knn_accuracy,
    distance_spearman=metrics$distance_spearman, stringsAsFactors=FALSE)
}
