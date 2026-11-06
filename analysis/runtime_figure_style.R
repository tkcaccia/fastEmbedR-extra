runtime_figure_palette <- c(
  fastEmbedR = "#0072B2", cuML = "#D55E00",
  `scikit-learn` = "#CC79A7", openTSNE = "#009E73",
  `umap-learn` = "#009E73", Rtsne = "#595959",
  `FIt-SNE` = "#E69F00", irlba = "#666666",
  umap = "#595959", uwot = "#8E44AD",
  `uwot fast SGD` = "#E69F00"
)

runtime_figure_data <- function(data, family) {
  if (family == "umap") {
    data <- data[!grepl("binary", data$title, ignore.case = TRUE), ]
  }
  data$elapsed_median_sec <- suppressWarnings(
    as.numeric(data$elapsed_median_sec)
  )
  data <- data[is.finite(data$elapsed_median_sec) &
    data$elapsed_median_sec > 0, ]
  data$backend <- factor(
    ifelse(grepl("\\[CUDA\\]$", data$title), "CUDA", "CPU"),
    levels = c("CPU", "CUDA")
  )
  label <- sub(" \\[(CPU|CUDA|Python)\\]$", "", data$title)
  label <- sub("^fastEmbedR.*", "fastEmbedR", label)
  label <- sub("^RAPIDS cuML.*", "cuML", label)
  label <- sub("^scikit-learn.*", "scikit-learn", label)
  label <- sub("^openTSNE.*", "openTSNE", label)
  label <- sub("^umap-learn.*", "umap-learn", label)
  if (!all(label %in% names(runtime_figure_palette))) {
    stop("Unknown runtime figure method: ",
      paste(unique(label[!label %in% names(runtime_figure_palette)]),
        collapse = ", "), call. = FALSE)
  }
  data$series <- label
  data
}

render_diagnostic_runtime <- function(data, family, figure_dir) {
  if (!requireNamespace("ggplot2", quietly = TRUE)) {
    stop("ggplot2 is required for runtime figures.", call. = FALSE)
  }
  data <- runtime_figure_data(data, family)
  position <- ggplot2::position_dodge(width = 0.78)
  plot <- ggplot2::ggplot(data, ggplot2::aes(
    dataset, elapsed_median_sec, colour = series, shape = backend,
    group = interaction(series, backend)
  )) +
    ggplot2::geom_point(position = position, size = 3.4) +
    ggplot2::scale_y_log10() +
    ggplot2::scale_colour_manual(values = runtime_figure_palette) +
    ggplot2::scale_shape_manual(values = c(CPU = 16, CUDA = 17)) +
    ggplot2::coord_flip() +
    ggplot2::labs(
      x = NULL, y = "Median elapsed time (s, log scale)",
      colour = NULL, shape = "Backend"
    ) +
    ggplot2::theme_minimal(base_size = 14) +
    ggplot2::theme(
      axis.text.y = ggplot2::element_text(size = 13),
      legend.position = "bottom", legend.box = "vertical",
      legend.text = ggplot2::element_text(size = 10),
      legend.title = ggplot2::element_text(size = 10),
      plot.margin = ggplot2::margin(8, 18, 8, 8)
    ) +
    ggplot2::guides(
      colour = ggplot2::guide_legend(
        ncol = 3L, byrow = TRUE,
        override.aes = list(shape = 16)
      )
    )
  stem <- file.path(figure_dir, paste0("diagnostic_runtime_", family))
  ggplot2::ggsave(paste0(stem, ".pdf"), plot,
    width = 7.2, height = 6.8, units = "in")
  ggplot2::ggsave(paste0(stem, ".png"), plot,
    width = 7.2, height = 6.8, units = "in", dpi = 180)
}
