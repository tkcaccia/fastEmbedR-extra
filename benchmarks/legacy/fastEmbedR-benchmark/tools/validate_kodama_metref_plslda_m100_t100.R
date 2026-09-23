#!/usr/bin/env Rscript

args <- commandArgs(trailingOnly = TRUE)
if (length(args) < 3L) {
  stop(
    "Usage: validate_kodama_metref_plslda_m100_t100.R OUTPUT_DIR DATA_FILE BACKEND",
    call. = FALSE
  )
}

output_dir <- args[[1L]]
data_file <- args[[2L]]
backend <- match.arg(tolower(args[[3L]]), c("cpu", "cuda"))
n_cores <- 4L
kodama_r_lib <- Sys.getenv("KODAMA_R_LIB", unset = "")
if (nzchar(kodama_r_lib)) {
  .libPaths(c(kodama_r_lib, .libPaths()))
}

dir.create(output_dir, recursive = TRUE, showWarnings = FALSE)
dir.create(file.path(output_dir, "objects"), recursive = TRUE, showWarnings = FALSE)
dir.create(file.path(output_dir, "plots"), recursive = TRUE, showWarnings = FALSE)

library(kodamaR)
library(fastEmbedR)

loaded <- new.env(parent = emptyenv())
load(data_file, envir = loaded)
if (!exists("dataset", envir = loaded, inherits = FALSE)) {
  stop("The input RData file must contain `dataset`.", call. = FALSE)
}
dataset <- get("dataset", envir = loaded, inherits = FALSE)
x <- dataset$data
if (inherits(x, "float32") || inherits(x, "float")) {
  if (!requireNamespace("float", quietly = TRUE)) {
    stop("The float package is required for the MetRef float32 input.", call. = FALSE)
  }
  x <- float::dbl(x)
}
x <- as.matrix(x)
labels <- as.factor(dataset$labels)
stopifnot(nrow(x) == length(labels), nrow(x) == 873L, ncol(x) == 375L)

parameters <- list(
  M = 100L,
  Tcycle = 100L,
  ncomp = 50L,
  landmarks = 10000000L,
  splitting = 100L,
  graph_neighbors = 100L,
  knn_k = 50L,
  visualization_k = 30L,
  perplexity = 30,
  seed = 1234L,
  metric = "euclidean",
  n_cores = n_cores,
  backend = backend
)

timestamp <- function() format(Sys.time(), "%FT%T%z")
log_stage <- function(...) {
  message(timestamp(), " ", sprintf(...))
  flush.console()
}

as_layout <- function(value) {
  if (is.matrix(value)) {
    return(value[, seq_len(min(2L, ncol(value))), drop = FALSE])
  }
  for (name in c("layout", "Y", "embedding", "coordinates")) {
    candidate <- value[[name]]
    if (!is.null(candidate)) {
      candidate <- as.matrix(candidate)
      return(candidate[, seq_len(min(2L, ncol(candidate))), drop = FALSE])
    }
  }
  candidate <- as.matrix(value)
  candidate[, seq_len(min(2L, ncol(candidate))), drop = FALSE]
}

stored_init <- function(fit, method) {
  if (!is.list(fit) || is.null(fit$visual_init)) return(NULL)
  if (!is.list(fit$visual_init)) return(fit$visual_init)
  key <- if (identical(method, "UMAP")) "umap" else "opentsne"
  fit$visual_init[[key]]
}

plot_layout <- function(layout, path, title) {
  palette <- grDevices::hcl.colors(max(3L, nlevels(labels)), "Dark 3")
  colors <- palette[as.integer(labels)]
  grDevices::png(path, width = 1800, height = 1800, res = 220, bg = "white")
  on.exit(grDevices::dev.off(), add = TRUE)
  graphics::par(mar = c(0, 0, 2, 0), bty = "n", xaxs = "r", yaxs = "r")
  graphics::plot(
    layout[, 1L], layout[, 2L],
    pch = 16, cex = 0.8, col = colors,
    axes = FALSE, ann = FALSE, frame.plot = FALSE
  )
  graphics::title(main = title, line = 0.2, cex.main = 0.95)
}

write_status <- function(stage, status, elapsed_sec = NA_real_, error = NA_character_) {
  path <- file.path(output_dir, "stage_status.csv")
  row <- data.frame(
    timestamp = timestamp(),
    backend = backend,
    stage = stage,
    status = status,
    elapsed_sec = elapsed_sec,
    error = error,
    stringsAsFactors = FALSE
  )
  utils::write.table(
    row, path,
    sep = ",", row.names = FALSE,
    col.names = !file.exists(path), append = file.exists(path),
    qmethod = "double"
  )
}

writeLines(
  c(
    paste0("data_file=", normalizePath(data_file)),
    paste0("output_dir=", normalizePath(output_dir)),
    paste0("backend=", backend),
    paste0("n=", nrow(x)),
    paste0("p=", ncol(x)),
    paste0("classes=", nlevels(labels)),
    vapply(names(parameters), function(name) {
      paste0(name, "=", parameters[[name]])
    }, character(1L))
  ),
  file.path(output_dir, "run_manifest.txt")
)

