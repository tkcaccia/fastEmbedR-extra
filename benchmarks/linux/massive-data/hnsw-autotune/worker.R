#!/usr/bin/env Rscript

args <- commandArgs(trailingOnly = TRUE)
if (length(args) != 3L) {
    stop("Usage: worker.R truth|sweep CAMPAIGN TASK_ID")
}
phase <- match.arg(args[[1L]], c("truth", "sweep"))
root <- normalizePath(args[[2L]], mustWork = TRUE)
task <- as.integer(args[[3L]])
cases <- read.delim(file.path(root, paste0(phase, "_cases.tsv")),
    stringsAsFactors = FALSE)
if (is.na(task) || task < 0L || task >= nrow(cases)) {
    stop("Invalid array task ID")
}
worker_started <- unname(proc.time()[[3L]])
case <- cases[task + 1L, , drop = FALSE]
threads <- as.integer(Sys.getenv("SLURM_CPUS_PER_TASK", "4"))
data_root <- Sys.getenv("BIGANN_DATA_ROOT",
    "/scratch/firenze/NN/Data/BigANN")
input <- file.path(data_root, case$dataset, "1000000000",
    "base.1000000000.fbin")
if (utils::packageVersion("faissR") < package_version("0.99.50")) {
    stop("This sweep requires faissR >= 0.99.50")
}
source <- fastEmbedR::massive_matrix(input)
if (source$nrow != 1e9 ||
    source$ncol != if (case$dataset == "deep") 96 else 100) {
    stop("Completed BigANN input has unexpected dimensions")
}
first_row <- if ("first_row" %in% names(case)) {
    as.integer(case$first_row)
} else 1L
view <- fastEmbedR:::massive_matrix_rows(source, first_row, case$rows)
if (case$scope == "fresh5m" &&
    utils::packageVersion("faissR") < package_version("0.99.52")) {
    stop("The 5M screen requires faissR >= 0.99.52")
}
truth_file <- file.path(root, "truth", paste0(case$dataset, "_",
    case$scope, ".rds"))
dir.create(dirname(truth_file), recursive = TRUE, showWarnings = FALSE)
clock <- function() unname(proc.time()[[3L]])
rss_peak <- function() {
    line <- grep("^VmHWM:", readLines("/proc/self/status"), value = TRUE)
    if (length(line)) as.numeric(gsub("[^0-9]", "", line)) * 1024 else NA_real_
}
hash_dll <- function(package) {
    path <- system.file("libs", paste0(package, .Platform$dynlib.ext),
        package = package)
    if (!nzchar(path)) stop("Package shared library is missing")
    sub(" .*", "", system2("sha256sum", path, stdout = TRUE))
}
faissr_dll <- hash_dll("faissR")
fastembedr_dll <- hash_dll("fastEmbedR")
image_sha <- strsplit(readLines(file.path(root, "source.sha256"),
    n = 1L), " +")[[1L]][[1L]]
if (phase == "truth") {
    n_queries <- if ("query_count" %in% names(case)) {
        as.integer(case$query_count)
    } else 2048L
    offset <- if (case$scope == "scale") 20000L else 0L
    seed <- 1701L +
        (if (case$dataset == "turing") 1L else 0L) +
        (if (case$scope == "scale") 10L else 0L)
    set.seed(seed)
    rows <- as.integer(sample.int(case$rows - offset,
        n_queries, replace = FALSE) + offset)
    started <- clock()
    exact_k <- if (case$scope %in% c("fresh5m", "refine5m") ||
        startsWith(case$scope, "rep_") ||
        startsWith(case$scope, "large_")) {
        31L
    } else 51L
    exact <- fastEmbedR:::massive_exact_sample_batch_cpp(
        view, view, rows, exact_k, 20000L, threads, TRUE)
    if (!isTRUE(exact$exact) ||
        !identical(exact$backend_used, "native_cpu_exact_stream")) {
        stop("Exact ground-truth backend changed")
    }
    evidence <- list(rows = rows, indices = exact$indices,
        distances = exact$distances, input = input,
        input_bytes = file.info(input)$size, fit_rows = case$rows,
        first_row = first_row,
        split = rep(c("tune", "holdout"), each = n_queries / 2L),
        seed = seed, image_sha256 = image_sha,
        faissr_dll_sha256 = faissr_dll,
        fastembedr_dll_sha256 = fastembedr_dll,
        elapsed_seconds = clock() - started)
    saveRDS(evidence, truth_file)
    ratio <- exact$distances[, 30L] /
        pmax(exact$distances[, 1L], .Machine$double.eps)
    geometry <- data.frame(dataset = case$dataset, scope = case$scope,
        query_count = n_queries,
        median_d30_over_d1 = median(ratio),
        q10_d30_over_d1 = unname(quantile(ratio, 0.1)),
        q90_d30_over_d1 = unname(quantile(ratio, 0.9)))
    write.csv(geometry, file.path(root, "truth", paste0(
        case$dataset, "_", case$scope, "_geometry.csv")),
        row.names = FALSE)
    write.csv(data.frame(dataset = case$dataset, scope = case$scope,
        query_n = n_queries, exact_seconds = evidence$elapsed_seconds,
        worker_elapsed_seconds = clock() - worker_started,
        rss_peak_bytes = rss_peak()),
        file.path(root, "truth", paste0(case$dataset, "_",
            case$scope, "_timing.csv")), row.names = FALSE)
    cat("Exact truth:", case$dataset, case$scope,
        "seconds=", evidence$elapsed_seconds, "\n")
    quit(save = "no")
}

