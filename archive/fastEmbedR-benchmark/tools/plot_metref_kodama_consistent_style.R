#!/usr/bin/env Rscript

args <- commandArgs(trailingOnly = TRUE)
source_dir <- if (length(args) >= 1L) args[[1L]] else
  file.path("results", "metref_kodama_consistent_style_20260801", "source")
output_dir <- if (length(args) >= 2L) args[[2L]] else
  file.path("results", "metref_kodama_consistent_style_20260801", "plots")
dir.create(output_dir, recursive = TRUE, showWarnings = FALSE)

data_env <- new.env(parent = emptyenv())
load(file.path(source_dir, "MetRef.RData"), envir = data_env)
if (!exists("dataset", envir = data_env, inherits = FALSE)) {
  stop("MetRef.RData does not contain `dataset`.")
}
dataset <- get("dataset", envir = data_env, inherits = FALSE)
labels <- factor(dataset$labels, levels = levels(factor(dataset$labels)))
palette <- grDevices::hcl.colors(max(3L, nlevels(labels)), "Dark 3")
point_colors <- palette[as.integer(labels)]

specs <- data.frame(
  id = c(
    "fastembedr_opentsne_cuda",
    "kodama_knn_opentsne_cuda",
    "kodama_plslda_opentsne_cuda",
    "fastembedr_umap_fuzzy_cuda",
    "kodama_knn_umap_cuda",
    "kodama_plslda_umap_cuda"
  ),
  title = c(
    "fastEmbedR openTSNE (CUDA)",
    "KODAMA KNN + openTSNE (CUDA)",
    "KODAMA PLS-LDA + openTSNE (CUDA)",
    "fastEmbedR fuzzy UMAP (CUDA)",
    "KODAMA KNN + UMAP (CUDA)",
    "KODAMA PLS-LDA + UMAP (CUDA)"
  ),
  file = c(
    "MetRef_fastEmbedR_opentsne_cuda_full_threads1_seed4.rds",
    "MetRef_knn_opentsne_default_seed4_layout.rds",
    "MetRef_pls_lda_opentsne_default_seed4_layout.rds",
    "MetRef_fastEmbedR_umap_cuda_fuzzy_full_threads1_seed4.rds",
    "MetRef_knn_umap_default_seed4_layout.rds",
    "MetRef_pls_lda_umap_default_seed4_layout.rds"
  ),
  stringsAsFactors = FALSE
)

extract_layout <- function(path) {
  object <- readRDS(path)
  layout <- if (is.list(object) && !is.null(object$layout)) object$layout else object
  layout <- as.matrix(layout)
  if (!identical(dim(layout), c(length(labels), 2L)) || any(!is.finite(layout))) {
    stop("Invalid layout in ", path)
  }
  storage.mode(layout) <- "double"
  layout
}

layouts <- setNames(
  lapply(specs$file, function(file) extract_layout(file.path(source_dir, file))),
  specs$id
)

padded_limits <- function(values, fraction = 0.04) {
  limits <- range(values, finite = TRUE)
  span <- diff(limits)
  if (!is.finite(span) || span <= 0) {
    center <- if (all(is.finite(limits))) mean(limits) else 0
    span <- max(1, abs(center) * 0.08)
    limits <- center + c(-0.5, 0.5) * span
  }
  limits + c(-1, 1) * span * fraction
}

draw_layout <- function(layout, title = NULL, cex = 0.75) {
  graphics::plot(
    layout[, 1L], layout[, 2L],
    type = "n",
    xlim = padded_limits(layout[, 1L]),
    ylim = padded_limits(layout[, 2L]),
    axes = FALSE,
    ann = FALSE,
    frame.plot = FALSE,
    asp = 1
  )
  graphics::points(
    layout[, 1L], layout[, 2L],
    pch = 16,
    cex = cex,
    col = point_colors
  )
  if (!is.null(title)) graphics::title(main = title, line = 0.15, cex.main = 0.82)
}

for (i in seq_len(nrow(specs))) {
  path <- file.path(output_dir, paste0("MetRef_", specs$id[[i]], "_consistent.png"))
  grDevices::png(path, width = 1800, height = 1800, res = 220, bg = "white")
  old <- graphics::par(mar = rep(0, 4L), xaxs = "i", yaxs = "i", bty = "n")
  draw_layout(layouts[[specs$id[[i]]]], cex = 0.75)
  graphics::par(old)
  grDevices::dev.off()
}

comparison_png <- file.path(output_dir, "MetRef_CUDA_fastEmbedR_KODAMA_consistent_comparison.png")
comparison_pdf <- file.path(output_dir, "MetRef_CUDA_fastEmbedR_KODAMA_consistent_comparison.pdf")

draw_comparison <- function() {
  old <- graphics::par(
    mfrow = c(2L, 3L),
    mar = c(0.15, 0.15, 1.35, 0.15),
    oma = rep(0, 4L),
    xaxs = "i",
    yaxs = "i",
    bty = "n"
  )
  on.exit(graphics::par(old), add = TRUE)
  for (i in seq_len(nrow(specs))) {
    draw_layout(layouts[[specs$id[[i]]]], specs$title[[i]], cex = 0.75)
  }
}

grDevices::png(comparison_png, width = 3300, height = 2200, res = 240, bg = "white")
draw_comparison()
grDevices::dev.off()

grDevices::pdf(comparison_pdf, width = 13.75, height = 9.17, useDingbats = FALSE)
draw_comparison()
grDevices::dev.off()

manifest <- transform(
  specs,
  n = length(labels),
  n_labels = nlevels(labels),
  seed = 4L,
  point_symbol = 16L,
  point_cex = 0.75,
  palette = "Dark 3",
  source_path = normalizePath(file.path(source_dir, file), mustWork = TRUE),
  source_md5 = unname(tools::md5sum(file.path(source_dir, file)))
)
utils::write.csv(
  manifest,
  file.path(output_dir, "MetRef_consistent_plot_manifest.csv"),
  row.names = FALSE
)
saveRDS(
  list(layouts = layouts, labels = labels, palette = palette, manifest = manifest),
  file.path(output_dir, "MetRef_CUDA_fastEmbedR_KODAMA_consistent_layouts.rds"),
  compress = "xz"
)

cat(normalizePath(comparison_png), "\n")
