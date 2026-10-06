#!/usr/bin/env Rscript

args <- commandArgs(trailingOnly = TRUE)
if (length(args) != 1L) {
  stop("Usage: render_jss_secondary_20260930.R GENERATED_DIR")
}
dir <- file.path(args[[1L]], "secondary_20260930")
read <- function(name) {
  utils::read.csv(file.path(dir, name), stringsAsFactors = FALSE)
}
write <- function(name, lines) {
  writeLines(lines, file.path(dir, name), useBytes = TRUE)
}
fmt <- function(value, digits) {
  if (!length(value) || !is.finite(value)) return("--")
  formatC(value, format = "f", digits = digits)
}

scaling <- read("cpu_scaling_comparison.csv")
scaling_rows <- character()
for (method in c("UMAP", "t-SNE")) {
  for (dataset in c("COIL20", "MNIST", "flow18", "imagenet")) {
    data <- scaling[scaling$method == method &
                      scaling$dataset == dataset, ]
    data <- data[match(c(1L, 2L, 4L, 8L, 12L), data$threads), ]
    if (nrow(data) != 5L || anyNA(data$threads)) {
      stop("Incomplete CPU scaling row: ", dataset, " ", method)
    }
    scaling_rows <- c(scaling_rows, paste0(
      paste(c(dataset, method, fmt(data$median_sec[[1L]], 1L),
              vapply(data$speedup[-1L], fmt, character(1L), 2L)),
            collapse = " & "), " \\\\"
    ))
  }
}
write("cpu_scaling_table.tex", c(
  "\\begin{tabular}{llrrrrr}", "\\toprule",
  "Data set & Method & 1-core s & 2-core & 4-core & 8-core & 12-core \\\\",
  "\\midrule", scaling_rows, "\\bottomrule", "\\end{tabular}"
))

landmark <- read("landmark_summary_comparison.csv")
landmark_rows <- vapply(seq_len(nrow(landmark)), function(i) {
  row <- landmark[i, ]
  paste0(paste(c(
    if (row$method == "tsne") "t-SNE" else "Fuzzy UMAP",
    toupper(row$backend), row$datasets,
    fmt(row$runtime_ratio, 2L), fmt(row$preserve_delta, 3L),
    fmt(row$projected_full_procrustes, 2L),
    fmt(row$peak_rss_ratio, 2L), fmt(row$peak_gpu_ratio, 2L)
  ), collapse = " & "), " \\\\")
}, character(1L))
write("landmark_table.tex", c(
  "\\begin{tabular}{llrrrrrr}", "\\toprule",
  paste0("Method & Backend & Data sets & Time ratio",
         " & Preserve@30 $\\Delta$ & Procrustes",
         " & RSS ratio & GPU ratio \\\\"),
  "\\midrule", landmark_rows, "\\bottomrule", "\\end{tabular}"
))

cluster <- read("clustering_summary_comparison.csv")
cluster_rows <- vapply(seq_len(nrow(cluster)), function(i) {
  row <- cluster[i, ]
  paste0(paste(c(
    switch(row$method, leiden = "Leiden", louvain = "Louvain",
           walktrap = "Walktrap"), row$datasets,
    fmt(row$elapsed_sec_native, 3L),
    fmt(row$elapsed_sec_igraph, 3L),
    fmt(row$membership_ari, 3L), fmt(row$graph_sec, 3L)
  ), collapse = " & "), " \\\\")
}, character(1L))
write("clustering_table.tex", c(
  "\\begin{tabular}{lrrrrr}", "\\toprule",
  "Method & Data sets & Native s & igraph s & ARI & Graph s \\\\",
  "\\midrule", cluster_rows, "\\bottomrule", "\\end{tabular}"
))
