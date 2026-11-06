#!/usr/bin/env python3
"""Verify the installed binary identity of a completed Mac 100M run."""

import hashlib
import json
import re
import sys
from datetime import datetime, timezone
from pathlib import Path


def require(ok, message):
    if not ok:
        raise ValueError(message)


def digest(path):
    result = hashlib.sha256()
    with path.open("rb") as stream:
        while block := stream.read(8 * 1024 * 1024):
            result.update(block)
    return result.hexdigest()


def main():
    if len(sys.argv) != 2:
        raise SystemExit("usage: script.py DEEP1B_RUN_ROOT")
    run = Path(sys.argv[1]).resolve()
    require(str(run).startswith(
            "/Users/silvanopiazza/Documents/Stefano/"),
            "Identity audit must stay under Stefano")
    require((run / "postprocess/postprocess.exit").read_text().strip() ==
            "0", "Independent 100M structural audit has not passed")
    queue = run / "queue100m"
    require((queue / "queue.exit").read_text().strip() == "0",
            "100M calculation did not complete")
    lines = (queue / "installed_dll.sha256").read_text().splitlines()
    require(len(lines) == 1, "Installed DLL identity has multiple rows")
    match = re.fullmatch(r"([0-9a-f]{64})\s+(.+)", lines[0])
    require(match is not None, "Installed DLL identity is malformed")
    expected, recorded_path = match.groups()
    dll = run / "Rlib/fastEmbedR/libs/fastEmbedR.so"
    require(Path(recorded_path).resolve() == dll.resolve() and
            dll.is_file(), "Installed DLL path changed")
    observed = digest(dll)
    require(observed == expected, "Installed DLL changed after 100M run")
    description = (run / "Rlib/fastEmbedR/DESCRIPTION").read_text()
    require(re.search(r"^Package:\s*fastEmbedR\s*$", description, re.M)
            and re.search(r"^Version:\s*0\.1\s*$", description, re.M),
            "Installed package name or version changed")
    require((queue / "install.log").stat().st_size > 0,
            "Package installation evidence is missing")
    output = run / "installed-identity-audit-v1"
    output.mkdir(exist_ok=False)
    (output / "identity.json").write_text(json.dumps({
        "status": "passed", "installed_dll_sha256": observed,
        "installed_dll_path": str(dll), "package": "fastEmbedR",
        "version": "0.1", "completed_utc":
            datetime.now(timezone.utc).isoformat(),
    }, indent=2, sort_keys=True) + "\n")
    print("Verified installed fastEmbedR binary identity")


if __name__ == "__main__":
    main()
