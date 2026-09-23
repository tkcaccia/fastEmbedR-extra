#!/usr/bin/env Rscript

args <- commandArgs(trailingOnly = TRUE)
source_root <- if (length(args) >= 1L) args[[1L]] else
  file.path("results", "kodama_cpu4_consistent_style_20260801", "source")
output_root <- if (length(args) >= 2L) args[[2L]] else
  file.path("results", "kodama_cpu4_consistent_style_20260801", "plots")
max_points <- if (length(args) >= 3L) as.integer(args[[3L]]) else 250000L
dir.create(output_root, recursive = TRUE, showWarnings = FALSE)

datasets <- list.dirs(source_root, recursive = FALSE, full.names = FALSE)
if (!length(datasets)) stop("No dataset directories found under ", source_root)

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

point_cex <- function(n) {
  if (n < 2000L) 0.75 else if (n < 20000L) 0.35 else 0.16
}

sample_rows <- function(n, size, seed = 75L) {
  if (size >= n) return(seq_len(n))
  set.seed(seed)
  sort(sample.int(n, size, replace = FALSE))
}

method_details <- function(file) {
  base <- basename(file)
  classifier <- if (grepl("_pls_lda_", base, fixed = TRUE)) {
    "PLS-LDA"
  } else if (grepl("_knn_", base, fixed = TRUE)) {
    "KNN"
  } else {
    NA_character_
  }
  visualization <- if (grepl("_opentsne_", base, fixed = TRUE)) {
    "openTSNE"
  } else if (grepl("_umap_", base, fixed = TRUE)) {
    "UMAP"
  } else {
    NA_character_
  }
  data.frame(
    file = file,
    classifier = classifier,
    visualization = visualization,
    stringsAsFactors = FALSE
  )
}

draw_layout <- function(layout, rows, colors, cex, title = NULL) {
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

manifest_rows <- list()

for (dataset in datasets) {
  dataset_dir <- file.path(source_root, dataset)
  files <- list.files(
    dataset_dir,
    pattern = "_default_seed4_layout[.]rds$",
    full.names = TRUE,
    recursive = FALSE
  )
  if (!length(files)) next

  details <- do.call(rbind, lapply(files, method_details))
  details <- details[!is.na(details$classifier) & !is.na(details$visualization), , drop = FALSE]
  if (!nrow(details)) next
  details$order <- match(
    paste(details$visualization, details$classifier),
    c("openTSNE KNN", "openTSNE PLS-LDA", "UMAP KNN", "UMAP PLS-LDA")
  )
  details <- details[order(details$order), , drop = FALSE]

  objects <- lapply(details$file, readRDS)
  layouts <- lapply(objects, function(object) {
    layout <- as.matrix(object$layout)
    if (ncol(layout) != 2L || any(!is.finite(layout))) stop("Invalid layout in ", dataset)
    layout
  })
  n <- nrow(layouts[[1L]])
  if (any(vapply(layouts, nrow, integer(1L)) != n)) {
    stop("Layout row-count mismatch for ", dataset)
  }

  labels <- factor(objects[[1L]]$labels)
  if (length(labels) != n) stop("Label/layout mismatch for ", dataset)
  if (any(vapply(objects, function(object) length(object$labels), integer(1L)) != n)) {
    stop("Label-count mismatch across layouts for ", dataset)
  }
  palette <- grDevices::hcl.colors(max(3L, nlevels(labels)), "Dark 3")
  colors <- palette[as.integer(labels)]
  rows <- sample_rows(n, min(n, max_points), seed = 4L + 71L)
  cex <- point_cex(n)

  dataset_output <- file.path(output_root, dataset)
  dir.create(dataset_output, recursive = TRUE, showWarnings = FALSE)

  for (i in seq_len(nrow(details))) {
    id <- paste0(
      tolower(gsub("-", "", details$classifier[[i]])), "_",
      tolower(details$visualization[[i]])
    )
    output <- file.path(
      dataset_output,
      paste0(dataset, "_kodama_", id, "_cpu4_consistent.png")
    )
    grDevices::png(output, width = 1800, height = 1800, res = 220, bg = "white")
    old <- graphics::par(mar = rep(0, 4L), xaxs = "i", yaxs = "i", bty = "n")
    draw_layout(layouts[[i]], rows, colors, cex)
    graphics::par(old)
    grDevices::dev.off()

    manifest_rows[[length(manifest_rows) + 1L]] <- data.frame(
      dataset = dataset,
      classifier = details$classifier[[i]],
      visualization = details$visualization[[i]],
      backend = "cpu",
      n.cores = 4L,
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

  n_panels <- nrow(details)
  dimensions <- if (n_panels == 4L) c(2L, 2L) else c(1L, n_panels)
  comparison_png <- file.path(
    dataset_output,
    paste0(dataset, "_KODAMA_CPU4_consistent_comparison.png")
  )
  comparison_pdf <- sub("[.]png$", ".pdf", comparison_png)

  draw_comparison <- function() {
    old <- graphics::par(
      mfrow = dimensions,
      mar = c(0.15, 0.15, 1.35, 0.15),
      oma = rep(0, 4L),
      xaxs = "i",
      yaxs = "i",
      bty = "n"
    )
    on.exit(graphics::par(old), add = TRUE)
    for (i in seq_len(n_panels)) {
      draw_layout(
        layouts[[i]], rows, colors, cex,
        paste0("KODAMA ", details$classifier[[i]], " + ",
               details$visualization[[i]], " (CPU4)")
      )
    }
  }

  grDevices::png(
    comparison_png,
    width = if (dimensions[[2L]] == 2L) 2600 else 1800,
    height = if (dimensions[[1L]] == 2L) 2500 else 1300,
    res = 220,
    bg = "white"
  )
  draw_comparison()
  grDevices::dev.off()

  grDevices::pdf(
    comparison_pdf,
    width = if (dimensions[[2L]] == 2L) 11.8 else 8.2,
    height = if (dimensions[[1L]] == 2L) 11.4 else 5.9,
    useDingbats = FALSE
  )
  draw_comparison()
  grDevices::dev.off()
  cat(dataset, ": ", n_panels, " panels; displayed ", length(rows), "/", n, " points\n", sep = "")
}

manifest <- do.call(rbind, manifest_rows)
utils::write.csv(
  manifest,
  file.path(output_root, "KODAMA_CPU4_consistent_plot_manifest.csv"),
  row.names = FALSE
)
