#!/usr/bin/env Rscript

args <- commandArgs(trailingOnly = TRUE)
arg_value <- function(name, default = NULL) {
    prefix <- paste0("--", name, "=")
    hit <- args[startsWith(args, prefix)]
    if (!length(hit)) return(default)
    sub(prefix, "", hit[[length(hit)]], fixed = TRUE)
}

script_file <- sub("^--file=", "", commandArgs(FALSE)[
    startsWith(commandArgs(FALSE), "--file=")
][[1L]])
script_dir <- dirname(normalizePath(script_file, mustWork = TRUE))
source(file.path(script_dir, "common.R"))

suppressPackageStartupMessages(library(fastEmbedR))
if (!requireNamespace("float", quietly = TRUE)) {
    stop("The float package is required by this validation suite.")
}

mode <- arg_value("mode", "preflight")
base_dir <- normalizePath(
    arg_value("base-dir", "/scratch/firenze/NN"), mustWork = TRUE
)
data_root <- arg_value("data-root", file.path(base_dir, "Data"))
input_root <- arg_value(
    "input-root", file.path(base_dir, "fastEmbedR-input", "jss_validation")
)
output_root <- arg_value(
    "output-root", file.path(base_dir, "fastEmbedR-results", "jss_validation")
)
image <- arg_value(
    "image", file.path(base_dir, "singularity", "fastembedr_cuda.sif")
)
dataset <- arg_value("dataset", "MNIST")
backend <- arg_value("backend", "cpu")
threads <- as_int(arg_value("threads"), 4L)
perplexity <- as_num(arg_value("perplexity"), 30)
support_multiplier <- as_num(arg_value("support-multiplier"), 1)
timing_reps <- as_int(arg_value("timing-reps"), 5L)
seeds <- csv_values(arg_value("seeds", "4,17,29"), "integer")
max_n <- as_int(arg_value("max-n"), 70000L)
quality_n <- as_int(arg_value("quality-n"), 2000L)
expected_version <- arg_value("expected-version", "0.1")
longrun_n <- as_int(arg_value("longrun-n"), 2000L)
grid_size <- as_int(arg_value("grid-size"), 256L)
normal_iterations <- as_int(arg_value("normal-iterations"), 750L)
run_seed <- as_int(arg_value("run-seed"), 42L)
quality_boundary <- arg_value("quality-boundary", "matched_knn")
landmark_fraction <- as_num(arg_value("landmark-fraction"), 0.2)

dir.create(input_root, recursive = TRUE, showWarnings = FALSE)
dir.create(output_root, recursive = TRUE, showWarnings = FALSE)

dataset_input_dir <- function(name) {
    file.path(input_root, name)
}

dataset_output_dir <- function(experiment, name, used_backend = backend) {
    file.path(output_root, experiment, name, used_backend)
}

shared_input_path <- function(name) {
    file.path(dataset_input_dir(name), "matched_inputs.rds")
}

longrun_input_path <- function(name) {
    file.path(dataset_input_dir(name), "tsne_longrun_inputs.rds")
}

write_status <- function(experiment, name, used_backend, status, error = NA,
                         ...) {
    path <- file.path(
        dataset_output_dir(experiment, name, used_backend), "status.csv"
    )
    write_csv_atomic(status_row(
        experiment, name, used_backend, status, error, ...
    ), path)
}

require_expected_version <- function() {
    observed <- as.character(utils::packageVersion("fastEmbedR"))
    if (!identical(observed, expected_version)) {
        stop(
            "Expected fastEmbedR ", expected_version,
            " but loaded ", observed, ".",
            call. = FALSE
        )
    }
}

run_preflight <- function() {
    require_expected_version()
    assert_backend(backend)
    out <- file.path(output_root, "identity", backend)
    dir.create(out, recursive = TRUE, showWarnings = FALSE)
    write_csv_atomic(package_identity(image), file.path(out, "identity.csv"))
    capture.output(
        print(fastEmbedR::fastEmbedR_capabilities()),
        file = file.path(out, "capabilities.txt")
    )
    capture.output(sessionInfo(), file = file.path(out, "sessionInfo.txt"))
    python <- Sys.getenv("FASTEMBEDR_PYTHON", "/opt/conda/bin/python")
    if (backend == "cpu") {
        if (!file.exists(python)) {
            stop("Missing Python runtime: ", python, call. = FALSE)
        }
        python_check <- system2(
            python,
            c("-c", shQuote(paste(
                "import openTSNE, numpy;",
                "print('openTSNE=' + openTSNE.__version__);",
                "print('numpy=' + numpy.__version__)"
            ))),
            stdout = TRUE, stderr = TRUE
        )
        python_status <- attr(python_check, "status") %||% 0L
        writeLines(python_check, file.path(out, "python_versions.txt"))
        if (python_status != 0L) {
            stop("Python openTSNE preflight failed.", call. = FALSE)
        }
    }
    set.seed(4L)
    smoke_x <- matrix(runif(512L * 16L), nrow = 512L)
    smoke_fit <- fastEmbedR::umap(
        smoke_x, n_neighbors = 15L, backend = backend,
        n.cores = threads, seed = 4L, graph_mode = "fuzzy"
    )
    observed_backend <- assert_layout_backend(smoke_fit, backend)
    smoke_layout <- layout_matrix(smoke_fit)
    if (!all(is.finite(smoke_layout))) {
        stop("Preflight layout contains non-finite values.", call. = FALSE)
    }
    raw_layout <- if (is.list(smoke_fit)) smoke_fit$layout else smoke_fit
    smoke_config <- attr(raw_layout, "fastEmbedR_config", exact = TRUE)
    write_csv_atomic(data.frame(
        requested_backend = backend,
        observed_backend = observed_backend,
        knn_backend = smoke_config$knn_backend %||% NA_character_,
        n = nrow(smoke_layout), p = ncol(smoke_layout),
        finite = all(is.finite(smoke_layout)),
        stringsAsFactors = FALSE
    ), file.path(out, "backend_smoke.csv"))
    if (backend == "cuda") {
        system2("nvidia-smi", stdout = file.path(out, "nvidia-smi.txt"),
            stderr = TRUE
        )
    }
    write_status("preflight", "all", backend, "success")
}

run_precompute <- function() {
    require_expected_version()
    loaded <- load_dataset(data_root, dataset)
    rows <- stratified_rows(
        loaded$labels, nrow(loaded$data), max_n, seed = 1701L
    )
    selected <- subset_dataset(loaded, rows)
    x <- as_float_matrix(selected$data)
    max_k <- min(nrow(x) - 1L, ceiling(3 * perplexity))
    adaptive_quality_n <- if (ncol(x) > 5000L) {
        min(quality_n, 500L)
    } else if (ncol(x) > 1000L) {
        min(quality_n, 1000L)
    } else {
        quality_n
    }
    quality_rows <- stratified_rows(
        selected$labels, nrow(x), adaptive_quality_n, seed = 2027L
    )
    recall_query_n <- knn_recall_sample_size(nrow(x), ncol(x))
    recall_query_rows <- stratified_rows(
        selected$labels, nrow(x), recall_query_n, seed = 31337L
    )
    recall_reference_time <- system.time({
        recall_exact <- exact_sampled_self_knn(
            x, recall_query_rows, ceiling(perplexity)
        )
    })[["elapsed"]]
    knn_time <- system.time({
        knn <- fastEmbedR::precompute_knn(
            x, k = max_k, metric = "euclidean",
            backend = "cpu", n.cores = 12L
        )
    })[["elapsed"]]
    pca_time <- system.time({
        pca_fit <- fastEmbedR::pca(
            x, ncomp = 2L, backend = "cpu", n.cores = 12L,
            seed = 4L, tsne_init = TRUE
        )
    })[["elapsed"]]
    shared <- list(
        dataset = dataset, source_path = loaded$path,
        source_object = loaded$object_name,
        source_n = nrow(loaded$data), source_p = ncol(loaded$data),
        rows = rows, labels = selected$labels,
        quality_rows = quality_rows,
        recall_query_rows = recall_query_rows,
        recall_exact = recall_exact,
        knn = knn, init = pca_fit$tsne_init,
        perplexity = perplexity, max_k = max_k,
        input_class = class(x), knn_elapsed_sec = knn_time,
        pca_elapsed_sec = pca_time,
        recall_reference_elapsed_sec = recall_reference_time,
        package_version = as.character(utils::packageVersion("fastEmbedR")),
        created_utc = format(Sys.time(), tz = "UTC", usetz = TRUE)
    )
    path <- shared_input_path(dataset)
    dir.create(dirname(path), recursive = TRUE, showWarnings = FALSE)
    saveRDS(shared, path, compress = FALSE)
    write_csv_atomic(data.frame(
        selected_position = seq_along(rows), source_row = rows,
        quality_sample = seq_along(rows) %in% quality_rows
    ), file.path(dataset_input_dir(dataset), "row_identifiers.csv"))
    write_csv_atomic(data.frame(
        dataset = dataset, source_path = loaded$path,
        source_n = nrow(loaded$data), source_p = ncol(loaded$data),
        benchmark_n = nrow(x), benchmark_p = ncol(x),
        quality_n = length(quality_rows), max_k = max_k,
        knn_elapsed_sec = knn_time, pca_elapsed_sec = pca_time,
        recall_query_n = length(recall_query_rows),
        recall_reference_elapsed_sec = recall_reference_time,
        shared_input = path, stringsAsFactors = FALSE
    ), file.path(dataset_input_dir(dataset), "manifest.csv"))
    write_status("precompute", dataset, "cpu", "success")
}

write_longrun_portable_inputs <- function(bundle, directory) {
    dir.create(directory, recursive = TRUE, showWarnings = FALSE)
    write_csv_atomic(
        bundle$affinity,
        file.path(directory, "compact_affinity_edges.csv")
    )
    for (seed_name in names(bundle$initializations)) {
        write_csv_atomic(
            as.data.frame(bundle$initializations[[seed_name]]),
            file.path(directory, paste0("init_seed", seed_name, ".csv"))
        )
    }
    connection <- file(file.path(directory, "data_float32_rowmajor.bin"), "wb")
    on.exit(close(connection), add = TRUE)
    writeBin(
        as.vector(t(as_double_matrix(bundle$data))), connection,
        size = 4L, endian = "little"
    )
    label <- if (is.null(bundle$labels)) {
        rep.int(NA_character_, nrow(bundle$data))
    } else {
        as.character(bundle$labels)
    }
    write_csv_atomic(
        data.frame(row = seq_len(nrow(bundle$data)), label = label),
        file.path(directory, "labels.csv")
    )
    write_csv_atomic(data.frame(
        dataset = bundle$dataset,
        n = nrow(bundle$data), p = ncol(bundle$data),
        k = ncol(bundle$knn$indices), perplexity = bundle$perplexity,
        early_exaggeration_iter = 250L,
        early_exaggeration = 12,
        learning_rate = nrow(bundle$data) / 12,
        initial_momentum = 0.8, final_momentum = 0.8,
        max_step_norm = 5,
        stringsAsFactors = FALSE
    ), file.path(directory, "portable_manifest.csv"))
}

run_longrun_precompute <- function() {
    require_expected_version()
    loaded <- load_dataset(data_root, dataset)
    rows <- stratified_rows(
        loaded$labels, nrow(loaded$data), longrun_n, seed = 2027L
    )
    selected <- subset_dataset(loaded, rows)
    x <- as_float_matrix(selected$data)
    distance <- exact_distance_matrix(x)
    knn <- exact_knn_from_distances(
        distance, min(nrow(x) - 1L, ceiling(perplexity))
    )
    initializations <- list()
    for (seed in c(4L, 17L, 42L)) {
        fit <- fastEmbedR::pca(
            x, ncomp = 2L, backend = "cpu", n.cores = 12L,
            seed = seed, tsne_init = TRUE
        )
        initializations[[as.character(seed)]] <- fit$tsne_init
    }
    bundle <- list(
        dataset = dataset, data = x, labels = selected$labels,
        source_rows = rows, knn = knn,
        affinity = symmetrized_affinities(knn, perplexity),
        initializations = initializations, perplexity = perplexity,
        package_version = as.character(utils::packageVersion("fastEmbedR")),
        created_utc = format(Sys.time(), tz = "UTC", usetz = TRUE)
    )
    path <- longrun_input_path(dataset)
    dir.create(dirname(path), recursive = TRUE, showWarnings = FALSE)
    saveRDS(bundle, path, compress = FALSE)
    portable <- file.path(dataset_input_dir(dataset), "tsne_longrun_portable")
    write_longrun_portable_inputs(bundle, portable)
    write_csv_atomic(data.frame(
        selected_position = seq_along(rows), source_row = rows
    ), file.path(portable, "row_identifiers.csv"))
    write_status("tsne_longrun_precompute", dataset, "cpu", "success")
}

