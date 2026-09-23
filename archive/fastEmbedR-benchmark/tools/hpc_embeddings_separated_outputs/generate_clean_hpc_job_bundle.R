#!/usr/bin/env Rscript

# Generate a self-contained Slurm handoff with R, Python, KODAMA, and landmark
# workflows separated by dataset and execution profile.

args <- commandArgs(trailingOnly = TRUE)
script_arg <- grep("^--file=", commandArgs(FALSE), value = TRUE)
script_path <- if (length(script_arg)) {
  normalizePath(sub("^--file=", "", script_arg[[1L]]), mustWork = TRUE)
} else {
  normalizePath("generate_clean_hpc_job_bundle.R", mustWork = TRUE)
}
source_dir <- dirname(script_path)
package_tools <- normalizePath(file.path(source_dir, "..", "hpc_embeddings"), mustWork = TRUE)
output_dir <- if (length(args)) args[[1L]] else {
  "/Users/stefano/HPC-firenze/NN/fastEmbedR_benchmark_jobs"
}
dir.create(output_dir, recursive = TRUE, showWarnings = FALSE)

datasets <- c(
  "COIL20", "USPS", "FashionMNIST", "FlowRepository_FR-FCM-ZYRM_files",
  "flow18", "MNIST", "imagenet", "MetRef", "mass41", "TabulaMuris",
  "Macosko2015_retina"
)

profiles <- list(
  cpu1 = list(
    backend = "cpu", threads = 1L, account = "immunology", partition = "ada",
    ntasks = 1L, extra = character()
  ),
  cpu4 = list(
    backend = "cpu", threads = 4L, account = "immunology", partition = "ada",
    ntasks = 4L, extra = character()
  ),
  cuda = list(
    backend = "cuda", threads = 1L, account = "l40sfree", partition = "l40s",
    ntasks = 1L,
    extra = c("#SBATCH --gres=gpu:l40s:1", "#SBATCH --mem=64G")
  )
)

r_cpu_methods <- paste(c(
  "fastEmbedR_pca_cpu", "irlba_pca",
  "fastEmbedR_opentsne_cpu_full", "fastEmbedR_opentsne_cpu_knn",
  "Rtsne_full", "Rtsne_neighbors", "KlugerLab_FItSNE",
  "fastEmbedR_umap_cpu_fuzzy_full", "fastEmbedR_umap_cpu_fuzzy_knn",
  "fastEmbedR_umap_cpu_binary_full", "fastEmbedR_umap_cpu_binary_knn",
  "uwot_default", "uwot_fast_sgd", "uwot_knn",
  "umap_package", "umap_package_knn"
), collapse = ",")
r_cuda_methods <- paste(c(
  "fastEmbedR_pca_cuda",
  "fastEmbedR_opentsne_cuda_full", "fastEmbedR_opentsne_cuda_knn",
  "fastEmbedR_umap_cuda_fuzzy_full", "fastEmbedR_umap_cuda_fuzzy_knn",
  "fastEmbedR_umap_cuda_binary_full", "fastEmbedR_umap_cuda_binary_knn"
), collapse = ",")
python_cpu_methods <- paste(c(
  "python_opentsne_fft", "python_opentsne_fft_direct",
  "python_umap_learn", "python_umap_learn_direct"
), collapse = ",")
python_cuda_methods <- paste(c(
  "rapids_cuml_tsne_full", "rapids_cuml_tsne_full_direct",
  "rapids_cuml_umap_full", "rapids_cuml_umap_full_direct"
), collapse = ",")
kodama_cpu_methods <- paste(c(
  "KODAMA_plslda_opentsne_cpu", "KODAMA_plslda_umap_cpu",
  "KODAMA_knn_opentsne_cpu", "KODAMA_knn_umap_cpu"
), collapse = ",")
kodama_cuda_methods <- paste(c(
  "KODAMA_plslda_opentsne_cuda", "KODAMA_plslda_umap_cuda",
  "KODAMA_knn_opentsne_cuda", "KODAMA_knn_umap_cuda"
), collapse = ",")

