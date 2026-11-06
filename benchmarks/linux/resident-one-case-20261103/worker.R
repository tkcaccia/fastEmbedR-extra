#!/usr/bin/env Rscript

arguments <- commandArgs(trailingOnly = TRUE)
if (length(arguments) != 3L) {
    stop("Usage: worker.R CASE.json DATA_ROOT RESULT_DIR",
        call. = FALSE)
}
if (!requireNamespace("jsonlite", quietly = TRUE)) {
    stop("jsonlite is required.", call. = FALSE)
}
case <- jsonlite::fromJSON(arguments[[1L]])
data_root <- arguments[[2L]]
result_dir <- arguments[[3L]]
if (!identical(case$implementation, "fastEmbedR") ||
    !case$backend %in% c("cpu", "cuda") ||
    !identical(case$storage_mode, "in_memory") ||
    !identical(case$runtime_input, "resident") ||
    !identical(case$algorithm_state, "resident") ||
    !identical(case$spill, FALSE) ||
    !case$fit_scope %in% c("all_rows_optimized",
        "landmark_fit_plus_projection") ||
    !identical(case$scientific_tests, 1L) ||
    !identical(case$warmup_fits, 0L)) {
    stop("Resident one-case contract is not satisfied.",
        call. = FALSE)
}
if (case$fit_scope == "landmark_fit_plus_projection") {
    fractions <- if (identical(case$dataset, "Deep1B 10M"))
        c(0.001, 0.005, 0.01, 0.05, 0.1) else
        c(0.01, 0.05, 0.1, 0.2, 0.5)
    if (!case$method %in% c("PCA", "t-SNE", "UMAP",
        "Leiden", "Louvain") ||
        length(case$landmark_fraction) != 1L ||
        !is.numeric(case$landmark_fraction) ||
        !case$landmark_fraction %in% fractions ||
        length(case$expected_rows) != 1L ||
        !is.numeric(case$expected_rows) ||
        is.na(case$expected_rows) ||
        case$expected_rows < 2 ||
        case$expected_rows > .Machine$integer.max ||
        case$expected_rows != floor(case$expected_rows)) stop(
        "Resident landmark case has an invalid method or fraction.",
        call. = FALSE)
} else if (!is.null(case$landmark_fraction)) stop(
    "Full-data case must not declare a landmark fraction.",
    call. = FALSE)
visible <- Sys.getenv("CUDA_VISIBLE_DEVICES", unset = "")
visible_count <- if (visible %in% c("", "NoDevFiles")) 0L else
    length(strsplit(visible, ",", fixed = TRUE)[[1L]])
if (!identical(as.integer(visible_count), as.integer(case$gpus)) ||
    (case$backend == "cpu" && case$gpus != 0L) ||
    (case$backend == "cuda" && case$gpus < 1L)) {
    stop("Worker GPU visibility does not match the resident case.",
        call. = FALSE)
}
suppressPackageStartupMessages(library(fastEmbedR))

resident_dataset_files <- function() {
    c(
        COIL20 = "COIL20/COIL20_float32.RData",
        USPS = "USPS/USPS_float32.RData",
        MNIST = "MNIST/MNIST_float32.RData",
        `Fashion-MNIST` = "FashionMNIST/FashionMNIST_float32.RData",
        MetRef = "MetRef/MetRef_float32.RData",
        mass41 = "mass41/mass41_float32.RData",
        flow18 = "flow18/flow18_float32.RData",
        `ImageNet features` = "imagenet/imagenet_float32.RData",
        FlowRepository = paste0("FlowRepository_FR-FCM-ZYRM_files/",
            "van_unen_FR-FCM-ZYRM_float32.RData"),
        `Tabula Muris` = "TabulaMuris/TabulaMuris_float32.RData",
        `Macosko retina` =
            "Macosko2015_retina/Macosko2015_retina_float32.RData"
    )
}

resident_data <- function(root, dataset, request) {
    if (identical(dataset, "Deep1B 10M")) {
        worker_dir <- Sys.getenv("FASTEMBEDR_WORKER_DIR", unset = "")
        loader <- file.path(worker_dir, "deep1b_resident.R")
        if (!nzchar(worker_dir) || !file.exists(loader)) {
            stop("The reviewed Deep1B resident loader is missing.")
        }
        source(loader, local = TRUE)
        return(load_deep1b_resident(root, request))
    }
    files <- resident_dataset_files()
    if (!dataset %in% names(files)) {
        stop("Dataset has no resident loader.", call. = FALSE)
    }
    path <- file.path(root, files[[dataset]])
    if (!file.exists(path)) stop("Dataset file is missing: ", path,
        call. = FALSE)
    environment <- new.env(parent = emptyenv())
    names <- load(path, envir = environment)
    for (name in names) {
        value <- get(name, envir = environment, inherits = FALSE)
        if (is.list(value) && !is.null(value$data)) {
            value <- value$data
        }
        if (inherits(value, c("massive_matrix", "DelayedMatrix",
            "HDF5Matrix", "big.matrix", "ff"))) {
            stop("File-backed input is forbidden on HPC.",
                call. = FALSE)
        }
        if (!is.matrix(value) && !inherits(value, "float32")) next
        if (nrow(value) < 2L || ncol(value) < 1L) {
            stop("Invalid resident dataset dimensions.",
                call. = FALSE)
        }
        return(value)
    }
    stop("No resident numeric matrix found in dataset.",
        call. = FALSE)
}

