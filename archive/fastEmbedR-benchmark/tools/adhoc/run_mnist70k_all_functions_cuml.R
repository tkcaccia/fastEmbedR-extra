#!/usr/bin/env Rscript

args <- commandArgs(trailingOnly = TRUE)
arg_value <- function(name, default = NULL) {
  hit <- grep(paste0("^--", name, "="), args, value = TRUE)
  if (length(hit)) sub(paste0("^--", name, "="), "", hit[[1]]) else default
}

data_file <- arg_value("data", "/mnt/sata_ssd/fastEmbedR/Data/MNIST/MNIST.RData")
out_dir <- arg_value("out", file.path("/mnt/sata_ssd/fastEmbedR/results",
                                      paste0("mnist70k_all_functions_cuml_", format(Sys.time(), "%Y%m%d_%H%M%S"))))
threads <- as.integer(arg_value("threads", "4"))
seed <- as.integer(arg_value("seed", "4"))
perplexity <- as.integer(arg_value("perplexity", "30"))
k <- as.integer(arg_value("k", as.character(perplexity)))
trust_sample <- as.integer(arg_value("trust-sample", "5000"))

dir.create(out_dir, recursive = TRUE, showWarnings = FALSE)
dir.create(file.path(out_dir, "plots"), recursive = TRUE, showWarnings = FALSE)
dir.create(file.path(out_dir, "layouts"), recursive = TRUE, showWarnings = FALSE)

Sys.setenv(
  OMP_NUM_THREADS = threads,
  OPENBLAS_NUM_THREADS = threads,
  MKL_NUM_THREADS = threads,
  RCPP_PARALLEL_NUM_THREADS = threads,
  NUMBA_NUM_THREADS = threads
)

log_msg <- function(...) {
  cat(format(Sys.time(), "%Y-%m-%d %H:%M:%S"), ..., "\n")
  flush.console()
}

safe_matrix <- function(x) {
  if (is.data.frame(x)) x <- as.matrix(x)
  if (!is.matrix(x)) x <- as.matrix(x)
  storage.mode(x) <- "double"
  x
}

extract_layout <- function(x) {
  if (inherits(x, "fastEmbedR_embedding")) x <- x$layout
  else if (is.list(x) && !is.null(x$layout)) x <- x$layout
  else if (is.list(x) && !is.null(x$Y)) x <- x$Y

  if (inherits(x, "float32")) {
    if (!requireNamespace("float", quietly = TRUE)) {
      stop("The float package is required to materialize a float32 layout.", call. = FALSE)
    }
    x <- float::dbl(x)
  }
  x <- as.matrix(x)
  storage.mode(x) <- "double"
  x
}

palette_labels <- function(labels) {
  labs <- as.factor(labels)
  cols <- c(
    "#000000", "#2E86DE", "#44C143", "#E83E5C", "#A000C8",
    "#F0B800", "#26D9D0", "#8E8E8E", "#FF7F0E", "#6F42C1"
  )
  cols[((as.integer(labs) - 1L) %% length(cols)) + 1L]
}

sample_quality <- function(x, y, labels, sample_n = 5000, seed = 4) {
  out <- list(trust = NA_real_, label_acc = NA_real_)
  y <- tryCatch(extract_layout(y), error = function(e) NULL)
  if (!is.matrix(y) || nrow(y) != nrow(x) || ncol(y) < 2L) return(out)
  set.seed(seed)
  idx <- if (nrow(x) > sample_n) sample.int(nrow(x), sample_n) else seq_len(nrow(x))
  x_sub <- x[idx, , drop = FALSE]
  y_sub <- as.matrix(y[idx, 1:2, drop = FALSE])
  labels_sub <- as.factor(labels[idx])
  sk_manifold <- tryCatch(reticulate::import("sklearn.manifold", convert = TRUE), error = function(e) NULL)
  if (!is.null(sk_manifold)) {
    out$trust <- tryCatch(
      as.numeric(sk_manifold$trustworthiness(x_sub, y_sub, n_neighbors = as.integer(min(15, nrow(x_sub) - 1L)))),
      error = function(e) NA_real_
    )
  }
  sk_neighbors <- tryCatch(reticulate::import("sklearn.neighbors", convert = TRUE), error = function(e) NULL)
  sk_metrics <- tryCatch(reticulate::import("sklearn.metrics", convert = TRUE), error = function(e) NULL)
  if (!is.null(sk_neighbors) && !is.null(sk_metrics)) {
    out$label_acc <- tryCatch({
      clf <- sk_neighbors$KNeighborsClassifier(n_neighbors = as.integer(min(10, nrow(y_sub) - 1L)))
      clf$fit(y_sub, as.character(labels_sub))
      pred <- clf$predict(y_sub)
      as.numeric(sk_metrics$accuracy_score(as.character(labels_sub), pred))
    }, error = function(e) NA_real_)
  }
  out
}