suites <- list(
  r_embedding_methods = list(
    runner = "run_reviewer_dataset_job.sh", benchmark_suite = "standard",
    cpu_methods = r_cpu_methods, cuda_methods = r_cuda_methods, job_tag = "R"
  ),
  python_embedding_methods = list(
    runner = "run_python_dataset_job.sh", benchmark_suite = "python",
    cpu_methods = python_cpu_methods, cuda_methods = python_cuda_methods,
    job_tag = "Py"
  ),
  kodama_methods = list(
    runner = "run_reviewer_dataset_job.sh", benchmark_suite = "kodama",
    cpu_methods = kodama_cpu_methods, cuda_methods = kodama_cuda_methods,
    job_tag = "Kod"
  ),
  landmark_methods = list(
    runner = "run_landmark_dataset_job.sh", benchmark_suite = "landmark",
    cpu_methods = "", cuda_methods = "", job_tag = "Land"
  )
)

safe_name <- function(x) gsub("[^A-Za-z0-9_.-]+", "_", x)

write_launcher <- function(dataset, suite_name, suite, profile_name, profile) {
  safe <- safe_name(dataset)
  target_dir <- file.path(output_dir, suite_name, profile_name)
  dir.create(target_dir, recursive = TRUE, showWarnings = FALSE)
  path <- file.path(target_dir, sprintf("run_%s_%s.sh", safe, profile_name))
  methods <- if (identical(profile$backend, "cuda")) {
    suite$cuda_methods
  } else {
    suite$cpu_methods
  }
  optional <- profile$extra[nzchar(profile$extra)]
  job_name <- sprintf(
    "feR_%s_%s_%s", suite$job_tag, substr(safe, 1L, 18L), profile_name
  )
  log_tag <- sprintf("%s_%s_%s", suite_name, safe, profile_name)
  shared_runner <- sprintf(
    "${BASE_DIR}/fastEmbedR_benchmark_jobs/shared/%s", suite$runner
  )

  lines <- c(
    "#!/usr/bin/env bash", "",
    sprintf("#SBATCH --account=%s", profile$account),
    sprintf("#SBATCH --partition=%s", profile$partition),
    "#SBATCH --nodes=1",
    sprintf("#SBATCH --ntasks=%d", profile$ntasks),
    optional,
    "#SBATCH --time=48:00:00",
    sprintf("#SBATCH --job-name=\"%s\"", job_name),
    "#SBATCH --chdir=/scratch/firenze/NN",
    sprintf(
      "#SBATCH --output=/scratch/firenze/NN/benchmark_logs/%s_%%j.out",
      log_tag
    ),
    sprintf(
      "#SBATCH --error=/scratch/firenze/NN/benchmark_logs/%s_%%j.err",
      log_tag
    ),
    "", "set -euo pipefail", "",
    sprintf("export BENCHMARK_DATASET=\"%s\"", dataset),
    sprintf("export BENCHMARK_BACKEND_GROUP=\"%s\"", profile$backend),
    sprintf("export BENCHMARK_THREADS=\"%d\"", profile$threads),
    sprintf("export BENCHMARK_SUITE=\"%s\"", suite$benchmark_suite),
    "export BASE_DIR=\"${BASE_DIR:-/scratch/firenze/NN}\"",
    "export DATA_ROOT=\"${DATA_ROOT:-${BASE_DIR}/Data}\"",
    "export SINGULARITY_IMAGE=\"${SINGULARITY_IMAGE:-${BASE_DIR}/singularity/fastembedr_cuda.sif}\"",
    "export RESULTS_ROOT=\"${RESULTS_ROOT:-${BASE_DIR}/fastEmbedR-results}\"",
    "export LAYOUT_ROOT=\"${LAYOUT_ROOT:-${BASE_DIR}/fastEmbedR-rlayout}\"",
    "export SEEDS=\"${SEEDS:-4,17,42}\"",
    "export K=\"${K:-30}\"",
    "export PERPLEXITY=\"${PERPLEXITY:-30}\"",
    "export TIMEOUT=\"${TIMEOUT:-10800}\"",
    "export FORCE=\"${FORCE:-FALSE}\"",
    "export LANDMARK_FRACTION=\"${LANDMARK_FRACTION:-0.5}\"",
    "export KODAMA_M=\"${KODAMA_M:-100}\"",
    "export KODAMA_TCYCLE=\"${KODAMA_TCYCLE:-20}\"",
    "export KODAMA_NCOMP=\"${KODAMA_NCOMP:-50}\"",
    "export KODAMA_LANDMARKS=\"${KODAMA_LANDMARKS:-10000000}\"",
    "export KODAMA_GRAPH_NEIGHBORS=\"${KODAMA_GRAPH_NEIGHBORS:-100}\""
  )
  if (nzchar(methods)) {
    lines <- c(lines, sprintf("export BENCHMARK_METHODS=\"%s\"", methods))
  }
  lines <- c(
    lines, "",
    sprintf("runner=\"%s\"", shared_runner),
    "[[ -f \"${runner}\" ]] || { echo \"Missing runner: ${runner}\" >&2; exit 1; }",
    "exec bash \"${runner}\""
  )
  writeLines(lines, path, useBytes = TRUE)
  Sys.chmod(path, mode = "0755")
  data.frame(
    dataset = dataset, suite = suite_name, profile = profile_name,
    backend = profile$backend, threads = profile$threads,
    ntasks = profile$ntasks, methods = methods, file = path,
    stringsAsFactors = FALSE
  )
}

