#!/usr/bin/env Rscript

args <- commandArgs(trailingOnly = TRUE)
if (length(args) < 2L || length(args) > 3L) {
  stop("Usage: build_secondary_comparisons.R RESULTS OUT [THREE_D_ROOT]")
}
results <- normalizePath(args[[1L]], mustWork = TRUE)
out <- args[[2L]]
three_d <- if (length(args) == 3L) {
  normalizePath(args[[3L]], mustWork = TRUE)
} else ""
dir.create(out, recursive = TRUE, showWarnings = FALSE)

read_csv <- function(path) {
  utils::read.csv(path, stringsAsFactors = FALSE, check.names = FALSE)
}
write_csv <- function(data, name) {
  utils::write.csv(data, file.path(out, name), row.names = FALSE,
                   na = "")
}
fmt <- function(x, digits = 2L) {
  ifelse(is.finite(x), formatC(x, format = "f", digits = digits), "--")
}
tex <- function(x) gsub("_", "\\_", x, fixed = TRUE)
write_tex <- function(lines, name) {
  writeLines(lines, file.path(out, name), useBytes = TRUE)
}
median_finite <- function(x) {
  x <- as.numeric(x)
  x <- x[is.finite(x)]
  if (length(x)) stats::median(x) else NA_real_
}
group_median <- function(data, keys, values) {
  stats::aggregate(data[values], data[keys], median_finite)
}

scaling <- read_csv(file.path(results, "aggregate", "scaling_summary.csv"))
stage_names <- c(
  knn_sec = "KNN", pca_sec = "PCA rank 2",
  pca_rank50_sec = "PCA rank up to 50", graph_sec = "SNN graph",
  louvain_graph_fit_sec = "Graph + Louvain",
  leiden_graph_fit_sec = "Graph + Leiden",
  walktrap_graph_fit_sec = "Graph + Walktrap",
  total_tsne_sec = "t-SNE", total_umap_sec = "UMAP"
)
missing <- setdiff(names(stage_names), unique(scaling$stage))
if (length(missing)) {
  stop("CPU scaling results lack: ", paste(missing, collapse = ", "))
}
write_csv(scaling, "cpu_scaling_stages.csv")
scaling <- scaling[scaling$stage %in% names(stage_names), ]
scaling$method <- unname(stage_names[scaling$stage])
scaling <- scaling[c("dataset", "method", "stage", "threads",
                     "n_observations", "repetitions", "median_sec",
                     "speedup", "parallel_efficiency")]
write_csv(scaling, "cpu_scaling_comparison.csv")
scale_rows <- lapply(split(scaling, interaction(
  scaling$dataset, scaling$method, drop = TRUE
)), function(row) {
  row <- row[order(row$threads), ]
  paste(c(tex(row$dataset[[1L]]), tex(row$method[[1L]]),
          format(row$n_observations[[1L]], scientific = FALSE),
          fmt(row$median_sec[row$threads == 1L], 1L),
          fmt(row$speedup[match(c(2L, 4L, 8L, 12L), row$threads)])),
        collapse = " & ")
})
write_tex(c(
  "\\begin{tabular}{lllrrrrr}", "\\toprule",
  paste0("Data set & Stage & $n$ & 1-core s & 2-core & 4-core",
         " & 8-core & 12-core \\\\"),
  "\\midrule", paste0(unlist(scale_rows), " \\\\"),
  "\\bottomrule", "\\end{tabular}"
), "cpu_scaling_table.tex")

landmark_files <- list.files(
  file.path(results, "landmark_reconstruction"),
  pattern = "^landmark_reconstruction[.]csv$", recursive = TRUE,
  full.names = TRUE
)
landmark_files <- landmark_files[vapply(landmark_files, function(path) {
  status <- file.path(dirname(path), "status.csv")
  file.exists(status) && identical(read_csv(status)$status[[1L]], "success")
}, logical(1L))]
if (!length(landmark_files)) stop("No successful landmark results")
landmark <- do.call(rbind, lapply(landmark_files, read_csv))
landmark$runtime_ratio <- landmark$landmark_total_sec /
  landmark$full_embedding_sec
landmark$preserve_delta <- landmark$landmark_preserve_at_30 -
  landmark$full_preserve_at_30
landmark$trust_delta <- landmark$landmark_trustworthiness -
  landmark$full_trustworthiness
