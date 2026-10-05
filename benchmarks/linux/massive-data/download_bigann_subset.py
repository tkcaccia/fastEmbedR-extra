"""Download a verified BigANN float32 prefix without a second full copy."""

import argparse
import hashlib
import json
import os
import shutil
import struct
import time
import urllib.request
from pathlib import Path


SOURCES = {
    "turing": {
        "url": ("https://comp21storage.z5.web.core.windows.net/comp21/"
                "MSFT-TURING-ANNS/base1b.fbin"),
        "columns": 100,
        "terms": "https://big-ann-benchmarks.com/MSFT-Turing-ANNS-terms.txt",
    },
    "deep": {
        "url": ("https://storage.yandexcloud.net/yandex-research/"
                "ann-datasets/DEEP/base.1B.fbin"),
        "columns": 96,
        "terms": "https://creativecommons.org/licenses/by/4.0/",
    },
}
TOTAL_ROWS = 1_000_000_000
READ_BYTES = 8 * 1024 * 1024


def inspect_remote(url, expected_bytes):
    request = urllib.request.Request(url, method="HEAD")
    with urllib.request.urlopen(request, timeout=60) as response:
        length = int(response.headers["Content-Length"])
        etag = response.headers.get("ETag", "")
        ranges = response.headers.get("Accept-Ranges", "")
    if length != expected_bytes or ranges.lower() != "bytes":
        raise RuntimeError("Remote size or range support differs from plan")
    return etag


def check_local(path, rows, columns, expected_bytes):
    if path.stat().st_size != expected_bytes:
        raise RuntimeError(f"Unexpected file size: {path}")
    with path.open("rb") as source:
        header = source.read(8)
    if len(header) != 8 or struct.unpack("<II", header) != (
            rows, columns):
        raise RuntimeError(f"Unexpected .fbin header: {path}")


def download_range(url, partial, target_bytes):
    failures = 0
    while partial.stat().st_size < target_bytes:
        position = partial.stat().st_size
        request = urllib.request.Request(
            url, headers={"Range": f"bytes={position}-{target_bytes - 1}"})
        try:
            with urllib.request.urlopen(request, timeout=120) as response:
                expected = f"bytes {position}-{target_bytes - 1}/"
                actual = response.headers.get("Content-Range", "")
                if response.status != 206 or not actual.startswith(expected):
                    raise RuntimeError("Server did not honor exact byte range")
                with partial.open("ab") as output:
                    while True:
                        block = response.read(READ_BYTES)
                        if not block:
                            break
                        output.write(block)
                        if output.tell() > target_bytes:
                            raise RuntimeError("Server sent extra bytes")
            if partial.stat().st_size == position:
                raise RuntimeError("Server returned an empty range")
            failures = 0
        except (OSError, TimeoutError) as error:
            failures += 1
            if failures >= 5:
                raise RuntimeError("Download failed after five retries") \
                    from error
            print(f"Retrying at byte {partial.stat().st_size}: {error}",
                  flush=True)
            time.sleep(5 * failures)


def checksum(path):
    digest = hashlib.sha256()
    with path.open("rb") as source:
        while block := source.read(READ_BYTES):
            digest.update(block)
    return digest.hexdigest()


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("dataset", choices=SOURCES)
    parser.add_argument("--rows", type=int, default=10_000_000)
    parser.add_argument("--output-root", type=Path, required=True)
    parser.add_argument("--reserve-gb", type=int, default=20)
    parser.add_argument("--preflight-only", action="store_true")
    args = parser.parse_args()
    if not 1 <= args.rows <= TOTAL_ROWS:
        parser.error("--rows must be between 1 and one billion")
    source = SOURCES[args.dataset]
    columns = source["columns"]
    target_bytes = 8 + args.rows * columns * 4
    full_bytes = 8 + TOTAL_ROWS * columns * 4
    directory = args.output_root / args.dataset / str(args.rows)
    if args.preflight_only:
        args.output_root.mkdir(parents=True, exist_ok=True)
    else:
        directory.mkdir(parents=True, exist_ok=True)
    final = directory / f"base.{args.rows}.fbin"
    partial = directory / f"base.{args.rows}.fbin.part"
    if final.exists() and not args.preflight_only:
        check_local(final, args.rows, columns, target_bytes)
        print(f"EXISTS {final}", flush=True)
        return
    if partial.exists() and partial.stat().st_size > target_bytes:
        raise RuntimeError("Partial download is larger than the target")
    remaining = target_bytes - (
        partial.stat().st_size if partial.exists() else 0)
    free = shutil.disk_usage(
        args.output_root if args.preflight_only else directory).free
    required = remaining + args.reserve_gb * 1_000_000_000
    if free < required:
        raise RuntimeError(f"Need {required} free bytes; only {free} remain")
    etag = inspect_remote(source["url"], full_bytes)
    if args.preflight_only:
        print(json.dumps({
            "dataset": args.dataset, "rows": args.rows,
            "columns": columns, "target_bytes": target_bytes,
            "remaining_bytes": remaining, "free_bytes": free,
            "reserve_bytes": args.reserve_gb * 1_000_000_000,
            "source_url": source["url"], "source_etag": etag,
            "source_terms": source["terms"],
            "output": str(final), "status": "READY",
        }, sort_keys=True), flush=True)
        return
    print(f"START {args.dataset} rows={args.rows} remaining={remaining} "
          f"free={free} etag={etag}", flush=True)
    started = time.monotonic()
    if not partial.exists():
        partial.touch(exist_ok=False)
    download_range(source["url"], partial, target_bytes)
    if partial.stat().st_size != target_bytes:
        raise RuntimeError("Download stopped before the requested prefix")
    with partial.open("rb") as source_file:
        stored_rows, stored_columns = struct.unpack(
            "<II", source_file.read(8))
    if stored_columns != columns or stored_rows not in (
            TOTAL_ROWS, args.rows):
        raise RuntimeError("Unexpected header in partial download")
    if stored_rows == TOTAL_ROWS:
        with partial.open("r+b") as output:
            output.write(struct.pack("<I", args.rows))
            output.flush()
            os.fsync(output.fileno())
    check_local(partial, args.rows, columns, target_bytes)
    sha256 = checksum(partial)
    partial.rename(final)
    manifest = {
        "dataset": args.dataset, "rows": args.rows,
        "columns": columns, "format": "little-endian float32 fbin",
        "source_url": source["url"], "source_etag": etag,
        "source_terms": source["terms"],
        "bytes": target_bytes, "sha256": sha256,
        "download_seconds": round(time.monotonic() - started, 3),
        "path": str(final),
    }
    (directory / "manifest.json").write_text(
        json.dumps(manifest, indent=2) + "\n", encoding="utf-8")
    print("DONE " + json.dumps(manifest, sort_keys=True), flush=True)


if __name__ == "__main__":
    main()
