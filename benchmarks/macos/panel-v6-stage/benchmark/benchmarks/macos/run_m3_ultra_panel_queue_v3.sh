#!/usr/bin/env bash

# Serial, fail-closed Mac panel controller. No retries or remote dependency.
set -euo pipefail

stefano=/Users/silvanopiazza/Documents/Stefano
campaign_root="${FASTEMBEDR_MAC_ROOT:-${stefano}/fastEmbedR-mac-20261031}"
queue_id="${1:-}"
[[ "${queue_id}" =~ ^[A-Za-z0-9_.-]+$ &&
   "${queue_id}" != . && "${queue_id}" != .. ]] || {
  echo "Give a unique queue identifier." >&2
  exit 64
}
script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)"
benchmark_root="$(cd "${script_dir}/../.." && pwd -P)"
runner="${script_dir}/run_m3_ultra_panel_v3.sh"
datasets=(
  Macosko2015_retina MNIST FashionMNIST
  TabulaMuris mass41 flow18 FlowRepository_FR-FCM-ZYRM_files
  imagenet
)
if [[ "$(uname -s)" != Darwin ]]; then
  echo "This queue runs only on the Mac." >&2
  exit 64
fi
campaign_root="$(cd "${campaign_root}" && pwd -P)"
for source_dir in "${campaign_root}" "${benchmark_root}"; do
  case "${source_dir}" in
    "${stefano}"/*) ;;
    *) echo "Mac campaign and sources must be under Stefano." >&2
       exit 64 ;;
  esac
done
package_root="${campaign_root}/candidates/mac-benchmark-integration-20261102-v3/source"
[[ -d "${package_root}" && -f "${runner}" ]] || {
  echo "Missing clean package source or panel runner." >&2; exit 1;
}
if [[ "${RUN:-FALSE}" != TRUE ]]; then
  echo "DRY RUN: queue=${queue_id}"
  printf 'dataset=%s\n' "${datasets[@]}"
  echo "Set RUN=TRUE for the serial Mac campaign."
  exit 0
fi
[[ -z "$(git -C "${package_root}" status --short)" ]] || {
  echo "Package source is dirty." >&2; exit 1;
}
if pgrep -x 'R|Rscript' >/dev/null 2>&1; then
  echo "Another R job is active; exclusive timing is unavailable." >&2
  exit 1
fi
queue_root="${campaign_root}/results/m3-ultra-panel-v1-queue/${queue_id}"
[[ ! -e "${queue_root}" ]] || {
  echo "Queue identifier already exists: ${queue_root}" >&2; exit 1;
}
mkdir -p "${queue_root}"
resolved_queue="$(cd "${queue_root}" && pwd -P)"
case "${resolved_queue}" in
  "${stefano}"/*) ;;
  *) echo "Queue path escapes Stefano." >&2; exit 1 ;;
esac
sources=(
  "${runner}" "$0"
  "${script_dir}/preflight_m3_ultra_panel_v1.py"
  "${script_dir}/M3_ULTRA_LOCAL_INPUTS_SHA256_20261101.txt"
  "${script_dir}/audit_m3_ultra_panel_v1.py"
  "${script_dir}/audit_m3_ultra_panel_quality_v2.R"
  "${script_dir}/mac_global_knn_recall_v1.R"
  "${script_dir}/smoke_m3_ultra_routes_v3.R"
  "${script_dir}/mac_memory_guard_v1.py"
  "${script_dir}/derive_m3_ultra_selector_v2.py"
  "${benchmark_root}/benchmarks/shared/benchmark_reviewer_validation.R"
  "${benchmark_root}/benchmarks/shared/benchmark_worker_monitor.sh"
  "${benchmark_root}/benchmarks/shared/publication_metrics.R"
)
shasum -a 256 "${sources[@]}" > "${queue_root}/sources.lock"
git -C "${package_root}" rev-parse HEAD > "${queue_root}/package_commit.lock"
git -C "${benchmark_root}" rev-parse HEAD \
  > "${queue_root}/benchmark_commit.lock"
printf 'dataset,status,run_id,audit_dir\n' > "${queue_root}/status.csv"
python3 - "${campaign_root}" "${queue_root}" <<'PY'
import csv
import json
import sys
from pathlib import Path

campaign, queue = (Path(arg) for arg in sys.argv[1:])
prior = campaign / "results/m3-ultra-panel-v1"
recovery = campaign / "results/recovery/USPS_quality_v2"
package = (queue / "package_commit.lock").read_text().strip()
benchmark = (queue / "benchmark_commit.lock").read_text().strip()
with (queue / "status.csv").open("a", newline="") as stream:
    writer = csv.writer(stream, lineterminator="\n")
    for dataset in ("COIL20", "MetRef", "USPS"):
        run_id = f"panel_v5b_20261102_{dataset}"
        root = prior / run_id
        audit = recovery if dataset == "USPS" else root
        identity = dict(line.split("=", 1) for line in
                        (root / "source_identity.txt").read_text().splitlines()
                        if "=" in line)
        inputs = json.loads((root / "input_postflight.json").read_text())
        panel = json.loads((root / "panel_audit.json").read_text())
        with (root / "benchmark_runs.csv").open(newline="") as source:
            runs = list(csv.DictReader(source))
        with (audit / "quality_speed_summary.csv").open(newline="") as source:
            quality = list(csv.DictReader(source))
        with (audit / "global_knn_recall_audit.csv").open(newline="") as source:
            recall = list(csv.DictReader(source))
        if (identity.get("package_commit") != package or
                identity.get("benchmark_commit") != benchmark or
                inputs.get("status") != "inputs_verified" or
                panel.get("execution_status") != "passed" or
                len(runs) != 147 or
                any(row.get("status") != "success" for row in runs) or
                len(quality) != 7 or len(recall) != 63):
            raise SystemExit(f"Cannot reuse audited run: {dataset}")
        writer.writerow((dataset, "success", run_id,
                         str(audit) if dataset == "USPS" else ""))
PY

for dataset in "${datasets[@]}"; do
  if pgrep -x 'R|Rscript' >/dev/null 2>&1; then
    echo "Another R job appeared before ${dataset}." >&2
    printf '%s,blocked,,\n' "${dataset}" >> "${queue_root}/status.csv"
    exit 1
  fi
  shasum -a 256 "${sources[@]}" > "${queue_root}/sources.current"
  cmp "${queue_root}/sources.lock" "${queue_root}/sources.current" || {
    printf '%s,source_changed,,\n' "${dataset}" \
      >> "${queue_root}/status.csv"
    exit 1
  }
  if [[ "$(git -C "${package_root}" rev-parse HEAD)" != \
        "$(cat "${queue_root}/package_commit.lock")" ||
        "$(git -C "${benchmark_root}" rev-parse HEAD)" != \
        "$(cat "${queue_root}/benchmark_commit.lock")" ||
        -n "$(git -C "${package_root}" status --short)" ]]; then
    printf '%s,source_changed,,\n' "${dataset}" \
      >> "${queue_root}/status.csv"
    exit 1
  fi
  run_id="${queue_id}_${dataset}"
  out_dir="${campaign_root}/results/m3-ultra-panel-v1/${run_id}"
  if RUN=TRUE FASTEMBEDR_RUN_ID="${run_id}" \
      bash "${runner}" "${dataset}" \
      > "${queue_root}/${dataset}.log" 2>&1 &&
      shasum -a 256 "${sources[@]}" \
      > "${queue_root}/sources.current" &&
      cmp "${queue_root}/sources.lock" \
      "${queue_root}/sources.current" &&
      [[ "$(git -C "${package_root}" rev-parse HEAD)" == \
         "$(cat "${queue_root}/package_commit.lock")" ]] &&
      [[ "$(git -C "${benchmark_root}" rev-parse HEAD)" == \
         "$(cat "${queue_root}/benchmark_commit.lock")" ]] &&
      [[ -z "$(git -C "${package_root}" status --short)" ]] &&
      python3 - "${out_dir}" <<'PY'
import csv
import json
import sys
from pathlib import Path

root = Path(sys.argv[1])
input_report = json.loads((root / "input_postflight.json").read_text())
panel = json.loads((root / "panel_audit.json").read_text())
with (root / "quality_speed_summary.csv").open(newline="") as stream:
    quality = list(csv.DictReader(stream))
with (root / "global_knn_recall_audit.csv").open(newline="") as stream:
    recall = list(csv.DictReader(stream))
if (input_report["status"] != "inputs_verified" or
        panel["execution_status"] != "passed" or len(quality) != 7 or
        len(recall) != 63):
    raise SystemExit("Dataset audit or source postflight failed")
PY
  then
    printf '%s,success,%s,\n' "${dataset}" "${run_id}" \
      >> "${queue_root}/status.csv"
  else
    printf '%s,failed,%s,\n' "${dataset}" "${run_id}" \
      >> "${queue_root}/status.csv"
    echo "Queue stopped at ${dataset}; inspect its retained evidence." >&2
    exit 1
  fi
done
python3 "${script_dir}/derive_m3_ultra_selector_v2.py" \
  "${queue_root}" "${campaign_root}" \
  > "${queue_root}/selector.log" 2>&1
printf 'queue,success,%s,\n' "${queue_id}" \
  >> "${queue_root}/status.csv"
