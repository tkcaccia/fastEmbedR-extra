#!/usr/bin/env bash
set -euo pipefail

base=${DEEP1B_BASE:-/scratch/firenze/NN}
suite=$base/benchmark_scripts/massive-data/deep1b
after=${DEEP1B_AFTER_JOB:-}
if [[ -n "$after" && ! "$after" =~ ^[0-9]+$ ]]; then
    echo "DEEP1B_AFTER_JOB must be a Slurm job ID." >&2
    exit 2
fi
for backend in cpu cuda; do
    for dataset in deep turing; do
        for method in pca umap tsne leiden; do
            name=${backend}_${method}_1b
            awk -F '\t' -v name="$name" \
                'NR > 1 && $1 == name {found = 1} END {exit !found}' \
                "$suite/cases.tsv" || {
                echo "Missing billion-row case: $name" >&2
                exit 1
            }
            export DEEP1B_ONLY_BACKEND="$backend"
            export DEEP1B_CASE_FILTER="$name"
            export DEEP1B_AFTER_JOB="$after"
            export DEEP1B_PRUNE_BILLION=1
            export DEEP1B_ALLOW_BILLION=1
            export DEEP1B_SERIALIZE=1
            launch=$(bash "$suite/submit.sh" billion "$dataset")
            printf '%s\n' "$launch"
            root=$(printf '%s\n' "$launch" |
                sed -n 's/^Campaign: //p' | head -n 1)
            test -s "$root/jobs.tsv"
            after=$(awk -F '\t' '$1 == "audit" {print $2}' \
                "$root/jobs.tsv")
            [[ "$after" =~ ^[0-9]+$ ]] || {
                echo "No audit job in $root" >&2
                exit 1
            }
        done
    done
done
echo "Last scheduled audit job: $after"
