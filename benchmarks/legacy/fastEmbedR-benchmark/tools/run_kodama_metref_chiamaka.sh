#!/usr/bin/env bash

set -euo pipefail

IMAGE="${IMAGE:-/mnt/sata_ssd/fastEmbedR/singularity/fastembedr_cuda.sif}"
DATA="${DATA:-/mnt/sata_ssd/fastEmbedR/Data/MetRef/MetRef.RData}"
SCRIPT="${SCRIPT:-/mnt/sata_ssd/fastEmbedR/tools/validate_kodama_metref_chiamaka.R}"
STAMP="${STAMP:-$(date +%Y%m%d_%H%M%S)}"
OUTPUT_DIR="${OUTPUT_DIR:-/mnt/sata_ssd/fastEmbedR/results/kodama_metref_${STAMP}}"
LOG="${OUTPUT_DIR}/run.log"
KODAMA_M="${KODAMA_M:-10}"
KODAMA_TCYCLE="${KODAMA_TCYCLE:-10}"

mkdir -p "${OUTPUT_DIR}"
cp -p "${SCRIPT}" "${OUTPUT_DIR}/validate_kodama_metref_chiamaka.R"
cp -p "$0" "${OUTPUT_DIR}/run_kodama_metref_chiamaka.sh"

{
  echo "started_at=$(date --iso-8601=seconds)"
  echo "hostname=$(hostname)"
  echo "image=$(readlink -f "${IMAGE}")"
  echo "data=${DATA}"
  echo "script=${SCRIPT}"
  echo "output_dir=${OUTPUT_DIR}"
  echo "KODAMA_M=${KODAMA_M}"
  echo "KODAMA_TCYCLE=${KODAMA_TCYCLE}"
  nvidia-smi \
    --query-gpu=name,driver_version,memory.total,compute_cap \
    --format=csv,noheader
} | tee "${OUTPUT_DIR}/system_info.txt"

OMP_NUM_THREADS=4 \
OPENBLAS_NUM_THREADS=4 \
MKL_NUM_THREADS=4 \
KODAMA_M="${KODAMA_M}" \
KODAMA_TCYCLE="${KODAMA_TCYCLE}" \
singularity exec \
  --nv \
  --cleanenv \
  -B /mnt/sata_ssd:/mnt/sata_ssd \
  "${IMAGE}" \
  Rscript "${SCRIPT}" "${OUTPUT_DIR}" "${DATA}" \
  2>&1 | tee "${LOG}"

echo "finished_at=$(date --iso-8601=seconds)" | tee -a "${LOG}"
echo "Results: ${OUTPUT_DIR}"
