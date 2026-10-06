#!/usr/bin/env Rscript

args <- commandArgs(trailingOnly = TRUE)
if (!length(args)) {
  stop(
    "Usage: build_table5_and_embedding_gallery.R RESULTS_ROOT ...",
    call. = FALSE
  )
}
runtime_only <- length(args) == 5L &&
  identical(args[[5L]], "--runtime-only")
if (length(args) > 5L || (length(args) == 5L && !runtime_only)) {
  stop("The optional fifth argument must be --runtime-only.")
}
results_root <- normalizePath(args[[1L]], mustWork = TRUE)
campaign_root <- dirname(results_root)
campaign_id <- basename(campaign_root)
audit_path <- file.path(campaign_root, "final_audit.txt")
audit_lines <- if (file.exists(audit_path)) {
  readLines(audit_path, warn = FALSE)
} else {
  character()
}
audit_status <- if ("status=PASS" %in% audit_lines) {
  "PASS"
} else if ("status=FAIL" %in% audit_lines) {
  "FAIL"
} else {
  "INCOMPLETE"
}
evidence_label <- if (audit_status == "PASS") {
  "release-audited"
} else if (audit_status == "FAIL") {
  "diagnostic, failed audit"
} else {
  "diagnostic, incomplete campaign"
}
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
input_rows <- do.call(rbind, lapply(datasets, function(dataset) {
  path <- file.path(
    campaign_root, "input", dataset, "workflow_comparators",
    "manifest.csv"
  )
  if (!file.exists(path)) stop("Missing comparator manifest: ", path)
  row <- read.csv(path, stringsAsFactors = FALSE)
  if (!"source_n" %in% names(row)) {
    source_path <- file.path(campaign_root, "input", dataset,
                             "manifest.csv")
    source <- read.csv(source_path, stringsAsFactors = FALSE)
    row$source_n <- source$source_n
  }
  data.frame(
    dataset = row$dataset, source_n = row$source_n,
    benchmark_n = row$n
  )
}))
if (anyNA(input_rows) || any(input_rows$benchmark_n > input_rows$source_n)) {
  stop("Invalid source or fitted row counts in input manifests.")
}
capped <- input_rows$dataset[input_rows$benchmark_n < input_rows$source_n]
cap_note <- if (length(capped)) {
  paste0(" ", length(capped), " data sets use capped fitting inputs; ",
         "source and fitted row counts are listed in the manuscript.")
} else {
  " All fits use the full source matrix."
}
row_count_label <- function(dataset) {
  count <- input_rows[input_rows$dataset == dataset, , drop = FALSE]
  if (count$benchmark_n < count$source_n) {
    return(paste0("fitted ", format(count$benchmark_n, big.mark = ","),
                  " of ", format(count$source_n, big.mark = ","),
                  " rows"))
  }
  paste0(format(count$benchmark_n, big.mark = ","), " rows")
}

