#!/bin/bash
#SBATCH --job-name=fastembedr-resident-umap-b825116
#SBATCH --account=l40sfree
#SBATCH --partition=l40s
#SBATCH --gres=gpu:l40s:2
#SBATCH --cpus-per-task=4
#SBATCH --mem=32G
#SBATCH --time=00:10:00
#SBATCH --signal=B:USR1@120
#SBATCH --output=/scratch/firenze/NN/singularity/candidate_b825116_20261104/pilot-%j.out
#SBATCH --error=/scratch/firenze/NN/singularity/candidate_b825116_20261104/pilot-%j.err
set -Eeuo pipefail
root=/scratch/firenze/NN/singularity/candidate_b825116_20261104
cd "$root"
exec python3 "$root/hpc_resident_pilot_runner_b825116.py"
