#!/usr/bin/env bash

set -euo pipefail

SOURCE_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
HPC_ROOT="${HPC_ROOT:?Set HPC_ROOT to the mounted HPC root directory.}"
DESTINATION="$HPC_ROOT/benchmark_scripts/fastembedr_jss_review_validation"

[[ -f "$SOURCE_DIR/FILES.sha256" ]] || {
  echo "Missing source checksum manifest: $SOURCE_DIR/FILES.sha256" >&2
  exit 1
}
[[ -d "$HPC_ROOT" ]] || {
  echo "HPC_ROOT is not a directory: $HPC_ROOT" >&2
  exit 1
}

mkdir -p "$DESTINATION"
rsync -av --exclude '.DS_Store' "$SOURCE_DIR/" "$DESTINATION/"

if command -v sha256sum >/dev/null 2>&1; then
  (cd "$DESTINATION" && sha256sum -c FILES.sha256)
else
  (cd "$DESTINATION" && shasum -a 256 -c FILES.sha256)
fi

cat <<EOF
Synchronized the checksummed JSS validation campaign.
  source:      $SOURCE_DIR
  destination: $DESTINATION

No Slurm job was submitted and no container was executed.
EOF
