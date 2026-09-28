#!/usr/bin/env bash

# Shared submission helpers for the staged JSS validation campaign.

campaign_require_environment() {
  : "${BASE_DIR:?BASE_DIR is required}"
  : "${SUITE:?SUITE is required}"
  : "${IMAGE:?IMAGE is required}"
  : "${INPUT_ROOT:?INPUT_ROOT is required}"
  : "${OUTPUT_ROOT:?OUTPUT_ROOT is required}"
  : "${EXPECTED_VERSION:?EXPECTED_VERSION is required}"
  : "${FASTEMBEDR_IMAGE_SHA256:?FASTEMBEDR_IMAGE_SHA256 is required}"
  : "${FASTEMBEDR_SUITE_MANIFEST_SHA256:?suite checksum is required}"
  : "${JSS_CAMPAIGN_ID:?JSS_CAMPAIGN_ID is required}"
  : "${JSS_CAMPAIGN_DIR:?JSS_CAMPAIGN_DIR is required}"
  : "${JSS_LEDGER:?JSS_LEDGER is required}"
}

campaign_verify_suite_revision() {
  local expected="${FASTEMBEDR_SUITE_MANIFEST_SHA256:-}"
  local manifest="$SUITE/FILES.sha256"
  local actual
  [[ -n "$expected" ]] || return 0
  if [[ ! -f "$manifest" ]]; then
    echo "Missing campaign source manifest: $manifest" >&2
    return 1
  fi
  actual="$(sha256sum "$manifest" | awk '{print $1}')"
  if [[ "$actual" != "$expected" ]]; then
    echo "Benchmark suite changed after campaign creation." >&2
    echo "Expected manifest SHA-256: $expected" >&2
    echo "Current manifest SHA-256:  $actual" >&2
    return 1
  fi
  (
    cd "$SUITE"
    sha256sum -c FILES.sha256 >/dev/null
  ) || {
    echo "Benchmark suite files do not match FILES.sha256." >&2
    return 1
  }
}

campaign_init_ledger() {
  mkdir -p "$JSS_CAMPAIGN_DIR" "$INPUT_ROOT" "$OUTPUT_ROOT"
  if [[ ! -f "$JSS_LEDGER" ]]; then
    printf '%s\n' \
      $'timestamp_utc\tcampaign_id\tstage\trole\tlabel\tjob_id\tdependency\tscript\tarray' \
      > "$JSS_LEDGER"
  fi
  if [[ ! -f "$JSS_CAMPAIGN_DIR/stages.tsv" ]]; then
    printf 'timestamp_utc\tstage\tevent\tdetail\n' \
      > "$JSS_CAMPAIGN_DIR/stages.tsv"
  fi
  if [[ ! -f "$JSS_CAMPAIGN_DIR/failures.tsv" ]]; then
    printf 'timestamp_utc\tstage\tlabel\tjob_id\ttask_id\tstate\texit_code\n' \
      > "$JSS_CAMPAIGN_DIR/failures.tsv"
  fi
}

campaign_record_stage() {
  printf '%s\t%s\t%s\t%s\n' \
    "$(date -u +%Y-%m-%dT%H:%M:%SZ)" "$1" "$2" "${3:--}" \
    >> "$JSS_CAMPAIGN_DIR/stages.tsv"
}

campaign_record_controller_failure() {
  local code="$1"
  campaign_record_stage "$JSS_STAGE" failed \
    "controller=${SLURM_JOB_ID:-local} exit=$code"
  printf '%s\t%s\t%s\t%s\t%s\t%s\t%s\n' \
    "$(date -u +%Y-%m-%dT%H:%M:%SZ)" "$JSS_STAGE" controller \
    "${SLURM_JOB_ID:-local}" '-' FAILED "$code" \
    >> "$JSS_CAMPAIGN_DIR/failures.tsv"
}

campaign_record_previous_stage() {
  local previous_stage job_id label records task_id state exit_code attempt
  local failed=0
  previous_stage="$(awk -F '\t' -v label="controller_$JSS_STAGE" \
    '$4 == "controller" && $5 == label { stage = $3 }
     END { print stage }' "$JSS_LEDGER")"
  [[ -n "$previous_stage" ]] || return 0
  [[ "$previous_stage" != "$JSS_STAGE" ]] || return 0
  if grep -Fqx "$previous_stage" \
      "$JSS_CAMPAIGN_DIR/audited_stages.txt" 2>/dev/null; then
    return 0
  fi
  while IFS=$'\t' read -r label job_id; do
    [[ -n "$job_id" ]] || continue
    records=''
    for attempt in 1 2 3 4 5; do
      records="$(sacct -X -n -P -j "$job_id" \
        -o JobID,State,ExitCode 2>/dev/null || true)"
      [[ -n "$records" ]] && break
      sleep 2
    done
    if [[ -z "$records" ]]; then
      printf '%s\t%s\t%s\t%s\t%s\t%s\t%s\n' \
        "$(date -u +%Y-%m-%dT%H:%M:%SZ)" "$previous_stage" \
        "$label" "$job_id" '-' UNKNOWN NA \
        >> "$JSS_CAMPAIGN_DIR/failures.tsv"
      failed=$((failed + 1))
      continue
    fi
    while IFS='|' read -r task_id state exit_code; do
      [[ "$task_id" == "$job_id" || \
         "$task_id" == "$job_id"'_'* ]] || continue
      if [[ "$task_id" == "$job_id" ]] && \
          grep -q "^${job_id}_" <<< "$records"; then
        continue
      fi
      if [[ "$state" != COMPLETED* || "$exit_code" != 0:0 ]]; then
        printf '%s\t%s\t%s\t%s\t%s\t%s\t%s\n' \
          "$(date -u +%Y-%m-%dT%H:%M:%SZ)" "$previous_stage" \
          "$label" "$job_id" "$task_id" "$state" "$exit_code" \
          >> "$JSS_CAMPAIGN_DIR/failures.tsv"
        failed=$((failed + 1))
      fi
    done <<< "$records"
  done < <(awk -F '\t' -v stage="$previous_stage" \
    'NR > 1 && $3 == stage && $4 == "worker" { print $5 "\t" $6 }' \
    "$JSS_LEDGER")
  campaign_record_stage "$previous_stage" completed "failures=$failed"
  printf '%s\n' "$previous_stage" \
    >> "$JSS_CAMPAIGN_DIR/audited_stages.txt"
}

