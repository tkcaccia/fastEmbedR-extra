#!/usr/bin/env bash
#SBATCH --nodes=1
#SBATCH --ntasks=1
set -euo pipefail

suite=${DEEP1B_SUITE:?Set DEEP1B_SUITE}
python3 "$suite/audit_visuals.py" \
    "${DEEP1B_PIPELINE:?Set DEEP1B_PIPELINE}"
