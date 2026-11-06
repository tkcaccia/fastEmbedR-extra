#!/bin/bash
#SBATCH --job-name=fer-cluster-repeatability
#SBATCH --account=immunology
#SBATCH --partition=ada
#SBATCH --qos=normal
#SBATCH --cpus-per-task=4
#SBATCH --mem=8G
#SBATCH --time=00:10:00
#SBATCH --output=/scratch/firenze/NN/benchmarks/matched_afeaffc_20261106_v2/repeatability-%j.out
#SBATCH --error=/scratch/firenze/NN/benchmarks/matched_afeaffc_20261106_v2/repeatability-%j.err
set -Eeuo pipefail
root=/scratch/firenze/NN/benchmarks/matched_afeaffc_20261106_v2
image=/scratch/firenze/NN/singularity/release_afeaffc_20261106/fastembedr_afeaffc_20261106.sif
identity=/scratch/firenze/NN/singularity/release_afeaffc_20261106/release_inputs/source-identity.txt
grep -qx 'FastEmbedRCommit=afeaffc39a607c00db5899c284451c6cdbf741bb' "$identity"
[[ -z ${CUDA_VISIBLE_DEVICES:-} || ${CUDA_VISIBLE_DEVICES:-} == NoDevFiles ]]
singularity exec --bind /scratch/firenze/NN:/scratch/firenze/NN "$image" \
    /opt/r46/bin/Rscript "$root/audit_cluster_repeatability.R"
