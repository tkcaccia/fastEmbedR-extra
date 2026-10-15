#!/usr/bin/env bash
set -euo pipefail
sha256sum -c "$HNSW_ROOT/code.sha256" >/dev/null
python3 "$HNSW_SUITE/followup_after_representative.py" "$HNSW_ROOT"
