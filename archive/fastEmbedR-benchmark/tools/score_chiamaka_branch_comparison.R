args <- commandArgs(trailingOnly = TRUE)
if (length(args) != 4L) {
  stop(
    "Usage: Rscript score_chiamaka_branch_comparison.R ",
    "<mnist.RData> <historical-details.rds> <latest-details.rds> <output.csv>",
    call. = FALSE
  )
}

suppressPackageStartupMessages({
  library(fastEmbedR)
  library(float)
})

load(args[[1L]])
if (!exists("dataset") || is.null(dataset$data) || is.null(dataset$labels)) {
  stop("MNIST file must contain dataset$data and dataset$labels.", call. = FALSE)
}

historical <- readRDS(args[[2L]])
latest <- readRDS(args[[3L]])

layouts <- list(
  historical_faissr_opentsne = historical$layouts$fastembedr_opentsne,
  latest_native_hnsw_opentsne = latest$layouts$fastembedr_opentsne,
  historical_faissr_umap_fuzzy = historical$layouts$fastembedr_umap,
  latest_native_hnsw_umap_fuzzy = latest$layouts$fastembedr_umap
)

scores <- lapply(names(layouts), function(name) {
  message("Scoring ", name)
  evaluate_embedding(
    x_high = dataset$data,
    embedding = layouts[[name]],
    labels = dataset$labels,
    k = c(15L, 30L),
    primary_k = 15L,
    sample_size_for_local_metrics = 1000L,
    sample_size_for_global_metrics = 1000L,
    seed = 4L,
    method = name,
    backend = "cpu",
    n_threads = 4L,
    dataset = "MNIST70k"
  )
})

out <- do.call(rbind, scores)
keep <- c(
  "method",
  "trustworthiness",
  "continuity",
  "knn_preservation_15",
  "knn_preservation_30",
  "label_knn_accuracy",
  "silhouette",
  "distance_spearman",
  "stress"
)
utils::write.csv(out[, keep, drop = FALSE], args[[4L]], row.names = FALSE)
print(out[, keep, drop = FALSE])
