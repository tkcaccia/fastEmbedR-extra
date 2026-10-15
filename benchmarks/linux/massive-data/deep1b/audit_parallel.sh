#!/usr/bin/env bash

set -euo pipefail
root=${DEEP1B_PARALLEL_ROOT:?Missing parallel ledger}
base=${DEEP1B_BASE:-/scratch/firenze/NN}
suite=$base/benchmark_scripts/massive-data/deep1b
printf '%s\taudit\tstarted\tjob=%s\n' \
    "$(date -u +%FT%TZ)" "$SLURM_JOB_ID" >> "$root/stages.tsv"
if ! sha256sum -c "$root/source.sha256" \
    > "$root/source_audit.txt" 2>&1; then
    printf 'audit\tall\tsource checksum mismatch\n' \
        >> "$root/failures.tsv"
    printf 'FAIL source checksum mismatch\n' > "$root/final_audit.txt"
    exit 1
fi
failed=0
printf 'phase\tdataset\tstatus\tcampaign\n' > "$root/final_audit.txt"
while IFS=$'\t' read -r phase dataset campaign; do
    [[ "$phase" == phase ]] && continue
    log=$root/audit_${phase}_${dataset}.txt
    if python3 "$suite/audit_campaign.py" "$campaign" \
        --output "$campaign/audit.json" > "$log" 2>&1; then
        status=PASS
    else
        status=FAIL
        failed=1
        printf '%s\t%s\tcase audit failed; see %s\n' \
            "$phase" "$dataset" "$log" >> "$root/failures.tsv"
    fi
    printf '%s\t%s\t%s\t%s\n' \
        "$phase" "$dataset" "$status" "$campaign" \
        >> "$root/final_audit.txt"
done < "$root/campaigns.tsv"
if [[ $(wc -l < "$root/campaigns.tsv") -ne 5 ]]; then
    printf 'audit\tall\texpected four campaign ledgers\n' \
        >> "$root/failures.tsv"
fi
if [[ $(wc -l < "$root/failures.tsv") -gt 1 ]]; then
    failed=1
fi
printf 'overall\tall\t%s\t-\n' \
    "$([[ "$failed" == 0 ]] && echo PASS || echo FAIL)" \
    >> "$root/final_audit.txt"
printf '%s\taudit\t%s\tsee final_audit.txt\n' \
    "$(date -u +%FT%TZ)" \
    "$([[ "$failed" == 0 ]] && echo completed || echo failed)" \
    >> "$root/stages.tsv"
exit "$failed"
