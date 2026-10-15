#!/usr/bin/env bash

set -euo pipefail

SUITE="$(cd "$(dirname "$0")/.." && pwd)"
export SUITE
export JSS_REAL_SHA256SUM="$(command -v sha256sum)"
CONTROLLER="$SUITE/common/run_complete_campaign_controller.sh"
TEST_ROOT="$(mktemp -d)"
trap 'rm -rf "$TEST_ROOT"' EXIT
mkdir -p "$TEST_ROOT/bin"
export PREFLIGHT_ROOT="$TEST_ROOT/preflight"

cat > "$TEST_ROOT/bin/sbatch" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
id="$(< "$JSS_FAKE_COUNTER")"
id=$((id + 1))
printf '%s\n' "$id" > "$JSS_FAKE_COUNTER"
if [[ -n "${JSS_FAKE_SUBMISSIONS:-}" ]]; then
  printf '%s\n' "$*" >> "$JSS_FAKE_SUBMISSIONS"
fi
printf '%s\n' "$id"
EOF
cat > "$TEST_ROOT/bin/sacct" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
if [[ "${JSS_FAKE_PREFLIGHT_FAIL:-FALSE}" == TRUE ]]; then
  printf 'FAILED|1:0\n'
  exit 0
fi
if [[ " $* " == *' State,ExitCode '* ]]; then
  printf 'COMPLETED|0:0\n'
  exit 0
