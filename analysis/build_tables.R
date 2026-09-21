#!/usr/bin/env Rscript

args <- commandArgs(trailingOnly = TRUE)
input_dir <- if (length(args)) args[[1L]] else "results/aggregate"
output_dir <- if (length(args) > 1L) args[[2L]] else "results/tables"
dir.create(output_dir, recursive = TRUE, showWarnings = FALSE)

read_required <- function(filename) {
  path <- file.path(input_dir, filename)
  if (!file.exists(path)) stop("Missing input: ", path, call. = FALSE)
  read.csv(path, stringsAsFactors = FALSE, check.names = FALSE)
}

tsne <- read_required("runtime_tsne_all_methods.csv")
umap <- read_required("runtime_umap_all_methods.csv")
quality <- read_required("key_dataset_runtime_quality.csv")
parameters <- read_required("all_method_parameters.csv")
landmark <- read_required("landmark_20pct_summary.csv")

runtime_columns <- c(
  "dataset", "dataset_label", "method", "display_label", "family",
  "backend", "profile", "timing_interface", "timing_scope",
  "runtime_measure", "n_runs", "runtime", "runtime_q1", "runtime_q3"
)
runtime <- rbind(tsne[runtime_columns], umap[runtime_columns])
runtime <- runtime[order(runtime$family, runtime$dataset_label,
                         runtime$backend, runtime$method), , drop = FALSE]

write.csv(runtime, file.path(output_dir, "runtime_summary.csv"),
          row.names = FALSE, na = "")
write.csv(quality, file.path(output_dir, "runtime_quality_summary.csv"),
          row.names = FALSE, na = "")
write.csv(parameters, file.path(output_dir, "method_parameters.csv"),
          row.names = FALSE, na = "")
write.csv(landmark, file.path(output_dir, "landmark_summary.csv"),
          row.names = FALSE, na = "")

escape_markdown <- function(x) {
  x <- ifelse(is.na(x), "", as.character(x))
  gsub("|", "\\|", x, fixed = TRUE)
}

format_number <- function(x, digits = 3L) {
  x <- suppressWarnings(as.numeric(x))
  ifelse(is.finite(x), formatC(x, digits = digits, format = "fg"), "")
}

summary_table <- runtime[c(
  "dataset_label", "display_label", "timing_scope", "n_runs",
  "runtime", "runtime_q1", "runtime_q3"
)]
names(summary_table) <- c(
  "Dataset", "Method", "Timing scope", "Runs", "Median seconds",
  "Q1", "Q3"
)
summary_table$`Median seconds` <- format_number(summary_table$`Median seconds`)
summary_table$Q1 <- format_number(summary_table$Q1)
summary_table$Q3 <- format_number(summary_table$Q3)

header <- paste0("| ", paste(names(summary_table), collapse = " | "), " |")
separator <- paste0("| ", paste(rep("---", ncol(summary_table)),
                                 collapse = " | "), " |")
rows <- apply(summary_table, 1L, function(row) {
  paste0("| ", paste(escape_markdown(row), collapse = " | "), " |")
})
writeLines(c(
  "# Runtime summary",
  "",
  "Direct-Python fit and R total-call timings are distinct boundaries.",
  "Missing method-dataset combinations remain absent.",
  "",
  header, separator, rows
), file.path(output_dir, "runtime_summary.md"))
