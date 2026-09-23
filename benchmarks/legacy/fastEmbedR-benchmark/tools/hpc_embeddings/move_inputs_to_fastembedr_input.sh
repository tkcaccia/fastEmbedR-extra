#!/usr/bin/env bash

# Move deterministic benchmark inputs out of fastEmbedR-results and
# deduplicate them in fastEmbedR-input. The default is a read-only preview.

set -euo pipefail

BASE_DIR="${BASE_DIR:-/scratch/firenze/NN}"
RESULTS_ROOT="${RESULTS_ROOT:-${BASE_DIR}/fastEmbedR-results}"
INPUT_ROOT="${INPUT_ROOT:-${BASE_DIR}/fastEmbedR-input}"
DRY_RUN="${DRY_RUN:-TRUE}"
LINK_BACK="${LINK_BACK:-FALSE}"
STAMP="$(date +%Y%m%d_%H%M%S)"
MANIFEST="${MANIFEST:-${INPUT_ROOT}/migration_manifest_${STAMP}.csv}"

is_true() {
  case "$(printf '%s' "$1" | tr '[:upper:]' '[:lower:]')" in
    1|true|yes|y) return 0 ;;
    *) return 1 ;;
  esac
}

csv_field() {
  local value="${1//\"/\"\"}"
  printf '"%s"' "${value}"
}

sha256_file() {
  if command -v sha256sum >/dev/null 2>&1; then
    sha256sum "$1" | awk '{print $1}'
  elif command -v shasum >/dev/null 2>&1; then
    shasum -a 256 "$1" | awk '{print $1}'
  else
    echo "A SHA-256 utility (sha256sum or shasum) is required." >&2
    return 1
  fi
}

file_size() {
  if stat -c '%s' "$1" >/dev/null 2>&1; then
    stat -c '%s' "$1"
  else
    stat -f '%z' "$1"
  fi
}

record() {
  local category="$1" source="$2" destination="$3" action="$4"
  local bytes="$5" digest="${6:-}" note="${7:-}"
  {
    csv_field "${category}"; printf ','
    csv_field "${source}"; printf ','
    csv_field "${destination}"; printf ','
    csv_field "${action}"; printf ','
    printf '%s,' "${bytes}"
    csv_field "${digest}"; printf ','
    csv_field "${note}"; printf '\n'
  } >>"${MANIFEST}"
}

dataset_from_cache_name() {
  local name="$1"
  name="${name%.rds}"
  case "${name}" in
    *_knn_*) printf '%s\n' "${name%%_knn_*}" ;;
    *_pca_init_*) printf '%s\n' "${name%%_pca_init_*}" ;;
    *_validation_*) printf '%s\n' "${name%%_validation_*}" ;;
    *_precompute_manifest*) printf '%s\n' "${name%%_precompute_manifest*}" ;;
    *) printf '%s\n' "legacy" ;;
  esac
}

is_kodama_cache_name() {
  [[ "$1" =~ _M[0-9]+_C[0-9]+_P[0-9]+_L[0-9]+_G[0-9]+_K[0-9]+_v ]]
}

dataset_from_kodama_name() {
  local name="${1%.rds}"
  if [[ "${name}" == *_pls_lda_* ]]; then
    printf '%s\n' "${name%%_pls_lda_*}"
  elif [[ "${name}" == *_knn_* ]]; then
    printf '%s\n' "${name%%_knn_*}"
  else
    printf '%s\n' "legacy"
  fi
}

canonical_path() {
  local category="$1" source="$2" name parent dataset grandparent
  name="$(basename "${source}")"
  parent="$(basename "$(dirname "${source}")")"
  case "${category}" in
    python_npz)
      dataset="${name%_float32_for_python.npz}"
      [[ "${dataset}" != "${name}" ]] || dataset="${parent}"
      printf '%s/python_npz/%s/%s\n' "${INPUT_ROOT}" "${dataset}" "${name}"
      ;;
    reference_affinity)
      dataset="${parent}"
      printf '%s/reference_affinity/%s/%s\n' "${INPUT_ROOT}" "${dataset}" "${name}"
      ;;
    validation_knn)
      dataset="${name%.rds}"
      dataset="${dataset%%_cpu_knn}"
      dataset="${dataset%%_cuda_knn}"
      dataset="${dataset%%_metal_knn}"
      dataset="${dataset%%_cpu_validation_*}"
      dataset="${dataset%%_cuda_validation_*}"
      dataset="${dataset%%_metal_validation_*}"
      [[ -n "${dataset}" ]] || dataset="legacy"
      printf '%s/validation_knn/%s/%s\n' "${INPUT_ROOT}" "${dataset}" "${name}"
      ;;
    precomputed)
      if [[ "${parent}" == "kodama_core" ]] || is_kodama_cache_name "${name}"; then
        grandparent="$(basename "$(dirname "$(dirname "${source}")")")"
        case "${grandparent}" in
          cpu|cuda|metal|cpu1|cpu4|cpu12|cuda1|cuda4)
            dataset="$(basename "$(dirname "$(dirname "$(dirname "${source}")")")")"
            ;;
          precomputed|kodama_core)
            dataset="$(dataset_from_kodama_name "${name}")"
            ;;
          *)
            dataset="${grandparent}"
            if [[ "${parent}" != "kodama_core" ]]; then
              dataset="$(dataset_from_kodama_name "${name}")"
            fi
            ;;
        esac
        printf '%s/precomputed/%s/kodama_core/%s\n' \
          "${INPUT_ROOT}" "${dataset}" "${name}"
        return 0
      fi
      dataset="$(dataset_from_cache_name "${name}")"
      if [[ "${dataset}" == "legacy" ]]; then
        dataset="${parent}"
        case "${dataset}" in
          cpu|cuda|metal|cpu1|cpu4|cpu12|cuda1|cuda4)
            dataset="$(basename "$(dirname "$(dirname "${source}")")")"
            ;;
        esac
      fi
      printf '%s/precomputed/%s/%s\n' "${INPUT_ROOT}" "${dataset}" "${name}"
      ;;
    *)
      return 2
      ;;
  esac
}

