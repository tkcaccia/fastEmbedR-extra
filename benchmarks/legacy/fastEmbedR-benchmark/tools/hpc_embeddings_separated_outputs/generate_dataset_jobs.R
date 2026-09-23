#!/usr/bin/env Rscript

args <- commandArgs(trailingOnly = TRUE)
script_arg <- grep("^--file=", commandArgs(FALSE), value = TRUE)
script_path <- if (length(script_arg)) {
  normalizePath(sub("^--file=", "", script_arg[[1L]]), mustWork = TRUE)
} else {
  normalizePath("generate_dataset_jobs.R", mustWork = TRUE)
}
output_dir <- if (length(args)) {
  args[[1L]]
} else {
  file.path(dirname(script_path), "jobs_by_dataset")
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
    ntasks = 1L, gpu = character(), memory = character()
  ),
  cpu4 = list(
    backend = "cpu", threads = 4L, account = "immunology", partition = "ada",
    ntasks = 4L, gpu = character(), memory = character()
  ),
  cuda = list(
    backend = "cuda", threads = 1L, account = "l40sfree", partition = "l40s",
    ntasks = 1L, gpu = "#SBATCH --gres=gpu:l40s:1", memory = "#SBATCH --mem=64G"
  )
)

suites <- list(
  standard = list(runner = "run_reviewer_dataset_job.sh", prefix = "std"),
  landmark = list(runner = "run_landmark_dataset_job.sh", prefix = "land"),
  kodama = list(runner = "run_reviewer_dataset_job.sh", prefix = "kod")
)

safe_name <- function(x) gsub("[^A-Za-z0-9_.-]+", "_", x)

write_launcher <- function(dataset, suite_name, suite, profile_name, profile) {
  safe <- safe_name(dataset)
  file_tag <- sprintf("%s_%s_%s", safe, suite_name, profile_name)
  path <- file.path(output_dir, sprintf("run_%s.sh", file_tag))
  optional <- c(profile$gpu, profile$memory)
  optional <- optional[nzchar(optional)]
  job_name <- paste0(
    "feR_", suite$prefix, "_", substr(safe, 1L, 20L), "_", profile_name
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
      "#SBATCH --output=/scratch/firenze/NN/benchmark_logs/fastEmbedR_%s_%%j.out",
      file_tag
    ),
    sprintf(
      "#SBATCH --error=/scratch/firenze/NN/benchmark_logs/fastEmbedR_%s_%%j.err",
      file_tag
    ),
    "", "set -euo pipefail", "",
    sprintf("export BENCHMARK_DATASET=\"%s\"", dataset),
    sprintf("export BENCHMARK_BACKEND_GROUP=\"%s\"", profile$backend),
    sprintf("export BENCHMARK_THREADS=\"%d\"", profile$threads),
    sprintf("export BENCHMARK_SUITE=\"%s\"", suite_name),
    "export LANDMARK_FRACTION=\"${LANDMARK_FRACTION:-0.5}\"",
    "export BASE_DIR=\"${BASE_DIR:-/scratch/firenze/NN}\"",
    "", "launcher_path=\"${BASH_SOURCE[0]:-$0}\"",
    "if command -v readlink >/dev/null 2>&1; then",
    "  launcher_path=\"$(readlink -f \"${launcher_path}\" 2>/dev/null || printf '%s\\n' \"${launcher_path}\")\"",
    "fi",
    "launcher_dir=\"$(cd \"$(dirname \"${launcher_path}\")\" && pwd)\"",
    sprintf("runner_name=\"%s\"", suite$runner),
    "if [[ -f \"${launcher_dir}/../${runner_name}\" ]]; then",
    "  runner=\"${launcher_dir}/../${runner_name}\"",
    "elif [[ -f \"${launcher_dir}/${runner_name}\" ]]; then",
    "  runner=\"${launcher_dir}/${runner_name}\"",
    "else",
    "  runner=\"${BASE_DIR}/${runner_name}\"",
    "fi",
    "[[ -f \"${runner}\" ]] || { echo \"Missing ${runner_name}\" >&2; exit 1; }",
    "", "exec bash \"${runner}\""
  )
  writeLines(lines, path, useBytes = TRUE)
  Sys.chmod(path, mode = "0755")
  data.frame(
    dataset = dataset, suite = suite_name, profile = profile_name,
    backend = profile$backend, threads = profile$threads, ntasks = profile$ntasks,
    landmark_fraction = if (identical(suite_name, "landmark")) 0.5 else NA_real_,
    file = basename(path), stringsAsFactors = FALSE
  )
}

manifest <- do.call(rbind, unlist(lapply(datasets, function(dataset) {
  unlist(Map(function(suite_name, suite) {
    Map(
      function(profile_name, profile) {
        write_launcher(dataset, suite_name, suite, profile_name, profile)
      },
      names(profiles), profiles
    )
  }, names(suites), suites), recursive = FALSE)
}), recursive = FALSE))

write.csv(manifest, file.path(output_dir, "job_manifest.csv"), row.names = FALSE)
cat(sprintf(
  "Generated %d launchers (%d datasets x %d suites x %d profiles) in %s\n",
  nrow(manifest), length(datasets), length(suites), length(profiles),
  normalizePath(output_dir)
))
