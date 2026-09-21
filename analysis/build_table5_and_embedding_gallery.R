#!/usr/bin/env Rscript

args <- commandArgs(trailingOnly = TRUE)
results_root <- if (length(args)) args[[1L]] else
  "/Users/stefano/Documents/fastEmbedR-results/fastEmbedR-results"
script_arg <- grep("^--file=", commandArgs(FALSE), value = TRUE)
script_path <- normalizePath(sub("^--file=", "", script_arg[[1L]]))
jss_dir <- dirname(script_path)
aggregate_dir <- if (length(args) >= 2L) args[[2L]] else
  file.path(dirname(jss_dir), "mloss", "generated")
generated_dir <- if (length(args) >= 3L) args[[3L]] else
  file.path(jss_dir, "generated")
figure_dir <- if (length(args) >= 4L) args[[4L]] else
  file.path(jss_dir, "figures", "embedding_all_methods")

dir.create(generated_dir, recursive = TRUE, showWarnings = FALSE)
dir.create(figure_dir, recursive = TRUE, showWarnings = FALSE)

if (!requireNamespace("png", quietly = TRUE)) {
  stop("The png package is required.", call. = FALSE)
}

datasets <- c(
  "COIL20", "USPS", "FashionMNIST",
  "FlowRepository_FR-FCM-ZYRM_files", "flow18", "MNIST", "imagenet",
  "MetRef", "mass41", "TabulaMuris", "Macosko2015_retina"
)
dataset_labels <- c(
  COIL20 = "COIL-20", USPS = "USPS", FashionMNIST = "Fashion-MNIST",
  "FlowRepository_FR-FCM-ZYRM_files" = "FlowRepository", flow18 = "flow18",
  MNIST = "MNIST", imagenet = "ImageNet", MetRef = "MetRef",
  mass41 = "mass41", TabulaMuris = "Tabula Muris",
  Macosko2015_retina = "Retina"
)

read_runtime <- function(filename) {
  path <- file.path(aggregate_dir, filename)
  if (!file.exists(path)) stop("Missing aggregate input: ", path)
  read.csv(path, stringsAsFactors = FALSE, check.names = FALSE)
}

tsne <- read_runtime("runtime_tsne_all_methods.csv")
umap <- read_runtime("runtime_umap_all_methods.csv")

tsne_order <- c(
  "Rtsne_full", "KlugerLab_FItSNE", "fastEmbedR_tsne_cpu_full",
  "fastEmbedR_tsne_cuda_full", "python_opentsne_fft",
  "python_opentsne_fft_direct", "rapids_cuml_tsne_full",
  "rapids_cuml_tsne_full_direct"
)
tsne_headers <- c(
  "Rtsne", "FIt-SNE", "fER CPU", "fER CUDA", "openTSNE R",
  "openTSNE Py", "cuML R", "cuML Py"
)

umap_order <- c(
  "umap_package", "uwot_default", "uwot_fast_sgd",
  "fastEmbedR_umap_cpu_fuzzy_full",
  "fastEmbedR_umap_cpu_binary_full", "python_umap_learn",
  "python_umap_learn_direct", "fastEmbedR_umap_cuda_fuzzy_full",
  "fastEmbedR_umap_cuda_binary_full", "rapids_cuml_umap_full",
  "rapids_cuml_umap_full_direct"
)
umap_headers <- c(
  "umap", "uwot", "uwot fast", "fER fuzzy CPU", "fER binary CPU",
  "umap-learn R", "umap-learn Py", "fER fuzzy CUDA",
  "fER binary CUDA", "cuML R", "cuML Py"
)

format_seconds <- function(x) {
  x <- suppressWarnings(as.numeric(x))
  ifelse(
    !is.finite(x), "--",
    ifelse(x < 10, formatC(x, digits = 2L, format = "f"),
           ifelse(x < 100, formatC(x, digits = 1L, format = "f"),
                  formatC(x, digits = 0L, format = "f")))
  )
}

latex_escape <- function(x) {
  x <- gsub("_", "\\\\_", x, fixed = TRUE)
  x <- gsub("%", "\\\\%", x, fixed = TRUE)
  gsub("&", "\\\\&", x, fixed = TRUE)
}

