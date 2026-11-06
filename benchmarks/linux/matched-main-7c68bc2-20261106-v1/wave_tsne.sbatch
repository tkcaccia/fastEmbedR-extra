#!/bin/bash
#SBATCH --job-name=fer-matched-tsne-7c68bc2
#SBATCH --account=immunology
#SBATCH --partition=ada
#SBATCH --qos=normal
#SBATCH --cpus-per-task=4
#SBATCH --mem=64G
#SBATCH --time=12:00:00
#SBATCH --array=0-20%1
#SBATCH --output=/scratch/firenze/NN/benchmarks/matched_7c68bc2_20261106_v1/logs/tsne-%A_%a.out
#SBATCH --error=/scratch/firenze/NN/benchmarks/matched_7c68bc2_20261106_v1/logs/tsne-%A_%a.err
set -Eeuo pipefail
root=/scratch/firenze/NN/benchmarks/matched_7c68bc2_20261106_v1
image=/scratch/firenze/NN/singularity/release_7c68bc2_20261106/fastembedr_7c68bc2_20261106.sif
identity=/scratch/firenze/NN/singularity/release_7c68bc2_20261106/release_inputs/source-identity.txt
[[ -f "$image" && -f "$identity" ]]
grep -qx 'FastEmbedRCommit=7c68bc2a48ff3f98d07f216db9601047951827fd' "$identity"
[[ -z ${CUDA_VISIBLE_DEVICES:-} || ${CUDA_VISIBLE_DEVICES:-} == NoDevFiles ]]
case_id=$(sed -n "$((SLURM_ARRAY_TASK_ID+1))p" "$root/wave_tsne.txt")
[[ $case_id =~ ^[A-Za-z0-9_-]+$ ]]
singularity exec --bind /scratch/firenze/NN:/scratch/firenze/NN "$image" \
  /opt/conda/bin/python "$root/run_case.py" \
  "$root/cases/$case_id.json" /scratch/firenze/NN/Data "$root/results"
