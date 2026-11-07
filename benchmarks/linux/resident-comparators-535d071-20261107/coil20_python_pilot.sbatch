#!/bin/bash
#SBATCH --job-name=fer-py-coil20
#SBATCH --account=immunology
#SBATCH --partition=ada
#SBATCH --qos=normal
#SBATCH --cpus-per-task=4
#SBATCH --mem=16G
#SBATCH --time=00:20:00
#SBATCH --array=0-1%1
#SBATCH --output=/scratch/firenze/NN/benchmarks/resident-comparators-535d071-20261107/logs/coil20-python-%A_%a.out
#SBATCH --error=/scratch/firenze/NN/benchmarks/resident-comparators-535d071-20261107/logs/coil20-python-%A_%a.err
set -Eeuo pipefail
root=/scratch/firenze/NN/benchmarks/resident-comparators-535d071-20261107
image=/scratch/firenze/NN/singularity/release_535d071_20261107/fastembedr_535d071_20261107.sif
image_record=/scratch/firenze/NN/singularity/release_535d071_20261107/image-1606224.sha256
identity=/scratch/firenze/NN/singularity/release_535d071_20261107/release_inputs/source-identity.txt
worker="$root/coil20_python_worker.R"
input=/scratch/firenze/NN/Data/COIL20/COIL20_float32.RData
methods=(opentsne umaplearn)
[[ ${SLURM_ARRAY_TASK_ID:-} =~ ^[0-1]$ ]]
[[ ${SLURM_CPUS_PER_TASK:-} == 4 ]]
[[ -z ${CUDA_VISIBLE_DEVICES:-} || ${CUDA_VISIBLE_DEVICES:-} == NoDevFiles ]]
method=${methods[$SLURM_ARRAY_TASK_ID]}
test -f "$image"
test -f "$worker"
test -f "$input"
grep -qx 'FastEmbedRCommit=535d071849945db3fa550d3c50f80633b91748cc' "$identity"
grep -q '^15b494004966c5e8ae4ada72db28024356cfa8a981333a37484ce75a09d08bf2 ' "$image_record"
printf '%s  %s\n' \
  7126e65c12b0c82c4c24e580b3d4dbd2dd19bed9c71ca91850efc6cd662d4fe7 \
  "$worker" | sha256sum -c -
printf '%s  %s\n' \
  8e53030869bcfbc228edc06ca970e69b78ddae13fb188327e8899194d5841d66 \
  "$input" | sha256sum -c -
result="$root/results/coil20_${method}_cpu4_d2_s4"
test ! -e "$result"
mkdir "$result"
cd "$result"
export FASTEMBEDR_WORKER_SHA256=7126e65c12b0c82c4c24e580b3d4dbd2dd19bed9c71ca91850efc6cd662d4fe7
export FASTEMBEDR_IMAGE_SHA256=15b494004966c5e8ae4ada72db28024356cfa8a981333a37484ce75a09d08bf2
singularity exec --bind /scratch/firenze/NN:/scratch/firenze/NN "$image" \
  /opt/r46/bin/Rscript "$worker" "$method" "$result"
test -s "$result/metrics.json"
test -s "$result/layout.rds"
printf 'resident_coil20_python_comparator_pass method=%s job=%s\n' \
  "$method" "$SLURM_JOB_ID"
