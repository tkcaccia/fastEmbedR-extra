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

gnu_time_bin() {
  local requested="${FASTEMBEDR_TIME_BIN:-auto}"
  local candidate
  [[ "$requested" == "disable" ]] && return 1
  if [[ "$requested" != "auto" ]]; then
    [[ -x "$requested" ]] || return 1
    "$requested" -v -o /dev/null true 2>/dev/null || return 1
    printf '%s\n' "$requested"
    return 0
  fi
  for candidate in /usr/bin/time /bin/time; do
    [[ -x "$candidate" ]] || continue
    "$candidate" -v -o /dev/null true 2>/dev/null || continue
    printf '%s\n' "$candidate"
    return 0
  done
  candidate="$(command -v gtime 2>/dev/null || true)"
  [[ -n "$candidate" ]] || return 1
  "$candidate" -v -o /dev/null true 2>/dev/null || return 1
  printf '%s\n' "$candidate"
}

slurm_max_rss() {
  local job_id="${SLURM_JOB_ID:-}"
  [[ -n "$job_id" ]] || return 1
  command -v sstat >/dev/null 2>&1 || return 1
  sstat -j "${job_id}.batch" --noheader --parsable2 \
    --format=MaxRSS 2>/dev/null |
    awk -F '|' 'NF && $1 != "" { print $1; exit }'
}

clock_nanoseconds() {
  local value
  value="$(date +%s%N)"
  if [[ "$value" =~ ^[0-9]+$ ]]; then
    printf '%s\n' "$value"
    return 0
  fi
  if command -v perl >/dev/null 2>&1; then
    perl -MTime::HiRes=time -e 'printf "%.0f\n", time() * 1000000000'
    return 0
  fi
  printf '%s000000000\n' "$(date +%s)"
}

write_fallback_measurement() {
  local start_ns="$1"
  local end_ns="$2"
  local raw_rss="$3"
  local source="$4"
  local elapsed
  elapsed="$(awk -v a="$start_ns" -v b="$end_ns" \
    'BEGIN { printf "%.6f", (b - a) / 1000000000 }')"
  {
    printf 'Measurement source: %s\n' "$source"
    printf 'Wall clock seconds: %s\n' "$elapsed"
    printf 'Slurm maximum resident set size: %s\n' "${raw_rss:-NA}"
  } > "$TIME_FILE"
}

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

TIME_BIN="$(gnu_time_bin || true)"
set +e
if [[ -n "$TIME_BIN" ]]; then
  "$TIME_BIN" -v -o "$TIME_FILE" "$@"
  STATUS=$?
  printf 'Measurement source: gnu_time\n' >> "$TIME_FILE"
else
  START_NS="$(clock_nanoseconds)"
  "$@"
  STATUS=$?
  END_NS="$(clock_nanoseconds)"
  RAW_RSS="$(slurm_max_rss || true)"
  SOURCE=unavailable
  [[ -n "$RAW_RSS" ]] && SOURCE=slurm_sstat
  write_fallback_measurement "$START_NS" "$END_NS" "$RAW_RSS" "$SOURCE"
fi
set -e
printf '%s\n' "$STATUS" > "$EXIT_FILE"
exit "$STATUS"
