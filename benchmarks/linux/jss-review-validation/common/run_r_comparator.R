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
dataset <- arg_value("dataset", "MNIST")
method <- arg_value("method", "fastembedr_tsne")
backend <- arg_value("backend", "cpu")
threads <- as_int(arg_value("threads"), 4L)
seed <- as_int(arg_value("seed"), 4L)
timing_reps <- as_int(arg_value("timing-reps"), 5L)
n_components <- as_int(arg_value("n-components"), 2L)
defer_quality <- identical(arg_value("defer-quality"), "TRUE")
full_dataset <- identical(arg_value("full-dataset"), "TRUE")
output_group <- if (n_components == 3L) {
    "workflow_comparators_3d"
} else "workflow_comparators"
tsne_early_iterations <- 250L
tsne_total_iterations <- 1000L
tsne_normal_iterations <- tsne_total_iterations - tsne_early_iterations
parameter_contract <- utils::read.csv(
    file.path(script_dir, "workflow_parameter_contract.csv"),
    stringsAsFactors = FALSE, na.strings = character()
)

if (!backend %in% c("cpu", "cuda")) {
    stop("Unsupported comparator backend: ", backend, call. = FALSE)
}
if (backend == "cuda" && !startsWith(method, "fastembedr_")) {
    stop("Only fastEmbedR methods are valid in the R CUDA comparator.")
}
if (timing_reps < 2L) {
    stop("At least two timing repetitions are required.", call. = FALSE)
}
if (!n_components %in% c(2L, 3L)) {
    stop("Output dimensions must be 2 or 3.", call. = FALSE)
}

method_family <- function(name) {
    family <- parameter_contract$family[parameter_contract$method == name]
    if (length(family) != 1L || !family %in% c("pca", "tsne", "umap")) {
        stop("Unknown comparator method: ", name, call. = FALSE)
    }
    family
}

method_version <- function(name) {
    package <- switch(
        name,
        fastembedr_pca = "fastEmbedR",
        fastembedr_tsne = "fastEmbedR",
        fastembedr_umap = "fastEmbedR",
        irlba_pca = "irlba", rtsne = "Rtsne",
        uwot = "uwot", uwot_fast_sgd = "uwot", r_umap = "umap",
        stats_prcomp = "stats", NA_character_
    )
    if (identical(name, "fitsne")) {
        return(sha256_file("/opt/fit-sne/bin/fast_tsne"))
    }
    if (is.na(package)) return(NA_character_)
    as.character(utils::packageVersion(package))
}

umap_epoch_policy <- function(n) {
    if (n < 10000L) 500L else 200L
}

method_parameters <- function(name, family, fit, n) {
    row <- parameter_contract[
        parameter_contract$method == name, , drop = FALSE
    ]
    if (nrow(row) != 1L || row$family != family) {
        stop("Missing parameter contract for ", name, call. = FALSE)
    }
    row$learning_rate_value <- switch(
        name,
        fastembedr_tsne = max(n / 12, 200),
        rtsne = 200,
        fitsne = max(n / 12, 200),
        fastembedr_umap = fit$parameters$learning_rate %||% 1,
        uwot = 1,
        uwot_fast_sgd = 1,
        r_umap = 1,
        NA_real_
    )
    row$epochs_value <- switch(
        name,
        fastembedr_umap = fit$parameters$epochs %||% umap_epoch_policy(n),
        uwot = umap_epoch_policy(n),
        uwot_fast_sgd = umap_epoch_policy(n),
        r_umap = 200L,
        NA_integer_
    )
    row$min_dist_value <- if (name == "fastembedr_umap") {
        fit$parameters$min_dist %||% 0.01
    } else if (family == "umap") {
        as.numeric(row$min_dist_policy)
    } else NA_real_
    if (name == "fitsne" && n_components == 3L) {
        row$optimizer <- "Barnes-Hut"
    }
    if (name == "fastembedr_tsne") {
        row$optimizer <- fit$parameters$repulsion %||% NA_character_
    }
    row[setdiff(names(row), c("method", "family"))]
}

