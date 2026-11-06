#!/bin/bash
#SBATCH --job-name=fer-matched-coil20-7c68bc2
#SBATCH --account=immunology
#SBATCH --partition=ada
#SBATCH --qos=normal
#SBATCH --cpus-per-task=4
#SBATCH --mem=32G
#SBATCH --time=00:45:00
#SBATCH --output=/scratch/firenze/NN/benchmarks/matched_7c68bc2_20261106_v1/pilot-%j.out
#SBATCH --error=/scratch/firenze/NN/benchmarks/matched_7c68bc2_20261106_v1/pilot-%j.err
set -Eeuo pipefail
root=/scratch/firenze/NN/benchmarks/matched_7c68bc2_20261106_v1
image=/scratch/firenze/NN/singularity/release_7c68bc2_20261106/fastembedr_7c68bc2_20261106.sif
identity=/scratch/firenze/NN/singularity/release_7c68bc2_20261106/release_inputs/source-identity.txt
[[ -f "$image" && -f "$identity" ]]
grep -qx 'FastEmbedRCommit=7c68bc2a48ff3f98d07f216db9601047951827fd' "$identity"
[[ -z ${CUDA_VISIBLE_DEVICES:-} || ${CUDA_VISIBLE_DEVICES:-} == NoDevFiles ]]
singularity exec --bind /scratch/firenze/NN:/scratch/firenze/NN "$image" \
  /opt/conda/bin/python "$root/run_case.py" "$root/case.json" \
  /scratch/firenze/NN/Data "$root/results"
