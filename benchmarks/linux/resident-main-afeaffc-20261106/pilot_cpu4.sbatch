#!/bin/bash
#SBATCH --job-name=fer-cpu-pilot-afeaffc
#SBATCH --account=immunology
#SBATCH --partition=ada
#SBATCH --qos=normal
#SBATCH --cpus-per-task=4
#SBATCH --mem=32G
#SBATCH --time=00:45:00
#SBATCH --output=/scratch/firenze/NN/benchmarks/resident_afeaffc_20261106/pilot-%j.out
#SBATCH --error=/scratch/firenze/NN/benchmarks/resident_afeaffc_20261106/pilot-%j.err
set -Eeuo pipefail
root=/scratch/firenze/NN/benchmarks/resident_afeaffc_20261106
image=/scratch/firenze/NN/singularity/release_afeaffc_20261106/fastembedr_afeaffc_20261106.sif
identity=/scratch/firenze/NN/singularity/release_afeaffc_20261106/release_inputs/source-identity.txt
[[ -f "$image" && -f "$identity" ]]
grep -qx 'FastEmbedRCommit=afeaffc39a607c00db5899c284451c6cdbf741bb' "$identity"
cp "$identity" "$root/image-identity-approved.txt"
[[ -z ${CUDA_VISIBLE_DEVICES:-} || ${CUDA_VISIBLE_DEVICES:-} == NoDevFiles ]]
singularity exec --bind /scratch/firenze/NN:/scratch/firenze/NN "$image" \
  /opt/conda/bin/python "$root/run_case.py" \
  "$root/cases/coil20_umap_cpu4_d2_s4_afeaffc.json" \
  /scratch/firenze/NN/Data "$root/results"
