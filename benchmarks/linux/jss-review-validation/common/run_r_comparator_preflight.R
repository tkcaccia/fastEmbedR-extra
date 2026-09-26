#!/usr/bin/env Rscript

script_file <- sub("^--file=", "", commandArgs(FALSE)[
    startsWith(commandArgs(FALSE), "--file=")
][[1L]])
script_dir <- dirname(normalizePath(script_file, mustWork = TRUE))
source(file.path(script_dir, "common.R"))

args <- commandArgs(trailingOnly = TRUE)
backend_arg <- args[startsWith(args, "--backend=")]
backend <- if (length(backend_arg)) {
    sub("--backend=", "", tail(backend_arg, 1L), fixed = TRUE)
} else {
    "cpu"
}
packages <- if (backend == "cuda") {
    c("fastEmbedR", "float")
} else {
    c("fastEmbedR", "float", "irlba", "Rtsne", "uwot", "umap")
}
missing <- packages[!vapply(
    packages, requireNamespace, logical(1L), quietly = TRUE
)]
if (length(missing)) {
    stop("Missing R comparators: ", paste(missing, collapse = ", "))
}

assert_matrix <- function(value, rows, columns = 2L, field = NULL) {
    value <- embedding_result_matrix(value, field)
    stopifnot(
        identical(dim(value), c(as.integer(rows), as.integer(columns))),
        all(is.finite(value))
    )
    invisible(value)
}

verify_output_contract <- function(layout) {
    directory <- tempfile("fastembedr-output-")
    dir.create(directory)
    on.exit(unlink(directory, recursive = TRUE), add = TRUE)
    rows <- seq_len(nrow(layout))
    labels <- rep(c("A", "B"), length.out = nrow(layout))
    artifacts <- write_embedding_artifacts(
        layout, labels, rows, directory
    )
    output <- utils::read.csv(artifacts[["csv"]])
    stopifnot(
        nrow(output) == nrow(layout),
        identical(output$source_row, rows),
        file.info(artifacts[["plot"]])$size > 0L
    )
}

set.seed(4L)
x <- matrix(stats::rnorm(256L * 8L), nrow = 256L)
rank <- 2L

if (backend == "cuda") {
    x_float <- float::fl(x)
    pca_fit <- fastEmbedR::pca(
        x_float, ncomp = rank, backend = "cuda", seed = 4L
    )
    stopifnot(grepl("cuda", pca_fit$backend, fixed = TRUE))
    tsne_fit <- fastEmbedR::tsne(
        x_float, perplexity = 5, backend = "cuda", seed = 4L,
        early_exaggeration_iter = 5L, n_iter = 5L,
        negative_gradient_method = "fft", auto_config = FALSE
    )
    assert_matrix(tsne_fit, nrow(x))
    assert_layout_backend(tsne_fit, "cuda")
    umap_fit <- fastEmbedR::umap(
        x_float, n_neighbors = 15L, backend = "cuda", seed = 4L
    )
    assert_matrix(umap_fit, nrow(x))
    assert_layout_backend(umap_fit, "cuda")
    verify_output_contract(embedding_result_matrix(umap_fit))
    writeLines("R CUDA comparator smoke: PASS")
    quit(save = "no", status = 0L)
}

assert_matrix(stats::prcomp(x, rank. = rank), nrow(x), rank, "x")
assert_matrix(irlba::prcomp_irlba(x, n = rank), nrow(x), rank, "x")
assert_matrix(Rtsne::Rtsne(
    x, dims = 2L, perplexity = 5, pca = TRUE, max_iter = 10L,
    num_threads = 2L, check_duplicates = FALSE, verbose = FALSE
), nrow(x), field = "Y")

fitsne_environment <- new.env(parent = globalenv())
sys.source(
    "/opt/fit-sne/bin/fast_tsne.R", envir = fitsne_environment,
    chdir = TRUE
)
assert_matrix(fitsne_environment$fftRtsne(
    x, perplexity = 5, max_iter = 10L, stop_early_exag_iter = 2L,
    mom_switch_iter = 2L, initialization = "pca", rand_seed = 4L,
    nthreads = 2L,
    fast_tsne_path = "/opt/fit-sne/bin/fast_tsne"
), nrow(x))

assert_matrix(uwot::umap(
    x, n_neighbors = 15L, init = "spectral", n_epochs = 10L,
    n_threads = 2L, n_sgd_threads = 1L, seed = 4L, verbose = FALSE
), nrow(x))
config <- umap::umap.defaults
config$n_neighbors <- 15L
config$n_components <- 2L
config$metric <- "euclidean"
config$input <- "data"
config$init <- "spectral"
config$n_epochs <- 10L
config$random_state <- 4L
config$verbose <- FALSE
assert_matrix(
    umap::umap(x, config = config, method = "naive"),
    nrow(x), field = "layout"
)
verify_output_contract(x[, 1:2, drop = FALSE])

versions <- vapply(
    packages, function(package) as.character(utils::packageVersion(package)),
    character(1L)
)
writeLines(paste(names(versions), versions, sep = "="))
writeLines("R comparator smoke: PASS")
