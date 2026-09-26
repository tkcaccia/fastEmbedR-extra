#!/usr/bin/env bash

set -euo pipefail

: "${JSS_CAMPAIGN_DIR:?campaign directory required}"
: "${JSS_LEDGER:?campaign ledger required}"
: "${OUTPUT_ROOT:?output root required}"

AUDIT_TSV="$JSS_CAMPAIGN_DIR/job_audit.tsv"
SUMMARY="$JSS_CAMPAIGN_DIR/final_audit.txt"
FAILURES=0

printf 'label\tjob_id\tstate\texit_code\n' > "$AUDIT_TSV"
while IFS=$'\t' read -r _ _ _ role label job_id _ _ _; do
  [[ "$role" == "worker" ]] || continue
  record="$(sacct -X -n -P -j "$job_id" \
    -o JobIDRaw,State,ExitCode | awk -F '|' -v id="$job_id" \
    '$1 == id { print $2 "|" $3; exit }')"
  state="${record%%|*}"
  exit_code="${record#*|}"
  if [[ -z "$record" ]]; then
    state=UNKNOWN
    exit_code=NA
  fi
  printf '%s\t%s\t%s\t%s\n' \
    "$label" "$job_id" "$state" "$exit_code" >> "$AUDIT_TSV"
  if [[ "$state" != COMPLETED* || "$exit_code" != 0:0 ]]; then
    FAILURES=$((FAILURES + 1))
  fi
done < <(tail -n +2 "$JSS_LEDGER")

set +e
python3 - "$OUTPUT_ROOT" "$JSS_CAMPAIGN_DIR" <<'PY'
import csv
import pathlib
import sys

root = pathlib.Path(sys.argv[1])
campaign = pathlib.Path(sys.argv[2])
problems = []

required = [
    "aggregate/csv_inventory.csv",
    "aggregate/all_status.csv",
    "aggregate/scheduler_status_all.csv",
    "aggregate/support_timing_summary.csv",
    "aggregate/tsne_timing_summary.csv",
    "aggregate/backend_quality_summary.csv",
    "aggregate/knn_observed_recall.csv",
    "aggregate/affinity_characterization_all.csv",
    "aggregate/tsne_longrun_all.csv",
    "aggregate/transform_all.csv",
    "aggregate/scaling_summary.csv",
    "aggregate/pca_timing_all.csv",
    "aggregate/pca_accuracy_vs_dense.csv",
    "aggregate/clustering_precompute_all.csv",
    "aggregate/clustering_validation_all.csv",
    "aggregate/workflow_comparators_all.csv",
    "aggregate/workflow_comparators_timing_eligible.csv",
    "aggregate/workflow_comparator_parameters.csv",
    "aggregate/cuda_tsne_workflow_speed_ratio.csv",
]
for relative in required:
    path = root / relative
    if not path.is_file() or path.stat().st_size == 0:
        problems.append(f"missing required output: {relative}")

for path in root.rglob("*.csv"):
    if "aggregate" in path.parts:
        continue
    if path.name != "status.csv" and "scheduler_status" not in str(path):
        continue
    try:
        with path.open(newline="") as handle:
            for row in csv.DictReader(handle):
                status = row.get("status", "").lower()
                if status not in {"success", "completed"}:
                    problems.append(
                        f"non-success status {status!r}: {path}"
                    )
    except Exception as exc:
        problems.append(f"unreadable status file {path}: {exc}")

workflow = root / "workflow_comparators"
if workflow.is_dir():
    for status_path in workflow.rglob("status.csv"):
        with status_path.open(newline="") as handle:
            rows = list(csv.DictReader(handle))
        if not rows or rows[-1].get("status", "").lower() != "success":
            continue
        directory = status_path.parent
        for name in (
            "result.csv",
            "timing_repetitions.csv",
            "quality_layout.csv",
            "embedding.csv",
            "embedding.png",
        ):
            artifact = directory / name
            if not artifact.is_file() or artifact.stat().st_size == 0:
                problems.append(
                    f"successful method lacks {name}: {directory}"
                )

