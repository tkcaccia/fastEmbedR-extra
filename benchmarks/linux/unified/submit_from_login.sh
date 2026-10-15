#!/usr/bin/env bash
# Run on the UCT login node; the benchmark launcher runs on a CPU node.
set -euo pipefail

base=${FASTEMBEDR_BASE:-/scratch/firenze/NN}
suite=$base/benchmark_scripts/unified
quota_command=purequota
if ! command -v "$quota_command" >/dev/null; then
    quota_command=myquota
fi
command -v "$quota_command" >/dev/null || {
    echo 'Run this helper where purequota is available.' >&2
    exit 2
}
free=$("$quota_command" | awk '$1 == "/scratch" {
    gsub(/GB/, "", $2); gsub(/GB/, "", $3)
    printf "%.0f", ($2 - $3) * 1000000000
}')
[[ "$free" =~ ^[0-9]+$ ]] || {
    echo 'Could not read the scratch quota.' >&2
    exit 2
}
test -s "$suite/submit.sbatch"
mkdir -p "$base/benchmark_logs"
printf 'Scratch quota free: %s bytes\n' "$free"
sbatch --parsable --export=ALL,DEEP1B_QUOTA_FREE_BYTES="$free" \
    "$suite/submit.sbatch"
