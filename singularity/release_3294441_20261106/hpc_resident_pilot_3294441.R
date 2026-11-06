library(fastEmbedR)
identity <- readLines('/opt/fastembedr-manifest/source-identity.txt')
expected <- 'FastEmbedRCommit=32944414d8256da04d67df2ab8a62131ba61028c'
stopifnot(expected %in% identity,
    fastEmbedR:::massive_cuda_device_count_cpp() >= 2L)
groups <- rep(seq_len(4L), each = 30L)
pairs <- which(outer(groups, groups, `==`) &
    upper.tri(matrix(FALSE, 120L, 120L)), arr.ind = TRUE)
graph <- list(from = as.integer(pairs[, 1L]),
    to = as.integer(pairs[, 2L]),
    weight = rep(1, nrow(pairs)), n_vertices = 120L)
cpu <- graph_cluster(graph, method = 'leiden', backend = 'cpu',
    seed = 4L, n.cores = 1L)
gpu <- graph_cluster(graph, method = 'leiden', backend = 'cuda',
    seed = 4L, devices = c(0L, 1L))
ari <- fastEmbedR:::adjusted_rand_index(cpu$membership,
    gpu$membership)
stopifnot(length(gpu$membership) == 120L,
    all(is.finite(gpu$membership)),
    identical(gpu$gpu_devices, c(0L, 1L)),
    length(unique(gpu$gpu_identity)) == 2L,
    identical(gpu$implementation,
        'resident_cuda_coordinated_host_sync'),
    gpu$effective_gpu_workers == 2L,
    length(gpu$vertex_rows_per_device) == 2L,
    all(gpu$vertex_rows_per_device > 0L),
    length(gpu$csr_entries_per_device) == 2L,
    all(gpu$csr_entries_per_device > 0L),
    gpu$n_communities == 4L,
    is.finite(gpu$modularity),
    gpu$modularity > 0.5,
    ari > 0.95)
result <- list(source_commit = sub('^FastEmbedRCommit=', '', expected),
    gpu_devices = gpu$gpu_devices, gpu_identity = gpu$gpu_identity,
    effective_gpu_workers = gpu$effective_gpu_workers,
    vertex_rows_per_device = gpu$vertex_rows_per_device,
    csr_entries_per_device = gpu$csr_entries_per_device,
    cpu_modularity = cpu$modularity,
    gpu_modularity = gpu$modularity,
    adjusted_rand_index = ari,
    communities = gpu$n_communities)
path <- sprintf('/scratch/firenze/NN/singularity/release_3294441_20261106/pilot-%s-metrics.json',
    Sys.getenv('SLURM_JOB_ID'))
jsonlite::write_json(result, path, auto_unbox = TRUE, pretty = TRUE)
cat(jsonlite::toJSON(result, auto_unbox = TRUE), '\n')
cat('HPC_RESIDENT_CLUSTER_2GPU_PASS\n')
