#!/usr/bin/env bash
# Run on the Mac. Copy evidence, never input or full-size output arrays.
set -euo pipefail

host=${HPC_HOST:-01481067@hex.uct.ac.za}
remote=${HPC_RESULT_ROOT:-/scratch/firenze/NN/fastEmbedR-results/massive-data}
local_root=${LOCAL_RESULT_ROOT:-/Users/stefano/Documents/fastEmbedR-results/massive-data}
mkdir -p "$local_root"
source="$host:$remote/"
if [[ "$host" == local ]]; then source="$remote/"; fi

rsync -rltvhm --partial --max-size=40m \
    --exclude='input/***' \
    --exclude='checkpoints/***' \
    --include='*/' \
    --include='state.json' \
    --include='audit*.json' \
    --include='visual_audit.json' \
    --include='input.json' \
    --include='metrics.csv' \
    --include='stages.csv' \
    --include='knn.csv' \
    --include='knn_device_audit.csv' \
    --include='knn_audit_rows.csv' \
    --include='hnsw_settings.csv' \
    --include='sample_community_counts.csv' \
    --include='preflight.json' \
    --include='all_cases.csv' \
    --include='matched_pairs.csv' \
    --include='unsupported_routes.tsv' \
    --include='input_manifest.csv' \
    --include='representative_results.csv' \
    --include='selected.csv' \
    --include='large_probe_results.csv' \
    --include='full_graph_feasibility.csv' \
    --include='hnsw_shards.csv.gz' \
    --include='knn_audit_rows.csv.gz' \
    --include='*_queries.csv' \
    --include='*_geometry.csv' \
    --include='*_timing.csv' \
    --include='source_label_legend.csv' \
    --include='quality.csv' \
    --include='knn_exact_quality.csv' \
    --include='refine_5m.csv' \
    --include='screen_5m.csv' \
    --include='gpu_memory.csv' \
    --include='plot_sample.csv.gz' \
    --include='plot_sample_10000.csv.gz' \
    --include='*.png' \
    --include='visual_manifest.csv' \
    --include='figure_manifest.csv' \
    --include='cluster_sample.csv.gz' \
    --include='landmark_labels.csv.gz' \
    --include='quality_row_ids.csv' \
    --include='*.tsv' \
    --include='*.sha256' \
    --include='image.stat' \
    --include='launch.txt' \
    --include='job.txt' \
    --include='source_check.txt' \
    --include='plot_preflight.out' \
    --include='plot_preflight.err' \
    --include='time.txt' \
    --include='fit.err' \
    --include='score.err' \
    --include='fit.out' \
    --include='final_audit.txt' \
    --exclude='*' \
    "$source" "$local_root/"

printf 'Small result evidence copied to %s\n' "$local_root"
