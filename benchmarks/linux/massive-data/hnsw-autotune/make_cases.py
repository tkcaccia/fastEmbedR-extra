#!/usr/bin/env python3
"""Create the fixed, bounded Deep/Turing HNSW experiment matrix."""

import csv
import json
import struct
import sys
from pathlib import Path


def write(path, fields, rows):
    with path.open("w", newline="", encoding="utf-8") as stream:
        writer = csv.DictWriter(stream, fieldnames=fields, delimiter="\t")
        writer.writeheader()
        writer.writerows(rows)


def validate_input(data_root, dataset):
    columns = {"deep": 96, "turing": 100}[dataset]
    path = data_root / dataset / "1000000000" / "base.1000000000.fbin"
    expected = 8 + 1_000_000_000 * columns * 4
    if path.stat().st_size != expected:
        raise ValueError(f"Incomplete {dataset} file: {path}")
    with path.open("rb") as stream:
        if struct.unpack("<II", stream.read(8)) != (1_000_000_000, columns):
            raise ValueError(f"Invalid {dataset} fbin header")
    manifest = json.loads((path.parent / "manifest.json").read_text())
    digest = manifest.get("sha256", "")
    if (len(digest) != 64 or
            any(c not in "0123456789abcdef" for c in digest) or
            manifest.get("rows") != 1_000_000_000 or
            manifest.get("columns") != columns or
            manifest.get("bytes") != expected):
        raise ValueError(f"Invalid {dataset} download manifest")
    return {"path": str(path), "sha256": digest,
            "size_bytes": expected, "sha256_reverified_now": False}


def main(root, data_root):
    inputs = {name: validate_input(data_root, name)
              for name in ("deep", "turing")}
    root.mkdir(parents=True, exist_ok=False)
    (root / "input_identity.json").write_text(
        json.dumps(inputs, indent=2) + "\n", encoding="utf-8")
    truth = []
    sweep = []
    build = [(12, 60), (12, 80), (12, 160), (16, 100), (16, 200),
             (24, 160), (24, 320), (32, 200)]
    extra = [(12, 80), (16, 100), (24, 120),
             (24, 160), (32, 200)]
    for dataset in ("deep", "turing"):
        for scope, rows in (("pilot", 20000), ("scale", 1000000)):
            truth.append(dict(dataset=dataset, scope=scope, rows=rows))
            configs = [(20000, m, efc) for m, efc in build]
            if scope == "scale":
                configs += [(50000, m, efc) for m, efc in extra]
                configs += [(1000000, m, efc) for m, efc in extra]
            for shard, m, efc in configs:
                sweep.append(dict(dataset=dataset, scope=scope,
                                  rows=rows, shard_rows=shard,
                                  m=m, ef_construction=efc))
    write(root / "truth_cases.tsv", ("dataset", "scope", "rows"), truth)
    write(root / "sweep_cases.tsv", ("dataset", "scope", "rows",
          "shard_rows", "m", "ef_construction"), sweep)
    for name, cases in (("truth", truth), ("sweep", sweep)):
        for scope in ("pilot", "scale"):
            indices = [str(i) for i, case in enumerate(cases)
                       if case["scope"] == scope]
            (root / f"{scope}_{name}.indices").write_text(
                ",".join(indices) + "\n", encoding="utf-8")
    print(f"truth={len(truth)} sweep={len(sweep)}")


if __name__ == "__main__":
    main(Path(sys.argv[1]), Path(sys.argv[2]))