link_old_path() {
  local source="$1" destination="$2"
  is_true "${LINK_BACK}" || return 0
  ln -s "${destination}" "${source}"
}

migrate_one() {
  local category="$1" source="$2" destination bytes source_hash destination_hash name
  [[ -f "${source}" && ! -L "${source}" ]] || return 0
  name="$(basename "${source}")"
  if [[ "${category}" == "precomputed" &&
        "${name}" == *_precompute_manifest*.rds ]]; then
    bytes="$(file_size "${source}")"
    record "${category}" "${source}" "" "skipped" "${bytes}" "" \
      "run-specific manifest is not a reusable benchmark input"
    return 0
  fi
  destination="$(canonical_path "${category}" "${source}")"
  [[ "${source}" != "${destination}" ]] || return 0
  bytes="$(file_size "${source}")"

  if [[ ! -e "${destination}" ]]; then
    if is_true "${DRY_RUN}"; then
      printf 'MOVE  %s\n   -> %s\n' "${source}" "${destination}"
      record "${category}" "${source}" "${destination}" "would_move" \
        "${bytes}" "" "dry run"
      return 0
    fi
    mkdir -p "$(dirname "${destination}")"
    mv "${source}" "${destination}"
    link_old_path "${source}" "${destination}"
    source_hash="$(sha256_file "${destination}")"
    record "${category}" "${source}" "${destination}" "moved" \
      "${bytes}" "${source_hash}" "canonical copy created"
    moved_count=$((moved_count + 1))
    return 0
  fi

  if [[ "$(file_size "${destination}")" != "${bytes}" ]]; then
    printf 'CONFLICT (different size): %s\n' "${source}" >&2
    record "${category}" "${source}" "${destination}" "conflict" \
      "${bytes}" "" "destination has a different size; source retained"
    conflict_count=$((conflict_count + 1))
    return 0
  fi

  source_hash="$(sha256_file "${source}")"
  destination_hash="$(sha256_file "${destination}")"
  if [[ "${source_hash}" != "${destination_hash}" ]]; then
    printf 'CONFLICT (different checksum): %s\n' "${source}" >&2
    record "${category}" "${source}" "${destination}" "conflict" \
      "${bytes}" "${source_hash}" "destination checksum differs; source retained"
    conflict_count=$((conflict_count + 1))
    return 0
  fi

  if is_true "${DRY_RUN}"; then
    printf 'DEDUP %s\n   == %s\n' "${source}" "${destination}"
    record "${category}" "${source}" "${destination}" "would_deduplicate" \
      "${bytes}" "${source_hash}" "dry run"
    return 0
  fi

  unlink "${source}"
  link_old_path "${source}" "${destination}"
  record "${category}" "${source}" "${destination}" "deduplicated" \
    "${bytes}" "${source_hash}" "identical duplicate removed"
  deduplicated_count=$((deduplicated_count + 1))
  reclaimed_bytes=$((reclaimed_bytes + bytes))
}

if [[ ! -d "${RESULTS_ROOT}" ]]; then
  echo "Results root does not exist: ${RESULTS_ROOT}" >&2
  exit 1
fi
if [[ -z "${INPUT_ROOT}" || "${INPUT_ROOT}" == "/" ||
      "${INPUT_ROOT}" == "${RESULTS_ROOT}" ]]; then
  echo "Unsafe INPUT_ROOT: ${INPUT_ROOT}" >&2
  exit 2
fi

mkdir -p "${INPUT_ROOT}"
printf '"category","source","destination","action","bytes","sha256","note"\n' \
  >"${MANIFEST}"

moved_count=0
deduplicated_count=0
conflict_count=0
reclaimed_bytes=0
removed_link_count=0

