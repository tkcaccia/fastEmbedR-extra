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
check_cpus "$SUITE/slurm/run_preflight_cuda.sh" 1

while IFS= read -r script; do
  check_cpus "$script" 4
done < <(
  grep -l 'run_array_task[.]sh.*cuda' "$SUITE"/slurm/*cuda*.sh |
    grep -v '/run_preflight_cuda[.]sh$'
)

echo "Slurm resource contracts: PASS"
