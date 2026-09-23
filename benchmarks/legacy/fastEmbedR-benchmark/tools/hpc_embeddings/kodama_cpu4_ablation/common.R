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

script_file <- function() {
  z <- sub("^--file=", "", commandArgs(FALSE)[grepl("^--file=", commandArgs(FALSE))])
  if (!length(z)) stop("Cannot identify the running script.")
  normalizePath(z[[1L]], mustWork = TRUE)
}

suite_dir <- function() dirname(script_file())
safe_name <- function(x) gsub("[^A-Za-z0-9_.-]", "_", x)
as_int <- function(x, default) {
  out <- suppressWarnings(as.integer(x %||% default))
  if (is.na(out)) as.integer(default) else out
}

sha256 <- function(path) {
  if (!file.exists(path)) return(NA_character_)
  z <- system2("sha256sum", path, stdout = TRUE, stderr = TRUE)
  if (!length(z)) return(NA_character_)
  strsplit(z[[1L]], "[[:space:]]+")[[1L]][[1L]]
}

atomic_save_rds <- function(x, path) {
  dir.create(dirname(path), recursive = TRUE, showWarnings = FALSE)
  tmp <- paste0(path, ".tmp.", Sys.getpid())
  saveRDS(x, tmp, compress = FALSE)
  if (!file.rename(tmp, path)) stop("Atomic rename failed: ", path)
}

atomic_write_csv <- function(x, path) {
  dir.create(dirname(path), recursive = TRUE, showWarnings = FALSE)
  tmp <- paste0(path, ".tmp.", Sys.getpid())
  write.csv(x, tmp, row.names = FALSE, na = "")
  if (!file.rename(tmp, path)) stop("Atomic rename failed: ", path)
}

atomic_write_lines <- function(x, path) {
  dir.create(dirname(path), recursive = TRUE, showWarnings = FALSE)
  tmp <- paste0(path, ".tmp.", Sys.getpid())
  writeLines(x, tmp)
  if (!file.rename(tmp, path)) stop("Atomic rename failed: ", path)
}

load_registry <- function(path = file.path(suite_dir(), "datasets.csv")) {
  x <- read.csv(path, stringsAsFactors = FALSE)
  x[x$enabled, , drop = FALSE]
}

load_dataset <- function(dataset, representation, data_root) {
  reg <- load_registry()
  row <- reg[reg$dataset == dataset & reg$representation == representation, , drop = FALSE]
  if (nrow(row) != 1L) stop("Dataset/representation is absent or duplicated: ", dataset, "/", representation)
  path <- file.path(data_root, row$relative_path)
  if (!file.exists(path)) stop("Dataset file not found: ", path)
  env <- new.env(parent = emptyenv())
  loaded <- load(path, envir = env)
  candidates <- mget(loaded, env, inherits = FALSE)
  obj <- if ("dataset" %in% names(candidates)) candidates$dataset else {
    hit <- candidates[vapply(candidates, function(z) is.list(z) && !is.null(z$data), logical(1))]
    if (length(hit)) hit[[1L]] else NULL
  }
  if (is.null(obj)) stop("No list containing $data in ", path)
  x <- as.matrix(obj$data)
  storage.mode(x) <- "double"
  if (!nrow(x) || !ncol(x) || any(!is.finite(x))) stop("Invalid matrix in ", path)
  labels <- obj$labels %||% obj$label %||% NULL
  if (!is.null(labels)) {
    if (length(labels) != nrow(x)) stop("Label length mismatch in ", path)
    labels <- factor(labels)
  }
  list(x = x, labels = labels, path = normalizePath(path), file_sha256 = sha256(path),
       label_sha256 = if (is.null(labels)) NA_character_ else {
         f <- tempfile(); saveRDS(labels, f); on.exit(unlink(f), add = TRUE); sha256(f)
       })
}

release_info <- function(image) {
  pkg <- function(x) if (requireNamespace(x, quietly = TRUE)) as.character(packageVersion(x)) else NA_character_
  list(
    timestamp = format(Sys.time(), "%Y-%m-%dT%H:%M:%S%z"),
    image = normalizePath(image, mustWork = TRUE),
    image_sha256 = sha256(image),
    kodamaR_version = pkg("kodamaR"),
    fastEmbedR_version = pkg("fastEmbedR"),
    r_version = R.version.string,
    host = Sys.info()[["nodename"]],
    os = paste(Sys.info()[c("sysname", "release", "machine")], collapse = " "),
    cpu = paste(system2("bash", c("-lc", shQuote("lscpu 2>/dev/null | tr '\\n' ';'")), stdout = TRUE), collapse = ""),
    environment = as.list(Sys.getenv(c("OMP_NUM_THREADS", "OPENBLAS_NUM_THREADS", "MKL_NUM_THREADS",
                                         "VECLIB_MAXIMUM_THREADS", "NUMEXPR_NUM_THREADS"), unset = ""))
  )
}

expected_policy_names <- c("full", "no_prediction_guidance", "fixed_proposal_budget",
  "no_transition_proposal", "greedy_acceptance", "raw_cv_score",
  "no_pls_transition_coarsening", "no_pls_fragmentation_penalty")

check_protocol_api <- function(strict = TRUE) {
  if (!requireNamespace("kodamaR", quietly = TRUE)) stop("kodamaR is not installed.")
  f <- names(formals(kodamaR::KODAMA.matrix))
  policy_arg <- intersect(c("evolution.policy", "evolution_policy"), f)
  required <- c("data", "graph", "M", "Tcycle", "ncomp", "landmarks", "splitting",
                "n.cores", "graph.neighbors", "knn.k", "classifier", "backend", "seed")
  status <- data.frame(
    requirement = c(required, "folds", "named evolution policy"),
    available = c(required %in% f, "folds" %in% f, length(policy_arg) == 1L),
    stringsAsFactors = FALSE
  )
  if (strict && any(!status$available)) {
    stop("Installed kodamaR does not implement the frozen protocol API: ",
         paste(status$requirement[!status$available], collapse = ", "),
         ". Do not run surrogate ablations.")
  }
  list(status = status, policy_arg = if (length(policy_arg)) policy_arg[[1L]] else NA_character_)
}