truth <- readRDS(truth_file)
if (!identical(truth$input, input) || truth$fit_rows != case$rows ||
    !identical(if (is.null(truth$first_row)) 1L else
        truth$first_row, first_row) ||
    truth$input_bytes != file.info(input)$size ||
    truth$image_sha256 != image_sha ||
    truth$faissr_dll_sha256 != faissr_dll ||
    truth$fastembedr_dll_sha256 != fastembedr_dll) {
    stop("Ground truth belongs to a different input")
}
rows <- truth$rows
query <- do.call(rbind, lapply(rows, function(i) {
    fastEmbedR::massive_read_rows(view, first = i, n = 1L)
}))
query_float <- float::fl(query)
grid <- if (case$scope == "fresh5m" ||
    startsWith(case$scope, "rep_") ||
    startsWith(case$scope, "large_")) {
    data.frame(k = as.integer(case$k), ef = as.integer(case$ef_search))
} else if (case$scope == "refine5m") {
    data.frame(k = 30L, ef = c(45L, 60L, 80L, 120L, 150L, 240L))
} else expand.grid(k = c(15L, 30L, 50L),
    ef = c(45L, 60L, 80L, 120L, 150L, 240L, 480L, 960L))
grid <- grid[grid$ef >= grid$k + 1L, , drop = FALSE]
choices <- lapply(seq_len(nrow(grid)), function(i) list(
    indices = matrix(integer(), nrow = length(rows)),
    distances = matrix(numeric(), nrow = length(rows))))
merge_candidates <- function(old, found, offset, keep) {
    ids <- cbind(old$indices, found$indices + offset)
    distances <- cbind(old$distances, found$distances)
    next_ids <- matrix(0L, nrow(ids), keep)
    next_distances <- matrix(Inf, nrow(ids), keep)
    for (i in seq_len(nrow(ids))) {
        valid <- which(ids[i, ] > 0L & is.finite(distances[i, ]))
        sorted <- valid[order(distances[i, valid], ids[i, valid])]
        selected <- head(sorted, keep)
        length_out <- length(selected)
        next_ids[i, seq_len(length_out)] <- ids[i, selected]
        next_distances[i, seq_len(length_out)] <-
            distances[i, selected]
    }
    list(indices = next_ids, distances = next_distances)
}
search_seconds <- numeric(nrow(grid))
collect_seconds <- numeric(nrow(grid))
timing_reps <- if (case$scope == "pilot") 25L else 3L
timing_seconds <- matrix(0, nrow(grid), timing_reps)
if (case$scope == "pilot") {
    timing_query <- query_float
} else {
    timing_rows <- round(seq(1, length(rows), length.out = 128L))
    timing_query <- query_float[timing_rows, , drop = FALSE]
}
build_seconds <- 0
for (first in seq.int(1L, case$rows, by = case$shard_rows)) {
    count <- min(case$shard_rows, case$rows - first + 1L)
    shard <- fastEmbedR:::massive_matrix_rows(view, first, count)
    reference <- fastEmbedR:::massive_read_rows_cpp(shard, 1L,
        count, 4 * count * source$ncol, TRUE)
    started <- clock()
    index <- faissR:::nn_faiss_hnsw_index_build_float32_cpp(
        reference, case$m, case$ef_construction, 120L,
        "euclidean", "euclidean", threads)
    build_seconds <- build_seconds + clock() - started
    set.seed(2000L + first)
    for (j in sample.int(nrow(grid))) {
        k <- grid$k[[j]]
        ef <- grid$ef[[j]]
        invisible(faissR:::nn_faiss_hnsw_index_search_float32_cpp(
            index, timing_query[1:2, , drop = FALSE],
            k + 1L, FALSE, ef, threads, "double"))
        started <- clock()
        found <- faissR:::nn_faiss_hnsw_index_search_float32_cpp(
            index, query_float, k + 1L, FALSE, ef,
            threads, "double")
        search_seconds[[j]] <- search_seconds[[j]] + clock() - started
        if (!isTRUE(found$index_reused) ||
            found$ef_search != ef ||
            found$m != case$m ||
            found$ef_construction != case$ef_construction) {
            stop("Persistent FAISS query path changed")
        }
        started <- clock()
        choices[[j]] <- merge_candidates(choices[[j]], found,
            first - 1L, k + 1L)
        collect_seconds[[j]] <- collect_seconds[[j]] + clock() - started
        for (rep in seq_len(ncol(timing_seconds))) {
            started <- clock()
            invisible(faissR:::nn_faiss_hnsw_index_search_float32_cpp(
                index, timing_query, k + 1L, FALSE,
                ef, threads, "double"))
            timing_seconds[j, rep] <- timing_seconds[j, rep] +
                clock() - started
        }
    }
    rm(index, reference, found)
    invisible(gc(verbose = FALSE))
    if (first %% (10L * case$shard_rows) == 1L) {
        message("Indexed through row ", first + count - 1L)
    }
}

