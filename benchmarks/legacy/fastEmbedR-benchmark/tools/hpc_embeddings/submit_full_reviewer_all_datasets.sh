#!/usr/bin/env bash

# Submit the complete reviewer benchmark: every dataset, every standard
# method, and the KODAMA workflows already included in the shared runner.
# Each dataset/profile gets an independent Slurm job and an independent output
# directory, so a timeout or OOM does not stop the rest of the benchmark.
#
# Run on the HPC from /scratch/firenze/NN, for example:
#   bash submit_full_reviewer_all_datasets.sh
#   PROFILE=cpu4 bash submit_full_reviewer_all_datasets.sh
#   PROFILE=cuda DRY_RUN=true bash submit_full_reviewer_all_datasets.sh

set -uo pipefail

BASE_DIR="${BASE_DIR:-/scratch/firenze/NN}"
JOBS_DIR="${JOBS_DIR:-${BASE_DIR}/jobs_by_dataset}"
PROFILE="${PROFILE:-all}"
DRY_RUN="${DRY_RUN:-false}"
FORCE="${FORCE:-FALSE}"
SUBMIT_SLEEP="${SUBMIT_SLEEP:-0.2}"
LOG_DIR="${LOG_DIR:-${BASE_DIR}/benchmark_logs}"
STAMP="${STAMP:-$(date +%Y%m%d_%H%M%S)}"
RESULTS_ROOT="${RESULTS_ROOT:-${BASE_DIR}/fastEmbedR-results/full_reviewer_${STAMP}}"
SUBMISSION_LOG="${SUBMISSION_LOG:-${RESULTS_ROOT}/submission_manifest.csv}"

case "${PROFILE}" in
  all)  scripts=("${JOBS_DIR}"/run_*.sh) ;;
  cpu1) scripts=("${JOBS_DIR}"/run_*_cpu1.sh) ;;
  cpu4) scripts=("${JOBS_DIR}"/run_*_cpu4.sh) ;;
  cuda) scripts=("${JOBS_DIR}"/run_*_cuda.sh) ;;
  *) echo "PROFILE must be one of: all, cpu1, cpu4, cuda" >&2; exit 2 ;;
esac

if [[ ! -d "${JOBS_DIR}" || ! -f "${scripts[0]}" ]]; then
  echo "No ${PROFILE} reviewer launchers found under ${JOBS_DIR}" >&2
  exit 1
fi

dry_run="$(printf '%s' "${DRY_RUN}" | tr '[:upper:]' '[:lower:]')"
if [[ ! "${dry_run}" =~ ^(true|1|yes)$ ]] && ! command -v sbatch >/dev/null 2>&1; then
  echo "sbatch was not found." >&2
  exit 1
fi

mkdir -p "${LOG_DIR}" "${RESULTS_ROOT}"
printf 'submitted_at,profile,dataset,script,job_id,status,output_dir,message\n' \
  > "${SUBMISSION_LOG}"

submitted=0
failed=0
for script in "${scripts[@]}"; do
  script_name="$(basename "${script}")"
  profile=""
  case "${script_name}" in
    *_cpu1.sh) profile=cpu1 ;;
    *_cpu4.sh) profile=cpu4 ;;
    *_cuda.sh) profile=cuda ;;
    *) echo "Cannot infer profile from ${script_name}" >&2; failed=$((failed + 1)); continue ;;
  esac

  dataset="${script_name#run_}"
  dataset="${dataset%_${profile}.sh}"
  safe_dataset="$(printf '%s' "${dataset}" | tr -c 'A-Za-z0-9_.-' '_')"
  output_dir="${RESULTS_ROOT}/${safe_dataset}/${profile}"
  mkdir -p "${output_dir}"

  export_values="ALL,OUT_DIR=${output_dir},RUN_STAMP=${STAMP},FORCE=${FORCE},BENCHMARK_METHODS=,REFERENCE_VALIDATIONS=TRUE"
  if [[ "${dry_run}" =~ ^(true|1|yes)$ ]]; then
    echo "DRY RUN: sbatch --export=${export_values} ${script}"
    printf '%s,%s,%s,%s,%s,%s,%s,%s\n' \
      "$(date '+%Y-%m-%d %H:%M:%S')" "${profile}" "${dataset}" \
      "${script_name}" "" "dry_run" "${output_dir}" "not submitted" \
      >> "${SUBMISSION_LOG}"
    continue
  fi

  echo "Submitting ${script_name} -> ${output_dir}"
  output="$(sbatch --parsable --export="${export_values}" "${script}" 2>&1)"
  status=$?
  if [[ ${status} -eq 0 ]]; then
    job_id="${output%%;*}"
    echo "  job ${job_id}"
    printf '%s,%s,%s,%s,%s,%s,%s,%s\n' \
      "$(date '+%Y-%m-%d %H:%M:%S')" "${profile}" "${dataset}" \
      "${script_name}" "${job_id}" "submitted" "${output_dir}" "" \
      >> "${SUBMISSION_LOG}"
    submitted=$((submitted + 1))
  else
    message="$(printf '%s' "${output}" | tr ',\n' '; ')"
    echo "  FAILED: ${message}" >&2
    printf '%s,%s,%s,%s,%s,%s,%s,%s\n' \
      "$(date '+%Y-%m-%d %H:%M:%S')" "${profile}" "${dataset}" \
      "${script_name}" "" "failed" "${output_dir}" "${message}" \
      >> "${SUBMISSION_LOG}"
    failed=$((failed + 1))
  fi
  sleep "${SUBMIT_SLEEP}"
done

echo "Submitted jobs: ${submitted}"
echo "Failed submissions: ${failed}"
echo "Results root: ${RESULTS_ROOT}"
echo "Submission manifest: ${SUBMISSION_LOG}"
[[ ${failed} -eq 0 ]]
