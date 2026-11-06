#!/bin/bash
#SBATCH --job-name=fastembedr-image-77b852f
#SBATCH --account=immunology
#SBATCH --partition=ada
#SBATCH --qos=normal
#SBATCH --cpus-per-task=8
#SBATCH --mem=64G
#SBATCH --time=00:45:00
#SBATCH --output=/scratch/firenze/NN/singularity/release_77b852f_20261106/build-%j.out
#SBATCH --error=/scratch/firenze/NN/singularity/release_77b852f_20261106/build-%j.err
set -Eeuo pipefail
umask 027
root=/scratch/firenze/NN/singularity/release_77b852f_20261106
base=/scratch/firenze/NN/singularity/fastembedr_a670bcc_20261029.sif
expected_base=3e81f859f48824825ed11928275954a062e6fd324e313bea515d43e1519db402
expected_source=77b852fc496ad4665969c4f6771088f5b98da4fe
printf 'host=%s job=%s started=%s\n' "$(hostname)" "${SLURM_JOB_ID}" "$(date -u +%FT%TZ)"
actual_base=$(sha256sum "$base" | cut -d' ' -f1)
[[ "$actual_base" == "$expected_base" ]]
grep -qx "FastEmbedRCommit=$expected_source" "$root/release_inputs/source-identity.txt"
printf '%s  %s\n' f1c6e346f3433a3f8e62a7ec26ce614e5ae62c58b8d0aa5b798b349426212288 "$root/release_inputs/fastEmbedR_0.1.tar.gz" | sha256sum -c -
work="$root/build-${SLURM_JOB_ID}.partial.sif"
final="$root/fastembedr_77b852f_20261106.sif"
[[ ! -e "$work" && ! -e "$final" ]]
export SINGULARITY_CACHEDIR="$root/cache-${SLURM_JOB_ID}"
mkdir -p "$SINGULARITY_CACHEDIR"
singularity build --fakeroot "$work" "$root/fastembedr_cuda_77b852f.def"
singularity inspect --labels "$work" > "$root/labels-${SLURM_JOB_ID}.txt"
sha256sum "$work" > "$root/image-${SLURM_JOB_ID}.sha256"
mv --no-clobber "$work" "$final"
printf 'image=%s finished=%s\n' "$final" "$(date -u +%FT%TZ)"
