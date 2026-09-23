source(file.path(dirname(script_file()), "common.R"))
args <- parse_cli(); cells <- read.csv(args$cells %||% stop("--cells required"), stringsAsFactors = FALSE)
id <- as_int(args$cell_id %||% Sys.getenv("SLURM_ARRAY_TASK_ID"), NA_integer_)
if (is.na(id) || !id %in% cells$cell_id) stop("Invalid cell id: ", id)
cell <- cells[cells$cell_id == id, , drop = FALSE]; check_protocol_api(strict = TRUE)
prepared <- readRDS(file.path(args$prepared_root, cell$dataset, cell$representation,
                              paste0("seed_", cell$seed), "prepared_graph.rds"))
out <- file.path(args$out_root, cell$dataset, cell$representation, cell$classifier,
  cell$experiment, cell$setting, paste0("seed_", cell$seed))
if (file.exists(file.path(out, "exit_status.txt")) && identical(readLines(file.path(out, "exit_status.txt"), warn = FALSE), "0")) quit(save = "no")
dir.create(out, recursive = TRUE, showWarnings = FALSE)
status <- 1L; err <- NA_character_; started <- Sys.time()
tryCatch({
  if (cell$experiment == "classic") {
    t0 <- proc.time()[["elapsed"]]
    layout <- if (cell$setting == "umap") extract_layout(fastEmbedR::umap(prepared$x,
      n_neighbors = 30L, graph_mode = "fuzzy", backend = "cpu", n.cores = 4L,
      seed = cell$seed)) else extract_layout(fastEmbedR::opentsne(prepared$x,
      perplexity = 30, backend = "cpu", n.cores = 4L, seed = cell$seed))
    wall <- proc.time()[["elapsed"]] - t0; fit <- NULL
  } else {
    api <- check_protocol_api(strict = TRUE); call <- list(data = prepared$x, graph = prepared$graph,
      M = 100L, Tcycle = 100L, folds = 5L, ncomp = 50L, landmarks = 100000L,
      splitting = if (prepared$n < 40000L) 100L else 300L, n.cores = 4L,
      graph.neighbors = 100L, knn.k = 30L, classifier = cell$classifier,
      backend = "cpu", seed = cell$seed, visual.init = TRUE, progress = TRUE)
    if (cell$experiment == "ablation") call[[api$policy_arg]] <- cell$setting
    if (cell$experiment == "knn_sensitivity") call$knn.k <- as.integer(cell$value)
    if (cell$experiment == "ncomp_sensitivity") call$ncomp <- as.integer(cell$value)
    t0 <- proc.time()[["elapsed"]]; fit <- do.call(kodamaR::KODAMA.matrix, call)
    wall <- proc.time()[["elapsed"]] - t0
    # Save both visualizations from the same fitted KODAMA result.
    layouts <- lapply(c("UMAP", "openTSNE"), function(method) extract_layout(kodamaR::KODAMA.visualization(
      fit, method = method, k = 30L, perplexity = 30, graph.mode = "fuzzy",
      backend = "cpu", n.cores = 4L, seed = cell$seed)))
    names(layouts) <- c("umap", "opentsne"); layout <- layouts$umap
    atomic_save_rds(layouts, file.path(out, "layouts.rds"))
    atomic_write_csv(fit_diagnostics(fit), file.path(out, "run_metrics.csv"))
    atomic_write_csv(timing_rows(fit, wall, prepared$graph_seconds), file.path(out, "timing.csv"))
    atomic_save_rds(fit$best_labels, file.path(out, "labels.rds"))
    for (nm in c("run_diagnostics", "cycle_diagnostics", "agreement_diagnostics")) {
      if (!is.null(fit[[nm]])) atomic_save_rds(fit[[nm]], file.path(out, paste0(nm, ".rds")))
    }
  }
  if (cell$experiment == "classic") atomic_save_rds(list(layout = layout), file.path(out, "layouts.rds"))
  q <- quality_metrics(prepared$x, layout, prepared$labels, cell$seed)
  info <- if (is.null(fit)) c(nmi=NA,homogeneity=NA,completeness=NA,v_measure=NA) else information_metrics(prepared$labels, fit$best_labels)
  metrics <- data.frame(cell, status = "success", error = NA_character_, n = prepared$n, p = prepared$p,
    workers = 4L, M = if (is.null(fit)) NA else 100L, Tcycle = if (is.null(fit)) NA else 100L,
    requested_k = if (cell$classifier == "knn") if (cell$experiment == "knn_sensitivity") as.integer(cell$value) else 30L else NA,
    requested_ncomp = if (cell$classifier == "pls_lda") if (cell$experiment == "ncomp_sensitivity") as.integer(cell$value) else 50L else NA,
    wall_seconds = wall, graph_seconds = prepared$graph_seconds, pipeline_seconds = wall + prepared$graph_seconds,
    peak_rss_kb = suppressWarnings(as.numeric(Sys.getenv("SLURM_MAX_RSS_KB", NA))),
    ari = if (is.null(fit)) NA else ari(prepared$labels, fit$best_labels), t(q), t(info),
    dataset_sha256 = prepared$dataset_sha256, graph_sha256 = sha256(file.path(args$prepared_root,
      cell$dataset, cell$representation, paste0("seed_", cell$seed), "prepared_graph.rds")))
  atomic_write_csv(metrics, file.path(out, "metrics.csv")); status <- 0L
}, error = function(e) { err <<- conditionMessage(e); atomic_write_csv(data.frame(cell,
  status = "failed", error = err, started = as.character(started), ended = as.character(Sys.time())), file.path(out, "metrics.csv")) })
atomic_write_lines(as.character(status), file.path(out, "exit_status.txt"))
if (status != 0L) stop(err)