standard <- read_runtime("all_methods_all_datasets_standard.csv")
python <- read_runtime("python_summary_median.csv")

format_metric <- function(x) {
  x <- suppressWarnings(as.numeric(x))
  ifelse(is.finite(x), formatC(x, digits = 3L, format = "f"), "--")
}

quality_for <- function(dataset, method, backend, profile, timing_scope) {
  if (timing_scope %in% c("r_mediated_total_call", "direct_python_fit")) {
    hit <- python[
      python$dataset == dataset & python$method == method &
        python$backend == backend & python$profile == profile &
        python$timing_scope == timing_scope,
      , drop = FALSE
    ]
    if (!nrow(hit)) return(rep(NA_real_, 4L))
    return(c(
      hit$trustworthiness_median[[1L]], hit$nn_preservation_median[[1L]],
      hit$label_accuracy_median[[1L]], NA_real_
    ))
  }
  hit <- standard[
    standard$dataset == dataset & standard$method == method &
      standard$backend == backend & standard$profile == profile &
      standard$timing_scope == "full_pipeline",
    , drop = FALSE
  ]
  if (!nrow(hit)) return(rep(NA_real_, 4L))
  c(
    hit$trustworthiness_median[[1L]],
    hit$knn_preservation_30_median[[1L]],
    hit$label_knn_accuracy_median[[1L]], hit$tsne_kl_median[[1L]]
  )
}

make_performance_rows <- function(data, methods, family_label) {
  template <- unique(data[, c(
    "method", "display_label", "backend", "profile", "timing_scope"
  )])
  template <- template[match(methods, template$method), , drop = FALSE]
  output <- vector("list", length(datasets) * nrow(template))
  counter <- 0L
  for (dataset in datasets) {
    for (i in seq_len(nrow(template))) {
      counter <- counter + 1L
      info <- template[i, ]
      hit <- data[
        data$dataset == dataset & data$method == info$method,
        , drop = FALSE
      ]
      quality <- rep(NA_real_, 4L)
      runtime <- NA_real_
      if (nrow(hit)) {
        runtime <- hit$runtime[[1L]]
        quality <- quality_for(
          dataset, info$method, info$backend, info$profile,
          info$timing_scope
        )
      }
      output[[counter]] <- data.frame(
        dataset = dataset_labels[[dataset]], family = family_label,
        method = info$display_label, runtime = runtime,
        trust = quality[[1L]], preserve = quality[[2L]],
        accuracy = quality[[3L]], kl = quality[[4L]],
        stringsAsFactors = FALSE
      )
    }
  }
  do.call(rbind, output)
}

performance <- rbind(
  make_performance_rows(tsne, tsne_order, "t-SNE"),
  make_performance_rows(umap, umap_order, "UMAP")
)
performance$dataset <- factor(
  performance$dataset, levels = unname(dataset_labels[datasets])
)
performance$family <- factor(performance$family, levels = c("t-SNE", "UMAP"))
performance <- performance[order(performance$dataset, performance$family), ]