load_benchmark_data <- function() {
    shared <- readRDS(file.path(input_root, dataset, "matched_inputs.rds"))
    loaded <- load_dataset(data_root, dataset)
    selected <- if (full_dataset) loaded$data else {
        loaded$data[shared$rows, , drop = FALSE]
    }
    if (full_dataset && nrow(selected) != length(shared$rows)) {
        stop("Full comparator input does not cover every source row.")
    }
    if (defer_quality && startsWith(method, "fastembedr_")) {
        return(list(shared = shared, double = NULL,
            float = as_float_matrix(selected), n = nrow(selected),
            p = ncol(selected)))
    }
    standard <- as_double_matrix(selected)
    list(shared = shared, double = standard,
        float = if (startsWith(method, "fastembedr_")) {
            float::fl(standard)
        } else NULL,
        n = nrow(standard), p = ncol(standard))
}

load_fitsne <- function() {
    wrapper <- "/opt/fit-sne/bin/fast_tsne.R"
    executable <- "/opt/fit-sne/bin/fast_tsne"
    if (!file.exists(wrapper) || !file.exists(executable)) {
        stop("FIt-SNE wrapper or executable is unavailable.", call. = FALSE)
    }
    environment <- new.env(parent = globalenv())
    sys.source(wrapper, envir = environment, chdir = TRUE)
    if (!is.function(environment$fftRtsne)) {
        stop("FIt-SNE wrapper does not define fftRtsne().", call. = FALSE)
    }
    list(fun = environment$fftRtsne, executable = executable)
}

fit_pca <- function(name, x, rank) {
    if (name == "fastembedr_pca") {
        return(fastEmbedR::pca(
            x, ncomp = rank, backend = backend,
            n.cores = threads, seed = seed
        ))
    }
    if (name == "irlba_pca") {
        return(irlba::prcomp_irlba(
            x, n = rank, center = TRUE, scale. = FALSE
        ))
    }
    stats::prcomp(x, rank. = rank, center = TRUE, scale. = FALSE)
}

fit_tsne <- function(name, x, perplexity, fitsne = NULL) {
    if (name == "fastembedr_tsne") {
        return(fastEmbedR::tsne(
            x, perplexity = perplexity, n_components = n_components,
            backend = backend,
            n.cores = threads, seed = seed,
            learning_rate = max(nrow(x) / 12, 200),
            early_exaggeration_iter = tsne_early_iterations,
            early_exaggeration = 12,
            n_iter = tsne_normal_iterations, exaggeration = 1,
            initial_momentum = 0.8, final_momentum = 0.8,
            max_step_norm = 5,
            negative_gradient_method = if (n_components == 3L) {
                "auto"
            } else "fft",
            auto_config = FALSE
        ))
    }
    if (name == "rtsne") {
        return(Rtsne::Rtsne(
            x, dims = n_components, perplexity = perplexity, pca = TRUE,
            initial_dims = 50L, Y_init = NULL,
            theta = 0.5, max_iter = tsne_total_iterations,
            num_threads = threads,
            stop_lying_iter = 250L, mom_switch_iter = 250L,
            momentum = 0.5, final_momentum = 0.8, eta = 200,
            exaggeration_factor = 12, check_duplicates = FALSE,
            verbose = FALSE
        ))
    }
    if (is.null(fitsne)) {
        stop("FIt-SNE wrapper was not loaded.", call. = FALSE)
    }
    fitsne$fun(
        x, dims = n_components, perplexity = perplexity,
        fft_not_bh = n_components == 2L,
        max_iter = tsne_total_iterations,
        initialization = "pca", stop_early_exag_iter = 250L,
        exaggeration_factor = 12, learning_rate = "auto",
        momentum = 0.5, final_momentum = 0.8,
        rand_seed = seed, nthreads = threads,
        fast_tsne_path = fitsne$executable
    )
}