campaign_existing_job() {
  local role="$1"
  local label="$2"
  awk -F '\t' -v role="$role" -v label="$label" '
    NR > 1 && $4 == role && $5 == label { id = $6 }
    END { if (id != "") print id }
  ' "$JSS_LEDGER"
}

campaign_record_job() {
  local role="$1"
  local label="$2"
  local job_id="$3"
  local dependency="$4"
  local script="$5"
  local array_spec="$6"
  printf '%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\n' \
    "$(date -u +%Y-%m-%dT%H:%M:%SZ)" "$JSS_CAMPAIGN_ID" \
    "${JSS_STAGE:-launcher}" "$role" "$label" "$job_id" \
    "${dependency:--}" "$script" "${array_spec:--}" >> "$JSS_LEDGER"
}

campaign_submit_job() {
  local role="$1"
  local label="$2"
  local dependency="$3"
  local script="$4"
  local array_spec="${5:-}"
  local next_stage="${6:-}"
  local existing output status job_id attempt
  local retry_seconds="${JSS_RETRY_SECONDS:-60}"
  local max_attempts="${JSS_MAX_SUBMIT_ATTEMPTS:-720}"
  local export_spec
  local -a command

  existing="$(campaign_existing_job "$role" "$label")"
  if [[ -n "$existing" ]]; then
    echo "Reusing recorded $role job $existing for $label" >&2
    printf '%s\n' "$existing"
    return 0
  fi

  export_spec="ALL,BASE_DIR=$BASE_DIR,SUITE=$SUITE,IMAGE=$IMAGE"
  export_spec+=",INPUT_ROOT=$INPUT_ROOT,OUTPUT_ROOT=$OUTPUT_ROOT"
  export_spec+=",EXPECTED_VERSION=$EXPECTED_VERSION"
  export_spec+=",FASTEMBEDR_IMAGE_SHA256=$FASTEMBEDR_IMAGE_SHA256"
  export_spec+=",FASTEMBEDR_SUITE_MANIFEST_SHA256="
  export_spec+="$FASTEMBEDR_SUITE_MANIFEST_SHA256"
  export_spec+=",JSS_CAMPAIGN_ID=$JSS_CAMPAIGN_ID"
  export_spec+=",JSS_CAMPAIGN_DIR=$JSS_CAMPAIGN_DIR"
  export_spec+=",JSS_LEDGER=$JSS_LEDGER"
  export_spec+=",JSS_RETRY_SECONDS=$retry_seconds"
  export_spec+=",JSS_MAX_SUBMIT_ATTEMPTS=$max_attempts"
  if [[ -n "$next_stage" ]]; then
    export_spec+=",JSS_STAGE=$next_stage"
  fi

  command=(sbatch --parsable --export="$export_spec")
  if [[ -n "$dependency" ]]; then
    command+=(--dependency="$dependency")
  fi
  if [[ -n "$array_spec" ]]; then
    command+=(--array="$array_spec")
  fi
  command+=("$script")

  for ((attempt = 1; attempt <= max_attempts; attempt++)); do
    set +e
    output="$("${command[@]}" 2>&1)"
    status=$?
    set -e
    if [[ "$status" -eq 0 ]]; then
      job_id="${output%%;*}"
      if [[ ! "$job_id" =~ ^[0-9]+$ ]]; then
        echo "Unexpected sbatch response: $output" >&2
        return 1
      fi
      campaign_record_job \
        "$role" "$label" "$job_id" "$dependency" "$script" "$array_spec"
      echo "Submitted $role $label as $job_id" >&2
      printf '%s\n' "$job_id"
      return 0
    fi
    if grep -Eqi \
      'QOSMaxSubmitJobPerUserLimit|AssocMaxSubmitJobLimit|job submit limit' \
      <<< "$output"; then
      echo "Submission limit reached for $label; retry $attempt/$max_attempts in ${retry_seconds}s." >&2
      sleep "$retry_seconds"
      continue
    fi
    echo "sbatch failed for $label: $output" >&2
    return "$status"
  done
  echo "Submission retries exhausted for $label." >&2
  return 1
}

campaign_afterany_dependency() {
  local joined
  joined="$(IFS=:; echo "$*")"
  printf 'afterany:%s\n' "$joined"
}
