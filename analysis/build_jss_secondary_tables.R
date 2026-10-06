#!/usr/bin/env Rscript

args <- commandArgs(trailingOnly = TRUE)
if (length(args) != 2L) {
  stop("Usage: build_jss_secondary_tables.R CAMPAIGN OUTPUT_DIR")
}
campaign <- normalizePath(args[[1L]], mustWork = TRUE)
output <- args[[2L]]
dir.create(output, recursive = TRUE, showWarnings = FALSE)
read_result <- function(name) {
  read.csv(file.path(campaign, "results", "aggregate", name))
}
write_result <- function(name, lines) {
  writeLines(lines, file.path(output, name))
}
fmt <- function(x, digits = 3L) {
  if (!length(x) || !is.finite(x)) return("--")
  formatC(x, format = "f", digits = digits)
}
pair <- function(x, y) paste(fmt(x), fmt(y), sep = " / ")
median_or_na <- function(x) {
  values <- x[is.finite(x)]
  if (length(values)) median(values) else NA_real_
}
datasets <- c(
  "COIL20", "USPS", "FashionMNIST",
  "FlowRepository_FR-FCM-ZYRM_files", "flow18", "MNIST",
  "imagenet", "MetRef", "mass41", "TabulaMuris",
  "Macosko2015_retina"
)
labels <- c(
  "COIL-20", "USPS", "Fashion", "FlowRepo.", "flow18", "MNIST",
  "ImageNet", "MetRef", "mass41", "Tabula", "Retina"
)
tsne <- read_result("cuda_tsne_workflow_speed_ratio.csv")
umap <- read_result("cuda_umap_workflow_speed_ratio.csv")
workflow <- read_result("workflow_comparators_all.csv")
outcomes <- read_result("workflow_comparator_outcomes.csv")
quality_metric <- function(dataset, method, mode, field) {
  if (quality_status(dataset, method, mode) != "success") {
    return(NA_real_)
  }
  row <- workflow[
    workflow$dataset == dataset & workflow$method == method &
      workflow$comparator_mode == mode, , drop = FALSE
  ]
  if (nrow(row) > 1L) stop("Duplicate comparator result")
  if (!nrow(row) || !field %in% names(row)) return(NA_real_)
  as.numeric(row[[field]][[1L]])
}
quality_status <- function(dataset, method, mode) {
  row <- outcomes[
    outcomes$dataset == dataset & outcomes$method == method &
      outcomes$comparator_mode == mode, , drop = FALSE
  ]
  if (nrow(row)) {
    return(gsub("_", " ", row$status[[nrow(row)]], fixed = TRUE))
  }
  path <- file.path(campaign, "results", "workflow_comparators",
                    mode, dataset, method, "status.csv")
  if (!file.exists(path)) return("not run")
  status <- read.csv(path, stringsAsFactors = FALSE)
  if (!nrow(status)) return("missing status")
  gsub("_", " ", status$status[[nrow(status)]], fixed = TRUE)
}
quality_fitted_n <- function(dataset) {
  path <- file.path(campaign, "input", dataset,
                    "workflow_comparators", "manifest.csv")
  if (!file.exists(path)) return("--")
  manifest <- read.csv(path, stringsAsFactors = FALSE)
  if (nrow(manifest) != 1L || !is.finite(manifest$n[[1L]])) {
    return("--")
  }
  format(manifest$n[[1L]], big.mark = ",", scientific = FALSE)
}
quality_rows <- function(family) {
  data <- if (family == "tsne") tsne else umap
  vapply(seq_along(datasets), function(i) {
    row <- data[data$dataset == datasets[[i]], , drop = FALSE]
    if (nrow(row) > 1L) stop("Duplicate paired quality result")
    dataset <- datasets[[i]]
    native <- paste0("fastembedr_", family)
    comparator <- paste0("cuml_", family)
    if (!nrow(row)) {
      values <- c(
        labels[[i]], quality_fitted_n(dataset),
        pair(quality_metric(dataset, native, "r_cuda",
                            "trustworthiness"),
             quality_metric(dataset, comparator, "python_cuda",
                            "trustworthiness")),
        pair(quality_metric(dataset, native, "r_cuda",
                            "preserve_at_30"),
             quality_metric(dataset, comparator, "python_cuda",
                            "preserve_at_30"))
      )
      if (family == "tsne") {
        values <- c(values, pair(
          quality_metric(dataset, native, "r_cuda", "sampled_kl"),
          quality_metric(dataset, comparator, "python_cuda",
                         "sampled_kl")
        ))
      }
      status <- paste(
        quality_status(dataset, native, "r_cuda"),
        quality_status(dataset, comparator, "python_cuda"),
        sep = " / "
      )
      return(paste0(paste(c(values, status), collapse = " & "),
                    " \\\\"))
    }
    values <- c(
      labels[[i]], format(row$n, big.mark = ","),
      pair(row$fastembedr_trustworthiness,
           row$cuml_trustworthiness),
      pair(row$fastembedr_preserve_at_30,
           row$cuml_preserve_at_30)
    )
    if (family == "tsne") {
      kl <- function(method, mode) {
        hit <- workflow[
          workflow$dataset == datasets[[i]] &
            workflow$method == method &
            workflow$comparator_mode == mode, , drop = FALSE
        ]
        if (nrow(hit) != 1L) stop("Incomplete KL results")
        hit$sampled_kl[[1L]]
      }
      values <- c(values, pair(
        kl("fastembedr_tsne", "r_cuda"),
        kl("cuml_tsne", "python_cuda")
      ))
    }
    paste0(paste(c(values, "success / success"),
                 collapse = " & "), " \\\\")
  }, character(1L))
}
write_result("diagnostic_cuda_quality_table.tex", c(
  "\\begin{table}[p]", "\\centering",
  paste0(
    "\\caption{CUDA embedding quality in diagnostic campaign ",
    basename(campaign), ". Entries are fastEmbedR / cuML on fixed ",
    "sampled rows; $n$ is the fitted matrix size. Status is ",
    "fastEmbedR / cuML; -- marks unavailable metrics. Different ",
    "affinity supports make sampled t-SNE KL descriptive, ",
    "not a matched-objective test.}"
  ),
  "\\label{tab:diagnostic-cuda-quality}", "\\scriptsize",
  "\\textbf{A. Compact-support t-SNE / cuML t-SNE}\\par\\smallskip",
  "\\resizebox{\\textwidth}{!}{%",
  "\\begin{tabular}{lrrrrl}", "\\toprule",
  "Data set & Fitted $n$ & Trustworthiness & Preserve@30 & Sampled KL & Status \\\\",
  "\\midrule", quality_rows("tsne"), "\\bottomrule",
  "\\end{tabular}%", "}", "\\medskip",
  "\\textbf{B. Fuzzy UMAP / cuML UMAP}\\par\\smallskip",
  "\\resizebox{\\textwidth}{!}{%",
  "\\begin{tabular}{lrrrl}", "\\toprule",
  "Data set & Fitted $n$ & Trustworthiness & Preserve@30 & Status \\\\",
  "\\midrule", quality_rows("umap"), "\\bottomrule",
  "\\end{tabular}%", "}", "\\end{table}"
))
support_quality <- read_result("support_quality_raw.csv")
support_timing <- read_result("support_timing_summary.csv")
if (!"perplexity" %in% names(support_quality)) {
  support_quality$perplexity <- 30L
}
if (!"perplexity" %in% names(support_timing)) {
  support_timing$perplexity <- 30L
}
support_keys <- c("dataset", "backend", "perplexity",
                  "support_multiplier")
