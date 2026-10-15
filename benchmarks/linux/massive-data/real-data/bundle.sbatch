#!/usr/bin/env bash
# Run a small method bundle inside one GPU allocation.
set -euo pipefail
count=$(( $(wc -l < "$REAL_CASE_FILE") - 1 ))
failures=0
for ((index=0; index<count; index++)); do
    if ! SLURM_ARRAY_TASK_ID=$index bash "$REAL_SUITE/case.sbatch"; then
        failures=$((failures + 1))
    fi
done
echo "GPU bundle completed: $count cases, $failures failures"
test "$failures" -eq 0