table_header <- c(
  "\\toprule",
  "Data set & Family & Method and timing route & Seconds & Trust & P@30 & Acc. & KL \\\\",
  "\\midrule"
)
table_lines <- c(
  "\\begingroup",
  "\\scriptsize",
  "\\setlength{\\tabcolsep}{2.2pt}",
  "\\begin{longtable}{p{1.65cm}p{0.9cm}p{3.8cm}rrrrr}",
  paste0(
    "\\caption{Performance of every tested R and Python method on every data ",
    "set. Values are medians over available seeds. Seconds denote complete R ",
    "public calls, complete R-mediated calls, or direct-Python fit-only time ",
    "as stated in the method label. Trust is trustworthiness, P@30 is ",
    "30-neighbor preservation, Acc. is embedding-space label KNN accuracy, ",
    "and KL is the t-SNE Kullback--Leibler divergence when available. ",
    "\\texttt{--} denotes an unavailable, failed, timed-out, unrun, or ",
    "inapplicable value.}\\label{tab:all-method-performance}\\\\"
  ),
  table_header,
  "\\endfirsthead",
  "\\multicolumn{8}{c}{\\tablename\\ \\thetable{} -- continued} \\\\",
  table_header,
  "\\endhead",
  "\\midrule",
  "\\multicolumn{8}{r}{Continued on next page} \\\\",
  "\\endfoot",
  "\\bottomrule",
  "\\endlastfoot"
)
for (i in seq_len(nrow(performance))) {
  row <- performance[i, ]
  dataset_text <- as.character(row$dataset)
  if (dataset_text == "FlowRepository") dataset_text <- "FlowRepo."
  dataset_text <- latex_escape(dataset_text)
  family_text <- as.character(row$family)
  table_lines <- c(
    table_lines,
    paste(
      c(
        dataset_text, family_text, latex_escape(row$method),
        format_seconds(row$runtime), format_metric(row$trust),
        format_metric(row$preserve), format_metric(row$accuracy),
        format_metric(row$kl)
      ),
      collapse = " & "
    ) |> paste0(" \\\\")
  )
  current_dataset <- as.character(row$dataset)
  current_family <- as.character(row$family)
  next_row_new_group <- i == nrow(performance) ||
    as.character(performance$dataset[[i + 1L]]) != current_dataset ||
    as.character(performance$family[[i + 1L]]) != current_family
  if (next_row_new_group && i < nrow(performance)) {
    table_lines <- c(table_lines, "\\addlinespace[2pt]")
  }
}
table_lines <- c(table_lines, "\\end{longtable}", "\\endgroup")
writeLines(table_lines,
           file.path(generated_dir, "table5_all_methods_runtime.tex"))

spec <- data.frame(
  family = c(rep("tsne", 6L), rep("umap", 9L)),
  token = c(
    "Rtsne_full", "KlugerLab_FItSNE",
    "fastEmbedR_(opentsne|tsne)_cpu_full",
    "fastEmbedR_(opentsne|tsne)_cuda_full",
    "python_opentsne_fft(_direct)?",
    "rapids_cuml_tsne_full", "umap_package", "uwot_default",
    "uwot_fast_sgd", "fastEmbedR_umap_cpu_fuzzy_full",
    "fastEmbedR_umap_cpu_binary_full",
    "fastEmbedR_umap_cuda_fuzzy_full",
    "fastEmbedR_umap_cuda_binary_full", "python_umap_learn",
    "rapids_cuml_umap_full"
  ),
  profile = c(
    "standard/cpu4", "standard/cpu4", "standard/cpu4", "standard/cuda",
    "python/cpu4", "standard/cuda", "standard/cpu4", "standard/cpu4",
    "standard/cpu4", "standard/cpu4", "standard/cpu4", "standard/cuda",
    "standard/cuda", "python/cpu4", "standard/cuda"
  ),
  title = c(
    "Rtsne", "FIt-SNE", "fastEmbedR::tsne [CPU]",
    "fastEmbedR::tsne [CUDA]", "Python openTSNE",
    "RAPIDS cuML t-SNE", "umap", "uwot", "uwot fast SGD",
    "fastEmbedR fuzzy [CPU]", "fastEmbedR binary [CPU]",
    "fastEmbedR fuzzy [CUDA]", "fastEmbedR binary [CUDA]",
    "Python umap-learn", "RAPIDS cuML UMAP"
  ),
  stringsAsFactors = FALSE
)

find_plot <- function(dataset, token, profile) {
  root <- file.path(results_root, dataset)
  if (!dir.exists(root)) return(NA_character_)
  files <- list.files(root, pattern = "seed4[.]png$", recursive = TRUE,
                      full.names = TRUE)
  normalized <- gsub("\\\\", "/", files)
  profile_hit <- grepl(paste0("/", profile, "/"), normalized, fixed = TRUE)
  token_hit <- grepl(paste0("_", token, "_threads[0-9]+_seed4[.]png$"),
                     basename(files), perl = TRUE)
  hits <- files[profile_hit & token_hit]
  if (!length(hits)) return(NA_character_)
  hits[[which.max(file.info(hits)$mtime)]]
}

draw_placeholder <- function(title) {
  plot.new()
  plot.window(xlim = c(0, 1), ylim = c(0, 1), asp = 1)
  rect(0.03, 0.03, 0.97, 0.97, border = "#BDBDBD", col = "#F7F7F7")
  text(0.5, 0.53, title, cex = 0.9, font = 2)
  text(0.5, 0.44, "Unavailable", cex = 0.82, col = "#666666")
}

