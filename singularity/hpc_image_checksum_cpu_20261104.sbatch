#!/bin/bash
#SBATCH --job-name=fastembedr-image-sha256
#SBATCH --account=immunology
#SBATCH --partition=ada
#SBATCH --qos=normal
#SBATCH --cpus-per-task=1
#SBATCH --mem=2G
#SBATCH --time=00:20:00
#SBATCH --output=/scratch/firenze/NN/singularity/checksum-%j.out
#SBATCH --error=/scratch/firenze/NN/singularity/checksum-%j.err
set -Eeuo pipefail

if [[ -z ${SLURM_JOB_ID:-} ]]; then
    echo 'Submit this script with sbatch; never hash on a login node.' >&2
    exit 78
fi
if [[ $# -ne 1 ]]; then
    echo 'Usage: sbatch hpc_image_checksum_cpu_20261104.sbatch IMAGE.sif' >&2
    exit 64
fi
image=$1
case "$image" in
    /scratch/firenze/NN/singularity/*.sif|\
    /scratch/firenze/NN/singularity/*/*.sif) ;;
    *) echo 'Image must be under the project Singularity directory.' >&2
       exit 78 ;;
esac
[[ -f "$image" ]] || { echo 'Image is missing.' >&2; exit 66; }
printf 'job=%s host=%s image=%s bytes=%s\n' \
    "$SLURM_JOB_ID" "$(hostname)" "$image" "$(stat -c %s "$image")"
sha256sum -- "$image"
