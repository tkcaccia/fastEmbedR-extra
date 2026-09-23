#!/usr/bin/env Rscript

# Aggregate the newest CPU1, CPU4, and CUDA clustering-validation runs. This
# script never relabels CUDA graph construction as CUDA clustering.

args <- commandArgs(trailingOnly = TRUE)
parse_args <- function(x) {
  out <- list()
  for (arg in x) {
    if (!startsWith(arg, "--")) next
    pair <- strsplit(sub("^--", "", arg), "=", fixed = TRUE)[[1L]]
    out[[gsub("-", "_", pair[[1L]])]] <- if (length(pair) > 1L) {
      paste(pair[-1L], collapse = "=")
    } else {
      "TRUE"
    }
  }
  out
}
`%||%` <- function(x, y) if (is.null(x) || !length(x)) y else x

options <- parse_args(args)
base_dir <- normalizePath(
  options$base_dir %||% "/scratch/firenze/NN",
  mustWork = FALSE
)
root <- normalizePath(
  options$results_root %||%
    file.path(base_dir, "fastEmbedR-results", "clustering_validation"),
  mustWork = FALSE
)
out_dir <- normalizePath(
  options$out_dir %||%
    file.path(root, paste0("aggregate_", format(Sys.time(), "%Y%m%d_%H%M%S"))),
  mustWork = FALSE
)
dir.create(out_dir, recursive = TRUE, showWarnings = FALSE)

latest_file <- function(profile) {
  folder <- file.path(root, profile)
  candidates <- list.files(
    folder,
    pattern = "^clustering_validation_runs\\.csv$",
    recursive = TRUE,
    full.names = TRUE
  )
  if (!length(candidates)) return(character())
  run_dir <- basename(dirname(candidates))
  candidates[[order(run_dir, decreasing = TRUE)[[1L]]]]
}

paths <- unlist(lapply(c("cpu1", "cpu4", "cuda"), latest_file), use.names = FALSE)
if (!length(paths)) stop("No clustering validation runs found under ", root)

rows <- lapply(paths, function(path) {
  value <- read.csv(path, stringsAsFactors = FALSE, check.names = FALSE)
  profile <- basename(dirname(dirname(path)))
  value$profile <- profile
  value$source_file <- path
  value
})
runs <- do.call(rbind, rows)
rownames(runs) <- NULL
write.csv(
  runs,
  file.path(out_dir, "clustering_validation_all_runs.csv"),
  row.names = FALSE,
  na = ""
)

success <- runs[runs$status == "success", , drop = FALSE]
if (!nrow(success)) stop("No successful clustering rows were found.")

summarize_numeric <- function(x) {
  x <- suppressWarnings(as.numeric(x))
  x <- x[is.finite(x)]
  if (!length(x)) return(c(median = NA, q1 = NA, q3 = NA))
  c(
    median = median(x),
    q1 = unname(quantile(x, 0.25)),
    q3 = unname(quantile(x, 0.75))
  )
}

key <- interaction(
  success$dataset,
  success$method,
  success$engine,
  success$profile,
  drop = TRUE
)
summary_rows <- lapply(split(success, key), function(x) {
  runtime <- summarize_numeric(x$cluster_sec)
  ari <- summarize_numeric(x$reference_ari)
  nmi <- summarize_numeric(x$reference_nmi)
  modularity_delta <- summarize_numeric(abs(x$modularity_delta_from_igraph))
  data.frame(
    dataset = x$dataset[[1L]],
    method = x$method[[1L]],
    engine = x$engine[[1L]],
    profile = x$profile[[1L]],
    graph_backend_used = x$graph_backend_used[[1L]],
    clustering_backend_used = x$clustering_backend_used[[1L]],
    requested_threads = x$requested_threads[[1L]],
    clustering_threads = x$clustering_threads[[1L]],
    n_benchmark = x$n_benchmark[[1L]],
    seeds = nrow(x),
    cluster_sec_median = runtime[["median"]],
    cluster_sec_q1 = runtime[["q1"]],
    cluster_sec_q3 = runtime[["q3"]],
    reference_ari_median = ari[["median"]],
    reference_nmi_median = nmi[["median"]],
    abs_modularity_delta_median = modularity_delta[["median"]],
    label_ari_median = median(x$label_ari, na.rm = TRUE),
    label_nmi_median = median(x$label_nmi, na.rm = TRUE),
    stringsAsFactors = FALSE
  )
})
summary <- do.call(rbind, summary_rows)
rownames(summary) <- NULL
write.csv(
  summary,
  file.path(out_dir, "clustering_validation_summary.csv"),
  row.names = FALSE,
  na = ""
)

graph_rows <- unique(success[c(
  "dataset", "profile", "graph_backend_used", "requested_threads",
  "n_benchmark", "graph_sec", "graph_peak_rss_gb",
  "graph_gpu_memory_delta_mb", "source_file"
)])
write.csv(
  graph_rows,
  file.path(out_dir, "graph_construction_summary.csv"),
  row.names = FALSE,
  na = ""
)

cpu1 <- graph_rows[graph_rows$profile == "cpu1", c("dataset", "graph_sec")]
cpu4 <- graph_rows[graph_rows$profile == "cpu4", c("dataset", "graph_sec")]
cuda <- graph_rows[graph_rows$profile == "cuda", c("dataset", "graph_sec")]
names(cpu1)[2L] <- "cpu1_sec"
names(cpu4)[2L] <- "cpu4_sec"
names(cuda)[2L] <- "cuda_sec"
speedups <- Reduce(
  function(left, right) merge(left, right, by = "dataset", all = TRUE),
  list(cpu1, cpu4, cuda)
)
speedups$cpu1_over_cpu4 <- speedups$cpu1_sec / speedups$cpu4_sec
speedups$cpu1_over_cuda <- speedups$cpu1_sec / speedups$cuda_sec
write.csv(
  speedups,
  file.path(out_dir, "graph_backend_speedups.csv"),
  row.names = FALSE,
  na = ""
)

