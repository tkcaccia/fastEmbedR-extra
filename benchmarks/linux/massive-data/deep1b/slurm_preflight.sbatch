#!/usr/bin/env bash
#SBATCH --nodes=1
#SBATCH --ntasks=1
set -euo pipefail

sha256sum -c "$DEEP1B_CAMPAIGN/source.sha256" >/dev/null
sha256sum -c "$DEEP1B_CAMPAIGN/image.sha256" >/dev/null
stat -Lc '%i:%s:%Y' "$DEEP1B_IMAGE" \
    > "$DEEP1B_CAMPAIGN/image.stat"
suite=${DEEP1B_SUITE:-$DEEP1B_BASE/benchmark_scripts/massive-data/deep1b}
singularity exec "$DEEP1B_IMAGE" /opt/r46/bin/Rscript \
    "$suite/preflight.R"
if [[ "${DEEP1B_PHASE:-}" == pilot && -n "${VIS_SUITE:-}" ]]; then
    test -s "$VIS_SUITE/test_render_full_layouts.R"
    singularity exec "$DEEP1B_IMAGE" /opt/r46/bin/Rscript \
        "$VIS_SUITE/test_render_full_layouts.R" \
        > "$DEEP1B_CAMPAIGN/plot_preflight.out" \
        2> "$DEEP1B_CAMPAIGN/plot_preflight.err"
fi
touch "$DEEP1B_CAMPAIGN/preflight.ok"
