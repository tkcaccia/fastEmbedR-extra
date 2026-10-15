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
timeout_seconds <- as.numeric(arg_value("timeout-seconds", 7200))
deadline_epoch <- as.numeric(arg_value("deadline-epoch", Inf))
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
if (!is.finite(timeout_seconds) || timeout_seconds <= 0) {
    stop("Timeout must be positive.", call. = FALSE)
}

can_fit_repetitions <- function(observed, count, remaining) {
    reserve <- min(300, timeout_seconds * 0.05)
    remaining >= reserve + 1.2 * max(observed) * count
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
        fastembedr_umap_binary = "fastEmbedR",
        irlba_pca = "irlba", rtsne = "Rtsne",
        uwot = "uwot", uwot_fast_sgd = "uwot", r_umap = "umap",
        NA_character_
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

fitsne_grid_policy <- function(n) {
    target <- if (n >= 40000L) 256L else 128L
    minimum <- as.integer(ceiling(target / 3))
    allowed <- c(25L, 36L, 50L, 55L, 60L, 65L, 70L, 75L,
        80L, 85L, 90L, 96L, 100L, 110L, 120L, 130L,
        140L, 150L, 175L, 200L)
    boxes <- min(allowed[allowed >= minimum])
    list(target = target, minimum = minimum, boxes = boxes)
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
        fastembedr_umap_binary = fit$parameters$learning_rate %||% 1,
        uwot = 1,
        uwot_fast_sgd = 1,
        r_umap = 1,
        NA_real_
    )
    row$epochs_value <- switch(
        name,
        fastembedr_umap = fit$parameters$epochs %||% umap_epoch_policy(n),
        fastembedr_umap_binary = fit$parameters$epochs %||%
            umap_epoch_policy(n),
        uwot = umap_epoch_policy(n),
        uwot_fast_sgd = umap_epoch_policy(n),
        r_umap = 200L,
        NA_integer_
    )
    row$min_dist_value <- if (name %in% c("fastembedr_umap",
            "fastembedr_umap_binary")) {
        fit$parameters$min_dist %||% 0.01
    } else if (family == "umap") {
        as.numeric(row$min_dist_policy)
    } else NA_real_
    row$graph_mode <- if (name %in% c("fastembedr_umap",
            "fastembedr_umap_binary")) {
        fit$parameters$graph_mode
    } else if (family == "umap") "fuzzy" else NA_character_
    if (name == "fitsne" && n_components == 3L) {
        row$optimizer <- "barnes_hut_theta_0.2"
    }
    if (name == "fastembedr_tsne") {
        row$optimizer <- fit$parameters$repulsion %||% NA_character_
    }
    row$initialization_engine <- if (name == "rtsne") {
        "irlba_prcomp_irlba"
    } else NA_character_
    row$initialization_engine_version <- if (name == "rtsne") {
        as.character(utils::packageVersion("irlba"))
    } else NA_character_
    row$initialization_max_sd <- if (name == "rtsne") {
        1e-4
    } else NA_real_
    row$input_normalization <- if (name == "rtsne") {
        "Rtsne_center_maxabs"
    } else NA_character_
    row$fft_grid_policy <- if (name == "fitsne" &&
            n_components == 2L) {
        "minimum_cells_cpu_policy"
    } else if (name == "fastembedr_tsne") {
        "native_reported"
    } else NA_character_
    row$fft_grid_nodes_per_axis <- if (name == "fastembedr_tsne") {
        fit$parameters$fft_grid_size %||% NA_integer_
    } else NA_integer_
    row$fft_grid_min_boxes_per_axis <- if (name == "fitsne" &&
            n_components == 2L) {
        fitsne_grid_policy(n)$boxes
    } else NA_integer_
    row$fft_grid_min_nodes_per_axis <- if (name == "fitsne" &&
            n_components == 2L) {
        3L * fitsne_grid_policy(n)$boxes
    } else NA_integer_
    row$fft_grid_interpolation_points <- if (name == "fitsne" &&
            n_components == 2L) 3L else NA_integer_
    row$fft_grid_padded_axis_min <- if (name == "fastembedr_tsne" &&
            is.finite(row$fft_grid_nodes_per_axis)) {
        2L * row$fft_grid_nodes_per_axis
    } else if (name == "fitsne" && n_components == 2L) {
        6L * fitsne_grid_policy(n)$boxes
    } else NA_integer_
    row$fft_grid_intervals_per_integer <- if (name == "fitsne" &&
            n_components == 2L) 1e6 else NA_real_
    row[setdiff(names(row), c("method", "family"))]
}