keys <- c("dataset", "method", "backend")
memory_path <- file.path(results, "aggregate",
                         "landmark_memory_comparison.csv")
if (file.exists(memory_path)) {
  memory <- read_csv(memory_path)
  full <- memory[memory$variant == "full", ]
  approx <- memory[memory$variant == "landmark", ]
  paired <- merge(full, approx, by = keys,
                  suffixes = c("_full", "_landmark"))
  paired$peak_rss_ratio <- paired$max_rss_kb_landmark /
    paired$max_rss_kb_full
  paired$peak_gpu_ratio <- paired$peak_incremental_mib_landmark /
    paired$peak_incremental_mib_full
  landmark <- merge(landmark, paired[c(keys, "peak_rss_ratio",
    "peak_gpu_ratio")], by = keys, all.x = TRUE)
} else {
  landmark$peak_rss_ratio <- NA_real_
  landmark$peak_gpu_ratio <- NA_real_
}
landmark$memory_scope <- ifelse(
  is.finite(landmark$peak_rss_ratio), "isolated_fit",
  "not_separately_measured"
)
metrics <- c("landmark_fraction", "runtime_ratio", "preserve_delta",
             "trust_delta", "projected_full_procrustes",
             "peak_rss_ratio", "peak_gpu_ratio")
landmark_dataset <- group_median(landmark, keys, metrics)
landmark_dataset$memory_scope <- ifelse(
  is.finite(landmark_dataset$peak_rss_ratio), "isolated_fit",
  "not_separately_measured"
)
write_csv(landmark_dataset, "landmark_dataset_comparison.csv")
landmark_summary <- group_median(
  landmark_dataset, c("method", "backend"), metrics
)
landmark_summary$datasets <- as.integer(table(interaction(
  landmark_dataset$method, landmark_dataset$backend
))[interaction(landmark_summary$method, landmark_summary$backend)])
landmark_summary$memory_scope <- ifelse(
  is.finite(landmark_summary$peak_rss_ratio), "isolated_fit",
  "not_separately_measured"
)
write_csv(landmark_summary, "landmark_summary_comparison.csv")
landmark_rows <- lapply(seq_len(nrow(landmark_summary)), function(i) {
  row <- landmark_summary[i, ]
  paste(c(if (row$method == "tsne") "t-SNE" else "Fuzzy UMAP",
          toupper(row$backend), row$datasets,
          fmt(row$runtime_ratio, 2L), fmt(row$preserve_delta, 3L),
          fmt(row$projected_full_procrustes, 2L),
          fmt(row$peak_rss_ratio, 2L),
          fmt(row$peak_gpu_ratio, 2L)), collapse = " & ")
})
write_tex(c(
  "\\begin{tabular}{llrrrrrr}", "\\toprule",
  paste0("Method & Backend & Data sets & Time ratio",
         " & Preserve@30 $\\Delta$ & Procrustes",
         " & RSS ratio & GPU ratio \\\\"),
  "\\midrule", paste0(unlist(landmark_rows), " \\\\"),
  "\\bottomrule", "\\end{tabular}"
), "landmark_table.tex")

cluster <- read_csv(file.path(results, "aggregate",
                              "clustering_validation_all.csv"))
graph <- read_csv(file.path(results, "aggregate",
                            "clustering_precompute_all.csv"))
native <- cluster[cluster$implementation == "fastEmbedR", ]
reference <- cluster[cluster$implementation == "igraph", ]
pair <- merge(native, reference, by = c("dataset", "method", "seed"),
              suffixes = c("_native", "_igraph"))
pair$membership_ari <- pair$reference_membership_ari_igraph
pair$modularity_difference <- abs(pair$modularity_native -
                                  pair$modularity_igraph)
pair$graph <- ifelse(pair$method == "walktrap", "walktrap", "main")
pair <- merge(pair, graph[c("dataset", "graph", "knn_sec", "graph_sec")],
              by = c("dataset", "graph"), all.x = TRUE)
cluster_metrics <- c("elapsed_sec_native", "elapsed_sec_igraph",
                     "membership_ari", "modularity_difference",
                     "knn_sec", "graph_sec")
cluster_dataset <- group_median(pair, c("dataset", "method"),
                                cluster_metrics)
write_csv(cluster_dataset, "clustering_dataset_comparison.csv")
cluster_summary <- group_median(cluster_dataset, "method", cluster_metrics)
cluster_summary$datasets <- as.integer(table(cluster_dataset$method)[
  cluster_summary$method])