fit_umap <- function(name, x, neighbors) {
    if (name == "fastembedr_umap") {
        return(fastEmbedR::umap(
            x, n_neighbors = neighbors, n_components = n_components,
            graph_mode = "fuzzy",
            backend = backend, n.cores = threads, seed = seed
        ))
    }
    if (name %in% c("uwot", "uwot_fast_sgd")) {
        fast <- identical(name, "uwot_fast_sgd")
        return(uwot::umap(
            x, n_neighbors = neighbors, n_components = n_components,
            init = "spectral",
            metric = "euclidean", n_epochs = umap_epoch_policy(nrow(x)),
            learning_rate = 1,
            min_dist = 0.01, spread = 1, repulsion_strength = 1,
            negative_sample_rate = 5,
            n_threads = threads,
            n_sgd_threads = if (fast) threads else 1L,
            fast_sgd = fast, seed = seed, verbose = FALSE
        ))
    }
    config <- umap::umap.defaults
    config$n_neighbors <- as.integer(neighbors)
    config$n_components <- n_components
    config$metric <- "euclidean"
    config$input <- "data"
    config$init <- "spectral"
    config$min_dist <- 0.1
    config$spread <- 1
    config$learning_rate <- 1
    config$negative_sample_rate <- 5L
    config$random_state <- as.integer(seed)
    config$verbose <- FALSE
    umap::umap(x, config = config, method = "naive")
}

fit_once <- function(name, x, perplexity, neighbors, rank,
                     fitsne = NULL) {
    set.seed(seed)
    family <- method_family(name)
    switch(
        family,
        pca = fit_pca(name, x, rank),
        tsne = fit_tsne(name, x, perplexity, fitsne),
        umap = fit_umap(name, x, neighbors)
    )
}

assert_fastembedr_backend <- function(fit) {
    if (!startsWith(method, "fastembedr_")) return(invisible(NULL))
    if (method_family(method) == "pca") {
        observed <- as.character(fit$backend %||% "")
        if (!grepl(backend, observed, fixed = TRUE)) {
            stop("Requested backend ", backend, " but observed ", observed)
        }
        return(invisible(observed))
    }
    assert_layout_backend(fit, backend)
}

extract_layout <- function(fit, family) {
    if (family == "pca") {
        value <- fit$scores %||% fit$x
        return(as_double_matrix(value)[, 1:2, drop = FALSE])
    }
    field <- if (family == "tsne") "Y" else "layout"
    embedding_result_matrix(fit, field)
}

pca_diagnostics <- function(fit, x, quality_rows) {
    scores <- as_double_matrix(fit$scores %||% fit$x)
    loadings <- as_double_matrix(fit$loadings %||% fit$rotation)
    center <- as.numeric(fit$center %||% colMeans(x))
    rows <- quality_rows
    reconstruction <- sweep(scores[rows, , drop = FALSE] %*% t(loadings),
        2L, center, "+"
    )
    reference <- x[rows, , drop = FALSE]
    data.frame(
        reconstruction_relative_l2 = sqrt(
            sum((reference - reconstruction)^2) / sum(reference^2)
        ),
        retained_variance_fraction = sum(scores * scores) /
            sum(sweep(x, 2L, center, "-")^2)
    )
}

stage_seconds <- function(fit) {
    fields <- c(
        preprocess = "preprocess_elapsed",
        knn = "knn_elapsed",
        initialization = "initialization_elapsed",
        embedding = "embedding_elapsed"
    )
    if (!startsWith(method, "fastembedr_")) {
        return(setNames(rep(NA_real_, length(fields)), names(fields)))
    }
    vapply(fields, function(field) {
        value <- fit$metrics[[field]]
        if (length(value) == 1L) as.numeric(value) else NA_real_
    }, numeric(1L))
}