rows <- list()
for (dataset in datasets) {
  for (suite_name in names(suites)) {
    suite <- suites[[suite_name]]
    for (profile_name in names(profiles)) {
      rows[[length(rows) + 1L]] <- write_launcher(
        dataset, suite_name, suite, profile_name, profiles[[profile_name]]
      )
    }
  }
}
manifest <- do.call(rbind, rows)
manifest$file <- sub(paste0("^", output_dir, "/?"), "", manifest$file)
write.csv(manifest, file.path(output_dir, "job_manifest.csv"), row.names = FALSE)

shared_dir <- file.path(output_dir, "shared")
dir.create(shared_dir, recursive = TRUE, showWarnings = FALSE)
shared_sources <- c(
  file.path(source_dir, "run_reviewer_dataset_job.sh"),
  file.path(source_dir, "run_landmark_dataset_job.sh"),
  file.path(source_dir, "run_python_dataset_job.sh"),
  file.path(source_dir, "benchmark_reviewer_validation.R"),
  file.path(source_dir, "publication_metrics.R"),
  file.path(source_dir, "benchmark_worker_monitor.sh"),
  file.path(source_dir, "reference_opentsne_affinity.py"),
  file.path(package_tools, "benchmark_embeddings_float32_publication.R"),
  file.path(package_tools, "benchmark_python_direct.py")
)
missing <- shared_sources[!file.exists(shared_sources)]
if (length(missing)) stop("Missing shared sources: ", paste(missing, collapse = ", "))
ok <- file.copy(shared_sources, shared_dir, overwrite = TRUE, copy.mode = TRUE)
if (!all(ok)) stop("Failed to copy one or more shared benchmark files.")

