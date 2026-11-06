"""Remove the verified full Deep1B payload after a checked 100M extract."""

import hashlib
import json
import os
import struct
import time
from pathlib import Path


ROOT = Path("/Users/silvanopiazza/Documents/Stefano/fastEmbedR-mac-20261031")
SOURCE = ROOT / "data/BigANN/deep/1000000000/base.1000000000.fbin"
SUBSET = ROOT / "data/BigANN/deep/mod10-100000000/base.mod10.100000000.fbin"
RECORD = ROOT / "deep1b-100m-v1/full_source_retirement.json"
EXIT = ROOT / "deep1b-100m-v1/extract.exit"
SOURCE_SHA = "1178bb266619c2d7882795861772b50cb0e2bf111a3b786a188aa3ea6137c7c4"
SOURCE_BYTES = 384_000_000_008
SUBSET_BYTES = 38_400_000_008
ROW_BYTES = 384


def digest(path):
    result = hashlib.sha256()
    with path.open("rb") as stream:
        for block in iter(lambda: stream.read(16 * 1024 * 1024), b""):
            result.update(block)
    return result.hexdigest()


def checked_rows():
    with SOURCE.open("rb") as original, SUBSET.open("rb") as chosen:
        for j in (0, 1, 49_999_999, 99_999_998, 99_999_999):
            original.seek(8 + (10 * (j + 1) - 1) * ROW_BYTES)
            chosen.seek(8 + j * ROW_BYTES)
            if original.read(ROW_BYTES) != chosen.read(ROW_BYTES):
                raise RuntimeError(f"Subset row {j} differs")


def write_record(record):
    pending = RECORD.with_suffix(".json.part")
    with pending.open("x") as stream:
        json.dump(record, stream, indent=2, sort_keys=True)
        stream.write("\n")
        stream.flush()
        os.fsync(stream.fileno())
    pending.replace(RECORD)


def main():
    if RECORD.exists() or EXIT.read_text().strip() != "0":
        raise RuntimeError("Retirement record exists or extract failed")
    full_meta = json.loads((SOURCE.parent / "manifest.json").read_text())
    small_meta = json.loads((SUBSET.parent / "manifest.json").read_text())
    if (SOURCE.stat().st_size != SOURCE_BYTES or
            SUBSET.stat().st_size != SUBSET_BYTES or
            full_meta["sha256"] != SOURCE_SHA or
            small_meta["source_sha256"] != SOURCE_SHA or
            small_meta["selection"] !=
            "one-based row i where i % 10 == 0"):
        raise RuntimeError("Deep1B source or subset metadata differs")
    with SUBSET.open("rb") as stream:
        if stream.read(8) != struct.pack("<II", 100_000_000, 96):
            raise RuntimeError("Subset fbin header differs")
    checked_rows()
    if digest(SOURCE) != SOURCE_SHA:
        raise RuntimeError("Full source SHA256 differs")
    if digest(SUBSET) != small_meta["sha256"]:
        raise RuntimeError("Subset SHA256 differs")
    record = {
        "status": "verified_before_deletion",
        "time_utc": time.strftime("%Y-%m-%dT%H:%M:%SZ", time.gmtime()),
        "source_path": str(SOURCE),
        "source_bytes": SOURCE_BYTES,
        "source_sha256": SOURCE_SHA,
        "subset_path": str(SUBSET),
        "subset_bytes": SUBSET_BYTES,
        "subset_sha256": small_meta["sha256"],
        "selection": small_meta["selection"],
        "authorization": "User requested 100M subset and full-source removal",
    }
    write_record(record)
    SOURCE.unlink()
    record["status"] = "full_source_removed"
    record["time_utc"] = time.strftime(
        "%Y-%m-%dT%H:%M:%SZ", time.gmtime())
    write_record(record)
    print(f"full_source_removed={not SOURCE.exists()}", flush=True)
    print(f"subset_sha256={small_meta['sha256']}", flush=True)


if __name__ == "__main__":
    main()
