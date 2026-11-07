"""Start one bounded source-locked Mac diagnostic and return its PID."""

import json
from pathlib import Path
import platform
import subprocess
import sys

from policy import valid_case


root = Path(__file__).resolve().parent
case_path = root / "case.json"
case = json.loads(case_path.read_text())
if platform.system() != "Darwin" or not valid_case(case):
    raise SystemExit("Diagnostic requires a valid Mac case.")
if Path(case["output_dir"]).exists():
    raise SystemExit("Diagnostic output already exists.")
log = (root / "controller.log").open("xb")
process = subprocess.Popen(
    [sys.executable, str(root / "run_case.py"), str(case_path)],
    cwd=root, stdin=subprocess.DEVNULL, stdout=log,
    stderr=subprocess.STDOUT, start_new_session=True,
)
(root / "controller.pid").write_text(f"{process.pid}\n")
print(f"diagnostic_pid={process.pid}")