ratio_path = root / "aggregate/cuda_tsne_workflow_speed_ratio.csv"
if ratio_path.is_file():
    with ratio_path.open(newline="") as handle:
        ratios = list(csv.DictReader(handle))
    if len(ratios) != 11:
        problems.append(
            "CUDA t-SNE workflow ratios require 11 paired datasets; "
            f"observed {len(ratios)}"
        )
    for row in ratios:
        if row.get("total_iterations") != "750":
            problems.append("CUDA t-SNE ratio has a non-750 iteration budget")
        for field in ("timing_reps_fastembedr", "timing_reps_cuml"):
            if int(row.get(field, "0")) < 5:
                problems.append("CUDA t-SNE ratio has insufficient repetitions")
        for field in ("warmup_count_fastembedr", "warmup_count_cuml"):
            if int(row.get(field, "0")) < 1:
                problems.append("CUDA t-SNE ratio lacks an excluded warm-up")
        if row.get("comparison_type") != (
            "workflow_level_not_optimizer_matched"
        ):
            problems.append("CUDA t-SNE ratio has an invalid comparison type")
        if row.get("fastembedr_initialization") != "pca":
            problems.append("fastEmbedR CUDA t-SNE did not request PCA init")
        if row.get("cuml_initialization") != "pca":
            problems.append("cuML CUDA t-SNE did not request PCA init")
        if row.get("initialization_match") != (
            "same_policy_not_same_coordinates"
        ):
            problems.append("CUDA t-SNE initialization match is not explicit")

parameter_path = root / "aggregate/workflow_comparator_parameters.csv"
if parameter_path.is_file():
    with parameter_path.open(newline="") as handle:
        parameters = list(csv.DictReader(handle))
    for row in parameters:
        if row.get("family") not in {"tsne", "umap"}:
            continue
        if not row.get("initialization_requested"):
            problems.append("Missing comparator initialization metadata")
        if not row.get("initialization_match"):
            problems.append("Missing initialization match classification")
    rtsne = [row for row in parameters if row.get("method") == "rtsne"]
    if rtsne and any(row.get("initialization_requested") != "random"
                     for row in rtsne):
        problems.append("Rtsne PCA preprocessing was mislabeled as PCA init")

quality_path = root / "aggregate/backend_quality_raw.csv"
if quality_path.is_file():
    with quality_path.open(newline="") as handle:
        quality_rows = list(csv.DictReader(handle))
    for row in quality_rows:
        if row.get("timing_eligible", "").lower() == "true":
            problems.append("A quality diagnostic was marked timing eligible")
        if row.get("method") == "tsne" and row.get("total_iterations") != "750":
            problems.append(
                "A t-SNE quality diagnostic did not use 750 iterations"
            )

report = campaign / "output_audit.txt"
report.write_text(
    "\n".join(problems) + ("\n" if problems else "PASS\n"),
    encoding="utf-8",
)
raise SystemExit(1 if problems else 0)
PY
OUTPUT_STATUS=$?
set -e
if [[ "$OUTPUT_STATUS" -ne 0 ]]; then
  FAILURES=$((FAILURES + 1))
fi

{
  echo "campaign_id=$JSS_CAMPAIGN_ID"
  echo "completed_utc=$(date -u +%Y-%m-%dT%H:%M:%SZ)"
  echo "image_sha256=$FASTEMBEDR_IMAGE_SHA256"
  echo "expected_version=$EXPECTED_VERSION"
  echo "job_audit=$AUDIT_TSV"
  echo "output_audit=$JSS_CAMPAIGN_DIR/output_audit.txt"
  echo "failures=$FAILURES"
  if [[ "$FAILURES" -eq 0 ]]; then
    echo "status=PASS"
  else
    echo "status=FAIL"
  fi
} > "$SUMMARY"

cat "$SUMMARY"
[[ "$FAILURES" -eq 0 ]]
