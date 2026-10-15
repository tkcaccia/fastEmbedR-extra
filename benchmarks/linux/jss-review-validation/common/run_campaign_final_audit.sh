#!/usr/bin/env bash

set -euo pipefail

: "${JSS_CAMPAIGN_DIR:?campaign directory required}"
: "${JSS_LEDGER:?campaign ledger required}"
: "${OUTPUT_ROOT:?output root required}"
SUITE="${SUITE:-$PWD/benchmark_scripts/fastembedr_jss_review_validation}"

AUDIT_TSV="$JSS_CAMPAIGN_DIR/job_audit.tsv"
TASK_AUDIT="$JSS_CAMPAIGN_DIR/job_audit_tasks.tsv"
SUMMARY="$JSS_CAMPAIGN_DIR/final_audit.txt"
FAILURES=0

printf 'label\tjob_id\tstate\texit_code\n' > "$AUDIT_TSV"
printf 'job_key\tstate\texit_code\n' > "$TASK_AUDIT"
while IFS=$'\t' read -r _ _ _ role label job_id _ _ _; do
  [[ "$role" == "worker" ]] || continue
  record="$(sacct -X -n -P -j "$job_id" \
    -o JobIDRaw,State,ExitCode | awk -F '|' -v id="$job_id" \
    '$1 == id { print $2 "|" $3; exit }')"
  records="$(sacct -n -P -j "$job_id" \
    -o JobID,State%30,ExitCode)"
  printf '%s\n' "$records" | awk -F '|' -v id="$job_id" '
    {
      key = $1
      sub(/\..*$/, "", key)
      if (key !~ ("^" id "_[0-9]+$")) next
      if (!(key in state) || $2 ~ /^OUT_OF_MEMORY/ ||
          ($2 ~ /^TIMEOUT/ && state[key] !~ /^OUT_OF_MEMORY/)) {
        state[key] = $2
        code[key] = $3
      }
    }
    END {
      for (key in state)
        print key "\t" state[key] "\t" code[key]
    }
  ' >> "$TASK_AUDIT"
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

python3 "$SUITE/common/summarize_comparator_outcomes.py" \
  "$OUTPUT_ROOT" "$TASK_AUDIT"

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
    "aggregate/clustering_scale_all.csv",
    "aggregate/workflow_comparators_all.csv",
    "aggregate/task_memory.csv",
    "aggregate/task_gpu_memory.csv",
    "aggregate/workflow_comparators_timing_eligible.csv",
    "aggregate/workflow_comparator_parameters.csv",
    "aggregate/workflow_comparator_outcomes.csv",
    "aggregate/cuda_tsne_workflow_speed_ratio.csv",
    "aggregate/cuda_umap_workflow_speed_ratio.csv",
    "aggregate/umap_binary_vs_fuzzy.csv",
]
for relative in required:
    path = root / relative
    if not path.is_file() or path.stat().st_size == 0:
        problems.append(f"missing required output: {relative}")