while IFS= read -r -d '' source; do
  migrate_one "python_npz" "${source}"
done < <(find "${RESULTS_ROOT}" -type f -path '*/python_inputs/*.npz' -print0)

while IFS= read -r -d '' source; do
  migrate_one "reference_affinity" "${source}"
done < <(
  find "${RESULTS_ROOT}" -type f \
    \( -path '*/reference_affinity/*/validation_float32.bin' \
       -o -path '*/reference_affinity/*/validation_*_float32.bin' \) \
    -print0
)

while IFS= read -r -d '' source; do
  migrate_one "validation_knn" "${source}"
done < <(find "${RESULTS_ROOT}" -type f -path '*/validation_knn/*.rds' -print0)

while IFS= read -r -d '' source; do
  migrate_one "precomputed" "${source}"
done < <(
  find "${RESULTS_ROOT}" -type f \
    \( -path '*/cache_cpu/*.rds' -o -path '*/cache_cuda/*.rds' \
       -o -path '*/reviewer_precomputed/*.rds' \) \
    -print0
)

for legacy_root in \
  "${BASE_DIR}/Data/_fastEmbedR_precomputed" \
  "${BASE_DIR}/Data/_fastEmbedR_precomputed_jobs"; do
  [[ -d "${legacy_root}" ]] || continue
  while IFS= read -r -d '' source; do
    migrate_one "precomputed" "${source}"
  done < <(
    find "${legacy_root}" -type f \
      \( -name '*_knn_*.rds' -o -name '*_validation_*.rds' \
         -o -path '*/kodama_core/*.rds' \) \
      -print0
  )
done

# Repair KODAMA caches placed by an earlier migration-script revision. Moving
# them leaves a compatibility symlink, so historical paths remain valid.
while IFS= read -r -d '' source; do
  if [[ "$(basename "$(dirname "${source}")")" == "kodama_core" ]] ||
      is_kodama_cache_name "$(basename "${source}")"; then
    migrate_one "precomputed" "${source}"
  fi
done < <(find "${INPUT_ROOT}/precomputed" -maxdepth 3 -type f -name '*.rds' -print0)

if ! is_true "${LINK_BACK}"; then
  while IFS= read -r -d '' source; do
    link_target="$(readlink "${source}" 2>/dev/null || true)"
    case "${link_target}" in
      /*) resolved="${link_target}" ;;
      "")
        resolved=""
        ;;
      *)
        if command -v realpath >/dev/null 2>&1; then
          resolved="$(realpath "${source}" 2>/dev/null || true)"
        else
          resolved="$(cd "$(dirname "${source}")" &&
            printf '%s/%s\n' "$(pwd -P)" "${link_target}")"
        fi
        ;;
    esac
    case "${resolved}" in
      "${INPUT_ROOT}"/*)
        if is_true "${DRY_RUN}"; then
          printf 'UNLINK %s\n' "${source}"
          record "compatibility_link" "${source}" "${resolved}" \
            "would_remove_symlink" 0 "" "dry run"
        else
          unlink "${source}"
          record "compatibility_link" "${source}" "${resolved}" \
            "removed_symlink" 0 "" "canonical input remains"
          removed_link_count=$((removed_link_count + 1))
        fi
        ;;
      *)
        record "compatibility_link" "${source}" "${resolved}" \
          "skipped" 0 "" "symlink does not resolve inside INPUT_ROOT"
        ;;
    esac
  done < <(
    find "${RESULTS_ROOT}" -type l \
      \( -path '*/python_inputs/*.npz' \
         -o -path '*/reference_affinity/*/validation_float32.bin' \
         -o -path '*/reference_affinity/*/validation_*_float32.bin' \
         -o -path '*/validation_knn/*.rds' \
         -o -path '*/cache_cpu/*.rds' \
         -o -path '*/cache_cuda/*.rds' \
         -o -path '*/reviewer_precomputed/*.rds' \) \
      -print0
  )

  if ! is_true "${DRY_RUN}"; then
    find "${RESULTS_ROOT}" -depth -type d \
      \( -name python_inputs -o -name validation_knn \
         -o -name cache_cpu -o -name cache_cuda \
         -o -name reviewer_precomputed \) \
      -empty -exec rmdir {} \; 2>/dev/null || true
  fi
fi

echo
echo "Migration manifest: ${MANIFEST}"
if is_true "${DRY_RUN}"; then
  echo "Dry run only; no files were moved or removed."
  echo "Run with DRY_RUN=FALSE after reviewing the manifest."
else
  echo "Moved canonical files: ${moved_count}"
  echo "Removed identical duplicates: ${deduplicated_count}"
  echo "Removed compatibility symlinks: ${removed_link_count}"
  echo "Conflicts retained: ${conflict_count}"
  echo "Bytes reclaimed by deduplication: ${reclaimed_bytes}"
fi
