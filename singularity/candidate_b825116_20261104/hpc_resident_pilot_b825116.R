library(fastEmbedR)
stopifnot(isTRUE(fastEmbedR:::massive_nccl_available_cpp()))
stopifnot(fastEmbedR:::massive_cuda_device_count_cpp() >= 2L)
cat('CUDA_VISIBLE_DEVICES=', Sys.getenv('CUDA_VISIBLE_DEVICES'), '\n')
cat('SLURM_JOB_GPUS=', Sys.getenv('SLURM_JOB_GPUS'), '\n')
set.seed(84L)
x <- rbind(matrix(rnorm(80L * 8L, 0, 0.2), 80L, 8L),
           matrix(rnorm(80L * 8L, 3, 0.2), 80L, 8L))
fit <- umap(x, n_neighbors = 15L, n_components = 3L,
    landmarks = 80L, backend = 'cuda', devices = c(0L, 1L),
    seed = 84L, refinement_epochs = 5L)
stopifnot(identical(dim(fit$layout), c(160L, 3L)))
stopifnot(all(is.finite(fit$layout)))
stopifnot(identical(fit$parameters$landmark_refinement_gpu_devices,
    c(0L, 1L)))
stopifnot(length(fit$parameters$landmark_refinement_gpu_identity) == 2L)
stopifnot(max(abs(fit$layout[fit$landmarks$indices, , drop = FALSE] -
    fit$landmarks$layout)) < 1e-5)
print(fit$parameters[c('backend', 'nn_backend',
    'projection_nn_backend', 'landmark_refinement_backend',
    'landmark_refinement_gpu_devices',
    'landmark_refinement_gpu_identity')])
cat('HPC_RESIDENT_UMAP_2GPU_PASS\n')
