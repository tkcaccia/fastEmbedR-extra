#!/usr/bin/env Rscript

args <- commandArgs(trailingOnly = TRUE)
source_dir <- if (length(args) >= 1L) args[[1L]] else
  file.path("results", "kodama_imagenet_consistent_style_20260801", "source")
output_dir <- if (length(args) >= 2L) args[[2L]] else
  file.path("results", "kodama_imagenet_consistent_style_20260801", "plots")
max_points <- if (length(args) >= 3L) as.integer(args[[3L]]) else 250000L
dir.create(output_dir, recursive = TRUE, showWarnings = FALSE)

files <- list.files(
  source_dir,
  pattern = "^imagenet_.*_seed4_layout[.]rds$",
  full.names = TRUE
)
if (!length(files)) stop("No ImageNet KODAMA layouts found in ", source_dir)

parse_file <- function(path) {
  base <- basename(path)
  classifier <- if (grepl("_pls_lda_", base, fixed = TRUE)) "PLS-LDA" else "KNN"
  visualization <- if (grepl("_opentsne_", base, fixed = TRUE)) "openTSNE" else "UMAP"
  mode <- if (grepl("_landmark10_", base, fixed = TRUE)) {
    "landmark10"
  } else if (grepl("_landmark20_", base, fixed = TRUE)) {
    "landmark20"
  } else if (grepl("_landmark50_", base, fixed = TRUE)) {
    "landmark50"
  } else {
    "default"
  }
  data.frame(
    file = path,
    classifier = classifier,
    visualization = visualization,
    mode = mode,
    stringsAsFactors = FALSE
  )
}

details <- do.call(rbind, lapply(files, parse_file))
objects <- lapply(details$file, readRDS)
layouts <- lapply(objects, function(object) {
  layout <- as.matrix(object$layout)
  if (ncol(layout) != 2L || any(!is.finite(layout))) stop("Invalid ImageNet layout")
  layout
})
n <- nrow(layouts[[1L]])
if (any(vapply(layouts, nrow, integer(1L)) != n)) stop("ImageNet layout sizes differ")

labels <- factor(objects[[1L]]$labels)
if (length(labels) != n) stop("ImageNet labels do not match the layouts")
if (!all(vapply(objects, function(object) {
  identical(as.character(object$labels), as.character(labels))
}, logical(1L)))) stop("ImageNet labels differ across layouts")

palette <- grDevices::hcl.colors(max(3L, nlevels(labels)), "Dark 3")
colors <- palette[as.integer(labels)]
set.seed(4L + 71L)
rows <- if (n <= max_points) seq_len(n) else sort(sample.int(n, max_points))
cex <- if (n < 2000L) 0.75 else if (n < 20000L) 0.35 else 0.16

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

draw_layout <- function(layout, title = NULL) {
  shown <- layout[rows, , drop = FALSE]
  graphics::plot(
    shown[, 1L], shown[, 2L],
    type = "n",
    xlim = padded_limits(shown[, 1L]),
    ylim = padded_limits(shown[, 2L]),
    axes = FALSE,
    ann = FALSE,
    frame.plot = FALSE,
    asp = 1
  )
  graphics::points(
    shown[, 1L], shown[, 2L],
    pch = 16,
    cex = cex,
    col = colors[rows]
  )
  if (!is.null(title)) graphics::title(main = title, line = 0.15, cex.main = 0.85)
}

manifest <- list()
mode_order <- c("default", "landmark10", "landmark20", "landmark50")

for (mode in mode_order) {
  selected <- which(details$mode == mode)
  if (!length(selected)) next
  order_key <- match(
    paste(details$visualization[selected], details$classifier[selected]),
    c("openTSNE KNN", "openTSNE PLS-LDA", "UMAP KNN", "UMAP PLS-LDA")
  )
  selected <- selected[order(order_key)]

  mode_dir <- file.path(output_dir, mode)
  dir.create(mode_dir, recursive = TRUE, showWarnings = FALSE)
  for (i in selected) {
    id <- paste0(
      "imagenet_kodama_",
      tolower(gsub("-", "", details$classifier[[i]])), "_",
      tolower(details$visualization[[i]]), "_cuda_", mode,
      "_consistent.png"
    )
    output <- file.path(mode_dir, id)
    grDevices::png(output, width = 1800, height = 1800, res = 220, bg = "white")
    old <- graphics::par(mar = rep(0, 4L), xaxs = "i", yaxs = "i", bty = "n")
    draw_layout(layouts[[i]])
    graphics::par(old)
    grDevices::dev.off()

    manifest[[length(manifest) + 1L]] <- data.frame(
      dataset = "imagenet",
      classifier = details$classifier[[i]],
      visualization = details$visualization[[i]],
      backend = "cuda",
      mode = mode,
      seed = 4L,
      n = n,
      n_labels = nlevels(labels),
      displayed_n = length(rows),
      point_symbol = 16L,
      point_cex = cex,
      palette = "Dark 3",
      source_path = normalizePath(details$file[[i]], mustWork = TRUE),
      source_md5 = unname(tools::md5sum(details$file[[i]])),
      plot_path = normalizePath(output, mustWork = TRUE),
      stringsAsFactors = FALSE
    )
  }

  n_panels <- length(selected)
  dimensions <- if (n_panels == 4L) c(2L, 2L) else c(1L, n_panels)
  comparison <- file.path(
    mode_dir,
    paste0("imagenet_KODAMA_CUDA_", mode, "_consistent_comparison.png")
  )
  grDevices::png(
    comparison,
    width = if (dimensions[[2L]] == 2L) 2600 else 1800,
    height = if (dimensions[[1L]] == 2L) 2500 else 1300,
    res = 220,
    bg = "white"
  )
  old <- graphics::par(
    mfrow = dimensions,
    mar = c(0.15, 0.15, 1.35, 0.15),
    oma = rep(0, 4L),
    xaxs = "i",
    yaxs = "i",
    bty = "n"
  )
  for (i in selected) {
    fraction <- switch(
      mode,
      landmark10 = "10%",
      landmark20 = "20%",
      landmark50 = "50%",
      default = "default"
    )
    draw_layout(
      layouts[[i]],
      paste0(
        details$classifier[[i]], " + ", details$visualization[[i]],
        " (CUDA, ", fraction, ")"
      )
    )
  }
  graphics::par(old)
  grDevices::dev.off()
  cat(mode, ": ", n_panels, " panels; displayed ", length(rows), "/", n, " points\n", sep = "")
}

manifest <- do.call(rbind, manifest)
utils::write.csv(
  manifest,
  file.path(output_dir, "imagenet_KODAMA_CUDA_consistent_plot_manifest.csv"),
  row.names = FALSE
)