plot_one <- function(layout, labels, title, file, cex = 0.28) {
  png(file, width = 1200, height = 1000, res = 150)
  on.exit(dev.off(), add = TRUE)
  y <- extract_layout(layout)
  plot(y[, 1], y[, 2], pch = 20, cex = cex, col = palette_labels(labels),
       xlab = "Component 1", ylab = "Component 2", main = title)
}

run_method <- function(name, family, backend, expr) {
  log_msg(name, "running")
  gc()
  status <- "success"
  err <- NA_character_
  value <- NULL
  elapsed <- NA_real_
  t0 <- proc.time()[["elapsed"]]
  value <- tryCatch(
    force(expr),
    error = function(e) {
      status <<- "failed"
      err <<- conditionMessage(e)
      NULL
    }
  )
  elapsed <- proc.time()[["elapsed"]] - t0
  if (status == "success") {
    layout <- extract_layout(value)
    q <- sample_quality(x_ref, layout, labels, sample_n = trust_sample, seed = seed)
    layout_file <- file.path(out_dir, "layouts", paste0(gsub("[^A-Za-z0-9]+", "_", name), ".rds"))
    plot_file <- file.path(out_dir, "plots", paste0(gsub("[^A-Za-z0-9]+", "_", name), ".png"))
    saveRDS(layout, layout_file)
    plot_one(layout, labels, name, plot_file)
    row <- data.frame(
      dataset = "MNIST70k",
      method = name,
      family = family,
      backend = backend,
      status = status,
      n = nrow(x_ref),
      p = ncol(x_ref),
      k = k,
      perplexity = perplexity,
      threads = threads,
      elapsed_sec = elapsed,
      trust = q$trust,
      label_acc = q$label_acc,
      layout_file = layout_file,
      plot_file = plot_file,
      error = NA_character_,
      stringsAsFactors = FALSE
    )
    log_msg(name, "success sec=", sprintf("%.3f", elapsed),
            " trust=", sprintf("%.3f", q$trust),
            " label_acc=", sprintf("%.3f", q$label_acc))
    return(row)
  }
  log_msg(name, "failed:", err)
  data.frame(
    dataset = "MNIST70k",
    method = name,
    family = family,
    backend = backend,
    status = status,
    n = nrow(x_ref),
    p = ncol(x_ref),
    k = k,
    perplexity = perplexity,
    threads = threads,
    elapsed_sec = elapsed,
    trust = NA_real_,
    label_acc = NA_real_,
    layout_file = NA_character_,
    plot_file = NA_character_,
    error = err,
    stringsAsFactors = FALSE
  )
}

log_msg("Loading", data_file)
load(data_file)
if (!exists("dataset")) stop("Expected object `dataset` in ", data_file, call. = FALSE)
x_ref <- safe_matrix(dataset$data)
labels <- dataset$labels
if (is.null(labels)) labels <- rep(1L, nrow(x_ref))
stopifnot(nrow(x_ref) == 70000L)
log_msg("Loaded MNIST70k n=", nrow(x_ref), " p=", ncol(x_ref),
        " perplexity=", perplexity, " k=", k, " threads=", threads)

