#!/usr/bin/env Rscript

script_argument <- grep("^--file=", commandArgs(FALSE), value = TRUE)
script_path <- normalizePath(
  sub("^--file=", "", script_argument[[1L]]),
  mustWork = TRUE
)
source(file.path(dirname(script_path), "kodama_benchmark_common.R"))

args <- parse_cli(commandArgs(trailingOnly = TRUE))
layout_dir <- args$layout_dir %||% stop("--layout-dir is required.")
out_dir <- args$out_dir %||% stop("--out-dir is required.")
plot_max_points <- as_int(args$plot_max_points, 250000L)

if (!dir.exists(layout_dir)) {
  stop("Layout directory does not exist: ", layout_dir, call. = FALSE)
}
dir.create(file.path(out_dir, "plots"), recursive = TRUE, showWarnings = FALSE)

layout_files <- list.files(
  layout_dir,
  pattern = "_layout\\.rds$",
  full.names = TRUE
)
if (!length(layout_files)) {
  stop("No completed layout checkpoints were found in ", layout_dir, ".")
}

rows <- lapply(layout_files, function(layout_file) {
  value <- readRDS(layout_file)
  layout <- extract_layout(value$layout %||% value)
  labels <- value$labels %||% NULL
  kodama_labels <- value$kodama_labels %||% NULL
  seed <- as_int(value$seed, 4L)
  stem <- sub("_layout\\.rds$", "", basename(layout_file))
  truth_file <- file.path(out_dir, "plots", paste0(stem, "_truth.png"))
  kodama_file <- file.path(
    out_dir,
    "plots",
    paste0(stem, "_kodama_labels.png")
  )

  truth <- safe_embedding_plot(
    layout,
    labels,
    truth_file,
    seed,
    plot_max_points
  )
  kodama <- safe_embedding_plot(
    layout,
    kodama_labels,
    kodama_file,
    seed,
    plot_max_points
  )
  errors <- c(truth$error, kodama$error)
  errors <- errors[!is.na(errors) & nzchar(errors)]

  data.frame(
    dataset = as.character(value$dataset %||% NA_character_),
    classifier = as.character(value$classifier %||% NA_character_),
    visualization = as.character(value$visualization %||% NA_character_),
    backend = as.character(value$backend %||% NA_character_),
    seed = seed,
    n = nrow(layout),
    status = if (length(errors)) "partial" else "success",
    error = if (length(errors)) {
      paste(unique(errors), collapse = " | ")
    } else {
      NA_character_
    },
    layout_file = layout_file,
    truth_plot_file = truth$file,
    kodama_label_plot_file = kodama$file,
    plot_sample_n = truth$sample_n,
    stringsAsFactors = FALSE
  )
})

manifest <- do.call(rbind, rows)
manifest_file <- file.path(out_dir, "recovered_plot_manifest.csv")
atomic_write_csv(manifest, manifest_file)
print(manifest)
cat("Recovered plot manifest:", manifest_file, "\n")
