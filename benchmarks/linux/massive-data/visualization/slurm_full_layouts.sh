#!/usr/bin/env bash
#SBATCH --job-name=feR_fullplot
#SBATCH --cpus-per-task=4
#SBATCH --mem=8G
#SBATCH --time=24:00:00
set -euo pipefail

base=${VIS_BASE:?Set VIS_BASE}
out=${VIS_OUT:?Set VIS_OUT}
rows=${VIS_ROWS:?Set VIS_ROWS}
suite=${VIS_SUITE:-$base/benchmark_scripts/massive-data/visualization}
image=${VIS_IMAGE:?Set VIS_IMAGE}
dataset=deep
[[ "${SLURM_ARRAY_TASK_ID:?}" == 1 ]] && dataset=turing
mkdir -p "$out/$dataset"
sha256sum -c "$out/source.sha256"
export OPENBLAS_NUM_THREADS=4 OMP_NUM_THREADS=4
args=("$base" "$dataset" "$rows" "$out/$dataset")
if [[ -n "${VIS_CAMPAIGN:-}" ]]; then
    args+=("$VIS_CAMPAIGN")
fi
singularity exec "$image" \
    /opt/r46/bin/Rscript "$suite/render_full_layouts.R" \
    "${args[@]}"
