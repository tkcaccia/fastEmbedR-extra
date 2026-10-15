#!/usr/bin/env python3
"""Prespecified, separated BigANN windows for HNSW calibration."""

import json
import sys
from pathlib import Path

from make_cases import validate_input, write


WINDOWS = (("rep_early", 1_000_001),
           ("rep_middle", 450_000_001),
           ("rep_late", 995_000_001))
SETTINGS = {
    "deep": ((50_000, 24, 160, 45), (50_000, 32, 200, 150),
             (50_000, 32, 200, 240), (250_000, 32, 200, 150),
             (250_000, 48, 320, 240)),
    "turing": ((50_000, 32, 200, 150), (50_000, 32, 200, 240),
               (50_000, 48, 320, 480), (250_000, 48, 320, 480),
               (250_000, 64, 400, 960)),
}


def main(root, data_root):
    inputs = {name: validate_input(data_root, name)
              for name in ("deep", "turing")}
    root.mkdir(parents=True, exist_ok=False)
    (root / "input_identity.json").write_text(
        json.dumps(inputs, indent=2) + "\n", encoding="utf-8")
    truth, sweep = [], []
    for dataset in ("deep", "turing"):
        for scope, first_row in WINDOWS:
            common = dict(dataset=dataset, scope=scope, rows=5_000_000,
                          first_row=first_row, query_count=2_048)
            truth.append(common)
            for shard_rows, m, efc, efs in SETTINGS[dataset]:
                sweep.append(dict(**common, shard_rows=shard_rows, k=30,
                                  m=m, ef_construction=efc,
                                  ef_search=efs))
    write(root / "truth_cases.tsv", truth[0].keys(), truth)
    write(root / "sweep_cases.tsv", sweep[0].keys(), sweep)
    print(f"truth={len(truth)} sweep={len(sweep)}")


if __name__ == "__main__":
    main(Path(sys.argv[1]), Path(sys.argv[2]))
