#!/bin/bash
#SBATCH --job-name=fer-v3-coil-wave-audit
#SBATCH --account=immunology
#SBATCH --partition=ada
#SBATCH --qos=normal
#SBATCH --cpus-per-task=1
#SBATCH --mem=1G
#SBATCH --time=00:05:00
#SBATCH --output=/scratch/firenze/NN/benchmarks/matched-v3-coil-wave-audit-%j.out
#SBATCH --error=/scratch/firenze/NN/benchmarks/matched-v3-coil-wave-audit-%j.err
set -Eeuo pipefail
root=/scratch/firenze/NN/benchmarks/matched_main_535d071_20261107_v3
test -f "$root/audit_dataset_wave_v3.py"
[[ ${WAVE_JOB_IDS:?Provide six exact Slurm job IDs in CPU order.} =~ ^[0-9]+(:[0-9]+){5}$ ]]
IFS=: read -r -a jobs <<< "$WAVE_JOB_IDS"
python3 "$root/audit_dataset_wave_v3.py" --cohort-root "$root" \
  --dataset COIL20 --jobs "${jobs[@]}" \
  --output "$root/coil20-wave-audit-v3.json"
