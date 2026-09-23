args <- commandArgs(trailingOnly = TRUE)
out_dir <- if (length(args) >= 1L) args[[1L]] else tempfile("mnist70k_exact_policy_")
dir.create(out_dir, recursive = TRUE, showWarnings = FALSE)

log_file <- file.path(out_dir, "benchmark.log")
log_msg <- function(...) {
  line <- paste(format(Sys.time()), paste(..., collapse = " "))
  cat(line, "\n")
  cat(line, "\n", file = log_file, append = TRUE)
}
`%||%` <- function(x, y) if (is.null(x)) y else x

Sys.setenv(RETICULATE_PYTHON = "/mnt/sata_ssd/fastEmbedR/python_envs/rapids_cuml_py312/bin/python")
suppressPackageStartupMessages({
  library(faissR)
  library(fastEmbedR)
})

data_file <- "/mnt/sata_ssd/fastEmbedR/Data/MNIST/MNIST.RData"
if (!file.exists(data_file)) {
  stop("Missing data file: ", data_file)
}
load(data_file)
x <- dataset$data
storage.mode(x) <- "double"

log_msg("faissR path:", system.file(package = "faissR"))
log_msg("fastEmbedR path:", system.file(package = "fastEmbedR"))
log_msg("MNIST dimensions:", paste(dim(x), collapse = "x"))
log_msg(
  "policy cuda n=70000:",
  paste(names(fastEmbedR:::fastembedr_embedding_nn_policy("cuda", n = nrow(x))),
        unlist(fastEmbedR:::fastembedr_embedding_nn_policy("cuda", n = nrow(x))),
        sep = "=", collapse = ",")
)

rows <- list()
add_row <- function(method, backend, nn_policy, total_sec, status = "success",
                    knn_sec = NA_real_, embed_sec = NA_real_,
                    engine = NA_character_, nn_backend = NA_character_,
                    error = NA_character_) {
  if (length(engine) == 0L || is.null(engine)) engine <- NA_character_
  if (length(nn_backend) == 0L || is.null(nn_backend)) nn_backend <- NA_character_
  if (length(error) == 0L || is.null(error)) error <- NA_character_
  rows[[length(rows) + 1L]] <<- data.frame(
    method = method,
    backend = backend,
    nn_policy = nn_policy,
    n = nrow(x),
    p = ncol(x),
    k = 30L,
    perplexity = 30,
    total_sec = as.numeric(total_sec),
    knn_sec = as.numeric(knn_sec),
    embed_sec = as.numeric(embed_sec),
    status = status,
    engine = engine,
    nn_backend = nn_backend,
    error = error,
    stringsAsFactors = FALSE
  )
}

run_fit <- function(label, expr, nn_policy) {
  log_msg(label, "starting")
  t <- system.time({
    fit <- tryCatch(expr, error = function(e) e)
  })
  if (inherits(fit, "error")) {
    log_msg(label, "failed:", conditionMessage(fit))
    add_row(label, "cuda", nn_policy, NA_real_, "failed", error = conditionMessage(fit))
    return(invisible(NULL))
  }
  knn_sec <- tryCatch(fit$metrics$knn_elapsed[[1L]], error = function(e) NA_real_)
  embed_sec <- tryCatch(fit$metrics$embedding_elapsed[[1L]], error = function(e) NA_real_)
  engine <- tryCatch(fit$parameters$nn_engine, error = function(e) NA_character_)
  nn_backend <- tryCatch(fit$parameters$nn_backend, error = function(e) NA_character_)
  log_msg(
    label, "success total", round(t[["elapsed"]], 3),
    "knn", round(knn_sec, 3),
    "embed", round(embed_sec, 3),
    "engine", paste(engine, collapse = "|"),
    "nn_backend", paste(nn_backend, collapse = "|")
  )
  add_row(label, "cuda", nn_policy, t[["elapsed"]], "success", knn_sec, embed_sec, engine, nn_backend)
  invisible(fit)
}

