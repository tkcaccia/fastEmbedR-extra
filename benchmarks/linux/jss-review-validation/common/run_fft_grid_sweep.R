#!/usr/bin/env Rscript

script_file <- sub("^--file=", "", commandArgs(FALSE)[
    startsWith(commandArgs(FALSE), "--file=")
][[1L]])
source(file.path(dirname(script_file), "common.R"))
suppressPackageStartupMessages(library(float))
args <- parse_cli()
value <- function(name, default) args[[name]] %||% default
dataset <- value("dataset", "MNIST")
backend <- value("backend", "cpu")
threads <- as_int(value("threads", 4L), 4L)
seed <- as_int(value("seed", 4L), 4L)
perplexity <- as_num(value("perplexity", 30), 30)
quality_n <- as_int(value("quality-n", 2000L), 2000L)
timing_reps <- as_int(value("timing-reps", 2L), 2L)
early_iter <- as_int(value("early-iterations", 250L), 250L)
normal_iter <- as_int(value("normal-iterations", 750L), 750L)
data_root <- value("data-root", "/scratch/firenze/NN/Data")
output_root <- value(
    "output-root", "/scratch/firenze/NN/fastEmbedR-results/jss_validation"
)
job_id <- value("job-id", "local")
grids <- csv_values(value("grids", "128,256,512"), "integer")
if (!backend %in% c("cpu", "cuda", "metal") ||
        !identical(sort(unique(grids)), c(128L, 256L, 512L)) ||
        timing_reps < 1L || quality_n < 32L ||
        early_iter < 0L || normal_iter < 1L) {
    stop("Invalid backend, grids, repetitions, or quality sample size.")
}
expected <- value("expected-version", "0.1")
if (as.character(utils::packageVersion("fastEmbedR")) != expected) {
    stop("Installed fastEmbedR version differs from the requested version.")
}

fit_grid <- function(knn, initial, grid) {
    Sys.setenv(FASTEMBEDR_TSNE_FFT_GRID = as.character(grid))
    fastEmbedR::tsne_knn(
        knn, perplexity = perplexity, Y_init = initial,
        seed = seed, backend = backend, n.cores = threads,
        learning_rate = "auto", early_exaggeration_iter = early_iter,
        n_iter = normal_iter, early_exaggeration = 12,
        negative_gradient_method = "fft", auto_config = FALSE
    )
}

force_score <- function(sample_knn, coordinates, grid) {
    diagnostic <- fastEmbedR:::opentsne_force_diagnostic_cpp(
        sample_knn$indices, sample_knn$distances,
        coordinates, perplexity, 1, grid, threads
    )
    exact <- diagnostic$repulsive_force_exact
    approx <- diagnostic$repulsive_force_fft
    error <- sqrt(sum((approx - exact)^2) / sum(exact^2))
    c(relative_force_error = error,
      resolution_score = 1 - min(1, error))
}

