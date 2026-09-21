#!/usr/bin/env Rscript

args <- commandArgs(trailingOnly = TRUE)
input_dir <- if (length(args)) args[[1L]] else "results/aggregate"
output_dir <- if (length(args) > 1L) args[[2L]] else "results/figures"

if (!requireNamespace("ggplot2", quietly = TRUE) ||
    !requireNamespace("scales", quietly = TRUE)) {
  stop("Install ggplot2 and scales to build the figures.", call. = FALSE)
}

dir.create(output_dir, recursive = TRUE, showWarnings = FALSE)

dataset_levels <- c(
  "COIL-20", "USPS", "Fashion-MNIST", "FlowRepository", "flow18",
  "MNIST", "ImageNet", "MetRef", "mass41", "Tabula Muris", "Retina"
)

tsne_methods <- c(
  "Rtsne_full", "KlugerLab_FItSNE", "fastEmbedR_tsne_cpu_full",
  "python_opentsne_fft", "python_opentsne_fft_direct",
  "fastEmbedR_tsne_cuda_full", "rapids_cuml_tsne_full",
  "rapids_cuml_tsne_full_direct"
)

umap_methods <- c(
  "umap_package", "uwot_default", "uwot_fast_sgd",
  "fastEmbedR_umap_cpu_fuzzy_full", "fastEmbedR_umap_cpu_binary_full",
  "python_umap_learn", "python_umap_learn_direct",
  "fastEmbedR_umap_cuda_fuzzy_full",
  "fastEmbedR_umap_cuda_binary_full", "rapids_cuml_umap_full",
  "rapids_cuml_umap_full_direct"
)

method_colors <- c(
  "Rtsne [CPU]" = "#4D4D4D",
  "FIt-SNE [CPU]" = "#999999",
  "fastEmbedR t-SNE [CPU]" = "#0072B2",
  "Python openTSNE via R (total call) [CPU]" = "#7B3294",
  "Python openTSNE direct (fit only) [CPU]" = "#C2A5CF",
  "fastEmbedR t-SNE [CUDA]" = "#56B4E9",
  "RAPIDS cuML t-SNE via R (total call) [CUDA]" = "#D55E00",
  "RAPIDS cuML t-SNE direct (fit only) [CUDA]" = "#E69F00",
  "umap [CPU]" = "#4D4D4D",
  "uwot default [CPU]" = "#999999",
  "uwot fast SGD [CPU]" = "#666666",
  "fastEmbedR fuzzy [CPU]" = "#0072B2",
  "fastEmbedR binary [CPU]" = "#009E73",
  "Python umap-learn via R (total call) [CPU]" = "#7B3294",
  "Python umap-learn direct (fit only) [CPU]" = "#C2A5CF",
  "fastEmbedR fuzzy [CUDA]" = "#56B4E9",
  "fastEmbedR binary [CUDA]" = "#00A087",
  "RAPIDS cuML UMAP via R (total call) [CUDA]" = "#D55E00",
  "RAPIDS cuML UMAP direct (fit only) [CUDA]" = "#E69F00"
)

read_runtime <- function(filename, methods) {
  path <- file.path(input_dir, filename)
  if (!file.exists(path)) stop("Missing input: ", path, call. = FALSE)
  data <- read.csv(path, stringsAsFactors = FALSE, check.names = FALSE)
  data <- data[data$method %in% methods, , drop = FALSE]
  data$dataset_label <- factor(data$dataset_label, levels = dataset_levels)
  data$method <- factor(data$method, levels = methods)
  data <- data[order(data$dataset_label, data$method), , drop = FALSE]
  data
}

complete_slots <- function(data, methods) {
  grid <- expand.grid(
    dataset_label = dataset_levels,
    method = methods,
    stringsAsFactors = FALSE
  )
  keep <- setdiff(names(data), c("dataset_label", "method"))
  merge(grid, data[c("dataset_label", "method", keep)],
        by = c("dataset_label", "method"), all.x = TRUE, sort = FALSE)
}

runtime_plot <- function(data, methods, title) {
  data <- complete_slots(data, methods)
  data$dataset_id <- match(data$dataset_label, dataset_levels)
  data$method_id <- match(data$method, methods)
  slot_width <- min(0.095, 0.78 / length(methods))
  center <- (length(methods) + 1) / 2
  data$x <- data$dataset_id + (data$method_id - center) * slot_width
  labels <- unique(data[is.finite(data$runtime), c("method", "display_label")])
  label_map <- setNames(labels$display_label, labels$method)
  data$display_label <- unname(label_map[as.character(data$method)])
  data$display_label <- factor(
    data$display_label,
    levels = unname(label_map[methods])
  )

  ggplot2::ggplot(
    data,
    ggplot2::aes(x = x, y = runtime, fill = display_label)
  ) +
    ggplot2::geom_col(width = slot_width * 0.88, na.rm = TRUE) +
    ggplot2::geom_errorbar(
      ggplot2::aes(ymin = runtime_q1, ymax = runtime_q3),
      width = slot_width * 0.42, linewidth = 0.25, na.rm = TRUE
    ) +
    ggplot2::scale_x_continuous(
      breaks = seq_along(dataset_levels), labels = dataset_levels,
      expand = ggplot2::expansion(mult = c(0.015, 0.015))
    ) +
    ggplot2::scale_y_continuous(
      trans = scales::pseudo_log_trans(base = 10, sigma = 0.025),
      breaks = c(0, 0.1, 1, 10, 100, 1000, 10000),
      labels = scales::label_number(big.mark = " ")
    ) +
    ggplot2::scale_fill_manual(values = method_colors, drop = FALSE) +
    ggplot2::labs(
      title = title,
      subtitle = paste(
        "CPU and CUDA share one panel.",
        "Direct-Python rows are fit-only; R rows are total calls.",
        "The pseudo-log axis retains a true zero baseline."
      ),
      x = NULL, y = "Median time (seconds, pseudo-log scale)", fill = NULL
    ) +
    ggplot2::theme_minimal(base_size = 9) +
    ggplot2::theme(
      panel.grid.minor = ggplot2::element_blank(),
      plot.title = ggplot2::element_text(face = "bold", size = 12),
      plot.subtitle = ggplot2::element_text(size = 8.5),
      axis.text.x = ggplot2::element_text(angle = 38, hjust = 1),
      legend.position = "bottom",
      legend.box = "vertical"
    ) +
    ggplot2::guides(
      fill = ggplot2::guide_legend(nrow = 3, byrow = TRUE)
    )
}

save_plot <- function(plot, stem) {
  ggplot2::ggsave(
    file.path(output_dir, paste0(stem, ".pdf")), plot,
    width = 10.2, height = 7.4, units = "in"
  )
  ggplot2::ggsave(
    file.path(output_dir, paste0(stem, ".png")), plot,
    width = 10.2, height = 7.4, units = "in", dpi = 180
  )
}

tsne <- read_runtime("runtime_tsne_all_methods.csv", tsne_methods)
umap <- read_runtime("runtime_umap_all_methods.csv", umap_methods)

save_plot(runtime_plot(tsne, tsne_methods, "t-SNE runtime"),
          "runtime_tsne_all_methods")
save_plot(runtime_plot(umap, umap_methods, "UMAP runtime"),
          "runtime_umap_all_methods")
