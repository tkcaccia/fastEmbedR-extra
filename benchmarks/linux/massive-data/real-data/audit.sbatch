#!/usr/bin/env bash
set -euo pipefail
sha256sum -c "$REAL_ROOT/image.sha256" >/dev/null
sha256sum -c "$REAL_ROOT/source.sha256" >/dev/null
python3 "$REAL_SUITE/audit.py" "$REAL_ROOT" "$REAL_DATASET"
singularity exec "$REAL_BASE/singularity/fastembedr_cuda.sif" \
    /opt/r46/bin/Rscript "$REAL_SUITE/plot_comparison.R" \
    "$REAL_ROOT" "$REAL_DATASET"