suppressPackageStartupMessages({
  library(fastEmbedR)
  library(faissR)
  library(float)
  library(reticulate)
})

x_fast <- float::fl(x_ref)

py <- reticulate::import_builtins()
np <- reticulate::import("numpy", convert = FALSE)
np_x <- np$array(x_ref, dtype = "float32")

sync_cuda <- function() {
  tryCatch({
    cp <- reticulate::import("cupy", convert = FALSE)
    cp$cuda$Stream$null$synchronize()
  }, error = function(e) NULL)
  invisible(NULL)
}

rows <- list()

rows[[length(rows) + 1L]] <- run_method(
  "fastEmbedR openTSNE CPU", "tsne", "cpu",
  fastEmbedR::opentsne(x_fast, perplexity = perplexity, backend = "cpu",
                       seed = seed, n_threads = threads)
)
rows[[length(rows) + 1L]] <- run_method(
  "fastEmbedR openTSNE CUDA", "tsne", "cuda",
  fastEmbedR::opentsne(x_fast, perplexity = perplexity, backend = "cuda",
                       seed = seed, n_threads = threads)
)

if (requireNamespace("Rtsne", quietly = TRUE)) {
  rows[[length(rows) + 1L]] <- run_method(
    "Rtsne full", "tsne", "cpu",
    Rtsne::Rtsne(x_ref, perplexity = perplexity, check_duplicates = FALSE,
                 pca = TRUE, num_threads = threads, verbose = FALSE)
  )
}

tsne_py <- tryCatch(reticulate::import("openTSNE", convert = FALSE), error = function(e) NULL)
if (!is.null(tsne_py)) {
  rows[[length(rows) + 1L]] <- run_method(
    "Python openTSNE FFT", "tsne", "cpu",
    {
      fit <- tsne_py$TSNE(
        perplexity = as.integer(perplexity),
        n_iter = as.integer(250),
        initialization = "pca",
        negative_gradient_method = "fft",
        random_state = as.integer(seed),
        n_jobs = as.integer(threads),
        verbose = FALSE
      )$fit(np_x)
      py_to_r(fit)
    }
  )
}

cuml_manifold <- tryCatch(reticulate::import("cuml.manifold", convert = FALSE), error = function(e) NULL)
cuml_tsne_neighbors <- as.integer(max(3L * perplexity + 10L, k, 100L))
if (!is.null(cuml_manifold)) {
  rows[[length(rows) + 1L]] <- run_method(
    "RAPIDS cuML t-SNE FFT", "tsne", "cuda",
    {
      out <- cuml_manifold$TSNE(
        n_components = as.integer(2),
        perplexity = as.numeric(perplexity),
        max_iter = as.integer(1000),
        method = "fft",
        init = "random",
        n_neighbors = cuml_tsne_neighbors,
        random_state = as.integer(seed),
        output_type = "numpy"
      )$fit_transform(np_x)
      sync_cuda()
      py_to_r(out)
    }
  )
}

rows[[length(rows) + 1L]] <- run_method(
  "fastEmbedR UMAP CPU fuzzy", "umap", "cpu",
  fastEmbedR::umap(x_fast, n_neighbors = k, backend = "cpu",
                   graph_mode = "fuzzy", seed = seed, n_threads = threads)
)
rows[[length(rows) + 1L]] <- run_method(
  "fastEmbedR UMAP CUDA fuzzy", "umap", "cuda",
  fastEmbedR::umap(x_fast, n_neighbors = k, backend = "cuda",
                   graph_mode = "fuzzy", seed = seed, n_threads = threads)
)
rows[[length(rows) + 1L]] <- run_method(
  "fastEmbedR UMAP CPU binary", "umap", "cpu",
  fastEmbedR::umap(x_fast, n_neighbors = k, backend = "cpu",
                   graph_mode = "binary", seed = seed, n_threads = threads)
)
rows[[length(rows) + 1L]] <- run_method(
  "fastEmbedR UMAP CUDA binary", "umap", "cuda",
  fastEmbedR::umap(x_fast, n_neighbors = k, backend = "cuda",
                   graph_mode = "binary", seed = seed, n_threads = threads)
)

