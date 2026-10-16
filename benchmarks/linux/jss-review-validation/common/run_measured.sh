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
GPU_IDENTITY_FILE="${PREFIX}.gpu_identity.csv"
GPU_ERROR="${PREFIX}.gpu_monitor.err"
GPU_READY="${PREFIX}.gpu_monitor.ready"
EXIT_FILE="${PREFIX}.exit_status"
declare -A BASELINES=()
declare -A NVML_IDS=()
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

# Slurm physical IDs can be renumbered in the job's CUDA/NVML namespace.
GPU_IDS="${CUDA_VISIBLE_DEVICES:-${SLURM_JOB_GPUS:-}}"
if [[ "${FASTEMBEDR_MONITOR_ALL_GPUS:-FALSE}" != TRUE ]]; then
  GPU_IDS="${GPU_IDS%%,*}"
fi
if [[ "$BACKEND" == "cuda" ]]; then
  command -v nvidia-smi >/dev/null 2>&1 || {
    echo "CUDA memory measurement requires nvidia-smi" >&2
    exit 1
  }
  [[ -n "$GPU_IDS" ]] || {
    echo "CUDA memory measurement needs a visible GPU ID" >&2
    exit 1
  }
  : > "$GPU_ERROR"
  rm -f "$GPU_READY"
  printf 'gpu_id,nvml_id,slurm_physical_id,gpu_uuid\n' \
    > "$GPU_IDENTITY_FILE"
  PHYSICAL_TEXT=${SLURM_JOB_GPUS:-}
  PHYSICAL_IDS=( ${PHYSICAL_TEXT//,/ } )
  GPU_POSITION=0
  for GPU_ID in ${GPU_IDS//,/ }; do
    NVML_ID="$GPU_ID"
    BASELINE="$(nvidia-smi -i "$NVML_ID" \
      --query-gpu=memory.used --format=csv,noheader,nounits \
      2>/dev/null | tr -d '[:space:]')"
    if [[ ! "$BASELINE" =~ ^[0-9]+$ ]]; then
      mapfile -t VISIBLE_NVML < <(nvidia-smi --query-gpu=index \
        --format=csv,noheader,nounits 2>> "$GPU_ERROR")
      if [[ "$GPU_IDS" != *,* && ${#VISIBLE_NVML[@]} -eq 1 ]]; then
        NVML_ID="${VISIBLE_NVML[0]}"
        BASELINE="$(nvidia-smi -i "$NVML_ID" \
          --query-gpu=memory.used --format=csv,noheader,nounits \
          2>> "$GPU_ERROR" | tr -d '[:space:]')"
      fi
    fi
    [[ "$BASELINE" =~ ^[0-9]+$ ]] || {
      echo "Invalid GPU memory baseline for device $GPU_ID" \
        >> "$GPU_ERROR"
      cat "$GPU_ERROR" >&2
      exit 1
    }
    BASELINES["$GPU_ID"]="$BASELINE"
    NVML_IDS["$GPU_ID"]="$NVML_ID"
    GPU_UUID="$(nvidia-smi -i "$NVML_ID" --query-gpu=uuid \
      --format=csv,noheader 2>> "$GPU_ERROR" | tr -d '[:space:]')"
    [[ "$GPU_UUID" == GPU-* || "$GPU_UUID" == MIG-* ]] || {
      echo "Invalid UUID for visible GPU $GPU_ID" >> "$GPU_ERROR"
      cat "$GPU_ERROR" >&2
      exit 1
    }
    printf '%s,%s,%s,%s\n' "$GPU_ID" "$NVML_ID" \
      "${PHYSICAL_IDS[$GPU_POSITION]:-NA}" "$GPU_UUID" \
      >> "$GPU_IDENTITY_FILE"
    GPU_POSITION=$((GPU_POSITION + 1))
  done
  if [[ -s "$GPU_ERROR" ]]; then
    cat "$GPU_ERROR" >&2
    exit 1
  fi
  echo 'timestamp_utc,gpu_id,memory_used_mib,baseline_mib,incremental_mib' \
    > "$GPU_FILE"
  (
    while true; do
      for GPU_ID in ${GPU_IDS//,/ }; do
        USED="$(nvidia-smi -i "${NVML_IDS[$GPU_ID]}" \
          --query-gpu=memory.used \
          --format=csv,noheader,nounits 2>> "$GPU_ERROR" |
          tr -d '[:space:]')"
        BASELINE="${BASELINES[$GPU_ID]}"
        [[ "$USED" =~ ^[0-9]+$ ]] || {
          echo "Invalid GPU memory sample for device $GPU_ID" \
            >> "$GPU_ERROR"
          exit 1
        }
        printf '%s,%s,%s,%s,%s\n' \
          "$(date -u +%Y-%m-%dT%H:%M:%SZ)" \
          "$GPU_ID" "$USED" "$BASELINE" \
          "$((USED > BASELINE ? USED - BASELINE : 0))" \
          >> "$GPU_FILE"
      done
      touch "$GPU_READY"
      sleep 0.05
    done
  ) &
  MONITOR_PID=$!
  for ((attempt = 0; attempt < 50; attempt++)); do
    [[ -f "$GPU_READY" ]] && break
    kill -0 "$MONITOR_PID" 2>/dev/null || break
    sleep 0.1
  done
  [[ -f "$GPU_READY" ]] || {
    echo "GPU memory monitor failed before the measured command" >&2
    cat "$GPU_ERROR" >&2
    exit 1
  }
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
if [[ -n "$MONITOR_PID" && -s "$GPU_ERROR" ]]; then
  cat "$GPU_ERROR" >&2
  if (( STATUS == 0 )); then
    STATUS=1
  fi
fi
printf '%s\n' "$STATUS" > "$EXIT_FILE"
exit "$STATUS"
