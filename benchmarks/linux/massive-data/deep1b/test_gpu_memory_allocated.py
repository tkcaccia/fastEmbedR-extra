#!/usr/bin/env python3
"""Small contract tests for the Slurm two-GPU memory monitor."""

import csv
import json
import tempfile
import unittest
from pathlib import Path
from unittest.mock import patch

import gpu_memory_allocated as monitor


class AllocatedMemoryTests(unittest.TestCase):
    @staticmethod
    def manifest(root, first=2, second=3):
        devices = [dict(backend="cuda", process_visible=True,
                        logical_id=0, physical_id=first,
                        uuid="GPU-two"),
                   dict(backend="cuda", process_visible=True,
                        logical_id=1, physical_id=second,
                        uuid="GPU-three")]
        (root / "hardware_manifest.json").write_text(
            json.dumps(dict(devices=devices)))

    def test_requires_two_distinct_allocated_gpus(self):
        self.assertEqual(monitor.allocated_indices(
            {"SLURM_JOB_GPUS": "2,3"}), (2, 3))
        for value in ("", "0", "0,0", "gpu0,gpu1", "0,1,2"):
            with self.subTest(value=value), self.assertRaises(ValueError):
                monitor.allocated_indices({"SLURM_JOB_GPUS": value})

    @patch("gpu_memory_allocated.subprocess.run")
    def test_reads_device_wide_usage(self, run):
        run.return_value.stdout = (
            "2, GPU-two, 101\n3, GPU-three, 203\n")
        self.assertEqual(monitor.device_memory(), {
            2: ("GPU-two", 101 * monitor.MIB),
            3: ("GPU-three", 203 * monitor.MIB),
        })

    def test_one_inactive_gpu_fails_evidence(self):
        baseline = {2: ("GPU-two", 100 * monitor.MIB),
                    3: ("GPU-three", 100 * monitor.MIB)}
        peaks = {2: 150 * monitor.MIB, 3: 100 * monitor.MIB}
        with tempfile.TemporaryDirectory() as path:
            root = Path(path)
            self.manifest(root)
            devices = monitor.visible_devices(root, (2, 3), baseline)
            monitor.record(root, devices, baseline, peaks, 10, 0, 0)
            summary = json.loads((root / "gpu_summary.json").read_text())
            with (root / "gpu_memory.csv").open(newline="") as stream:
                rows = list(csv.DictReader(stream))
        self.assertEqual(summary["status"],
                         "incomplete_device_evidence")
        self.assertEqual(summary["active_devices"], 1)
        self.assertEqual(rows[1]["delta_bytes"], "0")
        self.assertEqual(rows[1]["logical_id"], "1")
        self.assertEqual(rows[1]["physical_id"], "3")

    def test_both_active_gpus_pass_evidence(self):
        baseline = {2: ("GPU-two", 100 * monitor.MIB),
                    3: ("GPU-three", 110 * monitor.MIB)}
        peaks = {2: 150 * monitor.MIB, 3: 160 * monitor.MIB}
        with tempfile.TemporaryDirectory() as path:
            root = Path(path)
            self.manifest(root)
            devices = monitor.visible_devices(root, (2, 3), baseline)
            monitor.record(root, devices, baseline, peaks, 10, 0, 0)
            summary = json.loads((root / "gpu_summary.json").read_text())
        self.assertEqual(summary["status"], "two_devices_active")
        self.assertEqual(summary["active_devices"], 2)

    def test_manifest_mismatch_rejects_device_attribution(self):
        baseline = {2: ("GPU-two", 100 * monitor.MIB),
                    3: ("GPU-three", 110 * monitor.MIB)}
        with tempfile.TemporaryDirectory() as path:
            root = Path(path)
            self.manifest(root, first=3, second=2)
            with self.assertRaisesRegex(ValueError, "disagree"):
                monitor.visible_devices(root, (2, 3), baseline)

    def test_reordered_cuda_visibility_keeps_uuid_attribution(self):
        baseline = {2: ("GPU-two", 100 * monitor.MIB),
                    3: ("GPU-three", 110 * monitor.MIB)}
        peaks = {2: 130 * monitor.MIB, 3: 160 * monitor.MIB}
        with tempfile.TemporaryDirectory() as path:
            root = Path(path)
            (root / "hardware_manifest.json").write_text(json.dumps({
                "devices": [dict(backend="cuda", process_visible=True,
                    logical_id=0, physical_id=3, uuid="GPU-three"),
                    dict(backend="cuda", process_visible=True,
                    logical_id=1, physical_id=2, uuid="GPU-two")]}))
            devices = monitor.visible_devices(root, (2, 3), baseline)
            monitor.record(root, devices, baseline, peaks, 10, 0, 0)
            with (root / "gpu_memory.csv").open(newline="") as stream:
                rows = list(csv.DictReader(stream))
        self.assertEqual([(row["logical_id"], row["physical_id"],
                           row["delta_bytes"]) for row in rows],
                         [("0", "3", str(50 * monitor.MIB)),
                          ("1", "2", str(30 * monitor.MIB))])


if __name__ == "__main__":
    unittest.main()
