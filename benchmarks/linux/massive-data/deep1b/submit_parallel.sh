#!/usr/bin/env bash
# Submit independent pilot and scale cases; audit after every array ends.

set -euo pipefail
base=${DEEP1B_BASE:-/scratch/firenze/NN}
suite=$base/benchmark_scripts/massive-data/deep1b
active=$(squeue -h -u "$USER" -o '%j')
if printf '%s\n' "$active" | grep -Eq '^feR_(deep|turing)'; then
    echo "An earlier Deep1B/Turing campaign is still active." >&2
    exit 1
fi
parent=$base/fastEmbedR-results/massive-data/parallel
mkdir -p "$parent" "$base/benchmark_logs"
root=$(mktemp -d "$parent/$(date -u +%Y%m%dT%H%M%SZ)_XXXXXX")
image=${DEEP1B_IMAGE:-$base/singularity/fastembedr_cuda.sif}
sha256sum "$image" "$suite/submit.sh" "$suite/submit_parallel.sh" \
    "$suite/audit_parallel.sh" "$suite/slurm_parallel_audit.sbatch" \
    "$suite/audit_campaign.py" "$suite/cases.tsv" \
    "$suite/run_case.sh" "$suite/preflight.R" \
    "$suite/validate_input.py" "$suite/score.R" \
    "$suite/score_cluster.R" \
    "$suite/score_knn_exact.R" "$suite/gpu_memory.py" \
    "$suite/slurm_case.sbatch" "$suite/slurm_preflight.sbatch" \
    "$suite/slurm_audit.sbatch" "$suite/prune_campaign.sh" \
    "$base/benchmark_scripts/massive-data/run_scaling.R" \
    > "$root/source.sha256"
printf 'phase\tdataset\tcampaign\n' > "$root/campaigns.tsv"
printf 'phase\tdataset\tjob_id\tcampaign\n' > "$root/jobs.tsv"
printf 'timestamp_utc\tphase\tstate\tdetail\n' > "$root/stages.tsv"
printf 'phase\tdataset\treason\n' > "$root/failures.tsv"
dependencies=()
failed=0
for phase in pilot scale; do
  for dataset in deep turing; do
    log=$root/${phase}_${dataset}_launch.log
    submitted=1
    bash "$suite/submit.sh" "$phase" "$dataset" > "$log" 2>&1 ||
        submitted=0
    campaign=$(sed -n 's/^Campaign: //p' "$log" | tail -n 1)
    if [[ -n "$campaign" && -s "$campaign/jobs.tsv" ]]; then
        printf '%s\t%s\t%s\n' \
            "$phase" "$dataset" "$campaign" >> "$root/campaigns.tsv"
        while IFS=$'\t' read -r kind job count; do
            [[ "$kind" == kind ]] && continue
            dependencies+=("$job")
            printf '%s\t%s\t%s\t%s\n' \
                "$phase" "$dataset" "$job" "$campaign" \
                >> "$root/jobs.tsv"
        done < "$campaign/jobs.tsv"
    fi
    if [[ "$submitted" == 0 ]]; then
        printf '%s\t%s\tsubmission failed; see %s\n' \
            "$phase" "$dataset" "$log" >> "$root/failures.tsv"
        failed=1
    fi
    printf '%s\t%s\t%s\t%s %s\n' \
        "$(date -u +%FT%TZ)" "$phase" \
        "$([[ "$submitted" == 1 ]] && echo submitted || echo failed)" \
        "$dataset" "$campaign" >> "$root/stages.tsv"
  done
done
if ((${#dependencies[@]} == 0)); then
    echo "No jobs were submitted. Ledger: $root" >&2
    exit 1
fi
joined=$(IFS=:; echo "${dependencies[*]}")
audit=$(sbatch --parsable \
    --account="${DEEP1B_CPU_ACCOUNT:-immunology}" \
    --partition="${DEEP1B_CPU_PARTITION:-ada}" \
    --dependency="afterany:$joined" \
    --export=ALL,DEEP1B_PARALLEL_ROOT="$root" \
    "$suite/slurm_parallel_audit.sbatch")
printf 'audit\tall\t%s\t%s\n' "$audit" "$root" >> "$root/jobs.tsv"
printf '%s\taudit\tsubmitted\tjob=%s\n' \
    "$(date -u +%FT%TZ)" "$audit" >> "$root/stages.tsv"
echo "Parallel ledger: $root"
echo "Final audit job: $audit"
cat "$root/jobs.tsv"
exit "$failed"
