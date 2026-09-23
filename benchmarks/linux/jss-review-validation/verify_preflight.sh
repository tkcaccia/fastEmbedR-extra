#!/usr/bin/env bash

set -euo pipefail

BASE_DIR="${BASE_DIR:-/scratch/firenze/NN}"
IMAGE="${IMAGE:-$BASE_DIR/singularity/fastembedr_cuda.sif}"
OUTPUT_ROOT="${OUTPUT_ROOT:-$BASE_DIR/fastEmbedR-results/jss_validation}"
EXPECTED_VERSION="${EXPECTED_VERSION:-0.1}"

[[ -f "$IMAGE" ]] || { echo "Missing image: $IMAGE" >&2; exit 1; }
if command -v sha256sum >/dev/null 2>&1; then
  IMAGE_SHA256="$(sha256sum "$IMAGE" | awk '{print $1}')"
else
  IMAGE_SHA256="$(shasum -a 256 "$IMAGE" | awk '{print $1}')"
fi

check_backend() {
  local backend="$1"
  local identity="$OUTPUT_ROOT/identity/$backend/identity.csv"
  local smoke="$OUTPUT_ROOT/identity/$backend/backend_smoke.csv"
  local components="$OUTPUT_ROOT/identity/$backend/component_smoke.csv"
  [[ -s "$identity" ]] || {
    echo "Missing $backend preflight identity: $identity" >&2
    return 1
  }
  [[ -s "$smoke" ]] || {
    echo "Missing $backend smoke evidence: $smoke" >&2
    return 1
  }
  [[ -s "$components" ]] || {
    echo "Missing $backend component evidence: $components" >&2
    return 1
  }
  FASTEMBEDR_EXPECTED_BACKEND="$backend" \
  FASTEMBEDR_EXPECTED_VERSION="$EXPECTED_VERSION" \
  FASTEMBEDR_EXPECTED_IMAGE_SHA="$IMAGE_SHA256" \
  IDENTITY_FILE="$identity" SMOKE_FILE="$smoke" \
  COMPONENT_FILE="$components" \
  python3 - <<'PY'
import csv
import os

with open(os.environ["IDENTITY_FILE"], newline="") as handle:
    identity = next(csv.DictReader(handle))
with open(os.environ["SMOKE_FILE"], newline="") as handle:
    smoke = next(csv.DictReader(handle))
with open(os.environ["COMPONENT_FILE"], newline="") as handle:
    components = list(csv.DictReader(handle))

backend = os.environ["FASTEMBEDR_EXPECTED_BACKEND"]
version = os.environ["FASTEMBEDR_EXPECTED_VERSION"]
image_sha = os.environ["FASTEMBEDR_EXPECTED_IMAGE_SHA"]
if identity["package_version"] != version:
    raise SystemExit(
        f"{backend}: expected fastEmbedR {version}, "
        f"found {identity['package_version']}"
    )
if identity["image_sha256"] != image_sha:
    raise SystemExit(f"{backend}: preflight belongs to a different image")
if smoke["requested_backend"] != backend:
    raise SystemExit(f"{backend}: requested-backend metadata mismatch")
observed = smoke["observed_backend"]
if backend == "cuda" and observed != "cuda":
    raise SystemExit(f"cuda: observed backend is {observed!r}")
if backend == "cpu" and not observed.startswith("cpu"):
    raise SystemExit(f"cpu: observed backend is {observed!r}")
if smoke["finite"].lower() != "true":
    raise SystemExit(f"{backend}: smoke layout is not finite")
if backend == "cuda" and "cuda" not in smoke["knn_backend"].lower():
    raise SystemExit("cuda: KNN metadata does not identify CUDA execution")
expected = {"umap", "pca", "leiden"}
observed_components = {row["component"] for row in components}
if observed_components != expected:
    raise SystemExit(
        f"{backend}: component evidence is {observed_components}, "
        f"expected {expected}"
    )
for row in components:
    observed_backend = row["observed_backend"].lower()
    if backend not in observed_backend:
        raise SystemExit(
            f"{backend}: {row['component']} used {observed_backend!r}"
        )
    if row["finite"].lower() != "true":
        raise SystemExit(f"{backend}: {row['component']} was not finite")
print(
    f"{backend}: PASS version={version} image={image_sha[:12]} "
    f"optimizer={observed} knn={smoke['knn_backend']}"
)
PY
}

check_backend cpu
check_backend cuda
echo "Strict CPU and CUDA preflight evidence matches the current image."