support_fields <- c("trustworthiness", "preserve_at_30", "sampled_kl")
support_quality <- aggregate(
  support_quality[support_fields], support_quality[support_keys],
  median_or_na
)
support <- merge(
  support_quality,
  support_timing[c(support_keys, "median_sec", "timing_n")],
  by = support_keys, all = TRUE
)
support$paired <- is.finite(support$median_sec) &
  is.finite(support$trustworthiness) &
  is.finite(support$preserve_at_30) &
  is.finite(support$sampled_kl)
group <- interaction(
  support$dataset, support$backend, support$perplexity,
  drop = TRUE
)
complete_widths <- vapply(split(support, group), function(rows) {
  all(c(1, 3) %in% rows$support_multiplier[rows$paired])
}, logical(1L))
support$paired_widths <- support$paired &
  group %in% names(complete_widths)[complete_widths] &
  support$support_multiplier %in% c(1, 3)
write.csv(support, file.path(output, "support_width_dataset.csv"),
          row.names = FALSE, na = "")
paired_support <- support[support$paired_widths, ]
support_summary <- aggregate(
  paired_support[c("median_sec", support_fields)],
  paired_support[c("backend", "perplexity", "support_multiplier")],
  median_or_na
)
support_counts <- aggregate(
  paired_support$dataset,
  paired_support[c("backend", "perplexity", "support_multiplier")],
  length
)
names(support_counts)[[4L]] <- "paired_datasets"
support_summary <- merge(support_summary, support_counts)
support_summary <- support_summary[order(
  support_summary$perplexity, support_summary$backend,
  support_summary$support_multiplier
), ]
write.csv(support_summary,
  file.path(output, "support_width_summary.csv"),
  row.names = FALSE, na = "")
