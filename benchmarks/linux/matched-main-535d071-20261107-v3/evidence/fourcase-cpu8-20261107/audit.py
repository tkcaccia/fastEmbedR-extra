"""Local manifest audit of four completed resident CPU8 benchmark cases."""

import hashlib
import json
import math
from pathlib import Path


ROOT = Path(__file__).resolve().parent
SOURCE = ROOT / "source"
JOBS = {
    "flowrepository_umap_cpu8_d3_s4_matched_535d071":
        ("1607319", 27, 52262316),
    "imagenet_umap_cpu8_d3_s4_matched_535d071":
        ("1607318", 34, 10653388),
    "flowrepository_tsne_cpu8_d2_s4_matched_535d071":
        ("1607345", 24, 37009756),
    "imagenet_tsne_cpu8_d2_s4_matched_535d071":
        ("1607344", 31, 7537260),
}


def sha(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()


def finite(value):
    return type(value) in (int, float) and math.isfinite(value)


def inspect(name, job, array_task, output_size, cases):
    case = cases[name]
    folder = ROOT / name
    p, i, m, r = (json.loads((folder / (part + ".json")).read_text())
                  for part in ("provenance", "input_identity", "memory",
                               "metrics"))
    issues = []
    expected = {
        "case_sha256": sha(SOURCE / "cases" / (name + ".json")),
        "routes_sha256": sha(SOURCE / "routes.json"),
        "worker_sha256": sha(SOURCE / "matched_worker.R"),
        "package_commit": "535d071849945db3fa550d3c50f80633b91748cc",
        "slurm_job_id": job,
        "slurm_array_task_id": str(array_task),
        "status": "completed", "exit_code": 0,
    }
    for key, value in expected.items():
        if p.get(key) != value:
            issues.append("provenance." + key)
    if i.get("actual_sha256") != case["input_sha256"] or \
            i.get("expected_sha256") != case["input_sha256"] or \
            i.get("status") != "verified":
        issues.append("input_identity")
    if m.get("scope") != "slurm_job_cgroup" or \
            not finite(m.get("peak_ram_bytes")) or \
            m["peak_ram_bytes"] <= 0 or \
            m.get("after", {}).get("job_id") != job:
        issues.append("memory")
    science = {
        "case_id": name, "dataset": case["dataset"],
        "method": case["method"], "n_rows": case["expected_rows"],
        "n_columns": case["expected_columns"],
        "dimensions": case["dimensions"], "cores": 8,
        "cores_effective": 8, "backend": "cpu",
        "input_precision": "float32",
        "preprocess_precision": "float32",
        "input_sha256": case["input_sha256"],
    }
    for key, value in science.items():
        if r.get(key) != value:
            issues.append("metrics." + key)
    if not str(r.get("observed_backend", "")).startswith("cpu"):
        issues.append("observed_backend")
    for key in ("load_seconds", "preprocess_seconds", "graph_seconds",
                "fit_seconds", "quality_seconds", "write_seconds"):
        if not finite(r.get(key)) or r[key] < 0:
            issues.append("timing." + key)
    for key in ("trustworthiness", "label_accuracy"):
        value = r.get("quality", {}).get(key)
        if not finite(value) or not 0 <= value <= 1:
            issues.append("quality." + key)
    if output_size <= 0:
        issues.append("output_missing")
    return {"case_id": name, "job_id": job,
            "status": "manifest_pass" if not issues else "manifest_fail",
            "issues": issues, "fit_seconds": r.get("fit_seconds"),
            "peak_ram_bytes": m.get("peak_ram_bytes"),
            "quality": r.get("quality"),
            "output_bytes_stat_only": output_size}


def main():
    cases = {row["case_id"]: row for line in
             (SOURCE / "cases.jsonl").read_text().splitlines()
             if (row := json.loads(line))}
    rows = [inspect(name, *values, cases) for name, values in JOBS.items()]
    report = {"scope": "small JSON manifests plus remote output stat; "
               "RDS content not independently read",
              "source_sha256": {
                  "routes": sha(SOURCE / "routes.json"),
                  "worker": sha(SOURCE / "matched_worker.R"),
              },
              "scheduler": {
                  "1607318_27": {"job_id_raw": "1607319",
                                 "state": "COMPLETED", "exit": "0:0"},
                  "1607318_34": {"job_id_raw": "1607318",
                                 "state": "COMPLETED", "exit": "0:0"},
                  "1607344_24": {"job_id_raw": "1607345",
                                 "state": "COMPLETED", "exit": "0:0"},
                  "1607344_31": {"job_id_raw": "1607344",
                                 "state": "COMPLETED", "exit": "0:0"},
              },
              "cases": rows}
    (ROOT / "report.json").write_text(json.dumps(report, indent=2) + "\n")
    print(json.dumps({row["case_id"]: row["issues"] for row in rows},
                     indent=2))
    return 0 if all(row["status"] == "manifest_pass" for row in rows) else 1


if __name__ == "__main__":
    raise SystemExit(main())