run_sweep <- function() {
    previous_grid <- Sys.getenv(
        "FASTEMBEDR_TSNE_FFT_GRID", unset = NA_character_
    )
    on.exit({
        if (is.na(previous_grid)) Sys.unsetenv("FASTEMBEDR_TSNE_FFT_GRID")
        else Sys.setenv(FASTEMBEDR_TSNE_FFT_GRID = previous_grid)
    }, add = TRUE)
    loaded <- load_dataset(data_root, dataset)
    x <- as_float_matrix(loaded$data)
    n <- nrow(x)
    if (n <= ceiling(perplexity) + 1L) {
        stop("Dataset has too few rows for the requested perplexity.")
    }
    out <- file.path(
        output_root, "fft_grid_sweep", dataset, backend, job_id
    )
    dir.create(out, recursive = TRUE, showWarnings = FALSE)
    rows <- stratified_rows(loaded$labels, n, quality_n, 2027L)
    write_csv_atomic(data.frame(source_row = rows),
        file.path(out, "quality_rows.csv"))
    knn <- fastEmbedR::precompute_knn(
        x, k = ceiling(perplexity), backend = "cpu", n.cores = threads
    )
    initial <- fastEmbedR::pca(
        x, ncomp = 2L, backend = "cpu", n.cores = threads,
        seed = seed, tsne_init = TRUE
    )$tsne_init
    sample_x <- x[rows, , drop = FALSE]
    sample_knn <- exact_knn_from_distances(
        exact_distance_matrix(sample_x), ceiling(perplexity)
    )
    metrics <- vector("list", length(grids))
    timings <- vector("list", length(grids))
    for (i in seq_along(grids)) {
        grid <- grids[[i]]
        cat("grid=", grid, " dataset=", dataset, " backend=", backend,
            "\n", sep = "")
        elapsed <- system.time({
            fit <- fit_grid(knn, initial, grid)
        })[["elapsed"]]
        config <- attr(fit, "fastEmbedR_config")
        if (!identical(config$backend, backend) ||
                !identical(config$fft_grid_size, grid)) {
            stop("Requested backend or FFT grid was not used.")
        }
        layout <- layout_matrix(fit)
        sampled <- layout[rows, , drop = FALSE]
        labels <- if (is.null(loaded$labels)) NULL else loaded$labels[rows]
        quality <- quality_metrics(
            sample_x, sampled, labels, perplexity, 1, k = 30L
        )
        score <- force_score(sample_knn, sampled, grid)
        metrics[[i]] <- cbind(data.frame(
            dataset, backend, n, p = ncol(x), seed, grid,
            early_iterations = early_iter, normal_iterations = normal_iter,
            job_id, image_sha256 = Sys.getenv("FASTEMBEDR_IMAGE_SHA256"),
            fft_grid_used = config$fft_grid_size,
            warmup_elapsed_sec = elapsed,
            relative_force_error = score[[1L]],
            resolution_score = score[[2L]],
            quality_n = length(rows)
        ), quality)
        grid_out <- file.path(out, paste0("grid", grid))
        dir.create(grid_out, recursive = TRUE, showWarnings = FALSE)
        write_csv_atomic(embedding_output_table(
            layout, loaded$labels), file.path(grid_out, "layout.csv"))
        plot_layout_dots(
            layout, loaded$labels, file.path(grid_out, "layout.png")
        )
        repeated <- numeric(timing_reps)
        for (rep in seq_len(timing_reps)) {
            repeated[[rep]] <- system.time({
                timed_fit <- fit_grid(knn, initial, grid)
            })[["elapsed"]]
            timed_config <- attr(timed_fit, "fastEmbedR_config")
            if (!identical(timed_config$backend, backend) ||
                    !identical(timed_config$fft_grid_size, grid)) {
                stop("Timed fit changed backend or grid.")
            }
        }
        timings[[i]] <- data.frame(
            dataset, backend, n, seed, grid,
            timing_scope = "matched_embedding_only",
            warmup_excluded = TRUE,
            timing_replicate = seq_len(timing_reps),
            elapsed_sec = repeated
        )
    }
    results <- do.call(rbind, metrics)
    reference <- results[results$grid == 512L, , drop = FALSE]
    trust_drop <- pmax(0, reference$trustworthiness -
        results$trustworthiness)
    preserve_drop <- pmax(0, reference$preserve_at_30 -
        results$preserve_at_30)
    kl_increase <- pmax(0, results$sampled_kl - reference$sampled_kl) /
        pmax(abs(reference$sampled_kl), 1e-9)
    results$quality_stability_score <- 1 / (1 + pmax(
        trust_drop / 0.01, preserve_drop / 0.03, kl_increase / 0.05
    ))
    results$quality_flag <- ifelse(
        results$quality_stability_score >= 0.5,
        "quality_stable", "review_quality"
    )
    write_csv_atomic(results,
        file.path(out, "grid_quality.csv"))
    write_csv_atomic(do.call(rbind, timings),
        file.path(out, "grid_timing_repetitions.csv"))
    write_csv_atomic(data.frame(dataset, backend, status = "success"),
        file.path(out, "status.csv"))
}

run_sweep()
