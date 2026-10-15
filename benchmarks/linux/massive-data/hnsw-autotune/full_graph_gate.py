#!/usr/bin/env python3
"""Record lower-bound resource gates for full all-row graph experiments."""

import csv
import math
import sys
from pathlib import Path


ROWS = (10_000_000, 100_000_000, 1_000_000_000)
COLS = {"deep": 96, "turing": 100}
K = 30
MAX_IO_BYTES = 5_000_000_000_000


def read_csv(path):
    with path.open(newline="") as handle:
        return list(csv.DictReader(handle))


def plan(root):
    selected = read_csv(root / "selected.csv")
    output = []
    for dataset in COLS:
        for backend, devices in (("cpu", 1), ("cuda", 1),
                                 ("cuda", 2)):
            for rows in ROWS:
                requested_shard = 50_000 if rows == 10_000_000 else 250_000
                shards = math.ceil(rows / requested_shard)
                read_bytes = rows * COLS[dataset] * 4 * shards
                graph_bytes = rows * K * 8
                has_controls = any(row["dataset"] == dataset and
                    int(row["shard_rows"]) == requested_shard
                    for row in selected)
                if devices == 2:
                    status = "UNSUPPORTED_FULL_GRAPH_MULTI_GPU"
                elif backend == "cpu" and not has_controls:
                    status = "NO_CALIBRATED_099_HNSW_SETTING"
                elif read_bytes > MAX_IO_BYTES:
                    status = "GATED_MINIMUM_IO_OVER_5TB"
                elif rows == 10_000_000:
                    status = "ELIGIBLE_10M_GRAPH_STAGE"
                else:
                    status = "REQUIRES_INDEPENDENT_LARGE_RECALL_PROBE"
                output.append(dict(dataset=dataset, backend=backend,
                    devices=devices, rows=rows,
                    reference_shard_rows=requested_shard,
                    minimum_query_input_read_bytes=read_bytes,
                    graph_output_bytes=graph_bytes,
                    status=status))
    with (root / "full_graph_feasibility.csv").open(
            "w", newline="") as handle:
        writer = csv.DictWriter(handle, output[0])
        writer.writeheader()
        writer.writerows(output)
    return output


if __name__ == "__main__":
    plan(Path(sys.argv[1]))
