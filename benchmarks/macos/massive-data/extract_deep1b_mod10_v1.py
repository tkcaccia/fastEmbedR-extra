"""Extract one-based Deep1B rows divisible by ten, with full-file hashes."""

import argparse
import hashlib
import json
import os
import shutil
import struct
import time
from pathlib import Path

import numpy as np


ROWS = 1_000_000_000
COLUMNS = 96
KEEP = ROWS // 10
ROW_BYTES = 4 * COLUMNS
BLOCK_ROWS = 100_000
SOURCE_BYTES = 8 + ROWS * ROW_BYTES
OUTPUT_BYTES = 8 + KEEP * ROW_BYTES
STEFANO = Path("/Users/silvanopiazza/Documents/Stefano")


def hash_file(path):
    digest = hashlib.sha256()
    with path.open("rb") as stream:
        for block in iter(lambda: stream.read(16 * 1024 * 1024), b""):
            digest.update(block)
    return digest.hexdigest()


def verify_rows(source, output):
    positions = (0, 1, KEEP // 2, KEEP - 2, KEEP - 1)
    with source.open("rb") as original, output.open("rb") as subset:
        for selected in positions:
            original.seek(8 + (10 * (selected + 1) - 1) * ROW_BYTES)
            subset.seek(8 + selected * ROW_BYTES)
            if original.read(ROW_BYTES) != subset.read(ROW_BYTES):
                raise RuntimeError(f"Selected row {selected} differs")


def write_manifest(path, record):
    pending = path.with_suffix(path.suffix + ".part")
    with pending.open("x") as stream:
        json.dump(record, stream, indent=2, sort_keys=True)
        stream.write("\n")
        stream.flush()
        os.fsync(stream.fileno())
    pending.replace(path)


def extract(source, target, source_sha, reserve_bytes):
    started = time.time()
    if source.stat().st_size != SOURCE_BYTES:
        raise RuntimeError("Source has an unexpected byte count")
    with source.open("rb") as stream:
        header = stream.read(8)
    if header != struct.pack("<II", ROWS, COLUMNS):
        raise RuntimeError("Source has an unexpected fbin header")
    if target.exists() or target.with_suffix(".fbin.part").exists():
        raise RuntimeError("Subset output already exists")
    if shutil.disk_usage(target.parent).free < OUTPUT_BYTES + reserve_bytes:
        raise RuntimeError("Insufficient free space for subset and reserve")
    partial = target.with_suffix(".fbin.part")
    source_hash = hashlib.sha256()
    subset_hash = hashlib.sha256()
    output_header = struct.pack("<II", KEEP, COLUMNS)
    with source.open("rb") as original, partial.open("xb") as subset:
        source_hash.update(original.read(8))
        subset.write(output_header)
        subset_hash.update(output_header)
        for block in range(ROWS // BLOCK_ROWS):
            raw = original.read(BLOCK_ROWS * ROW_BYTES)
            if len(raw) != BLOCK_ROWS * ROW_BYTES:
                raise RuntimeError("Source ended before expected row count")
            source_hash.update(raw)
            selected = np.frombuffer(raw, dtype=np.uint8).reshape(
                -1, 10, ROW_BYTES)[:, 9, :].copy().tobytes()
            subset.write(selected)
            subset_hash.update(selected)
            if block % 100 == 99:
                if shutil.disk_usage(target.parent).free < reserve_bytes:
                    raise RuntimeError("Free-space reserve was crossed")
                print(f"blocks={block + 1}/10000", flush=True)
        if original.read(1):
            raise RuntimeError("Source exceeds expected row count")
        subset.flush()
        os.fsync(subset.fileno())
    if source_hash.hexdigest() != source_sha:
        raise RuntimeError("Full Deep1B source SHA256 differs from manifest")
    if partial.stat().st_size != OUTPUT_BYTES:
        raise RuntimeError("Subset has an unexpected byte count")
    with partial.open("rb") as stream:
        if stream.read(8) != output_header:
            raise RuntimeError("Subset header differs")
    verify_rows(source, partial)
    if hash_file(partial) != subset_hash.hexdigest():
        raise RuntimeError("Independent subset SHA256 differs")
    partial.replace(target)
    write_manifest(target.parent / "manifest.json", {
        "source_path": str(source),
        "source_sha256": source_sha,
        "source_bytes": SOURCE_BYTES,
        "selection": "one-based row i where i % 10 == 0",
        "rows": KEEP,
        "columns": COLUMNS,
        "format": "little-endian float32 fbin",
        "bytes": OUTPUT_BYTES,
        "sha256": subset_hash.hexdigest(),
        "elapsed_seconds": round(time.time() - started, 3),
        "output_path": str(target),
    })
    print(f"verified_subset_sha256={subset_hash.hexdigest()}", flush=True)
    print(f"elapsed_seconds={round(time.time() - started, 3)}", flush=True)


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--source", type=Path, required=True)
    parser.add_argument("--source-manifest", type=Path, required=True)
    parser.add_argument("--output-dir", type=Path, required=True)
    parser.add_argument("--reserve-gb", type=int, default=40)
    args = parser.parse_args()
    source = args.source.resolve(strict=True)
    output_dir = args.output_dir.resolve()
    if not source.is_relative_to(STEFANO) or not output_dir.is_relative_to(
            STEFANO):
        raise RuntimeError("All Mac files must stay under Stefano")
    if args.reserve_gb < 20:
        raise RuntimeError("Reserve must be at least 20 GB")
    manifest = json.loads(args.source_manifest.read_text())
    if manifest.get("path") != str(source):
        raise RuntimeError("Source manifest path differs")
    if manifest.get("bytes") != SOURCE_BYTES:
        raise RuntimeError("Source manifest size differs")
    output_dir.mkdir(parents=True, exist_ok=False)
    target = output_dir / "base.mod10.100000000.fbin"
    extract(source, target, manifest["sha256"], args.reserve_gb * 10**9)


if __name__ == "__main__":
    main()
