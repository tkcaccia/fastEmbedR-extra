#!/usr/bin/env bash
#SBATCH --nodes=1
#SBATCH --ntasks=1
set -euo pipefail

suite=${DEEP1B_SUITE:-$DEEP1B_BASE/benchmark_scripts/massive-data/deep1b}
python3 "$suite/audit_campaign.py" \
    "$DEEP1B_CAMPAIGN"
