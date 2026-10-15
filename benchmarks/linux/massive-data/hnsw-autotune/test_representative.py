#!/usr/bin/env python3

import csv
import hashlib
import json
import os
import tempfile
import unittest
from pathlib import Path
from unittest.mock import patch

import audit_representative
import make_cases_representative
import make_cases_large_probe
import full_graph_gate
import followup_after_representative


def write_csv(path, rows):
    with path.open("w", newline="") as handle:
        writer = csv.DictWriter(handle, rows[0])
        writer.writeheader()
        writer.writerows(rows)


def read_tsv(path):
    with path.open(newline="") as handle:
        return list(csv.DictReader(handle, delimiter="\t"))


def read_csv(path):
    with path.open(newline="") as handle:
        return list(csv.DictReader(handle))


class RepresentativeTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.addCleanup(self.temp.cleanup)
        self.root = Path(self.temp.name) / "pilot"
        with patch.object(make_cases_representative, "validate_input",
                          return_value={"rows": 1_000_000_000}):
            make_cases_representative.main(self.root, Path(self.temp.name))

    def test_separated_windows_and_shard_sizes(self):
        cases = read_tsv(self.root / "sweep_cases.tsv")
        self.assertEqual(len(cases), 30)
        self.assertEqual({int(row["shard_rows"]) for row in cases},
                         {50_000, 250_000})
        self.assertEqual({int(row["first_row"]) for row in cases},
                         {1_000_001, 450_000_001, 995_000_001})

    def test_audit_selects_only_fully_passing_candidate(self):
        (self.root / "source.sha256").write_text("a" * 64 + "  image\n")
        truth = read_tsv(self.root / "truth_cases.tsv")
        (self.root / "truth").mkdir()
        (self.root / "sweep").mkdir()
        for item in truth:
            stem = item["dataset"] + "_" + item["scope"]
            (self.root / "truth" / (stem + ".rds")).write_text("truth")
            (self.root / "truth" / (stem + "_timing.csv")).write_text("x")
        cases = read_tsv(self.root / "sweep_cases.tsv")
        for index, case in enumerate(cases):
            rows = []
            for split in ("tune", "holdout"):
                rows.append(dict(dataset=case["dataset"],
                    scope=case["scope"], fit_rows=case["rows"],
                    shard_rows=case["shard_rows"], m=case["m"],
                    ef_construction=case["ef_construction"],
                    ef_search=case["ef_search"], split=split,
                    mean_recall=1, n_queries=1024, image_sha256="a" * 64,
                    build_seconds=int(case["m"]), query_seconds=1,
                    rss_peak_bytes=1000, cpu_model="same"))
            write_csv(self.root / "sweep" / f"case_{index:03d}.csv", rows)
            detail = [dict(row=i, split="tune" if i <= 1024 else
                           "holdout", recall=1) for i in range(1, 2049)]
            write_csv(self.root / "sweep" /
                      f"case_{index:03d}_queries.csv", detail)
        with patch.object(audit_representative, "lower_bound",
                          return_value=1):
            self.assertTrue(audit_representative.audit(self.root))
        result = json.loads((self.root /
                             "audit_representative.json").read_text())
        self.assertEqual(result["selected_datasets"], ["deep", "turing"])
        chosen = read_csv(self.root / "selected.csv")
        self.assertEqual(len(chosen), 4)
        gates = full_graph_gate.plan(self.root)
        self.assertTrue(all(row["status"] ==
                            "GATED_MINIMUM_IO_OVER_5TB" for row in gates
                            if row["rows"] == 1_000_000_000 and
                            row["devices"] == 1))
        self.assertTrue(all(row["status"] ==
                            "UNSUPPORTED_FULL_GRAPH_MULTI_GPU"
                            for row in gates if row["devices"] == 2))
        large = Path(self.temp.name) / "large"
        with patch.object(make_cases_large_probe, "validate_input",
                          return_value={"rows": 1_000_000_000}):
            make_cases_large_probe.main(large, self.root,
                                        Path(self.temp.name))
        cases = read_tsv(large / "sweep_cases.tsv")
        self.assertEqual(len(cases), 4)
        self.assertEqual({int(row["rows"]) for row in cases},
                         {100_000_000, 1_000_000_000})

    def test_full_row_plot_is_dependent_on_campaign_audit(self):
        base = Path(self.temp.name)
        image = base / "singularity/fastembedr_cuda.sif"
        image.parent.mkdir()
        image.write_text("image")
        suite = base / "benchmark_scripts/massive-data/visualization"
        suite.mkdir(parents=True)
        for name in ("render_full_layouts.R", "slurm_full_layouts.sh"):
            (suite / name).write_text("script")
        campaign = base / "campaign"
        campaign.mkdir()
        (campaign / "image.sha256").write_text(
            hashlib.sha256(b"image").hexdigest() + "  image\n")
        (campaign / "jobs.tsv").write_text(
            "kind\tjob_id\tcase_count\naudit\t432\t1\n")
        bin_dir = base / "bin"
        bin_dir.mkdir()
        log = base / "sbatch_args.txt"
        sbatch = bin_dir / "sbatch"
        sbatch.write_text(f"#!/bin/sh\nprintf '%s\\n' \"$*\" > "
                          f"{log}\necho 433\n")
        sbatch.chmod(0o755)
        with patch.dict(os.environ, {"PATH": str(bin_dir) + ":" +
                        os.environ["PATH"]}):
            job, out = followup_after_representative.queue_plot(
                base, campaign, "deep", "cpu", "fresh5m_3d")
        self.assertEqual(job, "433")
        self.assertIn("--dependency=afterany:432", log.read_text())
        self.assertTrue((Path(out) / "source.sha256").is_file())


if __name__ == "__main__":
    unittest.main()
