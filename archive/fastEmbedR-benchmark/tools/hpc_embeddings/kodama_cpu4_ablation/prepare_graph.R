source(file.path(dirname(script_file()), "common.R"))
args <- parse_cli(); dataset <- args$dataset %||% stop("--dataset required")
representation <- args$representation %||% stop("--representation required"); seed <- as_int(args$seed, 4L)
data_root <- args$data_root %||% stop("--data-root required"); out <- args$out_dir %||% stop("--out-dir required")
check_protocol_api(strict = TRUE); d <- load_dataset(dataset, representation, data_root)
x <- d$x; pca_seconds <- 0; pca_meta <- NULL
if (dataset == "imagenet" && representation == "pca50") {
  pca_path <- file.path(dirname(out), "..", "imagenet_pca50_seed4.rds")
  pca_path <- normalizePath(pca_path, mustWork = FALSE)
  if (!file.exists(pca_path)) {
    t0 <- proc.time()[["elapsed"]]
    pca <- kodamaR::KODAMA.pca(x, ncomp = 50L, center = TRUE, scale = FALSE,
      backend = "cpu", n.cores = 4L, seed = 4L)
    pca_seconds <- proc.time()[["elapsed"]] - t0
    atomic_save_rds(pca, pca_path)
  } else pca <- readRDS(pca_path)
  x <- as.matrix(pca$scores %||% pca$x %||% pca)
  pca_meta <- list(path = pca_path, sha256 = sha256(pca_path), seconds = pca_seconds)
}
t0 <- proc.time()[["elapsed"]]
graph <- kodamaR::KODAMA.graph(x, k = 100L, metric = "euclidean", backend = "cpu",
  n.cores = 4L, seed = seed, storage = "matrix")
graph_seconds <- proc.time()[["elapsed"]] - t0
payload <- list(graph = graph, x = x, labels = d$labels, dataset_path = d$path,
  dataset_sha256 = d$file_sha256, label_sha256 = d$label_sha256,
  dataset = dataset, representation = representation, seed = seed,
  pca = pca_meta, graph_seconds = graph_seconds, graph_bytes = as.numeric(object.size(graph)),
  n = nrow(x), p = ncol(x), created = format(Sys.time(), "%Y-%m-%dT%H:%M:%S%z"))
atomic_save_rds(payload, file.path(out, "prepared_graph.rds"))
atomic_write_csv(data.frame(dataset, representation, seed, n = nrow(x), p = ncol(x),
  pca_seconds, graph_seconds, graph_bytes = as.numeric(object.size(graph)), status = "success"),
  file.path(out, "graph_metadata.csv"))
