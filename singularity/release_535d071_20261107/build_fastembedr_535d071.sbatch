#!/bin/bash
#SBATCH --job-name=fastembedr-image-535d071
#SBATCH --account=immunology
#SBATCH --partition=ada
#SBATCH --qos=normal
#SBATCH --cpus-per-task=8
#SBATCH --mem=64G
#SBATCH --time=00:45:00
#SBATCH --output=/scratch/firenze/NN/singularity/release_535d071_20261107/build-%j.out
#SBATCH --error=/scratch/firenze/NN/singularity/release_535d071_20261107/build-%j.err
set -Eeuo pipefail
umask 027
root=/scratch/firenze/NN/singularity/release_535d071_20261107
base=/scratch/firenze/NN/singularity/fastembedr_a670bcc_20261029.sif
expected_base=3e81f859f48824825ed11928275954a062e6fd324e313bea515d43e1519db402
expected_source=535d071849945db3fa550d3c50f80633b91748cc
printf 'host=%s job=%s started=%s\n' "$(hostname)" "${SLURM_JOB_ID}" "$(date -u +%FT%TZ)"
actual_base=$(sha256sum "$base" | cut -d' ' -f1)
[[ "$actual_base" == "$expected_base" ]]
grep -qx "FastEmbedRCommit=$expected_source" "$root/release_inputs/source-identity.txt"
printf '%s  %s\n' 9591bc47b952993f296bd678479245038ab5823097a33af9a18e0bb6670eb451 "$root/release_inputs/fastEmbedR_0.1.tar.gz" | sha256sum -c -
work="$root/build-${SLURM_JOB_ID}.partial.sif"
final="$root/fastembedr_535d071_20261107.sif"
[[ ! -e "$work" && ! -e "$final" ]]
export SINGULARITY_CACHEDIR="$root/cache-${SLURM_JOB_ID}"
mkdir -p "$SINGULARITY_CACHEDIR"
singularity build --fakeroot "$work" "$root/fastembedr_cuda_535d071.def"
singularity inspect --labels "$work" > "$root/labels-${SLURM_JOB_ID}.txt"
sha256sum "$work" > "$root/image-${SLURM_JOB_ID}.sha256"
mv --no-clobber "$work" "$final"
printf 'image=%s finished=%s\n' "$final" "$(date -u +%FT%TZ)"