run_fit(
  "fastEmbedR openTSNE CUDA current policy",
  fastEmbedR::opentsne(x, backend = "cuda", perplexity = 30, n_threads = 4, seed = 4),
  "exact if n<100000 else ivf"
)
run_fit(
  "fastEmbedR UMAP fuzzy CUDA current policy",
  fastEmbedR::umap(x, backend = "cuda", n_neighbors = 30, graph_mode = "fuzzy", n_threads = 4, seed = 4),
  "exact if n<100000 else ivf"
)
run_fit(
  "fastEmbedR UMAP binary CUDA current policy",
  fastEmbedR::umap(x, backend = "cuda", n_neighbors = 30, graph_mode = "binary", n_threads = 4, seed = 4),
  "exact if n<100000 else ivf"
)

log_msg("Manual faissR::nn_gpu auto timing starting")
auto_time <- system.time({
  auto_knn <- faissR::nn_gpu(
    x,
    k = 30,
    exclude_self = TRUE,
    method = "auto",
    metric = "euclidean",
    tuning = "auto",
    target_recall = 0.99
  )
})
log_msg(
  "Manual faissR::nn_gpu auto timing success",
  round(auto_time[["elapsed"]], 3),
  "backend", paste(auto_knn$backend_used %||% attr(auto_knn, "backend"), collapse = "|")
)

run_fit(
  "fastEmbedR openTSNE CUDA manual auto KNN",
  fastEmbedR::opentsne(auto_knn, init_data = x, backend = "cuda", perplexity = 30, n_threads = 4, seed = 4),
  paste0("manual faissR::nn_gpu auto; knn_sec=", round(auto_time[["elapsed"]], 3))
)
run_fit(
  "fastEmbedR UMAP fuzzy CUDA manual auto KNN",
  fastEmbedR::umap(auto_knn, backend = "cuda", n_neighbors = 30, graph_mode = "fuzzy", n_threads = 4, seed = 4),
  paste0("manual faissR::nn_gpu auto; knn_sec=", round(auto_time[["elapsed"]], 3))
)

rapids_helper <- file.path(out_dir, "rapids_full_helpers.py")
if (file.exists(rapids_helper) && requireNamespace("reticulate", quietly = TRUE)) {
  suppressPackageStartupMessages(library(reticulate))
  source_python(rapids_helper)
  log_msg("RAPIDS cuML UMAP starting")
  u <- tryCatch(run_umap(x, n_neighbors = 30L, random_state = 4L), error = function(e) e)
  if (inherits(u, "error")) {
    add_row("RAPIDS cuML UMAP full", "cuda", "RAPIDS internal", NA_real_, "failed", error = conditionMessage(u))
    log_msg("RAPIDS cuML UMAP failed:", conditionMessage(u))
  } else {
    add_row("RAPIDS cuML UMAP full", "cuda", "RAPIDS internal", u$total_sec, "success",
            knn_sec = NA_real_, embed_sec = u$fit_sec, engine = "RAPIDS", nn_backend = "RAPIDS internal")
    log_msg("RAPIDS cuML UMAP success", round(u$total_sec, 3), "fit", round(u$fit_sec, 3))
  }
  log_msg("RAPIDS cuML TSNE starting")
  tt <- tryCatch(run_tsne(x, perplexity = 30L, random_state = 4L), error = function(e) e)
  if (inherits(tt, "error")) {
    add_row("RAPIDS cuML TSNE full", "cuda", "RAPIDS internal", NA_real_, "failed", error = conditionMessage(tt))
    log_msg("RAPIDS cuML TSNE failed:", conditionMessage(tt))
  } else {
    add_row("RAPIDS cuML TSNE full", "cuda", "RAPIDS internal", tt$total_sec, "success",
            knn_sec = NA_real_, embed_sec = tt$fit_sec, engine = "RAPIDS", nn_backend = "RAPIDS internal")
    log_msg("RAPIDS cuML TSNE success", round(tt$total_sec, 3), "fit", round(tt$fit_sec, 3))
  }
}

result <- do.call(rbind, rows)
write.csv(result, file.path(out_dir, "mnist70k_exact_policy_benchmark.csv"), row.names = FALSE)
print(result)
