#!/usr/bin/env bash
set -euo pipefail

SRC_ROOT="${1:-/Users/stefano/Documents/umap}"
DST_ROOT="${2:-/Users/stefano/HPC-firenze}"

OUT_ROOT="${DST_ROOT}/sh_by_backend"
CPU_DIR="${OUT_ROOT}/cpu"
CUDA_DIR="${OUT_ROOT}/cuda"
COMMON_DIR="${OUT_ROOT}/common"

mkdir -p "$CPU_DIR" "$CUDA_DIR" "$COMMON_DIR"

classify_script() {
  local file="$1"
  local base
  base="$(basename "$file")"
  local lower
  lower="$(printf '%s' "$base" | tr '[:upper:]' '[:lower:]')"

  local is_cpu=0
  local is_cuda=0

  # Name-based classification
  if [[ "$lower" == *_cpu* ]] || [[ "$lower" == *"cpu_"* ]] || [[ "$lower" == *"cpu"* ]]; then
    is_cpu=1
  fi
  if [[ "$lower" == *_cuda* ]] || [[ "$lower" == *"cuda_"* ]] || [[ "$lower" == *"cuda"* ]]; then
    is_cuda=1
  fi

  # Header-based fallback for ambiguous cases
  if { (( is_cpu == 1 && is_cuda == 1 )); } || { (( is_cpu == 0 && is_cuda == 0 )); }; then
    local hdr
    hdr="$(awk 'NR<=80 {print tolower($0)}' "$file" | tr -d '\r')"

    if echo "$hdr" | grep -Eq '#SBATCH[[:space:]]+--(gres|gpus)=' || \
       echo "$hdr" | grep -Ei -q 'nvidia-smi|--gres=.*gpu|cuda|cuvs|cuml|torch\.cuda'; then
      is_cuda=1
      is_cpu=0
    elif echo "$hdr" | grep -Ei -q '#SBATCH[[:space:]]+--ntasks=|cpu|OMP_NUM_THREADS|OPENBLAS_NUM_THREADS|MKL_NUM_THREADS'; then
      is_cpu=1
      is_cuda=0
    else
      is_cpu=0
      is_cuda=0
    fi
  fi

  if (( is_cuda == 1 && is_cpu == 0 )); then
    echo cuda
  elif (( is_cpu == 1 && is_cuda == 0 )); then
    echo cpu
  else
    echo common
  fi
}

total=0
while IFS= read -r -d '' file; do
  rel="${file#$SRC_ROOT/}"
  cat_name="$(classify_script "$file")"
  case "$cat_name" in
    cpu) dest="$CPU_DIR/$(dirname "$rel")" ;;
    cuda) dest="$CUDA_DIR/$(dirname "$rel")" ;;
    common) dest="$COMMON_DIR/$(dirname "$rel")" ;;
  esac

  mkdir -p "$dest"
  cp -f "$file" "$dest/$(basename "$file")"
  ((total++))

done < <(find "$SRC_ROOT" -type f -name '*.sh' -print0)

echo "Saved $total .sh files from $SRC_ROOT"
printf 'CPU:   %s files\n' "$(find "$CPU_DIR" -type f -name '*.sh' | wc -l | tr -d ' ')"
printf 'CUDA:  %s files\n' "$(find "$CUDA_DIR" -type f -name '*.sh' | wc -l | tr -d ' ')"
printf 'Common:%s files\n' "$(find "$COMMON_DIR" -type f -name '*.sh' | wc -l | tr -d ' ')"

printf "Output directories:\n"
printf "  %s\n" "$CPU_DIR"
printf "  %s\n" "$CUDA_DIR"
printf "  %s\n" "$COMMON_DIR"
