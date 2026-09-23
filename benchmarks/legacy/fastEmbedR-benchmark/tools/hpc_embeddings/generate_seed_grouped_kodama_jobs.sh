#!/usr/bin/env bash

# Generate one three-seed Slurm array per dataset and backend. Each array task
# runs both KODAMA classifiers for landmark 10%, 20%, 50%, and then the full
# default configuration. CPU-1 jobs are intentionally excluded.

set -euo pipefail

generation_base_dir="${GENERATION_BASE_DIR:-${BASE_DIR:-/scratch/firenze/NN}}"
runtime_base_dir="${HPC_BASE_DIR:-/scratch/firenze/NN}"
launcher_root="${generation_base_dir}/kodama_classifier_jobs_by_dataset"
pair_dir="${launcher_root}/combined"
output_dir="${launcher_root}/seed_grouped"
graph_dir="${launcher_root}/graph_precompute"

mkdir -p "${output_dir}" "${graph_dir}"

generated=0
for profile in cpu4 cuda; do
  shopt -s nullglob
  defaults=("${pair_dir}"/run_kodama_combined_*_"${profile}"_default.sh)
  if (( ${#defaults[@]} == 0 )); then
    echo "No paired default launchers found for ${profile}." >&2
    exit 1
  fi

  for default_job in "${defaults[@]}"; do
    default_name="$(basename "${default_job}")"
    dataset="${default_name#run_kodama_combined_}"
    dataset="${dataset%_${profile}_default.sh}"
    safe_dataset="$(printf '%s' "${dataset}" | tr -c 'A-Za-z0-9_.-' '_')"
    short_dataset="${safe_dataset:0:12}"
    output="${output_dir}/run_kodama_seed_grouped_${safe_dataset}_${profile}.sh"
    graph_job="${graph_dir}/prepare_kodama_graph_${safe_dataset}_${profile}.sh"

    awk '
      /^set -uo pipefail$/ { exit }
      /^#SBATCH --array=/ { next }
      { print }
    ' "${default_job}" |
      sed \
        -e "s|^#SBATCH --job-name=.*|#SBATCH --job-name=\"K_SEED_${short_dataset}_${profile}\"|" \
        -e "s|^#SBATCH --output=.*|#SBATCH --output=${runtime_base_dir}/benchmark_logs/KODAMA_seed_${safe_dataset}_${profile}_%A_%a.out|" \
        -e "s|^#SBATCH --error=.*|#SBATCH --error=${runtime_base_dir}/benchmark_logs/KODAMA_seed_${safe_dataset}_${profile}_%A_%a.err|" \
        > "${output}"

    {
      printf '%s\n' '#SBATCH --array=0-2'
      printf '\n'
      printf '%s\n' 'set -uo pipefail'
      printf '\n'
      printf 'dataset=%q\n' "${dataset}"
      printf 'profile=%q\n' "${profile}"
      printf 'pair_dir=%q\n' "${runtime_base_dir}/kodama_classifier_jobs_by_dataset/combined"
      cat <<'EOF'
run_stamp="${RUN_STAMP:-$(date +%Y%m%d_%H%M%S)}"
seed_values=(4 17 42)
seed_index="${SLURM_ARRAY_TASK_ID:-0}"
seed="${seed_values[${seed_index}]}"
variants=(landmark10 landmark20 landmark50 default)

overall_status=0
for variant in "${variants[@]}"; do
  pair_job="${pair_dir}/run_kodama_combined_${dataset}_${profile}_${variant}.sh"
  if [[ ! -f "${pair_job}" ]]; then
    if [[ "${variant}" == "default" ]]; then
      echo "Missing required paired launcher: ${pair_job}" >&2
      overall_status=1
    else
      echo "SKIP: ${dataset} has no ${variant} launcher."
    fi
    continue
  fi

  echo
  echo "######## dataset=${dataset} profile=${profile} seed=${seed} variant=${variant} ########"
  if SLURM_ARRAY_TASK_ID="${seed_index}" \
     RUN_STAMP="${run_stamp}" \
     bash "${pair_job}"; then
    echo "COMPLETED: dataset=${dataset} profile=${profile} seed=${seed} variant=${variant}"
  else
    rc=$?
    overall_status=1
    echo "FAILED: dataset=${dataset} profile=${profile} seed=${seed} variant=${variant} status=${rc}" >&2
  fi
done

exit "${overall_status}"
EOF
    } >> "${output}"

    chmod 0755 "${output}"

    awk '
      /^set -uo pipefail$/ { exit }
      /^#SBATCH --array=/ { next }
      { print }
    ' "${default_job}" |
      sed \
        -e "s|^#SBATCH --job-name=.*|#SBATCH --job-name=\"K_GRAPH_${short_dataset}_${profile}\"|" \
        -e "s|^#SBATCH --output=.*|#SBATCH --output=${runtime_base_dir}/benchmark_logs/KODAMA_graph_${safe_dataset}_${profile}_%j.out|" \
        -e "s|^#SBATCH --error=.*|#SBATCH --error=${runtime_base_dir}/benchmark_logs/KODAMA_graph_${safe_dataset}_${profile}_%j.err|" \
        > "${graph_job}"

    {
      printf '%s\n' 'set -euo pipefail'
      printf '\n'
      printf 'export BENCHMARK_DATASET=%q\n' "${dataset}"
      if [[ "${profile}" == "cpu4" ]]; then
        printf '%s\n' 'export KODAMA_BACKEND="cpu"'
        printf '%s\n' 'export KODAMA_THREADS="4"'
      else
        printf '%s\n' 'export KODAMA_BACKEND="cuda"'
        printf '%s\n' 'export KODAMA_THREADS="1"'
      fi
      printf 'export BASE_DIR=%q\n' "${runtime_base_dir}"
      cat <<'EOF'
export KODAMA_GRAPH_NEIGHBORS="100"
export KODAMA_GRAPH_SEED="4"
export FORCE_GRAPH="${FORCE_GRAPH:-FALSE}"

exec bash "${BASE_DIR}/benchmark_scripts/kodama_classifier_benchmark/run_kodama_graph_precompute_job.sh"
EOF
    } >> "${graph_job}"
    chmod 0755 "${graph_job}"
    generated=$((generated + 1))
  done
done

cat > "${output_dir}/submit_cpu4.sh" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
graph_dir="$(cd "${script_dir}/../graph_precompute" && pwd)"
shopt -s nullglob
for analysis_job in "${script_dir}"/run_kodama_seed_grouped_*_cpu4.sh; do
  stem="$(basename "${analysis_job}")"
  dataset="${stem#run_kodama_seed_grouped_}"
  dataset="${dataset%_cpu4.sh}"
  graph_job="${graph_dir}/prepare_kodama_graph_${dataset}_cpu4.sh"
  [[ -f "${graph_job}" ]] || { echo "Missing ${graph_job}" >&2; exit 1; }
  graph_id="$(sbatch --parsable "${graph_job}")"
  graph_id="${graph_id%%;*}"
  analysis_id="$(sbatch --parsable --dependency="afterok:${graph_id}" "${analysis_job}")"
  echo "dataset=${dataset} graph_job=${graph_id} analysis_job=${analysis_id%%;*}"
done
EOF

cat > "${output_dir}/submit_cuda.sh" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
graph_dir="$(cd "${script_dir}/../graph_precompute" && pwd)"
shopt -s nullglob
for analysis_job in "${script_dir}"/run_kodama_seed_grouped_*_cuda.sh; do
  stem="$(basename "${analysis_job}")"
  dataset="${stem#run_kodama_seed_grouped_}"
  dataset="${dataset%_cuda.sh}"
  graph_job="${graph_dir}/prepare_kodama_graph_${dataset}_cuda.sh"
  [[ -f "${graph_job}" ]] || { echo "Missing ${graph_job}" >&2; exit 1; }
  graph_id="$(sbatch --parsable "${graph_job}")"
  graph_id="${graph_id%%;*}"
  analysis_id="$(sbatch --parsable --dependency="afterok:${graph_id}" "${analysis_job}")"
  echo "dataset=${dataset} graph_job=${graph_id} analysis_job=${analysis_id%%;*}"
done
EOF

chmod 0755 "${output_dir}/submit_cpu4.sh" "${output_dir}/submit_cuda.sh"
echo "Generated ${generated} graph-precompute jobs in ${graph_dir}."
echo "Generated ${generated} CPU-4/CUDA seed-grouped launchers in ${output_dir}."