load_benchmark_data <- function() {
    shared <- readRDS(file.path(input_root, dataset, "matched_inputs.rds"))
    loaded <- load_dataset(data_root, dataset)
    if (full_dataset) {
        if (nrow(loaded$data) != shared$source_n) {
            stop("Full comparator source row count changed.")
        }
        shared$quality_rows <- shared$rows[shared$quality_rows]
        shared$rows <- seq_len(shared$source_n)
        shared$labels <- loaded$labels
    }
    selected <- if (full_dataset) loaded$data else {
        loaded$data[shared$rows, , drop = FALSE]
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
    stop("Unsupported PCA comparator: ", name, call. = FALSE)
}

rtsne_pca_initialization <- function(x) {
    if (min(dim(x)) <= n_components) {
        stop("PCA initialization needs more input dimensions than output.")
    }
    scores <- irlba::prcomp_irlba(
        x, n = n_components, center = TRUE, scale. = FALSE
    )$x
    init <- sweep(scores, 2L, colMeans(scores), "-")
    scale <- max(apply(init, 2L, stats::sd))
    if (!is.finite(scale) || scale <= 0) {
        stop("PCA initialization has no finite variation.")
    }
    init <- init * (1e-4 / scale)
    if (any(!is.finite(init))) {
        stop("PCA initialization contains non-finite coordinates.")
    }
    init
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
        init <- rtsne_pca_initialization(x)
        return(Rtsne::Rtsne(
            x, dims = n_components, perplexity = perplexity,
            pca = FALSE, partial_pca = FALSE,
            initial_dims = ncol(x), Y_init = init,
            normalize = TRUE, is_distance = FALSE,
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
    grid <- fitsne_grid_policy(nrow(x))
    fitsne$fun(
        x, dims = n_components, perplexity = perplexity,
        theta = if (n_components == 3L) 0.2 else 0.5,
        fft_not_bh = n_components == 2L,
        max_iter = tsne_total_iterations,
        initialization = "pca", stop_early_exag_iter = 250L,
        exaggeration_factor = 12, learning_rate = "auto",
        momentum = 0.5, final_momentum = 0.8,
        nterms = 3L, min_num_intervals = grid$minimum,
        intervals_per_integer = 1e6,
        rand_seed = seed, nthreads = threads,
        fast_tsne_path = fitsne$executable
    )
}

fit_umap <- function(name, x, neighbors) {
    if (name %in% c("fastembedr_umap", "fastembedr_umap_binary")) {
        mode <- if (name == "fastembedr_umap_binary") "binary" else "fuzzy"
        fit <- fastEmbedR::umap(
            x, n_neighbors = neighbors, n_components = n_components,
            graph_mode = mode,
            backend = backend, n.cores = threads, seed = seed
        )
        if (!identical(fit$parameters$graph_mode, mode)) {
            stop("UMAP graph mode changed during fitting.", call. = FALSE)
        }
        return(fit)
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
    if (n_components == 3L && method == "fastembedr_tsne") {
        expected <- switch(backend,
            cpu = "fft_grid_3d",
            cuda = "fft_grid_3d_cuda_cufft",
            metal = "fft_grid_3d_metal"
        )
        observed <- fit$parameters$repulsion %||% ""
        if (!identical(observed, expected)) {
            stop("3D t-SNE did not use the requested FFT backend: ",
                 observed, call. = FALSE)
        }
    }
}

extract_layout <- function(fit, family) {
    if (family == "pca") {
        value <- fit$scores %||% fit$x
        return(as_double_matrix(value))
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
                          output_dir = output_root,
                          warmup_excluded = TRUE) {
    family <- method_family(method)
    layout <- extract_layout(fit, family)
    rows <- benchmark$shared$quality_rows
    quality <- if (family == "pca" || defer_quality) {
        data.frame(
            trustworthiness = NA_real_, preserve_at_30 = NA_real_,
            label_knn_accuracy = NA_real_, sampled_kl = NA_real_,
            neighborhood_quality_score = NA_real_
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
    timing_scope <- if (method == "rtsne") {
        "R_workflow_fit"
    } else "R_public_fit"
    timing_interface <- if (method == "rtsne") {
        "irlba_PCA_init_plus_Rtsne"
    } else "R_public_function"
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
        pca_rank = if (family == "pca") {
            ncol(fit$scores %||% fit$x)
        } else NA_integer_,
        language = "R", backend = result_backend,
        timing_scope = timing_scope,
        timing_boundary = timing_boundary,
        timing_interface = timing_interface,
        timing_eligible = warmup_excluded &&
            length(elapsed) == timing_reps,
        seed = seed, timing_reps = length(elapsed),
        timing_reps_requested = timing_reps,
        warmup_count = as.integer(warmup_excluded),
        warmup_excluded = warmup_excluded,
        timing_policy = if (!warmup_excluded) {
            "single_fit_budget"
        } else if (length(elapsed) < timing_reps) {
            "partial_budget"
        } else {
            "complete_repeated"
        },
        method_timeout_seconds = timeout_seconds,
        quality_sample_n = length(rows),
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
        warmup_count = as.integer(warmup_excluded),
        warmup_excluded = warmup_excluded,
        timing_reps_requested = timing_reps,
        timing_scope = timing_scope,
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
        file.path(out, "embedding.csv.gz")
    )
    write_csv_atomic(status_row(
        "workflow_comparator", dataset, comparator_mode, "success",
        method = method
    ), file.path(out, "status.csv"))
}

timed_fits <- function(input, rank, fitsne) {
    pilot_time <- system.time({
        pilot <- fit_once(method, input, 30, 30L, rank, fitsne)
    })[["elapsed"]]
    assert_fastembedr_backend(pilot)
    message("Pilot completed: ", dataset, "/", method, " in ",
        format(pilot_time, digits = 6), " seconds")
    stage_names <- names(stage_seconds(pilot))
    remaining <- deadline_epoch - as.numeric(Sys.time())
    if (!can_fit_repetitions(pilot_time, timing_reps, remaining)) {
        stages <- matrix(stage_seconds(pilot), nrow = 1L,
            dimnames = list(NULL, stage_names))
        message("Skipping timing repeats: method time budget.")
        return(list(fit = pilot, elapsed = pilot_time,
            stages = stages, warmup_excluded = FALSE))
    }
    rm(pilot)
    if (full_dataset) gc()
    elapsed <- numeric()
    stages <- matrix(NA_real_, nrow = 0L, ncol = 4L,
        dimnames = list(NULL, stage_names))
    fit <- NULL
    for (index in seq_len(timing_reps)) {
        if (index > 1L && !can_fit_repetitions(
                c(pilot_time, elapsed), 1L,
                deadline_epoch - as.numeric(Sys.time()))) break
        if (full_dataset) {
            fit <- NULL
            gc()
        }
        timing <- system.time({
            fit <- fit_once(method, input, 30, 30L, rank, fitsne)
        })[["elapsed"]]
        assert_fastembedr_backend(fit)
        elapsed <- c(elapsed, timing)
        stages <- rbind(stages, stage_seconds(fit))
        message("Timing repetition ", index, "/", timing_reps,
            ": ", format(timing, digits = 6), " seconds")
    }
    list(fit = fit, elapsed = elapsed, stages = stages,
        warmup_excluded = TRUE)
}

run <- function() {
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
    timed <- timed_fits(input, rank, fitsne)
    write_outputs(timed$fit, timed$elapsed, benchmark, timed$stages,
        warmup_excluded = timed$warmup_excluded)
}

run_smoke <- function() {
    suppressPackageStartupMessages(library(fastEmbedR))
    suppressPackageStartupMessages(library(float))
    set.seed(seed)
    x <- matrix(stats::rnorm(256L * 16L), nrow = 256L)
    input <- if (startsWith(method, "fastembedr_")) float::fl(x) else x
    fitsne <- if (method == "fitsne") load_fitsne() else NULL
    rank <- if (method_family(method) == "pca") 5L else 2L
    fit <- fit_once(method, input, 5, 15L, rank, fitsne)
    assert_fastembedr_backend(fit)
    layout <- extract_layout(fit, method_family(method))
    expected <- if (method_family(method) == "pca") rank else n_components
    if (!identical(dim(layout), c(256L, expected)) ||
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
    if (method_family(method) == "pca") {
        path <- file.path(smoke_dir, "workflow_comparators",
            paste0("r_", backend), dataset, method, "result.csv")
        if (utils::read.csv(path)$pca_rank[[1L]] != rank) {
            stop("PCA result did not record the fitted rank.")
        }
    }
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
