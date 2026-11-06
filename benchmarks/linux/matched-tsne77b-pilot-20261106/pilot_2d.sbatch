#!/bin/bash
#SBATCH --job-name=fer-tsne8-coil2-77b852f
#SBATCH --account=immunology
#SBATCH --partition=ada
#SBATCH --qos=normal
#SBATCH --cpus-per-task=8
#SBATCH --mem=64G
#SBATCH --time=00:20:00
#SBATCH --output=/scratch/firenze/NN/benchmarks/matched_tsne77b_pilot_20261106/logs/pilot-2d-%j.out
#SBATCH --error=/scratch/firenze/NN/benchmarks/matched_tsne77b_pilot_20261106/logs/pilot-2d-%j.err
set -Eeuo pipefail
root=/scratch/firenze/NN/benchmarks/matched_tsne77b_pilot_20261106
image_root=/scratch/firenze/NN/singularity/release_77b852f_20261106
image="$image_root/fastembedr_77b852f_20261106.sif"
case_id=coil20_tsne_cpu8_d2_s4_matched_77b852f
[[ -r "$root/cases/$case_id.json" && -r "$image" ]]
[[ -z ${CUDA_VISIBLE_DEVICES:-} || ${CUDA_VISIBLE_DEVICES:-} == NoDevFiles ]]
expected=$(cut -d' ' -f1 "$image_root/image-1605295.sha256")
actual=$(sha256sum "$image" | cut -d' ' -f1)
[[ "$actual" == "$expected" ]]
singularity exec --bind /scratch/firenze/NN:/scratch/firenze/NN "$image" \
    /opt/conda/bin/python "$root/run_case.py" \
    "$root/cases/$case_id.json" /scratch/firenze/NN/Data \
    "$root/results"
