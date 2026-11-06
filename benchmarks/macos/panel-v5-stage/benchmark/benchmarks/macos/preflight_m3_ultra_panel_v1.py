#!/usr/bin/env python3
"""Read-only input and space check for the M3 Ultra manuscript panel."""

import argparse
import hashlib
import json
import platform
import shutil
from pathlib import Path


STEFANO = Path("/Users/silvanopiazza/Documents/Stefano")
CAMPAIGN = STEFANO / "fastEmbedR-mac-20261031"
MANIFEST = Path(__file__).with_name("M3_ULTRA_LOCAL_INPUTS_SHA256_20261101.txt")
INPUTS = {
    "COIL20": "COIL20_float32.RData",
    "USPS": "USPS_float32.RData",
    "MNIST": "MNIST_float32.RData",
    "FashionMNIST": "FashionMNIST_float32.RData",
    "MetRef": "MetRef_float32.RData",
    "mass41": "mass41_float32.RData",
    "flow18": "flow18_float32.RData",
    "imagenet": "imagenet_float32.RData",
    "FlowRepository_FR-FCM-ZYRM_files":
        "van_unen_FR-FCM-ZYRM_float32.RData",
    "TabulaMuris": "TabulaMuris_float32.RData",
    "Macosko2015_retina": "Macosko2015_retina_float32.RData",
}


def expected_hashes(path):
    result = {}
    for line in path.read_text().splitlines():
        digest, name = line.split(maxsplit=1)
        name = Path(name).name
        if name in result or len(digest) != 64:
            raise ValueError(f"Invalid or duplicate manifest entry: {name}")
        int(digest, 16)
        result[name] = digest.lower()
    missing = set(INPUTS.values()) - result.keys()
    if missing:
        raise ValueError(f"Missing expected hashes: {sorted(missing)}")
    return result


def file_hash(path):
    digest = hashlib.sha256()
    with path.open("rb") as stream:
        for block in iter(lambda: stream.read(8 * 1024 * 1024), b""):
            digest.update(block)
    return digest.hexdigest()


def inspect_input(data_root, dataset, filename, expected, verify_hash):
    candidates = [p for p in data_root.glob(f"*/{filename}") if p.is_file()]
    row = {"dataset": dataset, "expected_sha256": expected}
    if len(candidates) != 1:
        row["status"] = "missing" if not candidates else "ambiguous"
        row["paths"] = [str(p) for p in candidates]
        return row
    path = candidates[0]
    if not path.resolve().is_relative_to(data_root.resolve()):
        row["status"] = "outside_data_root"
        row["path"] = str(path)
        return row
    row.update(path=str(path), bytes=path.stat().st_size)
    if verify_hash:
        row["sha256"] = file_hash(path)
        row["status"] = ("verified" if row["sha256"] == expected
                         else "hash_mismatch")
    else:
        row["status"] = "present_unverified"
    return row


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--campaign-root", type=Path, default=CAMPAIGN)
    parser.add_argument("--expected-manifest", type=Path, default=MANIFEST)
    parser.add_argument("--dataset", choices=["all", *INPUTS], default="all")
    parser.add_argument("--verify-hash", action="store_true")
    args = parser.parse_args()
    root = args.campaign_root.resolve()
    if platform.system() == "Darwin" and not root.is_relative_to(STEFANO):
        parser.error("Mac campaign root must be under Stefano")
    data_root = root / "data"
    if not data_root.is_dir():
        parser.error(f"Missing input directory: {data_root}")
    expected = expected_hashes(args.expected_manifest)
    names = INPUTS if args.dataset == "all" else {args.dataset: INPUTS[args.dataset]}
    rows = [inspect_input(data_root, name, filename, expected[filename],
                          args.verify_hash) for name, filename in names.items()]
    free = shutil.disk_usage(root).free
    report = {
        "campaign_root": str(root),
        "free_gib": round(free / 1024**3, 2),
        "hashes_checked": args.verify_hash,
        "inputs": rows,
        "status": ("inputs_verified" if all(r["status"] == "verified"
                                      for r in rows) else "incomplete"),
        "note": "Input check only; resource and benchmark admission remain separate.",
    }
    print(json.dumps(report, indent=2))
    return 0 if report["status"] == "inputs_verified" else 1


if __name__ == "__main__":
    raise SystemExit(main())