write_outputs <- function(fit, elapsed, benchmark, stages = NULL,
                          output_dir = output_root) {
    family <- method_family(method)
    layout <- extract_layout(fit, family)
    rows <- benchmark$shared$quality_rows
    quality <- if (family == "pca" || defer_quality) {
        data.frame(
            trustworthiness = NA_real_, preserve_at_30 = NA_real_,
            label_knn_accuracy = NA_real_, sampled_kl = NA_real_
        )
    } else {
        quality_metrics(
            benchmark$double[rows, , drop = FALSE],
            layout[rows, , drop = FALSE],
            benchmark$shared$labels[rows] %||% NULL,
            benchmark$shared$perplexity, 1, 30L
        )
    }
    if (family == "umap") quality$sampled_kl <- NA_real_
    extra <- if (family == "pca" && !defer_quality) {
        pca_diagnostics(fit, benchmark$double, rows)
    } else {
        data.frame(
            reconstruction_relative_l2 = NA_real_,
            retained_variance_fraction = NA_real_
        )
    }
    comparator_mode <- paste0("r_", backend)
    timing_boundary <- if (startsWith(method, "fastembedr_")) {
        "host_float32_to_host_result"
    } else {
        "host_R_double_to_host_result"
    }
    result_backend <- if (startsWith(method, "fastembedr_")) {
        backend
    } else {
        "cpu"
    }
    if (is.null(stages)) {
        stages <- matrix(NA_real_, nrow = length(elapsed), ncol = 4L)
        colnames(stages) <- names(stage_seconds(fit))
    }
    stage_median <- apply(stages, 2L, function(value) {
        if (all(is.na(value))) NA_real_ else stats::median(value)
    })
    fit_parameters <- if (startsWith(method, "fastembedr_")) {
        fit$parameters
    } else {
        NULL
    }
    out <- file.path(output_dir, output_group, comparator_mode,
        dataset,
        method
    )
    result <- cbind(data.frame(
        dataset = dataset, family = family, method = method,
        n_components = n_components,
        language = "R", backend = result_backend,
        timing_scope = "R_public_fit",
        timing_boundary = timing_boundary,
        timing_interface = "R_public_function",
        timing_eligible = TRUE,
        seed = seed, timing_reps = timing_reps, warmup_count = 1L,
        warmup_excluded = TRUE,
        device_synchronized = backend == "cuda",
        output_materialized_on_host_before_timer = TRUE,
        early_iterations = if (family == "tsne") {
            tsne_early_iterations
        } else {
            NA_integer_
        },
        normal_iterations = if (family == "tsne") {
            tsne_normal_iterations
        } else {
            NA_integer_
        },
        total_iterations = if (family == "tsne") {
            tsne_total_iterations
        } else {
            NA_integer_
        },
        comparison_contract = if (family == "tsne") {
            "workflow_1000_total_iterations"
        } else {
            "workflow_package_policy"
        },
        n = benchmark$n, p = benchmark$p,
        elapsed_median_sec = stats::median(elapsed),
        elapsed_q1_sec = unname(stats::quantile(elapsed, 0.25)),
        elapsed_q3_sec = unname(stats::quantile(elapsed, 0.75)),
        preprocess_median_sec = stage_median[["preprocess"]],
        knn_median_sec = stage_median[["knn"]],
        initialization_median_sec = stage_median[["initialization"]],
        embedding_median_sec = stage_median[["embedding"]],
        nn_engine = fit_parameters$nn_engine %||% NA_character_,
        nn_backend = fit_parameters$nn_backend %||% NA_character_,
        threads = threads, implementation_version = method_version(method),
        stringsAsFactors = FALSE
    ), method_parameters(method, family, fit, benchmark$n),
    quality, extra)
    result$quality_deferred <- defer_quality
    write_csv_atomic(result, file.path(out, "result.csv"))
    write_csv_atomic(cbind(data.frame(
        dataset = dataset, method = method, backend = result_backend,
        seed = seed, timing_replicate = seq_along(elapsed),
        warmup_count = 1L, warmup_excluded = TRUE,
        timing_scope = "R_public_fit",
        timing_boundary = timing_boundary,
        total_iterations = if (family == "tsne") {
            tsne_total_iterations
        } else {
            NA_integer_
        },
        elapsed_sec = elapsed, stringsAsFactors = FALSE
    ), as.data.frame(stages)), file.path(out, "timing_repetitions.csv"))
    if (!defer_quality) {
        quality_layout <- data.frame(
            benchmark_row = rows,
            source_row = benchmark$shared$rows[rows],
            x = layout[rows, 1L], y = layout[rows, 2L]
        )
        if (n_components == 3L) {
            quality_layout$z <- layout[rows, 3L]
        }
        write_csv_atomic(quality_layout, file.path(out,
            "quality_layout.csv"))
    }
    write_csv_atomic(
        embedding_output_table(
            layout, benchmark$shared$labels, benchmark$shared$rows
        ),
        file.path(out, "embedding.csv")
    )
    write_csv_atomic(status_row(
        "workflow_comparator", dataset, comparator_mode, "success",
        method = method
    ), file.path(out, "status.csv"))
}