spec <- data.frame(
  family = c(rep("pca", 5L), rep("tsne", 7L), rep("umap", 9L)),
  method = c(
    "fastembedr_pca", "irlba_pca", "fastembedr_pca",
    "sklearn_pca", "cuml_pca", "rtsne", "fitsne",
    "fastembedr_tsne", "fastembedr_tsne", "sklearn_tsne",
    "python_opentsne", "cuml_tsne", "r_umap", "uwot",
    "uwot_fast_sgd", "fastembedr_umap",
    "fastembedr_umap_binary", "fastembedr_umap",
    "fastembedr_umap_binary",
    "python_umap", "cuml_umap"
  ),
  route = c(
    "r_cpu", "r_cpu", "r_cuda", "python_cpu",
    "python_cuda", "r_cpu", "r_cpu", "r_cpu", "r_cuda",
    "python_cpu", "python_cpu", "python_cuda", "r_cpu", "r_cpu",
    "r_cpu", "r_cpu", "r_cpu", "r_cuda", "r_cuda",
    "python_cpu", "python_cuda"
  ),
  title = c(
    "fastEmbedR PCA [CPU]", "irlba [CPU]",
    "fastEmbedR PCA [CUDA]", "scikit-learn PCA [Python]",
    "RAPIDS cuML PCA [CUDA]", "Rtsne [CPU]", "FIt-SNE [CPU]",
    "fastEmbedR t-SNE [CPU]", "fastEmbedR t-SNE [CUDA]",
    "scikit-learn t-SNE [Python]", "openTSNE [Python]",
    "RAPIDS cuML t-SNE [CUDA]", "umap [CPU]", "uwot [CPU]",
    "uwot fast SGD [CPU]", "fastEmbedR fuzzy UMAP [CPU]",
    "fastEmbedR binary UMAP [CPU]", "fastEmbedR fuzzy UMAP [CUDA]",
    "fastEmbedR binary UMAP [CUDA]", "umap-learn [Python]",
    "RAPIDS cuML UMAP [CUDA]"
  ),
  scope = c(
    rep("R total", 3L), "Python fit", "Python fit",
    rep("R total", 4L), rep("Python fit", 3L), rep("R total", 7L),
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
outcomes_path <- file.path(
  results_root, "aggregate", "workflow_comparator_outcomes.csv"
)
outcomes <- if (file.exists(outcomes_path)) {
  read.csv(outcomes_path, stringsAsFactors = FALSE)
} else {
  NULL
}
required_runtime <- c(
  "comparator_mode", "dataset", "method", "elapsed_median_sec",
  "elapsed_q1_sec", "elapsed_q3_sec", "timing_eligible",
  "timing_scope"
)
if (!all(required_runtime %in% names(runtime))) {
  stop("The workflow aggregate has an invalid schema.", call. = FALSE)
}

format_seconds <- function(x) {
  x <- suppressWarnings(as.numeric(x))
  vapply(x, function(value) {
    if (!is.finite(value)) return("--")
    digits <- if (value < 0.1) 3L else if (value < 10) 2L else
      if (value < 100) 1L else 0L
    formatC(value, digits = digits, format = "f")
  }, character(1L))
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
  if (!nrow(rows)) {
    return(list(seconds = NA_real_, repeated = FALSE))
  }
  list(
    seconds = suppressWarnings(as.numeric(
      rows$elapsed_median_sec[[1L]]
    )),
    repeated = identical(
      tolower(as.character(rows$timing_eligible[[1L]])), "true"
    )
  )
}

outcome_value <- function(dataset, method, route) {
  if (!is.null(outcomes)) {
    row <- outcomes[
      outcomes$dataset == dataset & outcomes$method == method &
        outcomes$comparator_mode == route, , drop = FALSE
    ]
    if (nrow(row)) return(row$status[[nrow(row)]])
  }
  path <- file.path(
    results_root, "workflow_comparators", route, dataset,
    method, "status.csv"
  )
  if (!file.exists(path)) return("not_run")
  row <- read.csv(path, stringsAsFactors = FALSE)
  if (!nrow(row)) return("missing_status")
  row$status[[nrow(row)]]
}

outcome_symbol <- function(status) {
  symbols <- c(
    timeout = "T", memory_limit = "M", failed = "F",
    killed_unclassified = "K", unsupported = "U",
    cancelled = "C", success = "I", not_run = "--",
    missing_status = "--"
  )
  symbol <- unname(symbols[status])
  if (is.na(symbol)) "?" else symbol
}

runtime_matrix <- function(family) {
  methods <- spec[spec$family == family, , drop = FALSE]
  output <- matrix(
    "--", nrow = nrow(methods), ncol = length(datasets),
    dimnames = list(
      methods$title,
      table_dataset_labels
    )
  )
  for (row in seq_len(nrow(methods))) {
    for (column in seq_along(datasets)) {
      timing <- runtime_value(
        datasets[[column]], methods$method[[row]], methods$route[[row]]
      )
      status <- outcome_value(
        datasets[[column]], methods$method[[row]], methods$route[[row]]
      )
      output[row, column] <- if (status == "success" &&
                                is.finite(timing$seconds) &&
                                timing$seconds > 0) {
        paste0(format_seconds(timing$seconds),
               if (timing$repeated) "" else "*")
      } else {
        outcome_symbol(status)
      }
    }
  }
  list(methods = methods, values = output)
}

latex_runtime_panel <- function(family, title) {
  result <- runtime_matrix(family)
  methods <- result$methods
  values <- result$values
  blocks <- split(seq_len(ncol(values)),
                  ceiling(seq_len(ncol(values)) / 6L))
  unlist(lapply(seq_along(blocks), function(block) {
    indices <- blocks[[block]]
    part <- values[, indices, drop = FALSE]
    blanks <- rep("", 6L - length(indices))
    header <- c("Method", "Scope", colnames(part), blanks)
    body <- vapply(seq_len(nrow(part)), function(index) {
      scope <- if (methods$scope[[index]] == "R total") {
        "R call"
      } else "Py fit"
      label <- methods$title[[index]]
      label <- sub("^fastEmbedR (fuzzy|binary) UMAP ",
                   "fastEmbedR \\1 ", label)
      label <- sub("^fastEmbedR (PCA|t-SNE) ", "fastEmbedR ", label)
      label <- sub("^RAPIDS cuML (PCA|t-SNE|UMAP) ",
                   "cuML ", label)
      cells <- c(latex_escape(label), scope,
                 part[index, ], blanks)
      paste0(paste(cells, collapse = " & "), " \\\\")
    }, character(1L))
    c(paste0("\\multicolumn{8}{@{}l}{\\textbf{", title,
             ", data sets ", block, "/2}} \\\\"),
      "\\midrule", paste0(paste(header, collapse = " & "), " \\\\"),
      "\\midrule", body, "\\addlinespace", "\\midrule")
  }), use.names = FALSE)
}

table_lines <- c(
  "\\begingroup", "\\footnotesize", "\\setlength{\\tabcolsep}{2pt}",
  "\\begin{longtable}{@{}p{0.34\\textwidth}lrrrrrr@{}}",
  paste0(
    "\\caption{Observed elapsed time in seconds from campaign ",
    latex_escape(campaign_id), " (", evidence_label, "). ",
    "R call and direct Python fit use different timing boundaries.",
    cap_note, "}\\label{tab:all-method-performance}\\\\"
  ),
  "\\toprule",
  "\\multicolumn{8}{@{}l}{PCA, t-SNE, and UMAP methods} \\\\",
  "\\midrule", "\\endfirsthead",
  "\\toprule",
  "\\multicolumn{8}{@{}l}{Runtime table, continued} \\\\",
  "\\midrule", "\\endhead",
  latex_runtime_panel("pca", "A. PCA"),
  latex_runtime_panel("tsne", "B. t-SNE"),
  latex_runtime_panel("umap", "C. UMAP"),
  "\\bottomrule", "\\end{longtable}", "\\endgroup"
)
writeLines(
  table_lines,
  file.path(generated_dir, "table_all_methods_runtime_supp.tex")
)
runtime_rows <- do.call(rbind, lapply(c("pca", "tsne", "umap"),
  function(family) {
    result <- runtime_matrix(family)
    data.frame(
      family = family, method = result$methods$title,
      scope = ifelse(result$methods$scope == "R total",
                     "R call", "Py fit"),
      result$values, check.names = FALSE
    )
  }))
write.csv(runtime_rows,
  file.path(generated_dir, "table_all_methods_runtime_supp.csv"),
  row.names = FALSE)

if (!"peak_host_gib" %in% names(runtime)) {
  runtime$peak_host_gib <- as.numeric(runtime$max_rss_kb) / 1024^2
}
if (!"peak_device_incremental_gib" %in% names(runtime)) {
  runtime$peak_device_incremental_gib <-
    as.numeric(runtime$peak_incremental_mib) / 1024
}
if (!"device_samples_n" %in% names(runtime)) {
  runtime$device_samples_n <- NA_integer_
}
if (!"baseline_mib" %in% names(runtime)) {
  runtime$baseline_mib <- NA_real_
}
memory <- do.call(rbind, lapply(seq_len(nrow(spec)), function(i) {
  do.call(rbind, lapply(datasets, function(dataset) {
    entry <- spec[i, ]
    row <- runtime[
      runtime$dataset == dataset &
        runtime$method == entry$method &
        runtime$comparator_mode == entry$route, , drop = FALSE
    ]
    if (nrow(row) > 1L) stop("Duplicate comparator memory row.")
    status <- outcome_value(dataset, entry$method, entry$route)
    completed <- status %in% c("success", "completed")
    host <- if (completed && nrow(row)) row$peak_host_gib[[1L]] else NA
    device <- if (completed && nrow(row)) {
      row$peak_device_incremental_gib[[1L]]
    } else NA
    data.frame(
      dataset = dataset, family = entry$family,
      method = entry$method, route = entry$route,
      title = entry$title, status = status,
      fit_n = if (nrow(row)) row$n[[1L]] else NA,
      peak_host_gib = as.numeric(host),
      peak_device_incremental_gib = as.numeric(device),
      device_baseline_gib = if (nrow(row)) {
        as.numeric(row$baseline_mib[[1L]]) / 1024
      } else NA_real_,
      device_samples_n = if (nrow(row)) {
        as.integer(row$device_samples_n[[1L]])
      } else NA_integer_
    )
  }))
}))
completed <- memory$status %in% c("success", "completed")
missing_host <- completed & (!is.finite(memory$peak_host_gib) |
  memory$peak_host_gib <= 0)
missing_device <- completed & grepl("cuda", memory$route) &
  (!is.finite(memory$peak_device_incremental_gib) |
    memory$peak_device_incremental_gib <= 0)
missing_peak <- memory[missing_host | missing_device,
  c("dataset", "method", "route", "status")]
missing_peak$missing_host <- missing_host[missing_host | missing_device]
missing_peak$missing_device <- missing_device[missing_host | missing_device]
write.csv(missing_peak,
  file.path(generated_dir, "peak_memory_missing.csv"), row.names = FALSE)
if (audit_status == "PASS" && nrow(missing_peak)) {
  stop("A passing campaign cannot have missing peak-memory evidence.")
}
write.csv(memory, file.path(generated_dir, "peak_memory_by_dataset.csv"),
          row.names = FALSE, na = "")
finite_peak <- function(x) {
  x <- x[is.finite(x) & x > 0]
  c(n = length(x), median = if (length(x)) median(x) else NA,
    maximum = if (length(x)) max(x) else NA)
}
memory_summary <- do.call(rbind, lapply(seq_len(nrow(spec)), function(i) {
  entry <- spec[i, ]
  rows <- memory[memory$method == entry$method &
                   memory$route == entry$route, ]
  host <- finite_peak(rows$peak_host_gib)
  device <- finite_peak(rows$peak_device_incremental_gib)
  data.frame(
    family = entry$family, method = entry$method,
    route = entry$route, title = entry$title,
    completed_datasets = sum(rows$status %in% c("success", "completed")),
    host_measured = host[["n"]], peak_host_median_gib = host[["median"]],
    peak_host_max_gib = host[["maximum"]],
    device_measured = device[["n"]],
    peak_device_median_gib = device[["median"]],
    peak_device_max_gib = device[["maximum"]]
  )
}))
write.csv(memory_summary,
          file.path(generated_dir, "peak_memory_summary.csv"),
          row.names = FALSE, na = "")
format_peak <- function(x) {
  ifelse(is.finite(x), formatC(x, format = "f", digits = 2L), "--")
}
host_lines <- vapply(seq_len(nrow(memory_summary)), function(i) {
  row <- memory_summary[i, ]
  paste0(paste(c(latex_escape(row$title), row$completed_datasets,
    row$host_measured,
    format_peak(row$peak_host_median_gib),
    format_peak(row$peak_host_max_gib)), collapse = " & "), " \\\\")
}, character(1L))
device_rows <- memory_summary[grepl("cuda", memory_summary$route), ]
device_lines <- vapply(seq_len(nrow(device_rows)), function(i) {
  row <- device_rows[i, ]
  paste0(paste(c(latex_escape(row$title), row$completed_datasets,
    row$device_measured, format_peak(row$peak_device_median_gib),
    format_peak(row$peak_device_max_gib)), collapse = " & "), " \\\\")
}, character(1L))
writeLines(c(
  "\\begin{table}[!htbp]", "\\centering", "\\scriptsize",
  paste0("\\caption{Observed peak memory in campaign ",
    latex_escape(campaign_id), " (", evidence_label, "). ",
    "Host RSS covers the complete worker, including data loading and ",
    "quality assessment; it is not fit-only memory. CUDA values are ",
    "sampled device-memory increases above the pre-worker baseline ",
    "(nominal 0.2-s polling plus query time), so short peaks may be ",
    "underestimated. Values are GiB; -- indicates no valid ",
    "measurement. Counts show valid data sets for each memory ",
    "metric; missing measurements are archived separately.}" ),
  "\\label{tab:peak-memory}",
  "\\textbf{A. Host peak RSS}\\par\\smallskip",
  "\\begin{tabular}{p{0.48\\textwidth}rrrr}", "\\toprule",
  "Method & Completed & Measured & Median & Maximum \\\\",
  "\\midrule", host_lines, "\\bottomrule", "\\end{tabular}",
  "\\par\\medskip",
  "\\textbf{B. CUDA device-memory increase}\\par\\smallskip",
  "\\begin{tabular}{p{0.48\\textwidth}rrrr}", "\\toprule",
  "Method & Completed & Measured & Median & Maximum \\\\",
  "\\midrule", device_lines, "\\bottomrule", "\\end{tabular}",
  "\\end{table}"
), file.path(generated_dir, "table_peak_memory.tex"))

render_runtime <- function(family) {
  if (!requireNamespace("ggplot2", quietly = TRUE)) {
    stop("ggplot2 is required for runtime figures.", call. = FALSE)
  }
  methods <- spec[spec$family == family, , drop = FALSE]
  data <- merge(
    runtime, methods,
    by.x = c("method", "comparator_mode"),
    by.y = c("method", "route")
  )
  data$status <- mapply(
    outcome_value, data$dataset, data$method, data$comparator_mode,
    USE.NAMES = FALSE
  )
  data <- data[data$status == "success", ]
  seconds <- suppressWarnings(as.numeric(data$elapsed_median_sec))
  data <- data[is.finite(seconds) & seconds > 0, ]
  data$elapsed_median_sec <- as.numeric(data$elapsed_median_sec)
  data$elapsed_q1_sec <- as.numeric(data$elapsed_q1_sec)
  data$elapsed_q3_sec <- as.numeric(data$elapsed_q3_sec)
  data$elapsed_q1_sec[!is.finite(data$elapsed_q1_sec)] <-
    data$elapsed_median_sec[!is.finite(data$elapsed_q1_sec)]
  data$elapsed_q3_sec[!is.finite(data$elapsed_q3_sec)] <-
    data$elapsed_median_sec[!is.finite(data$elapsed_q3_sec)]
  data$dataset <- factor(data$dataset, levels = datasets,
                         labels = unname(dataset_labels[datasets]))
  data$plot_label <- data$title
  data$plot_label <- sub("^fastEmbedR fuzzy UMAP",
                         "fastEmbedR fuzzy", data$plot_label)
  data$plot_label <- sub("^fastEmbedR binary UMAP",
                         "fastEmbedR binary", data$plot_label)
  data$plot_label <- sub("^fastEmbedR (t-SNE|PCA)",
                         "fastEmbedR", data$plot_label)
  data$plot_label <- sub("^RAPIDS cuML.*\\[CUDA\\]$",
                         "cuML CUDA", data$plot_label)
  data$plot_label <- sub("^scikit-learn (t-SNE|PCA)",
                         "scikit-learn", data$plot_label)
  data$plot_label <- sub(" \\[Python\\]$", "", data$plot_label)
  data$plot_label <- sub(" \\[(CPU|CUDA)\\]$",
                         " \\1", data$plot_label)
  data$scope_label <- paste0(
    ifelse(data$scope == "R total", "R call", "Python fit"),
    ifelse(tolower(as.character(data$timing_eligible)) == "true",
           "; repeated", "; one fit")
  )
  position <- ggplot2::position_dodge(width = 0.78)
  plot <- ggplot2::ggplot(data, ggplot2::aes(
    dataset, elapsed_median_sec, colour = plot_label,
    shape = scope_label, group = plot_label
  )) +
    ggplot2::geom_errorbar(ggplot2::aes(
      ymin = elapsed_q1_sec, ymax = elapsed_q3_sec
    ), width = 0.12, position = position) +
    ggplot2::geom_point(position = position, size = 3.4) +
    ggplot2::scale_y_log10() +
    ggplot2::scale_shape_manual(values = c(
      "R call; repeated" = 16, "R call; one fit" = 1,
      "Python fit; repeated" = 17, "Python fit; one fit" = 2
    )) +
    ggplot2::coord_flip() +
    ggplot2::labs(
      x = NULL, y = "Elapsed time (s, log scale)",
      colour = NULL, shape = "Timing boundary"
    ) +
    ggplot2::theme_minimal(base_size = 14) +
    ggplot2::theme(
      axis.text.y = ggplot2::element_text(size = 13),
      legend.position = "bottom",
      legend.box = "vertical",
      legend.text = ggplot2::element_text(size = 10),
      legend.title = ggplot2::element_text(size = 10),
      plot.margin = ggplot2::margin(8, 18, 8, 8)
    ) +
    ggplot2::guides(
      colour = ggplot2::guide_legend(
        ncol = 3L, byrow = TRUE,
        override.aes = list(shape = 16)
      ),
      shape = ggplot2::guide_legend(nrow = 2L)
    )
  ggplot2::ggsave(
    file.path(dirname(figure_dir), paste0(
      "diagnostic_runtime_", family, ".pdf"
  )), plot, width = 7.2, height = 6.8, units = "in"
  )
  ggplot2::ggsave(
    file.path(dirname(figure_dir), paste0(
      "diagnostic_runtime_", family, ".png"
  )), plot, width = 7.2, height = 6.8, units = "in", dpi = 180
  )
}

render_runtime("pca")
render_runtime("tsne")
render_runtime("umap")
if (runtime_only) quit(save = "no")

find_output <- function(dataset, method, route) {
  path <- embedding_csv_path(file.path(
    results_root, "workflow_comparators", route, dataset, method
  ))
  if (file.exists(path)) path else NA_character_
}

draw_placeholder <- function(title) {
  plot.new()
  plot.window(xlim = c(0, 1), ylim = c(0, 1), asp = 1)
  rect(0.03, 0.03, 0.97, 0.97, border = "#BDBDBD", col = "#F7F7F7")
  text(0.5, 0.5, "Unavailable", cex = 0.82, col = "#666666")
}

draw_output <- function(path, title) {
  if (is.na(path) || !file.exists(path)) {
    draw_placeholder(title)
  } else {
    data <- read_embedding_csv(path)
    layout <- data$layout
    plot(
      layout[, 1L], layout[, 2L], pch = 16,
      cex = point_size(nrow(layout)),
      col = label_colors(data$labels),
      axes = FALSE, ann = FALSE, frame.plot = FALSE
    )
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
  count_label <- row_count_label(dataset)
  mtext(
    paste0(dataset_labels[[dataset]], " (seed 4; ", count_label, ")"),
    side = 3,
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

gallery_tex <- character()
family_names <- c(pca = "PCA", tsne = "t-SNE", umap = "UMAP")
for (dataset in datasets) {
  stem <- gsub("[^A-Za-z0-9]+", "_", dataset)
  count_label <- row_count_label(dataset)
  for (family in families) {
    gallery_tex <- c(
      gallery_tex, "", "\\begin{figure}[p]", "\\centering",
      paste0(
        "\\includegraphics[width=0.94\\textwidth]",
        "{", latex_figure_prefix, "/", stem, "_", family, ".png}"
      ),
      paste0(
        "\\caption{", latex_escape(dataset_labels[[dataset]]), " ",
        family_names[[family]], " outputs for the tested methods ",
        "(seed 4; ", count_label, "). ",
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
