#!/usr/bin/env bash
set -euo pipefail

SUITE_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
FAKE_SUITE="$(mktemp -d)"
trap 'rm -rf "$FAKE_SUITE"' EXIT
mkdir -p "$FAKE_SUITE/common"
printf '%s\n' '#!/usr/bin/env bash' \
  'printf "%s %s %s %s\n" "$SLURM_ARRAY_TASK_ID" "$QUALITY_THREADS_OVERRIDE" "$1" "$2"' \
  > "$FAKE_SUITE/common/run_array_task.sh"

for task in {0..11}; do
  actual="$(SUITE="$FAKE_SUITE" SLURM_ARRAY_TASK_ID="$task" \
    bash "$SUITE_ROOT/slurm/run_backend_quality_flow_cpu16.sh")"
  expected="$((36 + task)) 16 backend_quality cpu"
  [[ "$actual" == "$expected" ]] || {
    echo "Unexpected quality task mapping: $actual" >&2
    exit 1
  }
done

if SUITE="$FAKE_SUITE" SLURM_ARRAY_TASK_ID=12 \
    bash "$SUITE_ROOT/slurm/run_backend_quality_flow_cpu16.sh" \
    >/dev/null 2>&1; then
  echo 'Out-of-range quality task was accepted.' >&2
  exit 1
fi
