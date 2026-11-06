source("analysis/runtime_figure_style.R")

data <- data.frame(
  title = c("fastEmbedR PCA [CPU]", "fastEmbedR PCA [CUDA]",
    "fastEmbedR binary UMAP [CPU]", "fastEmbedR fuzzy UMAP [CUDA]"),
  elapsed_median_sec = c(1, 0.1, 2, 0.2)
)
pca <- runtime_figure_data(data[1:2, ], "pca")
stopifnot(identical(pca$series, c("fastEmbedR", "fastEmbedR")))
stopifnot(identical(as.character(pca$backend), c("CPU", "CUDA")))
stopifnot(identical(unname(runtime_figure_palette["fastEmbedR"]),
  "#0072B2"))
umap <- runtime_figure_data(data[3:4, ], "umap")
stopifnot(nrow(umap) == 1L, umap$series == "fastEmbedR",
  as.character(umap$backend) == "CUDA")