write_csv(cluster_summary, "clustering_summary_comparison.csv")
cluster_rows <- lapply(seq_len(nrow(cluster_summary)), function(i) {
  row <- cluster_summary[i, ]
  paste(c(tools::toTitleCase(row$method), row$datasets,
          fmt(row$elapsed_sec_native, 3L),
          fmt(row$elapsed_sec_igraph, 3L),
          fmt(row$membership_ari, 3L),
          fmt(row$graph_sec, 3L)), collapse = " & ")
})
write_tex(c(
  "\\begin{tabular}{lrrrrr}", "\\toprule",
  "Method & Data sets & Native s & igraph s & ARI & Graph s \\\\",
  "\\midrule", paste0(unlist(cluster_rows), " \\\\"),
  "\\bottomrule", "\\end{tabular}"
), "clustering_table.tex")

peak_memory <- function(root, group, mode, dataset, method) {
  directory <- file.path(root, "measurement", group, mode,
                         dataset, method)
  time_files <- list.files(directory, pattern = "[.]time[.]txt$",
                           full.names = TRUE)
  gpu_files <- list.files(directory, pattern = "[.]gpu_memory[.]csv$",
                          full.names = TRUE)
  rss <- if (length(time_files) == 1L) {
    line <- grep("Maximum resident set size \\(kbytes\\):",
                 readLines(time_files), value = TRUE)
    if (length(line)) as.numeric(sub(".*: *", "", line[[1L]])) / 1024
    else NA_real_
  } else NA_real_
  gpu <- if (length(gpu_files) == 1L) {
    samples <- read_csv(gpu_files)
    if (nrow(samples)) max(samples$incremental_mib) else NA_real_
  } else NA_real_
  c(rss_mib = rss, gpu_incremental_mib = gpu)
}

pair_root <- if (nzchar(three_d)) three_d else results
two_d <- list.files(file.path(pair_root, "workflow_comparators"),
                    pattern = "^result[.]csv$", recursive = TRUE,
                    full.names = TRUE)
