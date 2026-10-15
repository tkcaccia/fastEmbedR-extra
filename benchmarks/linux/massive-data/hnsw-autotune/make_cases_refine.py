#!/usr/bin/env python3
"""Create a new 5M-row window for bounded HNSW effort refinement."""

import json
import sys
from pathlib import Path

from make_cases import validate_input, write


def main(root, data_root):
    inputs = {name: validate_input(data_root, name)
              for name in ("deep", "turing")}
    root.mkdir(parents=True, exist_ok=False)
    (root / "input_identity.json").write_text(
        json.dumps(inputs, indent=2) + "\n", encoding="utf-8")
    common = dict(scope="refine5m", rows=5_000_000,
                  first_row=6_000_001, query_count=8_192)
    truth = [dict(dataset=name, **common)
             for name in ("deep", "turing")]
    sweep = [
        dict(dataset="deep", **common, shard_rows=50_000,
             k=30, m=32, ef_construction=200, ef_search=150),
        dict(dataset="deep", **common, shard_rows=50_000,
             k=30, m=24, ef_construction=160, ef_search=45),
        dict(dataset="turing", **common, shard_rows=50_000,
             k=30, m=32, ef_construction=200, ef_search=150),
    ]
    write(root / "truth_cases.tsv", truth[0].keys(), truth)
    write(root / "sweep_cases.tsv", sweep[0].keys(), sweep)
    print(f"truth={len(truth)} sweep={len(sweep)}")


if __name__ == "__main__":
    main(Path(sys.argv[1]), Path(sys.argv[2]))