set.seed(parameters$seed)
log_stage(
  "PLS-LDA core start: backend=%s M=%d Tcycle=%d ncomp=%d landmarks=%d",
  backend, parameters$M, parameters$Tcycle, parameters$ncomp,
  parameters$landmarks
)
core_error <- NULL
core_time <- system.time({
  fit <- tryCatch(
    KODAMA.matrix(
      data = x,
      M = parameters$M,
      Tcycle = parameters$Tcycle,
      ncomp = parameters$ncomp,
      landmarks = parameters$landmarks,
      splitting = parameters$splitting,
      n.cores = parameters$n_cores,
      graph.neighbors = parameters$graph_neighbors,
      knn.k = parameters$knn_k,
      metric = parameters$metric,
      classifier = "pls_lda",
      backend = backend,
      seed = parameters$seed,
      visual.init = TRUE,
      progress = FALSE,
      apply.kodama.dissimilarity = TRUE
    ),
    error = function(e) {
      core_error <<- conditionMessage(e)
      NULL
    }
  )
})
core_sec <- unname(core_time[["elapsed"]])
if (is.null(fit)) {
  write_status("KODAMA.matrix_pls_lda", "failed", core_sec, core_error)
  stop(core_error, call. = FALSE)
}
write_status("KODAMA.matrix_pls_lda", "success", core_sec)
log_stage("PLS-LDA core success: elapsed=%.3f sec", core_sec)
saveRDS(fit, file.path(output_dir, "objects", "MetRef_pls_lda_core.rds"),
        compress = FALSE)

result_rows <- list()
for (method in c("opentsne", "UMAP")) {
  set.seed(parameters$seed)
  log_stage("Visualization start: backend=%s method=%s", backend, method)
  visualization_error <- NULL
  visualization_time <- system.time({
    result <- tryCatch(
      KODAMA.visualization(
        x = fit,
        method = method,
        init = stored_init(fit, method),
        k = parameters$visualization_k,
        metric = parameters$metric,
        backend = backend,
        n.cores = parameters$n_cores,
        gpu.device = 0L,
        n.epochs = 200L,
        n.iter = 500L,
        perplexity = parameters$perplexity,
        seed = parameters$seed
      ),
      error = function(e) {
        visualization_error <<- conditionMessage(e)
        NULL
      }
    )
  })
  visualization_sec <- unname(visualization_time[["elapsed"]])
  if (is.null(result)) {
    write_status(
      paste0("KODAMA.visualization_", method),
      "failed", visualization_sec, visualization_error
    )
    result_rows[[length(result_rows) + 1L]] <- data.frame(
      backend = backend,
      classifier = "pls_lda",
      method = method,
      status = "failed",
      core_sec = core_sec,
      visualization_sec = visualization_sec,
      total_sec = core_sec + visualization_sec,
      trustworthiness = NA_real_,
      knn_preservation_15 = NA_real_,
      silhouette = NA_real_,
      label_knn_accuracy = NA_real_,
      error = visualization_error,
      stringsAsFactors = FALSE
    )
    next
  }

  layout <- as_layout(result)
  stem <- sprintf("MetRef_%s_pls_lda_%s", backend, method)
  layout_file <- file.path(output_dir, "objects", paste0(stem, "_layout.rds"))
  plot_file <- file.path(output_dir, "plots", paste0(stem, ".png"))
  metrics_file <- file.path(output_dir, paste0(stem, "_metrics.csv"))
  saveRDS(
    list(layout = layout, labels = labels, parameters = parameters),
    layout_file, compress = FALSE
  )
  plot_layout(
    layout, plot_file,
    sprintf("KODAMA PLS-LDA | %s | %s", method, backend)
  )
  metrics <- fastEmbedR::evaluate_embedding(
    x_high = x,
    embedding = layout,
    labels = labels,
    k = c(15L, 30L, 50L),
    seed = parameters$seed,
    method = paste("KODAMA PLS-LDA", method),
    backend = backend,
    dataset = "MetRef",
    n_threads = parameters$n_cores
  )
  utils::write.csv(metrics, metrics_file, row.names = FALSE)
  write_status(paste0("KODAMA.visualization_", method), "success",
               visualization_sec)
  log_stage(
    "Visualization success: method=%s elapsed=%.3f sec trust=%.4f label_acc=%.4f",
    method, visualization_sec, metrics$trustworthiness[[1L]],
    metrics$label_knn_accuracy[[1L]]
  )
  result_rows[[length(result_rows) + 1L]] <- data.frame(
    backend = backend,
    classifier = "pls_lda",
    method = method,
    status = "success",
    core_sec = core_sec,
    visualization_sec = visualization_sec,
    total_sec = core_sec + visualization_sec,
    trustworthiness = metrics$trustworthiness[[1L]],
    knn_preservation_15 = metrics$knn_preservation_15[[1L]],
    silhouette = metrics$silhouette[[1L]],
    label_knn_accuracy = metrics$label_knn_accuracy[[1L]],
    error = NA_character_,
    stringsAsFactors = FALSE
  )
}

results <- do.call(rbind, result_rows)
utils::write.csv(
  results,
  file.path(output_dir, "kodama_metref_plslda_m100_t100_results.csv"),
  row.names = FALSE
)
saveRDS(
  list(results = results, parameters = parameters),
  file.path(output_dir, "kodama_metref_plslda_m100_t100_complete.rds"),
  compress = FALSE
)
writeLines(capture.output(sessionInfo()), file.path(output_dir, "sessionInfo.txt"))
writeLines(
  capture.output(KODAMA.diagnostics()),
  file.path(output_dir, "kodama_diagnostics.txt")
)
print(results)
cat("OUTPUT_DIR=", normalizePath(output_dir), "\n", sep = "")
