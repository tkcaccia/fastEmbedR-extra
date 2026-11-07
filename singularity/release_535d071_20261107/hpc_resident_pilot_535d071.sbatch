#!/bin/bash
#SBATCH --job-name=fastembedr-resident-cluster-535d071-v1
#SBATCH --account=l40sfree
#SBATCH --partition=l40s
#SBATCH --gres=gpu:l40s:2
#SBATCH --cpus-per-task=4
#SBATCH --mem=32G
#SBATCH --time=00:10:00
#SBATCH --signal=B:USR1@120
#SBATCH --output=/scratch/firenze/NN/singularity/release_535d071_20261107/pilot-535d071-%j.out
#SBATCH --error=/scratch/firenze/NN/singularity/release_535d071_20261107/pilot-535d071-%j.err
set -Eeuo pipefail
root=/scratch/firenze/NN/singularity/release_535d071_20261107
cd "$root"
exec python3 "$root/hpc_resident_pilot_runner_535d071.py"
