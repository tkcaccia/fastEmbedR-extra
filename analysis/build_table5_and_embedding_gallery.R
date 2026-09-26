#!/usr/bin/env Rscript

args <- commandArgs(trailingOnly = TRUE)
if (!length(args)) {
  stop(
    "Usage: build_table5_and_embedding_gallery.R RESULTS_ROOT ...",
    call. = FALSE
  )
}
results_root <- normalizePath(args[[1L]], mustWork = TRUE)
script_arg <- grep("^--file=", commandArgs(FALSE), value = TRUE)
script_path <- normalizePath(sub("^--file=", "", script_arg[[1L]]))
repo_root <- normalizePath(file.path(dirname(script_path), ".."))
generated_dir <- if (length(args) >= 2L) args[[2L]] else {
  file.path(results_root, "publication", "tables")
}
figure_dir <- if (length(args) >= 3L) args[[3L]] else {
  file.path(results_root, "publication", "embedding_plots")
}
latex_figure_prefix <- if (length(args) >= 4L) args[[4L]] else {
  "../embedding_plots"
}

dir.create(generated_dir, recursive = TRUE, showWarnings = FALSE)
dir.create(figure_dir, recursive = TRUE, showWarnings = FALSE)
source(file.path(
  repo_root, "benchmarks", "linux", "jss-review-validation",
  "common", "common.R"
))

datasets <- c(
  "COIL20", "USPS", "FashionMNIST",
  "FlowRepository_FR-FCM-ZYRM_files", "flow18", "MNIST", "imagenet",
  "MetRef", "mass41", "TabulaMuris", "Macosko2015_retina"
)
dataset_labels <- c(
  COIL20 = "COIL-20", USPS = "USPS", FashionMNIST = "Fashion-MNIST",
  "FlowRepository_FR-FCM-ZYRM_files" = "FlowRepository",
  flow18 = "flow18", MNIST = "MNIST", imagenet = "ImageNet",
  MetRef = "MetRef", mass41 = "mass41",
  TabulaMuris = "Tabula Muris", Macosko2015_retina = "Retina"
)
table_dataset_labels <- c(
  "COIL-20", "USPS", "Fashion", "FlowRepo.", "flow18", "MNIST",
  "ImageNet", "MetRef", "mass41", "Tabula", "Retina"
)

spec <- data.frame(
  family = c(rep("pca", 6L), rep("tsne", 7L), rep("umap", 7L)),
  method = c(
    "fastembedr_pca", "irlba_pca", "stats_prcomp", "fastembedr_pca",
    "sklearn_pca", "cuml_pca", "rtsne", "fitsne",
    "fastembedr_tsne", "fastembedr_tsne", "sklearn_tsne",
    "python_opentsne", "cuml_tsne", "r_umap", "uwot",
    "uwot_fast_sgd", "fastembedr_umap", "fastembedr_umap",
    "python_umap", "cuml_umap"
  ),
  route = c(
    "r_cpu", "r_cpu", "r_cpu", "r_cuda", "python_cpu",
    "python_cuda", "r_cpu", "r_cpu", "r_cpu", "r_cuda",
    "python_cpu", "python_cpu", "python_cuda", "r_cpu", "r_cpu",
    "r_cpu", "r_cpu", "r_cuda", "python_cpu", "python_cuda"
  ),
  title = c(
    "fastEmbedR PCA [CPU]", "irlba [CPU]", "stats::prcomp [CPU]",
    "fastEmbedR PCA [CUDA]", "scikit-learn PCA [Python]",
    "RAPIDS cuML PCA [CUDA]", "Rtsne [CPU]", "FIt-SNE [CPU]",
    "fastEmbedR t-SNE [CPU]", "fastEmbedR t-SNE [CUDA]",
    "scikit-learn t-SNE [Python]", "openTSNE [Python]",
    "RAPIDS cuML t-SNE [CUDA]", "umap [CPU]", "uwot [CPU]",
    "uwot fast SGD [CPU]", "fastEmbedR fuzzy UMAP [CPU]",
    "fastEmbedR fuzzy UMAP [CUDA]", "umap-learn [Python]",
    "RAPIDS cuML UMAP [CUDA]"
  ),
  scope = c(
    rep("R total", 4L), "Python fit", "Python fit",
    rep("R total", 4L), rep("Python fit", 3L), rep("R total", 5L),
    "Python fit", "Python fit"
  ),
  stringsAsFactors = FALSE
)