support_rows <- vapply(seq_len(nrow(support_summary)), function(i) {
  row <- support_summary[i, ]
  paste0(paste(c(toupper(row$backend), row$perplexity,
    row$support_multiplier, row$paired_datasets,
    fmt(row$median_sec, 2L), fmt(row$trustworthiness),
    fmt(row$preserve_at_30), fmt(row$sampled_kl)),
    collapse = " & "), " \\\\")
}, character(1L))
write_result("diagnostic_support_width_table.tex", c(
  "\\begin{table}[htbp]", "\\centering", "\\scriptsize",
  paste0("\\caption{Support-width sensitivity in campaign ",
    basename(campaign), ". Each median uses the same data sets ",
    "with valid timing and quality at both support widths. ",
    "Times cover precomputed-neighbor t-SNE calls with 250 ",
    "exaggerated and 500 normal iterations, not matrix workflows. ",
    "KL values describe different ",
    "affinity objectives and are not matched-objective ratios.}"),
  "\\label{tab:support-width}",
  "\\begin{tabular}{llrrrrrr}", "\\toprule",
  "Backend & $P$ & $k/P$ & Data sets & Seconds & Trust & Preserve@30 & KL \\\\",
  "\\midrule", support_rows, "\\bottomrule",
  "\\end{tabular}", "\\end{table}"
))
pca <- read_result("pca_accuracy_vs_dense.csv")
pca <- pca[pca$method == "fastEmbedR", , drop = FALSE]
pca_rows <- unlist(lapply(c("cpu", "cuda"), function(backend) {
  vapply(c(2L, 50L), function(rank) {
    hit <- pca[pca$backend == backend &
                 pca$requested_rank == rank, , drop = FALSE]
    paste0(paste(
      toupper(backend), rank, nrow(hit),
      fmt(median_or_na(hit$score_procrustes), 6L),
      fmt(median_or_na(hit$loading_subspace_cosine_mean), 6L),
      sep = " & "
    ), " \\\\")
  }, character(1L))
}))
write_result("diagnostic_pca_accuracy_table.tex", c(
  "\\begin{table}[htbp]", "\\centering",
  paste0(
    "\\caption{PCA agreement with dense centered SVD on fixed ",
    "subsets in campaign ", basename(campaign),
    ". The effective rank may be below the requested rank.}"
  ),
  "\\label{tab:diagnostic-pca-accuracy}", "\\scriptsize",
  "\\begin{tabular}{lrrrr}", "\\toprule",
  "Backend & Requested rank & Data sets & Score correlation & Loading cosine \\\\",
  "\\midrule", pca_rows, "\\bottomrule",
  "\\end{tabular}", "\\end{table}"
))
clusters <- read_result("clustering_validation_all.csv")
cluster_specs <- rbind(
  expand.grid(
    method = c("louvain", "leiden"),
    implementation = c("fastEmbedR", "igraph"),
    backend = "cpu", stringsAsFactors = FALSE
  ),
  data.frame(method = c("louvain", "leiden"),
             implementation = "fastEmbedR", backend = "cuda"),
  data.frame(method = c("louvain", "leiden"),
             implementation = "fastEmbedR", backend = "metal"),
  data.frame(method = "walktrap",
             implementation = c("fastEmbedR", "igraph"),
             backend = "cpu")
)
cluster_rows <- vapply(seq_len(nrow(cluster_specs)), function(i) {
  spec <- cluster_specs[i, ]
  hit <- clusters[
    clusters$method == spec$method &
      clusters$backend == spec$backend &
      clusters$implementation == spec$implementation, , drop = FALSE
  ]
  paired <- hit$reference_membership_ari
  if (nrow(hit) && all(is.na(paired)) && spec$backend == "cpu") {
    other <- clusters[
      clusters$method == spec$method & clusters$backend == "cpu" &
        clusters$implementation != spec$implementation, , drop = FALSE
    ]
    key <- paste(hit$dataset, hit$method, hit$seed)
    other_key <- paste(other$dataset, other$method, other$seed)
    paired <- other$reference_membership_ari[match(key, other_key)]
  }
  sizes <- if (nrow(hit)) {
    paste(range(hit$n_vertices), collapse = "--")
  } else {
    "--"
  }
  paste0(paste(
    spec$method, toupper(spec$backend), spec$implementation,
    nrow(hit), sizes, fmt(median_or_na(hit$elapsed_sec)),
    fmt(median_or_na(hit$label_ari)),
    fmt(median_or_na(paired)),
    sep = " & "
  ), " \\\\")
}, character(1L))
write_result("diagnostic_clustering_table.tex", c(
  "\\begin{table}[htbp]", "\\centering",
  paste0(
    "\\caption{Clustering in campaign ", basename(campaign),
    ". The Runs column counts completed data-set--seed fits; ",
    "times exclude graph construction. Label ARI uses external ",
    "data-set labels; paired ARI compares native CPU with igraph ",
    "or an accelerator with native CPU. Graph sizes identify any fixed ",
    "Walktrap subset. Missing runs are not zero.}"
  ),
  "\\label{tab:diagnostic-clustering}", "\\scriptsize",
  "\\begin{tabular}{lllrrrrr}", "\\toprule",
  paste0("Method & Backend & Implementation & Runs & $n$ range & ",
         "Median seconds & Label ARI & Paired ARI ", "\\\\"),
  "\\midrule", cluster_rows, "\\bottomrule",
  "\\end{tabular}", "\\end{table}"
))

