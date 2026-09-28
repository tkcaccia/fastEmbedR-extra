#!/usr/bin/env bash

set -euo pipefail

SUITE="${1:-$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)}"

check_cpus() {
  local script="$1"
  local required="$2"
  local allocated
  allocated="$(awk -F= '/^#SBATCH --cpus-per-task=/{print $2; exit}' \
    "$script")"
  if [[ ! "$allocated" =~ ^[0-9]+$ ]] || (( allocated < required )); then
    echo "Resource contract failed: $script reserves " \
      "${allocated:-no} CPUs but requires at least $required." >&2
    return 1
  fi
}

check_array() {
  local script="$1"
  local required="$2"
  local allocated
  allocated="$(awk -F= '/^#SBATCH --array=/{print $2; exit}' "$script")"
  if [[ "$allocated" != "$required" ]]; then
    echo "Array contract failed: $script uses ${allocated:-no array};" \
      "expected $required." >&2
    return 1
  fi
}

check_cpus "$SUITE/slurm/run_preflight_cpu.sh" 1
check_array "$SUITE/slurm/run_comparators_r_cpu4.sh" '0-100%40'
check_array "$SUITE/slurm/run_cuda_pairs.sh" '0-10%2'
check_array "$SUITE/slurm/run_full_nomad_cuda.sh" '0-10%2'
check_array "$SUITE/slurm/run_comparators_cuda_pca.sh" '0-10%2'
check_array "$SUITE/slurm/run_transform_landmark_cuda_bundle.sh" '0-10%5'
check_array "$SUITE/slurm/run_pca_accuracy_cuda_bundle.sh" '0-10%5'
check_array "$SUITE/slurm/run_tsne_longrun_cuda_bundle.sh" '0-3%4'
while IFS= read -r path; do
  script="$SUITE/${path#./}"
  case "$(basename "$script")" in
    run_preflight_cuda.sh) required=1 ;;
    run_comparator_preflight_cuda.sh) required=3 ;;
    run_cuda_pairs.sh|run_comparators_cuda_pca.sh) required=3 ;;
    run_components_cuda.sh) required=2 ;;
    run_clustering_cuda.sh) required=3 ;;
    *) required=4 ;;
  esac
  check_cpus "$script" "$required"
done < <(
  awk '$2 ~ /^\.\/slurm\/.*cuda.*\.sh$/ { print $2 }' \
    "$SUITE/FILES.sha256"
)

echo "Slurm resource contracts: PASS"