resident_fit <- function(x, request) {
    cores <- as.integer(request$cores)
    seed <- as.integer(request$seed)
    dimensions <- as.integer(request$dimensions)
    backend <- request$backend
    devices <- if (request$gpus > 1L) {
        seq.int(0L, request$gpus - 1L)
    } else NULL
    switch(request$method,
        PCA = fastEmbedR::pca(x, ncomp = dimensions,
            backend = backend, n.cores = cores, seed = seed,
            massive = "off", devices = devices,
            landmarks = if (request$fit_scope ==
                "landmark_fit_plus_projection")
                request$landmark_fraction else FALSE),
        `t-SNE` = fastEmbedR::tsne(x,
            n_components = dimensions, backend = backend,
            n.cores = cores, seed = seed, massive = "off",
            devices = devices,
            landmarks = if (request$fit_scope ==
                "landmark_fit_plus_projection")
                request$landmark_fraction else FALSE,
            perplexity = if (is.null(request$perplexity))
                30 else request$perplexity,
            affinity_k = request$affinity_k,
            early_exaggeration_iter =
                if (is.null(request$early_exaggeration_iter))
                    250L else request$early_exaggeration_iter,
            n_iter = if (is.null(request$n_iter))
                500L else request$n_iter),
        UMAP = fastEmbedR::umap(x, n_neighbors = 30L,
            n_components = dimensions, backend = backend,
            n.cores = cores, seed = seed, massive = "off",
            devices = devices,
            landmarks = if (request$fit_scope ==
                "landmark_fit_plus_projection")
                request$landmark_fraction else FALSE),
        Leiden = resident_cluster(x, "leiden", cores, seed,
            backend, devices, request$landmark_fraction),
        Louvain = resident_cluster(x, "louvain", cores, seed,
            backend, devices, request$landmark_fraction),
        stop("Method has no reviewed resident worker.",
            call. = FALSE))
}

resident_cluster <- function(x, method, cores, seed,
                             backend, devices, landmarks) {
    if (!is.null(landmarks)) return(fastEmbedR::graph_cluster(
        x, landmarks = landmarks, method = method,
        k = 30L, vote_k = 30L, backend = backend,
        n.cores = cores, n_runs = 1L, devices = devices,
        parallel.mode = if (backend == "cpu") "fit" else "restarts",
        seed = seed))
    graph <- fastEmbedR::knn_graph(x, k = 30L,
        backend = backend, n.cores = cores)
    fastEmbedR::graph_cluster(graph, method = method,
        backend = backend,
        n.cores = if (backend == "cpu") cores else 1L,
        n_runs = 1L, devices = devices,
        parallel.mode = if (backend == "cpu") "fit" else "restarts",
        seed = seed)
}

resident_result_backend <- function(fit, method) {
    if (method %in% c("t-SNE", "UMAP")) {
        return(fit$parameters$backend)
    }
    fit$backend
}

resident_result_devices <- function(fit, method) {
    if (method %in% c("t-SNE", "UMAP")) {
        return(fit$parameters$gpu_devices)
    }
    fit$gpu_devices
}

resident_result_rows <- function(fit, method) {
    switch(method,
        PCA = nrow(fit$scores),
        `t-SNE` = nrow(fit$layout),
        UMAP = nrow(fit$layout),
        Leiden = length(fit$membership),
        Louvain = length(fit$membership))
}

load_started <- proc.time()[[3L]]
input <- resident_data(data_root, case$dataset, case)
if (case$fit_scope == "landmark_fit_plus_projection") {
    selected <- ceiling(nrow(input) * case$landmark_fraction)
    minimum <- switch(case$method,
        PCA = case$dimensions + 1L,
        `t-SNE` = {
            perplexity <- if (is.null(case$perplexity))
                30 else case$perplexity
            width <- if (is.null(case$affinity_k))
                ceiling(perplexity) else case$affinity_k
            max(ceiling(3 * perplexity) + 1L, width + 1L)
        },
        UMAP = 31L,
        Leiden = 31L,
        Louvain = 31L)
    if (nrow(input) != case$expected_rows ||
        selected < minimum || selected >= nrow(input)) stop(
        "Resident landmark count cannot support fit controls.",
        call. = FALSE)
}
load_elapsed <- unname(proc.time()[[3L]] - load_started)
started <- proc.time()[[3L]]
fit <- resident_fit(input, case)
elapsed <- unname(proc.time()[[3L]] - started)
if (inherits(fit, "massive_matrix") ||
    (is.list(fit) && !is.null(fit$mode) &&
     identical(fit$mode, "out_of_core"))) {
    stop("File-backed result is forbidden on HPC.", call. = FALSE)
}
observed_backend <- resident_result_backend(fit, case$method)
backend_ok <- if (case$backend == "cpu") {
    is.character(observed_backend) && length(observed_backend) == 1L &&
        startsWith(observed_backend, "cpu")
} else identical(observed_backend, "cuda")
if (!backend_ok) stop("Observed backend differs from the case request.",
    call. = FALSE)
