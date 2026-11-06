#!/bin/bash
#SBATCH --job-name=fer-cpu2-afeaffc
#SBATCH --account=immunology
#SBATCH --partition=ada
#SBATCH --qos=normal
#SBATCH --cpus-per-task=2
#SBATCH --mem=64G
#SBATCH --time=12:00:00
#SBATCH --array=0-54%1
#SBATCH --output=/scratch/firenze/NN/benchmarks/resident_afeaffc_20261106/logs/wave-cpu2-%A_%a.out
#SBATCH --error=/scratch/firenze/NN/benchmarks/resident_afeaffc_20261106/logs/wave-cpu2-%A_%a.err
set -Eeuo pipefail
root=/scratch/firenze/NN/benchmarks/resident_afeaffc_20261106
image=/scratch/firenze/NN/singularity/release_afeaffc_20261106/fastembedr_afeaffc_20261106.sif
test -f "$image"
test -f "$root/image-identity-approved.txt"
grep -qx 'FastEmbedRCommit=afeaffc39a607c00db5899c284451c6cdbf741bb' "$root/image-identity-approved.txt"
[[ -z ${CUDA_VISIBLE_DEVICES:-} || ${CUDA_VISIBLE_DEVICES:-} == NoDevFiles ]]
case_id=$(sed -n "$((SLURM_ARRAY_TASK_ID+1))p" "$root/wave_cpu2.txt")
[[ $case_id =~ ^[A-Za-z0-9_-]+$ ]]
case_file="$root/cases/$case_id.json"
test -f "$case_file"
singularity exec --bind /scratch/firenze/NN:/scratch/firenze/NN "$image" \
  /opt/conda/bin/python "$root/run_case.py" "$case_file" \
  /scratch/firenze/NN/Data "$root/results"
