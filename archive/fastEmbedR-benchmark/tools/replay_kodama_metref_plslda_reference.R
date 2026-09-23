#!/usr/bin/env Rscript

options(stringsAsFactors = FALSE)

value_or <- function(name, default) {
  value <- Sys.getenv(name, unset = "")
  if (nzchar(value)) value else default
}

load_dataset <- function(path) {
  environment <- new.env(parent = emptyenv())
  load(path, envir = environment)
  objects <- mget(ls(environment, all.names = TRUE), envir = environment)
  if ("dataset" %in% names(objects)) return(objects$dataset)
  candidates <- Filter(
    function(x) is.list(x) && !is.null(x$data) && !is.null(x$labels),
    objects
  )
  if (length(candidates) != 1L) stop("Could not identify dataset in ", path)
  candidates[[1L]]
}

truth_silhouette <- function(embedding, truth) {
  labels <- as.integer(droplevels(as.factor(truth)))
  distances <- as.matrix(stats::dist(embedding))
  groups <- split(seq_along(labels), labels)
  values <- numeric(length(labels))
  for (i in seq_along(labels)) {
    same <- groups[[as.character(labels[[i]])]]
    same <- same[same != i]
    a <- if (length(same)) mean(distances[i, same]) else 0
    other <- vapply(
      groups[names(groups) != as.character(labels[[i]])],
      function(rows) mean(distances[i, rows]),
      numeric(1)
    )
    b <- min(other)
    denominator <- max(a, b)
    values[[i]] <- if (denominator > 0) (b - a) / denominator else 0
  }
  mean(values)
}

as_visualization_input <- function(result) {
  if (is.null(result$knn)) result$knn <- result$knn_Rnanoflann
  result
}

data_path <- value_or(
  "KODAMA_DATA_PATH",
  "/mnt/sata_ssd/fastEmbedR/Data/MetRef/MetRef_float32.RData"
)
cpu_path <- value_or(
  "KODAMA_CPU_RESULT",
  "/mnt/sata_ssd/KODAMAopt/metref_cpu_parity_20260720/final_cpu_M100_T100.rds"
)
cuda_path <- value_or(
  "KODAMA_CUDA_RESULT",
  "/mnt/sata_ssd/KODAMAopt/metref_cpu_parity_20260720/final_cuda_curand_skip_M100_T100.rds"
)
output_dir <- value_or(
  "KODAMA_COMPARE_OUT",
  "/mnt/sata_ssd/fastEmbedR/results/kodama_metref_plslda_reference_replay"
)
dir.create(output_dir, recursive = TRUE, showWarnings = FALSE)

source_root <- value_or("KODAMA_CPP_ROOT", "")
if (nzchar(source_root)) {
  source_root <- normalizePath(source_root, mustWork = TRUE)
  source(file.path(source_root, "wrappers", "R", "kodama_matrix_temp.R"))
  # The accepted CUDA archive also contains the CPU visualization objects.
  # Load it with CUDA link flags, then request CPU graph/UMAP execution below.
  .kodama_cpp_temp_load("cuda")
  graph_from_data <- function(data) {
    KODAMA.knn.graph.cpp(
      data,
      k = 30L,
      backend = "cpu",
      n.cores = 4L,
      exclude.self = TRUE
    )
  }
  visualize_umap <- function(input, init) {
    KODAMA.umap.knn.cpp(
      input,
      init = init,
      n.neighbors = 30L,
      backend = "cpu",
      n.threads = 4L,
      n.epochs = 200L,
      seed = 4L
    )
  }
} else {
  library(kodamaR)
  requested_graph_mode <- value_or("KODAMA_GRAPH_MODE", "")
  graph_from_data <- function(data) {
    KODAMA.graph(data, k = 30L, backend = "cpu", n.cores = 4L)
  }
  visualize_umap <- function(input, init) {
    arguments <- list(
      x = input,
      method = "UMAP",
      init = init,
      k = 30L,
      backend = "cpu",
      n.cores = 4L,
      n.epochs = 200L,
      seed = 4L
    )
    if (nzchar(requested_graph_mode) &&
        "graph.mode" %in% names(formals(KODAMA.visualization))) {
      arguments$graph.mode <- requested_graph_mode
    }
    do.call(KODAMA.visualization, arguments)
  }
}

