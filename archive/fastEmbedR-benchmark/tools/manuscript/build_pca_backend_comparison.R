#!/usr/bin/env Rscript

args <- commandArgs(trailingOnly = TRUE)
generated_dir <- if (length(args) >= 1L) args[[1L]] else
  file.path("manuscript", "mloss", "generated")

local_path <- file.path(generated_dir, "local_pca_runtime.csv")
hpc_path <- file.path(generated_dir, "successful_standard_results.csv")
if (!file.exists(local_path)) {
  stop("Missing local PCA summary: ", local_path, call. = FALSE)
}
if (!file.exists(hpc_path)) {
  stop("Missing HPC PCA summary: ", hpc_path, call. = FALSE)
}

local <- read.csv(local_path, stringsAsFactors = FALSE, check.names = FALSE)
hpc <- read.csv(hpc_path, stringsAsFactors = FALSE, check.names = FALSE)

local <- local[
  local$dataset == "MNIST" &
    local$method %in% c("fastEmbedR_pca_cpu", "fastEmbedR_pca_metal"),
  ,
  drop = FALSE
]
hpc <- hpc[
  hpc$dataset == "MNIST" &
    hpc$method %in% c("fastEmbedR_pca_cpu", "fastEmbedR_pca_cuda"),
  ,
  drop = FALSE
]

make_rows <- function(x, machine, hardware) {
  data.frame(
    dataset = x$dataset,
    machine = machine,
    hardware = hardware,
    backend = toupper(x$backend),
    n.cores = ifelse(x$backend == "cpu", x$requested_threads, NA_integer_),
    n_runs = x$n_runs,
    runtime_sec_median = x$total_runtime_sec_median,
    runtime_sec_q1 = x$total_runtime_sec_q1,
    runtime_sec_q3 = x$total_runtime_sec_q3,
    source_file = x$source_file %||% NA_character_,
    stringsAsFactors = FALSE
  )
}

`%||%` <- function(x, y) {
  if (is.null(x)) y else x
}

local_rows <- make_rows(
  local,
  "Local Mac",
  "Apple M3 (8 CPU cores; integrated Metal GPU)"
)
hpc_rows <- make_rows(
  hpc,
  "HPC",
  "Intel Xeon Gold 6442Y; NVIDIA L40S"
)
comparison <- rbind(local_rows, hpc_rows)
comparison$backend <- factor(comparison$backend, levels = c("CPU", "METAL", "CUDA"))
comparison$machine <- factor(
  comparison$machine,
  levels = c("Local Mac", "HPC")
)
comparison <- comparison[
  order(comparison$machine, comparison$backend, comparison$n.cores),
  ,
  drop = FALSE
]
comparison$backend <- as.character(comparison$backend)
comparison$machine <- as.character(comparison$machine)
comparison$speedup_vs_cpu1 <- NA_real_
for (machine in unique(comparison$machine)) {
  rows <- comparison$machine == machine
  baseline <- comparison$runtime_sec_median[
    rows & comparison$backend == "CPU" & comparison$n.cores == 1L
  ]
  if (length(baseline) == 1L && is.finite(baseline)) {
    comparison$speedup_vs_cpu1[rows] <-
      baseline / comparison$runtime_sec_median[rows]
  }
}

csv_path <- file.path(generated_dir, "pca_backend_speed_mnist70k.csv")
write.csv(comparison, csv_path, row.names = FALSE, na = "")

escape_latex <- function(x) {
  x <- gsub("\\\\", "\\\\textbackslash{}", x)
  x <- gsub("_", "\\\\_", x, fixed = TRUE)
  x <- gsub("&", "\\\\&", x, fixed = TRUE)
  x
}
fmt <- function(x, digits = 3L) {
  ifelse(is.finite(x), formatC(x, digits = digits, format = "f"), "--")
}
machine_label <- ifelse(
  comparison$machine == "Local Mac",
  "MacBook Pro (M3)",
  "HPC Xeon/L40S"
)
backend_label <- c(CPU = "CPU", METAL = "Metal", CUDA = "CUDA")[
  comparison$backend
]
core_label <- ifelse(is.na(comparison$n.cores), "--", comparison$n.cores)
runtime_label <- paste0(
  fmt(comparison$runtime_sec_median), " (",
  fmt(comparison$runtime_sec_q1), "--",
  fmt(comparison$runtime_sec_q3), ")"
)
lines <- c(
  "\\begin{tabular}{lllrr}",
  "\\toprule",
  "Machine & Backend & CPU cores & Runtime, s & Speedup vs. CPU-1 \\\\",
  "\\midrule",
  paste0(
    escape_latex(machine_label), " & ",
    escape_latex(backend_label), " & ",
    core_label, " & ",
    runtime_label, " & ",
    fmt(comparison$speedup_vs_cpu1, 2L),
    " \\\\"
  ),
  "\\bottomrule",
  "\\end{tabular}"
)
writeLines(lines, file.path(generated_dir, "pca_backend_speed_mnist70k.tex"))

message("Wrote ", csv_path)
