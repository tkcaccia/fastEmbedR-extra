#!/bin/bash
#SBATCH --job-name=fer-comp-probe
#SBATCH --account=immunology
#SBATCH --partition=ada
#SBATCH --qos=normal
#SBATCH --cpus-per-task=1
#SBATCH --mem=2G
#SBATCH --time=00:05:00
#SBATCH --output=/scratch/firenze/NN/benchmarks/resident-comparators-535d071-20261107/probe-%j.out
#SBATCH --error=/scratch/firenze/NN/benchmarks/resident-comparators-535d071-20261107/probe-%j.err
set -Eeuo pipefail
image=/scratch/firenze/NN/singularity/release_535d071_20261107/fastembedr_535d071_20261107.sif
identity=/scratch/firenze/NN/singularity/release_535d071_20261107/release_inputs/source-identity.txt
test -f "$image"
grep -qx 'FastEmbedRCommit=535d071849945db3fa550d3c50f80633b91748cc' "$identity"
[[ -z ${CUDA_VISIBLE_DEVICES:-} || ${CUDA_VISIBLE_DEVICES:-} == NoDevFiles ]]
singularity exec "$image" /opt/r46/bin/Rscript -e '
  packages <- c("fastEmbedR", "float", "Rtsne", "uwot", "umap", "irlba")
  available <- vapply(packages, requireNamespace, logical(1L), quietly = TRUE)
  cat("R_PACKAGES ", paste(names(available), available, sep = "=", collapse = " "), "\n", sep = "")
  cat("FITSNE_WRAPPER ", file.exists("/opt/fit-sne/bin/fast_tsne.R"), "\n", sep = "")
  cat("FITSNE_BINARY ", file.exists("/opt/fit-sne/bin/fast_tsne"), "\n", sep = "")
'
singularity exec "$image" /opt/conda/bin/python - <<'PY'
import importlib.util
packages = ('numpy', 'scipy', 'sklearn', 'openTSNE', 'umap', 'cuml', 'cupy')
print('PY_PACKAGES ' + ' '.join(
    f'{name}={importlib.util.find_spec(name) is not None}' for name in packages))
PY
printf 'resident_comparator_dependency_probe_pass job=%s host=%s\n' \
  "$SLURM_JOB_ID" "$(hostname)"
