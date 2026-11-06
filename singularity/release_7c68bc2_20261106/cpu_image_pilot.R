library(fastEmbedR)

identity <- readLines('/opt/fastembedr-manifest/source-identity.txt')
commit <- '7c68bc2a48ff3f98d07f216db9601047951827fd'
stopifnot(paste0('FastEmbedRCommit=', commit) %in% identity)

x <- as.matrix(iris[, 1:4])
fit <- umap(x, n_neighbors = 15L, n_components = 3L,
    backend = 'cpu', n.cores = 4L, seed = 4L)
stopifnot(identical(dim(fit$layout), c(150L, 3L)),
    all(is.finite(fit$layout)),
    identical(fit$parameters$backend, 'cpu'),
    identical(fit$parameters$n.cores_effective, 4L))

result <- list(source_commit = commit, method = 'umap',
    backend = fit$parameters$backend,
    requested_cores = 4L,
    effective_cores = fit$parameters$n.cores_effective,
    rows = nrow(fit$layout), dimensions = ncol(fit$layout),
    elapsed_seconds = fit$metrics$elapsed)
cat(jsonlite::toJSON(result, auto_unbox = TRUE), '\n')
cat('HPC_7C68BC2_CPU_IMAGE_PILOT_PASS\n')