if (requireNamespace("uwot", quietly = TRUE)) {
  rows[[length(rows) + 1L]] <- run_method(
    "uwot UMAP fast_sgd full", "umap", "cpu",
    uwot::umap(x_ref, n_neighbors = k, fast_sgd = TRUE,
               n_threads = threads, n_sgd_threads = threads,
               init = "spectral", verbose = FALSE,
               ret_model = FALSE)
  )
}

py_umap <- tryCatch(reticulate::import("umap", convert = FALSE), error = function(e) NULL)
if (!is.null(py_umap)) {
  rows[[length(rows) + 1L]] <- run_method(
    "Python umap-learn", "umap", "cpu",
    {
      fit <- py_umap$UMAP(
        n_neighbors = as.integer(k),
        n_components = as.integer(2),
        metric = "euclidean",
        random_state = as.integer(seed),
        n_jobs = as.integer(threads)
      )$fit_transform(np_x)
      py_to_r(fit)
    }
  )
}

if (!is.null(cuml_manifold)) {
  rows[[length(rows) + 1L]] <- run_method(
    "RAPIDS cuML UMAP", "umap", "cuda",
    {
      out <- cuml_manifold$UMAP(
        n_neighbors = as.integer(k),
        n_components = as.integer(2),
        metric = "euclidean",
        random_state = as.integer(seed),
        output_type = "numpy"
      )$fit_transform(np_x)
      sync_cuda()
      py_to_r(out)
    }
  )
}

bench <- do.call(rbind, rows)
csv_file <- file.path(out_dir, "mnist70k_all_functions_cuml.csv")
write.csv(bench, csv_file, row.names = FALSE)

plot_methods <- bench[bench$status == "success" & !is.na(bench$plot_file), , drop = FALSE]
combined_file <- file.path(out_dir, "mnist70k_all_functions_cuml_plots.png")
if (nrow(plot_methods)) {
  png(combined_file, width = 4200, height = 3200, res = 220)
  oldpar <- par(no.readonly = TRUE)
  on.exit(par(oldpar), add = TRUE)
  par(mfrow = c(3, 4), mar = c(2.4, 2.4, 3, 0.4))
  for (i in seq_len(nrow(plot_methods))) {
    layout <- readRDS(plot_methods$layout_file[[i]])
    plot(as.matrix(layout)[, 1], as.matrix(layout)[, 2], pch = 20, cex = 0.17,
         col = palette_labels(labels), xlab = "", ylab = "",
         main = sprintf("%s\n%.1fs trust %.3f", plot_methods$method[[i]],
                        plot_methods$elapsed_sec[[i]], plot_methods$trust[[i]]))
  }
  if (nrow(plot_methods) < 12) {
    for (i in seq_len(12 - nrow(plot_methods))) plot.new()
  }
  dev.off()
}

bar_file <- file.path(out_dir, "mnist70k_all_functions_cuml_time_barplot.png")
png(bar_file, width = 2200, height = 1300, res = 180)
ok <- bench[bench$status == "success", , drop = FALSE]
ok <- ok[order(ok$family, ok$elapsed_sec), , drop = FALSE]
cols <- ifelse(ok$backend == "cuda", "#4C78A8", ifelse(ok$backend == "cpu", "#F58518", "#54A24B"))
par(mar = c(9, 5, 3, 1))
barplot(ok$elapsed_sec, names.arg = ok$method, las = 2, col = cols,
        ylab = "Elapsed seconds", main = "MNIST70k elapsed time")
legend("topright", fill = c("#F58518", "#4C78A8"), legend = c("CPU", "CUDA"), bty = "n")
dev.off()

cat("\nRESULT_CSV=", csv_file, "\n", sep = "")
cat("RESULT_PLOTS=", combined_file, "\n", sep = "")
cat("RESULT_BARPLOT=", bar_file, "\n", sep = "")
print(bench[, c("method", "backend", "status", "elapsed_sec", "trust", "label_acc", "error")], row.names = FALSE)
