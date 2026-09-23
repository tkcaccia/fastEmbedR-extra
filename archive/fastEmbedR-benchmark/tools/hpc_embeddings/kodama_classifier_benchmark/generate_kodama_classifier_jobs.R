#!/usr/bin/env Rscript

# Generate separate PLS-LDA and KNN Slurm jobs. Datasets with more than
# 10,000 rows receive default, 10%, 20%, and 50% landmark jobs.

args <- commandArgs(trailingOnly = TRUE)
output_dir <- if (length(args)) {
  args[[1L]]
} else {
  file.path(getwd(), "kodama_classifier_jobs_by_dataset")
}
dir.create(output_dir, recursive = TRUE, showWarnings = FALSE)

dataset_n <- c(
  COIL20 = 1440L,
  USPS = 11000L,
  FashionMNIST = 70000L,
  `FlowRepository_FR-FCM-ZYRM_files` = 5220347L,
  flow18 = 1000021L,
  MNIST = 70000L,
  imagenet = 1281167L,
  MetRef = 873L,
  mass41 = 965282L,
  TabulaMuris = 70118L,
  Macosko2015_retina = 44808L
)
large_threshold <- 10000L
classifiers <- c("pls_lda", "knn")
profiles <- list(
  cpu1 = list(
    backend = "cpu", threads = 1L, ntasks = 1L,
    account = "immunology", partition = "ada", gpu = character()
  ),
  cpu4 = list(
    backend = "cpu", threads = 4L, ntasks = 4L,
    account = "immunology", partition = "ada", gpu = character()
  ),
  cuda = list(
    backend = "cuda", threads = 1L, ntasks = 1L,
    account = "l40sfree", partition = "l40s",
    gpu = "#SBATCH --gres=gpu:l40s:1"
  )
)
landmark_variants <- function(n) {
  output <- list(default = list(mode = "default", fraction = NA_real_))
  if (n > large_threshold) {
    output$landmark10 <- list(mode = "fraction", fraction = 0.10)
    output$landmark20 <- list(mode = "fraction", fraction = 0.20)
    output$landmark50 <- list(mode = "fraction", fraction = 0.50)
  }
  output
}
memory_gb <- function(dataset, backend) {
  if (dataset %in% c("imagenet", "FlowRepository_FR-FCM-ZYRM_files")) {
    if (backend == "cuda") 192L else 320L
  } else if (dataset %in% c("flow18", "mass41")) {
    if (backend == "cuda") 128L else 192L
  } else if (backend == "cuda") {
    96L
  } else {
    96L
  }
}
safe_name <- function(x) gsub("[^A-Za-z0-9_.-]+", "_", x)

