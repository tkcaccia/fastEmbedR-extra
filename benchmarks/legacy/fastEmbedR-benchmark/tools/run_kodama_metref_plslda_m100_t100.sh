#!/usr/bin/env bash

set -euo pipefail

BACKEND="${BACKEND:-cuda}"
IMAGE="${IMAGE:-/mnt/sata_ssd/fastEmbedR/singularity/fastembedr_cuda.sif}"
DATA="${DATA:-/mnt/sata_ssd/fastEmbedR/Data/MetRef/MetRef_float32.RData}"
SCRIPT="${SCRIPT:-/mnt/sata_ssd/fastEmbedR/tools/validate_kodama_metref_plslda_m100_t100.R}"
STAMP="${STAMP:-$(date +%Y%m%d_%H%M%S)}"
OUTPUT_DIR="${OUTPUT_DIR:-/mnt/sata_ssd/fastEmbedR/results/kodama_metref_plslda_m100_t100_${BACKEND}_${STAMP}}"
LOG="${OUTPUT_DIR}/run.log"
KODAMA_R_LIB="${KODAMA_R_LIB:-}"

mkdir -p "${OUTPUT_DIR}"
cp -p "${SCRIPT}" "${OUTPUT_DIR}/validate_kodama_metref_plslda_m100_t100.R"
cp -p "$0" "${OUTPUT_DIR}/run_kodama_metref_plslda_m100_t100.sh"

{
  echo "started_at=$(date --iso-8601=seconds)"
  echo "hostname=$(hostname)"
  echo "backend=${BACKEND}"
  echo "image=$(readlink -f "${IMAGE}")"
  echo "data=${DATA}"
  echo "script=${SCRIPT}"
  echo "output_dir=${OUTPUT_DIR}"
  echo "kodama_r_lib=${KODAMA_R_LIB}"
  nvidia-smi \
    --query-gpu=name,driver_version,memory.total,compute_cap \
    --format=csv,noheader
} | tee "${OUTPUT_DIR}/system_info.txt"

OMP_NUM_THREADS=4 \
OPENBLAS_NUM_THREADS=4 \
MKL_NUM_THREADS=4 \
APPTAINERENV_KODAMA_R_LIB="${KODAMA_R_LIB}" \
singularity exec \
  --nv \
  --cleanenv \
  -B /mnt/sata_ssd:/mnt/sata_ssd \
  "${IMAGE}" \
  Rscript "${SCRIPT}" "${OUTPUT_DIR}" "${DATA}" "${BACKEND}" \
  2>&1 | tee "${LOG}"

echo "finished_at=$(date --iso-8601=seconds)" | tee -a "${LOG}"
echo "Results: ${OUTPUT_DIR}"
