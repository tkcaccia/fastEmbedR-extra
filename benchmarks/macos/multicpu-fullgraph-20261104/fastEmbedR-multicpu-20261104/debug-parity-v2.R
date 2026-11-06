.libPaths(c('/Users/silvanopiazza/Documents/Stefano/fastEmbedR-multicpu-20261104/library', .libPaths()))
library(fastEmbedR)
d <- '/Users/silvanopiazza/Documents/Stefano/fastEmbedR-multicpu-20261104/debug-512-v2'
dir.create(d, showWarnings = FALSE)
n <- 512L; k <- 6L
source <- file.path(d, 'knn')
rows <- seq_len(n) - 1L
neighbors <- outer(rows, seq_len(k), function(row, step) (row + step) %% n + 1L)
writeBin(as.integer(t(neighbors)), paste0(source, '.indices.u32'), size=4L, endian='little')
writeBin(rep(as.numeric(seq_len(k)), n), paste0(source, '.distances.f32'), size=4L, endian='little')
graph <- massive_umap_fuzzy_graph(massive_umap_memberships(massive_knn_graph(source,n,k)), file.path(d,'fuzzy'), memory_limit='64MB')
a <- massive_louvain_level(graph,file.path(d,'parent1.u32'),seed=4L,chunk_rows=64L,memory_limit='128MB',n.cores=1L)
b <- massive_louvain_level(graph,file.path(d,'parent4.u32'),seed=4L,chunk_rows=64L,memory_limit='128MB',n.cores=4L)
cat('LOUVAIN_LEVEL',identical(massive_read_rows(a,1L,n),massive_read_rows(b,1L,n)),a$modularity_final,b$modularity_final,a$moves,b$moves,'\n')
c <- massive_leiden_refine_level(graph,a,file.path(d,'refine1.u32'),seed=4L,chunk_rows=64L,memory_limit='128MB',n.cores=1L)
e <- massive_leiden_refine_level(graph,a,file.path(d,'refine4.u32'),seed=4L,chunk_rows=64L,memory_limit='128MB',n.cores=4L)
cat('LEIDEN_REFINE',identical(readBin(c$membership_path,integer(),n=n,size=4L,endian='little'),readBin(e$membership_path,integer(),n=n,size=4L,endian='little')),c$n_refined,e$n_refined,c$moves,e$moves,'\n')
