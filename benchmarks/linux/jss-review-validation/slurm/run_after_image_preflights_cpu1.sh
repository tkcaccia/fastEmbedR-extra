#!/usr/bin/env bash
#SBATCH --account=immunology
#SBATCH --partition=ada
#SBATCH --nodes=1
#SBATCH --ntasks=1
#SBATCH --cpus-per-task=1
#SBATCH --mem=2G
#SBATCH --time=00:20:00
#SBATCH --job-name=feR_JSS_image
#SBATCH --chdir=/scratch/firenze/NN
#SBATCH --output=/scratch/firenze/NN/benchmark_logs/feR_JSS_image_%j.out
#SBATCH --error=/scratch/firenze/NN/benchmark_logs/feR_JSS_image_%j.err

set -euo pipefail

BASE_DIR="${BASE_DIR:-/scratch/firenze/NN}"
SUITE="${SUITE:-$BASE_DIR/benchmark_scripts/fastembedr_jss_review_validation}"
CAMPAIGN_MODE="${CAMPAIGN_MODE:-complete}"

check_preflight_job() {
  local job_id="$1" state="" attempt
  [[ "$job_id" =~ ^[0-9]+$ ]] || {
    echo "Invalid preflight job ID: $job_id" >&2
    return 1
  }
  for attempt in 1 2 3 4 5 6; do
    state="$(sacct -X -n -P -j "$job_id" -o State,ExitCode \
      2>/dev/null | awk -F '|' 'NF >= 2 {print $1 "|" $2; exit}')"
    [[ -n "$state" ]] && break
    sleep 5
  done
  [[ "$state" == 'COMPLETED|0:0' ]] || {
    echo "Preflight job $job_id did not complete successfully: " \
      "${state:-missing accounting record}" >&2
    return 1
  }
}

cd "$BASE_DIR"
check_preflight_job "${CPU_PREFLIGHT_JOB:?CPU job ID required}"
check_preflight_job "${CUDA_PREFLIGHT_JOB:?CUDA job ID required}"
bash "$SUITE/verify_preflight.sh"
case "$CAMPAIGN_MODE" in
  complete) bash "$SUITE/submit_complete_campaign.sh" ;;
  full_cuda) bash "$SUITE/submit_full_cuda_campaign.sh" ;;
  *) echo "Unknown campaign mode: $CAMPAIGN_MODE" >&2; exit 2 ;;
esac
