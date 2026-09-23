#!/usr/bin/env bash

# Copy the current standard, landmark, and KODAMA benchmark drivers into the
# local HPC mirror after /Users/stefano/HPC-firenze has been mounted.

set -euo pipefail

script_path="${BASH_SOURCE[0]:-$0}"
script_dir="$(cd "$(dirname "${script_path}")" && pwd)"
hpc_root="${HPC_ROOT:-/Users/stefano/HPC-firenze/NN}"

if [[ ! -d "${hpc_root}" ]]; then
  echo "HPC mirror is unavailable: ${hpc_root}" >&2
  exit 1
fi

core_files=(
  benchmark_embeddings_float32_publication.R
  benchmark_python_direct.py
  benchmark_embeddings_float32_cpu12.sh
  benchmark_embeddings_float32_cuda.sh
  benchmark_reviewer_validation.R
  publication_metrics.R
  reference_opentsne_affinity.py
  benchmark_worker_monitor.sh
  move_inputs_to_fastembedr_input.sh
  run_reviewer_dataset_job.sh
  run_reviewer_hpc_cpu.sh
  run_reviewer_hpc_cuda.sh
  run_landmark_dataset_job.sh
  submit_reviewer_dataset_jobs.sh
  submit_landmark_dataset_jobs.sh
  submit_kodama_dataset_jobs.sh
  generate_reviewer_dataset_jobs.R
  generate_landmark_dataset_jobs.R
  generate_kodama_dataset_jobs.R
)

for name in "${core_files[@]}"; do
  cp -p "${script_dir}/${name}" "${hpc_root}/${name}"
done

mkdir -p \
  "${hpc_root}/jobs_by_dataset" \
  "${hpc_root}/landmark_jobs_by_dataset" \
  "${hpc_root}/kodama_jobs_by_dataset"

cp -p "${script_dir}/jobs_by_dataset/"*.sh \
  "${hpc_root}/jobs_by_dataset/"
cp -p "${script_dir}/jobs_by_dataset/job_manifest.csv" \
  "${hpc_root}/jobs_by_dataset/job_manifest.csv"
cp -p "${script_dir}/landmark_jobs_by_dataset/"*.sh \
  "${hpc_root}/landmark_jobs_by_dataset/"
cp -p "${script_dir}/landmark_jobs_by_dataset/job_manifest.csv" \
  "${hpc_root}/landmark_jobs_by_dataset/job_manifest.csv"
cp -p "${script_dir}/kodama_jobs_by_dataset/"*.sh \
  "${hpc_root}/kodama_jobs_by_dataset/"
cp -p "${script_dir}/kodama_jobs_by_dataset/job_manifest.csv" \
  "${hpc_root}/kodama_jobs_by_dataset/job_manifest.csv"

for path in \
  "${hpc_root}/benchmark_worker_monitor.sh" \
  "${hpc_root}/benchmark_embeddings_float32_cpu12.sh" \
  "${hpc_root}/benchmark_embeddings_float32_cuda.sh" \
  "${hpc_root}/benchmark_python_direct.py" \
  "${hpc_root}/move_inputs_to_fastembedr_input.sh" \
  "${hpc_root}/run_reviewer_dataset_job.sh" \
  "${hpc_root}/run_reviewer_hpc_cpu.sh" \
  "${hpc_root}/run_reviewer_hpc_cuda.sh" \
  "${hpc_root}/run_landmark_dataset_job.sh" \
  "${hpc_root}/submit_reviewer_dataset_jobs.sh" \
  "${hpc_root}/submit_landmark_dataset_jobs.sh" \
  "${hpc_root}/submit_kodama_dataset_jobs.sh" \
  "${hpc_root}/jobs_by_dataset/"*.sh \
  "${hpc_root}/landmark_jobs_by_dataset/"*.sh \
  "${hpc_root}/kodama_jobs_by_dataset/"*.sh; do
  chmod +x "${path}" 2>/dev/null || true
done

echo "Synchronized reviewer benchmark files to ${hpc_root}"
echo "Standard launchers: $(find "${hpc_root}/jobs_by_dataset" -maxdepth 1 -name 'run_*.sh' | wc -l | tr -d ' ')"
echo "Landmark launchers: $(find "${hpc_root}/landmark_jobs_by_dataset" -maxdepth 1 -name 'run_landmark_*.sh' | wc -l | tr -d ' ')"
echo "KODAMA launchers:   $(find "${hpc_root}/kodama_jobs_by_dataset" -maxdepth 1 -name 'run_kodama_*.sh' | wc -l | tr -d ' ')"
