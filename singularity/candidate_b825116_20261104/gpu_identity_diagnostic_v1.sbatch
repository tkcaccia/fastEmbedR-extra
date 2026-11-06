#!/bin/bash
#SBATCH --job-name=fastembedr-gpu-identity-v1
#SBATCH --account=l40sfree
#SBATCH --partition=l40s
#SBATCH --gres=gpu:l40s:2
#SBATCH --cpus-per-task=1
#SBATCH --mem=1G
#SBATCH --time=00:03:00
#SBATCH --output=/scratch/firenze/NN/singularity/gpu_identity_diagnostic_20261105/diag-%j.out
#SBATCH --error=/scratch/firenze/NN/singularity/gpu_identity_diagnostic_20261105/diag-%j.err
set -Eeuo pipefail
printf 'job=%s host=%s\n' "${SLURM_JOB_ID:-missing}" "$(hostname)"
printf 'SLURM_JOB_GPUS=%s\n' "${SLURM_JOB_GPUS:-missing}"
printf 'SLURM_STEP_GPUS=%s\n' "${SLURM_STEP_GPUS:-missing}"
printf 'CUDA_VISIBLE_DEVICES=%s\n' "${CUDA_VISIBLE_DEVICES:-missing}"
printf 'NVIDIA_VISIBLE_DEVICES=%s\n' "${NVIDIA_VISIBLE_DEVICES:-missing}"
printf 'gpu inventory:\n'
timeout 8s nvidia-smi --query-gpu=index,uuid,pci.bus_id --format=csv,noheader,nounits
printf 'visible devices:\n'
timeout 8s nvidia-smi -L
printf 'compute contexts:\n'
timeout 8s nvidia-smi --query-compute-apps=pid,gpu_uuid --format=csv,noheader,nounits
printf 'GPU_IDENTITY_DIAGNOSTIC_COMPLETE\n'
