#!/usr/bin/env Rscript

args <- commandArgs(trailingOnly = TRUE)
if (length(args) != 3L || args[[3L]] != "--global-knn-recall") {
  stop(paste("Usage: audit_m3_ultra_panel_quality_v1.R",
             "RUN_DIR DATASET --global-knn-recall"))
}
root <- normalizePath(args[[1L]], mustWork = TRUE)
dataset <- args[[2L]]
script_arg <- grep("^--file=", commandArgs(FALSE), value = TRUE)
script_dir <- dirname(normalizePath(
  sub("^--file=", "", script_arg[[1L]]), mustWork = TRUE))
source(file.path(script_dir, "..", "shared", "publication_metrics.R"),
       local = TRUE)
source(file.path(script_dir, "mac_global_knn_recall_v1.R"),
       local = TRUE)
runs <- read.csv(file.path(root, "benchmark_runs.csv"),
                 stringsAsFactors = FALSE)
cpu_methods <- c(
  "fastEmbedR_pca_cpu", "fastEmbedR_tsne_cpu_full",
  "fastEmbedR_tsne_cpu_knn", "fastEmbedR_umap_cpu_fuzzy_full",
  "fastEmbedR_umap_cpu_fuzzy_knn",
  "fastEmbedR_umap_cpu_binary_full",
  "fastEmbedR_umap_cpu_binary_knn"
)
threads <- c(1L, 4L, 8L, 12L, 20L, 28L)
seeds <- c(4L, 17L, 42L)
if (nrow(runs) != 147L || any(runs$dataset != dataset) ||
    any(runs$status != "success") ||
    anyDuplicated(runs[c("method", "requested_threads", "seed")]) ||
    anyDuplicated(runs$layout_file)) {
  stop("Incomplete or duplicate panel run table")
}

select_run <- function(method, thread, seed) {
  row <- runs[runs$method == method &
                runs$requested_threads == thread &
                runs$seed == seed, , drop = FALSE]
  if (nrow(row) != 1L) stop("Missing method/thread/seed arm")
  row
}

sha256_file <- function(path) {
  result <- system2("shasum", c("-a", "256", shQuote(path)),
                    stdout = TRUE, stderr = TRUE)
  if (!length(result) || !is.null(attr(result, "status"))) {
    stop("Cannot hash quality sample: ", path)
  }
  strsplit(result[[1L]], "[[:space:]]+")[[1L]][[1L]]
}

check_artifact <- function(row) {
  path <- normalizePath(row$layout_file[[1L]], mustWork = TRUE)
  if (!startsWith(path, paste0(root, "/"))) {
    stop("Layout path escapes run directory: ", path)
  }
  expected_hash <- as.character(row$layout_sha256[[1L]])
  if (is.na(expected_hash) || !grepl("^[0-9a-f]{64}$", expected_hash) ||
      !identical(sha256_file(path), expected_hash)) {
    stop("Saved layout checksum mismatch: ", path)
  }
  record <- readRDS(path)
  layout <- publication_layout_matrix(record$layout)
  if (nrow(layout) != row$n[[1L]] || ncol(layout) != 2L ||
      any(!is.finite(layout)) ||
      !identical(as.character(record$method), row$method[[1L]]) ||
      !identical(as.character(record$backend),
                 row$actual_backend[[1L]]) ||
      !identical(as.integer(record$seed),
                 as.integer(row$seed[[1L]])) ||
      !identical(as.integer(record$requested_threads),
                 as.integer(row$requested_threads[[1L]]))) {
    stop("Invalid saved layout: ", path)
  }
  invisible(NULL)
}

check_sample <- function(row) {
  if (identical(row$family[[1L]], "PCA")) return(invisible(NULL))
  path <- normalizePath(row$quality_sample_rows_file[[1L]],
                        mustWork = TRUE)
  expected <- as.character(row$quality_sample_sha256[[1L]])
  if (is.na(expected) || !nzchar(expected) ||
      !identical(sha256_file(path), expected)) {
    stop("Quality sample identity failed: ", path)
  }
  invisible(NULL)
}

