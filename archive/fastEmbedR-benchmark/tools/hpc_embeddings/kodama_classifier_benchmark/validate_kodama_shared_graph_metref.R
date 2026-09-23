#!/usr/bin/env Rscript

args <- commandArgs(trailingOnly = TRUE)
backend <- if (length(args)) args[[1L]] else "cpu"
data_file <- if (length(args) >= 2L) {
  args[[2L]]
} else {
  "/mnt/sata_ssd/fastEmbedR/Data/MetRef/MetRef.RData"
}
output_dir <- if (length(args) >= 3L) args[[3L]] else tempdir()
if (!backend %in% c("cpu", "cuda")) stop("backend must be cpu or cuda.")
if (!file.exists(data_file)) stop("MetRef file was not found: ", data_file)
dir.create(output_dir, recursive = TRUE, showWarnings = FALSE)

suppressPackageStartupMessages(library(kodamaR))

`%||%` <- function(x, y) if (is.null(x)) y else x
loaded <- new.env(parent = emptyenv())
load(data_file, envir = loaded)
objects <- as.list(loaded)
dataset <- objects$dataset %||% objects$MetRef %||% objects[[1L]]
x <- if (is.list(dataset) && !is.null(dataset$data)) dataset$data else dataset
if (inherits(x, "float32")) x <- float::dbl(x)
x <- as.matrix(x)
storage.mode(x) <- "double"
if (!is.numeric(x) || nrow(x) < 3L || ncol(x) < 2L || anyNA(x)) {
  stop("MetRef data must be a finite numeric matrix.")
}

set.seed(4)
k_graph <- min(100L, nrow(x) - 1L)
graph_elapsed <- system.time({
  graph <- KODAMA.graph(
    x,
    k = k_graph,
    backend = backend,
    n.cores = if (backend == "cpu") 4L else 1L,
    seed = 4L
  )
})[["elapsed"]]
stopifnot(
  inherits(graph, "kodama_graph"),
  identical(as.integer(graph$graph_builds), 1L)
)

graph_file <- file.path(output_dir, paste0("MetRef_graph_", backend, ".rds"))
saveRDS(graph, graph_file, compress = FALSE)
reloaded <- readRDS(graph_file)
stopifnot(
  inherits(reloaded, "kodama_graph"),
  identical(graph$indices, reloaded$indices),
  identical(graph$distances, reloaded$distances)
)

rows <- lapply(c("knn", "pls_lda"), function(classifier) {
  matrix_elapsed <- system.time({
    fit <- KODAMA.matrix(
      data = x,
      graph = reloaded,
      classifier = classifier,
      backend = backend,
      M = 1L,
      Tcycle = 2L,
      ncomp = min(50L, ncol(x)),
      landmarks = min(300L, nrow(x)),
      splitting = min(20L, nrow(x)),
      graph.neighbors = k_graph,
      knn.k = min(30L, k_graph),
      n.cores = if (backend == "cpu") 4L else 1L,
      seed = 4L,
      visual.init = TRUE,
      progress = FALSE
    )
  })[["elapsed"]]
  stopifnot(
    identical(as.integer(fit$graph_builds), 0L),
    length(fit$best_labels) == nrow(x),
    all(is.finite(fit$acc))
  )

  method <- if (classifier == "knn") "UMAP" else "opentsne"
  layout <- KODAMA.visualization(
    fit,
    method,
    backend = backend,
    n.cores = if (backend == "cpu") 4L else 1L,
    k = min(30L, k_graph),
    perplexity = min(30, floor(k_graph / 3)),
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
    is.matrix(layout),
    identical(dim(layout), c(nrow(x), 2L)),
    all(is.finite(layout))
  )

  data.frame(
    dataset = "MetRef",
    n = nrow(x),
    p = ncol(x),
    backend = backend,
    classifier = classifier,
    graph_builds = fit$graph_builds,
    graph_elapsed_sec = unname(graph_elapsed),
    matrix_elapsed_sec = unname(matrix_elapsed),
    best_accuracy = max(fit$acc),
    graph_file = graph_file,
    stringsAsFactors = FALSE
  )
})

result <- do.call(rbind, rows)
write.csv(
  result,
  file.path(output_dir, paste0("MetRef_shared_graph_validation_", backend, ".csv")),
  row.names = FALSE
)
print(result)
