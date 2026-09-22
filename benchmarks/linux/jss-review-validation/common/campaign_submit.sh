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
  : "${JSS_CAMPAIGN_ID:?JSS_CAMPAIGN_ID is required}"
  : "${JSS_CAMPAIGN_DIR:?JSS_CAMPAIGN_DIR is required}"
  : "${JSS_LEDGER:?JSS_LEDGER is required}"
}

campaign_init_ledger() {
  mkdir -p "$JSS_CAMPAIGN_DIR" "$INPUT_ROOT" "$OUTPUT_ROOT"
  if [[ ! -f "$JSS_LEDGER" ]]; then
    printf '%s\n' \
      $'timestamp_utc\tcampaign_id\tstage\trole\tlabel\tjob_id\tdependency\tscript\tarray' \
      > "$JSS_LEDGER"
  fi
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
