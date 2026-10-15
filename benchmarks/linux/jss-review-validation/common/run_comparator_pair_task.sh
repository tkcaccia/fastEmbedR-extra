#!/usr/bin/env bash

set -euo pipefail

mode="${1:?comparator mode is required}"
suite="${SUITE:-/scratch/firenze/NN/benchmark_scripts/fastembedr_jss_review_validation}"
export PAIR_3D=TRUE
for dimensions in 2 3; do
  N_COMPONENTS="$dimensions" \
    bash "$suite/common/run_comparator_task.sh" "$mode"
done
