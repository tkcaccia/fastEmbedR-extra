.libPaths(c('/Users/silvanopiazza/Documents/Stefano/fastEmbedR-multicpu-20261104/library', .libPaths()))
library(fastEmbedR)
d <- '/Users/silvanopiazza/Documents/Stefano/fastEmbedR-multicpu-20261104/benchmark-10k'
dir.create(d, showWarnings = FALSE)
n <- 10000L; k <- 12L
source <- file.path(d, 'knn')
rows <- seq_len(n) - 1L
neighbors <- outer(rows, seq_len(k), function(row, step) (row + step) %% n + 1L)
writeBin(as.integer(t(neighbors)), paste0(source,'.indices.u32'), size=4L, endian='little')
writeBin(rep(as.numeric(seq_len(k)), n), paste0(source,'.distances.f32'), size=4L, endian='little')
graph <- massive_umap_fuzzy_graph(massive_umap_memberships(massive_knn_graph(source,n,k)),file.path(d,'fuzzy'),memory_limit='128MB')
labels <- list(); scores <- numeric()
for (cores in c(1L,2L,4L)) {
  start <- proc.time()[[3L]]
  fit <- massive_louvain_level(graph,file.path(d,paste0('louvain-',cores,'.u32')),max_passes=4L,seed=4L,chunk_rows=1024L,memory_limit='256MB',n.cores=cores)
  seconds <- proc.time()[[3L]]-start
  labels[[as.character(cores)]] <- massive_read_rows(fit,1L,n)
  scores <- c(scores,fit$modularity_final)
  cat('RESULT',cores,seconds,fit$n_communities,fit$modularity_final,fit$moves,fit$cpu_workers,fit$parallel_stage,'\n')
}
cat('PARITY',identical(labels[['1']],labels[['2']]),identical(labels[['1']],labels[['4']]),'\n')
