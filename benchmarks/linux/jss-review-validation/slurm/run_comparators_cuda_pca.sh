#!/usr/bin/env bash
#SBATCH --account=l40sfree
#SBATCH --partition=l40s
#SBATCH --nodes=1
#SBATCH --ntasks=1
#SBATCH --cpus-per-task=3
#SBATCH --gres=gpu:l40s:1
#SBATCH --mem=64G
#SBATCH --time=48:00:00
#SBATCH --array=0-10%2
#SBATCH --job-name=feR_JSS_pca_g
#SBATCH --chdir=/scratch/firenze/NN
#SBATCH --output=/scratch/firenze/NN/benchmark_logs/feR_JSS_pca_g_%A_%a.out
#SBATCH --error=/scratch/firenze/NN/benchmark_logs/feR_JSS_pca_g_%A_%a.err
set -euo pipefail
SUITE="${SUITE:-benchmark_scripts/fastembedr_jss_review_validation}"
export N_COMPONENTS=2
worker="$SUITE/common/run_comparator_task.sh"
failed=0
for mode in r_cuda python_cuda; do
  methods_per_dataset=4
  [[ "$mode" == python_cuda ]] && methods_per_dataset=3
  if ! COMPARATOR_TASK_ID="$((SLURM_ARRAY_TASK_ID * methods_per_dataset))" \
      bash "$worker" "$mode"; then
    echo "CUDA PCA comparator failed: $mode" >&2
    failed=1
  fi
done
exit "$failed"
