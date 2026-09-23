#!/usr/bin/env Rscript

# Generate convenient per-dataset submission wrappers. The actual Slurm
# resource requests and benchmark method lists remain in profile launchers.

args <- commandArgs(trailingOnly = TRUE)
script_arg <- grep("^--file=", commandArgs(FALSE), value = TRUE)
script_path <- if (length(script_arg)) {
  normalizePath(sub("^--file=", "", script_arg[[1L]]), mustWork = TRUE)
} else {
  normalizePath("generate_dataset_submitters.R", mustWork = TRUE)
}

output_dir <- if (length(args)) args[[1L]] else {
  file.path(dirname(script_path), "dataset_submitters")
}
dir.create(output_dir, recursive = TRUE, showWarnings = FALSE)

datasets <- c(
  "COIL20", "USPS", "FashionMNIST", "FlowRepository_FR-FCM-ZYRM_files",
  "flow18", "MNIST", "imagenet", "MetRef", "mass41", "TabulaMuris",
  "Macosko2015_retina"
)

safe_name <- function(x) gsub("[^A-Za-z0-9_.-]+", "_", x)

write_submitter <- function(dataset, kodama = FALSE) {
  safe <- safe_name(dataset)
  suffix <- if (kodama) "KODAMA" else "all_methods"
  path <- file.path(output_dir, sprintf("run_%s_%s.sh", safe, suffix))
  jobs_dir <- if (kodama) "kodama_jobs_by_dataset" else "jobs_by_dataset"
  job_prefix <- if (kodama) "run_kodama_" else "run_"
  lines <- c(
    "#!/usr/bin/env bash",
    "# Submit all execution profiles for one dataset.",
    "# This wrapper submits independent CPU-1, CPU-4, and CUDA Slurm jobs.",
    "set -euo pipefail",
    "",
    "BASE_DIR=\"${BASE_DIR:-/scratch/firenze/NN}\"",
    sprintf("JOBS_DIR=\"${JOBS_DIR:-${BASE_DIR}/%s}\"", jobs_dir),
    "DRY_RUN=\"${DRY_RUN:-false}\"",
    "SUBMIT_SLEEP=\"${SUBMIT_SLEEP:-0.1}\"",
    sprintf("DATASET=\"%s\"", dataset),
    "",
    "dry_run=\"$(printf '%s' \"${DRY_RUN}\" | tr '[:upper:]' '[:lower:]')\"",
    "submitted=0",
    "failed=0",
    "for profile in cpu1 cpu4 cuda; do",
    sprintf("  script=\"${JOBS_DIR}/%s${DATASET}_${profile}.sh\"", job_prefix),
    "  if [[ ! -f \"${script}\" ]]; then",
    "    echo \"Missing launcher: ${script}\" >&2",
    "    failed=$((failed + 1))",
    "    continue",
    "  fi",
    "  if [[ \"${dry_run}\" =~ ^(true|1|yes)$ ]]; then",
    "    echo \"DRY RUN: sbatch ${script}\"",
    "  else",
    "    echo \"Submitting ${script}\"",
    "    output=\"$(sbatch --parsable --export=ALL \"${script}\" 2>&1)\" || {",
    "      echo \"FAILED: ${output}\" >&2",
    "      failed=$((failed + 1))",
    "      continue",
    "    }",
    "    echo \"  job ${output%%;*}\"",
    "    submitted=$((submitted + 1))",
    "  fi",
    "  sleep \"${SUBMIT_SLEEP}\"",
    "done",
    "echo \"Dataset: ${DATASET}\"",
    "echo \"Submitted: ${submitted}\"",
    "echo \"Failed: ${failed}\"",
    "[[ ${failed} -eq 0 ]]"
  )
  writeLines(lines, path, useBytes = TRUE)
  Sys.chmod(path, mode = "0755")
  data.frame(
    dataset = dataset,
    workflow = if (kodama) "KODAMA" else "all_methods",
    file = basename(path),
    profiles = "cpu1,cpu4,cuda",
    stringsAsFactors = FALSE
  )
}

manifest <- do.call(rbind, c(
  lapply(datasets, write_submitter, kodama = FALSE),
  lapply(datasets, write_submitter, kodama = TRUE)
))
write.csv(manifest, file.path(output_dir, "submitter_manifest.csv"), row.names = FALSE)
cat(sprintf("Generated %d per-dataset submitters in %s\n", nrow(manifest), normalizePath(output_dir)))
