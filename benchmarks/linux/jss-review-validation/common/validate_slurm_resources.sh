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

check_cpus "$SUITE/slurm/run_preflight_cpu.sh" 1
for script in "$SUITE"/slurm/*cuda*.sh; do
  case "$(basename "$script")" in
    run_preflight_cuda.sh) required=1 ;;
    run_components_cuda.sh) required=2 ;;
    run_clustering_cuda.sh) required=3 ;;
    *) required=4 ;;
  esac
  check_cpus "$script" "$required"
done

echo "Slurm resource contracts: PASS"
