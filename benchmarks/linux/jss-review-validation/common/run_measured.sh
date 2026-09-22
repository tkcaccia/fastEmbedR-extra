#!/usr/bin/env bash

set -u

if [[ $# -lt 4 ]]; then
  echo "usage: run_measured.sh BACKEND OUTPUT_PREFIX -- COMMAND ..." >&2
  exit 2
fi

BACKEND="$1"
PREFIX="$2"
shift 2
[[ "$1" == "--" ]] || { echo "missing -- separator" >&2; exit 2; }
shift

mkdir -p "$(dirname "$PREFIX")"
TIME_FILE="${PREFIX}.time.txt"
GPU_FILE="${PREFIX}.gpu_memory.csv"
EXIT_FILE="${PREFIX}.exit_status"
BASELINE=0
MONITOR_PID=""

cleanup() {
  if [[ -n "$MONITOR_PID" ]]; then
    kill "$MONITOR_PID" 2>/dev/null || true
    wait "$MONITOR_PID" 2>/dev/null || true
  fi
}
trap cleanup EXIT INT TERM

if [[ "$BACKEND" == "cuda" ]] && command -v nvidia-smi >/dev/null 2>&1; then
  BASELINE="$(nvidia-smi --query-gpu=memory.used --format=csv,noheader,nounits \
    | head -n 1 | tr -d ' ')"
  echo 'timestamp_utc,memory_used_mib,baseline_mib,incremental_mib' > "$GPU_FILE"
  (
    while true; do
      USED="$(nvidia-smi --query-gpu=memory.used \
        --format=csv,noheader,nounits 2>/dev/null | head -n 1 | tr -d ' ')"
      if [[ "$USED" =~ ^[0-9]+$ ]]; then
        printf '%s,%s,%s,%s\n' \
          "$(date -u +%Y-%m-%dT%H:%M:%SZ)" \
          "$USED" "$BASELINE" "$((USED - BASELINE))" >> "$GPU_FILE"
      fi
      sleep 0.2
    done
  ) &
  MONITOR_PID=$!
fi

set +e
/usr/bin/time -v -o "$TIME_FILE" "$@"
STATUS=$?
set -e
printf '%s\n' "$STATUS" > "$EXIT_FILE"
exit "$STATUS"
