#!/bin/bash
#SBATCH --job-name=fer-py-audit
#SBATCH --account=immunology
#SBATCH --partition=ada
#SBATCH --qos=normal
#SBATCH --cpus-per-task=1
#SBATCH --mem=1G
#SBATCH --time=00:05:00
#SBATCH --output=/scratch/firenze/NN/benchmarks/resident-comparators-535d071-20261107/audit-python-%j.out
#SBATCH --error=/scratch/firenze/NN/benchmarks/resident-comparators-535d071-20261107/audit-python-%j.err
set -Eeuo pipefail
root=/scratch/firenze/NN/benchmarks/resident-comparators-535d071-20261107
[[ ${PILOT_JOB_ID:?Provide the exact pilot job ID.} =~ ^[0-9]+$ ]]
python3 "$root/audit_coil20_python_pilot.py" --root "$root" \
  --job "$PILOT_JOB_ID" --output "$root/coil20-python-pilot-audit.json"
