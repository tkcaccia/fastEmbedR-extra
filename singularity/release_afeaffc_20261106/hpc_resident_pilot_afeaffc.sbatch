#!/bin/bash
#SBATCH --job-name=fastembedr-resident-umap-afeaffc-v3
#SBATCH --account=l40sfree
#SBATCH --partition=l40s
#SBATCH --gres=gpu:l40s:2
#SBATCH --cpus-per-task=4
#SBATCH --mem=32G
#SBATCH --time=00:10:00
#SBATCH --signal=B:USR1@120
#SBATCH --output=/scratch/firenze/NN/singularity/release_afeaffc_20261106/pilot-afeaffc-%j.out
#SBATCH --error=/scratch/firenze/NN/singularity/release_afeaffc_20261106/pilot-afeaffc-%j.err
set -Eeuo pipefail
root=/scratch/firenze/NN/singularity/release_afeaffc_20261106
cd "$root"
exec python3 "$root/hpc_resident_pilot_runner_afeaffc.py"