check_global_recall <- function(row) {
  if (row$timing_scope[[1L]] != "full_pipeline" ||
      row$family[[1L]] == "PCA") return(NULL)
  reference_file <- normalizePath(
    row$global_knn_reference_file[[1L]], mustWork = TRUE)
  sample_file <- normalizePath(
    row$global_knn_sample_file[[1L]], mustWork = TRUE)
  if (!startsWith(sample_file, paste0(root, "/")) ||
      !identical(sha256_file(reference_file),
                 row$global_knn_reference_sha256[[1L]]) ||
      !identical(sha256_file(sample_file),
                 row$global_knn_sample_sha256[[1L]])) {
    stop("Global KNN sample or reference identity failed")
  }
  reference <- readRDS(reference_file)
  candidate <- readRDS(sample_file)
  if (!is.character(reference$input_sha256) ||
      length(reference$input_sha256) != 1L ||
      !grepl("^[0-9a-f]{64}$", reference$input_sha256) ||
      !identical(candidate$method, row$method[[1L]]) ||
      !identical(candidate$threads,
                 as.integer(row$requested_threads[[1L]])) ||
      !identical(candidate$seed, as.integer(row$seed[[1L]])) ||
      reference$engine != "native_cpu_exact_query_global") {
    stop("Global KNN arm or reference engine changed")
  }
  score <- global_knn_score(reference, candidate)
  if (!isTRUE(all.equal(score$mean,
                        row$global_knn_recall_mean[[1L]])) ||
      !isTRUE(all.equal(score$minimum,
                        row$global_knn_recall_minimum[[1L]])) ||
      !identical(score$pass, row$global_knn_recall_pass[[1L]])) {
    stop("Worker and independent global KNN recall differ")
  }
  score
}

quality_compare <- function(reference, candidate, pca = FALSE,
                            tsne = FALSE) {
  if (!pca) {
    names <- c("trustworthiness", "knn_preservation_15",
               "knn_preservation_30", "knn_preservation_50")
    limits <- c(0.01, rep(if (tsne) 0.01 else 0.005, 3L))
    first <- as.numeric(unlist(reference[1L, names], use.names = FALSE))
    second <- as.numeric(unlist(candidate[1L, names], use.names = FALSE))
    if (any(!is.finite(c(first, second)))) {
      stop("Missing required embedding quality metric")
    }
    delta <- second - first
    pass <- all(delta >= -limits)
    for (name in c("silhouette", "label_knn_accuracy")) {
      x <- as.numeric(reference[[name]][[1L]])
      y <- as.numeric(candidate[[name]][[1L]])
      if (xor(is.finite(x), is.finite(y))) {
        stop("One side lacks optional quality metric: ", name)
      }
      if (is.finite(x)) pass <- pass && y - x >= -0.01
    }
    if (tsne) {
      x <- as.numeric(reference$tsne_kl[[1L]])
      y <- as.numeric(candidate$tsne_kl[[1L]])
      if (!is.finite(x) || x <= 0 || !is.finite(y)) {
        stop("Missing or invalid sampled t-SNE KL")
      }
      pass <- pass && y / x <= 1.05
    }
    return(list(pass = pass, detail = paste(round(delta, 6),
                                            collapse = ";")))
  }
  first <- readRDS(reference$layout_file[[1L]])$layout
  second <- readRDS(candidate$layout_file[[1L]])$layout
  agreement <- publication_procrustes(first, second)
  correlation <- as.numeric(agreement$correlation[[1L]])
  if (!is.finite(correlation)) stop("Invalid PCA subspace agreement")
  list(pass = correlation >= 0.99,
       detail = sprintf("procrustes_correlation=%.6f", correlation))
}

recall_scores <- vector("list", nrow(runs))
for (i in seq_len(nrow(runs))) {
  check_artifact(runs[i, , drop = FALSE])
  check_sample(runs[i, , drop = FALSE])
  recall_scores[[i]] <- check_global_recall(runs[i, , drop = FALSE])
}
recalled <- which(!vapply(recall_scores, is.null, logical(1L)))
if (length(recalled) != 63L ||
    length(unique(runs$global_knn_reference_sha256[recalled])) != 1L) {
  stop("Incomplete or inconsistent global KNN recall sample schedule")
}
recall_table <- data.frame(
  method = runs$method[recalled],
  requested_threads = runs$requested_threads[recalled],
  seed = runs$seed[recalled],
  mean_recall = vapply(recall_scores[recalled], `[[`, numeric(1L),
                       "mean"),
  minimum_row_recall = vapply(recall_scores[recalled], `[[`,
                              numeric(1L), "minimum"),
  pass = vapply(recall_scores[recalled], `[[`, logical(1L), "pass")
)
write.csv(recall_table, file.path(root, "global_knn_recall_audit.csv"),
          row.names = FALSE)
for (seed in seeds) {
  rows <- runs[runs$seed == seed & runs$family != "PCA", , drop = FALSE]
  if (length(unique(rows$quality_sample_sha256)) != 1L) {
    stop("Quality sample differs within seed ", seed)
  }
}

