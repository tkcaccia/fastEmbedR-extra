#!/usr/bin/env bash
#SBATCH --nodes=1
#SBATCH --ntasks=1
set -euo pipefail
echo "policy_rejected: archived file-backed HPC worker is disabled." >&2
exit 78

base=${DEEP1B_BASE:-/scratch/firenze/NN}
suite=${DEEP1B_SUITE:-$base/benchmark_scripts/massive-data/deep1b}
python3 "$suite/controller.py" \
    advance "${DEEP1B_PIPELINE:?Set DEEP1B_PIPELINE}" \
    "${DEEP1B_STAGE:?Set DEEP1B_STAGE}"
