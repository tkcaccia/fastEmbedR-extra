#!/usr/bin/env Rscript

args <- commandArgs(trailingOnly = TRUE)
backend <- if (length(args)) args[[1L]] else "cpu"
output_dir <- if (length(args) >= 2L) args[[2L]] else tempdir()
if (!backend %in% c("cpu", "cuda")) stop("backend must be cpu or cuda.")
dir.create(output_dir, recursive = TRUE, showWarnings = FALSE)

kodama_r_lib <- Sys.getenv("KODAMA_R_LIB", unset = "")
if (nzchar(kodama_r_lib)) {
  .libPaths(c(kodama_r_lib, .libPaths()))
}
suppressPackageStartupMessages(library(kodamaR))
set.seed(4)
n_classes <- 8L
rows_per_class <- 50L
p <- 24L
truth <- rep(seq_len(n_classes), each = rows_per_class)
centers <- matrix(stats::rnorm(n_classes * p, sd = 3), n_classes, p)
x <- centers[truth, , drop = FALSE] +
  matrix(stats::rnorm(length(truth) * p, sd = 0.35), length(truth), p)

graph_elapsed <- system.time({
  graph <- KODAMA.graph(
    x, k = 30L, backend = backend, n.cores = 4L, seed = 4L
  )
})[["elapsed"]]
stopifnot(
  inherits(graph, "kodama_graph"),
  identical(as.character(graph$backend), backend),
  identical(as.integer(graph$graph_builds), 1L)
)

graph_file <- file.path(output_dir, paste0("shared_graph_", backend, ".rds"))
saveRDS(graph, graph_file, compress = FALSE)
reloaded <- readRDS(graph_file)
stopifnot(
  inherits(reloaded, "kodama_graph"),
  identical(graph$indices, reloaded$indices),
  identical(graph$distances, reloaded$distances)
)

rows <- lapply(c("knn", "pls_lda"), function(classifier) {
  elapsed <- system.time({
    fit <- KODAMA.matrix(
      data = x,
      graph = reloaded,
      classifier = classifier,
      backend = backend,
      M = 2L,
      Tcycle = 2L,
      ncomp = 8L,
      landmarks = 160L,
      splitting = 8L,
      graph.neighbors = 30L,
      knn.k = 15L,
      n.cores = 4L,
      seed = 4L,
      visual.init = TRUE,
      progress = FALSE
    )
  })[["elapsed"]]
  stopifnot(
    identical(as.character(fit$backend), backend),
    identical(as.integer(fit$graph_builds), 0L),
    length(fit$best_labels) == nrow(x),
    all(is.finite(fit$acc))
  )
  visualization <- if (classifier == "knn") "UMAP" else "opentsne"
  layout <- KODAMA.visualization(
    fit,
    visualization,
    backend = backend,
    n.cores = 4L,
    k = 15L,
    perplexity = 15,
    n.epochs = 20L,
    n.iter = 50L,
    seed = 4L
  )
  if (!is.matrix(layout)) {
    for (name in c("layout", "embedding", "Y")) {
      if (!is.null(layout[[name]]) && is.matrix(layout[[name]])) {
        layout <- layout[[name]]
        break
      }
    }
  }
  stopifnot(
    is.matrix(layout), identical(dim(layout), c(nrow(x), 2L)),
    all(is.finite(layout))
  )
  data.frame(
    backend = backend,
    classifier = classifier,
    graph_builds = fit$graph_builds,
    graph_elapsed_sec = unname(graph_elapsed),
    matrix_elapsed_sec = unname(elapsed),
    best_accuracy = max(fit$acc),
    layout_rows = nrow(layout),
    layout_columns = ncol(layout),
    graph_file = graph_file,
    graph_file_bytes = file.info(graph_file)$size,
    stringsAsFactors = FALSE
  )
})

result <- do.call(rbind, rows)
write.csv(
  result,
  file.path(output_dir, paste0("shared_graph_validation_", backend, ".csv")),
  row.names = FALSE
)
print(result)