extract_layout <- function(x) {
  if (is.matrix(x)) return(x[, 1:2, drop = FALSE])
  for (nm in c("layout", "embedding", "Y", "coordinates")) {
    if (!is.null(x[[nm]])) return(as.matrix(x[[nm]])[, 1:2, drop = FALSE])
  }
  stop("No 2D layout found.")
}

ari <- function(a, b) {
  if (is.null(a) || is.null(b) || length(a) != length(b)) return(NA_real_)
  tab <- table(a, b); n <- sum(tab); c2 <- function(z) z * (z - 1) / 2
  index <- sum(c2(tab)); rows <- sum(c2(rowSums(tab))); cols <- sum(c2(colSums(tab)))
  expected <- rows * cols / c2(n); limit <- (rows + cols) / 2
  if (limit == expected) as.numeric(index == expected) else (index - expected) / (limit - expected)
}

information_metrics <- function(a, b) {
  if (is.null(a) || is.null(b)) return(c(nmi = NA, homogeneity = NA, completeness = NA, v_measure = NA))
  tab <- table(a, b); p <- tab / sum(tab); pa <- rowSums(p); pb <- colSums(p)
  nz <- which(p > 0, arr.ind = TRUE)
  mi <- sum(vapply(seq_len(nrow(nz)), function(i) {
    r <- nz[i, 1]; c <- nz[i, 2]; p[r, c] * log(p[r, c] / (pa[r] * pb[c]))
  }, numeric(1)))
  h <- function(z) -sum(z[z > 0] * log(z[z > 0]))
  ha <- h(pa); hb <- h(pb)
  hom <- if (ha == 0) 1 else mi / ha; comp <- if (hb == 0) 1 else mi / hb
  c(nmi = if (ha + hb == 0) 1 else 2 * mi / (ha + hb), homogeneity = hom,
    completeness = comp, v_measure = if (hom + comp == 0) 0 else 2 * hom * comp / (hom + comp))
}

quality_metrics <- function(x, y, labels, seed, sample_n = 5000L) {
  set.seed(seed + 7919L)
  rows <- if (nrow(x) <= sample_n) seq_len(nrow(x)) else sort(sample.int(nrow(x), sample_n))
  out <- c(trust15 = NA, trust30 = NA, preserve15 = NA, preserve30 = NA,
           label_knn15 = NA, label_knn30 = NA, silhouette = NA, distance_spearman = NA)
  if (requireNamespace("fastEmbedR", quietly = TRUE)) {
    for (k in c(15L, 30L)) {
      z <- tryCatch(fastEmbedR::evaluate_embedding(x[rows, , drop = FALSE], y[rows, , drop = FALSE],
        labels = if (is.null(labels)) NULL else labels[rows], k = min(k, length(rows) - 1L),
        seed = seed, n.cores = 1L), error = function(e) NULL)
      if (!is.null(z) && nrow(z)) {
        pick <- function(nms) { h <- intersect(nms, names(z)); if (length(h)) as.numeric(z[[h[[1L]]]][[1L]]) else NA_real_ }
        out[paste0("trust", k)] <- pick("trustworthiness")
        out[paste0("preserve", k)] <- pick(c(paste0("knn_preservation_", k), "knn_preservation"))
        out[paste0("label_knn", k)] <- pick(c("label_knn_accuracy", "nn_accuracy"))
        if (k == 30L) out["silhouette"] <- pick("silhouette")
      }
    }
  }
  s <- if (length(rows) <= 2000L) seq_along(rows) else sort(sample.int(length(rows), 2000L))
  out["distance_spearman"] <- suppressWarnings(cor(as.vector(dist(x[rows[s], , drop = FALSE])),
    as.vector(dist(y[rows[s], , drop = FALSE])), method = "spearman"))
  out
}

fit_diagnostics <- function(fit) {
  acc <- as.numeric(fit$acc %||% numeric())
  classes <- if (!is.null(fit$res)) apply(as.matrix(fit$res), 1L, function(z) length(unique(z))) else numeric()
  q <- function(z, fun) if (length(z)) fun(z, na.rm = TRUE) else NA_real_
  data.frame(
    cv_initial = if (length(acc)) acc[[1L]] else NA_real_, cv_best = q(acc, max), cv_mean = q(acc, mean),
    cv_median = q(acc, median), cv_sd = q(acc, sd), cv_iqr = q(acc, IQR), cv_min = q(acc, min), cv_max = q(acc, max),
    selected_classes = length(unique(fit$best_labels %||% integer())), classes_median = q(classes, median),
    classes_iqr = q(classes, IQR), collapse_one_rate = q(classes <= 1, mean), collapse_two_rate = q(classes <= 2, mean),
    distinct_solutions = if (!is.null(fit$res)) nrow(unique(as.data.frame(as.matrix(fit$res)))) else NA_integer_,
    stringsAsFactors = FALSE
  )
}

timing_rows <- function(fit, wall, graph_seconds = 0) {
  t <- fit$timing %||% list()
  data.frame(stage = c("graph_reused", "matrix_wall", names(t)),
    seconds = c(graph_seconds, wall, as.numeric(unlist(t, use.names = FALSE))), stringsAsFactors = FALSE)
}
