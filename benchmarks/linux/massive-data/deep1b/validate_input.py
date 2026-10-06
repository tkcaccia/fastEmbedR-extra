#!/usr/bin/env python3
"""Validate a completed Deep1B download without reading 384 GB each run."""

import argparse
import hashlib
import json
import struct
from pathlib import Path

ROWS = 1_000_000_000
COLUMNS = 96
BYTES = 8 + ROWS * COLUMNS * 4


def validate(path, verify_hash=False):
    if path.name != f"base.{ROWS}.fbin" or path.stat().st_size != BYTES:
        raise ValueError("Expected the completed, full Deep1B .fbin file")
    with path.open("rb") as stream:
        if struct.unpack("<II", stream.read(8)) != (ROWS, COLUMNS):
            raise ValueError("Deep1B header differs from 1B x 96 float32")
    manifest = path.parent / "manifest.json"
    record = json.loads(manifest.read_text(encoding="utf-8"))
    expected = {"dataset": "deep", "rows": ROWS,
                "columns": COLUMNS, "bytes": BYTES}
    if any(record.get(key) != value for key, value in expected.items()):
        raise ValueError("Completed download manifest does not match input")
    digest = record.get("sha256", "")
    if len(digest) != 64 or any(c not in "0123456789abcdef" for c in digest):
        raise ValueError("Completed download manifest lacks a SHA-256")
    if verify_hash:
        with path.open("rb") as stream:
            check = hashlib.file_digest(stream, "sha256").hexdigest()
        if check != digest:
            raise ValueError("Deep1B data failed full SHA-256 verification")
    return {"input": str(path), "rows": ROWS, "columns": COLUMNS,
            "bytes": BYTES, "manifest_sha256": digest,
            "hash_verified_now": verify_hash}


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("input", type=Path)
    parser.add_argument("--verify-sha256", action="store_true")
    args = parser.parse_args()
    print(json.dumps(validate(args.input, args.verify_sha256),
                     sort_keys=True))


if __name__ == "__main__":
    main()
