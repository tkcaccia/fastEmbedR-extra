#!/usr/bin/env bash
# Submit all execution profiles for one dataset.
# This wrapper submits independent CPU-1, CPU-4, and CUDA Slurm jobs.
set -euo pipefail

BASE_DIR="${BASE_DIR:-/scratch/firenze/NN}"
JOBS_DIR="${JOBS_DIR:-${BASE_DIR}/jobs_by_dataset}"
DRY_RUN="${DRY_RUN:-false}"
SUBMIT_SLEEP="${SUBMIT_SLEEP:-0.1}"
DATASET="FashionMNIST"

dry_run="$(printf '%s' "${DRY_RUN}" | tr '[:upper:]' '[:lower:]')"
submitted=0
failed=0
for profile in cpu1 cpu4 cuda; do
  script="${JOBS_DIR}/run_${DATASET}_${profile}.sh"
  if [[ ! -f "${script}" ]]; then
    echo "Missing launcher: ${script}" >&2
    failed=$((failed + 1))
    continue
  fi
  if [[ "${dry_run}" =~ ^(true|1|yes)$ ]]; then
    echo "DRY RUN: sbatch ${script}"
  else
    echo "Submitting ${script}"
    output="$(sbatch --parsable --export=ALL "${script}" 2>&1)" || {
      echo "FAILED: ${output}" >&2
      failed=$((failed + 1))
      continue
    }
    echo "  job ${output%%;*}"
    submitted=$((submitted + 1))
  fi
  sleep "${SUBMIT_SLEEP}"
done
echo "Dataset: ${DATASET}"
echo "Submitted: ${submitted}"
echo "Failed: ${failed}"
[[ ${failed} -eq 0 ]]
