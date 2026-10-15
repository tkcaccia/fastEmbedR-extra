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
    "$SUITE/common/manuscript_example.R" \
    > "$OUT/manuscript_example.txt"
  "$CONTAINER" exec --cleanenv \
    --bind "$BASE_DIR:$BASE_DIR" \
    "${FASTEMBEDR_CONTAINER_R_ENV[@]}" \
    "$IMAGE" "$FASTEMBEDR_RSCRIPT" \
    "$SUITE/common/run_r_comparator_preflight.R" \
    "--base-dir=$BASE_DIR" \
    > "$OUT/r_packages.txt"
  "$CONTAINER" exec --cleanenv \
    --bind "$BASE_DIR:$BASE_DIR" \
    --env "PYTHONPATH=$SUITE/common" \
    "$IMAGE" "$FASTEMBEDR_PYTHON" -c '
import openTSNE, sklearn, umap
import numpy as np
from types import SimpleNamespace
from run_python_comparator import fit_once, pca_quality
print("openTSNE=" + openTSNE.__version__)
print("scikit-learn=" + sklearn.__version__)
print("umap-learn=" + umap.__version__)
x = np.random.default_rng(4).normal(size=(256, 8)).astype(np.float32)
args = SimpleNamespace(backend="cpu", method="sklearn_pca", seed=4,
                       n_components=2, threads=3)
model, scores, elapsed = fit_once(args, x, 5)
metrics = pca_quality(model, x, scores, np.arange(0, len(x), 2))
if scores.shape != (256, 5) or not np.isfinite(scores).all():
    raise RuntimeError("scikit-learn PCA did not return five scores")
if not np.isfinite(metrics["reconstruction_relative_l2"]):
    raise RuntimeError("scikit-learn PCA benchmark scoring is not finite")
print("sklearn PCA rank-five smoke: PASS")
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
    --backend=cuda "--base-dir=$BASE_DIR" > "$OUT/r_cuda.txt"
  "$CONTAINER" exec --nv --cleanenv \
    --bind "$BASE_DIR:$BASE_DIR" \
    --env "PYTHONPATH=$SUITE/common" \
    "$IMAGE" "$FASTEMBEDR_PYTHON" -c '
import inspect
import numpy as np
import cupy as cp
from cuml.decomposition import PCA
from cuml.manifold import TSNE, UMAP
from run_python_comparator import (
    check_cuml_tsne, fit_cuda, fit_once, pca_quality, to_numpy
)
from types import SimpleNamespace
required = {"max_iter", "exaggeration_iter", "n_neighbors"}
missing = required.difference(inspect.signature(TSNE).parameters)
if missing:
    raise RuntimeError(f"Installed cuML TSNE lacks: {sorted(missing)}")
x = np.random.default_rng(4).normal(size=(256, 8)).astype(np.float32)
model, device_scores = fit_cuda("cuml_pca", x, 5, 4, 2)
if not isinstance(model, PCA) or not isinstance(device_scores, cp.ndarray):
    raise RuntimeError("cuML PCA did not return CUDA scores")
args = SimpleNamespace(backend="cuda", method="cuml_pca", seed=4,
                       n_components=2, threads=3)
model, scores, elapsed = fit_once(args, x, 5)
reference = x - x.mean(axis=0)
_, singular, _ = np.linalg.svd(reference, full_matrices=False)
optimal_error = np.sum(singular[5:] ** 2)
if scores.shape != (256, 5):
    raise RuntimeError("cuML PCA did not return five scores")
reconstructed = scores @ to_numpy(model.components_) + to_numpy(model.mean_)
if np.sum((x - reconstructed) ** 2) > 1.25 * optimal_error:
    raise RuntimeError("cuML PCA reconstruction exceeds reference tolerance")
metrics = pca_quality(model, x, scores, np.arange(0, len(x), 2))
if not np.isfinite(metrics["reconstruction_relative_l2"]):
    raise RuntimeError("cuML PCA benchmark scoring is not finite")
if not np.isfinite(elapsed):
    raise RuntimeError("cuML PCA timing is not finite")
args.method = "cuml_tsne"
tsne, layout, elapsed = fit_once(args, x, 2)
if not np.isfinite(layout).all():
    raise RuntimeError("cuML t-SNE smoke result is non-finite")
if not check_cuml_tsne(tsne, len(x))["fitted_kl_valid"]:
    raise RuntimeError("cuML t-SNE smoke fitted KL is invalid")
invalid = SimpleNamespace(**{
    name: getattr(tsne, name) for name in (
        "n_iter_", "method", "max_iter", "n_neighbors",
        "learning_rate_method", "learning_rate"
    )
})
invalid.kl_divergence_ = 0.0
if check_cuml_tsne(invalid, len(x))["fitted_kl_valid"]:
    raise RuntimeError("A zero fitted KL was accepted as valid")
print(f"cuml_tsne_iterations={tsne.n_iter_} fitted_kl="
      f"{tsne.kl_divergence_:.6f} elapsed_sec={elapsed:.6f}")
umap = UMAP(n_neighbors=15, init="spectral", random_state=4)
result = umap.fit_transform(x)
cp.cuda.runtime.deviceSynchronize()
if not np.isfinite(cp.asnumpy(result)).all():
    raise RuntimeError("cuML UMAP smoke result is non-finite")
print("cuml comparator smoke: PASS")
' > "$OUT/python_cuda.txt"
fi

printf '%s\n' \
  'experiment,dataset,backend,status,error' \
  "comparator_preflight,all,$BACKEND,success," > "$OUT/status.csv"