dataset <- load_dataset(data_path)
truth <- droplevels(as.factor(dataset$labels))
if (inherits(dataset$data, "float32") || inherits(dataset$data, "float")) {
  dataset$data <- float::dbl(dataset$data)
}
cpu <- as_visualization_input(readRDS(cpu_path))
cuda <- as_visualization_input(readRDS(cuda_path))

# Historical diagnostic only: the July 20 comparison deliberately used one
# CPU initialization and one CPU UMAP implementation to isolate core-backend
# differences. Operational analyses must use each backend's own PCA
# initialization and matching visualization backend.
shared_init <- cpu$visual_init$umap
stopifnot(is.matrix(shared_init), nrow(shared_init) == nrow(dataset$data))

classic_graph <- graph_from_data(dataset$data)

embed <- function(input) {
  start <- proc.time()[["elapsed"]]
  layout <- visualize_umap(input, shared_init)
  list(layout = as.matrix(layout), seconds = proc.time()[["elapsed"]] - start)
}

classic <- embed(classic_graph)
cpu_layout <- embed(cpu)
cuda_layout <- embed(cuda)
records <- list(classic = classic, cpu = cpu_layout, cuda = cuda_layout)
saveRDS(records, file.path(output_dir, "MetRef_pls_lda_reference_layouts.rds"),
        compress = FALSE)

run_tag <- if (!is.null(cpu$parameters$M) && !is.null(cpu$parameters$Tcycle)) {
  sprintf("M%d_T%d", as.integer(cpu$parameters$M), as.integer(cpu$parameters$Tcycle))
} else {
  "M100_T100"
}

metrics <- data.frame(
  panel = c("classic", "cpu", "cuda"),
  core_seconds = c(NA_real_, cpu$runtime_seconds, cuda$runtime_seconds),
  umap_seconds = c(classic$seconds, cpu_layout$seconds, cuda_layout$seconds),
  truth_silhouette = c(
    truth_silhouette(classic$layout, truth),
    truth_silhouette(cpu_layout$layout, truth),
    truth_silhouette(cuda_layout$layout, truth)
  )
)
write.csv(metrics, file.path(output_dir, "metrics.csv"), row.names = FALSE)

colors <- grDevices::hcl.colors(nlevels(truth), "Dynamic")[as.integer(truth)]
plot_path <- file.path(
  output_dir,
  sprintf("MetRef_pls_lda_%s_reference.png", run_tag)
)
grDevices::png(plot_path, width = 2400, height = 820, res = 160)
old <- graphics::par(
  mfrow = c(1, 3),
  mar = c(1, 1, 3.1, 0.5),
  oma = c(0, 0, 2.2, 0)
)
panels <- list(
  list(title = "Classic UMAP", record = classic),
  list(title = "CPU KODAMA PLS-LDA", record = cpu_layout),
  list(title = "CUDA KODAMA PLS-LDA", record = cuda_layout)
)
for (panel in panels) {
  silhouette <- truth_silhouette(panel$record$layout, truth)
  graphics::plot(
    panel$record$layout,
    pch = 16,
    cex = 1,
    col = colors,
    axes = FALSE,
    xlab = "",
    ylab = "",
    main = sprintf("%s\ntruth silhouette=%.3f", panel$title, silhouette)
  )
  graphics::box(col = "grey80")
}
graphics::mtext("MetRef, colored by truth labels", outer = TRUE, cex = 1.2, font = 2)
graphics::par(old)
grDevices::dev.off()

print(metrics, row.names = FALSE)
cat("plot=", plot_path, "\n", sep = "")
