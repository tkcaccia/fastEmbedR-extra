#!/usr/bin/env bash
#SBATCH --job-name=feR_scale
#SBATCH --partition=ada
#SBATCH --nodes=1
#SBATCH --ntasks=1
#SBATCH --cpus-per-task=16
#SBATCH --mem=192G
#SBATCH --time=48:00:00
#SBATCH --exclusive
#SBATCH --output=/scratch/firenze/NN/benchmark_logs/feR_scale_%j.out
#SBATCH --error=/scratch/firenze/NN/benchmark_logs/feR_scale_%j.err

set -u
BASE_DIR=/scratch/firenze/NN
IMAGE="${BASE_DIR}/singularity/fastembedr_cuda.sif"
SCRIPT_DIR="${BASE_DIR}/benchmark_scripts/multicore_scaling"
mkdir -p "${BASE_DIR}/benchmark_logs"

if [[ ! -s "${IMAGE}" ]]; then
  echo "Missing image: ${IMAGE}" >&2
  exit 2
fi

export APPTAINERENV_R_LIBS_USER=/usr/local/lib/R/site-library
export APPTAINERENV_OMP_NUM_THREADS=1
export APPTAINERENV_OPENBLAS_NUM_THREADS=1
export APPTAINERENV_MKL_NUM_THREADS=1
export APPTAINERENV_VECLIB_MAXIMUM_THREADS=1

BASE_DIR="${BASE_DIR}" SCRIPT_DIR="${SCRIPT_DIR}" IMAGE="${IMAGE}" \
  THREAD_GRID=1,2,4,8,16 DATASETS=MetRef,MNIST,simulated_1M_2D \
  REPEATS=5 WARMUPS=1 SEED=4 \
  bash "${SCRIPT_DIR}/run_multicore_scaling_release_gate.sh"