longrun_output_dir <- function(name, used_backend, seed, grid, iterations,
                               used_threads) {
    config <- paste0(
        used_threads, "t_grid", grid, "_iter", iterations,
        "_seed", seed
    )
    file.path(output_root, "tsne_longrun", name, used_backend, config)
}

run_longrun_tsne <- function() {
    require_expected_version()
    assert_backend(backend)
    bundle <- readRDS(longrun_input_path(dataset))
    seed_name <- as.character(run_seed)
    if (!seed_name %in% names(bundle$initializations)) {
        stop("No archived initialization for seed ", run_seed, call. = FALSE)
    }
    previous_grid <- Sys.getenv("FASTEMBEDR_TSNE_FFT_GRID", unset = NA)
    on.exit({
        if (is.na(previous_grid)) {
            Sys.unsetenv("FASTEMBEDR_TSNE_FFT_GRID")
        } else {
            Sys.setenv(FASTEMBEDR_TSNE_FFT_GRID = previous_grid)
        }
    }, add = TRUE)
    Sys.setenv(FASTEMBEDR_TSNE_FFT_GRID = as.character(grid_size))
    elapsed <- system.time({
        layout <- fastEmbedR::tsne_knn(
            bundle$knn$indices, bundle$knn$distances,
            perplexity = bundle$perplexity,
            Y_init = bundle$initializations[[seed_name]],
            seed = run_seed, backend = backend, n.cores = threads,
            learning_rate = nrow(bundle$data) / 12,
            early_exaggeration_iter = 250L,
            early_exaggeration = 12,
            n_iter = normal_iterations, exaggeration = 1,
            initial_momentum = 0.8, final_momentum = 0.8,
            max_step_norm = 5, negative_gradient_method = "fft",
            record_costs = TRUE, auto_config = FALSE
        )
    })[["elapsed"]]
    assert_layout_backend(layout, backend)
    matrix_layout <- layout_matrix(layout)
    cfg <- attr(layout, "fastEmbedR_config")
    quality <- quality_metrics(
        bundle$data, matrix_layout, bundle$labels,
        bundle$perplexity, support_multiplier = 1, k = 30L
    )
    diagnostic_kl <- getFromNamespace(
        "opentsne_kl_diagnostic_cpp", "fastEmbedR"
    )(
        bundle$knn$indices, bundle$knn$distances, matrix_layout,
        bundle$perplexity, threads
    )
    recorded <- tail(attr(layout, "itercosts"), 1L)
    if (!length(recorded)) recorded <- NA_real_
    out <- longrun_output_dir(
        dataset, backend, run_seed, grid_size,
        normal_iterations, threads
    )
    dir.create(out, recursive = TRUE, showWarnings = FALSE)
    result <- cbind(data.frame(
        dataset = dataset, backend = backend, seed = run_seed,
        n = nrow(bundle$data), p = ncol(bundle$data),
        perplexity = bundle$perplexity,
        support_k = ncol(bundle$knn$indices),
        grid_requested = grid_size,
        grid_used = cfg$fft_grid_size %||% NA_integer_,
        threads = threads, early_iterations = 250L,
        normal_iterations = normal_iterations,
        learning_rate = nrow(bundle$data) / 12,
        elapsed_sec = elapsed,
        timing_scope = "matched_embedding_single_diagnostic_run",
        timing_eligible = FALSE,
        native_kl = as.numeric(diagnostic_kl),
        common_affinity_kl = sampled_tsne_kl(
            matrix_layout, bundle$knn, bundle$perplexity
        ),
        final_recorded_kl = as.numeric(recorded),
        max_abs_coordinate = max(abs(matrix_layout)),
        finite = all(is.finite(matrix_layout)),
        stringsAsFactors = FALSE
    ), quality)
    write_csv_atomic(result, file.path(out, "result.csv"))
    iterations <- attr(layout, "itercost_iterations")
    costs <- attr(layout, "itercosts")
    if (length(iterations) && length(costs)) {
        write_csv_atomic(data.frame(
            iteration = iterations, kl = costs
        ), file.path(out, "native_objective_trace.csv"))
    }
    saveRDS(list(
        layout = matrix_layout, config = cfg,
        source_rows = bundle$source_rows
    ), file.path(out, "layout.rds"), compress = FALSE)
    write_csv_atomic(
        as.data.frame(matrix_layout), file.path(out, "layout.csv")
    )
    plot_layout_dots(
        matrix_layout, bundle$labels, file.path(out, "layout.png")
    )
    write_csv_atomic(status_row(
        "tsne_longrun", dataset, backend, "success",
        grid_size = grid_size, normal_iterations = normal_iterations,
        seed = run_seed, threads = threads
    ), file.path(out, "status.csv"))
}

run_longrun_timing <- function() {
    require_expected_version()
    assert_backend(backend)
    bundle <- readRDS(longrun_input_path(dataset))
    seed_name <- as.character(run_seed)
    if (!seed_name %in% names(bundle$initializations)) {
        stop("No archived initialization for seed ", run_seed, call. = FALSE)
    }
    previous_grid <- Sys.getenv("FASTEMBEDR_TSNE_FFT_GRID", unset = NA)
    on.exit({
        if (is.na(previous_grid)) {
            Sys.unsetenv("FASTEMBEDR_TSNE_FFT_GRID")
        } else {
            Sys.setenv(FASTEMBEDR_TSNE_FFT_GRID = previous_grid)
        }
    }, add = TRUE)
    Sys.setenv(FASTEMBEDR_TSNE_FFT_GRID = as.character(grid_size))
    fit_once <- function() {
        fastEmbedR::tsne_knn(
            bundle$knn$indices, bundle$knn$distances,
            perplexity = bundle$perplexity,
            Y_init = bundle$initializations[[seed_name]],
            seed = run_seed, backend = backend, n.cores = threads,
            learning_rate = nrow(bundle$data) / 12,
            early_exaggeration_iter = 250L,
            early_exaggeration = 12,
            n_iter = normal_iterations, exaggeration = 1,
            initial_momentum = 0.8, final_momentum = 0.8,
            max_step_norm = 5, negative_gradient_method = "fft",
            record_costs = FALSE, auto_config = FALSE
        )
    }
    warmup <- fit_once()
    assert_layout_backend(warmup, backend)
    rows <- vector("list", timing_reps)
    for (replicate in seq_len(timing_reps)) {
        elapsed <- system.time({
            layout <- fit_once()
        })[["elapsed"]]
        assert_layout_backend(layout, backend)
        rows[[replicate]] <- data.frame(
            dataset = dataset, backend = backend,
            timing_scope = "matched_embedding_only",
            seed = run_seed, timing_replicate = replicate,
            warmup_count = 1L, warmup_excluded = TRUE,
            n = nrow(bundle$data), p = ncol(bundle$data),
            perplexity = bundle$perplexity,
            support_k = ncol(bundle$knn$indices),
            grid_requested = grid_size, threads = threads,
            early_iterations = 250L,
            normal_iterations = normal_iterations,
            elapsed_sec = elapsed, stringsAsFactors = FALSE
        )
    }
    out <- dataset_output_dir(
        "tsne_longrun_timing", dataset,
        paste0(backend, "_", threads, "t")
    )
    dir.create(out, recursive = TRUE, showWarnings = FALSE)
    write_csv_atomic(
        do.call(rbind, rows), file.path(out, "timing_repetitions.csv")
    )
    write_status(
        "tsne_longrun_timing", dataset,
        paste0(backend, "_", threads, "t"), "success",
        seed = run_seed, timing_reps = timing_reps,
        warmup_count = 1L
    )
}

run_affinity <- function() {
    shared <- readRDS(shared_input_path(dataset))
    loaded <- load_dataset(data_root, dataset)
    selected <- subset_dataset(loaded, shared$rows)
    sample <- subset_dataset(selected, shared$quality_rows)
    x <- as_double_matrix(sample$data)
    distance <- exact_distance_matrix(x)
    perplexities <- c(5, 15, 30, 50)
    perplexities <- perplexities[3 * perplexities < nrow(x)]
    max_support <- min(nrow(x) - 1L, 4L * max(perplexities))
    knn <- exact_knn_from_distances(distance, max_support)
    rows <- list()
    for (value in perplexities) {
        for (multiplier in c(1, 2, 3, 4)) {
            row <- affinity_summary(knn, value, multiplier)
            row$dataset <- dataset
            row$n <- nrow(x)
            row$p <- ncol(x)
            rows[[length(rows) + 1L]] <- row
        }
    }
    result <- do.call(rbind, rows)
    result <- result[c("dataset", "n", "p", setdiff(
        names(result), c("dataset", "n", "p")
    ))]
    out <- dataset_output_dir("affinity", dataset, "cpu")
    write_csv_atomic(result, file.path(out, "affinity_characterization.csv"))
    write_status("affinity", dataset, "cpu", "success")
}

run_tsne_once <- function(knn, init, multiplier, seed, used_backend) {
    width <- min(ncol(knn$indices), ceiling(perplexity * multiplier))
    indices <- knn$indices[, seq_len(width), drop = FALSE]
    distances <- knn$distances[, seq_len(width), drop = FALSE]
    controls <- list(
        perplexity = perplexity, n_components = 2L,
        Y_init = init, seed = seed, backend = used_backend,
        learning_rate = max(nrow(indices) / 12, 200),
        early_exaggeration_iter = 250L,
        early_exaggeration = 12, n_iter = 500L,
        exaggeration = 1, initial_momentum = 0.8,
        final_momentum = 0.8, max_step_norm = "auto",
        negative_gradient_method = "fft", record_costs = TRUE,
        auto_config = FALSE, verbose = FALSE
    )
    if (multiplier == 1) {
        return(do.call(fastEmbedR::tsne_knn, c(list(
            indices = indices, distances = distances,
            n.cores = threads
        ), controls)))
    }
    worker <- getFromNamespace(
        "fast_knn_opentsne_materialized", "fastEmbedR"
    )
    names(controls)[names(controls) == "backend"] <- "backend"
    do.call(worker, c(list(
        indices = indices, distances = distances,
        n_threads = threads, input_backend = "shared_cpu_hnsw"
    ), controls))
}

