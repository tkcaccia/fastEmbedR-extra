#!/usr/bin/env python3
"""Screen initial space for a sequential, reclaiming full-graph route."""

import argparse
import json
import shutil
import sys
from pathlib import Path


def storage_plan(rows, mode, free_bytes, quota_free_bytes=None,
                 rebuild_knn=False):
    if rebuild_knn and mode != "full":
        raise ValueError("KNN rebuilding requires full mode")
    if mode in ("full", "full_tsne", "full_umap"):
        edges = rows * 30
        layout_bytes = 24 if mode == "full" else 16
        offsets = 8 * (rows + 1)
        staged = (20 * edges if mode == "full" and not rebuild_knn
                  else 12 * edges + 12 * 65536)
        required = staged + layout_bytes * rows + offsets
        later_edges = 44 if mode == "full" and not rebuild_knn else 36
        worst_case = later_edges * edges + layout_bytes * rows + offsets
    elif mode == "pca":
        required = 24 * rows
        worst_case = required
    else:
        required = 12 * rows * 96
        worst_case = required
    available = min(free_bytes, free_bytes if quota_free_bytes is None
                    else quota_free_bytes)
    return {
        "mode": mode,
        "rebuild_knn_for_umap": rebuild_knn,
        "knn_builds": 2 if rebuild_knn else 1,
        "rows": rows,
        "required_bytes": required,
        "worst_case_bytes": worst_case,
        "required_bytes_kind": "initial_admission" if
            worst_case > required else "complete_stage",
        "scope": "graph_stage" if mode.startswith("full") else "fit_stage",
        "excludes": ["input", "image", "clustering", "concurrent_jobs"],
        "later_bucket_check_required": worst_case > required,
        "worst_case_fits_margin": worst_case <= 0.8 * available,
        "available_bytes": available,
        "status": "READY" if required <= 0.8 * available else
            "BLOCKED_SPACE",
    }


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("output_dir", type=Path)
    parser.add_argument("rows", type=int)
    parser.add_argument("mode", choices=("full", "full_tsne",
                                         "full_umap", "pca", "classic"))
    parser.add_argument("--quota-free-bytes", type=int)
    parser.add_argument("--free-bytes", type=int)
    parser.add_argument("--rebuild-knn", action="store_true")
    args = parser.parse_args()
    if args.rows < 1000 or args.rows > 1_000_000_000:
        parser.error("rows must be between 1,000 and 1 billion")
    if args.mode == "classic" and args.rows != 1_000_000:
        parser.error("classic comparison requires 1 million rows")
    free = args.free_bytes
    if free is None:
        free = shutil.disk_usage(args.output_dir).free
    plan = storage_plan(args.rows, args.mode, free,
                        args.quota_free_bytes, args.rebuild_knn)
    print(json.dumps(plan, sort_keys=True))
    if plan["status"] != "READY":
        sys.exit(3)


if __name__ == "__main__":
    main()