quality <- read_result("backend_quality_summary.csv")
quality <- quality[quality$boundary == "full_workflow", ]
display_names <- c(
  COIL20 = "COIL-20", FashionMNIST = "Fashion-MNIST",
  flow18 = "flow18", imagenet = "ImageNet",
  Macosko2015_retina = "Retina", mass41 = "mass41",
  MetRef = "MetRef", MNIST = "MNIST",
  TabulaMuris = "Tabula Muris", USPS = "USPS",
  `FlowRepository_FR-FCM-ZYRM_files` = "FlowRepository"
)
quality_pair <- function(dataset, method, field) {
  vapply(c("cpu", "cuda"), function(backend) {
    hit <- quality[quality$dataset == dataset &
      quality$method == method & quality$backend == backend, ]
    if (nrow(hit) != 1L) return("--")
    fmt(hit[[field]][[1L]])
  }, character(1L))
}
quality_rows <- function(method) {
  vapply(names(display_names), function(dataset) {
    trust <- quality_pair(dataset, method, "trustworthiness_median")
    preserve <- quality_pair(dataset, method, "preserve_at_30_median")
    kl <- if (method == "tsne") {
      quality_pair(dataset, method, "final_kl_median")
    } else c("--", "--")
    paste0(paste(c(display_names[[dataset]],
      paste(trust, collapse = " / "),
      paste(preserve, collapse = " / "),
      paste(kl, collapse = " / ")), collapse = " & "), " \\\\")
  }, character(1L))
}
write_result("diagnostic_native_quality_table.tex", c(
  "\\begin{table}[p]", "\\centering", "\\scriptsize",
  paste0("\\caption{File-to-layout quality from campaign ",
    basename(campaign), ". Each entry is CPU / CUDA, over ",
    "successful full-workflow seeds. A missing CPU FlowRepository ",
    "result is shown as --. KL is the production t-SNE objective; ",
    "UMAP has no KL entry. The campaign audit failed.}"),
  "\\label{tab:native-quality}",
  "\\begin{tabular}{lccc}", "\\toprule",
  "Data set & Trustworthiness & Preserve@30 & Final KL \\\\",
  "\\midrule", "\\multicolumn{4}{l}{Compact-support t-SNE} \\\\",
  quality_rows("tsne"), "\\midrule",
  "\\multicolumn{4}{l}{Fuzzy UMAP} \\\\",
  quality_rows("umap"), "\\bottomrule", "\\end{tabular}",
  "\\end{table}"
))