fi
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
cat > "$TEST_ROOT/bin/sha256sum" <<'EOF'
#!/usr/bin/env bash
if [[ $# -eq 1 && "$1" == "${JSS_FAKE_IMAGE:-}" ]]; then
  printf '%s  %s\n' "$JSS_FAKE_IMAGE_SHA" "$1"
else
  "$JSS_REAL_SHA256SUM" "$@"
fi
EOF
chmod +x "$TEST_ROOT/bin/"*
printf '1000\n' > "$TEST_ROOT/counter"

export PATH="$TEST_ROOT/bin:$PATH"
source "$SUITE/common/campaign_submit.sh"
unset METHOD_TIMEOUT_SECONDS
campaign_require_method_timeout
[[ "$METHOD_TIMEOUT_SECONDS" == 7200 ]]
if METHOD_TIMEOUT_SECONDS=600 campaign_require_method_timeout \
    > "$TEST_ROOT/timeout_rejection.log" 2>&1; then
  echo 'A stale ten-minute method limit was accepted.' >&2
  exit 1
fi
grep -q 'requires METHOD_TIMEOUT_SECONDS=7200' \
  "$TEST_ROOT/timeout_rejection.log"
export JSS_FAKE_COUNTER="$TEST_ROOT/counter"
export BASE_DIR="$TEST_ROOT"
export IMAGE="$TEST_ROOT/image.sif"
export INPUT_ROOT="$TEST_ROOT/input"
export OUTPUT_ROOT="$TEST_ROOT/results"
export EXPECTED_VERSION=0.1
export FASTEMBEDR_IMAGE_SHA256=test
export FASTEMBEDR_DLL_SHA256=test
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
run_stage file_backed
run_stage file_backed_audit
run_stage file_backed_done
for stage in comparators_cuda cuda_pairs support_cuda support_sweep_cuda \
  recall_quality_cuda \
  transform_cuda landmark_memory_cuda pca_cuda \
  knn_sensitivity_cuda components_cuda \
  longrun_cuda_1 gpu_done; do
  run_stage "$stage"
done
[[ -f "$JSS_CAMPAIGN_DIR/gpu_done" ]]
[[ -f "$JSS_CAMPAIGN_DIR/file_backed_done" ]]
[[ ! -f "$JSS_CAMPAIGN_DIR/cpu_done" ]]
! grep -q 'controller_clustering_cuda' "$JSS_LEDGER"

for stage in affinity_scaling scaling support_cpu support_sweep_cpu \
  recall_quality_cpu transform_cpu \
  landmark_cpu landmark_memory_cpu pca_cpu_1 pca_cpu_3 pca_accuracy_cpu \
  clustering_precompute clustering_cpu clustering_scale_cpu \
  knn_sensitivity_cpu components_cpu \
  longrun_cpu_1 longrun_final_cpu \
  longrun_threads longrun_python timing_cpu comparators_cpu cpu_done; do
  run_stage "$stage"
done
[[ -f "$JSS_CAMPAIGN_DIR/cpu_done" ]]
[[ "$(grep -c 'controller_clustering_cuda' "$JSS_LEDGER")" -eq 1 ]]
run_stage clustering_cuda
run_stage clustering_scale_cuda

python3 - "$JSS_LEDGER" <<'PY'
import csv
import sys

with open(sys.argv[1], newline="") as handle:
    rows = list(csv.DictReader(handle, delimiter="\t"))
workers = {row["job_id"]: row["stage"] for row in rows
           if row["role"] == "worker"}
scaling = [row for row in rows if row["label"] == "scaling"]
assert len(scaling) == 1
assert scaling[0]["stage"] == "scaling"
assert scaling[0]["array"] == "0-3%4"
pca = [row for row in rows if row["label"] == "comparators_cuda_pca"]
cuda = [row for row in rows if row["label"] == "controller_cuda_pairs"]
assert len(pca) == len(cuda) == 1
assert cuda[0]["dependency"] == "afterany:" + pca[0]["job_id"]
bundles = {
    "support_cuda": ("run_support_cuda.sh", "0-3%4"),
    "support_sweep_cuda": ("run_support_sweep_cuda.sh", "0-3%4"),
    "landmark_memory_cuda": ("run_landmark_memory_cuda.sh", "0-10%4"),
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
cpu = {"affinity_scaling", "scaling", "support_cpu", "support_sweep_cpu",
       "recall_quality_cpu",
       "transform_cpu", "landmark_cpu", "landmark_memory_cpu",
       "pca_cpu_1", "pca_cpu_3",
       "pca_accuracy_cpu", "clustering_precompute", "clustering_cpu",
       "clustering_scale_cpu",
       "knn_sensitivity_cpu", "components_cpu", "longrun_cpu_1",
       "longrun_final_cpu",
       "longrun_threads", "longrun_python", "timing_cpu",
       "comparators_cpu"}
gpu = {"cuda_pairs", "support_cuda", "support_sweep_cuda",
       "recall_quality_cuda",
       "transform_cuda", "landmark_memory_cuda", "pca_cuda",
       "knn_sensitivity_cuda",
       "components_cuda", "longrun_cuda_1", "comparators_cuda",
       "clustering_cuda", "clustering_scale_cuda"}
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
         {"controller_affinity_scaling", "controller_comparators_cuda",
          "controller_file_backed"}]
assert len(forks) == 3
assert len({row["dependency"] for row in forks}) == 1
assert forks[0]["dependency"].startswith("afterany:")
file_backed = [row for row in rows if row["stage"] == "file_backed"
               and row["role"] == "worker"]
assert len(file_backed) == 7
assert {row["label"] for row in file_backed} == {
    "file_backed_matched", "file_backed_scaling",
    "file_backed_boundary", "file_backed_full",
    "file_backed_multi", "file_backed_recovery",
    "file_backed_recovery_cuda"}
longrun = [row for row in rows if row["label"] == "longrun_cpu_1"]
assert len(longrun) == 1
assert longrun[0]["array"] == "0-71%24"
next_stage = [row for row in rows if row["label"] ==
              "controller_longrun_final_cpu"]
assert len(next_stage) == 1
assert next_stage[0]["dependency"] == "afterany:" + longrun[0]["job_id"]
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
assert pair[0]["array"] == "0-20%2"
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
assert [row["array"] for row in pair] == ["0-18%2"]
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
cat > "$SUITE/common/run_bundled_cuda.sh" <<'EOF'
#!/usr/bin/env bash
printf '%s\n' "$SUITE" > "$JSS_VERSIONED_SUITE_CALL"
EOF
export JSS_VERSIONED_SUITE_CALL="$TEST_ROOT/versioned_suite_call.txt"
SLURM_ARRAY_TASK_ID=0 bash \
  "$(dirname "$CONTROLLER")/../slurm/run_support_cuda.sh"
[[ "$(< "$JSS_VERSIONED_SUITE_CALL")" == "$SUITE" ]]
BUNDLE="$(dirname "$CONTROLLER")/run_bundled_cuda.sh"
SLURM_ARRAY_TASK_ID=3 bash "$BUNDLE" support \
  > "$TEST_ROOT/support_bundle.log"
[[ "$(wc -l < "$JSS_BUNDLE_CALLS")" -eq 2 ]]
grep -q $'^support\tcuda\t6\t' "$JSS_BUNDLE_CALLS"
grep -q $'^support\tcuda\t7\t' "$JSS_BUNDLE_CALLS"
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
[[ "$(wc -l < "$JSS_PAIR_CALLS")" -eq 6 ]]
grep -q $'^r_cuda\t21\tTRUE$' "$JSS_PAIR_CALLS"
grep -q $'^python_cuda\t14\tTRUE$' "$JSS_PAIR_CALLS"
grep -q $'^r_cuda\t22\tTRUE$' "$JSS_PAIR_CALLS"
grep -q $'^python_cuda\t15\tTRUE$' "$JSS_PAIR_CALLS"
grep -q $'^r_cuda\t23\tTRUE$' "$JSS_PAIR_CALLS"
grep -q $'^python_nomad\t7\tTRUE$' "$JSS_PAIR_CALLS"
grep -q ',python_cuda,tsne,14,failed,7,' \
  "$OUTPUT_ROOT/scheduler_status/full_cuda_pairs/555_0.csv"
export JSS_FAIL_PAIR=FALSE
: > "$JSS_PAIR_CALLS"
for array_id in {0..20}; do
  SLURM_ARRAY_TASK_ID="$array_id" bash "$PAIR" \
    >> "$TEST_ROOT/full_pair_coverage.log"
done
python3 - "$JSS_PAIR_CALLS" <<'PY'
import collections
import csv
import sys

with open(sys.argv[1], newline="") as handle:
    rows = list(csv.reader(handle, delimiter="\t"))
assert len(rows) == 66
actual = collections.Counter((mode, int(task)) for mode, task, flag in rows)
assert all(flag == "TRUE" for _, _, flag in rows)
expected = collections.Counter(("r_cuda", task) for task in range(33))
expected.update(("python_cuda", task) for task in range(22))
expected.update(("python_nomad", task) for task in range(11))
assert actual == expected
PY
unset INCLUDE_NOMAD
: > "$JSS_PAIR_CALLS"
for array_id in {0..18}; do
  SLURM_ARRAY_TASK_ID="$array_id" bash "$PAIR" \
    >> "$TEST_ROOT/full_pair_coverage.log"
done
[[ "$(wc -l < "$JSS_PAIR_CALLS")" -eq 55 ]]

cat > "$TEST_ROOT/mock_suite/common/container_runtime.sh" <<'EOF'
FASTEMBEDR_CONTAINER_R_ENV=(--env MOCK=1)
FASTEMBEDR_RSCRIPT=Rscript
EOF
cat > "$TEST_ROOT/bin/apptainer" <<'EOF'
#!/usr/bin/env bash
printf '%s\n' "$*" >> "$JSS_PLOT_CALLS"
EOF
chmod +x "$TEST_ROOT/bin/apptainer"
export JSS_PLOT_CALLS="$TEST_ROOT/plot_calls.txt"
export JSS_FAIL_PAIR=FALSE
export FULL_CUDA_PAIR=FALSE
: > "$JSS_PAIR_CALLS"
SLURM_ARRAY_TASK_ID=1 bash "$(dirname "$CONTROLLER")/run_cuda_pair.sh" \
  > "$TEST_ROOT/live_pair.log"
[[ "$(wc -l < "$JSS_PAIR_CALLS")" -eq 5 ]]
grep -q $'^r_cuda\t5\tFALSE$' "$JSS_PAIR_CALLS"
grep -q $'^python_cuda\t4\tFALSE$' "$JSS_PAIR_CALLS"
grep -q $'^r_cuda\t6\tFALSE$' "$JSS_PAIR_CALLS"
grep -q $'^r_cuda\t7\tFALSE$' "$JSS_PAIR_CALLS"
grep -q $'^python_cuda\t5\tFALSE$' "$JSS_PAIR_CALLS"
[[ "$(wc -l < "$JSS_PLOT_CALLS")" -eq 2 ]]

LAUNCH_BASE="$TEST_ROOT/launch_base"
mkdir -p "$LAUNCH_BASE"
touch "$LAUNCH_BASE/image.sif"
export JSS_FAKE_IMAGE="$LAUNCH_BASE/image.sif"
export JSS_FAKE_IMAGE_SHA
JSS_FAKE_IMAGE_SHA="$(awk -F, 'NR == 2 {print $1}' \
  "$(dirname "$CONTROLLER")/../common/image_source_identity.csv")"
SUBMISSIONS="$TEST_ROOT/preflight_submissions.txt"
if METHOD_TIMEOUT_SECONDS=600 JSS_FAKE_SUBMISSIONS="$SUBMISSIONS" \
    BASE_DIR="$LAUNCH_BASE" SUITE="$(dirname "$CONTROLLER")/.." \
    IMAGE="$LAUNCH_BASE/image.sif" \
    bash "$(dirname "$CONTROLLER")/../submit_after_new_image.sh" \
    > "$TEST_ROOT/stale_timeout_launch.log" 2>&1; then
  echo 'A stale timeout launched preflight jobs.' >&2
  exit 1
fi
[[ ! -e "$SUBMISSIONS" ]]
JSS_FAKE_SUBMISSIONS="$SUBMISSIONS" BASE_DIR="$LAUNCH_BASE" \
  SUITE="$(dirname "$CONTROLLER")/.." \
  IMAGE="$LAUNCH_BASE/image.sif" \
  CAMPAIGN_MODE=full_cuda INCLUDE_NOMAD=TRUE \
  bash "$(dirname "$CONTROLLER")/../submit_after_new_image.sh" \
  > "$TEST_ROOT/handoff_launch.log"
[[ "$(wc -l < "$SUBMISSIONS")" -eq 3 ]]
grep -q 'CAMPAIGN_MODE=full_cuda' "$SUBMISSIONS"
grep -q 'INCLUDE_NOMAD=TRUE' "$SUBMISSIONS"
grep -q -- '--dependency=afterany:' "$SUBMISSIONS"

AUTO_SUBMISSIONS="$TEST_ROOT/auto_nomad_submissions.txt"
env -u CAMPAIGN_MODE JSS_FAKE_SUBMISSIONS="$AUTO_SUBMISSIONS" \
  BASE_DIR="$LAUNCH_BASE" \
  SUITE="$(dirname "$CONTROLLER")/.." \
  IMAGE="$LAUNCH_BASE/image.sif" INCLUDE_NOMAD=TRUE \
  bash "$(dirname "$CONTROLLER")/../submit_after_new_image.sh" \
  > "$TEST_ROOT/auto_nomad_launch.log"
[[ "$(wc -l < "$AUTO_SUBMISSIONS")" -eq 3 ]]
grep -q 'CAMPAIGN_MODE=full_cuda' "$AUTO_SUBMISSIONS"
COMPLETE_SUBMISSIONS="$TEST_ROOT/complete_submissions.txt"
JSS_FAKE_SUBMISSIONS="$COMPLETE_SUBMISSIONS" BASE_DIR="$LAUNCH_BASE" \
  SUITE="$(dirname "$CONTROLLER")/.." \
  IMAGE="$LAUNCH_BASE/image.sif" INCLUDE_NOMAD=FALSE \
  CAMPAIGN_MODE=complete \
  bash "$(dirname "$CONTROLLER")/../submit_after_new_image.sh" \
  > "$TEST_ROOT/complete_launch.log"
[[ "$(wc -l < "$COMPLETE_SUBMISSIONS")" -eq 3 ]]
grep -q 'CAMPAIGN_MODE=complete' "$COMPLETE_SUBMISSIONS"
grep -q 'INCLUDE_NOMAD=FALSE' "$COMPLETE_SUBMISSIONS"
if JSS_FAKE_SUBMISSIONS="$AUTO_SUBMISSIONS" BASE_DIR="$LAUNCH_BASE" \
    SUITE="$(dirname "$CONTROLLER")/.." \
    IMAGE="$LAUNCH_BASE/image.sif" INCLUDE_NOMAD=TRUE \
    CAMPAIGN_MODE=complete \
    bash "$(dirname "$CONTROLLER")/../submit_after_new_image.sh" \
    > /dev/null 2>&1; then
  echo 'Explicit complete mode accepted NOMAD.' >&2
  exit 1
fi
[[ "$(wc -l < "$AUTO_SUBMISSIONS")" -eq 3 ]]

HANDOFF_SUITE="$TEST_ROOT/handoff_suite"
mkdir -p "$HANDOFF_SUITE"
for name in verify_preflight submit_complete_campaign \
    submit_full_cuda_campaign; do
  printf '#!/usr/bin/env bash\nprintf "%%s\\n" "%s" >> "$JSS_HANDOFF_CALLS"\n' \
    "$name" > "$HANDOFF_SUITE/$name.sh"
done
export JSS_HANDOFF_CALLS="$TEST_ROOT/handoff_calls.txt"
FOLLOW_UP="$(dirname "$CONTROLLER")/../slurm/run_after_image_preflights_cpu1.sh"
BASE_DIR="$LAUNCH_BASE" SUITE="$HANDOFF_SUITE" \
  CPU_PREFLIGHT_JOB=900 CUDA_PREFLIGHT_JOB=901 \
  CAMPAIGN_MODE=full_cuda bash "$FOLLOW_UP"
[[ "$(wc -l < "$JSS_HANDOFF_CALLS")" -eq 2 ]]
grep -q '^verify_preflight$' "$JSS_HANDOFF_CALLS"
grep -q '^submit_full_cuda_campaign$' "$JSS_HANDOFF_CALLS"
: > "$JSS_HANDOFF_CALLS"
if JSS_FAKE_PREFLIGHT_FAIL=TRUE BASE_DIR="$LAUNCH_BASE" \
    SUITE="$HANDOFF_SUITE" CPU_PREFLIGHT_JOB=900 \
    CUDA_PREFLIGHT_JOB=901 CAMPAIGN_MODE=full_cuda \
    bash "$FOLLOW_UP" > /dev/null 2>&1; then
  echo 'Failed preflight launched a campaign.' >&2
  exit 1
fi
[[ ! -s "$JSS_HANDOFF_CALLS" ]]

FAILED_DIR="$TEST_ROOT/failed_launch"
if BASE_DIR="$TEST_ROOT" CAMPAIGN_PARENT="$FAILED_DIR" \
    JSS_CAMPAIGN_ID=test SUITE="$TEST_ROOT/missing_suite" \
    bash "$(dirname "$CONTROLLER")/../submit_complete_campaign.sh" \
    > /dev/null 2>&1; then
  echo 'Invalid launch unexpectedly succeeded.' >&2
  exit 1
fi
grep -q '^status=FAILED$' "$FAILED_DIR/test/launch_status.txt"
grep -q '^phase=resource_contract$' "$FAILED_DIR/test/launch_status.txt"

PCA_WORKER="$TEST_ROOT/benchmark_scripts/fastembedr_jss_review_validation"
mkdir -p "$PCA_WORKER/common"
cat > "$PCA_WORKER/common/run_comparator_task.sh" <<'EOF'
#!/usr/bin/env bash
printf '%s\t%s\n' "$1" "$COMPARATOR_TASK_ID" >> "$JSS_PCA_CALLS"
[[ "$1" != r_cuda ]]
EOF
export JSS_PCA_CALLS="$TEST_ROOT/pca_calls.txt"
if (cd "$TEST_ROOT"; SUITE="$PCA_WORKER" SLURM_ARRAY_TASK_ID=1 bash \
    "$(dirname "$CONTROLLER")/../slurm/run_comparators_cuda_pca.sh" \
    > "$TEST_ROOT/pca_bundle.log" 2>&1); then
  echo 'CUDA PCA bundle hid a failed method.' >&2
  exit 1
fi
[[ "$(cat "$JSS_PCA_CALLS")" == $'r_cuda\t4\npython_cuda\t3' ]]
cat > "$PCA_WORKER/common/run_comparator_task.sh" <<'EOF'
#!/usr/bin/env bash
printf '%s\t%s\n' "$1" "$COMPARATOR_TASK_ID" >> "$JSS_FULL_CALLS"
EOF
export JSS_FULL_CALLS="$TEST_ROOT/full_calls.txt"
FULL_WORKER="$(dirname "$CONTROLLER")/run_full_cuda_pair.sh"
SUITE="$PCA_WORKER" OUTPUT_ROOT="$TEST_ROOT" \
  SLURM_ARRAY_TASK_ID=0 bash "$FULL_WORKER" \
  > "$TEST_ROOT/full_bundle.log"
[[ "$(cat "$JSS_FULL_CALLS")" == \
   $'r_cuda\t21\npython_cuda\t14\nr_cuda\t22\npython_cuda\t15\nr_cuda\t23' ]]
: > "$JSS_FULL_CALLS"
SUITE="$PCA_WORKER" OUTPUT_ROOT="$TEST_ROOT" \
  SLURM_ARRAY_TASK_ID=13 bash "$FULL_WORKER" \
  > "$TEST_ROOT/full_binary.log"
[[ "$(cat "$JSS_FULL_CALLS")" == $'r_cuda\t11' ]]
grep -q 'umap_binary' "$TEST_ROOT/full_binary.log"
: > "$JSS_FULL_CALLS"
SUITE="$PCA_WORKER" OUTPUT_ROOT="$TEST_ROOT" INCLUDE_NOMAD=TRUE \
  SLURM_ARRAY_TASK_ID=14 bash "$FULL_WORKER" \
  > "$TEST_ROOT/full_nomad.log"
[[ "$(cat "$JSS_FULL_CALLS")" == $'python_nomad\t3' ]]
echo 'Campaign CPU/CUDA schedule: PASS'
