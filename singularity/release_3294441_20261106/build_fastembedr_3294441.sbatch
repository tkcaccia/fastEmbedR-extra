#!/bin/bash
#SBATCH --job-name=fastembedr-image-3294441
#SBATCH --account=immunology
#SBATCH --partition=ada
#SBATCH --qos=normal
#SBATCH --cpus-per-task=8
#SBATCH --mem=64G
#SBATCH --time=02:00:00
#SBATCH --output=/scratch/firenze/NN/singularity/release_3294441_20261106/build-%j.out
#SBATCH --error=/scratch/firenze/NN/singularity/release_3294441_20261106/build-%j.err
set -Eeuo pipefail
umask 027
root=/scratch/firenze/NN/singularity/release_3294441_20261106
base=/scratch/firenze/NN/singularity/fastembedr_a670bcc_20261029.sif
expected_base=3e81f859f48824825ed11928275954a062e6fd324e313bea515d43e1519db402
expected_source=32944414d8256da04d67df2ab8a62131ba61028c
printf 'host=%s job=%s started=%s\n' "$(hostname)" "${SLURM_JOB_ID}" "$(date -u +%FT%TZ)"
actual_base=$(sha256sum "$base" | cut -d' ' -f1)
[[ "$actual_base" == "$expected_base" ]]
grep -qx "FastEmbedRCommit=$expected_source" "$root/release_inputs/source-identity.txt"
(cd "$root/release_inputs" && sha256sum -c SHA256SUMS)
work="$root/build-${SLURM_JOB_ID}.partial.sif"
final="$root/fastembedr_3294441_20261106.sif"
[[ ! -e "$work" && ! -e "$final" ]]
export SINGULARITY_CACHEDIR="$root/cache-${SLURM_JOB_ID}"
mkdir -p "$SINGULARITY_CACHEDIR"
singularity build --fakeroot "$work" "$root/fastembedr_cuda_3294441.def"
singularity inspect --labels "$work" > "$root/labels-${SLURM_JOB_ID}.txt"
sha256sum "$work" > "$root/image-${SLURM_JOB_ID}.sha256"
mv --no-clobber "$work" "$final"
printf 'image=%s finished=%s\n' "$final" "$(date -u +%FT%TZ)"
