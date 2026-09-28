#!/usr/bin/env bash

set -euo pipefail

SUITE="$(cd "$(dirname "$0")/.." && pwd)"
export SUITE
CONTROLLER="$SUITE/common/run_complete_campaign_controller.sh"
TEST_ROOT="$(mktemp -d)"
trap 'rm -rf "$TEST_ROOT"' EXIT
mkdir -p "$TEST_ROOT/bin"

cat > "$TEST_ROOT/bin/sbatch" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
id="$(< "$JSS_FAKE_COUNTER")"
id=$((id + 1))
printf '%s\n' "$id" > "$JSS_FAKE_COUNTER"
printf '%s\n' "$id"
EOF
cat > "$TEST_ROOT/bin/sacct" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
while (($#)); do
  if [[ "$1" == -j ]]; then
    printf '%s|COMPLETED|0:0\n' "$2"
    exit 0
  fi
  shift
done
exit 1
EOF
cat > "$TEST_ROOT/bin/flock" <<'EOF'
#!/usr/bin/env bash
exit 0
EOF
chmod +x "$TEST_ROOT/bin/"*
printf '1000\n' > "$TEST_ROOT/counter"

export PATH="$TEST_ROOT/bin:$PATH"
export JSS_FAKE_COUNTER="$TEST_ROOT/counter"
export BASE_DIR="$TEST_ROOT"
export IMAGE="$TEST_ROOT/image.sif"
export INPUT_ROOT="$TEST_ROOT/input"
export OUTPUT_ROOT="$TEST_ROOT/results"
export EXPECTED_VERSION=0.1
export FASTEMBEDR_IMAGE_SHA256=test
export FASTEMBEDR_SUITE_MANIFEST_SHA256
FASTEMBEDR_SUITE_MANIFEST_SHA256="$(
  sha256sum "$SUITE/FILES.sha256" | awk '{print $1}')"
export JSS_CAMPAIGN_ID=test
export JSS_CAMPAIGN_DIR="$TEST_ROOT/campaign"
export JSS_LEDGER="$JSS_CAMPAIGN_DIR/jobs.tsv"

run_stage() {
  if ! JSS_STAGE="$1" bash "$CONTROLLER" \
      >> "$TEST_ROOT/schedule.log" 2>&1; then
    cat "$TEST_ROOT/schedule.log" >&2
    return 1
  fi
}

run_stage comparator_inputs
for stage in cuda_pairs support_cuda recall_quality_cuda transform_cuda \
  pca_cuda knn_sensitivity_cuda components_cuda longrun_cuda_1 \
  comparators_cuda gpu_done; do
  run_stage "$stage"
done
[[ -f "$JSS_CAMPAIGN_DIR/gpu_done" ]]
[[ ! -f "$JSS_CAMPAIGN_DIR/cpu_done" ]]
! grep -q 'controller_clustering_cuda' "$JSS_LEDGER"

for stage in affinity_scaling support_cpu recall_quality_cpu transform_cpu \
  landmark_cpu pca_cpu_1 pca_cpu_3 pca_accuracy_cpu \
  clustering_precompute clustering_cpu knn_sensitivity_cpu components_cpu \
  longrun_cpu_1 longrun_cpu_2 longrun_cpu_3 longrun_final_cpu \
  longrun_threads longrun_python timing_cpu comparators_cpu cpu_done; do
  run_stage "$stage"
done
[[ -f "$JSS_CAMPAIGN_DIR/cpu_done" ]]
[[ "$(grep -c 'controller_clustering_cuda' "$JSS_LEDGER")" -eq 1 ]]

python3 - "$JSS_LEDGER" <<'PY'
import csv
import sys

with open(sys.argv[1], newline="") as handle:
    rows = list(csv.DictReader(handle, delimiter="\t"))
workers = {row["job_id"]: row["stage"] for row in rows
           if row["role"] == "worker"}
bundles = {
    "support_cuda": ("run_support_cuda.sh", "0-10%5"),
    "transform_cuda": ("run_transform_landmark_cuda_bundle.sh", "0-10%5"),
    "pca_cuda": ("run_pca_accuracy_cuda_bundle.sh", "0-10%5"),
    "longrun_cuda_1": ("run_tsne_longrun_cuda_bundle.sh", "0-3%4"),
}
for stage, (script, array) in bundles.items():
    matches = [row for row in rows if row["role"] == "worker"
               and row["stage"] == stage]
    assert len(matches) == 1, stage
    assert matches[0]["script"].endswith(script), stage
    assert matches[0]["array"] == array, stage
assert not {"landmark_cuda", "pca_accuracy_cuda", "longrun_cuda_2",
            "longrun_cuda_3", "longrun_final_cuda", "timing_cuda"} & {
                row["stage"] for row in rows
            }
cpu = {"affinity_scaling", "support_cpu", "recall_quality_cpu",
       "transform_cpu", "landmark_cpu", "pca_cpu_1", "pca_cpu_3",
       "pca_accuracy_cpu", "clustering_precompute", "clustering_cpu",
       "knn_sensitivity_cpu", "components_cpu", "longrun_cpu_1",
       "longrun_cpu_2", "longrun_cpu_3", "longrun_final_cpu",
       "longrun_threads", "longrun_python", "timing_cpu",
       "comparators_cpu"}
gpu = {"cuda_pairs", "support_cuda", "recall_quality_cuda",
       "transform_cuda", "pca_cuda", "knn_sensitivity_cuda",
       "components_cuda", "longrun_cuda_1", "comparators_cuda"}
for row in rows:
    if row["role"] != "controller":
        continue
    target = row["label"].removeprefix("controller_")
    if target not in cpu | gpu:
        continue
    ids = row["dependency"].removeprefix("afterany:").split(":")
    sources = {workers[job_id] for job_id in ids if job_id in workers}
    if target in cpu:
        assert not sources & gpu, (target, sources)
    else:
        assert not sources & cpu, (target, sources)
forks = [row for row in rows if row["label"] in
         {"controller_affinity_scaling", "controller_cuda_pairs"}]
assert len(forks) == 2
assert forks[0]["dependency"] == forks[1]["dependency"]
PY

export INCLUDE_NOMAD=TRUE
run_stage full_pairs
python3 - "$JSS_LEDGER" <<'PY'
import csv
import sys

with open(sys.argv[1], newline="") as handle:
    rows = list(csv.DictReader(handle, delimiter="\t"))
pair = [row for row in rows if row["label"] == "full_pairs"]
assert len(pair) == 1
assert pair[0]["array"] == "0-18%2"
assert not any("full_nomad" in row["label"] for row in rows)
next_stage = [row for row in rows if row["label"] ==
              "controller_full_quality"]
assert len(next_stage) == 1
assert next_stage[0]["dependency"] == "afterany:" + pair[0]["job_id"]
PY
unset INCLUDE_NOMAD
export JSS_CAMPAIGN_ID=test_without_nomad
export JSS_CAMPAIGN_DIR="$TEST_ROOT/campaign_without_nomad"
export JSS_LEDGER="$JSS_CAMPAIGN_DIR/jobs.tsv"
run_stage full_pairs
python3 - "$JSS_LEDGER" <<'PY'
import csv
import sys
with open(sys.argv[1], newline="") as handle:
    rows = list(csv.DictReader(handle, delimiter="\t"))
pair = [row for row in rows if row["label"] == "full_pairs"]
assert [row["array"] for row in pair] == ["0-16%2"]
PY

mkdir -p "$TEST_ROOT/mock_suite/common"
cat > "$TEST_ROOT/mock_suite/common/run_array_task.sh" <<'EOF'
#!/usr/bin/env bash
printf '%s\t%s\t%s\t%s\t%s\n' "$1" "$2" \
  "$SLURM_ARRAY_TASK_ID" "${LANDMARK_FRACTION:-}" \
  "${TIMING_REPS:-}" >> "$JSS_BUNDLE_CALLS"
if [[ "$1" == "${JSS_FAIL_MODE:-}" && \
      "$SLURM_ARRAY_TASK_ID" == "${JSS_FAIL_TASK:-}" ]]; then
  exit 7
fi
EOF
export SUITE="$TEST_ROOT/mock_suite"
export SLURM_JOB_ID=555
export JSS_BUNDLE_CALLS="$TEST_ROOT/bundle_calls.tsv"
BUNDLE="$(dirname "$CONTROLLER")/run_bundled_cuda.sh"
SLURM_ARRAY_TASK_ID=7 bash "$BUNDLE" support \
  > "$TEST_ROOT/support_bundle.log"
[[ "$(wc -l < "$JSS_BUNDLE_CALLS")" -eq 2 ]]
grep -q $'^support\tcuda\t14\t' "$JSS_BUNDLE_CALLS"
grep -q $'^support\tcuda\t15\t' "$JSS_BUNDLE_CALLS"
: > "$JSS_BUNDLE_CALLS"
SLURM_ARRAY_TASK_ID=0 bash "$BUNDLE" pca_accuracy \
  > "$TEST_ROOT/pca_bundle.log"
[[ "$(wc -l < "$JSS_BUNDLE_CALLS")" -eq 4 ]]
[[ "$(grep -c $'^pca_accuracy\tcuda\t' "$JSS_BUNDLE_CALLS")" -eq 2 ]]
: > "$JSS_BUNDLE_CALLS"
SLURM_ARRAY_TASK_ID=3 bash "$BUNDLE" tsne_longrun \
  > "$TEST_ROOT/longrun_bundle.log"
[[ "$(wc -l < "$JSS_BUNDLE_CALLS")" -eq 21 ]]
grep -q $'^longrun\tcuda\t54\t' "$JSS_BUNDLE_CALLS"
grep -q $'^longrun\tcuda\t71\t' "$JSS_BUNDLE_CALLS"
grep -q $'^longrun_final\tcuda\t7\t' "$JSS_BUNDLE_CALLS"
grep -q $'^longrun_timing\tcuda\t3\t\t10$' "$JSS_BUNDLE_CALLS"
: > "$JSS_BUNDLE_CALLS"
export JSS_FAIL_MODE=landmark_reconstruction
export JSS_FAIL_TASK=0
if SLURM_ARRAY_TASK_ID=0 bash "$BUNDLE" transform_landmark \
    > "$TEST_ROOT/transform_bundle.log" 2>&1; then
  echo 'Bundled CUDA runner did not report a failed subrun.' >&2
  exit 1
fi
[[ "$(wc -l < "$JSS_BUNDLE_CALLS")" -eq 4 ]]
grep -q $'^transform\tcuda\t1\t' "$JSS_BUNDLE_CALLS"
grep -q $'^landmark_reconstruction\tcuda\t1\t0.2\t' \
  "$JSS_BUNDLE_CALLS"
grep -q ',landmark_reconstruction,0,failed,7,' \
  "$OUTPUT_ROOT/scheduler_status/bundles/transform_landmark/555_0.csv"

cat > "$TEST_ROOT/mock_suite/common/run_comparator_task.sh" <<'EOF'
#!/usr/bin/env bash
printf '%s\t%s\t%s\n' "$1" "$COMPARATOR_TASK_ID" \
  "$FULL_CUDA_PAIR" >> "$JSS_PAIR_CALLS"
if [[ "${JSS_FAIL_PAIR:-FALSE}" == TRUE && \
      "$1" == python_cuda && "$COMPARATOR_TASK_ID" == 14 ]]; then
  exit 7
fi
EOF
export JSS_PAIR_CALLS="$TEST_ROOT/pair_calls.tsv"
export JSS_FAIL_PAIR=TRUE
export INCLUDE_NOMAD=TRUE
PAIR="$(dirname "$CONTROLLER")/run_full_cuda_pair.sh"
if SLURM_ARRAY_TASK_ID=0 bash "$PAIR" \
    > "$TEST_ROOT/full_pair.log" 2>&1; then
  echo 'Full CUDA bundle did not report a failed method.' >&2
  exit 1
fi
[[ "$(wc -l < "$JSS_PAIR_CALLS")" -eq 5 ]]
grep -q $'^r_cuda\t14\tTRUE$' "$JSS_PAIR_CALLS"
grep -q $'^python_cuda\t14\tTRUE$' "$JSS_PAIR_CALLS"
grep -q $'^r_cuda\t15\tTRUE$' "$JSS_PAIR_CALLS"
grep -q $'^python_cuda\t15\tTRUE$' "$JSS_PAIR_CALLS"
grep -q $'^python_nomad\t7\tTRUE$' "$JSS_PAIR_CALLS"
grep -q ',python_cuda,tsne,14,failed,7,' \
  "$OUTPUT_ROOT/scheduler_status/full_cuda_pairs/555_0.csv"
export JSS_FAIL_PAIR=FALSE
: > "$JSS_PAIR_CALLS"
for array_id in {0..18}; do
  SLURM_ARRAY_TASK_ID="$array_id" bash "$PAIR" \
    >> "$TEST_ROOT/full_pair_coverage.log"
done
python3 - "$JSS_PAIR_CALLS" <<'PY'
import collections
import csv
import sys

with open(sys.argv[1], newline="") as handle:
    rows = list(csv.reader(handle, delimiter="\t"))
assert len(rows) == 55
actual = collections.Counter((mode, int(task)) for mode, task, flag in rows)
assert all(flag == "TRUE" for _, _, flag in rows)
expected = collections.Counter((mode, task)
                               for task in range(22)
                               for mode in ("r_cuda", "python_cuda"))
expected.update(("python_nomad", task) for task in range(11))
assert actual == expected
PY
unset INCLUDE_NOMAD
: > "$JSS_PAIR_CALLS"
for array_id in {0..16}; do
  SLURM_ARRAY_TASK_ID="$array_id" bash "$PAIR" \
    >> "$TEST_ROOT/full_pair_coverage.log"
done
[[ "$(wc -l < "$JSS_PAIR_CALLS")" -eq 44 ]]
echo 'Campaign CPU/CUDA schedule: PASS'