expected_devices <- if (case$gpus > 1L)
    seq.int(0L, as.integer(case$gpus) - 1L) else integer()
observed_devices <- resident_result_devices(fit, case$method)
if (case$gpus > 1L &&
    !identical(as.integer(observed_devices), expected_devices)) {
    stop("Coordinated GPU fit did not report every requested device.",
        call. = FALSE)
}
if (!identical(as.integer(resident_result_rows(fit, case$method)),
        as.integer(nrow(input)))) stop(
    "Resident result has the wrong row count.", call. = FALSE)
if (case$fit_scope == "landmark_fit_plus_projection") {
    indices <- if (case$method %in% c("Leiden", "Louvain"))
        fit$selection$indices else fit$landmarks$indices
    count <- length(indices)
    valid <- is.integer(indices) && count >= 2L &&
        count < nrow(input) && !anyNA(indices) &&
        identical(indices, sort(unique(indices)))
    if (case$method == "PCA") valid <- valid &&
        identical(fit$fit_scope, case$fit_scope) &&
        nrow(fit$scores_reference) == count
    else if (case$method %in% c("Leiden", "Louvain"))
        valid <- valid && identical(fit$fit_scope, case$fit_scope) &&
            length(fit$reference_fit$membership) == count &&
            identical(fit$membership[indices],
                fit$reference_fit$membership)
    else valid <- valid && isTRUE(fit$parameters$landmark) &&
        nrow(fit$landmarks$layout) == count &&
        !is.null(fit$landmarks$reference_fit)
    if (!isTRUE(valid)) stop(
        "Resident landmark fit or projection was not observed.",
        call. = FALSE)
}
write_started <- proc.time()[[3L]]
saveRDS(fit, file.path(result_dir, "fit.rds"), compress = "xz")
write_elapsed <- unname(proc.time()[[3L]] - write_started)
summary <- list(
    case_id = case$case_id,
    dataset = case$dataset,
    method = case$method,
    backend = case$backend,
    observed_backend = observed_backend,
    gpu_devices = observed_devices,
    requested_cores = case$cores,
    configured_fit_cpu_workers = if (case$backend == "cuda" &&
        case$method %in% c("Leiden", "Louvain")) 1L else case$cores,
    requested_gpus = case$gpus,
    seed = case$seed,
    repetition = case$repetition,
    dimensions = case$dimensions,
    perplexity = if (case$method == "t-SNE")
        fit$parameters$perplexity else NULL,
    affinity_support_k = if (case$method == "t-SNE")
        fit$parameters$affinity_support_k else NULL,
    affinity_support = if (case$method == "t-SNE")
        fit$parameters$affinity_support else NULL,
    route_id = case$route_id,
    storage_mode = "in_memory",
    fit_scope = case$fit_scope,
    landmark_fraction = case$landmark_fraction,
    n_landmarks = if (case$fit_scope ==
        "landmark_fit_plus_projection")
        if (case$method %in% c("Leiden", "Louvain"))
            length(fit$selection$indices) else
            length(fit$landmarks$indices) else NULL,
    graph_assembly_backend = fit$graph_assembly_backend,
    vote_backend = fit$vote_backend,
    projection_backend = if (case$method == "PCA")
        fit$projection_backend else if (case$method == "t-SNE")
        fit$parameters$transform_backend else NULL,
    projection_nn_backend = if (case$method == "UMAP")
        fit$parameters$projection_nn_backend else NULL,
    landmark_refinement_backend = if (case$method == "UMAP")
        fit$parameters$landmark_refinement_backend else NULL,
    n_rows = nrow(input),
    n_columns = ncol(input),
    input_object_bytes = as.numeric(object.size(input)),
    load_elapsed_sec = load_elapsed,
    elapsed_sec = elapsed,
    write_elapsed_sec = write_elapsed,
    total_elapsed_sec = load_elapsed + elapsed + write_elapsed,
    result_class = class(fit),
    result_file = "fit.rds"
)
jsonlite::write_json(summary,
    file.path(result_dir, "metrics.json"),
    auto_unbox = TRUE, pretty = TRUE, null = "null")
