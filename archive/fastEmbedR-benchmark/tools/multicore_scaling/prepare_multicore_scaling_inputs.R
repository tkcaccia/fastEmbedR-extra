script_dir <- dirname(normalizePath(sub("^--file=", "", grep(
  "^--file=", commandArgs(trailingOnly = FALSE), value = TRUE
)[1L])))
source(file.path(script_dir, "multicore_scaling_common.R"))

data_root <- arg_value("data-root", "/scratch/firenze/NN/Data")
cache_root <- dir_create(arg_value(
  "cache-root", "/scratch/firenze/NN/fastEmbedR-input/multicore_scaling"
))
datasets <- strsplit(arg_value(
  "datasets", "MetRef,MNIST,simulated_1M_2D"
), ",", fixed = TRUE)[[1L]]
n.cores <- as_int(arg_value("n.cores", "4"), 4L)
seed <- as_int(arg_value("seed", "4"), 4L)

suppressPackageStartupMessages(library(fastEmbedR))

for (dataset in datasets) {
  message("Preparing fixed inputs for ", dataset)
  loaded <- load_scaling_dataset(dataset, data_root, seed)
  x <- loaded$data
  pars <- dataset_parameters(dataset, nrow(x))
  paths <- cache_paths(cache_root, dataset)
  dir_create(paths$folder)

  knn <- fastEmbedR::precompute_knn(
    x, k = max(pars$k_umap, pars$k_tsne), metric = "euclidean",
    backend = "cpu", n.cores = n.cores
  )
  saveRDS(knn, paths$knn, compress = FALSE)

  pca_fit <- fastEmbedR::pca(
    x, ncomp = 2L, center = TRUE, scale = FALSE, backend = "cpu",
    n.cores = n.cores, seed = seed, opentsne_init = TRUE
  )
  pca_init <- layout_matrix(pca_fit$opentsne_init)
  saveRDS(pca_init, paths$pca, compress = FALSE)

  umap_knn <- list(
    indices = knn$indices[, seq_len(pars$k_umap), drop = FALSE],
    distances = knn$distances[, seq_len(pars$k_umap), drop = FALSE]
  )
  prepared <- fastEmbedR::prepare_umap_knn(
    umap_knn, backend = "cpu", n.cores = n.cores, graph_mode = "fuzzy"
  )
  initialized <- fastEmbedR::umap_init(
    prepared, backend = "cpu", n.cores = n.cores,
    graph_mode = "fuzzy", seed = seed
  )
  saveRDS(initialized, paths$umap, compress = FALSE)

  manifest <- data.frame(
    dataset = dataset, profile = loaded$profile, n = nrow(x), p = ncol(x),
    k_umap = pars$k_umap, perplexity = pars$perplexity,
    k_tsne = pars$k_tsne, source = loaded$source,
    source_md5 = loaded$source_md5, seed = seed,
    preparation_n_cores = n.cores,
    knn_md5 = unname(tools::md5sum(paths$knn)),
    pca_md5 = unname(tools::md5sum(paths$pca)),
    umap_md5 = unname(tools::md5sum(paths$umap)),
    stringsAsFactors = FALSE
  )
  write.csv(manifest, paths$manifest, row.names = FALSE)
  rm(x, knn, pca_fit, pca_init, prepared, initialized)
  gc()
}

write_session_manifest(file.path(cache_root, "preparation_session.txt"))