if (nzchar(three_d) && !length(two_d)) {
  stop("3D lane lacks its same-image 2D comparator baselines")
}
three_rows <- lapply(two_d, function(path) {
  relative <- substring(path, nchar(file.path(pair_root,
    "workflow_comparators")) + 2L)
  parts <- strsplit(relative, "/", fixed = TRUE)[[1L]]
  if (length(parts) != 4L) return(NULL)
  if (!parts[[1L]] %in% c("r_cpu", "r_cuda", "python_cpu",
                          "python_cuda")) return(NULL)
  fit_2d <- read_csv(path)
  if (!fit_2d$family[[1L]] %in% c("tsne", "umap")) return(NULL)
  path_3d <- if (nzchar(three_d)) {
    file.path(three_d, "workflow_comparators_3d", parts[[1L]],
              parts[[2L]], parts[[3L]], "result.csv")
  } else ""
  status_3d <- if (nzchar(three_d)) {
    file.path(three_d, "workflow_comparators_3d", parts[[1L]],
              parts[[2L]], parts[[3L]], "status.csv")
  } else ""
  fit_3d <- if (file.exists(path_3d)) read_csv(path_3d) else NULL
  memory_2d <- peak_memory(pair_root, "workflow_comparators",
                           parts[[1L]], parts[[2L]], parts[[3L]])
  memory_3d <- if (nzchar(three_d)) {
    peak_memory(three_d, "workflow_comparators_3d",
                parts[[1L]], parts[[2L]], parts[[3L]])
  } else c(rss_mib = NA_real_, gpu_incremental_mib = NA_real_)
  state <- if (file.exists(status_3d)) {
    read_csv(status_3d)$status[[1L]]
  } else "not_run"
  if (state == "success" && is.null(fit_3d)) state <- "missing_result"
  data.frame(
    dataset = fit_2d$dataset[[1L]], mode = parts[[1L]],
    method = fit_2d$method[[1L]], status_3d = state,
    seed_2d = fit_2d$seed[[1L]],
    seed_3d = if (is.null(fit_3d)) NA_integer_ else fit_3d$seed[[1L]],
    dimensions_2d = fit_2d$n_components[[1L]],
    dimensions_3d = if (is.null(fit_3d)) NA_integer_ else
      fit_3d$n_components[[1L]],
    timing_scope_2d = fit_2d$timing_scope[[1L]],
    timing_scope_3d = if (is.null(fit_3d)) NA_character_ else
      fit_3d$timing_scope[[1L]],
    timing_eligible_2d = tolower(as.character(
      fit_2d$timing_eligible[[1L]])) == "true",
    timing_eligible_3d = if (is.null(fit_3d)) NA else
      tolower(as.character(fit_3d$timing_eligible[[1L]])) == "true",
    n_2d = fit_2d$n[[1L]],
    n_3d = if (is.null(fit_3d)) NA_integer_ else fit_3d$n[[1L]],
    sec_2d = fit_2d$elapsed_median_sec[[1L]],
    sec_3d = if (is.null(fit_3d)) NA_real_ else
      fit_3d$elapsed_median_sec[[1L]],
    trust_2d = fit_2d$trustworthiness[[1L]],
    trust_3d = if (is.null(fit_3d)) NA_real_ else
      fit_3d$trustworthiness[[1L]],
    preserve_2d = fit_2d$preserve_at_30[[1L]],
    preserve_3d = if (is.null(fit_3d)) NA_real_ else
      fit_3d$preserve_at_30[[1L]],
    sampled_kl_2d = fit_2d$sampled_kl[[1L]],
    sampled_kl_3d = if (is.null(fit_3d)) NA_real_ else
      fit_3d$sampled_kl[[1L]],
    host_rss_mib_2d = memory_2d[["rss_mib"]],
    host_rss_mib_3d = memory_3d[["rss_mib"]],
    gpu_incremental_mib_2d = memory_2d[["gpu_incremental_mib"]],
    gpu_incremental_mib_3d = memory_3d[["gpu_incremental_mib"]]
  )
})
three_rows <- Filter(Negate(is.null), three_rows)
if (length(three_rows)) {
  comparison_3d <- do.call(rbind, three_rows)
  comparison_3d$runtime_ratio_3d_to_2d <- comparison_3d$sec_3d /
    comparison_3d$sec_2d
  comparison_3d$trust_delta <- comparison_3d$trust_3d -
    comparison_3d$trust_2d
  comparison_3d$preserve_delta <- comparison_3d$preserve_3d -
    comparison_3d$preserve_2d
  comparison_3d$sampled_kl_delta <- comparison_3d$sampled_kl_3d -
    comparison_3d$sampled_kl_2d
  comparison_3d$host_rss_ratio_3d_to_2d <-
    comparison_3d$host_rss_mib_3d / comparison_3d$host_rss_mib_2d
  comparison_3d$gpu_memory_ratio_3d_to_2d <-
    comparison_3d$gpu_incremental_mib_3d /
    comparison_3d$gpu_incremental_mib_2d
  comparison_3d$status_3d[
    comparison_3d$status_3d == "success" &
      comparison_3d$n_2d != comparison_3d$n_3d
  ] <- "row_count_mismatch"
  comparison_3d$status_3d[
    comparison_3d$status_3d == "success" &
      (comparison_3d$seed_2d != comparison_3d$seed_3d |
       comparison_3d$dimensions_2d != 2L |
       comparison_3d$dimensions_3d != 3L)
  ] <- "pairing_mismatch"
  comparison_3d$status_3d[
    comparison_3d$status_3d == "success" &
      comparison_3d$timing_scope_2d != comparison_3d$timing_scope_3d
  ] <- "boundary_mismatch"
  comparison_3d$status_3d[
    comparison_3d$status_3d == "success" &
      (!comparison_3d$timing_eligible_2d |
       !comparison_3d$timing_eligible_3d)
  ] <- "timing_ineligible"
  invalid <- comparison_3d$status_3d != "success"
  comparison_3d[invalid, c(
    "runtime_ratio_3d_to_2d", "trust_delta", "preserve_delta",
    "sampled_kl_delta",
    "host_rss_ratio_3d_to_2d", "gpu_memory_ratio_3d_to_2d"
  )] <- NA_real_
  write_csv(comparison_3d, "three_d_comparison.csv")
  passed <- comparison_3d[comparison_3d$status_3d == "success", ]
  if (nrow(passed)) {
    summary_3d <- group_median(passed, c("mode", "method"), c(
      "runtime_ratio_3d_to_2d", "trust_delta", "preserve_delta",
      "sampled_kl_delta",
      "host_rss_ratio_3d_to_2d", "gpu_memory_ratio_3d_to_2d"
    ))
    summary_3d$datasets <- as.integer(table(interaction(
      passed$mode, passed$method
    ))[interaction(summary_3d$mode, summary_3d$method)])
    write_csv(summary_3d, "three_d_summary_comparison.csv")
    table_rows <- lapply(seq_len(nrow(summary_3d)), function(i) {
      row <- summary_3d[i, ]
      paste(c(tex(row$method), tex(row$mode), row$datasets,
              fmt(row$runtime_ratio_3d_to_2d, 2L),
              fmt(row$host_rss_ratio_3d_to_2d, 2L),
              fmt(row$trust_delta, 3L),
              fmt(row$preserve_delta, 3L),
              fmt(row$sampled_kl_delta, 3L)), collapse = " & ")
    })
    write_tex(c(
      "\\begin{tabular}{llrrrrrr}", "\\toprule",
      paste0("Method & Mode & Data sets & Time ratio & RSS ratio",
             " & Trust $\\Delta$ & Preserve@30 $\\Delta$",
             " & KL $\\Delta$ \\\\"),
      "\\midrule", paste0(unlist(table_rows), " \\\\"),
      "\\bottomrule", "\\end{tabular}"
    ), "three_d_summary_table.tex")
    grDevices::pdf(file.path(out, "three_d_comparison.pdf"),
                   width = 7.5, height = 4.5)
    graphics::plot(passed$runtime_ratio_3d_to_2d,
                   passed$preserve_delta,
                   col = as.integer(factor(passed$method)), pch = 16L,
                   xlab = "3D/2D elapsed time",
                   ylab = "Preserve@30 difference (3D - 2D)")
    graphics::abline(v = 1, h = 0, lty = 3, col = "gray50")
    graphics::legend("bottomright", legend = levels(factor(passed$method)),
                     col = seq_along(unique(passed$method)), pch = 16L,
                     bty = "n", cex = 0.8)
    grDevices::dev.off()
  }
}