run_support <- function() {
    assert_backend(backend)
    shared <- readRDS(shared_input_path(dataset))
    loaded <- load_dataset(data_root, dataset)
    selected <- subset_dataset(loaded, shared$rows)
    x <- as_float_matrix(selected$data)
    out <- dataset_output_dir(
        paste0("support_", support_multiplier, "P"), dataset, backend
    )
    dir.create(out, recursive = TRUE, showWarnings = FALSE)

    invisible(run_tsne_once(
        shared$knn, shared$init, support_multiplier, 4L, backend
    ))
    timings <- vector("list", timing_reps)
    last_layout <- NULL
    for (replicate in seq_len(timing_reps)) {
        elapsed <- system.time({
            last_layout <- run_tsne_once(
                shared$knn, shared$init, support_multiplier, 4L, backend
            )
        })[["elapsed"]]
        assert_layout_backend(last_layout, backend)
        timings[[replicate]] <- data.frame(
            dataset = dataset, backend = backend,
            support_multiplier = support_multiplier,
            support_k = ceiling(perplexity * support_multiplier),
            timing_seed = 4L, timing_replicate = replicate,
            elapsed_sec = elapsed, warmup_excluded = TRUE,
            stringsAsFactors = FALSE
        )
    }
    write_csv_atomic(do.call(rbind, timings),
        file.path(out, "timing_repetitions.csv")
    )

    layouts <- list(`4` = layout_matrix(last_layout))
    seed_times <- data.frame(
        seed = 4L, elapsed_sec = timings[[timing_reps]]$elapsed_sec
    )
    for (seed in setdiff(seeds, 4L)) {
        elapsed <- system.time({
            observed <- run_tsne_once(
                shared$knn, shared$init, support_multiplier, seed, backend
            )
        })[["elapsed"]]
        assert_layout_backend(observed, backend)
        layouts[[as.character(seed)]] <- layout_matrix(observed)
        seed_times <- rbind(seed_times, data.frame(
            seed = seed, elapsed_sec = elapsed
        ))
    }
    saveRDS(list(
        layouts = layouts, rows = shared$rows,
        quality_rows = shared$quality_rows, labels = shared$labels,
        support_multiplier = support_multiplier,
        support_k = ceiling(perplexity * support_multiplier),
        perplexity = perplexity, backend = backend
    ), file.path(out, "layouts.rds"), compress = FALSE)
    for (seed in names(layouts)) {
        plot_layout_dots(
            layouts[[seed]], shared$labels,
            file.path(out, paste0("layout_seed", seed, ".png"))
        )
    }
    seed_times$dataset <- dataset
    seed_times$backend <- backend
    seed_times$support_multiplier <- support_multiplier
    write_csv_atomic(seed_times, file.path(out, "seed_runs.csv"))

    quality <- list()
    quality_x <- x[shared$quality_rows, , drop = FALSE]
    quality_labels <- if (is.null(shared$labels)) NULL else {
        shared$labels[shared$quality_rows]
    }
    for (seed in names(layouts)) {
        layout <- layouts[[seed]][shared$quality_rows, , drop = FALSE]
        row <- quality_metrics(
            quality_x, layout, quality_labels, perplexity,
            support_multiplier, k = 30L
        )
        row$dataset <- dataset
        row$backend <- backend
        row$seed <- as.integer(seed)
        row$support_multiplier <- support_multiplier
        row$quality_n <- nrow(layout)
        quality[[length(quality) + 1L]] <- row
    }
    write_csv_atomic(do.call(rbind, quality),
        file.path(out, "quality.csv")
    )
    write_status(
        paste0("support_", support_multiplier, "P"), dataset, backend,
        "success"
    )
}

quality_knn <- function(shared) {
    width <- min(
        ncol(shared$knn$indices), ceiling(shared$perplexity)
    )
    list(
        indices = shared$knn$indices[, seq_len(width), drop = FALSE],
        distances = shared$knn$distances[, seq_len(width), drop = FALSE]
    )
}

run_matched_quality_fit <- function(method, shared, seed) {
    knn <- quality_knn(shared)
    if (method == "tsne") {
        return(fastEmbedR::tsne_knn(
            knn$indices, knn$distances,
            perplexity = shared$perplexity,
            Y_init = shared$init, seed = seed,
            backend = backend, n.cores = threads,
            learning_rate = max(nrow(knn$indices) / 12, 200),
            early_exaggeration_iter = 250L,
            early_exaggeration = 12, n_iter = 750L,
            exaggeration = 1, initial_momentum = 0.8,
            final_momentum = 0.8, max_step_norm = 5,
            negative_gradient_method = "fft",
            record_costs = TRUE, auto_config = FALSE
        ))
    }
    fastEmbedR::umap_knn(
        knn$indices, knn$distances, seed = seed,
        backend = backend, n.cores = threads, graph_mode = "fuzzy"
    )
}

run_workflow_quality_fit <- function(method, x, shared, seed) {
    if (method == "tsne") {
        return(fastEmbedR::tsne(
            x, perplexity = shared$perplexity,
            Y_init = shared$init, seed = seed,
            backend = backend, n.cores = threads,
            keep_knn = TRUE,
            learning_rate = max(nrow(x) / 12, 200),
            early_exaggeration_iter = 250L,
            early_exaggeration = 12, n_iter = 750L,
            exaggeration = 1, initial_momentum = 0.8,
            final_momentum = 0.8, max_step_norm = 5,
            negative_gradient_method = "fft",
            record_costs = TRUE, auto_config = FALSE
        ))
    }
    fastEmbedR::umap(
        x, n_neighbors = ceiling(shared$perplexity), seed = seed,
        backend = backend, n.cores = threads, keep_knn = TRUE,
        graph_mode = "fuzzy"
    )
}

final_recorded_kl <- function(fit) {
    raw <- if (is.list(fit) && !is.null(fit$layout)) fit$layout else fit
    costs <- attr(raw, "itercosts", exact = TRUE)
    if (!length(costs)) return(NA_real_)
    as.numeric(tail(costs, 1L))
}

embedding_knn_parameter <- function(fit, name, default = NA_character_) {
    if (!is.list(fit) || is.null(fit$parameters)) return(default)
    value <- fit$parameters[[name]]
    if (is.null(value) || !length(value)) default else as.character(value[[1L]])
}

embedding_knn_recall <- function(fit, shared, boundary) {
    required <- c("recall_query_rows", "recall_exact")
    if (!all(required %in% names(shared))) {
        stop("Shared inputs lack the exact KNN recall reference.", call. = FALSE)
    }
    knn <- if (boundary == "full_workflow") fit$knn else shared$knn
    if (is.null(knn)) {
        stop("The embedding call did not retain its KNN result.", call. = FALSE)
    }
    transfer_sec <- system.time({
        host <- materialize_benchmark_knn(knn)
    })[["elapsed"]]
    query_rows <- shared$recall_query_rows
    approximate <- as.matrix(host$indices)[query_rows, , drop = FALSE]
    recall <- knn_recall_summary(
        approximate, shared$recall_exact$indices,
        ncol(shared$recall_exact$indices)
    )
    engine <- knn_scalar(
        knn, "engine", embedding_knn_parameter(fit, "nn_engine")
    )
    method <- knn_scalar(knn, "method", NA_character_)
    data.frame(
        observed_knn_recall_at_k = recall$mean,
        observed_knn_recall_median = recall$median,
        observed_knn_recall_q05 = recall$q05,
        observed_knn_recall_min = recall$minimum,
        observed_knn_recall_k = ncol(shared$recall_exact$indices),
        observed_knn_recall_query_n = length(query_rows),
        observed_nn_engine = engine,
        observed_nn_method = method,
        observed_nn_exact = knn_scalar(knn, "exact", FALSE),
        observed_nn_target_recall = knn_scalar(knn, "target_recall", 0.99),
        knn_materialization_sec_diagnostic = transfer_sec,
        stringsAsFactors = FALSE
    )
}

run_backend_quality <- function() {
    require_expected_version()
    assert_backend(backend)
    method <- arg_value("method", "tsne")
    if (!method %in% c("tsne", "umap")) stop("Unsupported method.")
    if (!quality_boundary %in% c("matched_knn", "full_workflow")) {
        stop("Unsupported quality boundary: ", quality_boundary)
    }
    shared <- readRDS(shared_input_path(dataset))
    loaded <- load_dataset(data_root, dataset)
    if (nrow(loaded$data) != shared$source_n ||
            ncol(loaded$data) != shared$source_p) {
        stop("Dataset dimensions differ from the shared-input manifest.")
    }
    selected <- subset_dataset(loaded, shared$rows)
    x <- as_float_matrix(selected$data)
    fit_time <- system.time({
        fit <- if (quality_boundary == "matched_knn") {
            run_matched_quality_fit(method, shared, run_seed)
        } else {
            run_workflow_quality_fit(method, x, shared, run_seed)
        }
    })[["elapsed"]]
    assert_layout_backend(fit, backend)
    recall <- embedding_knn_recall(fit, shared, quality_boundary)
    layout <- layout_matrix(fit)
    quality_rows <- shared$quality_rows
    labels <- if (is.null(shared$labels)) NULL else {
        shared$labels[quality_rows]
    }
    metrics <- quality_metrics(
        x[quality_rows, , drop = FALSE],
        layout[quality_rows, , drop = FALSE], labels,
        shared$perplexity, support_multiplier = 1, k = 30L
    )
    if (method != "tsne") metrics$sampled_kl <- NA_real_
    result <- cbind(data.frame(
        dataset = dataset, method = method, backend = backend,
        boundary = quality_boundary, seed = run_seed,
        n = nrow(x), p = ncol(x), quality_n = length(quality_rows),
        perplexity_or_neighbors = shared$perplexity,
        nn_engine = embedding_knn_parameter(fit, "nn_engine", "supplied"),
        nn_backend = embedding_knn_parameter(fit, "nn_backend", "supplied"),
        nn_target_recall = if (quality_boundary == "full_workflow") {
            0.99
        } else {
            NA_real_
        },
        elapsed_sec_diagnostic = fit_time,
        timing_eligible = FALSE,
        final_recorded_kl = if (method == "tsne") {
            final_recorded_kl(fit)
        } else {
            NA_real_
        },
        stringsAsFactors = FALSE
    ), recall, metrics)
    config <- paste(
        quality_boundary, method, paste0("seed", run_seed), sep = "_"
    )
    out <- file.path(
        output_root, "backend_quality", dataset, backend, config
    )
    dir.create(out, recursive = TRUE, showWarnings = FALSE)
    write_csv_atomic(result, file.path(out, "backend_quality.csv"))
    write_csv_atomic(data.frame(
        quality_position = quality_rows,
        source_row = shared$rows[quality_rows],
        as.data.frame(layout[quality_rows, , drop = FALSE])
    ), file.path(out, "quality_layout.csv"))
    plot_layout_dots(
        layout, shared$labels, file.path(out, "layout.png")
    )
    write_csv_atomic(status_row(
        "backend_quality", dataset, backend, "success",
        method = method, boundary = quality_boundary,
        seed = run_seed
    ), file.path(out, "status.csv"))
}

reference_query_metrics <- function(reference_x, query_x,
                                    reference_layout, query_layout,
                                    reference_labels, query_labels) {
    high <- exact_cross_knn(reference_x, query_x, k = 30L)
    low <- exact_cross_knn(reference_layout, query_layout, k = 30L)
    data.frame(
        query_reference_preserve_at_30 = neighbor_preservation(
            high$indices, low$indices, 30L
        ),
        query_label_knn_accuracy = query_label_accuracy(
            low$indices, reference_labels, query_labels, 30L
        ),
        stringsAsFactors = FALSE
    )
}

