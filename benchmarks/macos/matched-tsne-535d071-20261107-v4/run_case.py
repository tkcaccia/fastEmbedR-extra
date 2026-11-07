"""Run one versioned resident Mac case and record Metal optimizer stages."""

import hashlib
import json
import os
from pathlib import Path
import platform
import re
import signal
import subprocess
import sys
import time

from policy import under_stefano, valid_case


HERE = Path(__file__).resolve().parent
WORKER = HERE / "worker.R"
RSCRIPT = Path("/Library/Frameworks/R.framework/Resources/bin/Rscript")


def digest(path):
    value = hashlib.sha256()
    with Path(path).open("rb") as stream:
        for block in iter(lambda: stream.read(1024 * 1024), b""):
            value.update(block)
    return value.hexdigest()


def refuse(reason):
    print(json.dumps({"status": "policy_rejected", "reason": reason}),
          file=sys.stderr)
    return 78


def checked_identity(case):
    source = Path(case["source_dir"])
    files = ((case["input_path"], case["input_sha256"]),
             (source / "source.tar.xz", case["source_sha256"]),
             (source / "library/fastEmbedR/libs/fastEmbedR.so",
              case["dll_sha256"]))
    try:
        return all(Path(path).is_file() and digest(path) == expected
                   for path, expected in files)
    except OSError:
        return False


def command_output(command):
    try:
        result = subprocess.run(command, check=False, text=True,
                                capture_output=True, timeout=5)
        return result.stdout.strip() if result.returncode == 0 else None
    except (OSError, subprocess.TimeoutExpired):
        return None


def peak_rss(path):
    if not path.is_file():
        return None
    match = re.search(r"(\d+)\s+maximum resident set size",
                      path.read_text(errors="replace"))
    return int(match.group(1)) if match else None


def group_clear(pid):
    try:
        os.killpg(pid, 0)
        return False
    except ProcessLookupError:
        return True
    except PermissionError:
        return False


def write_atomic(path, value):
    temporary = path.with_suffix(path.suffix + ".tmp")
    temporary.write_text(json.dumps(value, indent=2) + "\n")
    temporary.replace(path)


def main(argv):
    if len(argv) != 1 or platform.system() != "Darwin":
        return refuse("One manifest on macOS is required.")
    case_path = Path(argv[0])
    if not under_stefano(str(case_path)) or not case_path.is_file():
        return refuse("Case manifest must be under Stefano.")
    try:
        case = json.loads(case_path.read_text())
    except (OSError, ValueError) as error:
        return refuse("Cannot read case manifest: " + str(error))
    if not valid_case(case):
        return refuse("Case violates the resident Mac contract.")
    output = Path(case["output_dir"])
    if output.name != case["case_id"] or output.exists():
        return refuse("Output path must be a new case-specific directory.")
    if not WORKER.is_file() or not RSCRIPT.is_file():
        return refuse("Reviewed R worker or R runtime is missing.")
    if not checked_identity(case):
        return refuse("Input or package identity differs from manifest.")
    try:
        output.mkdir(parents=True, exist_ok=False)
    except OSError as error:
        return refuse("Cannot create unique output: " + str(error))
    (output / "tmp").mkdir()
    environment = os.environ.copy()
    environment["R_LIBS"] = ":".join((
        str(Path(case["source_dir"]) / "library"),
        "/Users/silvanopiazza/Documents/Stefano/data/Rlib"))
    environment["TMPDIR"] = str(output / "tmp")
    # The 256 GiB Mac can safely bound one R worker well below physical RAM.
    # The old 16 GiB cap rejected full ImageNet before scientific execution.
    environment["R_MAX_VSIZE"] = "96G"
    environment["VECLIB_MAXIMUM_THREADS"] = "1"
    identity = {"case_sha256": digest(case_path),
                "worker_sha256": digest(WORKER),
                "runner_sha256": digest(__file__),
                "source_sha256": case["source_sha256"],
                "dll_sha256": case["dll_sha256"],
                "input_sha256": case["input_sha256"]}
    write_atomic(output / "provenance.json", identity)
    before_swap = command_output(["sysctl", "vm.swapusage"])
    started = time.monotonic()
    command = ["nice", "-n", "10", "/usr/bin/time", "-l", "-o",
               str(output / "time.native"), str(RSCRIPT), "--vanilla",
               str(WORKER), str(case_path), str(output)]
    with (output / "worker.log").open("wb") as log:
        child = subprocess.Popen(command, stdout=log,
                                 stderr=subprocess.STDOUT,
                                 env=environment, start_new_session=True)
        try:
            code = child.wait(timeout=case["timeout_seconds"])
            timed_out = False
        except subprocess.TimeoutExpired:
            try:
                os.killpg(child.pid, signal.SIGTERM)
            except ProcessLookupError:
                pass
            try:
                child.wait(timeout=15)
            except subprocess.TimeoutExpired:
                try:
                    os.killpg(child.pid, signal.SIGKILL)
                except ProcessLookupError:
                    pass
                try:
                    child.wait(timeout=15)
                except subprocess.TimeoutExpired:
                    pass
            code = 124
            timed_out = True
    cleanup_clear = group_clear(child.pid)
    result = {**identity, "case_id": case["case_id"],
              "status": "completed" if code == 0 and
              cleanup_clear and peak_rss(output / "time.native")
              is not None else "failed", "exit_code": code,
              "timed_out": timed_out, "cleanup_clear": cleanup_clear,
              "elapsed_seconds": round(time.monotonic() - started, 3),
              "peak_rss_bytes": peak_rss(output / "time.native"),
              "swap_before": before_swap,
              "swap_after": command_output(["sysctl", "vm.swapusage"])}
    write_atomic(output / "run.json", result)
    return 0 if result["status"] == "completed" else 1


if __name__ == "__main__":
    raise SystemExit(main(sys.argv[1:]))
