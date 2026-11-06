#!/bin/bash
#SBATCH --job-name=fastembedr-resident-cluster-3294441-v3
#SBATCH --account=l40sfree
#SBATCH --partition=l40s
#SBATCH --gres=gpu:l40s:2
#SBATCH --cpus-per-task=4
#SBATCH --mem=32G
#SBATCH --time=00:10:00
#SBATCH --signal=B:USR1@120
#SBATCH --output=/scratch/firenze/NN/singularity/release_3294441_20261106/pilot-3294441-%j.out
#SBATCH --error=/scratch/firenze/NN/singularity/release_3294441_20261106/pilot-3294441-%j.err
set -Eeuo pipefail
root=/scratch/firenze/NN/singularity/release_3294441_20261106
cd "$root"
exec python3 "$root/hpc_resident_pilot_runner_3294441.py"