run_transform <- function() {
    require_expected_version()
    assert_backend(backend)
    shared <- readRDS(shared_input_path(dataset))
    loaded <- load_dataset(data_root, dataset)
    if (nrow(loaded$data) != shared$source_n ||
            ncol(loaded$data) != shared$source_p) {
        stop("Dataset dimensions differ from the shared-input manifest.")
    }
    selected <- subset_dataset(loaded, shared$rows)
    x <- as_float_matrix(selected$data)
    labels <- selected$labels
    method <- arg_value("method", "tsne")
    out <- dataset_output_dir(paste0("transform_", method), dataset, backend)
    dir.create(out, recursive = TRUE, showWarnings = FALSE)
    rows <- list()
    saved <- list()
    for (seed in seeds) {
        train_rows <- stratified_rows(labels, nrow(x), floor(0.8 * nrow(x)), seed)
        query_rows <- setdiff(seq_len(nrow(x)), train_rows)
        train <- x[train_rows, , drop = FALSE]
        query <- x[query_rows, , drop = FALSE]
        train_labels <- if (is.null(labels)) NULL else labels[train_rows]
        query_labels <- if (is.null(labels)) NULL else labels[query_rows]
        selection <- seq_len(nrow(train))
        fit_time <- system.time({
            model <- fastEmbedR::fit_landmark_model(
                train, selection, method = method,
                n_neighbors = if (method == "umap") 30L else NULL,
                perplexity = if (method == "tsne") perplexity else NULL,
                metric = "euclidean", seed = seed, backend = backend,
                n.cores = threads, graph_mode = "fuzzy"
            )
        })[["elapsed"]]
        reference_before <- layout_matrix(model$fit)
        transform_time <- system.time({
            projected <- fastEmbedR::project_landmark_model(
                model, query, n.cores = threads,
                transform_k = 30L, refinement_epochs = 50L,
                transform_perplexity = 5,
                transform_iter = 250L
            )
        })[["elapsed"]]
        projected_layout <- layout_matrix(projected)
        reference_after <- layout_matrix(model$fit)
        displacement <- max(abs(reference_after - reference_before))
        joint_time <- system.time({
            joint <- if (method == "tsne") {
                fastEmbedR::tsne(
                    x, perplexity = perplexity, seed = seed,
                    backend = backend, n.cores = threads,
                    metric = "euclidean"
                )
            } else {
                fastEmbedR::umap(
                    x, n_neighbors = 30L, seed = seed,
                    backend = backend, n.cores = threads,
                    metric = "euclidean", graph_mode = "fuzzy"
                )
            }
        })[["elapsed"]]
        joint_layout <- layout_matrix(joint)
        assert_layout_backend(joint, backend)
        evaluation_sizes <- if (ncol(x) > 5000L) {
            c(reference = 500L, query = 250L)
        } else if (ncol(x) > 1000L) {
            c(reference = 1000L, query = 500L)
        } else {
            c(reference = 5000L, query = 2000L)
        }
        reference_sample <- stratified_rows(
            train_labels, nrow(train),
            min(evaluation_sizes[["reference"]], nrow(train)), seed + 100L
        )
        query_sample <- stratified_rows(
            query_labels, nrow(query),
            min(evaluation_sizes[["query"]], nrow(query)), seed + 200L
        )
        metric <- reference_query_metrics(
            train[reference_sample, , drop = FALSE],
            query[query_sample, , drop = FALSE],
            reference_before[reference_sample, , drop = FALSE],
            projected_layout[query_sample, , drop = FALSE],
            if (is.null(train_labels)) NULL else train_labels[reference_sample],
            if (is.null(query_labels)) NULL else query_labels[query_sample]
        )
        joint_metric <- reference_query_metrics(
            train[reference_sample, , drop = FALSE],
            query[query_sample, , drop = FALSE],
            joint_layout[train_rows[reference_sample], , drop = FALSE],
            joint_layout[query_rows[query_sample], , drop = FALSE],
            if (is.null(train_labels)) NULL else train_labels[reference_sample],
            if (is.null(query_labels)) NULL else query_labels[query_sample]
        )
        rows[[length(rows) + 1L]] <- data.frame(
            dataset = dataset, method = method, backend = backend,
            projection_scope = "held_out_query",
            graph_mode = if (method == "umap") "fuzzy" else NA_character_,
            affinity_support = if (method == "tsne") {
                "compact_k_equals_perplexity"
            } else {
                NA_character_
            },
            seed = seed, n_train = nrow(train), n_query = nrow(query),
            fit_sec = fit_time, transform_sec = transform_time,
            joint_sec = joint_time,
            reference_max_displacement = displacement,
            query_reference_preserve_at_30 =
                metric$query_reference_preserve_at_30,
            query_label_knn_accuracy = metric$query_label_knn_accuracy,
            joint_query_reference_preserve_at_30 =
                joint_metric$query_reference_preserve_at_30,
            joint_query_label_knn_accuracy =
                joint_metric$query_label_knn_accuracy,
            projected_joint_procrustes = procrustes_correlation(
                joint_layout[query_rows[query_sample], , drop = FALSE],
                projected_layout[query_sample, , drop = FALSE]
            ),
            stringsAsFactors = FALSE
        )
        saved[[as.character(seed)]] <- list(
            train_rows = train_rows, query_rows = query_rows,
            reference_evaluation_rows = train_rows[reference_sample],
            query_evaluation_rows = query_rows[query_sample],
            reference_layout = reference_before,
            query_layout = projected_layout,
            joint_layout = joint_layout
        )
        write_csv_atomic(data.frame(
            benchmark_row = seq_len(nrow(x)), source_row = shared$rows,
            partition = ifelse(
                seq_len(nrow(x)) %in% train_rows, "reference", "query"
            ),
            evaluation_sample = seq_len(nrow(x)) %in% c(
                train_rows[reference_sample], query_rows[query_sample]
            ),
            stringsAsFactors = FALSE
        ), file.path(out, paste0("rows_seed", seed, ".csv")))
        plot_transformed_queries(
            reference_before, projected_layout, query_labels,
            file.path(out, paste0("held_out_seed", seed, ".png"))
        )
    }
    write_csv_atomic(do.call(rbind, rows), file.path(out, "transform.csv"))
    saveRDS(saved, file.path(out, "layouts.rds"), compress = FALSE)
    write_status(paste0("transform_", method), dataset, backend, "success")
}

run_full_embedding <- function(method, x, seed) {
    if (identical(method, "tsne")) {
        return(fastEmbedR::tsne(
            x, perplexity = perplexity, seed = seed,
            backend = backend, n.cores = threads,
            metric = "euclidean"
        ))
    }
    fastEmbedR::umap(
        x, n_neighbors = 30L, seed = seed,
        backend = backend, n.cores = threads,
        metric = "euclidean", graph_mode = "fuzzy"
    )
}

fit_reconstruction_model <- function(method, x, selection, seed) {
    fastEmbedR::fit_landmark_model(
        x, selection, method = method,
        n_neighbors = if (method == "umap") 30L else NULL,
        perplexity = if (method == "tsne") perplexity else NULL,
        metric = "euclidean", seed = seed, backend = backend,
        n.cores = threads, graph_mode = "fuzzy"
    )
}

project_reconstruction_model <- function(model, x) {
    fastEmbedR::project_landmark_model(
        model, x, n.cores = threads, transform_k = 30L,
        refinement_epochs = 50L, transform_perplexity = 5,
        transform_iter = 250L
    )
}

landmark_evaluation_sizes <- function(x) {
    if (ncol(x) > 5000L) return(c(reference = 500L, query = 250L))
    if (ncol(x) > 1000L) return(c(reference = 1000L, query = 500L))
    c(reference = 5000L, query = 2000L)
}

prefix_metric_names <- function(metrics, prefix) {
    names(metrics) <- paste0(prefix, names(metrics))
    metrics
}

landmark_reconstruction_metrics <- function(
    x, labels, shared, selection, layout, full_layout, seed
) {
    quality_rows <- shared$quality_rows
    quality_labels <- if (is.null(labels)) NULL else labels[quality_rows]
    landmark_quality <- quality_metrics(
        x[quality_rows, , drop = FALSE],
        layout[quality_rows, , drop = FALSE], quality_labels,
        shared$perplexity, support_multiplier = 1, k = 30L
    )
    full_quality <- quality_metrics(
        x[quality_rows, , drop = FALSE],
        full_layout[quality_rows, , drop = FALSE], quality_labels,
        shared$perplexity, support_multiplier = 1, k = 30L
    )
    list(
        landmark = prefix_metric_names(landmark_quality, "landmark_"),
        full = prefix_metric_names(full_quality, "full_"),
        quality_rows = quality_rows,
        procrustes = procrustes_correlation(
            full_layout[quality_rows, , drop = FALSE],
            layout[quality_rows, , drop = FALSE]
        ),
        neighbors = layout_neighbor_agreement(
            full_layout[quality_rows, , drop = FALSE],
            layout[quality_rows, , drop = FALSE], 30L
        )
    )
}

landmark_query_metrics <- function(
    x, labels, selection, layout, full_layout, seed
) {
    sizes <- landmark_evaluation_sizes(x)
    reference_labels <- if (is.null(labels)) NULL else {
        labels[selection$indices]
    }
    query_labels <- if (is.null(labels)) NULL else {
        labels[selection$query_indices]
    }
    reference_sample <- stratified_rows(
        reference_labels, length(selection$indices),
        min(sizes[["reference"]], length(selection$indices)), seed + 100L
    )
    query_sample <- stratified_rows(
        query_labels, length(selection$query_indices),
        min(sizes[["query"]], length(selection$query_indices)), seed + 200L
    )
    reference_rows <- selection$indices[reference_sample]
    query_rows <- selection$query_indices[query_sample]
    projected <- reference_query_metrics(
        x[reference_rows, , drop = FALSE], x[query_rows, , drop = FALSE],
        layout[reference_rows, , drop = FALSE],
        layout[query_rows, , drop = FALSE],
        if (is.null(labels)) NULL else labels[reference_rows],
        if (is.null(labels)) NULL else labels[query_rows]
    )
    joint <- reference_query_metrics(
        x[reference_rows, , drop = FALSE], x[query_rows, , drop = FALSE],
        full_layout[reference_rows, , drop = FALSE],
        full_layout[query_rows, , drop = FALSE],
        if (is.null(labels)) NULL else labels[reference_rows],
        if (is.null(labels)) NULL else labels[query_rows]
    )
    list(
        projected = prefix_metric_names(projected, "landmark_"),
        joint = prefix_metric_names(joint, "full_"),
        reference_rows = reference_rows, query_rows = query_rows
    )
}

run_landmark_reconstruction <- function() {
    require_expected_version()
    assert_backend(backend)
    if (!is.finite(landmark_fraction) || landmark_fraction <= 0 ||
            landmark_fraction >= 1) {
        stop("`landmark-fraction` must be strictly between zero and one.")
    }
    method <- arg_value("method", "tsne")
    if (!method %in% c("tsne", "umap")) stop("Unsupported method.")
    shared <- readRDS(shared_input_path(dataset))
    loaded <- load_dataset(data_root, dataset)
    selected <- subset_dataset(loaded, shared$rows)
    x <- as_float_matrix(selected$data)
    labels <- selected$labels
    fraction_label <- sprintf("fraction_%02d", round(100 * landmark_fraction))
    out <- file.path(
        dataset_output_dir("landmark_reconstruction", dataset, backend),
        method, fraction_label
    )
    dir.create(out, recursive = TRUE, showWarnings = FALSE)
    rows <- list()
    for (seed in seeds) {
        selection <- fastEmbedR::select_landmarks(
            x, landmarks = landmark_fraction, seed = seed,
            n.cores = threads
        )
        fit_sec <- system.time({
            model <- fit_reconstruction_model(method, x, selection, seed)
        })[["elapsed"]]
        reference_before <- layout_matrix(model$fit)
        transform_sec <- system.time({
            reconstructed <- project_reconstruction_model(model, x)
        })[["elapsed"]]
        layout <- layout_matrix(reconstructed)
        assert_layout_backend(reconstructed, backend)
        reference_after <- layout_matrix(model$fit)
        reference_displacement <- max(abs(
            reference_after - reference_before
        ))
        full_sec <- system.time({
            full_fit <- run_full_embedding(method, x, seed)
        })[["elapsed"]]
        assert_layout_backend(full_fit, backend)
        full_layout <- layout_matrix(full_fit)
        quality <- landmark_reconstruction_metrics(
            x, labels, shared, selection, layout, full_layout, seed
        )
        query <- landmark_query_metrics(
            x, labels, selection, layout, full_layout, seed
        )
        if (method != "tsne") {
            quality$landmark$landmark_sampled_kl <- NA_real_
            quality$full$full_sampled_kl <- NA_real_
        }
        rows[[length(rows) + 1L]] <- cbind(data.frame(
            dataset = dataset, method = method, backend = backend,
            graph_mode = if (method == "umap") "fuzzy" else NA_character_,
            affinity_support = if (method == "tsne") {
                "compact_k_equals_perplexity"
            } else {
                NA_character_
            },
            seed = seed, n = nrow(x), p = ncol(x),
            n_landmarks = length(selection$indices),
            n_projected = length(selection$query_indices),
            landmark_fraction = length(selection$indices) / nrow(x),
            reference_fit_sec = fit_sec,
            reconstruction_sec = transform_sec,
            landmark_total_sec = fit_sec + transform_sec,
            full_embedding_sec = full_sec,
            reference_max_displacement = reference_displacement,
            projected_full_procrustes = quality$procrustes,
            projected_full_neighbor_agreement_at_30 = quality$neighbors,
            stringsAsFactors = FALSE
        ), quality$landmark, quality$full, query$projected, query$joint)
        write_csv_atomic(data.frame(
            benchmark_row = seq_len(nrow(x)), source_row = shared$rows,
            is_landmark = seq_len(nrow(x)) %in% selection$indices,
            stringsAsFactors = FALSE
        ), file.path(out, paste0("rows_seed", seed, ".csv")))
        write_csv_atomic(data.frame(
            benchmark_row = quality$quality_rows,
            source_row = shared$rows[quality$quality_rows],
            landmark_x = layout[quality$quality_rows, 1L],
            landmark_y = layout[quality$quality_rows, 2L],
            full_x = full_layout[quality$quality_rows, 1L],
            full_y = full_layout[quality$quality_rows, 2L],
            stringsAsFactors = FALSE
        ), file.path(out, paste0("quality_layout_seed", seed, ".csv")))
        plot_transformed_queries(
            layout[selection$indices, , drop = FALSE],
            layout[selection$query_indices, , drop = FALSE],
            if (is.null(labels)) NULL else labels[selection$query_indices],
            file.path(out, paste0("reconstruction_seed", seed, ".png"))
        )
    }
    write_csv_atomic(
        do.call(rbind, rows), file.path(out, "landmark_reconstruction.csv")
    )
    write_csv_atomic(status_row(
        "landmark_reconstruction", dataset, backend, "success",
        method = method, graph_mode = if (method == "umap") {
            "fuzzy"
        } else {
            NA_character_
        }, landmark_fraction = landmark_fraction
    ), file.path(out, "status.csv"))
}

