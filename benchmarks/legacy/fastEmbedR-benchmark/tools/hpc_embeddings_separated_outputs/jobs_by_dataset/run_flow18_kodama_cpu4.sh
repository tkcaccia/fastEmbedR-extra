#!/usr/bin/env bash

#SBATCH --account=immunology
#SBATCH --partition=ada
#SBATCH --nodes=1
#SBATCH --ntasks=4
#SBATCH --time=48:00:00
#SBATCH --job-name="feR_kod_flow18_cpu4"
#SBATCH --chdir=/scratch/firenze/NN
#SBATCH --output=/scratch/firenze/NN/benchmark_logs/fastEmbedR_flow18_kodama_cpu4_%j.out
#SBATCH --error=/scratch/firenze/NN/benchmark_logs/fastEmbedR_flow18_kodama_cpu4_%j.err

set -euo pipefail

export BENCHMARK_DATASET="flow18"
export BENCHMARK_BACKEND_GROUP="cpu"
export BENCHMARK_THREADS="4"
export BENCHMARK_SUITE="kodama"
export LANDMARK_FRACTION="${LANDMARK_FRACTION:-0.5}"
export BASE_DIR="${BASE_DIR:-/scratch/firenze/NN}"

launcher_path="${BASH_SOURCE[0]:-$0}"
if command -v readlink >/dev/null 2>&1; then
  launcher_path="$(readlink -f "${launcher_path}" 2>/dev/null || printf '%s\n' "${launcher_path}")"
fi
launcher_dir="$(cd "$(dirname "${launcher_path}")" && pwd)"
runner_name="run_reviewer_dataset_job.sh"
if [[ -f "${launcher_dir}/../${runner_name}" ]]; then
  runner="${launcher_dir}/../${runner_name}"
elif [[ -f "${launcher_dir}/${runner_name}" ]]; then
  runner="${launcher_dir}/${runner_name}"
else
  runner="${BASE_DIR}/${runner_name}"
fi
[[ -f "${runner}" ]] || { echo "Missing ${runner_name}" >&2; exit 1; }

exec bash "${runner}"
