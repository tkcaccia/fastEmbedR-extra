#!/usr/bin/env bash
# Stop the obsolete comprehensive campaign, including its late controllers.
set -euo pipefail

[[ ${1:-} == --apply && $# -eq 1 ]] || {
    echo "Usage: stop_comprehensive.sh --apply" >&2
    exit 2
}

for pass in 1 2 3; do
    mapfile -t ids < <(
        squeue -h -u "$USER" -o '%A|%j' |
            awk -F '|' '$2 ~ /^feR_(cpu|cuda|deep|turing|auto)/ {
                print $1
            }' | sort -u
    )
    ((${#ids[@]})) || break
    printf 'Canceling campaign jobs: %s\n' "${ids[*]}"
    scancel "${ids[@]}"
    sleep 2
done

remaining=$(squeue -h -u "$USER" -o '%A|%j' |
    awk -F '|' '$2 ~ /^feR_(cpu|cuda|deep|turing|auto)/')
if [[ -n "$remaining" ]]; then
    printf 'Campaign jobs still present:\n%s\n' "$remaining" >&2
    exit 1
fi
echo 'No matching comprehensive campaign jobs remain.'
