args <- commandArgs(trailingOnly = TRUE)
if (length(args) != 3L) stop(
    "usage: Rscript audit_unified_pilot_v1.R WORK INPUT SOURCE")
work <- normalizePath(args[[1L]], mustWork = TRUE)
input <- normalizePath(args[[2L]], mustWork = TRUE)
source <- normalizePath(args[[3L]], mustWork = TRUE)
root <- "/Users/silvanopiazza/Documents/Stefano/"
if (!all(startsWith(c(work, input, source), root))) stop(
    "Mac benchmark paths must stay under Stefano.")
sha256 <- function(path) {
    value <- system2("shasum", c("-a", "256", shQuote(path)),
        stdout = TRUE, stderr = TRUE)
    if (length(value) != 1L || !grepl("^[0-9a-f]{64} ", value))
        stop("Cannot verify SHA-256: ", path)
    substr(value, 1L, 64L)
}
exit <- jsonlite::fromJSON(file.path(work, "exit.json"))
metrics <- read.csv(file.path(work, "metrics.csv"),
    stringsAsFactors = FALSE)
archive <- file.path(source, "source.tar.xz")
installed <- file.path(source, "library/fastEmbedR/libs/fastEmbedR.so")
built <- file.path(source, "source/src/fastEmbedR.so")
if (!identical(exit$status, "completed") || exit$exit_code != 0L ||
    isTRUE(exit$timed_out) ||
    !identical(sha256(input), exit$input_sha256) ||
    !identical(sha256(archive), exit$package_sha256) ||
    !identical(sha256(installed), sha256(built))) stop(
    "Pilot status or source/input identity failed.")
if (!nrow(metrics) || anyDuplicated(metrics$case) ||
    any(metrics$status != "ok")) stop("Pilot cases are incomplete.")
rows <- NA_integer_
for (case in metrics$case) {
    fit <- readRDS(file.path(work, paste0(case, ".rds")))
    backend <- if (grepl("_metal", case, fixed = TRUE))
        "metal" else "cpu"
    observed <- if (startsWith(case, "pca_")) fit$backend else
        if (startsWith(case, "louvain_") ||
            startsWith(case, "leiden_")) fit$backend else
            fit$parameters$backend
    if (length(observed) != 1L ||
        (backend == "metal" && observed != "metal") ||
        (backend == "cpu" && !startsWith(observed, "cpu"))) stop(
        "Effective backend mismatch: ", case)
    count <- if (startsWith(case, "pca_")) nrow(fit$scores) else
        if (startsWith(case, "louvain_") ||
            startsWith(case, "leiden_")) length(fit$membership) else
            nrow(fit$layout)
    if (is.na(rows)) rows <- count
    if (count != rows) stop("Output row count mismatch: ", case)
    if (grepl("_2d", case, fixed = TRUE) &&
        ncol(fit$layout) != 2L) stop("Wrong 2D output: ", case)
    if (grepl("_3d", case, fixed = TRUE) &&
        ncol(fit$layout) != 3L) stop("Wrong 3D output: ", case)
    if (backend == "metal" && startsWith(case, "tsne_") &&
        fit$parameters$nn_backend != "metal") stop(
        "Metal t-SNE KNN fell back: ", case)
    if (backend == "metal" && startsWith(case, "umap_") &&
        (fit$parameters$nn_backend != "metal" ||
         fit$parameters$optimizer_backend != "metal")) stop(
        "Metal UMAP stage fell back: ", case)
    if (case == "umap_cpu4_2d" &&
        fit$parameters$n.cores_effective != 4L) stop(
        "Four-core UMAP did not use four effective workers.")
}
report <- list(status = "passed", cases = nrow(metrics),
    rows = rows, source_archive_sha256 = sha256(archive),
    installed_dll_sha256 = sha256(installed),
    input_sha256 = sha256(input),
    cluster_effective_worker_count = "not exposed by pilot result")
cat(jsonlite::toJSON(report, auto_unbox = TRUE, pretty = TRUE), "\n")