run_scaling <- function() {
    if (backend != "cpu") stop("Scaling mode is CPU-only.")
    loaded <- load_dataset(data_root, dataset)
    scaling_cap <- switch(dataset,
        COIL20 = nrow(loaded$data),
        MNIST = nrow(loaded$data),
        flow18 = nrow(loaded$data),
        imagenet = min(100000L, nrow(loaded$data)),
        min(max_n, nrow(loaded$data))
    )
    selected_rows <- stratified_rows(
        loaded$labels, nrow(loaded$data), scaling_cap, 1701L
    )
    x <- as_float_matrix(loaded$data[selected_rows, , drop = FALSE])
    warm <- x[seq_len(min(2000L, nrow(x))), , drop = FALSE]
    invisible(fastEmbedR::precompute_knn(
        warm, k = min(30L, nrow(warm) - 1L), backend = "cpu",
        n.cores = threads
    ))
    reps <- if (nrow(x) > 100000L) 3L else 5L
    rows <- list()
    for (replicate in seq_len(reps)) {
        knn_sec <- system.time({
            knn <- fastEmbedR::precompute_knn(
                x, k = 30L, backend = "cpu", n.cores = threads
            )
        })[["elapsed"]]
        pca_sec <- system.time({
            pca_fit <- fastEmbedR::pca(
                x, ncomp = 2L, backend = "cpu", n.cores = threads,
                seed = 4L, tsne_init = TRUE
            )
        })[["elapsed"]]
        tsne_sec <- system.time({
            fastEmbedR::tsne_knn(
                knn, perplexity = 30, Y_init = pca_fit$tsne_init,
                seed = 4L, backend = "cpu", n.cores = threads
            )
        })[["elapsed"]]
        umap_sec <- system.time({
            fastEmbedR::umap_knn(
                knn, seed = 4L, backend = "cpu", n.cores = threads,
                graph_mode = "fuzzy"
            )
        })[["elapsed"]]
        rows[[replicate]] <- data.frame(
            dataset = dataset, n = nrow(x), p = ncol(x),
            threads = threads, replicate = replicate,
            knn_sec = knn_sec, pca_sec = pca_sec,
            tsne_embedding_sec = tsne_sec,
            umap_embedding_sec = umap_sec,
            total_tsne_sec = knn_sec + pca_sec + tsne_sec,
            total_umap_sec = knn_sec + umap_sec,
            stringsAsFactors = FALSE
        )
    }
    out <- dataset_output_dir("cpu_scaling", dataset, paste0(threads, "t"))
    write_csv_atomic(do.call(rbind, rows), file.path(out, "scaling.csv"))
    write_status("cpu_scaling", dataset, paste0(threads, "t"), "success")
}

run_pca_validation <- function() {
    require_expected_version()
    assert_backend(backend)
    loaded <- load_dataset(data_root, dataset)
    cap <- min(max_n, nrow(loaded$data))
    rows <- stratified_rows(loaded$labels, nrow(loaded$data), cap, 1701L)
    x <- as_float_matrix(loaded$data[rows, , drop = FALSE])
    requested_rank <- as_int(arg_value("rank"), 2L)
    rank <- valid_randomized_pca_rank(x, requested_rank)
    warm <- x[seq_len(min(2000L, nrow(x))), , drop = FALSE]
    invisible(fastEmbedR::pca(
        warm, ncomp = min(rank, nrow(warm) - 1L), backend = backend,
        n.cores = threads, seed = 4L
    ))
    reps <- if (nrow(x) > 100000L) 3L else 5L
    timings <- list()
    fit <- NULL
    for (replicate in seq_len(reps)) {
        elapsed <- system.time({
            fit <- fastEmbedR::pca(
                x, ncomp = rank, backend = backend,
                n.cores = threads, seed = 4L
            )
        })[["elapsed"]]
        if (!grepl(backend, fit$backend, fixed = TRUE)) {
            stop("PCA backend mismatch: requested ", backend,
                ", observed ", fit$backend, call. = FALSE
            )
        }
        timings[[replicate]] <- data.frame(
            dataset = dataset, backend = backend, threads = threads,
            requested_rank = requested_rank, rank = rank,
            replicate = replicate, elapsed_sec = elapsed,
            method = "fastEmbedR_rsvd", stringsAsFactors = FALSE
        )
    }
    if (backend == "cpu" && requireNamespace("irlba", quietly = TRUE)) {
        xd <- as_double_matrix(x)
        for (replicate in seq_len(reps)) {
            elapsed <- system.time({
                irlba::prcomp_irlba(
                    xd, n = rank, center = TRUE, scale. = FALSE
                )
            })[["elapsed"]]
            timings[[length(timings) + 1L]] <- data.frame(
                dataset = dataset, backend = "cpu", threads = threads,
                requested_rank = requested_rank, rank = rank,
                replicate = replicate, elapsed_sec = elapsed,
                method = "irlba_performance_comparator",
                stringsAsFactors = FALSE
            )
        }
    }
    out <- dataset_output_dir(
        "pca", dataset,
        paste0(backend, "_", threads, "t_rank", requested_rank)
    )
    write_csv_atomic(do.call(rbind, timings), file.path(out, "timing.csv"))
    score <- layout_matrix(fit$scores)
    saveRDS(list(
        score_sample = score[seq_len(min(5000L, nrow(score))), , drop = FALSE],
        loadings = fit$loadings,
        singular_values = fit$singular_values,
        backend = backend, threads = threads, rank = rank, rows = rows
    ), file.path(out, "pca_fit_summary.rds"), compress = FALSE)
    status_backend <- paste0(
        backend, "_", threads, "t_rank", requested_rank
    )
    write_status("pca", dataset, status_backend, "success",
        threads = threads, rank = rank
    )
}

valid_randomized_pca_rank <- function(x, requested_rank) {
    rank <- min(
        as.integer(requested_rank),
        nrow(x) - 1L,
        ncol(x) - 1L
    )
    if (!is.finite(rank) || rank < 1L) {
        stop(
            "PCA requires at least two observations and two variables.",
            call. = FALSE
        )
    }
    rank
}

pca_accuracy_sample_size <- function(n, p) {
    cap <- if (p > 5000L) 256L else if (p > 1000L) 512L else 2000L
    min(as.integer(n), cap)
}

dense_pca_reference <- function(x, rank) {
    x <- as_double_matrix(x)
    center <- colMeans(x)
    centered <- sweep(x, 2L, center, "-")
    rank <- min(as.integer(rank), nrow(centered) - 1L, ncol(centered))
    if (ncol(centered) <= nrow(centered)) {
        eig <- eigen(crossprod(centered), symmetric = TRUE)
        values <- pmax(eig$values[seq_len(rank)], 0)
        loadings <- eig$vectors[, seq_len(rank), drop = FALSE]
        scores <- centered %*% loadings
    } else {
        eig <- eigen(tcrossprod(centered), symmetric = TRUE)
        values <- pmax(eig$values[seq_len(rank)], 0)
        singular <- sqrt(values)
        left <- eig$vectors[, seq_len(rank), drop = FALSE]
        loadings <- crossprod(centered, left)
        safe <- ifelse(singular > sqrt(.Machine$double.eps), singular, 1)
        loadings <- sweep(loadings, 2L, safe, "/")
        scores <- sweep(left, 2L, singular, "*")
    }
    singular <- sqrt(values)
    total_ss <- sum(centered * centered)
    reconstruction <- scores %*% t(loadings)
    list(
        scores = scores, loadings = loadings,
        singular_values = singular, center = center,
        captured_variance = sum(singular * singular) / total_ss,
        reconstruction_relative_error = sqrt(
            sum((centered - reconstruction)^2) / total_ss
        )
    )
}

pca_relative_l2 <- function(reference, candidate) {
    reference <- as.numeric(reference)
    candidate <- as.numeric(candidate)
    keep <- seq_len(min(length(reference), length(candidate)))
    denominator <- sqrt(sum(reference[keep]^2))
    if (!is.finite(denominator) || denominator == 0) return(NA_real_)
    sqrt(sum((candidate[keep] - reference[keep])^2)) / denominator
}

pca_reconstruction_error <- function(x, center, scores, loadings) {
    x <- as_double_matrix(x)
    centered <- sweep(x, 2L, as.numeric(center), "-")
    reconstruction <- as_double_matrix(scores) %*% t(
        as_double_matrix(loadings)
    )
    sqrt(sum((centered - reconstruction)^2) / sum(centered^2))
}

pca_accuracy_row <- function(method, fit, reference, x, elapsed) {
    scores <- as_double_matrix(fit$scores)
    loadings <- as_double_matrix(fit$loadings)
    singular <- as.numeric(fit$singular_values)
    total_ss <- sum(sweep(as_double_matrix(x), 2L, reference$center, "-")^2)
    captured <- sum(singular^2) / total_ss
    score_angles <- principal_angle_summary(reference$scores, scores)
    loading_angles <- principal_angle_summary(
        reference$loadings, loadings
    )
    data.frame(
        method = method, diagnostic_elapsed_sec = elapsed,
        score_procrustes = procrustes_correlation(reference$scores, scores),
        score_max_principal_angle_rad =
            score_angles$max_principal_angle_rad,
        score_mean_principal_angle_rad =
            score_angles$mean_principal_angle_rad,
        score_subspace_cosine_mean = score_angles$subspace_cosine_mean,
        loading_max_principal_angle_rad =
            loading_angles$max_principal_angle_rad,
        loading_mean_principal_angle_rad =
            loading_angles$mean_principal_angle_rad,
        loading_subspace_cosine_mean =
            loading_angles$subspace_cosine_mean,
        singular_value_relative_l2 = pca_relative_l2(
            reference$singular_values, singular
        ),
        captured_variance = captured,
        captured_variance_abs_difference = abs(
            captured - reference$captured_variance
        ),
        reconstruction_relative_error = pca_reconstruction_error(
            x, reference$center, scores, loadings
        ),
        stringsAsFactors = FALSE
    )
}

run_irlba_accuracy_fit <- function(x, rank) {
    if (!requireNamespace("irlba", quietly = TRUE)) return(NULL)
    x <- as_double_matrix(x)
    elapsed <- system.time({
        fit <- irlba::prcomp_irlba(
            x, n = rank, center = TRUE, scale. = FALSE
        )
    })[["elapsed"]]
    list(
        fit = list(
            scores = fit$x, loadings = fit$rotation,
            singular_values = fit$sdev * sqrt(nrow(x) - 1L)
        ),
        elapsed = elapsed
    )
}

