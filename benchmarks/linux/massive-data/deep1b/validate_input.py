#!/usr/bin/env python3
"""Validate a completed BigANN download without rereading the full file."""

import argparse
import hashlib
import json
import struct
from pathlib import Path

ROWS = 1_000_000_000
COLUMNS = {"deep": 96, "turing": 100}


def validate(path, verify_hash=False, dataset="deep"):
    if dataset not in COLUMNS:
        raise ValueError(f"Unsupported dataset: {dataset}")
    columns = COLUMNS[dataset]
    expected_bytes = 8 + ROWS * columns * 4
    if (path.name != f"base.{ROWS}.fbin" or
            path.stat().st_size != expected_bytes):
        raise ValueError(f"Expected the completed, full {dataset} .fbin file")
    with path.open("rb") as stream:
        if struct.unpack("<II", stream.read(8)) != (ROWS, columns):
            raise ValueError(f"{dataset} header differs from expected shape")
    manifest = path.parent / "manifest.json"
    record = json.loads(manifest.read_text(encoding="utf-8"))
    expected = {"dataset": dataset, "rows": ROWS,
                "columns": columns, "bytes": expected_bytes}
    if any(record.get(key) != value for key, value in expected.items()):
        raise ValueError("Completed download manifest does not match input")
    digest = record.get("sha256", "")
    if len(digest) != 64 or any(c not in "0123456789abcdef" for c in digest):
        raise ValueError("Completed download manifest lacks a SHA-256")
    if verify_hash:
        with path.open("rb") as stream:
            check = hashlib.file_digest(stream, "sha256").hexdigest()
        if check != digest:
            raise ValueError(f"{dataset} data failed full SHA-256 verification")
    return {"input": str(path), "dataset": dataset,
            "rows": ROWS, "columns": columns,
            "bytes": expected_bytes, "manifest_sha256": digest,
            "hash_verified_now": verify_hash}


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("input", type=Path)
    parser.add_argument("--dataset", choices=sorted(COLUMNS), default="deep")
    parser.add_argument("--verify-sha256", action="store_true")
    args = parser.parse_args()
    print(json.dumps(validate(args.input, args.verify_sha256,
                              args.dataset),
                     sort_keys=True))


if __name__ == "__main__":
    main()
