#!/usr/bin/env bash
set -euo pipefail

if (( $# != 3 )); then
  echo "Usage: $0 IMAGE MNIST_FLOAT32.RData OUTPUT_DIR" >&2
  exit 2
fi
image=$(realpath "$1")
dataset=$(realpath "$2")
output=$(mkdir -p "$3" && realpath "$3")
suite=$(cd "$(dirname "$0")/.." && pwd)
input="$output/input"
runtime=$(command -v apptainer || command -v singularity)
bind=(--bind "$suite:$suite" --bind "$output:$output")
bind+=(--bind "$(dirname "$dataset"):$(dirname "$dataset")")

"$runtime" exec --cleanenv "${bind[@]}" "$image" \
  /opt/r46/bin/Rscript \
  "$suite/diagnostics/prepare_pca_plot_input.R" "$dataset" "$input"

for method in sklearn_pca cuml_pca; do
  backend=cpu
  gpu=()
  if [[ "$method" == cuml_pca ]]; then
    backend=cuda
    gpu=(--nv)
  fi
  target="$output/$method"
  mkdir -p "$target"
  "$runtime" exec "${gpu[@]}" --cleanenv "${bind[@]}" \
    --env OPENBLAS_NUM_THREADS=4,OMP_NUM_THREADS=4 \
    "$image" python \
    "$suite/common/run_python_comparator.py" \
    "--input-dir=$input" "--output-dir=$target" \
    --dataset=MNIST "--method=$method" "--backend=$backend" \
    --threads=4 --timing-reps=2 --n-components=2
  "$runtime" exec --cleanenv "${bind[@]}" "$image" \
    /opt/r46/bin/Rscript "$suite/common/plot_method_output.R" \
    "--input=$target/embedding.csv.gz" \
    "--output=$target/embedding.png"
done
