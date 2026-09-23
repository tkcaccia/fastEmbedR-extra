#!/usr/bin/env bash
set -euo pipefail

SOURCE_ROOT="${1:-/Users/stefano/HPC-firenze/NN}"
TARGET_ROOT="${2:-/Users/stefano/HPC-firenze}"

CPU_DIR="${TARGET_ROOT}/sh_cpu"
CUDA_DIR="${TARGET_ROOT}/sh_cuda"
COMMON_DIR="${TARGET_ROOT}/sh_common"

mkdir -p "$CPU_DIR" "$CUDA_DIR" "$COMMON_DIR"

if [[ ! -d "$SOURCE_ROOT" ]]; then
  echo "Source root not found: $SOURCE_ROOT"
  exit 1
fi

mapfile -t SH_FILES < <(find "$SOURCE_ROOT" -type f -name '*.sh' -print)

for src in "${SH_FILES[@]}"; do
  base=$(basename "$src")
  rel=${src#$SOURCE_ROOT/}
  target_dir=""

  base_lc=$(printf '%s' "$base" | tr '[:upper:]' '[:lower:]')
  src_lc=$(printf '%s' "$src" | tr '[:upper:]' '[:lower:]')

  if [[ "$base_lc" == *_cpu1.sh || "$base_lc" == *_cpu4.sh || "$base_lc" == *_cpu12.sh || "$base_lc" == *_cpu.sh || "$src_lc" == *"/cpu/"* || "$base_lc" == *'_cpu_'* || "$base_lc" == *'run_cpu' * ]]; then
    target_dir="$CPU_DIR/$(dirname "$rel")"
  elif [[ "$base_lc" == *'_cuda.sh' || "$base_lc" == *_cuda_* || "$src_lc" == *"/cuda/"* || "$base_lc" == *'run_reviewer_hpc_cuda.sh' || "$base_lc" == *'benchmark_embeddings_float32_cuda.sh' || "$base_lc" == *'benchmark_faissr_cuda.sh' ]]; then
    target_dir="$CUDA_DIR/$(dirname "$rel")"
  else
    # keep generic launchers/helpers in common
    target_dir="$COMMON_DIR/$(dirname "$rel")"
  fi

  mkdir -p "$target_dir"
  cp "$src" "$target_dir/$base"
 done

echo "Saved CPU scripts:  $CPU_DIR"
echo "Saved CUDA scripts: $CUDA_DIR"
echo "Saved common scripts: $COMMON_DIR"
printf "CPU: ";   find "$CPU_DIR" -type f -name '*.sh' | wc -l
printf "CUDA: ";  find "$CUDA_DIR" -type f -name '*.sh' | wc -l
printf "Common: "; find "$COMMON_DIR" -type f -name '*.sh' | wc -l
