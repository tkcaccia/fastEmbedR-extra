#!/usr/bin/env python3
"""Independent sampled-query checks against 100M and 1B references."""

import csv
import json
import sys
from pathlib import Path

from make_cases import validate_input, write


SCALES = (("large_100m", 100_000_000, 100_000_001, 1_024),
          ("large_1b", 1_000_000_000, 1, 256))


def main(root, representative, data_root):
    with (representative / "selected.csv").open(newline="") as handle:
        selected = [row for row in csv.DictReader(handle)
                    if row["shard_rows"] == "250000"]
    if not selected:
        raise ValueError("No 250k-shard HNSW setting passed all windows")
    inputs = {row["dataset"]: validate_input(data_root, row["dataset"])
              for row in selected}
    root.mkdir(parents=True, exist_ok=False)
    (root / "input_identity.json").write_text(
        json.dumps(inputs, indent=2) + "\n", encoding="utf-8")
    truth, sweep = [], []
    for selected_row in selected:
        for scope, rows, first_row, queries in SCALES:
            common = dict(dataset=selected_row["dataset"], scope=scope,
                          rows=rows, first_row=first_row,
                          query_count=queries)
            truth.append(common)
            sweep.append(dict(**common, shard_rows=250_000, k=30,
                m=selected_row["m"],
                ef_construction=selected_row["ef_construction"],
                ef_search=selected_row["ef_search"]))
    write(root / "truth_cases.tsv", truth[0].keys(), truth)
    write(root / "sweep_cases.tsv", sweep[0].keys(), sweep)
    print(f"truth={len(truth)} sweep={len(sweep)}")


if __name__ == "__main__":
    main(Path(sys.argv[1]), Path(sys.argv[2]), Path(sys.argv[3]))