run <- function() {
    if (n_components == 3L && backend == "cuda" &&
            startsWith(method, "fastembedr_")) {
        out <- file.path(output_root, output_group, paste0("r_", backend),
                         dataset, method)
        write_csv_atomic(status_row(
            "workflow_comparator", dataset, paste0("r_", backend),
            "unsupported", "3D is not supported by this method/backend.",
            method = method
        ), file.path(out, "status.csv"))
        return(invisible(NULL))
    }
    suppressPackageStartupMessages(library(fastEmbedR))
    suppressPackageStartupMessages(library(float))
    benchmark <- load_benchmark_data()
    rank <- min(50L, benchmark$n - 1L, benchmark$p - 1L)
    input <- if (startsWith(method, "fastembedr")) {
        benchmark$float
    } else {
        benchmark$double
    }
    fitsne <- if (method == "fitsne") load_fitsne() else NULL
    warmup <- fit_once(method, input, 30, 30L, rank, fitsne)
    assert_fastembedr_backend(warmup)
    message("Warm-up completed: ", dataset, "/", method)
    stage_names <- names(stage_seconds(warmup))
    if (full_dataset) {
        rm(warmup)
        gc()
    }
    elapsed <- numeric(timing_reps)
    stages <- matrix(NA_real_, nrow = timing_reps, ncol = 4L)
    colnames(stages) <- stage_names
    fit <- NULL
    for (index in seq_len(timing_reps)) {
        if (full_dataset) {
            fit <- NULL
            gc()
        }
        timing <- system.time({
            fit <- fit_once(method, input, 30, 30L, rank, fitsne)
        })
        assert_fastembedr_backend(fit)
        elapsed[[index]] <- timing[["elapsed"]]
        stages[index, ] <- stage_seconds(fit)
        message(
            "Timing repetition ", index, "/", timing_reps,
            ": ", format(elapsed[[index]], digits = 6), " seconds"
        )
    }
    write_outputs(fit, elapsed, benchmark, stages)
}

run_smoke <- function() {
    suppressPackageStartupMessages(library(fastEmbedR))
    suppressPackageStartupMessages(library(float))
    set.seed(seed)
    x <- matrix(stats::rnorm(256L * 8L), nrow = 256L)
    input <- if (startsWith(method, "fastembedr_")) float::fl(x) else x
    fitsne <- if (method == "fitsne") load_fitsne() else NULL
    fit <- fit_once(method, input, 5, 15L, 2L, fitsne)
    assert_fastembedr_backend(fit)
    layout <- extract_layout(fit, method_family(method))
    if (!identical(dim(layout), c(256L, 2L)) ||
            any(!is.finite(layout))) {
        stop("Comparator smoke returned an invalid layout.")
    }
    method_parameters(method, method_family(method), fit, nrow(x))
    smoke_dir <- tempfile("comparator-smoke-")
    on.exit(unlink(smoke_dir, recursive = TRUE), add = TRUE)
    benchmark <- list(
        double = x, n = nrow(x), p = ncol(x),
        shared = list(
            quality_rows = seq_len(128L), rows = seq_len(nrow(x)),
            labels = rep(c("A", "B"), length.out = nrow(x)),
            perplexity = 5
        )
    )
    write_outputs(
        fit, rep(1, 2L), benchmark, output_dir = smoke_dir
    )
    message("Comparator production-call smoke: PASS ", method)
}

if (identical(arg_value("smoke"), "TRUE")) {
    run_smoke()
} else tryCatch(run(), error = function(error) {
    comparator_mode <- paste0("r_", backend)
    out <- file.path(output_root, output_group, comparator_mode,
        dataset,
        method
    )
    detail <- conditionMessage(error)
    if (!is.null(conditionCall(error))) {
        detail <- paste0(detail, " [call: ", paste(
            deparse(conditionCall(error)), collapse = " "
        ), "]")
    }
    write_csv_atomic(status_row(
        "workflow_comparator", dataset, comparator_mode, "failed",
        detail, method = method
    ), file.path(out, "status.csv"))
    stop(error)
})
