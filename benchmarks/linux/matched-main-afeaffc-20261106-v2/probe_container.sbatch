#!/bin/bash
#SBATCH --job-name=fer-cgroup-container
#SBATCH --account=immunology
#SBATCH --partition=ada
#SBATCH --qos=normal
#SBATCH --cpus-per-task=1
#SBATCH --mem=1G
#SBATCH --time=00:02:00
#SBATCH --output=/scratch/firenze/NN/benchmarks/matched_afeaffc_20261106_v2/container-probe-%j.out
#SBATCH --error=/scratch/firenze/NN/benchmarks/matched_afeaffc_20261106_v2/container-probe-%j.err
set -Eeuo pipefail
image=/scratch/firenze/NN/singularity/release_afeaffc_20261106/fastembedr_afeaffc_20261106.sif
probe=/scratch/firenze/NN/benchmarks/matched_afeaffc_20261106_v2/probe_cgroup.py
singularity exec --bind /scratch/firenze/NN:/scratch/firenze/NN \
    "$image" /opt/conda/bin/python "$probe"
