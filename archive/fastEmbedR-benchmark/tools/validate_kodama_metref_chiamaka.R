#!/usr/bin/env Rscript

args <- commandArgs(trailingOnly = TRUE)
output_dir <- if (length(args) >= 1L) args[[1L]] else {
  file.path(
    "/mnt/sata_ssd/fastEmbedR/results",
    paste0("kodama_metref_", format(Sys.time(), "%Y%m%d_%H%M%S"))
  )
}
data_file <- if (length(args) >= 2L) args[[2L]] else {
  "/mnt/sata_ssd/fastEmbedR/Data/MetRef/MetRef.RData"
}

dir.create(output_dir, recursive = TRUE, showWarnings = FALSE)
dir.create(file.path(output_dir, "plots"), recursive = TRUE, showWarnings = FALSE)
dir.create(file.path(output_dir, "objects"), recursive = TRUE, showWarnings = FALSE)

library(kodamaR)
library(fastEmbedR)

load_env <- new.env(parent = emptyenv())
load(data_file, envir = load_env)
if (!exists("dataset", envir = load_env, inherits = FALSE)) {
  stop("MetRef RData must contain a `dataset` object.", call. = FALSE)
}
dataset <- get("dataset", envir = load_env, inherits = FALSE)
x <- as.matrix(dataset$data)
labels <- as.factor(dataset$labels)
stopifnot(nrow(x) == length(labels), nrow(x) > 2L, ncol(x) > 1L)

seed <- 4L
k <- min(30L, nrow(x) - 1L)
perplexity <- min(30, floor((nrow(x) - 1L) / 3L))
ncomp <- min(50L, ncol(x), nrow(x) - 1L)
landmarks <- min(10000000L, nrow(x))
graph_neighbors <- min(100L, nrow(x) - 1L)
env_int <- function(name, default) {
  value <- suppressWarnings(as.integer(Sys.getenv(name, unset = as.character(default))))
  if (is.na(value) || value < 1L) default else value
}
M <- env_int("KODAMA_M", 10L)
Tcycle <- env_int("KODAMA_TCYCLE", 10L)

