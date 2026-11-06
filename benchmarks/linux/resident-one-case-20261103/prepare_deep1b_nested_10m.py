"""Prepare the exact resident HPC Deep1B 10M input on the Mac."""

from __future__ import annotations

import argparse
import hashlib
import json
from pathlib import Path
import struct
import sys

from policy import DEEP1B_SOURCE_SHA256


SOURCE_ROWS = 100_000_000
COLUMNS = 96
OUTPUT_ROWS = 10_000_000
ROW_BYTES = COLUMNS * 4
SOURCE_SELECTION = "one-based row i where i % 10 == 0"
OUTPUT_SELECTION = "one-based source row i where i % 100 == 0"
MAC_ROOT = Path("/Users/silvanopiazza/Documents/Stefano")


def sha256_file(path: Path) -> str:
    digest = hashlib.sha256()
    with path.open("rb") as stream:
        for block in iter(lambda: stream.read(8 * 1024 * 1024), b""):
            digest.update(block)
    return digest.hexdigest()


def extract_nested(source: Path, output: Path, rows: int,
                   columns: int, block_rows: int = 100_000) -> str:
    """Copy every tenth one-based source row into a new fbin."""
    if rows < 10 or rows % 10 or block_rows < 10 or \
            block_rows % 10 or columns < 1:
        raise ValueError("Rows and block size must be divisible by ten.")
    row_bytes = columns * 4
    digest = hashlib.sha256()
    with source.open("rb") as origin, output.open("xb") as target:
        header = origin.read(8)
        if header != struct.pack("<ii", rows, columns):
            raise ValueError("Source fbin header changed.")
        output_header = struct.pack("<ii", rows // 10, columns)
        target.write(output_header)
        digest.update(output_header)
        for first in range(0, rows, block_rows):
            count = min(block_rows, rows - first)
            block = origin.read(count * row_bytes)
            if len(block) != count * row_bytes:
                raise ValueError("Source fbin ended early.")
            selected = bytearray((count // 10) * row_bytes)
            for index in range(count // 10):
                begin = (10 * index + 9) * row_bytes
                selected[index * row_bytes:(index + 1) * row_bytes] = \
                    block[begin:begin + row_bytes]
            target.write(selected)
            digest.update(selected)
        if origin.read(1):
            raise ValueError("Source fbin has trailing bytes.")
    return digest.hexdigest()


def prepare(source: Path, source_manifest: Path, output_dir: Path) -> Path:
    if sys.platform == "darwin" and not output_dir.resolve().is_relative_to(
            MAC_ROOT):
        raise ValueError("Mac output must stay under Stefano.")
    manifest = json.loads(source_manifest.read_text())
    expected_size = 8 + SOURCE_ROWS * ROW_BYTES
    if source.stat().st_size != expected_size or \
            manifest.get("bytes") != expected_size or \
            manifest.get("rows") != SOURCE_ROWS or \
            manifest.get("columns") != COLUMNS or \
            manifest.get("selection") != SOURCE_SELECTION or \
            manifest.get("format") != "little-endian float32 fbin" or \
            manifest.get("source_sha256") != DEEP1B_SOURCE_SHA256 or \
            sha256_file(source) != manifest.get("sha256"):
        raise ValueError("The verified Deep1B 100M source changed.")
    output_dir.mkdir(parents=True, exist_ok=True)
    output = output_dir / "base.mod100.10000000.fbin"
    part = output.with_suffix(".fbin.part")
    manifest_path = output_dir / "manifest.json"
    manifest_part = output_dir / "manifest.json.part"
    if any(path.exists() for path in
           (output, part, manifest_path, manifest_part)):
        raise FileExistsError("Deep1B 10M output already exists.")
    digest = extract_nested(source, part, SOURCE_ROWS, COLUMNS)
    expected_output_size = 8 + OUTPUT_ROWS * ROW_BYTES
    if part.stat().st_size != expected_output_size:
        raise ValueError("Deep1B 10M output has the wrong byte count.")
    result = {
        "bytes": expected_output_size,
        "columns": COLUMNS,
        "format": "little-endian float32 fbin",
        "rows": OUTPUT_ROWS,
        "selection": OUTPUT_SELECTION,
        "sha256": digest,
        "source_rows": 1_000_000_000,
        "source_sha256": DEEP1B_SOURCE_SHA256,
        "parent_sha256": manifest["sha256"],
    }
    manifest_part.write_text(json.dumps(result, indent=2) + "\n")
    part.rename(output)
    manifest_part.rename(manifest_path)
    return output


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("source", type=Path)
    parser.add_argument("source_manifest", type=Path)
    parser.add_argument("output_dir", type=Path)
    arguments = parser.parse_args()
    print(prepare(arguments.source, arguments.source_manifest,
                  arguments.output_dir))