run_pca_accuracy <- function() {
    require_expected_version()
    assert_backend(backend)
    loaded <- load_dataset(data_root, dataset)
    sample_n <- pca_accuracy_sample_size(
        nrow(loaded$data), ncol(loaded$data)
    )
    rows <- stratified_rows(loaded$labels, nrow(loaded$data), sample_n, 1701L)
    x <- as_float_matrix(loaded$data[rows, , drop = FALSE])
    requested_rank <- as_int(arg_value("rank"), 2L)
    rank <- valid_randomized_pca_rank(x, requested_rank)
    reference_sec <- system.time({
        reference <- dense_pca_reference(x, rank)
    })[["elapsed"]]
    elapsed <- system.time({
        fit <- fastEmbedR::pca(
            x, ncomp = rank, backend = backend,
            n.cores = threads, seed = 4L
        )
    })[["elapsed"]]
    if (!grepl(backend, fit$backend, fixed = TRUE)) {
        stop("PCA backend mismatch: requested ", backend,
            ", observed ", fit$backend, call. = FALSE
        )
    }
    accuracy <- pca_accuracy_row(
        "fastEmbedR", fit, reference, x, elapsed
    )
    irlba_fit <- run_irlba_accuracy_fit(x, rank)
    if (!is.null(irlba_fit)) {
        accuracy <- rbind(
            accuracy,
            pca_accuracy_row(
                "irlba", irlba_fit$fit, reference, x,
                irlba_fit$elapsed
            )
        )
    }
    accuracy <- cbind(data.frame(
        dataset = dataset, backend = backend, threads = threads,
        n = nrow(x), p = ncol(x), requested_rank = requested_rank,
        rank = rank, seed = 4L,
        reference = "dense_centered_svd",
        reference_elapsed_sec = reference_sec,
        stringsAsFactors = FALSE
    ), accuracy)
    out <- dataset_output_dir(
        "pca_accuracy", dataset,
        paste0(backend, "_", threads, "t_rank", requested_rank)
    )
    write_csv_atomic(accuracy, file.path(out, "pca_accuracy.csv"))
    write_csv_atomic(data.frame(
        sample_position = seq_along(rows), source_row = rows
    ), file.path(out, "row_identifiers.csv"))
    saveRDS(list(
        rows = rows, rank = rank, backend = backend,
        fastembedr = list(
            scores = as_double_matrix(fit$scores),
            loadings = as_double_matrix(fit$loadings),
            singular_values = as.numeric(fit$singular_values)
        ),
        reference = reference,
        irlba = if (is.null(irlba_fit)) NULL else irlba_fit$fit
    ), file.path(out, "pca_accuracy_summary.rds"), compress = FALSE)
    status_backend <- paste0(
        backend, "_", threads, "t_rank", requested_rank
    )
    write_status("pca_accuracy", dataset, status_backend, "success",
        threads = threads, rank = rank, sample_n = nrow(x)
    )
}

knn_recall_sample_size <- function(n, p) {
    cap <- if (p > 5000L) 32L else if (p > 1000L) 64L else 128L
    min(as.integer(n), cap)
}

knn_scalar <- function(x, name, default = NA) {
    value <- x[[name]] %||% attr(x, name, exact = TRUE)
    if (is.null(value) || !length(value)) return(default)
    value[[1L]]
}

materialize_benchmark_knn <- function(knn) {
    is_gpu <- inherits(knn, "fastEmbedR_gpu_knn") ||
        identical(knn_scalar(knn, "result_residency", "host"), "cuda")
    if (!is_gpu) return(knn)
    converter <- getFromNamespace(
        "fastembedr_gpu_knn_to_host", "fastEmbedR"
    )
    converter(knn)
}

knn_recall_summary <- function(approximate, exact, k) {
    k <- min(as.integer(k), ncol(approximate), ncol(exact))
    per_query <- vapply(seq_len(nrow(exact)), function(i) {
        length(intersect(approximate[i, seq_len(k)], exact[i, seq_len(k)])) / k
    }, numeric(1L))
    list(
        per_query = per_query,
        mean = mean(per_query), median = stats::median(per_query),
        q05 = unname(stats::quantile(per_query, 0.05)),
        minimum = min(per_query)
    )
}

run_observed_knn_accuracy <- function() {
    require_expected_version()
    assert_backend(backend)
    loaded <- load_dataset(data_root, dataset)
    rows <- stratified_rows(
        loaded$labels, nrow(loaded$data), min(max_n, nrow(loaded$data)), 1701L
    )
    selected <- subset_dataset(loaded, rows)
    x <- as_float_matrix(selected$data)
    k <- min(ceiling(perplexity), nrow(x) - 1L)
    query_n <- knn_recall_sample_size(nrow(x), ncol(x))
    query_rows <- stratified_rows(selected$labels, nrow(x), query_n, 31337L)
    elapsed <- system.time({
        knn <- fastEmbedR::precompute_knn(
            x, k = k, metric = "euclidean", backend = backend,
            n.cores = threads
        )
    })[["elapsed"]]
    if (!identical(knn_scalar(knn, "execution_backend"), backend)) {
        stop("KNN backend mismatch; no fallback is accepted.", call. = FALSE)
    }
    transfer_sec <- system.time({
        host <- materialize_benchmark_knn(knn)
    })[["elapsed"]]
    reference_sec <- system.time({
        exact <- exact_sampled_self_knn(x, query_rows, k)
    })[["elapsed"]]
    approximate <- as.matrix(host$indices)[query_rows, , drop = FALSE]
    recall <- knn_recall_summary(approximate, exact$indices, k)
    write_observed_knn_accuracy(
        knn, recall, rows, query_rows, elapsed, transfer_sec, reference_sec,
        nrow(x), ncol(x), k
    )
}

write_observed_knn_accuracy <- function(knn, recall, source_rows, query_rows,
                                        elapsed, transfer_sec, reference_sec,
                                        n, p, k) {
    out <- dataset_output_dir("knn_observed", dataset, backend)
    result <- data.frame(
        dataset = dataset, backend = backend, n = n, p = p, k = k,
        metric = "euclidean", query_n = length(query_rows),
        source_selection_seed = 1701L, query_selection_seed = 31337L,
        engine = knn_scalar(knn, "engine"),
        nn_method = knn_scalar(knn, "method"),
        exact_search = knn_scalar(knn, "exact", FALSE),
        target_recall = knn_scalar(knn, "target_recall", 0.99),
        observed_recall_at_k = recall$mean,
        observed_recall_median = recall$median,
        observed_recall_q05 = recall$q05,
        observed_recall_min = recall$minimum,
        reported_pilot_recall = knn_scalar(knn, "pilot_recall", NA_real_),
        target_met_reported = knn_scalar(knn, "target_met", NA),
        nlist = knn_scalar(knn, "nlist", NA_integer_),
        nprobe = knn_scalar(knn, "nprobe", NA_integer_),
        hnsw_M = knn_scalar(knn, "M", NA_integer_),
        hnsw_ef_construction = knn_scalar(knn, "efConstruction", NA_integer_),
        hnsw_ef_search = knn_scalar(knn, "efSearch", NA_integer_),
        search_elapsed_sec_diagnostic = elapsed,
        host_transfer_sec_diagnostic = transfer_sec,
        exact_reference_sec_diagnostic = reference_sec,
        timing_eligible = FALSE, stringsAsFactors = FALSE
    )
    write_csv_atomic(result, file.path(out, "observed_recall.csv"))
    write_csv_atomic(data.frame(
        query_position = seq_along(query_rows),
        benchmark_row = query_rows, source_row = source_rows[query_rows],
        recall_at_k = recall$per_query, stringsAsFactors = FALSE
    ), file.path(out, "query_recall.csv"))
    write_status("knn_observed", dataset, backend, "success",
        engine = result$engine, observed_recall_at_k = recall$mean
    )
}

run_knn_sensitivity <- function() {
    require_expected_version()
    assert_backend(backend)
    loaded <- load_dataset(data_root, dataset)
    recall_n <- if (ncol(loaded$data) > 5000L) {
        500L
    } else if (ncol(loaded$data) > 1000L) {
        1000L
    } else {
        5000L
    }
    rows <- stratified_rows(
        loaded$labels, nrow(loaded$data), min(recall_n, nrow(loaded$data)),
        1701L
    )
    x <- as_float_matrix(loaded$data[rows, , drop = FALSE])
    labels <- if (is.null(loaded$labels)) NULL else loaded$labels[rows]
    exact <- exact_knn_from_distances(exact_distance_matrix(x), 30L)
    init <- fastEmbedR::pca(
        x, ncomp = 2L, backend = "cpu", n.cores = threads,
        seed = 4L, tsne_init = TRUE
    )$tsne_init
    quality_rows <- stratified_rows(
        labels, nrow(x), min(2000L, nrow(x)), 2027L
    )
    worker <- getFromNamespace("fastembedr_nn_without_self", "fastEmbedR")
    results <- list()
    for (target in c(0.90, 0.95, 0.99)) {
        method <- if (backend == "cuda") "ivf" else "hnsw"
        elapsed <- system.time({
            observed <- worker(
                x, k = 30L, backend = backend, method = method,
                metric = "euclidean", output = "double",
                n_threads = threads, tuning = "auto",
                target_recall = target, keep_gpu = FALSE
            )
        })[["elapsed"]]
        recall <- mean(vapply(seq_len(nrow(x)), function(i) {
            length(intersect(exact$indices[i, ], observed$indices[i, ])) / 30
        }, numeric(1L)))
        tsne_sec <- system.time({
            tsne_layout <- fastEmbedR::tsne_knn(
                observed, perplexity = 30, Y_init = init,
                backend = backend, n.cores = threads, seed = 4L
            )
        })[["elapsed"]]
        umap_sec <- system.time({
            umap_layout <- fastEmbedR::umap_knn(
                observed, backend = backend, n.cores = threads,
                seed = 4L, graph_mode = "fuzzy"
            )
        })[["elapsed"]]
        for (embedding_method in c("tsne", "umap_fuzzy")) {
            layout <- if (embedding_method == "tsne") {
                tsne_layout
            } else {
                umap_layout
            }
            quality <- quality_metrics(
                x[quality_rows, , drop = FALSE],
                layout_matrix(layout)[quality_rows, , drop = FALSE],
                if (is.null(labels)) NULL else labels[quality_rows],
                perplexity = 30, support_multiplier = 1, k = 30L
            )
            if (embedding_method != "tsne") quality$sampled_kl <- NA_real_
            results[[length(results) + 1L]] <- data.frame(
                dataset = dataset, backend = backend,
                target_recall = target, observed_recall_at_30 = recall,
                knn_elapsed_sec = elapsed,
                embedding_method = embedding_method,
                embedding_elapsed_sec = if (embedding_method == "tsne") {
                    tsne_sec
                } else {
                    umap_sec
                },
                quality,
                engine = attr(observed, "method") %||%
                    observed$method %||% NA,
                stringsAsFactors = FALSE
            )
        }
    }
    out <- dataset_output_dir("knn_sensitivity", dataset, backend)
    write_csv_atomic(do.call(rbind, results), file.path(out, "recall.csv"))
    write_status("knn_sensitivity", dataset, backend, "success")
}