as_layout <- function(x) {
  if (is.matrix(x)) return(x[, seq_len(min(2L, ncol(x))), drop = FALSE])
  for (name in c("layout", "Y", "embedding", "coordinates")) {
    value <- x[[name]]
    if (!is.null(value)) {
      value <- as.matrix(value)
      return(value[, seq_len(min(2L, ncol(value))), drop = FALSE])
    }
  }
  value <- as.matrix(x)
  value[, seq_len(min(2L, ncol(value))), drop = FALSE]
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

core_rows <- list()
run_rows <- list()
layouts <- list()

for (backend in c("cpu", "cuda")) {
  n_cores <- if (identical(backend, "cpu")) 4L else 1L
  for (classifier in c("knn", "pls_lda")) {
    message(sprintf(
      "%s core start: backend=%s classifier=%s M=%d Tcycle=%d",
      format(Sys.time(), "%FT%T%z"), backend, classifier, M, Tcycle
    ))
    set.seed(seed)
    core_time <- system.time({
      core_result <- tryCatch(
        KODAMA.matrix(
          data = x,
          M = M,
          Tcycle = Tcycle,
          ncomp = ncomp,
          landmarks = landmarks,
          n.cores = n_cores,
          graph.neighbors = graph_neighbors,
          knn.k = k,
          metric = "euclidean",
          classifier = classifier,
          backend = backend,
          seed = seed,
          visual.init = TRUE,
          progress = FALSE,
          apply.kodama.dissimilarity = TRUE
        ),
        error = function(e) e
      )
    })
    message(sprintf(
      "%s core end: backend=%s classifier=%s status=%s elapsed=%.3f",
      format(Sys.time(), "%FT%T%z"), backend, classifier,
      if (inherits(core_result, "error")) "failed" else "success",
      unname(core_time[["elapsed"]])
    ))
    core_status <- if (inherits(core_result, "error")) "failed" else "success"
    core_error <- if (inherits(core_result, "error")) {
      conditionMessage(core_result)
    } else {
      NA_character_
    }
    core_rows[[length(core_rows) + 1L]] <- data.frame(
      backend = backend,
      classifier = classifier,
      n_cores = n_cores,
      status = core_status,
      core_sec = unname(core_time[["elapsed"]]),
      error = core_error,
      stringsAsFactors = FALSE
    )
    if (inherits(core_result, "error")) next

    core_file <- file.path(
      output_dir, "objects",
      sprintf("MetRef_%s_%s_core.rds", backend, classifier)
    )
    saveRDS(core_result, core_file, compress = FALSE)

    for (method in c("opentsne", "UMAP")) {
      message(sprintf(
        "%s visualization start: backend=%s classifier=%s method=%s",
        format(Sys.time(), "%FT%T%z"), backend, classifier, method
      ))
      set.seed(seed)
      visualization_time <- system.time({
        visualization_result <- tryCatch(
          KODAMA.visualization(
            x = core_result,
            method = method,
            init = stored_init(core_result, method),
            k = k,
            metric = "euclidean",
            backend = backend,
            n.cores = n_cores,
            gpu.device = 0L,
            n.epochs = 200L,
            n.iter = 500L,
            perplexity = perplexity,
            seed = seed
          ),
          error = function(e) e
        )
      })
      message(sprintf(
        "%s visualization end: backend=%s classifier=%s method=%s status=%s elapsed=%.3f",
        format(Sys.time(), "%FT%T%z"), backend, classifier, method,
        if (inherits(visualization_result, "error")) "failed" else "success",
        unname(visualization_time[["elapsed"]])
      ))
      status <- if (inherits(visualization_result, "error")) "failed" else "success"
      error <- if (inherits(visualization_result, "error")) {
        conditionMessage(visualization_result)
      } else {
        NA_character_
      }
      layout_file <- NA_character_
      plot_file <- NA_character_
      metrics_file <- NA_character_
      trustworthiness <- NA_real_
      knn_preservation_15 <- NA_real_
      silhouette <- NA_real_
      label_knn_accuracy <- NA_real_

      if (!inherits(visualization_result, "error")) {
        layout <- as_layout(visualization_result)
        key <- sprintf("%s_%s_%s", backend, classifier, method)
        layouts[[key]] <- layout
        layout_file <- file.path(
          output_dir, "objects", sprintf("MetRef_%s_layout.rds", key)
        )
        plot_file <- file.path(
          output_dir, "plots", sprintf("MetRef_%s.png", key)
        )
        metrics_file <- file.path(
          output_dir, sprintf("MetRef_%s_metrics.csv", key)
        )
        saveRDS(
          list(
            layout = layout,
            labels = labels,
            backend = backend,
            classifier = classifier,
            method = method,
            seed = seed
          ),
          layout_file,
          compress = FALSE
        )
        plot_layout(
          layout,
          plot_file,
          sprintf("KODAMA %s | %s | %s", classifier, method, backend)
        )
        metric_row <- tryCatch(
          fastEmbedR::evaluate_embedding(
            x_high = x,
            embedding = layout,
            labels = labels,
            k = c(15L, 30L, 50L),
            seed = seed,
            method = paste("KODAMA", classifier, method),
            backend = backend,
            dataset = "MetRef",
            n_threads = n_cores
          ),
          error = function(e) data.frame(metric_error = conditionMessage(e))
        )
        write.csv(metric_row, metrics_file, row.names = FALSE)
        if (!"metric_error" %in% names(metric_row)) {
          trustworthiness <- metric_row$trustworthiness[[1L]]
          knn_preservation_15 <- metric_row$knn_preservation_15[[1L]]
          silhouette <- metric_row$silhouette[[1L]]
          label_knn_accuracy <- metric_row$label_knn_accuracy[[1L]]
        }
      }

      run_rows[[length(run_rows) + 1L]] <- data.frame(
        dataset = "MetRef",
        backend = backend,
        classifier = classifier,
        method = method,
        n = nrow(x),
        p = ncol(x),
        classes = nlevels(labels),
        seed = seed,
        k = k,
        perplexity = perplexity,
        ncomp = ncomp,
        landmarks = landmarks,
        n_cores = n_cores,
        status = status,
        core_sec = unname(core_time[["elapsed"]]),
        visualization_sec = unname(visualization_time[["elapsed"]]),
        standalone_pipeline_sec =
          unname(core_time[["elapsed"]]) + unname(visualization_time[["elapsed"]]),
        trustworthiness = trustworthiness,
        knn_preservation_15 = knn_preservation_15,
        silhouette = silhouette,
        label_knn_accuracy = label_knn_accuracy,
        layout_file = layout_file,
        plot_file = plot_file,
        metrics_file = metrics_file,
        error = error,
        stringsAsFactors = FALSE
      )
    }
    rm(core_result)
    invisible(gc())
  }
}

core_table <- do.call(rbind, core_rows)
result_table <- do.call(rbind, run_rows)
write.csv(core_table, file.path(output_dir, "kodama_metref_core_timing.csv"),
          row.names = FALSE)
write.csv(result_table, file.path(output_dir, "kodama_metref_results.csv"),
          row.names = FALSE)
saveRDS(
  list(
    results = result_table,
    core = core_table,
    layouts = layouts,
    parameters = list(
      M = M,
      Tcycle = Tcycle,
      ncomp = ncomp,
      landmarks = landmarks,
      graph_neighbors = graph_neighbors,
      k = k,
      perplexity = perplexity,
      seed = seed
    )
  ),
  file.path(output_dir, "kodama_metref_complete.rds"),
  compress = FALSE
)

writeLines(capture.output(sessionInfo()), file.path(output_dir, "sessionInfo.txt"))
writeLines(capture.output(KODAMA.diagnostics()),
           file.path(output_dir, "kodama_diagnostics.txt"))
writeLines(
  c(
    paste0("data_file=", normalizePath(data_file)),
    paste0("output_dir=", normalizePath(output_dir)),
    paste0("n=", nrow(x)),
    paste0("p=", ncol(x)),
    paste0("classes=", nlevels(labels)),
    paste0("M=", M),
    paste0("Tcycle=", Tcycle),
    paste0("ncomp=", ncomp),
    paste0("landmarks=", landmarks),
    paste0("graph_neighbors=", graph_neighbors),
    paste0("k=", k),
    paste0("perplexity=", perplexity),
    paste0("seed=", seed)
  ),
  file.path(output_dir, "run_manifest.txt")
)

print(result_table)
cat("OUTPUT_DIR=", normalizePath(output_dir), "\n", sep = "")
