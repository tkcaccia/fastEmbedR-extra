#!/bin/bash
#SBATCH --job-name=fer-tsne550-audit
#SBATCH --account=immunology
#SBATCH --partition=ada
#SBATCH --qos=normal
#SBATCH --cpus-per-task=1
#SBATCH --mem=1G
#SBATCH --time=00:05:00
#SBATCH --output=/scratch/firenze/NN/benchmarks/resident-comparators-535d071-20261107/audit-tsne550-%j.out
#SBATCH --error=/scratch/firenze/NN/benchmarks/resident-comparators-535d071-20261107/audit-tsne550-%j.err
set -Eeuo pipefail
root=/scratch/firenze/NN/benchmarks/resident-comparators-535d071-20261107
[[ ${PILOT_JOB_ID:?Provide the exact pilot job ID.} =~ ^[0-9]+$ ]]
python3 "$root/audit_coil20_r_tsne_schedule550_pilot.py" --root "$root" \
  --job "$PILOT_JOB_ID" --output "$root/coil20-r-tsne550-pilot-audit.json"