run_aggregate <- function() {
    csv_files <- list.files(
        output_root, pattern = "[.]csv$", recursive = TRUE,
        full.names = TRUE
    )
    csv_files <- csv_files[!grepl("/aggregate/", csv_files, fixed = TRUE)]
    inventory <- data.frame(
        path = csv_files,
        relative_path = sub(paste0("^", output_root, "/?"), "", csv_files),
        size_bytes = file.info(csv_files)$size,
        stringsAsFactors = FALSE
    )
    out <- file.path(output_root, "aggregate")
    write_csv_atomic(inventory, file.path(out, "csv_inventory.csv"))
    statuses <- csv_files[basename(csv_files) == "status.csv"]
    if (length(statuses)) {
        status <- bind_rows_union(lapply(statuses, function(path) {
            tryCatch(utils::read.csv(path, stringsAsFactors = FALSE),
                error = function(error) NULL
            )
        }))
        write_csv_atomic(status, file.path(out, "all_status.csv"))
    }
    scheduler_files <- csv_files[
        grepl("/scheduler_status/", csv_files, fixed = TRUE) |
            grepl(".scheduler_status.csv", csv_files, fixed = TRUE)
    ]
    if (length(scheduler_files)) {
        scheduler <- bind_rows_union(lapply(scheduler_files, function(path) {
            tryCatch(utils::read.csv(path, stringsAsFactors = FALSE),
                error = function(error) NULL
            )
        }))
        write_csv_atomic(scheduler,
            file.path(out, "scheduler_status_all.csv")
        )
    }
    timing_files <- csv_files[
        basename(csv_files) == "timing_repetitions.csv" &
            grepl("/support_", csv_files, fixed = TRUE)
    ]
    if (length(timing_files)) {
        raw <- do.call(rbind, lapply(timing_files, utils::read.csv))
        key <- interaction(
            raw$dataset, raw$backend, raw$support_multiplier, drop = TRUE
        )
        summary <- do.call(rbind, lapply(split(raw, key), function(x) {
            data.frame(
                dataset = x$dataset[[1L]], backend = x$backend[[1L]],
                support_multiplier = x$support_multiplier[[1L]],
                timing_n = nrow(x), median_sec = stats::median(x$elapsed_sec),
                q1_sec = stats::quantile(x$elapsed_sec, 0.25),
                q3_sec = stats::quantile(x$elapsed_sec, 0.75),
                stringsAsFactors = FALSE
            )
        }))
        write_csv_atomic(raw, file.path(out, "support_timing_raw.csv"))
        write_csv_atomic(summary,
            file.path(out, "support_timing_summary.csv")
        )
    }
    longrun_timing_files <- csv_files[
        basename(csv_files) == "timing_repetitions.csv" &
            grepl("/tsne_longrun_timing/", csv_files, fixed = TRUE)
    ]
    if (length(longrun_timing_files)) {
        raw <- bind_rows_union(lapply(
            longrun_timing_files, utils::read.csv,
            stringsAsFactors = FALSE
        ))
        key <- interaction(
            raw$dataset, raw$backend, raw$threads, drop = TRUE
        )
        summary <- do.call(rbind, lapply(split(raw, key), function(x) {
            data.frame(
                dataset = x$dataset[[1L]], backend = x$backend[[1L]],
                threads = x$threads[[1L]], seed = x$seed[[1L]],
                timing_n = nrow(x),
                median_sec = stats::median(x$elapsed_sec),
                q1_sec = stats::quantile(x$elapsed_sec, 0.25),
                q3_sec = stats::quantile(x$elapsed_sec, 0.75),
                min_sec = min(x$elapsed_sec),
                max_sec = max(x$elapsed_sec),
                stringsAsFactors = FALSE
            )
        }))
        write_csv_atomic(raw, file.path(out, "tsne_timing_raw.csv"))
        write_csv_atomic(summary, file.path(out, "tsne_timing_summary.csv"))
    }
    quality_files <- csv_files[basename(csv_files) == "quality.csv"]
    if (length(quality_files)) {
        quality <- do.call(rbind, lapply(quality_files, utils::read.csv))
        write_csv_atomic(quality, file.path(out, "support_quality_raw.csv"))
    }
    knn_observed <- data.frame()
    knn_observed_files <- csv_files[
        basename(csv_files) == "observed_recall.csv"
    ]
    if (length(knn_observed_files)) {
        knn_observed <- bind_rows_union(lapply(
            knn_observed_files, utils::read.csv,
            stringsAsFactors = FALSE
        ))
        write_csv_atomic(
            knn_observed, file.path(out, "knn_observed_recall.csv")
        )
    }
    backend_quality_files <- csv_files[
        basename(csv_files) == "backend_quality.csv"
    ]
    if (length(backend_quality_files)) {
        quality <- bind_rows_union(lapply(
            backend_quality_files, utils::read.csv,
            stringsAsFactors = FALSE
        ))
        key <- interaction(
            quality$dataset, quality$method, quality$backend,
            quality$boundary, drop = TRUE
        )
        summary <- do.call(rbind, lapply(split(quality, key), function(x) {
            summarize <- function(value) {
                value <- value[is.finite(value)]
                if (!length(value)) {
                    return(c(median = NA_real_, q1 = NA_real_, q3 = NA_real_))
                }
                c(
                    median = stats::median(value, na.rm = TRUE),
                    q1 = unname(stats::quantile(
                        value, 0.25, na.rm = TRUE
                    )),
                    q3 = unname(stats::quantile(
                        value, 0.75, na.rm = TRUE
                    ))
                )
            }
            trust <- summarize(x$trustworthiness)
            preserve <- summarize(x$preserve_at_30)
            accuracy <- summarize(x$label_knn_accuracy)
            sampled_kl <- summarize(x$sampled_kl)
            kl <- summarize(x$final_recorded_kl)
            observed_recall <- summarize(x$observed_knn_recall_at_k)
            data.frame(
                dataset = x$dataset[[1L]], method = x$method[[1L]],
                backend = x$backend[[1L]], boundary = x$boundary[[1L]],
                n = x$n[[1L]], p = x$p[[1L]],
                successful_seeds = nrow(x),
                trustworthiness_median = trust[["median"]],
                trustworthiness_q1 = trust[["q1"]],
                trustworthiness_q3 = trust[["q3"]],
                preserve_at_30_median = preserve[["median"]],
                preserve_at_30_q1 = preserve[["q1"]],
                preserve_at_30_q3 = preserve[["q3"]],
                label_knn_accuracy_median = accuracy[["median"]],
                label_knn_accuracy_q1 = accuracy[["q1"]],
                label_knn_accuracy_q3 = accuracy[["q3"]],
                sampled_compact_kl_median = sampled_kl[["median"]],
                sampled_compact_kl_q1 = sampled_kl[["q1"]],
                sampled_compact_kl_q3 = sampled_kl[["q3"]],
                final_kl_median = kl[["median"]],
                final_kl_q1 = kl[["q1"]],
                final_kl_q3 = kl[["q3"]],
                observed_knn_recall_median =
                    observed_recall[["median"]],
                observed_knn_recall_q1 = observed_recall[["q1"]],
                observed_knn_recall_q3 = observed_recall[["q3"]],
                observed_knn_recall_k = x$observed_knn_recall_k[[1L]],
                observed_knn_recall_query_n =
                    x$observed_knn_recall_query_n[[1L]],
                nn_engine = paste(unique(x$nn_engine), collapse = ";"),
                stringsAsFactors = FALSE
            )
        }))
        write_csv_atomic(quality, file.path(out, "backend_quality_raw.csv"))
        write_csv_atomic(
            summary, file.path(out, "backend_quality_summary.csv")
        )
        if (nrow(knn_observed)) {
            full <- quality[
                quality$boundary == "full_workflow", , drop = FALSE
            ]
            joined <- merge(
                full, knn_observed,
                by = c("dataset", "backend", "n"), all.x = TRUE,
                suffixes = c("", "_recall_audit")
            )
            joined$nn_engine_matches_audit <-
                joined$nn_engine == joined$engine
            joined$nn_k_matches_audit <-
                joined$perplexity_or_neighbors == joined$k
            write_csv_atomic(
                joined,
                file.path(out, "full_workflow_quality_with_knn_recall.csv")
            )
            full_summary <- summary[
                summary$boundary == "full_workflow", , drop = FALSE
            ]
            summary_joined <- merge(
                full_summary, knn_observed,
                by = c("dataset", "backend", "n"), all.x = TRUE
            )
            write_csv_atomic(
                summary_joined,
                file.path(
                    out,
                    "full_workflow_quality_summary_with_knn_recall.csv"
                )
            )
        }
    }
    affinity_files <- csv_files[
        basename(csv_files) == "affinity_characterization.csv"
    ]
    if (length(affinity_files)) {
        affinity <- do.call(rbind, lapply(affinity_files, utils::read.csv))
        write_csv_atomic(affinity,
            file.path(out, "affinity_characterization_all.csv")
        )
    }
    longrun_files <- csv_files[
        basename(csv_files) == "result.csv" &
            grepl("/tsne_longrun/", csv_files, fixed = TRUE)
    ]
    if (length(longrun_files)) {
        longrun <- bind_rows_union(lapply(longrun_files, function(path) {
            tryCatch(
                utils::read.csv(path, stringsAsFactors = FALSE),
                error = function(error) NULL
            )
        }))
        write_csv_atomic(longrun, file.path(out, "tsne_longrun_all.csv"))
        reference <- longrun[
            longrun$backend == "python_cpu",
            c("dataset", "seed", "normal_iterations", "common_affinity_kl")
        ]
        names(reference)[[4L]] <- "python_common_affinity_kl"
        candidate <- longrun[longrun$backend != "python_cpu", , drop = FALSE]
        comparison <- merge(
            candidate, reference,
            by = c("dataset", "seed", "normal_iterations"),
            all.x = TRUE
        )
        comparison$relative_kl_difference_vs_python <- (
            comparison$common_affinity_kl /
                comparison$python_common_affinity_kl
        ) - 1
        comparison$within_five_percent_of_python <-
            comparison$relative_kl_difference_vs_python <= 0.05
        write_csv_atomic(
            comparison,
            file.path(out, "tsne_longrun_kl_vs_python.csv")
        )
    }
    transform_files <- csv_files[basename(csv_files) == "transform.csv"]
    if (length(transform_files)) {
        transform <- do.call(rbind, lapply(transform_files, utils::read.csv))
        write_csv_atomic(transform, file.path(out, "transform_all.csv"))
    }
    scaling_files <- csv_files[basename(csv_files) == "scaling.csv"]
    if (length(scaling_files)) {
        scaling <- do.call(rbind, lapply(scaling_files, utils::read.csv))
        write_csv_atomic(scaling, file.path(out, "scaling_raw.csv"))
        stages <- c("knn_sec", "pca_sec", "tsne_embedding_sec",
            "umap_embedding_sec", "total_tsne_sec", "total_umap_sec"
        )
        summaries <- list()
        for (name in unique(scaling$dataset)) {
            current <- scaling[scaling$dataset == name, , drop = FALSE]
            for (stage in stages) {
                medians <- tapply(current[[stage]], current$threads,
                    stats::median
                )
                baseline <- medians[["1"]]
                summaries[[length(summaries) + 1L]] <- data.frame(
                    dataset = name, stage = stage,
                    threads = as.integer(names(medians)),
                    median_sec = as.numeric(medians),
                    speedup = baseline / as.numeric(medians),
                    parallel_efficiency = baseline /
                        (as.numeric(medians) * as.integer(names(medians))),
                    stringsAsFactors = FALSE
                )
            }
        }
        write_csv_atomic(do.call(rbind, summaries),
            file.path(out, "scaling_summary.csv")
        )
    }
    measurement_files <- list.files(
        file.path(output_root, "measurement"), pattern = "[.]time[.]txt$",
        recursive = TRUE, full.names = TRUE
    )
    if (length(measurement_files)) {
        memory <- do.call(rbind, lapply(measurement_files, function(path) {
            lines <- readLines(path, warn = FALSE)
            field <- function(label) {
                hit <- lines[grepl(label, lines, fixed = TRUE)]
                if (!length(hit)) return(NA_real_)
                as.numeric(trimws(sub("^[^:]+:", "", hit[[1L]])))
            }
            elapsed_field <- function() {
                hit <- lines[grepl(
                    "Elapsed (wall clock) time", lines, fixed = TRUE
                )]
                if (!length(hit)) return(NA_real_)
                value <- trimws(sub("^.*\\):[[:space:]]*", "", hit[[1L]]))
                pieces <- as.numeric(strsplit(value, ":", fixed = TRUE)[[1L]])
                if (anyNA(pieces)) return(NA_real_)
                if (length(pieces) == 2L) return(pieces[[1L]] * 60 + pieces[[2L]])
                if (length(pieces) == 3L) {
                    return(pieces[[1L]] * 3600 + pieces[[2L]] * 60 + pieces[[3L]])
                }
                NA_real_
            }
            data.frame(
                path = path,
                wall_clock_sec = elapsed_field(),
                max_rss_kb = field("Maximum resident set size"),
                stringsAsFactors = FALSE
            )
        }))
        write_csv_atomic(memory, file.path(out, "task_memory.csv"))
    }
    gpu_files <- list.files(
        file.path(output_root, "measurement"),
        pattern = "[.]gpu_memory[.]csv$", recursive = TRUE,
        full.names = TRUE
    )
    if (length(gpu_files)) {
        gpu <- do.call(rbind, lapply(gpu_files, function(path) {
            x <- utils::read.csv(path, stringsAsFactors = FALSE)
            data.frame(
                path = path,
                baseline_mib = if (nrow(x)) x$baseline_mib[[1L]] else NA,
                peak_used_mib = if (nrow(x)) max(x$memory_used_mib) else NA,
                peak_incremental_mib = if (nrow(x)) {
                    max(x$incremental_mib)
                } else {
                    NA
                },
                stringsAsFactors = FALSE
            )
        }))
        write_csv_atomic(gpu, file.path(out, "task_gpu_memory.csv"))
    }
    agreement <- aggregate_support_agreement(output_root)
    if (nrow(agreement)) {
        write_csv_atomic(agreement,
            file.path(out, "support_layout_agreement.csv")
        )
    }
    pca_agreement <- aggregate_pca_agreement(output_root)
    if (nrow(pca_agreement)) {
        write_csv_atomic(pca_agreement,
            file.path(out, "pca_backend_agreement.csv")
        )
    }
    pca_accuracy_files <- csv_files[
        basename(csv_files) == "pca_accuracy.csv"
    ]
    if (length(pca_accuracy_files)) {
        pca_accuracy <- bind_rows_union(lapply(
            pca_accuracy_files, utils::read.csv,
            stringsAsFactors = FALSE
        ))
        write_csv_atomic(
            pca_accuracy, file.path(out, "pca_accuracy_vs_dense.csv")
        )
        fast_rows <- pca_accuracy[pca_accuracy$method == "fastEmbedR", ]
        if (nrow(fast_rows)) {
            key <- interaction(
                fast_rows$backend, fast_rows$rank, drop = TRUE
            )
            pca_accuracy_summary <- do.call(rbind, lapply(
                split(fast_rows, key), function(x) {
                    data.frame(
                        backend = x$backend[[1L]], rank = x$rank[[1L]],
                        successful_datasets = nrow(x),
                        score_procrustes_median = stats::median(
                            x$score_procrustes, na.rm = TRUE
                        ),
                        loading_subspace_cosine_median = stats::median(
                            x$loading_subspace_cosine_mean, na.rm = TRUE
                        ),
                        singular_value_relative_l2_median = stats::median(
                            x$singular_value_relative_l2, na.rm = TRUE
                        ),
                        captured_variance_abs_difference_median = stats::median(
                            x$captured_variance_abs_difference, na.rm = TRUE
                        ),
                        reconstruction_relative_error_median = stats::median(
                            x$reconstruction_relative_error, na.rm = TRUE
                        ),
                        stringsAsFactors = FALSE
                    )
                }
            ))
            write_csv_atomic(
                pca_accuracy_summary,
                file.path(out, "pca_accuracy_summary.csv")
            )
        }
    }
    pca_accuracy_agreement <- aggregate_pca_accuracy_agreement(output_root)
    if (nrow(pca_accuracy_agreement)) {
        write_csv_atomic(
            pca_accuracy_agreement,
            file.path(out, "pca_accuracy_backend_agreement.csv")
        )
    }
    longrun_agreement <- aggregate_longrun_agreement(output_root)
    if (nrow(longrun_agreement)) {
        write_csv_atomic(
            longrun_agreement,
            file.path(out, "tsne_longrun_layout_agreement.csv")
        )
    }
    cat("Aggregated ", length(csv_files), " CSV files into ", out, "\n",
        sep = ""
    )
}

