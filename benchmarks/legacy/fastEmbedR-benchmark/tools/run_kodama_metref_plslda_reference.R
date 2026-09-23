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

library(kodamaR)

data_path <- value_or(
  "KODAMA_DATA_PATH",
  "/mnt/sata_ssd/fastEmbedR/Data/MetRef/MetRef_float32.RData"
)
backend <- match.arg(
  value_or("KODAMA_BACKEND", "cuda"),
  c("cpu", "cuda", "metal")
)
visual_backend <- match.arg(
  value_or(
    "KODAMA_VISUAL_BACKEND",
    if (identical(backend, "metal")) "cpu" else backend
  ),
  c("cpu", "cuda")
)
output <- value_or(
  "KODAMA_OUTPUT",
  file.path(
    "/mnt/sata_ssd/fastEmbedR/results/kodama_metref_plslda_reference",
    sprintf("MetRef_pls_lda_%s_M100_T100.rds", backend)
  )
)

parameters <- list(
  M = 100L,
  Tcycle = 100L,
  ncomp = 50L,
  landmarks = 100000L,
  effective_landmarks = 655L,
  splitting = 100L,
  n.cores = 4L,
  graph.neighbors = 100L,
  knn.k = 50L,
  classifier = "pls_lda",
  metric = "euclidean",
  seed = 1234L,
  visualization_k = 30L,
  visualization_epochs = 200L,
  visualization_seed = 4L,
  visualization_graph_mode = "fuzzy"
)

dataset <- load_dataset(data_path)
stopifnot(nrow(dataset$data) == 873L, ncol(dataset$data) == 375L)
dir.create(dirname(output), recursive = TRUE, showWarnings = FALSE)

start <- proc.time()[["elapsed"]]
result <- KODAMA.matrix(
  data = dataset$data,
  M = parameters$M,
  Tcycle = parameters$Tcycle,
  ncomp = parameters$ncomp,
  landmarks = parameters$landmarks,
  splitting = parameters$splitting,
  n.cores = parameters$n.cores,
  graph.neighbors = parameters$graph.neighbors,
  knn.k = parameters$knn.k,
  metric = parameters$metric,
  classifier = parameters$classifier,
  backend = backend,
  seed = parameters$seed,
  progress = TRUE,
  apply.kodama.dissimilarity = TRUE,
  visual.init = TRUE
)
elapsed <- proc.time()[["elapsed"]] - start

if (is.null(result$visual_init) || is.null(result$visual_init$umap)) {
  stop("KODAMA.matrix did not return its backend-native UMAP initialization.")
}
initialization_backend <- result$visual_init$backend
if (is.null(initialization_backend) &&
    grepl(paste0("_", backend, "_"), result$visual_init$method, fixed = TRUE)) {
  initialization_backend <- backend
}
if (!identical(tolower(initialization_backend), backend)) {
  stop(
    "PCA initialization backend mismatch: requested ", backend,
    ", received ", initialization_backend, "."
  )
}

visual_arguments <- list(
  x = result,
  method = "UMAP",
  init = result$visual_init$umap,
  k = parameters$visualization_k,
  metric = parameters$metric,
  backend = visual_backend,
  n.cores = parameters$n.cores,
  n.epochs = parameters$visualization_epochs,
  seed = parameters$visualization_seed
)
if ("graph.mode" %in% names(formals(KODAMA.visualization))) {
  visual_arguments$graph.mode <- parameters$visualization_graph_mode
}
visual_start <- proc.time()[["elapsed"]]
layout <- do.call(KODAMA.visualization, visual_arguments)
visual_elapsed <- proc.time()[["elapsed"]] - visual_start

result$reference_parameters <- parameters
result$reference_parameters$backend <- backend
result$reference_parameters$data_path <- data_path
result$reference_parameters$package_version <- as.character(
  utils::packageVersion("kodamaR")
)
result$reference_parameters$pca_initialization_method <- result$visual_init$method
result$reference_parameters$pca_initialization_backend <- initialization_backend
result$reference_parameters$visualization_backend <- visual_backend
result$reference_parameters$elapsed_seconds <- elapsed
saveRDS(result, output, compress = FALSE)
saveRDS(
  list(
    layout = as.matrix(layout),
    backend = backend,
    initialization_method = result$visual_init$method,
    initialization_backend = initialization_backend,
    visualization_backend = visual_backend,
    seconds = visual_elapsed
  ),
  sub("\\.rds$", "_umap.rds", output),
  compress = FALSE
)

truth <- droplevels(as.factor(dataset$labels))
colors <- grDevices::hcl.colors(nlevels(truth), "Dynamic")[as.integer(truth)]
plot_path <- sub("\\.rds$", "_umap.png", output)
grDevices::png(plot_path, width = 1100, height = 1000, res = 160)
graphics::par(mar = c(1, 1, 3, 1))
graphics::plot(
  layout,
  pch = 16,
  cex = 0.9,
  col = colors,
  axes = FALSE,
  xlab = "",
  ylab = "",
  main = sprintf(
    "MetRef KODAMA PLS-LDA %s core / %s visualization\n%s initialization",
    toupper(backend),
    toupper(visual_backend),
    result$visual_init$method
  )
)
graphics::box(col = "grey80")
grDevices::dev.off()

summary <- data.frame(
  backend = backend,
  M = parameters$M,
  Tcycle = parameters$Tcycle,
  requested_landmarks = parameters$landmarks,
  effective_landmarks = parameters$effective_landmarks,
  splitting = parameters$splitting,
  ncomp = parameters$ncomp,
  graph_neighbors = parameters$graph.neighbors,
  knn_k = parameters$knn.k,
  seed = parameters$seed,
  elapsed_seconds = elapsed,
  kernel_seconds = result$runtime_seconds,
  median_cv_accuracy = median(result$acc),
  maximum_cv_accuracy = max(result$acc),
  median_classes = median(apply(result$res, 1L, function(x) length(unique(x)))),
  pca_initialization_method = result$visual_init$method,
  pca_initialization_backend = initialization_backend,
  visualization_backend = visual_backend,
  visualization_seconds = visual_elapsed,
  output = output,
  layout_output = sub("\\.rds$", "_umap.rds", output),
  plot_output = plot_path
)
write.csv(summary, sub("\\.rds$", "_summary.csv", output), row.names = FALSE)
print(summary, row.names = FALSE)
