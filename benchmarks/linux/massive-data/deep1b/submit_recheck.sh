#!/usr/bin/env bash
set -euo pipefail

base=${DEEP1B_BASE:-/scratch/firenze/NN}
suite=$base/benchmark_scripts/massive-data/deep1b
image=${DEEP1B_IMAGE:-$base/singularity/fastembedr_cuda.sif}
expected=${FASTEMBEDR_IMAGE_SHA256:?Set FASTEMBEDR_IMAGE_SHA256}
printf '%s  %s\n' "$expected" "$image" | sha256sum -c -

full=$(bash "$suite/submit_fullgraph5m.sh")
printf '%s\n' "$full"
mapfile -t jobs < <(printf '%s\n' "$full" |
    awk -F '\t' 'NR > 1 {print $3}')
[[ "${#jobs[@]}" == 4 ]] || {
    echo "Expected four independent full-graph jobs." >&2
    exit 1
}
export DEEP1B_SKIP_CUDA2=1
for dataset in deep turing; do
    launch=$(bash "$suite/submit.sh" fresh5m "$dataset")
    printf '%s\n' "$launch"
    root=$(printf '%s\n' "$launch" |
        sed -n 's/^Campaign: //p' | head -n 1)
    test -s "$root/jobs.tsv"
    audit=$(awk -F '\t' '$1 == "audit" {print $2}' \
        "$root/jobs.tsv")
    [[ "$audit" =~ ^[0-9]+$ ]] || exit 1
    jobs+=("$audit")
done

dependency=$(IFS=:; echo "${jobs[*]}")
barrier=$(sbatch --parsable \
    --account="${DEEP1B_CPU_ACCOUNT:-immunology}" \
    --partition="${DEEP1B_CPU_PARTITION:-ada}" \
    --chdir="$base" --job-name=feR_billion_gate \
    --cpus-per-task=1 --mem=1G --time=00:05:00 \
    --dependency="afterany:$dependency" --wrap='true')
printf 'Billion-row disk gate: %s\n' "$barrier"
export DEEP1B_AFTER_JOB="$barrier"
bash "$suite/submit_billion_serial.sh"
