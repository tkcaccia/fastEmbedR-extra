#!/usr/bin/env bash
#SBATCH --nodes=1
#SBATCH --ntasks=1
set -euo pipefail

export OPENBLAS_NUM_THREADS=1
export MKL_NUM_THREADS=1
export OMP_NUM_THREADS=1
export VECLIB_MAXIMUM_THREADS=1
sha256sum -c "$HNSW_ROOT/code.sha256" >/dev/null

if [[ "$HNSW_PHASE" == truth || "$HNSW_PHASE" == sweep ||
      "$HNSW_PHASE" == sweep_bundle ||
      "$HNSW_PHASE" == preflight_5m ]]; then
    read -r expected unused < "$HNSW_ROOT/source.sha256"
    printf '%s  %s\n' "$expected" "$HNSW_IMAGE" | sha256sum -c -
fi

if [[ "$HNSW_PHASE" == preflight_5m ]]; then
    singularity exec "$HNSW_IMAGE" /opt/r46/bin/Rscript \
        "$HNSW_SUITE/preflight_5m.R"
    touch "$HNSW_ROOT/preflight.ok"
elif [[ "$HNSW_PHASE" == pilot_audit ]]; then
    python3 "$HNSW_SUITE/pilot_report.py" "$HNSW_ROOT"
elif [[ "$HNSW_PHASE" == audit_5m ]]; then
    python3 "$HNSW_SUITE/audit_5m.py" "$HNSW_ROOT"
elif [[ "$HNSW_PHASE" == audit_refine ]]; then
    python3 "$HNSW_SUITE/audit_refine.py" "$HNSW_ROOT"
elif [[ "$HNSW_PHASE" == audit_representative ]]; then
    python3 "$HNSW_SUITE/audit_representative.py" "$HNSW_ROOT"
elif [[ "$HNSW_PHASE" == audit_large_probe ]]; then
    python3 "$HNSW_SUITE/audit_large_probe.py" "$HNSW_ROOT"
elif [[ "$HNSW_PHASE" == audit ]]; then
    python3 "$HNSW_SUITE/audit.py" "$HNSW_ROOT"
elif [[ "$HNSW_PHASE" == sweep_bundle ]]; then
    [[ -f "$HNSW_ROOT/preflight.ok" ]] || {
        echo 'Representative preflight did not pass.' >&2
        exit 1
    }
    for ((index=HNSW_FIRST; index<=HNSW_LAST; index++)); do
        singularity exec "$HNSW_IMAGE" /opt/r46/bin/Rscript \
            "$HNSW_SUITE/worker.R" sweep "$HNSW_ROOT" "$index"
    done
else
    if [[ -f "$HNSW_ROOT/preflight.required" && \
          ! -f "$HNSW_ROOT/preflight.ok" ]]; then
        echo "Compute-node preflight did not pass." >&2
        exit 1
    fi
    singularity exec "$HNSW_IMAGE" /opt/r46/bin/Rscript \
        "$HNSW_SUITE/worker.R" "$HNSW_PHASE" "$HNSW_ROOT" \
        "$SLURM_ARRAY_TASK_ID"
fi
