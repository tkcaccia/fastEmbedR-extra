args <- commandArgs(trailingOnly = TRUE)
stopifnot(length(args) == 1L)
stopifnot(fastEmbedR:::embedding_cuda_available_cpp())
stopifnot(fastEmbedR:::native_cuda_knn_available_cpp())

x <- scale(as.matrix(datasets::iris[seq_len(45L), 1:4]))
rows <- vector("list", 2L)
for (i in seq_along(rows)) {
    mode <- c("fuzzy", "binary")[[i]]
    started <- proc.time()[[3L]]
    fit <- fastEmbedR::umap(x, n_neighbors = 10L,
        n_components = 3L, landmarks = 0.5, backend = "cuda",
        graph_mode = mode, seed = 11L)
    layout <- as.matrix(fit$layout)
    reference <- as.matrix(fit$landmarks$layout)
    held_out <- fastEmbedR::project_landmark_model(
        fit$model, x[1:3, , drop = FALSE], transform_k = 10L,
        refinement_epochs = 5L)
    stopifnot(identical(dim(layout), c(45L, 3L)),
        all(is.finite(layout)), sd(layout[, 3L]) > 0,
        isTRUE(all.equal(layout[fit$landmarks$indices, , drop = FALSE],
            reference, tolerance = 1e-5,
            check.attributes = FALSE)),
        identical(fit$parameters$landmark_refinement_backend, "cuda"),
        identical(dim(held_out$layout), c(3L, 3L)),
        all(is.finite(as.matrix(held_out$layout))))
    rows[[i]] <- data.frame(mode = mode, n = nrow(layout),
        dimensions = ncol(layout), landmarks = nrow(reference),
        third_sd = sd(layout[, 3L]),
        elapsed_sec = proc.time()[[3L]] - started,
        refinement_backend = fit$parameters$landmark_refinement_backend)
}
result <- do.call(rbind, rows)
utils::write.csv(result, args[[1L]], row.names = FALSE)
print(result)
