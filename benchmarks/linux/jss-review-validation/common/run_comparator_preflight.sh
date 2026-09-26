#!/usr/bin/env bash

set -euo pipefail

BACKEND="${1:?backend is required}"
BASE_DIR="${BASE_DIR:-/scratch/firenze/NN}"
SUITE="${SUITE:-$BASE_DIR/benchmark_scripts/fastembedr_jss_review_validation}"
IMAGE="${IMAGE:-$BASE_DIR/singularity/fastembedr_cuda.sif}"
OUTPUT_ROOT="${OUTPUT_ROOT:?OUTPUT_ROOT is required}"
CONTAINER="$(command -v apptainer || command -v singularity || true)"

source "$SUITE/common/container_runtime.sh"

[[ -n "$CONTAINER" ]] || { echo "container runtime not found" >&2; exit 1; }
[[ -f "$IMAGE" ]] || { echo "missing image: $IMAGE" >&2; exit 1; }

OUT="$OUTPUT_ROOT/comparator_preflight/$BACKEND"
mkdir -p "$OUT"

if [[ "$BACKEND" == cpu ]]; then
  "$CONTAINER" exec --cleanenv \
    --bind "$BASE_DIR:$BASE_DIR" \
    "${FASTEMBEDR_CONTAINER_R_ENV[@]}" \
    "$IMAGE" "$FASTEMBEDR_RSCRIPT" \
    "$SUITE/common/run_r_comparator_preflight.R" \
    > "$OUT/r_packages.txt"
  "$CONTAINER" exec --cleanenv "$IMAGE" "$FASTEMBEDR_PYTHON" -c '
import openTSNE, sklearn, umap
print("openTSNE=" + openTSNE.__version__)
print("scikit-learn=" + sklearn.__version__)
print("umap-learn=" + umap.__version__)
' > "$OUT/python_packages.txt"
  "$CONTAINER" exec --cleanenv "$IMAGE" sh -c \
    'test -x /opt/fit-sne/bin/fast_tsne &&
     test -r /opt/fit-sne/bin/fast_tsne.R'
else
  "$CONTAINER" exec --nv --cleanenv \
    --bind "$BASE_DIR:$BASE_DIR" \
    "${FASTEMBEDR_CONTAINER_R_ENV[@]}" \
    "$IMAGE" "$FASTEMBEDR_RSCRIPT" \
    "$SUITE/common/run_r_comparator_preflight.R" \
    --backend=cuda > "$OUT/r_cuda.txt"
  "$CONTAINER" exec --nv --cleanenv "$IMAGE" "$FASTEMBEDR_PYTHON" -c '
import inspect
import numpy as np
import cupy as cp
from cuml.decomposition import PCA
from cuml.manifold import TSNE, UMAP
required = {"max_iter", "exaggeration_iter", "n_neighbors"}
missing = required.difference(inspect.signature(TSNE).parameters)
if missing:
    raise RuntimeError(f"Installed cuML TSNE lacks: {sorted(missing)}")
x = np.random.default_rng(4).normal(size=(256, 8)).astype(np.float32)
for model in (PCA(n_components=2),
              UMAP(n_neighbors=15, init="spectral", random_state=4),
              TSNE(perplexity=15, n_neighbors=46, max_iter=250,
                   exaggeration_iter=50, init="pca", random_state=4,
                   output_type="cupy")):
    result = model.fit_transform(x)
    cp.cuda.runtime.deviceSynchronize()
    if not np.isfinite(cp.asnumpy(result)).all():
        raise RuntimeError("cuML smoke result is non-finite")
print("cuml comparator smoke: PASS")
' > "$OUT/python_cuda.txt"
fi

printf '%s\n' \
  'experiment,dataset,backend,status,error' \
  "comparator_preflight,all,$BACKEND,success," > "$OUT/status.csv"
