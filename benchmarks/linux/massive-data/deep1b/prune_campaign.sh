#!/usr/bin/env bash

set -euo pipefail

if [[ $# -lt 1 || $# -gt 2 ||
    ( $# == 2 && $2 != --apply ) ]]; then
    echo "Usage: prune_campaign.sh CAMPAIGN_DIR [--apply]" >&2
    exit 2
fi
base=${DEEP1B_BASE:-/scratch/firenze/NN}
base=$(cd -- "$base" && pwd -P)
campaign=$(cd -- "$1" && pwd -P)
parent=$(dirname "$campaign")
name=$(basename "$campaign")
case "$parent" in
    "$base/fastEmbedR-results/massive-data/deep1b"|\
    "$base/fastEmbedR-results/massive-data/turing") ;;
    *) echo "Not a Deep1B/Turing result campaign." >&2; exit 2 ;;
esac
[[ "$name" =~ ^20[0-9]{6}T[0-9]{6}Z_(pilot|scale|boundary|billion)$ ]] || {
    echo "Unexpected campaign name: $name" >&2
    exit 2
}
[[ -f "$campaign/jobs.tsv" && -f "$campaign/source.sha256" ]] || {
    echo "Missing campaign ledger or source identity." >&2
    exit 2
}
[[ -d "$campaign/results" ]] || {
    echo "Campaign has no results directory." >&2
    exit 2
}
command -v squeue >/dev/null || {
    echo "Slurm squeue is required to verify inactive jobs." >&2
    exit 2
}
active_jobs=$(squeue -h -u "${USER:?}" -o '%A') || {
    echo "Could not inspect the active Slurm queue." >&2
    exit 1
}
while IFS=$'\t' read -r kind job count; do
    [[ "$job" =~ ^[0-9]+$ ]] || continue
    if grep -Fxq "$job" <<< "$active_jobs"; then
        echo "Campaign job $job is still active; refusing cleanup." >&2
        exit 1
    fi
done < "$campaign/jobs.tsv"

files=()
while IFS= read -r -d '' path; do
    files+=("$path")
done < <(find "$campaign/results" -type f \
    \( -name '*.f32' -o -name '*.u32' -o -name '*.u64' \
       -o -name '*.rds' -o -name '*.part' \) -print0)
printf 'Campaign: %s\nPayload files: %s\n' "$campaign" "${#files[@]}"
if (( ${#files[@]} )); then
    du -ch -- "${files[@]}" | tail -n 1
fi
if [[ ${2:-} != --apply ]]; then
    echo "Dry run only. Re-run with --apply to remove these payloads."
    exit 0
fi
if (( ${#files[@]} )); then
    rm -f -- "${files[@]}"
fi
echo "Removed generated payloads; metrics and provenance remain."