aggregate_longrun_agreement <- function(root) {
    rows <- list()
    datasets <- c("USPS", "FashionMNIST", "MNIST", "MetRef")
    for (name in datasets) {
        for (seed in c(4L, 17L, 42L)) {
            python_path <- file.path(
                root, "tsne_longrun", name, "python_cpu",
                paste0("4t_iter750_seed", seed), "layout.csv"
            )
            if (!file.exists(python_path)) next
            reference <- as.matrix(utils::read.csv(python_path))
            for (candidate_backend in c("cpu", "metal", "cuda")) {
                candidate_path <- file.path(
                    root, "tsne_longrun", name, candidate_backend,
                    paste0("4t_grid256_iter750_seed", seed), "layout.csv"
                )
                if (!file.exists(candidate_path)) next
                candidate <- as.matrix(utils::read.csv(candidate_path))
                rows[[length(rows) + 1L]] <- data.frame(
                    dataset = name, seed = seed,
                    reference = "Python openTSNE",
                    candidate = paste("fastEmbedR", candidate_backend),
                    procrustes_correlation = procrustes_correlation(
                        reference, candidate
                    ),
                    neighborhood_agreement_at_30 =
                        layout_neighbor_agreement(reference, candidate, 30L),
                    stringsAsFactors = FALSE
                )
            }
        }
    }
    if (length(rows)) do.call(rbind, rows) else data.frame()
}

aggregate_support_agreement <- function(root) {
    rows <- list()
    for (name in dataset_registry(data_root)$dataset) {
        for (support in c(1, 3)) {
            cpu_path <- file.path(
                root, paste0("support_", support, "P"), name,
                "cpu", "layouts.rds"
            )
            cuda_path <- file.path(
                root, paste0("support_", support, "P"), name,
                "cuda", "layouts.rds"
            )
            if (!file.exists(cpu_path) || !file.exists(cuda_path)) next
            cpu <- readRDS(cpu_path)
            cuda <- readRDS(cuda_path)
            for (seed in intersect(names(cpu$layouts), names(cuda$layouts))) {
                sample <- cpu$quality_rows
                ref <- cpu$layouts[[seed]][sample, , drop = FALSE]
                can <- cuda$layouts[[seed]][sample, , drop = FALSE]
                rows[[length(rows) + 1L]] <- data.frame(
                    dataset = name, support_multiplier = support,
                    seed = as.integer(seed), comparison = "cpu_vs_cuda",
                    procrustes_correlation = procrustes_correlation(ref, can),
                    neighborhood_agreement_at_30 =
                        layout_neighbor_agreement(ref, can, 30L),
                    stringsAsFactors = FALSE
                )
            }
        }
        for (used_backend in c("cpu", "cuda")) {
            compact_path <- file.path(
                root, "support_1P", name, used_backend, "layouts.rds"
            )
            standard_path <- file.path(
                root, "support_3P", name, used_backend, "layouts.rds"
            )
            if (!file.exists(compact_path) || !file.exists(standard_path)) next
            compact <- readRDS(compact_path)
            standard <- readRDS(standard_path)
            seeds_here <- intersect(names(compact$layouts), names(standard$layouts))
            for (seed in seeds_here) {
                sample <- compact$quality_rows
                ref <- compact$layouts[[seed]][sample, , drop = FALSE]
                can <- standard$layouts[[seed]][sample, , drop = FALSE]
                rows[[length(rows) + 1L]] <- data.frame(
                    dataset = name, support_multiplier = NA_real_,
                    seed = as.integer(seed),
                    comparison = paste0(used_backend, "_1P_vs_3P"),
                    procrustes_correlation = procrustes_correlation(ref, can),
                    neighborhood_agreement_at_30 =
                        layout_neighbor_agreement(ref, can, 30L),
                    stringsAsFactors = FALSE
                )
            }
        }
    }
    if (length(rows)) do.call(rbind, rows) else data.frame()
}

aggregate_pca_agreement <- function(root) {
    rows <- list()
    registry <- dataset_registry(data_root)
    for (name in registry$dataset) {
        for (requested_rank in c(2, 50)) {
            cpu_path <- file.path(
                root, "pca", name,
                paste0("cpu_12t_rank", requested_rank),
                "pca_fit_summary.rds"
            )
            cuda_path <- file.path(
                root, "pca", name,
                paste0("cuda_4t_rank", requested_rank),
                "pca_fit_summary.rds"
            )
            if (!file.exists(cpu_path) || !file.exists(cuda_path)) next
            cpu <- readRDS(cpu_path)
            cuda <- readRDS(cuda_path)
            if (!identical(cpu$rows, cuda$rows)) next
            angle <- principal_angle_summary(
                cpu$score_sample, cuda$score_sample
            )
            rows[[length(rows) + 1L]] <- data.frame(
                dataset = name, requested_rank = requested_rank,
                rank = cpu$rank,
                procrustes_correlation = procrustes_correlation(
                    cpu$score_sample, cuda$score_sample
                ),
                angle,
                stringsAsFactors = FALSE
            )
        }
    }
    if (length(rows)) do.call(rbind, rows) else data.frame()
}

pca_backend_pair_row <- function(name, requested_rank, reference_backend,
                                 candidate_backend, reference, candidate) {
    score_angles <- principal_angle_summary(
        reference$fastembedr$scores, candidate$fastembedr$scores
    )
    loading_angles <- principal_angle_summary(
        reference$fastembedr$loadings, candidate$fastembedr$loadings
    )
    data.frame(
        dataset = name, requested_rank = requested_rank,
        rank = reference$rank,
        reference_backend = reference_backend,
        candidate_backend = candidate_backend,
        score_procrustes = procrustes_correlation(
            reference$fastembedr$scores,
            candidate$fastembedr$scores
        ),
        score_max_principal_angle_rad =
            score_angles$max_principal_angle_rad,
        score_mean_principal_angle_rad =
            score_angles$mean_principal_angle_rad,
        score_subspace_cosine_mean = score_angles$subspace_cosine_mean,
        loading_max_principal_angle_rad =
            loading_angles$max_principal_angle_rad,
        loading_mean_principal_angle_rad =
            loading_angles$mean_principal_angle_rad,
        loading_subspace_cosine_mean =
            loading_angles$subspace_cosine_mean,
        singular_value_relative_l2 = pca_relative_l2(
            reference$fastembedr$singular_values,
            candidate$fastembedr$singular_values
        ),
        stringsAsFactors = FALSE
    )
}

aggregate_pca_accuracy_agreement <- function(root) {
    rows <- list()
    registry <- dataset_registry(data_root)
    backends <- c("cpu", "metal", "cuda")
    pairs <- list(c("cpu", "cuda"), c("cpu", "metal"), c("metal", "cuda"))
    for (name in registry$dataset) {
        for (requested_rank in c(2L, 50L)) {
            summaries <- list()
            for (used_backend in backends) {
                path <- file.path(
                    root, "pca_accuracy", name,
                    paste0(used_backend, "_4t_rank", requested_rank),
                    "pca_accuracy_summary.rds"
                )
                if (file.exists(path)) summaries[[used_backend]] <- readRDS(path)
            }
            for (pair in pairs) {
                if (!all(pair %in% names(summaries))) next
                reference <- summaries[[pair[[1L]]]]
                candidate <- summaries[[pair[[2L]]]]
                if (!identical(reference$rows, candidate$rows)) next
                rows[[length(rows) + 1L]] <- pca_backend_pair_row(
                    name, requested_rank, pair[[1L]], pair[[2L]],
                    reference, candidate
                )
            }
        }
    }
    if (length(rows)) do.call(rbind, rows) else data.frame()
}

dispatch <- list(
    preflight = run_preflight,
    precompute = run_precompute,
    longrun_precompute = run_longrun_precompute,
    longrun = run_longrun_tsne,
    longrun_timing = run_longrun_timing,
    affinity = run_affinity,
    support = run_support,
    backend_quality = run_backend_quality,
    transform = run_transform,
    landmark_reconstruction = run_landmark_reconstruction,
    scaling = run_scaling,
    pca = run_pca_validation,
    pca_accuracy = run_pca_accuracy,
    knn_observed = run_observed_knn_accuracy,
    knn_sensitivity = run_knn_sensitivity,
    aggregate = run_aggregate
)

if (!mode %in% names(dispatch)) stop("Unknown mode: ", mode)
tryCatch(
    dispatch[[mode]](),
    error = function(error) {
        status_backend <- backend
        if (mode %in% c("pca", "pca_accuracy")) {
            requested_rank <- as_int(arg_value("rank"), 2L)
            status_backend <- paste0(
                backend, "_", threads, "t_rank", requested_rank
            )
        }
        write_status(
            mode, dataset, status_backend, "failed",
            conditionMessage(error)
        )
        message("ERROR: ", conditionMessage(error))
        quit(status = 1L)
    }
)
