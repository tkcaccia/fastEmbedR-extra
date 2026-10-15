#!/usr/bin/env python3
"""Summarize every declared file-backed case without hiding missing work."""
import csv
import math
import pathlib
import struct
import sys


def read_one(path):
    if not path.is_file():
        return None
    with path.open(newline="") as handle:
        rows = list(csv.DictReader(handle))
    return rows[0] if len(rows) == 1 else None


def write_rows(path, rows):
    fields = sorted({key for row in rows for key in row})
    with path.open("w", newline="") as handle:
        writer = csv.DictWriter(handle, fieldnames=fields)
        writer.writeheader()
        writer.writerows(rows)


def sampled_rows(path, rows, width, count=256):
    indices = [round(i * (rows - 1) / (count - 1))
               for i in range(count)]
    values = []
    with pathlib.Path(path).open("rb") as handle:
        for index in indices:
            handle.seek(index * width * 4)
            data = handle.read(width * 4)
            if len(data) != width * 4:
                raise ValueError("Incomplete paired output")
            code = "f" if width == 2 else "I"
            values.append(struct.unpack(f"<{width}{code}", data))
    return values


def paired_agreement(left, right, rows, method):
    width = 30 if method == "knn" else 2
    a = sampled_rows(left, rows, width)
    b = sampled_rows(right, rows, width)
    if method == "knn":
        return sum(len(set(x) & set(y)) / width
                   for x, y in zip(a, b)) / len(a)
    distances = lambda values: [
        math.dist(values[i], values[j])
        for i in range(len(values)) for j in range(i)]
    x, y = distances(a), distances(b)
    mx, my = sum(x) / len(x), sum(y) / len(y)
    xx = sum((v - mx) ** 2 for v in x)
    yy = sum((v - my) ** 2 for v in y)
    return sum((u - mx) * (v - my) for u, v in zip(x, y)) / math.sqrt(
        xx * yy) if xx > 0 and yy > 0 else float("nan")


def agreement_or_blank(left, right, rows, method):
    if left.get("status") != "PASS" or right.get("status") != "PASS":
        return ""
    try:
        return paired_agreement(left["output_path"],
                                right["output_path"], rows, method)
    except (OSError, ValueError, KeyError):
        return ""


