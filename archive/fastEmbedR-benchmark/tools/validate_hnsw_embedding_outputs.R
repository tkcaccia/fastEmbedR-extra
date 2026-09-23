args <- commandArgs(trailingOnly = TRUE)
if (length(args) != 5L) {
  stop(
    "Usage: Rscript validate_hnsw_embedding_outputs.R ",
    "<MNIST.RData> <baseline-details.rds> <candidate-details.rds> ",
    "<output.csv> <output.png>",
    call. = FALSE
  )
}

suppressPackageStartupMessages({
  library(fastEmbedR)
  library(float)
})

load(args[[1L]])
baseline <- readRDS(args[[2L]])
candidate <- readRDS(args[[3L]])

as_double_layout <- function(x) {
  if (inherits(x, "float32")) float::dbl(x) else as.matrix(x)
}

procrustes_rmsd <- function(reference, observed) {
  reference <- scale(as_double_layout(reference), center = TRUE, scale = FALSE)
  observed <- scale(as_double_layout(observed), center = TRUE, scale = FALSE)
  decomposition <- svd(crossprod(observed, reference))
  rotation <- decomposition$u %*% t(decomposition$v)
  aligned <- observed %*% rotation
  scale_factor <- sum(reference * aligned) / sum(aligned * aligned)
  aligned <- aligned * scale_factor
  rmsd <- sqrt(mean(rowSums((reference - aligned)^2)))
  reference_radius <- sqrt(mean(rowSums(reference^2)))
  c(rmsd = rmsd, normalized_rmsd = rmsd / reference_radius)
}

layout_pairs <- list(
  opentsne = list(
    baseline = baseline$layouts$fastembedr_opentsne,
    candidate = candidate$layouts$fastembedr_opentsne
  ),
  umap_fuzzy = list(
    baseline = baseline$layouts$fastembedr_umap,
    candidate = candidate$layouts$fastembedr_umap
  )
)

records <- lapply(names(layout_pairs), function(method) {
  pair <- layout_pairs[[method]]
  metrics <- lapply(c("baseline", "candidate"), function(revision) {
    evaluate_embedding(
      x_high = dataset$data,
      embedding = pair[[revision]],
      labels = dataset$labels,
      k = c(15L, 30L),
      primary_k = 15L,
      sample_size_for_local_metrics = 1000L,
      sample_size_for_global_metrics = 1000L,
      seed = 4L,
      method = paste(method, revision, sep = "_"),
      backend = "cpu",
      n_threads = 4L,
      dataset = "MNIST70k"
    )
  })
  aligned <- procrustes_rmsd(pair$baseline, pair$candidate)
  out <- do.call(rbind, metrics)
  out$revision <- c("baseline", "candidate")
  out$procrustes_rmsd <- unname(aligned[["rmsd"]])
  out$procrustes_normalized_rmsd <- unname(aligned[["normalized_rmsd"]])
  out
})

scores <- do.call(rbind, records)
keep <- c(
  "method",
  "revision",
  "trustworthiness",
  "continuity",
  "knn_preservation_15",
  "knn_preservation_30",
  "label_knn_accuracy",
  "silhouette",
  "procrustes_rmsd",
  "procrustes_normalized_rmsd"
)
utils::write.csv(scores[, keep, drop = FALSE], args[[4L]], row.names = FALSE)
print(scores[, keep, drop = FALSE])

labels <- as.factor(dataset$labels)
palette <- grDevices::hcl.colors(length(levels(labels)), "Dynamic")
colors <- palette[as.integer(labels)]
panels <- list(
  "Baseline openTSNE" = layout_pairs$opentsne$baseline,
  "Optimized-HNSW openTSNE" = layout_pairs$opentsne$candidate,
  "Baseline fuzzy UMAP" = layout_pairs$umap_fuzzy$baseline,
  "Optimized-HNSW fuzzy UMAP" = layout_pairs$umap_fuzzy$candidate
)

grDevices::png(args[[5L]], width = 2200, height = 2000, res = 220)
old_par <- graphics::par(
  mfrow = c(2, 2),
  mar = c(0.2, 0.2, 1.8, 0.2)
)
for (title in names(panels)) {
  graphics::plot(
    as_double_layout(panels[[title]]),
    pch = 20,
    cex = 0.24,
    col = colors,
    axes = FALSE,
    ann = FALSE
  )
  graphics::title(main = title, line = 0.35, cex.main = 0.9)
}
graphics::par(old_par)
grDevices::dev.off()
