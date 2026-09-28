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
import math
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
    "aggregate/cuda_umap_workflow_speed_ratio.csv",
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
if not workflow.is_dir():
    problems.append("missing comparator directory")
if workflow.is_dir():
    datasets = (
        "COIL20", "USPS", "FashionMNIST",
        "FlowRepository_FR-FCM-ZYRM_files", "flow18", "MNIST",
        "imagenet", "MetRef", "mass41", "TabulaMuris",
        "Macosko2015_retina",
    )
    for dataset in datasets:
        for family in ("tsne", "umap"):
            pair = root / "cuda_comparison_live" / dataset / family
            for filename in ("status.csv", "comparison.csv",
                             "comparison.png"):
                artifact = pair / filename
                if not artifact.is_file() or artifact.stat().st_size == 0:
                    problems.append(f"missing CUDA pair artifact: {artifact}")
            summary_path = pair / "comparison.csv"
            if summary_path.is_file():
                with summary_path.open(newline="") as handle:
                    rows = list(csv.DictReader(handle))
                expected = {f"fastembedr_{family}", f"cuml_{family}"}
                if {row.get("method") for row in rows} != expected:
                    problems.append(f"incomplete CUDA pair: {summary_path}")
    methods = {
        "r_cpu": (
            "fastembedr_pca", "irlba_pca", "fastembedr_tsne",
            "rtsne", "fitsne", "fastembedr_umap", "uwot",
            "uwot_fast_sgd", "r_umap",
        ),
        "r_cuda": (
            "fastembedr_pca", "fastembedr_tsne", "fastembedr_umap",
        ),
        "python_cpu": (
            "sklearn_pca", "sklearn_tsne", "python_opentsne",
            "python_umap",
        ),
        "python_cuda": ("cuml_pca", "cuml_tsne", "cuml_umap"),
    }
    for dataset in datasets:
        for mode, names in methods.items():
            for method in names:
                status_path = workflow / mode / dataset / method / "status.csv"
                if not status_path.is_file():
                    problems.append(f"missing comparator status: {status_path}")
    for dataset in ("USPS", "MetRef"):
        status_path = workflow / "r_cpu" / dataset / "stats_prcomp"
        if not (status_path / "status.csv").is_file():
            problems.append(f"missing comparator status: {status_path}")
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
        result_path = directory / "result.csv"
        if not result_path.is_file():
            continue
        with result_path.open(newline="") as handle:
            results = list(csv.DictReader(handle))
        if len(results) != 1:
            problems.append(f"expected one comparator result: {result_path}")
            continue
        result = results[0]
        method = directory.name
        family = (
            "pca" if method == "stats_prcomp" or method.endswith("_pca")
            else "tsne" if method in {"rtsne", "fitsne"}
            or "tsne" in method else "umap"
        )
        if result.get("method") != method or result.get("family") != family:
            problems.append(f"comparator method/family mismatch: {result_path}")
        try:
            elapsed = float(result["elapsed_median_sec"])
            if not math.isfinite(elapsed) or elapsed <= 0:
                raise ValueError("nonpositive or nonfinite elapsed time")
        except (KeyError, ValueError) as exc:
            problems.append(f"invalid comparator timing: {result_path}: {exc}")

for family in ("tsne", "umap"):
    ratio_path = root / f"aggregate/cuda_{family}_workflow_speed_ratio.csv"
    if not ratio_path.is_file():
        continue
    with ratio_path.open(newline="") as handle:
        ratios = list(csv.DictReader(handle))
    if len(ratios) != 11:
        problems.append(
            f"CUDA {family} workflow ratios require 11 paired datasets; "
            f"observed {len(ratios)}"
        )
    for row in ratios:
        if family == "tsne" and row.get("total_iterations") != "750":
            problems.append("CUDA t-SNE ratio has a non-750 iteration budget")
        if family == "umap" and row.get("n_neighbors") != "30":
            problems.append("CUDA UMAP ratio has a non-30 neighbor count")
        for field in ("timing_reps_fastembedr", "timing_reps_cuml"):
            if int(row.get(field, "0")) < 5:
                problems.append(f"CUDA {family} has insufficient repetitions")
        for field in ("warmup_count_fastembedr", "warmup_count_cuml"):
            if int(row.get(field, "0")) < 1:
                problems.append(f"CUDA {family} lacks an excluded warm-up")
        expected_type = (
            "workflow_level_not_optimizer_matched" if family == "tsne"
            else "workflow_level_not_parameter_matched"
        )
        if row.get("comparison_type") != expected_type:
            problems.append(f"CUDA {family} comparison type is invalid")
        expected_init = "pca" if family == "tsne" else "spectral"
        if row.get("fastembedr_initialization") != expected_init:
            problems.append(f"fastEmbedR CUDA {family} init is invalid")
        if row.get("cuml_initialization") != expected_init:
            problems.append(f"cuML CUDA {family} init is invalid")
        if row.get("initialization_match") != (
            "same_policy_not_same_coordinates"
        ):
            problems.append(f"CUDA {family} initialization is not explicit")
        if row.get("parameter_matched", "").lower() != "false":
            problems.append(f"CUDA {family} was mislabeled parameter matched")
        for field in (
            "fastembedr_median_sec", "cuml_median_sec",
            "fastembedr_knn_median_sec", "fastembedr_embedding_median_sec",
            "fastembedr_preserve_at_30", "cuml_preserve_at_30",
        ):
            try:
                value = float(row[field])
                if not math.isfinite(value):
                    raise ValueError("nonfinite")
            except (KeyError, ValueError) as exc:
                problems.append(f"CUDA {family} invalid {field}: {exc}")

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
        if row.get("trustworthiness", "").lower() in ("", "na", "nan"):
            problems.append(
                "Missing trustworthiness: " + row.get("dataset", "unknown")
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
TASK_FAILURES="$(tail -n +2 "$JSS_CAMPAIGN_DIR/failures.tsv" | wc -l)"
if (( TASK_FAILURES > 0 )); then
  FAILURES=$((FAILURES + 1))
fi

{
  echo "campaign_id=$JSS_CAMPAIGN_ID"
  echo "completed_utc=$(date -u +%Y-%m-%dT%H:%M:%SZ)"
  echo "image_sha256=$FASTEMBEDR_IMAGE_SHA256"
  echo "expected_version=$EXPECTED_VERSION"
  echo "job_audit=$AUDIT_TSV"
  echo "output_audit=$JSS_CAMPAIGN_DIR/output_audit.txt"
  echo "stages=$JSS_CAMPAIGN_DIR/stages.tsv"
  echo "task_failure_log=$JSS_CAMPAIGN_DIR/failures.tsv"
  echo "task_failures=$TASK_FAILURES"
  echo "failures=$FAILURES"
  if [[ "$FAILURES" -eq 0 ]]; then
    echo "status=PASS"
  else
    echo "status=FAIL"
  fi
} > "$SUMMARY"

cat "$SUMMARY"
[[ "$FAILURES" -eq 0 ]]
