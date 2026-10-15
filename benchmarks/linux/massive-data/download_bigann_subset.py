"""Download a verified BigANN float32 prefix without a second full copy."""

import argparse
import contextlib
import fcntl
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
CHECKPOINT_BYTES = 64 * 1024 * 1024


def inspect_remote(url, expected_bytes):
    request = urllib.request.Request(url, method="HEAD")
    with urllib.request.urlopen(request, timeout=60) as response:
        length = int(response.headers["Content-Length"])
        etag = response.headers.get("ETag", "")
        ranges = response.headers.get("Accept-Ranges", "")
    if length != expected_bytes or ranges.lower() != "bytes" or not etag:
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


def write_json(path, value):
    temporary = path.with_name(path.name + ".tmp")
    with temporary.open("w", encoding="utf-8") as output:
        json.dump(value, output, indent=2, sort_keys=True)
        output.write("\n")
        output.flush()
        os.fsync(output.fileno())
    temporary.replace(path)


def read_json(path):
    with path.open(encoding="utf-8") as source:
        return json.load(source)


@contextlib.contextmanager
def exclusive_download(directory):
    with (directory / ".download.lock").open("a+b") as guard:
        try:
            fcntl.flock(guard, fcntl.LOCK_EX | fcntl.LOCK_NB)
        except BlockingIOError as error:
            raise RuntimeError(
                f"Another download owns {directory}") from error
        yield


def drop_cache(handle, start, length):
    if not length or not hasattr(os, "posix_fadvise"):
        return
    try:
        os.posix_fadvise(
            handle.fileno(), start, length, os.POSIX_FADV_DONTNEED)
    except OSError:
        pass


def verify_partial_tail(url, partial, full_bytes, etag):
    position = partial.stat().st_size
    if not position:
        return
    start = max(0, position - CHECKPOINT_BYTES)
    request = urllib.request.Request(
        url, headers={
            "Range": f"bytes={start}-{position - 1}",
            "If-Range": etag,
        })
    with urllib.request.urlopen(request, timeout=120) as response:
        expected = f"bytes {start}-{position - 1}/{full_bytes}"
        if (response.status != 206 or
                response.headers.get("Content-Range") != expected or
                response.headers.get("ETag", etag) != etag):
            raise RuntimeError("Source changed while verifying partial file")
        mismatch = False
        with partial.open("rb") as saved:
            saved.seek(start)
            remaining = position - start
            while remaining:
                count = min(READ_BYTES, remaining)
                remote = response.read(count)
                if len(remote) != count or remote != saved.read(count):
                    mismatch = True
                    break
                remaining -= count
    if mismatch:
        with partial.open("r+b") as output:
            output.truncate(start)
            output.flush()
            os.fsync(output.fileno())
        print(f"Rechecking partial tail from byte {start}", flush=True)


def download_range(url, partial, target_bytes, full_bytes, etag):
    failures = 0
    while partial.stat().st_size < target_bytes:
        position = partial.stat().st_size
        request = urllib.request.Request(
            url, headers={
                "Range": f"bytes={position}-{target_bytes - 1}",
                "If-Range": etag,
            })
        try:
            with urllib.request.urlopen(request, timeout=120) as response:
                expected = (f"bytes {position}-{target_bytes - 1}/"
                            f"{full_bytes}")
                actual = response.headers.get("Content-Range", "")
                received_etag = response.headers.get("ETag", etag)
                if (response.status != 206 or actual != expected or
                        received_etag != etag):
                    raise RuntimeError("Server did not honor exact byte range")
                with partial.open("ab") as output:
                    last_checkpoint = position
                    while True:
                        block = response.read(READ_BYTES)
                        if not block:
                            break
                        output.write(block)
                        if output.tell() > target_bytes:
                            raise RuntimeError("Server sent extra bytes")
                        if output.tell() - last_checkpoint >= CHECKPOINT_BYTES:
                            output.flush()
                            os.fsync(output.fileno())
                            drop_cache(
                                output, last_checkpoint,
                                output.tell() - last_checkpoint)
                            last_checkpoint = output.tell()
                    output.flush()
                    os.fsync(output.fileno())
                    drop_cache(
                        output, last_checkpoint,
                        output.tell() - last_checkpoint)
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
        last_drop = 0
        while block := source.read(READ_BYTES):
            digest.update(block)
            if source.tell() - last_drop >= CHECKPOINT_BYTES:
                drop_cache(source, last_drop, source.tell() - last_drop)
                last_drop = source.tell()
        drop_cache(source, last_drop, source.tell() - last_drop)
    return digest.hexdigest()


