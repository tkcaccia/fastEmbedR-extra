#!/bin/bash
#SBATCH --job-name=fer-coil20-cuda2-afeaffc
#SBATCH --account=l40sfree
#SBATCH --partition=l40s
#SBATCH --gres=gpu:l40s:2
#SBATCH --cpus-per-task=4
#SBATCH --mem=64G
#SBATCH --time=00:10:00
#SBATCH --signal=B:USR1@120
#SBATCH --output=/scratch/firenze/NN/benchmarks/resident_gpu_afeaffc_20261106/pilot-%j.out
#SBATCH --error=/scratch/firenze/NN/benchmarks/resident_gpu_afeaffc_20261106/pilot-%j.err
set -Eeuo pipefail
root=/scratch/firenze/NN/benchmarks/resident_gpu_afeaffc_20261106
cd "$root"
exec python3 "$root/gpu_case_runner.py"