grDevices::pdf(file.path(out, "cpu_scaling_comparison.pdf"),
               width = 11, height = 9)
op <- graphics::par(mfrow = c(3L, 3L), mar = c(4, 4, 2, 1))
datasets <- unique(scaling$dataset)
colors <- grDevices::hcl.colors(length(datasets), "Dark 3")
for (method in unname(stage_names)) {
  current <- scaling[scaling$method == method, ]
  graphics::plot(NA, xlim = c(1, 12),
                 ylim = c(0, max(current$speedup, na.rm = TRUE) * 1.1),
                 xlab = "CPU threads", ylab = "Speedup vs one thread",
                 main = method)
  graphics::abline(a = 0, b = 1, lty = 3, col = "gray50")
  for (i in seq_along(datasets)) {
    ds <- datasets[[i]]
    row <- current[current$dataset == ds, ]
    row <- row[order(row$threads), ]
    graphics::lines(row$threads, row$speedup, type = "b", pch = i,
                    col = colors[[i]], lwd = 1.5)
  }
  if (identical(method, unname(stage_names[[1L]]))) {
    graphics::legend("topleft", legend = datasets,
                     pch = seq_along(datasets), col = colors,
                     cex = 0.55, bty = "n")
  }
}
graphics::par(op)
grDevices::dev.off()

grDevices::pdf(file.path(out, "landmark_comparison.pdf"),
               width = 7.5, height = 4.5)
colors <- c(cpu = "#267DA8", cuda = "#D75A3A")
symbols <- c(tsne = 16L, umap = 17L)
graphics::plot(landmark_dataset$runtime_ratio,
               landmark_dataset$preserve_delta,
               col = colors[landmark_dataset$backend],
               pch = symbols[landmark_dataset$method],
               xlab = "Landmark/full elapsed time",
               ylab = "Preserve@30 difference (landmark - full)")
graphics::abline(v = 1, h = 0, lty = 3, col = "gray50")
backends <- intersect(names(colors), unique(landmark_dataset$backend))
graphics::legend("bottomleft", legend = c(toupper(backends),
                 "t-SNE", "UMAP"),
                 col = c(colors[backends], "black", "black"),
                 pch = c(rep(16L, length(backends)), symbols), bty = "n")
grDevices::dev.off()

message("Wrote secondary comparisons to ", normalizePath(out))