scaling_path = root / "aggregate/scaling_summary.csv"
if scaling_path.is_file():
    stages = (
        "knn_sec", "pca_sec", "pca_rank50_sec", "graph_sec",
        "walktrap_graph_sec", "louvain_fit_sec", "leiden_fit_sec",
        "walktrap_fit_sec", "louvain_graph_fit_sec",
        "leiden_graph_fit_sec", "walktrap_graph_fit_sec",
        "tsne_embedding_sec", "umap_embedding_sec",
        "total_tsne_sec", "total_umap_sec",
    )
    datasets = ("COIL20", "MNIST", "flow18", "imagenet")
    threads = (1, 2, 4, 8, 12)
    seen = set()
    with scaling_path.open(newline="") as handle:
        for row in csv.DictReader(handle):
            key = (row["dataset"], row["stage"], int(row["threads"]))
            if key in seen:
                problems.append(f"duplicate CPU scaling row: {key}")
            seen.add(key)
            if (int(row["repetitions"]) < 3 or
                    int(row["n_observations"]) < 1 or
                    not math.isfinite(float(row["median_sec"])) or
                    not math.isfinite(float(row["speedup"]))):
                problems.append(f"invalid CPU scaling measurement: {key}")
            if row["stage"] in (
                    "louvain_fit_sec", "leiden_fit_sec",
                    "walktrap_fit_sec") and row["fit_threads"] != "1":
                problems.append(f"serial fit mislabeled: {key}")
    expected = {
        (dataset, stage, n_threads)
        for dataset in datasets for stage in stages
        for n_threads in threads
    }
    for key in sorted(expected - seen):
        problems.append(f"missing CPU scaling row: {key}")

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
memory_index = {}
memory_path = root / "aggregate/workflow_comparators_all.csv"
if memory_path.is_file():
    with memory_path.open(newline="") as handle:
        for row in csv.DictReader(handle):
            key = (row["comparator_mode"], row["dataset"], row["method"])
            if key in memory_index:
                problems.append(f"duplicate comparator memory row: {key}")
            memory_index[key] = row
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
        input_path = root.parent / "input" / dataset
        input_path = input_path / "workflow_comparators/manifest.csv"
        try:
            with input_path.open(newline="") as handle:
                input_row = next(csv.DictReader(handle))
            if (input_row.get("full_source", "").lower() != "true" or
                    int(input_row["n"]) != int(input_row["source_n"])):
                problems.append(f"comparator input is capped: {input_path}")
        except (OSError, ValueError, KeyError, StopIteration) as exc:
            problems.append(f"invalid comparator input: {input_path}: {exc}")
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
                if family == "umap":
                    expected.add("fastembedr_umap_binary")
                if {row.get("method") for row in rows} != expected:
                    problems.append(f"incomplete CUDA pair: {summary_path}")
    methods = {
        "r_cpu": (
            "fastembedr_pca", "irlba_pca", "fastembedr_tsne",
            "rtsne", "fitsne", "fastembedr_umap",
            "fastembedr_umap_binary", "uwot",
            "uwot_fast_sgd", "r_umap",
        ),
        "r_cuda": (
            "fastembedr_pca", "fastembedr_tsne", "fastembedr_umap",
            "fastembedr_umap_binary",
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
            "embedding.png",
        ):
            artifact = directory / name
            if not artifact.is_file() or artifact.stat().st_size == 0:
                problems.append(
                    f"successful method lacks {name}: {directory}"
                )
        if not any((directory / name).is_file() and
                   (directory / name).stat().st_size > 0 for name in
                   ("embedding.csv.gz", "embedding.csv")):
            problems.append(f"successful method lacks embedding: {directory}")
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
        try:
            source = root.parent / "input" / directory.parent.name
            source = source / "workflow_comparators/manifest.csv"
            with source.open(newline="") as handle:
                source_n = int(next(csv.DictReader(handle))["source_n"])
            if int(result["n"]) != source_n:
                problems.append(f"capped comparator fit: {result_path}")
        except (OSError, ValueError, KeyError, StopIteration) as exc:
            problems.append(f"unverifiable comparator rows: {result_path}: {exc}")
        if result.get("family") == "pca":
            try:
                expected_rank = min(50, int(result["n"]) - 1,
                                    int(result["p"]) - 1)
                if int(result["pca_rank"]) != expected_rank:
                    raise ValueError("incorrect PCA rank")
            except (KeyError, ValueError) as exc:
                problems.append(f"PCA rank check failed: {directory}: {exc}")
        if method == "cuml_tsne":
            try:
                if (int(result.get("n_neighbors", 0)) != 90 or
                        int(result.get(
                            "cuml_tsne_reported_neighbors", 0)) != 90 or
                        result.get("affinity_support") !=
                        "cuml_default_90"):
                    raise ValueError("incorrect cuML neighbor support")
                observed = int(result.get(
                    "cuml_tsne_min_observed_iterations", 0))
                with (directory / "timing_repetitions.csv").open(
                        newline="") as handle:
                    repetitions = list(csv.DictReader(handle))
                if observed != 1000 or not repetitions or any(
                        int(row.get("observed_iterations", 0)) != 1000
                        for row in repetitions):
                    raise ValueError("fewer than 1000 iterations")
            except (OSError, ValueError) as exc:
                problems.append(
                    f"cuML t-SNE iteration check failed: {directory}: {exc}"
                )
        if method in {"fastembedr_umap",
                      "fastembedr_umap_binary"}:
            expected_mode = ("binary" if method.endswith("binary")
                             else "fuzzy")
            if result.get("graph_mode") != expected_mode:
                problems.append(f"incorrect UMAP graph mode: {result_path}")
        family = (
            "pca" if method.endswith("_pca")
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
        key = (directory.parent.parent.name, directory.parent.name, method)
        memory_row = memory_index.get(key)
        if memory_row is None:
            problems.append(f"missing comparator memory row: {directory}")
            continue
        fields = ["peak_host_gib"]
        if "cuda" in key[0]:
            fields.append("peak_device_incremental_gib")
        for field in fields:
            try:
                value = float(memory_row[field])
                if not math.isfinite(value) or value <= 0:
                    raise ValueError("nonpositive or nonfinite peak")
            except (KeyError, ValueError) as exc:
                problems.append(f"invalid {field}: {directory}: {exc}")
        if "cuda" in key[0]:
            try:
                if int(float(memory_row["device_samples_n"])) < 2:
                    raise ValueError("fewer than two GPU samples")
            except (KeyError, ValueError) as exc:
                problems.append(f"invalid GPU sample count: {directory}: {exc}")
        trace_dir = root / "measurement/workflow_comparators"
        trace_dir = trace_dir.joinpath(*key)
        if len(list(trace_dir.glob("*.time.txt"))) != 1:
            problems.append(f"missing unique host memory trace: {directory}")
        if "cuda" in key[0] and len(list(
                trace_dir.glob("*.gpu_memory.csv"))) != 1:
            problems.append(f"missing unique GPU memory trace: {directory}")

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
        if family == "tsne" and row.get("total_iterations") != "1000":
            problems.append("CUDA t-SNE ratio has a non-1000 iteration budget")
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
    if rtsne and any(
        row.get("initialization_requested") != "pca"
        or row.get("pca_preprocessing") != "none"
        or row.get("initialization_engine") != "irlba_prcomp_irlba"
        or not row.get("initialization_engine_version")
        or row.get("timing_scope") != "R_workflow_fit"
        for row in rtsne
    ):
        problems.append("Rtsne PCA initialization contract is invalid")

quality_path = root / "aggregate/backend_quality_raw.csv"
if quality_path.is_file():
    with quality_path.open(newline="") as handle:
        quality_rows = list(csv.DictReader(handle))
    for row in quality_rows:
        if row.get("timing_eligible", "").lower() == "true":
            problems.append("A quality diagnostic was marked timing eligible")
        if row.get("method") == "tsne" and (
            row.get("early_iterations") != "250"
            or row.get("normal_iterations") != "750"
            or row.get("total_iterations") != "1000"
        ):
            problems.append(
                "A t-SNE quality diagnostic did not use 250+750 iterations"
            )
        if row.get("trustworthiness", "").lower() in ("", "na", "nan"):
            problems.append(
                "Missing trustworthiness: " + row.get("dataset", "unknown")
            )

support_path = root / "aggregate/support_timing_summary.csv"
if support_path.is_file():
    with support_path.open(newline="") as handle:
        support_rows = list(csv.DictReader(handle))
    expected = {
        (dataset, backend, str(perplexity), str(width))
        for dataset in ("COIL20", "USPS", "MNIST", "MetRef")
        for backend in ("cpu", "cuda")
        for perplexity in (10, 20, 30)
        for width in (1, 3)
    }
    observed = {
        (row["dataset"], row["backend"], row["perplexity"],
         row["support_multiplier"])
        for row in support_rows
    }
    missing = expected - observed
    if missing:
        problems.append(f"Missing support sensitivity rows: {sorted(missing)}")

cluster_path = root / "aggregate/clustering_validation_all.csv"
cluster_inputs = root / "aggregate/clustering_precompute_all.csv"
def finite_ari(row, field):
    try:
        return math.isfinite(float(row[field]))
    except (KeyError, TypeError, ValueError):
        return False

cluster_sizes = {}
walktrap_sizes = {}
if cluster_inputs.is_file():
    with cluster_inputs.open(newline="") as handle:
        for row in csv.DictReader(handle):
            if row["graph"] == "full":
                cluster_sizes[row["dataset"]] = int(row["n"])
            elif row["graph"] == "walktrap_subset":
                walktrap_sizes[row["dataset"]] = int(row["n"])
if cluster_path.is_file():
    with cluster_path.open(newline="") as handle:
        clustered = list(csv.DictReader(handle))
    expected = {
        (dataset, backend, method)
        for dataset in ("COIL20", "MetRef", "MNIST", "flow18")
        for backend in ("cpu", "cuda")
        for method in ("louvain", "leiden")
    }
    observed = {
        (row["dataset"], row["backend"], row["method"])
        for row in clustered if row.get("implementation") == "fastEmbedR"
    }
    missing = expected - observed
    if missing:
        problems.append(f"Missing clustering runs: {sorted(missing)}")
    for dataset in ("COIL20", "MetRef", "MNIST", "flow18"):
        n = cluster_sizes.get(dataset)
        if n is None:
            problems.append(f"Missing clustering graph size: {dataset}")
        subset_n = walktrap_sizes.get(dataset)
        if subset_n is None or subset_n > 3000:
            problems.append(f"Invalid Walktrap subset size: {dataset}")
        if (dataset, "cpu", "walktrap") not in observed:
            problems.append(f"Missing Walktrap subset run: {dataset}")
    for row in clustered:
        if row.get("implementation") != "fastEmbedR":
            continue
        if not finite_ari(row, "label_ari") or not finite_ari(
            row, "reference_membership_ari"
        ):
            problems.append("Missing clustering label or paired ARI")
            break
        if row["backend"] != row.get("observed_backend", row["backend"]):
            problems.append("Clustering backend mismatch")
            break

scale_path = root / "aggregate/clustering_scale_all.csv"
if scale_path.is_file():
    with scale_path.open(newline="") as handle:
        scale = list(csv.DictReader(handle))
    expected_scale = {
        (backend, method, n, run)
        for backend in ("cpu", "cuda")
        for method in ("louvain", "leiden")
        for n in (1500, 3000, 10000, 50000)
        for run in (1, 2, 3)
    }
    expected_scale.update({
        ("cpu", "walktrap", n, run)
        for n in (1500, 3000) for run in (1, 2, 3)
    })
    native_scale = [
        row for row in scale if row["implementation"] == "fastEmbedR"
    ]
    observed_scale = {
        (row["backend"], row["method"], int(row["n_vertices"]),
         int(row["run"]))
        for row in native_scale
    }
    if observed_scale != expected_scale or len(native_scale) != len(
        expected_scale
    ):
        problems.append("Incomplete clustering size sweep")
    if any(
        not finite_ari(row, "label_ari") or not finite_ari(
            row, "reference_membership_ari"
        ) for row in native_scale
    ):
        problems.append("Missing clustering size-sweep ARI")
    if any(row["backend"] != row["observed_backend"]
           for row in native_scale):
        problems.append("Clustering size-sweep backend mismatch")

memory_fits = list(root.glob("landmark_memory/*/*/*/*/result.csv"))
if len(memory_fits) != 88:
    problems.append(f"Expected 88 isolated landmark memory fits, got "
                    f"{len(memory_fits)}")
memory_times = list(root.glob("measurement/landmark_memory/*/*/*.time.txt"))
if len(memory_times) != 88:
    problems.append(f"Expected 88 landmark memory time files, got "
                    f"{len(memory_times)}")
memory_gpu = list(root.glob("measurement/landmark_memory/*/cuda/"
                            "*.gpu_memory.csv"))
if len(memory_gpu) != 44:
    problems.append(f"Expected 44 CUDA landmark memory traces, got "
                    f"{len(memory_gpu)}")

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
if ! python3 "$SUITE/file_backed/audit.py" \
    "$OUTPUT_ROOT" --strict; then
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
  echo "file_backed_audit=$OUTPUT_ROOT/file_backed/audit.txt"
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
