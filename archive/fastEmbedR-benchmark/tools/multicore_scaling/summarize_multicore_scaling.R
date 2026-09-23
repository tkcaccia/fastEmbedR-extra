script_dir <- dirname(normalizePath(sub("^--file=", "", grep(
  "^--file=", commandArgs(trailingOnly = FALSE), value = TRUE
)[1L])))
source(file.path(script_dir, "multicore_scaling_common.R"))

input_dir <- normalizePath(arg_value("input-dir"), mustWork = TRUE)
out_dir <- dir_create(arg_value("out-dir", file.path(input_dir, "summary")))
files <- list.files(input_dir, pattern = "[.]csv$", recursive = TRUE, full.names = TRUE)
files <- files[!grepl("/summary/", files, fixed = TRUE)]
if (!length(files)) stop("No run-level CSV files found.", call. = FALSE)

rows <- lapply(files, function(path) {
  value <- tryCatch(read.csv(path, stringsAsFactors = FALSE), error = function(e) NULL)
  if (is.null(value) || !all(c("dataset", "measured_stage", "elapsed_sec") %in% names(value))) NULL else value
})
raw <- do.call(rbind, Filter(Negate(is.null), rows))
write.csv(raw, file.path(out_dir, "multicore_scaling_run_level.csv"), row.names = FALSE)

ok <- raw[raw$status == "success" & is.finite(raw$elapsed_sec), , drop = FALSE]
key <- interaction(
  ok$dataset, ok$profile, ok$benchmark_scope, ok$measured_stage, ok$requested_threads,
  ok$effective_threads, ok$blas_threads_requested, drop = TRUE
)
summary_rows <- lapply(split(ok, key), function(z) {
  data.frame(
    dataset = z$dataset[[1L]], profile = z$profile[[1L]],
    benchmark_scope = z$benchmark_scope[[1L]],
    measured_stage = z$measured_stage[[1L]], n = z$n[[1L]], p = z$p[[1L]],
    requested_threads = z$requested_threads[[1L]],
    effective_threads = z$effective_threads[[1L]],
    blas_threads_requested = z$blas_threads_requested[[1L]],
    timing_repetitions = nrow(z),
    median_sec = median(z$elapsed_sec), q25_sec = unname(quantile(z$elapsed_sec, 0.25)),
    q75_sec = unname(quantile(z$elapsed_sec, 0.75)),
    min_sec = min(z$elapsed_sec), max_sec = max(z$elapsed_sec),
    peak_process_rss_gb = max(z$peak_process_rss_kb, na.rm = TRUE) / 1024^2,
    implementation = z$implementation[[1L]], stringsAsFactors = FALSE
  )
})
summary <- do.call(rbind, summary_rows)
summary$peak_process_rss_gb[!is.finite(summary$peak_process_rss_gb)] <- NA_real_

baseline_key <- paste(
  summary$dataset, summary$benchmark_scope, summary$measured_stage,
  summary$blas_threads_requested, sep = "\r"
)
baseline <- tapply(
  summary$median_sec[summary$requested_threads == 1L],
  baseline_key[summary$requested_threads == 1L], identity
)
summary$baseline_1thread_sec <- unname(baseline[baseline_key])
summary$speedup_vs_1thread <- summary$baseline_1thread_sec / summary$median_sec
summary$parallel_efficiency <- summary$speedup_vs_1thread / summary$effective_threads
write.csv(summary, file.path(out_dir, "multicore_scaling_summary.csv"), row.names = FALSE)

failures <- raw[raw$status != "success", , drop = FALSE]
write.csv(failures, file.path(out_dir, "multicore_scaling_failures.csv"), row.names = FALSE)

if (requireNamespace("ggplot2", quietly = TRUE)) {
  library(ggplot2)
  dodge <- position_dodge(width = 0.15)
  runtime <- ggplot(summary, aes(requested_threads, median_sec, color = measured_stage)) +
    geom_line() + geom_point(size = 1.8) +
    geom_errorbar(aes(ymin = q25_sec, ymax = q75_sec), width = 0.25, position = dodge) +
    scale_x_continuous(breaks = sort(unique(summary$requested_threads))) +
    scale_y_log10() + facet_wrap(~dataset, scales = "free_y") +
    labs(x = "Requested CPU workers", y = "Median seconds (log scale)", color = "Stage") +
    theme_bw(base_size = 10)
  ggsave(file.path(out_dir, "multicore_scaling_runtime.png"), runtime, width = 11, height = 6.5, dpi = 300)

  speed <- ggplot(summary, aes(requested_threads, speedup_vs_1thread, color = measured_stage)) +
    geom_abline(slope = 1, intercept = 0, linetype = 2, color = "grey50") +
    geom_line() + geom_point(size = 1.8) +
    scale_x_continuous(breaks = sort(unique(summary$requested_threads))) +
    facet_wrap(~dataset) +
    labs(x = "Requested CPU workers", y = "Speedup over one worker", color = "Stage") +
    theme_bw(base_size = 10)
  ggsave(file.path(out_dir, "multicore_scaling_speedup.png"), speed, width = 11, height = 6.5, dpi = 300)

  efficiency <- ggplot(summary, aes(requested_threads, parallel_efficiency, color = measured_stage)) +
    geom_hline(yintercept = 1, linetype = 2, color = "grey50") +
    geom_line() + geom_point(size = 1.8) +
    scale_x_continuous(breaks = sort(unique(summary$requested_threads))) +
    facet_wrap(~dataset) +
    labs(x = "Requested CPU workers", y = "Parallel efficiency", color = "Stage") +
    theme_bw(base_size = 10)
  ggsave(file.path(out_dir, "multicore_scaling_efficiency.png"), efficiency, width = 11, height = 6.5, dpi = 300)
}

writeLines(c(
  "# fastEmbedR multicore scaling summary",
  "",
  paste0("Run-level rows: ", nrow(raw)),
  paste0("Successful rows: ", nrow(ok)),
  paste0("Failure rows: ", nrow(failures)),
  "",
  "Speedup is median one-worker time divided by median p-worker time.",
  "Parallel efficiency is speedup divided by the effective worker count.",
  "The primary scaling grid forces BLAS to one thread for package-worker stages;",
  "the separate interaction run varies BLAS and package worker limits explicitly."
), file.path(out_dir, "README.md"))
