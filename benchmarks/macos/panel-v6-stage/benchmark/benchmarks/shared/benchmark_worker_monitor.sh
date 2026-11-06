#!/usr/bin/env bash

# Run one isolated benchmark worker while recording process RAM and, on an
# NVIDIA host, whole-device GPU memory. The GPU measurement is intentionally
# labelled device-wide because process accounting is not reliable through all
# Apptainer PID namespaces. Publication jobs should request an exclusive GPU.

set -uo pipefail

if [[ "$#" -lt 4 ]]; then
  echo "usage: $0 TIME_FILE GPU_FILE TIMEOUT_SECONDS COMMAND [ARG ...]" >&2
  exit 64
fi

TIME_FILE="$1"
GPU_FILE="$2"
TIMEOUT_SECONDS="$3"
shift 3

mkdir -p "$(dirname "${TIME_FILE}")" "$(dirname "${GPU_FILE}")"
: > "${TIME_FILE}"
: > "${GPU_FILE}"

gpu_used_mb() {
  if ! command -v nvidia-smi >/dev/null 2>&1; then
    return 1
  fi
  nvidia-smi --query-gpu=memory.used --format=csv,noheader,nounits 2>/dev/null \
    | awk 'NR == 1 { gsub(/ /, "", $1); print $1 }'
}

baseline_gpu="$(gpu_used_mb || true)"
peak_gpu="${baseline_gpu}"
is_macos=false
if [[ "$(uname -s 2>/dev/null || true)" == "Darwin" ]]; then
  is_macos=true
fi

mac_free_pct() {
  memory_pressure -Q 2>/dev/null | awk -F: '
    /System-wide memory free percentage/ {
      gsub(/[^0-9.]/, "", $2); print $2; exit
    }'
}

mac_swap_mb() {
  sysctl vm.swapusage 2>/dev/null | awk '
    /used =/ {
      for (i = 1; i < NF; ++i) if ($i == "used") {
        value = $(i + 2); gsub(/[^0-9.]/, "", value)
        print value; exit
      }
    }'
}

mac_vm_counter() {
  vm_stat 2>/dev/null | awk -v key="$1:" '
    $1 == key { gsub(/[^0-9]/, "", $2); print $2; exit }'
}

mac_free_min="NA"
mac_swap_peak="NA"
mac_pageouts_start="NA"
mac_swapouts_start="NA"
mac_disk_device="NA"
if ${is_macos}; then
  mac_free_min="$(mac_free_pct)"
  mac_swap_peak="$(mac_swap_mb)"
  mac_pageouts_start="$(mac_vm_counter Pageouts)"
  mac_swapouts_start="$(mac_vm_counter Swapouts)"
  data_device="$(df -P "$(dirname "${TIME_FILE}")" |
    awk 'NR == 2 {print $1}')"
  physical_store="$(diskutil info "${data_device}" 2>/dev/null |
    awk -F: '/APFS Physical Store:/ {
      gsub(/[[:space:]]/, "", $2); print $2; exit
    }')"
  if [[ "${physical_store}" =~ ^disk[0-9]+s[0-9]+$ ]]; then
    mac_disk_device="${physical_store%s[0-9]*}"
    iostat -Id "${mac_disk_device}" > "${TIME_FILE}.disk_before" \
      2>/dev/null || true
  fi
fi

run_command=()
guard_file="${TIME_FILE}.guard.json"
if ${is_macos} && [[ "${FASTEMBEDR_MAC_GUARD:-FALSE}" == TRUE ]]; then
  guard="$(cd "$(dirname "${BASH_SOURCE[0]}")/../macos" && pwd -P)/mac_memory_guard_v1.py"
  [[ -f "${guard}" ]] || {
    echo "Mac memory guard is missing: ${guard}" >&2
    exit 64
  }
  run_command=(python3 "${guard}" "${TIMEOUT_SECONDS}" "${guard_file}")
else
  if command -v timeout >/dev/null 2>&1; then
    run_command+=(timeout "${TIMEOUT_SECONDS}")
  elif command -v gtimeout >/dev/null 2>&1; then
    run_command+=(gtimeout "${TIMEOUT_SECONDS}")
  fi
fi
run_command+=("$@")