draw_image <- function(path, title) {
  if (is.na(path) || !file.exists(path)) {
    draw_placeholder(title)
  } else {
    image <- png::readPNG(path)
    plot.new()
    plot.window(xlim = c(0, 1), ylim = c(0, 1), asp = 1)
    rasterImage(image, 0, 0, 1, 1, interpolate = TRUE)
  }
  title(main = title, line = 0.25, cex.main = 0.92, font.main = 2)
}

render_family <- function(dataset, family) {
  methods <- spec[spec$family == family, , drop = FALSE]
  nrow_layout <- if (family == "tsne") 2L else 3L
  output <- file.path(
    figure_dir,
    paste0(gsub("[^A-Za-z0-9]+", "_", dataset), "_", family, ".png")
  )
  grDevices::png(
    output, width = 1500,
    height = if (family == "tsne") 1000 else 1375,
    res = 150, bg = "white"
  )
  old <- par(mfrow = c(nrow_layout, 3L), mar = c(0.1, 0.1, 1.7, 0.1),
             oma = c(0, 0, 2.3, 0), xaxs = "i", yaxs = "i")
  paths <- character(nrow(methods))
  for (i in seq_len(nrow(methods))) {
    paths[[i]] <- find_plot(dataset, methods$token[[i]], methods$profile[[i]])
    draw_image(paths[[i]], methods$title[[i]])
  }
  mtext(paste0(dataset_labels[[dataset]], " (seed 4)"), side = 3,
        outer = TRUE, line = 0.4, cex = 1.25, font = 2)
  par(old)
  dev.off()
  data.frame(dataset = dataset, family = family, method = methods$title,
             source = paths, available = !is.na(paths), stringsAsFactors = FALSE)
}

manifest <- do.call(rbind, lapply(datasets, function(dataset) {
  rbind(render_family(dataset, "tsne"), render_family(dataset, "umap"))
}))
write.csv(manifest, file.path(generated_dir, "embedding_gallery_manifest.csv"),
          row.names = FALSE, na = "")

gallery_tex <- c(
  "\\clearpage",
  "\\section{Embedding output gallery}",
  paste0(
    "Figures~\\ref{fig:gallery-first}--\\ref{fig:gallery-last} show seed-4 ",
    "layouts for every unique implementation represented in Table~",
    "\\ref{tab:all-method-performance}. Direct-Python and R-mediated timing ",
    "routes are not duplicated when they invoke the same implementation. ",
    "Unavailable combinations are marked explicitly."
  )
)

for (dataset_index in seq_along(datasets)) {
  dataset <- datasets[[dataset_index]]
  stem <- gsub("[^A-Za-z0-9]+", "_", dataset)
  for (family in c("tsne", "umap")) {
    label <- paste0("fig:gallery-", tolower(stem), "-", family)
    if (dataset_index == 1L && family == "tsne") label <- "fig:gallery-first"
    if (dataset_index == length(datasets) && family == "umap") {
      label <- "fig:gallery-last"
    }
    family_title <- if (family == "tsne") "t-SNE" else "UMAP"
    gallery_tex <- c(
      gallery_tex,
      "",
      if (dataset_index == 1L && family == "tsne") {
        "\\begin{figure}[htbp]"
      } else {
        "\\begin{figure}[p]"
      },
      "\\centering",
      paste0(
        "\\includegraphics[width=0.94\\textwidth]{figures/embedding_all_methods/",
        stem, "_", family, ".png}"
      ),
      paste0(
        "\\caption{", latex_escape(dataset_labels[[dataset]]), " ",
        family_title, " output layouts for the tested unique implementations ",
        "(seed 4). Colors encode the benchmark labels and were not used for fitting.}"
      ),
      paste0("\\label{", label, "}"),
      "\\end{figure}",
      "\\clearpage"
    )
  }
}
writeLines(gallery_tex,
           file.path(generated_dir, "all_methods_embedding_gallery.tex"))

cat("Wrote Table 5 and embedding gallery under", jss_dir, "\n")
