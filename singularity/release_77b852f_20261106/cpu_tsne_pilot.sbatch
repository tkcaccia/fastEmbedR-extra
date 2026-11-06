#!/bin/bash
#SBATCH --job-name=fer-tsne-image-77b852f
#SBATCH --account=immunology
#SBATCH --partition=ada
#SBATCH --qos=normal
#SBATCH --cpus-per-task=8
#SBATCH --mem=8G
#SBATCH --time=00:10:00
#SBATCH --output=/scratch/firenze/NN/singularity/release_77b852f_20261106/cpu-pilot-%j.out
#SBATCH --error=/scratch/firenze/NN/singularity/release_77b852f_20261106/cpu-pilot-%j.err
set -Eeuo pipefail
root=/scratch/firenze/NN/singularity/release_77b852f_20261106
image="$root/fastembedr_77b852f_20261106.sif"
expected=$(cut -d' ' -f1 "$root/image-1605295.sha256")
[[ -r "$image" && -r "$root/cpu_tsne_pilot.R" ]]
[[ -z ${CUDA_VISIBLE_DEVICES:-} || ${CUDA_VISIBLE_DEVICES:-} == NoDevFiles ]]
actual=$(sha256sum "$image" | cut -d' ' -f1)
[[ "$actual" == "$expected" ]]
printf 'host=%s job=%s image_sha256=%s\n' \
    "$(hostname)" "$SLURM_JOB_ID" "$actual"
singularity exec --cleanenv "$image" /opt/r46/bin/Rscript \
    "$root/cpu_tsne_pilot.R"