def source_identity(dataset, source, rows, columns, target_bytes, etag):
    return {
        "dataset": dataset, "rows": rows, "columns": columns,
        "bytes": target_bytes, "source_url": source["url"],
        "source_etag": etag, "source_terms": source["terms"],
    }


def complete_manifest(path, identity, seconds, data_file):
    record = dict(identity)
    record.update({
        "format": "little-endian float32 fbin",
        "sha256": checksum(data_file),
        "download_seconds": seconds,
        "path": str(data_file),
    })
    write_json(path, record)
    return record


def check_complete(final, manifest, meta, dataset, rows, columns,
                   target_bytes, preflight):
    check_local(final, rows, columns, target_bytes)
    if not manifest.exists():
        if preflight or not meta.exists():
            raise RuntimeError("Completed file has no manifest; inspect it")
        identity = read_json(meta)
        if (identity.get("dataset") != dataset or
                identity.get("rows") != rows or
                identity.get("bytes") != target_bytes or
                identity.get("columns") != columns):
            raise RuntimeError("Recovery identity does not match the file")
        complete_manifest(manifest, identity, None, final)
    record = read_json(manifest)
    if (record.get("dataset") != dataset or
            record.get("rows") != rows or
            record.get("bytes") != target_bytes or
            record.get("columns") != columns or
            checksum(final) != record.get("sha256")):
        raise RuntimeError("Completed file fails manifest verification")
    print(f"VERIFIED {final}", flush=True)


def run_download(args, source, columns, target_bytes, full_bytes, directory):
    final = directory / f"base.{args.rows}.fbin"
    partial = directory / f"base.{args.rows}.fbin.part"
    meta = directory / f"{partial.name}.meta.json"
    manifest_path = directory / "manifest.json"
    if final.exists():
        check_complete(final, manifest_path, meta, args.dataset, args.rows,
                       columns, target_bytes, args.preflight_only)
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
    identity = source_identity(args.dataset, source, args.rows, columns,
                               target_bytes, etag)
    if partial.exists() and partial.stat().st_size and not meta.exists():
        raise RuntimeError("Partial file has no source identity; cannot resume")
    if meta.exists() and read_json(meta) != identity:
        raise RuntimeError("Partial file source identity has changed")
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
    if not meta.exists():
        write_json(meta, identity)
    if not partial.exists():
        partial.touch(exist_ok=False)
    verify_partial_tail(source["url"], partial, full_bytes, etag)
    download_range(source["url"], partial, target_bytes, full_bytes, etag)
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
    partial.rename(final)
    manifest = complete_manifest(
        manifest_path, identity, round(time.monotonic() - started, 3), final)
    print("DONE " + json.dumps(manifest, sort_keys=True), flush=True)


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
    if args.reserve_gb < 0:
        parser.error("--reserve-gb must not be negative")
    source = SOURCES[args.dataset]
    columns = source["columns"]
    target_bytes = 8 + args.rows * columns * 4
    full_bytes = 8 + TOTAL_ROWS * columns * 4
    directory = args.output_root / args.dataset / str(args.rows)
    if args.preflight_only:
        args.output_root.mkdir(parents=True, exist_ok=True)
        run_download(args, source, columns, target_bytes, full_bytes,
                     directory)
        return
    directory.mkdir(parents=True, exist_ok=True)
    with exclusive_download(directory):
        run_download(args, source, columns, target_bytes, full_bytes,
                     directory)


if __name__ == "__main__":
    main()
