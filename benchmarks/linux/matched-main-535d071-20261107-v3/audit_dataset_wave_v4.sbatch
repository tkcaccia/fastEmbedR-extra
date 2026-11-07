#!/bin/bash
#SBATCH --job-name=fer-v3-dataset-audit
#SBATCH --account=immunology
#SBATCH --partition=ada
#SBATCH --qos=normal
#SBATCH --cpus-per-task=1
#SBATCH --mem=1G
#SBATCH --time=00:05:00
#SBATCH --output=/scratch/firenze/NN/benchmarks/matched-v3-dataset-audit-%j.out
#SBATCH --error=/scratch/firenze/NN/benchmarks/matched-v3-dataset-audit-%j.err
set -Eeuo pipefail
root=/scratch/firenze/NN/benchmarks/matched_main_535d071_20261107_v3
test -f "$root/audit_dataset_wave_v3.py"
[[ ${WAVE_JOB_IDS:?Provide six exact Slurm job IDs in CPU order.} =~ ^[0-9]+(:[0-9]+){5}$ ]]
case ${WAVE_DATASET_SLUG:?Provide one reviewed dataset slug.} in
  coil20) dataset=COIL20 ;;
  usps) dataset=USPS ;;
  mnist) dataset=MNIST ;;
  fashion) dataset=Fashion-MNIST ;;
  metref) dataset=MetRef ;;
  mass41) dataset=mass41 ;;
  flow18) dataset=flow18 ;;
  imagenet) dataset='ImageNet features' ;;
  flowrepository) dataset=FlowRepository ;;
  tabula) dataset='Tabula Muris' ;;
  retina) dataset='Macosko retina' ;;
  *) echo 'Unreviewed dataset slug.' >&2; exit 78 ;;
esac
IFS=: read -r -a jobs <<< "$WAVE_JOB_IDS"
python3 "$root/audit_dataset_wave_v3.py" --cohort-root "$root" \
  --dataset "$dataset" --jobs "${jobs[@]}" \
  --output "$root/${WAVE_DATASET_SLUG}-wave-audit-v3.json"
