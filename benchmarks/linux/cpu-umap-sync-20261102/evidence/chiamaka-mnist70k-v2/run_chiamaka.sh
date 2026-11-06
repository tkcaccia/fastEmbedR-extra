#!/usr/bin/env bash
set -euo pipefail

root=/mnt/sata_ssd/fastEmbedR/in-progress/cuda-graph-options-20261102
if [ "$#" -ne 2 ]; then
    echo "Usage: run_chiamaka.sh CASE_NAME forward|reverse" >&2
    exit 2
fi
case_name=$1
run_order=$2
[[ $case_name =~ ^cpu-umap-sync-mnist70k-v[0-9]+$ ]]
[[ $run_order == forward || $run_order == reverse ]]
data=/mnt/sata_ssd/fastEmbedR
image=$data/singularity/rebuild_20261029_a670bcc/fastembedr_a670bcc_20261029.sif
knn=$data/tmp_source/fastEmbedR_src/_umap_cycle_cache
knn=$knn/MNIST_centered_k15_faissR_auto_nn.rds
pca=$data/Data/MNIST/MNIST_fastPLS_pca2_init.RData
output=$root/benchmark/$case_name
log=$root/benchmark/$case_name.log
status=$root/benchmark/$case_name.exit

test ! -e "$output" && test ! -e "$log" && test ! -e "$status"
printf '%s  %s\n' \
    0651d481a290cb41de4888b5288aab008ac91d971066a372f5fd1e5584e61e1a \
    "$knn" \
    3b51aecbd4d69334f5da67d3e13b22dda3a93d19f6bc444a4894f93ec9647689 \
    "$pca" | sha256sum -c -
mkdir "$output"
trap 'printf "%d\n" "$?" > "$status"' EXIT
cd "$root"
timeout --signal=TERM --kill-after=10s 900s \
    nice -n 10 singularity exec --bind /mnt/sata_ssd:/mnt/sata_ssd \
    "$image" env OPENBLAS_NUM_THREADS=1 OMP_NUM_THREADS=8 \
    Rscript run_cpu_umap_sync_mnist70k.R "$knn" "$pca" \
    "$output" "$root/validation-lib" "$run_order" > "$log" 2>&1