write_submitter <- function(suite_name) {
  path <- file.path(output_dir, sprintf("submit_%s.sh", suite_name))
  lines <- c(
    "#!/usr/bin/env bash",
    "set -euo pipefail", "",
    "BASE_DIR=\"${BASE_DIR:-/scratch/firenze/NN}\"",
    sprintf("SUITE=\"%s\"", suite_name),
    "PROFILE=\"${PROFILE:-all}\"",
    "DATASET=\"${DATASET:-all}\"",
    "DRY_RUN=\"${DRY_RUN:-false}\"",
    "JOBS_ROOT=\"${BASE_DIR}/fastEmbedR_benchmark_jobs/${SUITE}\"",
    "mkdir -p \"${BASE_DIR}/benchmark_logs\"",
    "shopt -s nullglob", "",
    "case \"${PROFILE}\" in",
    "  all) profiles=(cpu1 cpu4 cuda) ;;",
    "  cpu1|cpu4|cuda) profiles=(\"${PROFILE}\") ;;",
    "  *) echo \"PROFILE must be all, cpu1, cpu4, or cuda.\" >&2; exit 2 ;;",
    "esac", "",
    "scripts=()",
    "for profile in \"${profiles[@]}\"; do",
    "  if [[ \"${DATASET}\" == \"all\" ]]; then",
    "    scripts+=(\"${JOBS_ROOT}/${profile}\"/run_*_\"${profile}\".sh)",
    "  else",
    "    scripts+=(\"${JOBS_ROOT}/${profile}/run_${DATASET}_${profile}.sh\")",
    "  fi",
    "done",
    "[[ ${#scripts[@]} -gt 0 ]] || { echo \"No matching jobs.\" >&2; exit 1; }", "",
    "for script in \"${scripts[@]}\"; do",
    "  [[ -f \"${script}\" ]] || { echo \"Missing ${script}\" >&2; continue; }",
    "  if [[ \"${DRY_RUN}\" =~ ^(true|TRUE|1|yes|YES)$ ]]; then",
    "    echo \"DRY RUN: sbatch ${script}\"",
    "  else",
    "    sbatch \"${script}\"",
    "  fi",
    "done"
  )
  writeLines(lines, path, useBytes = TRUE)
  Sys.chmod(path, mode = "0755")
}
invisible(lapply(names(suites), write_submitter))

readme <- c(
  "# fastEmbedR HPC benchmark jobs", "",
  "Each dataset and execution profile has an independent Slurm launcher.",
  "The suites are deliberately separate:", "",
  "- `r_embedding_methods`: fastEmbedR R API, Rtsne, FIt-SNE, uwot, umap, and PCA references.",
  "- `python_embedding_methods`: Python openTSNE/umap-learn on CPU and RAPIDS cuML on CUDA, through reticulate and direct Python timing.",
  "- `kodama_methods`: KODAMA PLS-LDA and KNN, each reused for openTSNE and UMAP visualization.",
  "- `landmark_methods`: matched full versus 50% landmark fastEmbedR openTSNE and binary UMAP.", "",
  "Profiles are `cpu1`, `cpu4`, and `cuda`. CPU launchers request `--ntasks=1` or `--ntasks=4`; CUDA launchers request one L40S GPU.",
  "KODAMA uses `landmarks=10000000` by default, as requested; the implementation caps this at the dataset size.", "",
  "Submit one suite/profile:", "",
  "```bash",
  "cd /scratch/firenze/NN",
  "PROFILE=cpu4 bash fastEmbedR_benchmark_jobs/submit_r_embedding_methods.sh",
  "PROFILE=cuda bash fastEmbedR_benchmark_jobs/submit_python_embedding_methods.sh",
  "PROFILE=cuda bash fastEmbedR_benchmark_jobs/submit_kodama_methods.sh",
  "```", "",
  "Submit one dataset only:", "",
  "```bash",
  "DATASET=MNIST PROFILE=cuda bash fastEmbedR_benchmark_jobs/submit_r_embedding_methods.sh",
  "DATASET=MNIST PROFILE=cuda bash fastEmbedR_benchmark_jobs/submit_kodama_methods.sh",
  "```", "",
  "Use `DRY_RUN=true` to print submissions without sending them. Results are written under `fastEmbedR-results`; layouts are written under `fastEmbedR-rlayout`.",
  "The shared runners isolate methods, record failures, and continue with the remaining methods."
)
writeLines(readme, file.path(output_dir, "README.md"), useBytes = TRUE)

cat(sprintf(
  "Generated %d jobs (%d datasets x %d suites x %d profiles) in %s\n",
  nrow(manifest), length(datasets), length(suites), length(profiles),
  normalizePath(output_dir)
))