transform <- read_result("transform_all.csv")
transform_fields <- c("transform_sec", "query_reference_preserve_at_30",
  "joint_query_reference_preserve_at_30", "query_label_knn_accuracy",
  "reference_max_displacement")
transform <- aggregate(transform[transform_fields],
  transform[c("dataset", "method", "backend")], median_or_na)
transform_summary <- aggregate(transform[transform_fields],
  transform[c("method", "backend")], median_or_na)
transform_rows <- vapply(seq_len(nrow(transform_summary)), function(i) {
  row <- transform_summary[i, ]
  count <- sum(transform$method == row$method &
    transform$backend == row$backend)
  paste0(paste(c(if (row$method == "tsne") "t-SNE" else "UMAP",
    toupper(row$backend), count, fmt(row$transform_sec),
    fmt(row$query_reference_preserve_at_30),
    fmt(row$joint_query_reference_preserve_at_30),
    fmt(row$query_label_knn_accuracy),
    fmt(row$reference_max_displacement, 0L)),
    collapse = " & "), " \\\\")
}, character(1L))
write_result("diagnostic_transform_table.tex", c(
  "\\begin{table}[htbp]", "\\centering", "\\scriptsize",
  paste0("\\caption{Held-out transformation in campaign ",
    basename(campaign), ". Each value is the median of data-set ",
    "medians over successful seeds. Query/reference Preserve@30 ",
    "is compared with joint embedding of the same queries; ",
    "the reference is held fixed during transformation.}"),
  "\\label{tab:transform-results}",
  "\\begin{tabular}{llrrrrrr}", "\\toprule",
  paste0("Method & Backend & Data sets & Transform s & Preserve@30",
    " & Joint & Label KNN & Ref. shift \\\\"),
  "\\midrule", transform_rows, "\\bottomrule",
  "\\end{tabular}", "\\end{table}"
))

binary <- read_result("umap_binary_vs_fuzzy.csv")
binary$preserve_delta <- binary$binary_preserve_at_30 -
  binary$fuzzy_preserve_at_30
binary_counts <- table(binary$comparator_mode)
binary <- aggregate(binary[c("binary_over_fuzzy_time", "preserve_delta")],
  binary["comparator_mode"], median_or_na)
binary_rows <- vapply(seq_len(nrow(binary)), function(i) {
  row <- binary[i, ]
  paste0(paste(c(gsub("_", "\\_", row$comparator_mode, fixed = TRUE),
    binary_counts[[row$comparator_mode]],
    fmt(row$binary_over_fuzzy_time), fmt(row$preserve_delta)),
    collapse = " & "), " \\\\")
}, character(1L))
write_result("diagnostic_binary_umap_table.tex", c(
  "\\begin{table}[htbp]", "\\centering", "\\scriptsize",
  paste0("\\caption{Binary-adjacency versus fuzzy UMAP in campaign ",
    basename(campaign), ". Ratios and quality changes are diagnostic ",
    "medians over completed data sets; binary UMAP changes the graph ",
    "objective and is not a drop-in speed substitute.}"),
  "\\label{tab:binary-umap}",
  "\\begin{tabular}{lrrr}", "\\toprule",
  "Workflow & Data sets & Binary/fuzzy time & Preserve@30 change \\\\",
  "\\midrule", binary_rows, "\\bottomrule",
  "\\end{tabular}", "\\end{table}"
))
