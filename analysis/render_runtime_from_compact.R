#!/usr/bin/env Rscript

args <- commandArgs(trailingOnly = TRUE)
if (length(args) != 2L) {
  stop("Usage: render_runtime_from_compact.R TABLE_CSV FIGURE_DIR",
    call. = FALSE)
}
script_arg <- grep("^--file=", commandArgs(FALSE), value = TRUE)
script_path <- normalizePath(sub("^--file=", "", script_arg[[1L]]))
source(file.path(dirname(script_path), "runtime_figure_style.R"))

table <- read.csv(args[[1L]], check.names = FALSE,
  stringsAsFactors = FALSE)
stopifnot(identical(names(table)[1:3], c("family", "method", "scope")))
datasets <- names(table)[-(1:3)]
labels <- c(Fashion = "Fashion-MNIST", `FlowRepo.` = "FlowRepository",
  Tabula = "Tabula Muris", Retina = "Retina")
display <- ifelse(datasets %in% names(labels),
  labels[datasets], datasets)
dir.create(args[[2L]], recursive = TRUE, showWarnings = FALSE)

for (family in c("pca", "tsne", "umap")) {
  rows <- table[table$family == family, ]
  data <- do.call(rbind, lapply(seq_len(nrow(rows)), function(i) {
    cell <- unlist(rows[i, datasets], use.names = FALSE)
    data.frame(
      title = rows$method[[i]],
      dataset = factor(display, levels = display),
      elapsed_median_sec = suppressWarnings(as.numeric(
        sub("\\*$", "", cell)
      ))
    )
  }))
  render_diagnostic_runtime(data, family, args[[2L]])
}
