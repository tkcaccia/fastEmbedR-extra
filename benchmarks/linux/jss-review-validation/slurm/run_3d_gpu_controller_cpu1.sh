#!/usr/bin/env bash
#SBATCH --account=immunology
#SBATCH --partition=ada
#SBATCH --nodes=1
#SBATCH --ntasks=1
#SBATCH --cpus-per-task=1
#SBATCH --mem=1G
#SBATCH --time=01:00:00
#SBATCH --job-name=feR_JSS_3d_ctl
#SBATCH --chdir=/scratch/firenze/NN
#SBATCH --output=/scratch/firenze/NN/benchmark_logs/feR_JSS_3d_ctl_%j.out
#SBATCH --error=/scratch/firenze/NN/benchmark_logs/feR_JSS_3d_ctl_%j.err
set -euo pipefail

: "${SUITE:?suite path required}"
: "${OUTPUT_ROOT:?result path required}"
: "${CPU_R_JOB:?CPU R job ID required}"
: "${CPU_PY_JOB:?CPU Python job ID required}"
GPU_PY_JOB="$(sbatch --parsable \
  "$SUITE/slurm/run_comparators_python_cuda_3d.sh")"
printf 'python_cuda\t%s\n' "$GPU_PY_JOB" >> "$OUTPUT_ROOT/jobs_3d.tsv"
AUDIT_JOB="$(sbatch --parsable \
  --dependency="afterany:$CPU_R_JOB:$CPU_PY_JOB:$GPU_PY_JOB" \
  "$SUITE/slurm/run_3d_audit_cpu1.sh")"
printf 'audit\t%s\n' "$AUDIT_JOB" >> "$OUTPUT_ROOT/jobs_3d.tsv"
echo "3D Python CUDA array: $GPU_PY_JOB"
echo "3D final audit: $AUDIT_JOB"