native <- summary[summary$engine == "fastEmbedR", , drop = FALSE]
conformance <- native[c(
  "dataset", "method", "profile", "n_benchmark",
  "reference_ari_median", "reference_nmi_median",
  "abs_modularity_delta_median", "cluster_sec_median"
)]
write.csv(
  conformance,
  file.path(out_dir, "native_vs_igraph_conformance.csv"),
  row.names = FALSE,
  na = ""
)

safe_median <- function(x) {
  x <- suppressWarnings(as.numeric(x))
  x <- x[is.finite(x)]
  if (length(x)) median(x) else NA_real_
}
report <- c(
  "# fastEmbedR clustering validation",
  "",
  sprintf("Generated: %s UTC", format(Sys.time(), tz = "UTC")),
  "",
  "The benchmark separates graph construction from clustering. fastEmbedR",
  "Louvain and Leiden use the explicitly requested native CPU or CUDA backend.",
  "Walktrap is CPU-only. Optional RAPIDS cuGraph rows are external oracles and",
  "are not a runtime dependency of fastEmbedR.",
  "",
  sprintf(
    "- Native versus igraph median partition ARI: %.6f",
    safe_median(conformance$reference_ari_median)
  ),
  sprintf(
    "- Native versus igraph median partition NMI: %.6f",
    safe_median(conformance$reference_nmi_median)
  ),
  sprintf(
    "- Native versus igraph median absolute modularity difference: %.3g",
    safe_median(conformance$abs_modularity_delta_median)
  ),
  sprintf(
    "- Median CPU1/CPU4 graph-construction speedup: %.3f",
    safe_median(speedups$cpu1_over_cpu4)
  ),
  sprintf(
    "- Median CPU1/CUDA graph-construction speedup: %.3f",
    safe_median(speedups$cpu1_over_cuda)
  ),
  "",
  "All dataset-, seed-, method-, backend-, and failure-level rows remain in",
  "`clustering_validation_all_runs.csv`."
)
writeLines(report, file.path(out_dir, "README.md"))

if (requireNamespace("ggplot2", quietly = TRUE)) {
  profile_labels <- c(
    cpu1 = "CPU graph, 1 thread",
    cpu4 = "CPU graph, 4 threads",
    cuda = "CUDA graph"
  )
  graph_rows$profile_label <- unname(profile_labels[graph_rows$profile])
  graph_plot <- ggplot2::ggplot(
    graph_rows,
    ggplot2::aes(
      x = reorder(dataset, graph_sec),
      y = graph_sec,
      fill = profile_label
    )
  ) +
    ggplot2::geom_col(position = "dodge", width = 0.75) +
    ggplot2::coord_flip() +
    ggplot2::scale_y_log10() +
    ggplot2::scale_fill_manual(
      values = c(
        "CPU graph, 1 thread" = "#6A3D9A",
        "CPU graph, 4 threads" = "#1F78B4",
        "CUDA graph" = "#E31A1C"
      )
    ) +
    ggplot2::labs(
      x = NULL,
      y = "Graph-construction time (seconds; log scale)",
      fill = NULL
    ) +
    ggplot2::theme_bw(base_size = 10) +
    ggplot2::theme(legend.position = "top")
  ggplot2::ggsave(
    file.path(out_dir, "graph_backend_runtime.png"),
    graph_plot,
    width = 8.5,
    height = 5.8,
    dpi = 360,
    bg = "white"
  )
  ggplot2::ggsave(
    file.path(out_dir, "graph_backend_runtime.pdf"),
    graph_plot,
    width = 8.5,
    height = 5.8
  )

  agreement_plot <- ggplot2::ggplot(
    conformance,
    ggplot2::aes(
      x = method,
      y = reference_ari_median,
      color = profile
    )
  ) +
    ggplot2::geom_hline(yintercept = 1, color = "grey55", linewidth = 0.35) +
    ggplot2::geom_point(
      position = ggplot2::position_jitter(width = 0.12, height = 0),
      size = 2,
      alpha = 0.8
    ) +
    ggplot2::facet_wrap(~dataset) +
    ggplot2::coord_cartesian(ylim = c(0, 1.01)) +
    ggplot2::scale_color_manual(
      values = c(cpu1 = "#6A3D9A", cpu4 = "#1F78B4", cuda = "#E31A1C"),
      labels = profile_labels
    ) +
    ggplot2::labs(
      x = NULL,
      y = "Partition ARI versus igraph",
      color = "Graph profile"
    ) +
    ggplot2::theme_bw(base_size = 9) +
    ggplot2::theme(
      legend.position = "top",
      axis.text.x = ggplot2::element_text(angle = 35, hjust = 1)
    )
  ggplot2::ggsave(
    file.path(out_dir, "native_igraph_partition_agreement.png"),
    agreement_plot,
    width = 10.5,
    height = 7.0,
    dpi = 360,
    bg = "white"
  )
  ggplot2::ggsave(
    file.path(out_dir, "native_igraph_partition_agreement.pdf"),
    agreement_plot,
    width = 10.5,
    height = 7.0
  )
}

message("Wrote clustering aggregate to ", out_dir)