runtime_path <- file.path(
  results_root, "aggregate", "workflow_comparators_all.csv"
)
if (!file.exists(runtime_path)) {
  stop("Missing campaign aggregate: ", runtime_path, call. = FALSE)
}
runtime <- read.csv(
  runtime_path, stringsAsFactors = FALSE, check.names = FALSE
)
required_runtime <- c(
  "comparator_mode", "dataset", "method", "elapsed_median_sec"
)
if (!all(required_runtime %in% names(runtime))) {
  stop("The workflow aggregate has an invalid schema.", call. = FALSE)
}

format_seconds <- function(x) {
  x <- suppressWarnings(as.numeric(x))
  ifelse(
    !is.finite(x), "--",
    ifelse(
      x < 10, formatC(x, digits = 2L, format = "f"),
      ifelse(
        x < 100, formatC(x, digits = 1L, format = "f"),
        formatC(x, digits = 0L, format = "f")
      )
    )
  )
}

latex_escape <- function(x) {
  x <- gsub("_", "\\\\_", x, fixed = TRUE)
  x <- gsub("%", "\\\\%", x, fixed = TRUE)
  gsub("&", "\\\\&", x, fixed = TRUE)
}

runtime_value <- function(dataset, method, route) {
  rows <- runtime[
    runtime$dataset == dataset & runtime$method == method &
      runtime$comparator_mode == route,
    , drop = FALSE
  ]
  if (nrow(rows) > 1L) {
    stop("Duplicate workflow aggregate row.", call. = FALSE)
  }
  if (!nrow(rows)) return(NA_real_)
  suppressWarnings(as.numeric(rows$elapsed_median_sec[[1L]]))
}

runtime_matrix <- function(family) {
  methods <- spec[spec$family == family, , drop = FALSE]
  output <- matrix(
    "--", nrow = nrow(methods), ncol = length(datasets),
    dimnames = list(
      paste0(methods$title, " [", methods$scope, "]"),
      table_dataset_labels
    )
  )
  for (row in seq_len(nrow(methods))) {
    for (column in seq_along(datasets)) {
      output[row, column] <- format_seconds(runtime_value(
        datasets[[column]], methods$method[[row]], methods$route[[row]]
      ))
    }
  }
  output
}

latex_runtime_panel <- function(title, matrix) {
  columns <- paste0("l", paste(rep("r", ncol(matrix)), collapse = ""))
  header <- paste(c("Method", colnames(matrix)), collapse = " & ")
  body <- vapply(seq_len(nrow(matrix)), function(index) {
    values <- c(latex_escape(rownames(matrix)[[index]]), matrix[index, ])
    paste0(paste(values, collapse = " & "), " \\\\")
  }, character(1L))
  c(
    paste0("\\textbf{", title, "}\\par\\smallskip"),
    "\\resizebox{\\textwidth}{!}{%",
    paste0("\\begin{tabular}{", columns, "}"),
    "\\toprule", paste0(header, " \\\\"), "\\midrule", body,
    "\\bottomrule", "\\end{tabular}%", "}"
  )
}

table_lines <- c(
  "\\begin{table}[p]", "\\centering",
  paste0(
    "\\caption{Median elapsed time in seconds from one release-locked ",
    "campaign. R rows report complete public fit calls; Python rows report ",
    "direct fit calls. Plotting and CSV serialization occur after timing. ",
    "The symbol -- denotes an unavailable, failed, timed-out, or unrun ",
    "combination.}"
  ),
  "\\label{tab:all-method-performance}", "\\scriptsize",
  latex_runtime_panel("A. PCA", runtime_matrix("pca")), "\\medskip",
  latex_runtime_panel("B. t-SNE", runtime_matrix("tsne")), "\\medskip",
  latex_runtime_panel("C. UMAP", runtime_matrix("umap")),
  "\\end{table}"
)
writeLines(
  table_lines, file.path(generated_dir, "table5_all_methods_runtime.tex")
)

