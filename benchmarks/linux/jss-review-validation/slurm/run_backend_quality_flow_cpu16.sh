#!/usr/bin/env bash
#SBATCH --account=immunology
#SBATCH --partition=ada
#SBATCH --nodes=1
#SBATCH --ntasks=1
#SBATCH --cpus-per-task=16
#SBATCH --mem=128G
#SBATCH --time=72:00:00
#SBATCH --array=0-11%2
#SBATCH --job-name=feR_JSS_flow_q_c
#SBATCH --chdir=/scratch/firenze/NN
#SBATCH --output=/scratch/firenze/NN/benchmark_logs/feR_JSS_flow_q_c_%A_%a.out
#SBATCH --error=/scratch/firenze/NN/benchmark_logs/feR_JSS_flow_q_c_%A_%a.err
set -euo pipefail
SUITE="${SUITE:-benchmark_scripts/fastembedr_jss_review_validation}"
task="${SLURM_ARRAY_TASK_ID:?missing Slurm array task ID}"
[[ "$task" =~ ^([0-9]|10|11)$ ]] || {
  echo "FlowRepository quality task must be 0-11." >&2
  exit 2
}
export QUALITY_THREADS_OVERRIDE=16
export SLURM_ARRAY_TASK_ID=$((36 + task))
bash "$SUITE/common/run_array_task.sh" backend_quality cpu
