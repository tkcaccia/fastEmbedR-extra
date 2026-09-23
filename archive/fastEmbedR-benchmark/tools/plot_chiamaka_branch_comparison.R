args <- commandArgs(trailingOnly = TRUE)
if (length(args) != 3L) {
  stop(
    "Usage: Rscript plot_chiamaka_branch_comparison.R ",
    "<historical-details.rds> <latest-details.rds> <output.png>",
    call. = FALSE
  )
}

suppressPackageStartupMessages(library(float))

historical <- readRDS(args[[1L]])
latest <- readRDS(args[[2L]])

as_layout <- function(x) {
  if (inherits(x, "float32")) {
    return(float::dbl(x))
  }
  as.matrix(x)
}

labels <- historical$labels
if (is.factor(labels)) {
  color_index <- as.integer(labels)
} else {
  color_index <- as.integer(factor(labels))
}
palette <- grDevices::hcl.colors(max(color_index), "Dynamic")
point_colors <- palette[color_index]

layouts <- list(
  "Historical faissR: openTSNE" =
    as_layout(historical$layouts$fastembedr_opentsne),
  "Latest native HNSW: openTSNE" =
    as_layout(latest$layouts$fastembedr_opentsne),
  "Historical faissR: fuzzy UMAP" =
    as_layout(historical$layouts$fastembedr_umap),
  "Latest native HNSW: fuzzy UMAP" =
    as_layout(latest$layouts$fastembedr_umap)
)

grDevices::png(args[[3L]], width = 2200, height = 2000, res = 220)
old_par <- graphics::par(
  mfrow = c(2, 2),
  mar = c(0.2, 0.2, 1.8, 0.2),
  oma = c(0, 0, 0, 0)
)
on.exit({
  graphics::par(old_par)
  grDevices::dev.off()
}, add = TRUE)

for (name in names(layouts)) {
  layout <- layouts[[name]]
  graphics::plot(
    layout,
    pch = 20,
    cex = 0.24,
    col = point_colors,
    axes = FALSE,
    ann = FALSE
  )
  graphics::title(main = name, line = 0.35, cex.main = 0.9)
  graphics::box(bty = "n")
}
