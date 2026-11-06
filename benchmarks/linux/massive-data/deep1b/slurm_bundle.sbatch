#!/usr/bin/env bash
#SBATCH --nodes=1
#SBATCH --ntasks=1
set -euo pipefail
echo "policy_rejected: archived Deep1B bundle violates resident one-case HPC policy." >&2
exit 78

base=${DEEP1B_BASE:-/scratch/firenze/NN}
suite=${DEEP1B_SUITE:-$base/benchmark_scripts/massive-data/deep1b}
count=${DEEP1B_CASE_COUNT:?Set DEEP1B_CASE_COUNT}
failed=0
for ((i = 0; i < count; i++)); do
    export SLURM_ARRAY_TASK_ID=$i
    bash "$suite/run_case.sh" || failed=$((failed + 1))
done
echo "Completed $count cases; failed $failed."
[[ "$failed" == 0 ]]