rows <- list()
for (dataset in names(dataset_n)) {
  for (classifier in classifiers) {
    for (profile_name in names(profiles)) {
      profile <- profiles[[profile_name]]
      for (variant_name in names(landmark_variants(dataset_n[[dataset]]))) {
        variant <- landmark_variants(dataset_n[[dataset]])[[variant_name]]
        safe_dataset <- safe_name(dataset)
        file <- sprintf(
          "run_kodama_%s_%s_%s_%s.sh",
          classifier, safe_dataset, profile_name, variant_name
        )
        path <- file.path(output_dir, file)
        fraction <- if (is.na(variant$fraction)) "NA" else {
          format(variant$fraction, nsmall = 2L)
        }
        optional <- c(
          profile$gpu,
          sprintf("#SBATCH --mem=%dG", memory_gb(dataset, profile$backend)),
          if (profile$backend == "cuda") "#SBATCH --requeue" else character()
        )
        lines <- c(
          "#!/usr/bin/env bash",
          "",
          sprintf("#SBATCH --account=%s", profile$account),
          sprintf("#SBATCH --partition=%s", profile$partition),
          "#SBATCH --nodes=1",
          sprintf("#SBATCH --ntasks=%d", profile$ntasks),
          optional,
          "#SBATCH --time=48:00:00",
          "#SBATCH --array=0-2",
          sprintf(
            "#SBATCH --job-name=\"K_%s_%s_%s_%s\"",
            if (classifier == "pls_lda") "PLS" else "KNN",
            substr(safe_dataset, 1L, 12L), profile_name, variant_name
          ),
          "#SBATCH --chdir=/scratch/firenze/NN",
          sprintf(
            "#SBATCH --output=/scratch/firenze/NN/benchmark_logs/KODAMA_%s_%s_%s_%s_%%A_%%a.out",
            classifier, safe_dataset, profile_name, variant_name
          ),
          sprintf(
            "#SBATCH --error=/scratch/firenze/NN/benchmark_logs/KODAMA_%s_%s_%s_%s_%%A_%%a.err",
            classifier, safe_dataset, profile_name, variant_name
          ),
          "",
          "set -euo pipefail",
          "",
          sprintf("export BENCHMARK_DATASET=\"%s\"", dataset),
          sprintf("export KODAMA_CLASSIFIER=\"%s\"", classifier),
          sprintf("export KODAMA_BACKEND=\"%s\"", profile$backend),
          sprintf("export KODAMA_THREADS=\"%d\"", profile$threads),
          sprintf("export KODAMA_LANDMARK_MODE=\"%s\"", variant$mode),
          sprintf("export KODAMA_LANDMARK_FRACTION=\"%s\"", fraction),
          "export KODAMA_DEFAULT_LANDMARKS=\"10000000\"",
          sprintf("export KODAMA_LARGE_THRESHOLD=\"%d\"", large_threshold),
          "export KODAMA_M=\"100\"",
          "export KODAMA_TCYCLE=\"100\"",
          "export KODAMA_NCOMP=\"50\"",
          "export KODAMA_K=\"30\"",
          "export KODAMA_PERPLEXITY=\"30\"",
          "export KODAMA_GRAPH_NEIGHBORS=\"100\"",
          "seed_values=(4 17 42)",
          "seed_index=\"${SLURM_ARRAY_TASK_ID:-0}\"",
          "export SEEDS=\"${seed_values[${seed_index}]}\"",
          "export TIMEOUT=\"172800\"",
          "export FORCE=\"FALSE\"",
          "export BASE_DIR=\"/scratch/firenze/NN\"",
          "",
          "exec bash \"${BASE_DIR}/benchmark_scripts/kodama_classifier_benchmark/run_kodama_classifier_job.sh\""
        )
        writeLines(lines, path, useBytes = TRUE)
        Sys.chmod(path, mode = "0755")
        rows[[length(rows) + 1L]] <- data.frame(
          dataset = dataset,
          n = dataset_n[[dataset]],
          classifier = classifier,
          profile = profile_name,
          backend = profile$backend,
          n.cores = profile$threads,
          landmark_variant = variant_name,
          landmark_mode = variant$mode,
          landmark_fraction = variant$fraction,
          seed_array = "4,17,42",
          file = file,
          stringsAsFactors = FALSE
        )
      }
    }
  }
}
manifest <- do.call(rbind, rows)
write.csv(manifest, file.path(output_dir, "job_manifest.csv"), row.names = FALSE)

write_submitter <- function(classifier) {
  path <- file.path(
    output_dir,
    if (classifier == "pls_lda") {
      "submit_all_kodama_plslda.sh"
    } else {
      "submit_all_kodama_knn.sh"
    }
  )
  pattern <- if (classifier == "pls_lda") {
    "run_kodama_pls_lda_*.sh"
  } else {
    "run_kodama_knn_*.sh"
  }
  writeLines(
    c(
      "#!/usr/bin/env bash",
      "set -euo pipefail",
      "script_dir=\"$(cd \"$(dirname \"${BASH_SOURCE[0]}\")\" && pwd)\"",
      "shopt -s nullglob",
      sprintf("jobs=(\"${script_dir}\"/%s)", pattern),
      "if (( ${#jobs[@]} == 0 )); then",
      "  echo \"No matching KODAMA launchers found.\" >&2",
      "  exit 1",
      "fi",
      "for job in \"${jobs[@]}\"; do",
      "  sbatch \"${job}\"",
      "done"
    ),
    path,
    useBytes = TRUE
  )
  Sys.chmod(path, mode = "0755")
}
write_submitter("pls_lda")
write_submitter("knn")

cat(
  sprintf(
    "Generated %d classifier-specific KODAMA jobs in %s\n",
    nrow(manifest), normalizePath(output_dir)
  )
)
