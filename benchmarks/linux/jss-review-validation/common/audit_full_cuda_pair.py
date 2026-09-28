#!/usr/bin/env python3
import csv
import math
import os
import sys
from pathlib import Path

DATASETS = (
    "COIL20", "USPS", "FashionMNIST",
    "FlowRepository_FR-FCM-ZYRM_files", "flow18", "MNIST",
    "imagenet", "MetRef", "mass41", "TabulaMuris",
    "Macosko2015_retina",
)
METHODS = (
    ("r_cuda", "fastembedr_tsne"),
    ("python_cuda", "cuml_tsne"),
    ("r_cuda", "fastembedr_umap"),
    ("python_cuda", "cuml_umap"),
)


def first_row(path):
    with path.open(newline="", encoding="utf-8") as handle:
        return next(csv.DictReader(handle))


def audit(campaign, inputs, outputs):
    failures = []
    methods = METHODS
    if os.environ.get("INCLUDE_NOMAD") == "TRUE":
        methods += (("python_cuda", "nomad"),)
    for dataset in DATASETS:
        try:
            manifest = first_row(inputs / dataset / "manifest.csv")
            n = int(manifest["source_n"])
            if int(manifest["benchmark_n"]) != n:
                raise ValueError("benchmark input is subsampled")
            if manifest["full_source"].lower() != "true":
                raise ValueError("full_source marker is not TRUE")
        except (OSError, ValueError, StopIteration) as error:
            failures.append(f"{dataset}: input {error}")
            continue
        for mode, method in methods:
            directory = outputs / "workflow_comparators" / mode
            directory = directory / dataset / method
            try:
                status = first_row(directory / "status.csv")
                result = first_row(directory / "result_with_quality.csv")
                if status["status"] != "success":
                    raise ValueError("fit status is not success")
                if int(result["n"]) != n:
                    raise ValueError("fit did not use every source row")
                if result["quality_analysis"] != "posthoc_R":
                    raise ValueError("quality was not calculated after fit")
                for field in ("elapsed_median_sec", "trustworthiness",
                              "preserve_at_30"):
                    if not math.isfinite(float(result[field])):
                        raise ValueError(f"non-finite {field}")
                if result["timing_eligible"].lower() != "true":
                    failures.append(
                        f"{dataset}/{method}: fit succeeded but "
                        "timing was not fully replicated"
                    )
                if not (directory / "embedding.csv").is_file():
                    raise ValueError("missing full embedding CSV")
                if not (directory / "quality.csv").is_file():
                    raise ValueError("missing R quality CSV")
                if method == "nomad":
                    if result["family"] != "nomad":
                        raise ValueError("NOMAD objective is mislabeled")
                    if not (directory / "embedding.png").is_file():
                        raise ValueError("missing R-style embedding plot")
            except (OSError, ValueError, KeyError, StopIteration) as error:
                failures.append(f"{dataset}/{method}: {error}")
        for family in ("tsne", "umap"):
            image = outputs / "cuda_comparison_live" / dataset
            panel = image / family
            if not (panel / "comparison.png").is_file():
                failures.append(f"{dataset}/{family}: missing paired plot")
            if family == "tsne" and os.environ.get("INCLUDE_NOMAD") == "TRUE":
                try:
                    with (panel / "comparison.csv").open(
                        newline="", encoding="utf-8"
                    ) as handle:
                        rows = list(csv.DictReader(handle))
                    if not any(row["method"] == "nomad" and
                               row["method_family"] == "nomad" and
                               row["status"] == "success" for row in rows):
                        raise ValueError("NOMAD panel is absent or mislabeled")
                except (OSError, ValueError, KeyError) as error:
                    failures.append(f"{dataset}/nomad-panel: {error}")
    with (campaign / "failures.tsv").open(encoding="utf-8") as handle:
        scheduler_failures = handle.read().splitlines()[1:]
    if scheduler_failures:
        failures.append(f"{len(scheduler_failures)} Slurm task failures")
    report = "PASS" if not failures else "FAIL\n" + "\n".join(failures)
    (campaign / "final_audit.txt").write_text(report + "\n")
    print(report)
    return not failures


if __name__ == "__main__":
    raise SystemExit(0 if audit(*(Path(p) for p in sys.argv[1:4])) else 1)
