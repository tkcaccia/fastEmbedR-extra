#!/bin/bash
#SBATCH --job-name=fer-v3-pilot-audit
#SBATCH --account=immunology
#SBATCH --partition=ada
#SBATCH --qos=normal
#SBATCH --cpus-per-task=1
#SBATCH --mem=1G
#SBATCH --time=00:05:00
#SBATCH --output=/scratch/firenze/NN/benchmarks/matched_main_535d071_20261107_v3/logs/pilot-audit-%j.out
#SBATCH --error=/scratch/firenze/NN/benchmarks/matched_main_535d071_20261107_v3/logs/pilot-audit-%j.err
set -Eeuo pipefail
root=/scratch/firenze/NN/benchmarks/matched_main_535d071_20261107_v3
[[ ${PILOT_JOB_ID:?Exact pilot array job ID required.} =~ ^[0-9]+$ ]]
case ${PILOT_DATASET_SLUG:?Reviewed dataset slug required.} in
  tabula) dataset='Tabula Muris' ;;
  *) echo 'Dataset is outside this pilot.' >&2; exit 78 ;;
esac
[[ ${PILOT_CORES:?Exact CPU count required.} == 4 ]]
python3 "$root/audit_single_core_v1.py" --cohort-root "$root" \
  --dataset "$dataset" --cores 4 --job "$PILOT_JOB_ID" \
  --output "$root/${PILOT_DATASET_SLUG}-cpu4-pilot-audit-v3.json"
