source(file.path(dirname(sub("^--file=", "", commandArgs(FALSE)[grepl("^--file=", commandArgs(FALSE))][1L])), "common.R"))
args <- parse_cli(); require_capability("folds")
dataset <- args$dataset %||% stop("--dataset is required")
seed <- as_int(args$seed, 4L); backend <- args$backend %||% "cuda"; ncores <- as_int(args$n_cores, 4L)
out_dir <- args$out_dir %||% stop("--out-dir is required"); layout_dir <- args$layout_dir %||% file.path(out_dir,"layouts")
dir.create(out_dir, recursive=TRUE, showWarnings=FALSE); dir.create(layout_dir, recursive=TRUE, showWarnings=FALSE)
lock <- read_release_lock(args$release_lock, args$image)
data <- load_dataset(dataset, args$data_root, load_registry(args$registry %||% file.path(suite_dir(),"datasets.csv")))
write_manifest(out_dir, lock, dataset, backend, seed, list(protocol="confirmatory-v1"))

rows <- list(); layouts <- list(); set.seed(seed)
graph_time <- run_timed(kodamaR::KODAMA.graph(data$x, k=100L, metric="euclidean", backend=backend,
                                              n.cores=ncores, seed=seed))
graph <- graph_time$value
for (method in c("UMAP", "opentsne")) {
  b <- run_timed(classic_embedding(data$x, method, backend, ncores, seed))
  layouts[[paste("classic",method,sep="_")]] <- b$value
  q <- layout_metrics(data$x,b$value,data$labels,seed)
  rows[[length(rows)+1L]] <- result_row(dataset,seed,"none",method,"classic",backend,data,NULL,b$value,b$elapsed,NA,q)
}

for (classifier in c("knn","pls_lda")) {
  fit_args <- list(data=data$x, graph=graph, M=100L, Tcycle=100L, folds=5L,
    ncomp=min(50L,data$p), landmarks=10000000L,
    splitting=if (data$n < 40000L) 100L else 300L, n.cores=ncores,
    graph.neighbors=100L, knn.k=30L, metric="euclidean", classifier=classifier,
    backend=backend, seed=seed, visual.init=TRUE, progress=TRUE,
    apply.kodama.dissimilarity=TRUE)
  ft <- run_timed(do.call(kodamaR::KODAMA.matrix, fit_args)); fit <- ft$value
  for (method in c("UMAP","opentsne")) {
    vt <- run_timed(kodama_embedding(fit,method,backend,ncores,seed)); key <- paste(classifier,method,sep="_")
    layouts[[key]] <- vt$value
    q <- layout_metrics(data$x,vt$value,data$labels,seed)
    rows[[length(rows)+1L]] <- result_row(dataset,seed,classifier,method,"kodama",backend,data,fit,
      vt$value,ft$elapsed+vt$elapsed,graph_time$elapsed,q)
  }
  saveRDS(list(best_labels=fit$best_labels,acc=fit$acc,knn=fit$knn,timing=fit$timing,
               parameters=fit$parameters), file.path(out_dir,paste0("fit_",classifier,".rds")),compress=FALSE)
}
saveRDS(layouts,file.path(layout_dir,paste0(safe_name(dataset),"_seed",seed,"_layouts.rds")),compress=FALSE)
write.csv(do.call(rbind,rows),file.path(out_dir,paste0(safe_name(dataset),"_seed",seed,"_confirmatory.csv")),row.names=FALSE)