native_time_file="${TIME_FILE}.native"
timed_command=()
if [[ -x /usr/bin/time ]]; then
  time_probe="${native_time_file}.probe"
  if [[ "$(uname -s 2>/dev/null || true)" == "Darwin" ]]; then
    if /usr/bin/time -l -o "${time_probe}" true >/dev/null 2>&1; then
      timed_command=(/usr/bin/time -l -o "${native_time_file}")
    fi
  else
    if /usr/bin/time -v -o "${time_probe}" true >/dev/null 2>&1; then
      timed_command=(/usr/bin/time -v -o "${native_time_file}")
    fi
  fi
  rm -f "${time_probe}"
fi
timed_command+=("${run_command[@]}")

rss_tree_proc_kb() {
  local root="$1"
  local -a queue=("${root}")
  local cursor=0
  local total=0
  local pid status rss children child

  while (( cursor < ${#queue[@]} )); do
    pid="${queue[cursor]}"
    cursor=$((cursor + 1))
    status="/proc/${pid}/status"
    if [[ -r "${status}" ]]; then
      rss="$(awk '/^VmRSS:/ { print $2; exit }' "${status}" 2>/dev/null || true)"
      if [[ "${rss}" =~ ^[0-9]+$ ]]; then
        total=$((total + rss))
      fi
    fi
    children="/proc/${pid}/task/${pid}/children"
    if [[ -r "${children}" ]]; then
      for child in $(<"${children}"); do
        [[ "${child}" =~ ^[0-9]+$ ]] && queue+=("${child}")
      done
    fi
  done
  echo "${total}"
}

rss_tree_ps_kb() {
  local root="$1"
  ps -axo pid=,ppid=,rss= 2>/dev/null | awk -v root="${root}" '
    { pid[NR] = $1; ppid[NR] = $2; rss[NR] = $3 }
    END {
      wanted[root] = 1
      changed = 1
      while (changed) {
        changed = 0
        for (i = 1; i <= NR; ++i) {
          if (wanted[ppid[i]] && !wanted[pid[i]]) {
            wanted[pid[i]] = 1
            changed = 1
          }
        }
      }
      total = 0
      for (i = 1; i <= NR; ++i) if (wanted[pid[i]]) total += rss[i]
      print total
    }'
}

rss_tree_kb() {
  local root="$1"
  if [[ -r "/proc/${root}/status" ]]; then
    rss_tree_proc_kb "${root}"
  else
    rss_tree_ps_kb "${root}"
  fi
}

start_epoch="$(date +%s)"
"${timed_command[@]}" &
worker_pid=$!
peak_rss_kb=0
last_mac_sample="${start_epoch}"

while kill -0 "${worker_pid}" >/dev/null 2>&1; do
  current_rss="$(rss_tree_kb "${worker_pid}" || true)"
  if [[ "${current_rss}" =~ ^[0-9]+$ ]] && (( current_rss > peak_rss_kb )); then
    peak_rss_kb="${current_rss}"
  fi
  current="$(gpu_used_mb || true)"
  if [[ "${current}" =~ ^[0-9]+([.][0-9]+)?$ ]]; then
    if [[ ! "${peak_gpu}" =~ ^[0-9]+([.][0-9]+)?$ ]] ||
       awk -v current="${current}" -v peak="${peak_gpu}" 'BEGIN { exit !(current > peak) }'; then
      peak_gpu="${current}"
    fi
  fi
  if ${is_macos} && (( $(date +%s) > last_mac_sample )); then
    last_mac_sample="$(date +%s)"
    mac_free="$(mac_free_pct)"
    mac_swap="$(mac_swap_mb)"
    if [[ "${mac_free}" =~ ^[0-9]+([.][0-9]+)?$ ]] &&
       { [[ ! "${mac_free_min}" =~ ^[0-9]+([.][0-9]+)?$ ]] ||
         awk -v a="${mac_free}" -v b="${mac_free_min}" \
           'BEGIN { exit !(a < b) }'; }; then
      mac_free_min="${mac_free}"
    fi
    if [[ "${mac_swap}" =~ ^[0-9]+([.][0-9]+)?$ ]] &&
       { [[ ! "${mac_swap_peak}" =~ ^[0-9]+([.][0-9]+)?$ ]] ||
         awk -v a="${mac_swap}" -v b="${mac_swap_peak}" \
           'BEGIN { exit !(a > b) }'; }; then
      mac_swap_peak="${mac_swap}"
    fi
  fi
  sleep 0.1
done

wait "${worker_pid}"
status=$?
end_epoch="$(date +%s)"
elapsed_sec=$(( end_epoch - start_epoch ))
mac_pageouts_delta="NA"
mac_swapouts_delta="NA"
if ${is_macos}; then
  if [[ "${mac_disk_device}" != NA ]]; then
    iostat -Id "${mac_disk_device}" > "${TIME_FILE}.disk_after" \
      2>/dev/null || true
  fi
  mac_pageouts_end="$(mac_vm_counter Pageouts)"
  mac_swapouts_end="$(mac_vm_counter Swapouts)"
  if [[ "${mac_pageouts_start}" =~ ^[0-9]+$ ]] &&
     [[ "${mac_pageouts_end}" =~ ^[0-9]+$ ]]; then
    mac_pageouts_delta=$((mac_pageouts_end - mac_pageouts_start))
  fi
  if [[ "${mac_swapouts_start}" =~ ^[0-9]+$ ]] &&
     [[ "${mac_swapouts_end}" =~ ^[0-9]+$ ]]; then
    mac_swapouts_delta=$((mac_swapouts_end - mac_swapouts_start))
  fi
fi

if [[ -s "${native_time_file}" ]]; then
  native_rss_kb=""
  if grep -q "Maximum resident set size (kbytes)" "${native_time_file}" 2>/dev/null; then
    native_rss_kb="$(awk -F: '/Maximum resident set size \(kbytes\)/ {gsub(/ /, "", $2); print $2}' "${native_time_file}" | tail -n 1)"
  elif grep -q "maximum resident set size" "${native_time_file}" 2>/dev/null; then
    native_rss_bytes="$(awk '/maximum resident set size/ {print $1}' "${native_time_file}" | tail -n 1)"
    if [[ "${native_rss_bytes}" =~ ^[0-9]+$ ]]; then
      native_rss_kb=$(( native_rss_bytes / 1024 ))
    fi
  fi
  if [[ "${native_rss_kb}" =~ ^[0-9]+$ ]] && (( native_rss_kb > peak_rss_kb )); then
    peak_rss_kb="${native_rss_kb}"
  fi
fi

{
  echo "Maximum resident set size (kbytes): ${peak_rss_kb}"
  echo "Elapsed wall clock time (seconds): ${elapsed_sec}"
  echo "Exit status: ${status}"
} > "${TIME_FILE}"

if ${is_macos}; then
  mac_native_field() {
    awk -v label="$1" '$2 == label { print $1; exit }' "${native_time_file}"
  }
  {
    echo "Mac system free memory minimum (percent): ${mac_free_min:-NA}"
    echo "Mac system swap used peak (MB): ${mac_swap_peak:-NA}"
    echo "Mac system pageouts delta: ${mac_pageouts_delta}"
    echo "Mac system swapouts delta: ${mac_swapouts_delta}"
    echo "Process swaps: $(mac_native_field swaps)"
    echo "Process block input operations: $(awk \
      '/block input operations/ {print $1; exit}' "${native_time_file}")"
    echo "Process block output operations: $(awk \
      '/block output operations/ {print $1; exit}' "${native_time_file}")"
    echo "Process peak memory footprint (bytes): $(awk \
      '/peak memory footprint/ {print $1; exit}' "${native_time_file}")"
    echo "Mac disk device: ${mac_disk_device}"
    if [[ -s "${guard_file}" ]]; then
      echo "Mac guard evidence file: ${guard_file}"
      echo "Mac guard status: $(awk -F\" \
        '/"status":/ {print $4; exit}' "${guard_file}")"
    fi
  } >> "${TIME_FILE}"
fi

delta_gpu="NA"
if [[ "${peak_gpu}" =~ ^[0-9]+([.][0-9]+)?$ ]] &&
   [[ "${baseline_gpu}" =~ ^[0-9]+([.][0-9]+)?$ ]]; then
  delta_gpu="$(awk -v peak="${peak_gpu}" -v base="${baseline_gpu}" \
    'BEGIN { value = peak - base; if (value < 0) value = 0; printf "%.3f", value }')"
fi

{
  if ${is_macos}; then
    echo "gpu_memory_scope=not_measured"
  else
    echo "gpu_memory_scope=device_wide"
  fi
  echo "gpu_baseline_mb=${baseline_gpu:-NA}"
  echo "gpu_peak_mb=${peak_gpu:-NA}"
  echo "gpu_peak_delta_mb=${delta_gpu}"
  echo "worker_exit_status=${status}"
} > "${GPU_FILE}"

exit "${status}"