find_output <- function(dataset, method, route) {
  path <- file.path(
    results_root, "workflow_comparators", route, dataset, method,
    "embedding.csv"
  )
  if (file.exists(path)) path else NA_character_
}

draw_placeholder <- function(title) {
  plot.new()
  plot.window(xlim = c(0, 1), ylim = c(0, 1), asp = 1)
  rect(0.03, 0.03, 0.97, 0.97, border = "#BDBDBD", col = "#F7F7F7")
  text(0.5, 0.53, title, cex = 0.9, font = 2)
  text(0.5, 0.44, "Unavailable", cex = 0.82, col = "#666666")
}

draw_output <- function(path, title) {
  if (is.na(path) || !file.exists(path)) {
    draw_placeholder(title)
  } else {
    draw_embedding_csv(path)
  }
  title(main = title, line = 0.25, cex.main = 0.88, font.main = 2)
}

render_family <- function(dataset, family) {
  methods <- spec[spec$family == family, , drop = FALSE]
  rows <- ceiling(nrow(methods) / 3L)
  output <- file.path(
    figure_dir,
    paste0(gsub("[^A-Za-z0-9]+", "_", dataset), "_", family, ".png")
  )
  grDevices::png(
    output, width = 1500, height = 500L * rows,
    res = 150, bg = "white"
  )
  old <- par(
    mfrow = c(rows, 3L), mar = c(0.1, 0.1, 1.7, 0.1),
    oma = c(0, 0, 2.3, 0), xaxs = "i", yaxs = "i"
  )
  on.exit({
    par(old)
    dev.off()
  }, add = TRUE)
  paths <- character(nrow(methods))
  for (index in seq_len(nrow(methods))) {
    paths[[index]] <- find_output(
      dataset, methods$method[[index]], methods$route[[index]]
    )
    draw_output(paths[[index]], methods$title[[index]])
  }
  empty <- rows * 3L - nrow(methods)
  if (empty > 0L) for (index in seq_len(empty)) plot.new()
  mtext(
    paste0(dataset_labels[[dataset]], " (seed 4)"), side = 3,
    outer = TRUE, line = 0.4, cex = 1.25, font = 2
  )
  data.frame(
    dataset = dataset, family = family, method = methods$title,
    source = paths, available = !is.na(paths), stringsAsFactors = FALSE
  )
}

families <- c("pca", "tsne", "umap")
manifest <- do.call(rbind, lapply(datasets, function(dataset) {
  do.call(rbind, lapply(families, function(family) {
    render_family(dataset, family)
  }))
}))
write.csv(
  manifest, file.path(generated_dir, "embedding_gallery_manifest.csv"),
  row.names = FALSE, na = ""
)

gallery_tex <- c(
  "\\clearpage", "\\section{Method output gallery}",
  paste0(
    "The following figures are rebuilt from the coordinate CSV files of ",
    "this campaign. Every panel uses the same R plotting function, label ",
    "palette, point-size policy, margins, and axis-free presentation."
  )
)
family_names <- c(pca = "PCA", tsne = "t-SNE", umap = "UMAP")
for (dataset in datasets) {
  stem <- gsub("[^A-Za-z0-9]+", "_", dataset)
  for (family in families) {
    gallery_tex <- c(
      gallery_tex, "", "\\begin{figure}[p]", "\\centering",
      paste0(
        "\\includegraphics[width=0.94\\textwidth]",
        "{", latex_figure_prefix, "/", stem, "_", family, ".png}"
      ),
      paste0(
        "\\caption{", latex_escape(dataset_labels[[dataset]]), " ",
        family_names[[family]], " outputs for the tested methods (seed 4). ",
        "Colors encode benchmark labels and were not used for fitting.}"
      ),
      "\\end{figure}", "\\clearpage"
    )
  }
}
writeLines(
  gallery_tex,
  file.path(generated_dir, "all_methods_embedding_gallery.tex")
)

cat("Wrote campaign Table 5 and method plots under", results_root, "\n")
