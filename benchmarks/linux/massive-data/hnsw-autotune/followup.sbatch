#!/usr/bin/env bash
set -euo pipefail
echo "policy_rejected: archived file-backed HPC worker is disabled." >&2
exit 78
sha256sum -c "$HNSW_ROOT/code.sha256" >/dev/null
python3 "$HNSW_SUITE/followup_after_representative.py" "$HNSW_ROOT"