select_neighbors <- function(j, k) {
    t(vapply(seq_along(rows), function(i) {
        ids <- choices[[j]]$indices[i, ]
        distances <- choices[[j]]$distances[i, ]
        valid <- is.finite(distances) & ids > 0L & ids != rows[[i]]
        ranked <- order(distances[valid], ids[valid])
        if (length(ranked) < k) stop("Insufficient ANN candidates")
        ids[valid][ranked[seq_len(k)]]
    }, integer(k)))
}
result <- list()
per_query <- list()
cpu_model <- grep("^model name", readLines("/proc/cpuinfo"), value = TRUE)
cpu_model <- if (length(cpu_model)) sub("^.*: *", "", cpu_model[[1L]]) else ""
affinity <- grep("^Cpus_allowed_list:",
    readLines("/proc/self/status"), value = TRUE)
affinity <- if (length(affinity)) sub("^.*: *", "", affinity[[1L]]) else ""
faiss_info <- faissR:::faiss_info_json_cpp()
for (j in seq_len(nrow(grid))) {
    k <- grid$k[[j]]
    ef <- grid$ef[[j]]
    started <- clock()
    observed <- select_neighbors(j, k)
    merge_seconds <- clock() - started
    recall <- vapply(seq_along(rows), function(i) {
        sum(observed[i, ] %in% truth$indices[i, seq_len(k)]) / k
    }, numeric(1))
    ties <- abs(truth$distances[, k + 1L] -
        truth$distances[, k]) <= 1e-6 *
        pmax(1, truth$distances[, k])
    if (k == 30L) {
        per_query[[length(per_query) + 1L]] <- data.frame(
            dataset = case$dataset, scope = case$scope,
            fit_rows = case$rows, shard_rows = case$shard_rows,
            m = case$m, ef_construction = case$ef_construction,
            ef_search = ef, row = rows,
            split = truth$split, recall = recall,
            boundary_tie = ties)
    }
    policy <- faissR:::nn_tune_faiss_hnsw_cpp(
        as.integer(case$shard_rows), as.integer(source$ncol), k,
        "euclidean", 0.99)
    for (split in c("tune", "holdout")) {
        selected <- recall[truth$split == split]
        result[[length(result) + 1L]] <- data.frame(
            dataset = case$dataset, scope = case$scope,
            fit_rows = case$rows, columns = source$ncol,
            shard_rows = case$shard_rows, k = k, m = case$m,
            ef_construction = case$ef_construction,
            ef_search = ef, split = split,
            mean_recall = mean(selected), min_recall = min(selected),
            lower_95_recall = max(0, mean(selected) -
                1.96 * sd(selected) / sqrt(length(selected))),
            p10_recall = unname(quantile(selected, 0.1)),
            rows_below_099 = sum(selected < 0.99),
            boundary_tie_rows = sum(ties[truth$split == split]),
            n_queries = length(selected),
            build_seconds = build_seconds,
            search_seconds = search_seconds[[j]],
            collect_seconds = collect_seconds[[j]],
            merge_seconds = merge_seconds,
            query_seconds = search_seconds[[j]] +
                collect_seconds[[j]] + merge_seconds,
            timing_median_seconds = median(timing_seconds[j, ]),
            timing_iqr_seconds = IQR(timing_seconds[j, ]),
            timing_repetitions = timing_reps,
            timing_queries = nrow(timing_query),
            rss_peak_bytes = rss_peak(),
            hostname = Sys.info()[["nodename"]],
            cpu_model = cpu_model, cpu_affinity = affinity,
            n_threads = threads,
            faissr_dll_sha256 = faissr_dll,
            fastembedr_dll_sha256 = fastembedr_dll,
            image_sha256 = image_sha,
            faiss_info_json = faiss_info,
            faissr_m = policy$m,
            faissr_ef_construction = policy$ef_construction,
            faissr_ef_search = policy$ef_search,
            faissr_rule = policy$rule,
            faissr_version = as.character(packageVersion("faissR")),
            fastembedr_version = as.character(packageVersion("fastEmbedR")))
    }
}
out <- file.path(root, "sweep", sprintf("case_%03d.csv", task))
dir.create(dirname(out), recursive = TRUE, showWarnings = FALSE)
summary <- do.call(rbind, result)
summary$worker_elapsed_seconds <- clock() - worker_started
write.csv(summary, out, row.names = FALSE)
write.csv(do.call(rbind, per_query), file.path(root, "sweep",
    sprintf("case_%03d_queries.csv", task)), row.names = FALSE)
cat("Completed", case$dataset, case$scope, "M=", case$m,
    "efC=", case$ef_construction, "shard=", case$shard_rows, "\n")
