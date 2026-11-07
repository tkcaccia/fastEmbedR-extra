#!/usr/bin/env python3
"""Verify the immutable Mac panel before admitting its first case."""

import hashlib
import json
from pathlib import Path
import shutil
import subprocess
import sys

from policy import under_stefano, valid_case


ROOT = Path(__file__).resolve().parent
STEFANO = Path("/Users/silvanopiazza/Documents/Stefano")
COMMIT = "535d071849945db3fa550d3c50f80633b91748cc"


def digest(path):
    value = hashlib.sha256()
    with path.open("rb") as stream:
        for block in iter(lambda: stream.read(8 * 1024 * 1024), b""):
            value.update(block)
    return value.hexdigest()


def check():
    if sys.platform != "darwin" or not under_stefano(str(ROOT)):
        raise RuntimeError("Preflight must run inside Stefano on macOS")
    summary = json.loads((ROOT / "plan-summary.json").read_text())
    if summary["package_commit"] != COMMIT or summary["cases"] != 693 or \
            summary["storage_mode"] != "resident" or \
            summary["fit_scope"] != "full":
        raise RuntimeError("Plan identity or scope differs")
    if digest(ROOT / "cases.jsonl") != summary["cases_sha256"]:
        raise RuntimeError("Case manifest changed")
    cases = [json.loads(line) for line in
             (ROOT / "cases.jsonl").read_text().splitlines()]
    queue = (ROOT / "queue.txt").read_text().splitlines()
    if len(cases) != 693 or len(queue) != 693 or \
            len(set(queue)) != 693 or (ROOT / "queue.lock").exists():
        raise RuntimeError("Queue is incomplete, duplicated, or already locked")
    if (ROOT / "results").exists():
        raise RuntimeError("New panel result directory already exists")
    by_name = {case["case_id"] + ".json": case for case in cases}
    if set(queue) != set(by_name):
        raise RuntimeError("Queue differs from case manifest")
    sources = {}
    inputs = {}
    for name in queue:
        case = by_name[name]
        if not valid_case(case) or \
                json.loads((ROOT / "manifests" / name).read_text()) != case:
            raise RuntimeError("Case policy or staged manifest differs: " + name)
        if case["output_dir"] != str(ROOT / "results" / case["case_id"]):
            raise RuntimeError("Result destination differs: " + name)
        sources[(case["source_dir"], case["source_sha256"],
                 case["dll_sha256"])] = True
        key = (case["input_path"], case["input_sha256"],
               case["expected_rows"], case["expected_columns"])
        inputs[key] = True
    if len(sources) != 1 or len(inputs) != 11:
        raise RuntimeError("Source or dataset inventory is inconsistent")
    source, source_sha, dll_sha = next(iter(sources))
    source = Path(source)
    if digest(source / "source.tar.xz") != source_sha or \
            digest(source / "library/fastEmbedR/libs/fastEmbedR.so") != dll_sha:
        raise RuntimeError("Installed package identity differs")
    for path, expected_sha, _, _ in inputs:
        if digest(Path(path)) != expected_sha:
            raise RuntimeError("Dataset checksum differs: " + path)
    if shutil.disk_usage(STEFANO).free < 150 * 1024 ** 3:
        raise RuntimeError("Insufficient free disk for the panel")
    command = ["/Library/Frameworks/R.framework/Resources/bin/Rscript",
               "--vanilla", "-e",
               "library(fastEmbedR);stopifnot(packageVersion('fastEmbedR')=='0.1')"]
    env = dict(__import__("os").environ,
               R_LIBS=str(source / "library") + ":" +
               str(STEFANO / "data/Rlib"))
    subprocess.run(command, env=env, check=True, timeout=30,
                   stdout=subprocess.DEVNULL)
    return {"cases": len(cases), "datasets": len(inputs),
            "source_sha256": source_sha, "dll_sha256": dll_sha,
            "free_gib": round(shutil.disk_usage(STEFANO).free / 1024**3, 1)}


if __name__ == "__main__":
    print(json.dumps(check(), sort_keys=True))