cpu_quality <- list()
metal_pairs <- list()
summary <- list()
knn_recall_status <- function(cpu, metal, best, scope) {
  if (scope == "pca_only") return("not_applicable")
  if (scope == "embedding_from_precomputed_knn") {
    return("precomputed_knn_outside_timing")
  }
  selected <- runs[
    (runs$method == cpu & runs$requested_threads == best) |
      runs$method == metal, , drop = FALSE
  ]
  cpu_rows <- selected$method == cpu
  if (nrow(selected) != 6L || sum(cpu_rows) != 3L ||
      anyNA(selected$global_knn_recall_pass)) {
    stop("Selected full-run KNN recall evidence is missing")
  }
  if (all(selected$global_knn_recall_pass)) {
    "sampled_exact_reference_pass"
  } else "sampled_exact_reference_fail"
}
for (cpu in cpu_methods) {
  pca <- identical(cpu, "fastEmbedR_pca_cpu")
  tsne <- grepl("_tsne_", cpu, fixed = TRUE)
  valid <- logical(length(threads))
  names(valid) <- as.character(threads)
  for (thread in threads) {
    comparisons <- lapply(seeds, function(seed) {
      reference <- select_run(cpu, 1L, seed)
      candidate <- select_run(cpu, thread, seed)
      quality_compare(reference, candidate, pca, tsne)
    })
    quality_pass <- all(vapply(
      comparisons, `[[`, logical(1L), "pass"))
    recall_pass <- pca ||
      grepl("_knn$", cpu) ||
      all(vapply(seeds, function(seed) {
        isTRUE(select_run(cpu, thread, seed)$global_knn_recall_pass[[1L]])
      }, logical(1L)))
    valid[[as.character(thread)]] <- quality_pass && recall_pass
    cpu_quality[[length(cpu_quality) + 1L]] <- data.frame(
      method = cpu, threads = thread,
      quality_pass_all_seeds = quality_pass,
      recall_pass_all_seeds = recall_pass,
      valid_for_cpu_selection = valid[[as.character(thread)]],
      details = paste(vapply(comparisons, `[[`, character(1L),
                             "detail"), collapse = " | "))
  }
  qualified <- threads[valid]
  if (!length(qualified)) stop("No quality-qualified CPU: ", cpu)
  medians <- vapply(qualified, function(thread) {
    median(vapply(seeds, function(seed) {
      as.numeric(select_run(cpu, thread, seed)$total_runtime_sec[[1L]])
    }, numeric(1L)))
  }, numeric(1L))
  best <- qualified[[which.min(medians)]]
  metal <- sub("_cpu", "_metal", cpu, fixed = TRUE)
  scope <- unique(runs$timing_scope[runs$method %in% c(cpu, metal)])
  if (length(scope) != 1L || is.na(scope) ||
      !scope %in% c("pca_only", "full_pipeline",
                    "embedding_from_precomputed_knn")) {
    stop("CPU/Metal timing scopes are inconsistent: ", cpu)
  }
  checks <- lapply(seeds, function(seed) {
    reference <- select_run(cpu, best, seed)
    candidate <- select_run(metal, max(threads), seed)
    quality <- quality_compare(reference, candidate, pca, tsne)
    ratio <- as.numeric(reference$total_runtime_sec[[1L]]) /
      as.numeric(candidate$total_runtime_sec[[1L]])
    if (!is.finite(ratio) || ratio <= 0) stop("Invalid paired runtime")
    data.frame(method = sub("_cpu", "", cpu, fixed = TRUE),
               seed = seed, best_cpu_threads = best,
               quality_pass = quality$pass, quality_detail = quality$detail,
               cpu_over_metal = ratio, speed_pass = ratio >= 1.2)
  })
  paired <- do.call(rbind, checks)
  metal_pairs[[length(metal_pairs) + 1L]] <- paired
  passed <- all(paired$quality_pass) && all(paired$speed_pass)
  recall <- knn_recall_status(cpu, metal, best, scope)
  recall_gate <- if (scope == "embedding_from_precomputed_knn") {
    NA
  } else if (!passed) {
    FALSE
  } else if (recall %in% c("sampled_exact_reference_pass",
                           "not_applicable")) {
    TRUE
  } else NA
  summary[[length(summary) + 1L]] <- data.frame(
    method = paired$method[[1L]], timing_scope = scope,
    best_cpu_threads = best,
    knn_recall_status = recall,
    quality_pass = all(paired$quality_pass),
    speed_pass = all(paired$speed_pass),
    median_ratio = median(paired$cpu_over_metal),
    quality_speed_gate = passed,
    end_to_end_speed_gate = if (scope ==
        "embedding_from_precomputed_knn") NA else
      passed,
    recall_qualified_end_to_end_gate = recall_gate)
}
write.csv(do.call(rbind, cpu_quality),
          file.path(root, "cpu_quality_grid.csv"), row.names = FALSE)
write.csv(do.call(rbind, metal_pairs),
          file.path(root, "metal_paired_quality_speed.csv"), row.names = FALSE)
write.csv(do.call(rbind, summary),
          file.path(root, "quality_speed_summary.csv"), row.names = FALSE)
cat("Saved-layout, quality and paired-speed audit complete\n")