def main():
    suite = pathlib.Path(__file__).resolve().parent
    output = pathlib.Path(sys.argv[1]) / "file_backed"
    output.mkdir(parents=True, exist_ok=True)
    with (suite / "cases.csv").open(newline="") as handle:
        cases = list(csv.DictReader(handle))
    rows = []
    for case in cases:
        result = read_one(output / case["id"] / "result.csv")
        if result is None:
            result = {"id": case["id"], "status": "MISSING",
                      "error": "No valid result.csv"}
        gpu = output / case["id"] / "measurement.gpu_memory.csv"
        peaks = {}
        if gpu.is_file():
            with gpu.open(newline="") as handle:
                for sample in csv.DictReader(handle):
                    device = sample["gpu_id"]
                    value = int(sample["incremental_mib"])
                    peaks[device] = max(peaks.get(device, 0), value)
        result["gpu_peak_incremental_mib"] = sum(peaks.values()) if peaks \
            else ""
        result["gpu_device_peaks_mib"] = ";".join(
            f"{key}:{value}" for key, value in sorted(peaks.items()))
        expected_devices = len(case["devices"].split(":"))
        if (case["backend"] == "cuda" and result["status"] == "PASS" and
                len(peaks) != expected_devices):
            result["status"] = "FAIL"
            result["error"] = "Missing per-device GPU memory samples"
        rows.append({**case, **result})
    write_rows(output / "summary.csv", rows)
    by_id = {row["id"]: row for row in rows}
    pairs = []
    for left, right in (("flow18_full_umap", "flow18_landmark_umap"),
                        ("flow18_full_tsne", "flow18_landmark_tsne")):
        first, second = by_id[left], by_id[right]
        indices = [output / name / "quality_rows.csv"
                   for name in (left, right)]
        agreement = agreement_or_blank(first, second, 50000,
                                       first["method"])
        same_rows = (all(path.is_file() for path in indices) and
                     indices[0].read_bytes() == indices[1].read_bytes())
        ok = (first["status"] == second["status"] == "PASS" and
              same_rows and agreement != "" and
              math.isfinite(agreement) and
              first.get("source_manifest_sha256") ==
              second.get("source_manifest_sha256"))
        pairs.append({"comparison": first["method"],
                      "status": "PASS" if ok else "INCOMPLETE",
                      "same_quality_rows": same_rows,
                      "layout_distance_correlation": agreement,
                      "full_seconds": first.get("elapsed_seconds", ""),
                      "landmark_seconds": second.get("elapsed_seconds", ""),
                      "full_rss_bytes": first.get("peak_rss_bytes", ""),
                      "landmark_rss_bytes": second.get("peak_rss_bytes", ""),
                      "full_gpu_peak_mib": first.get(
                          "gpu_peak_incremental_mib", ""),
                      "landmark_gpu_peak_mib": second.get(
                          "gpu_peak_incremental_mib", ""),
                      "full_preserve_at_30": first.get(
                          "preserve_at_30_sample", ""),
                      "landmark_preserve_at_30": second.get(
                          "preserve_at_30_sample", "")})
    write_rows(output / "full_landmark_pairs.csv", pairs)
    for method in ("pca", "knn", "umap", "tsne"):
        left = by_id[f"multi_{method}_1gpu"]
        right = by_id[f"multi_{method}_2gpu"]
        agreement = agreement_or_blank(left, right, 100000, method)
        threshold = 0.99 if method == "knn" else 0.95 if \
            method == "pca" else -1.0
        ok = (left["status"] == right["status"] == "PASS" and
              agreement != "" and math.isfinite(agreement) and
              agreement >= threshold and
              left.get("source_manifest_sha256") ==
              right.get("source_manifest_sha256") and
              left.get("gpu_devices_observed") == "0" and
              right.get("gpu_devices_observed") == "0:1")
        pairs.append({"comparison": f"multi_gpu_{method}",
                      "status": "PASS" if ok else "INCOMPLETE",
                      "one_gpu_seconds": left.get("elapsed_seconds", ""),
                      "two_gpu_seconds": right.get("elapsed_seconds", ""),
                      "paired_agreement": agreement,
                      "one_gpu_rss_bytes": left.get("peak_rss_bytes", ""),
                      "two_gpu_rss_bytes": right.get("peak_rss_bytes", ""),
                      "one_gpu_peak_mib": left.get(
                          "gpu_peak_incremental_mib", ""),
                      "two_gpu_peak_mib": right.get(
                          "gpu_peak_incremental_mib", ""),
                      "one_gpu_preserve_at_30": left.get(
                          "preserve_at_30_sample", ""),
                      "two_gpu_preserve_at_30": right.get(
                          "preserve_at_30_sample", "")})
    write_rows(output / "paired_comparisons.csv", pairs)
    counts = {status: sum(row["status"] == status for row in rows)
              for status in ("PASS", "FAIL", "BLOCKED", "TIMEOUT",
                             "MISSING")}
    report = [f"{status}={count}" for status, count in counts.items()]
    report.extend(f"{row['id']}: {row['status']} {row.get('error', '')}"
                  for row in rows if row["status"] != "PASS")
    report.extend(f"{row['comparison']}: {row['status']}" for row in pairs
                  if row["status"] != "PASS")
    (output / "audit.txt").write_text("\n".join(report) + "\n")
    print("\n".join(report))
    if len(sys.argv) > 2 and sys.argv[2] == "--strict":
        return 0 if counts["PASS"] == len(cases) and all(
            row["status"] == "PASS" for row in pairs) else 1
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
