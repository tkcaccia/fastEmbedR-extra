"""Check the required fastEmbedR capability grid and its evidence links."""

from __future__ import annotations

import argparse
import csv
import itertools
import json
from collections import Counter
from pathlib import Path


METHODS = ("pca", "tsne_2d", "tsne_3d", "umap_2d", "umap_3d",
           "leiden", "louvain")
BACKENDS = ("cpu_single", "cpu_multi", "cuda_single", "cuda_multi",
            "metal_single")
STORAGE = ("resident", "file_backed")
SCOPES = ("full", "landmark")
FINAL_STATUSES = {"verified", "failing", "limited by measured resources",
                  "not implemented"}
FIELDS = ("method", "backend", "storage", "fit_scope")


def audit(path: Path, repository: Path, final: bool = False) -> dict:
    with path.open(newline="") as stream:
        rows = list(csv.DictReader(stream))
    expected = set(itertools.product(METHODS, BACKENDS, STORAGE, SCOPES))
    found = [tuple(row.get(key) for key in FIELDS) for row in rows]
    counts = Counter(found)
    errors = []
    for key in sorted(expected - counts.keys()):
        errors.append(f"missing combination: {key}")
    for key in sorted(counts.keys() - expected):
        errors.append(f"unexpected combination: {key}")
    for key, count in sorted(counts.items()):
        if count != 1:
            errors.append(f"duplicate combination: {key} ({count})")
    statuses = Counter()
    for number, row in enumerate(rows, 2):
        status = row.get("qualification_status", "")
        statuses[status] += 1
        if status not in FINAL_STATUSES | {"unqualified"}:
            errors.append(f"row {number}: unknown status {status!r}")
        if final and status == "unqualified":
            errors.append(f"row {number}: still unqualified")
        evidence = [item.strip() for item in
                    row.get("evidence", "").split(";") if item.strip()]
        if status in FINAL_STATUSES and not evidence:
            errors.append(f"row {number}: final status lacks evidence")
        if status == "verified" and row.get("remaining_gate", "").strip():
            errors.append(f"row {number}: verified route has a remaining gate")
        for item in evidence:
            candidate = repository / item
            if Path(item).is_absolute() or not candidate.resolve().is_relative_to(
                    repository.resolve()) or not candidate.is_file():
                errors.append(f"row {number}: invalid evidence {item!r}")
    return {"rows": len(rows), "expected_rows": len(expected),
            "statuses": dict(sorted(statuses.items())),
            "errors": errors}


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--final", action="store_true")
    args = parser.parse_args()
    root = Path(__file__).resolve().parents[2]
    report = audit(root / "benchmarks/capability-matrix-20261105.csv",
                   root, args.final)
    print(json.dumps(report, indent=2))
    return int(bool(report["errors"]))


if __name__ == "__main__":
    raise SystemExit(main())
