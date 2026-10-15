"""Verify CUDA-visible IDs against measured hardware UUIDs."""

import csv
import json
import tempfile
import unittest
from pathlib import Path

from gpu_memory import verify_devices


class GpuMemoryIdentityTest(unittest.TestCase):
    def test_two_requested_devices_must_both_be_observed(self):
        with tempfile.TemporaryDirectory() as directory:
            memory = Path(directory) / "gpu_memory.csv"
            mapping = Path(directory) / "gpu_device_map.csv"
            with mapping.open("w", newline="") as stream:
                writer = csv.DictWriter(stream,
                                        ("logical_device", "uuid"))
                writer.writeheader()
                writer.writerows((
                    {"logical_device": 0, "uuid": "GPU-a"},
                    {"logical_device": 1, "uuid": "GPU-b"},
                ))
            with memory.open("w", newline="") as stream:
                writer = csv.DictWriter(stream,
                    ("status", "peak_per_device_json"))
                writer.writeheader()
                writer.writerow({"status": "ok",
                    "peak_per_device_json": json.dumps(
                        {"GPU-a": 100, "GPU-b": 200})})
            verify_devices(memory, mapping)
            with memory.open("w", newline="") as stream:
                writer = csv.DictWriter(stream,
                    ("status", "peak_per_device_json"))
                writer.writeheader()
                writer.writerow({"status": "ok",
                    "peak_per_device_json": json.dumps({"GPU-a": 100})})
            with self.assertRaisesRegex(ValueError,
                                        "requested device UUIDs"):
                verify_devices(memory, mapping)
            for invalid in (float("nan"), True, "100"):
                with memory.open("w", newline="") as stream:
                    writer = csv.DictWriter(stream,
                        ("status", "peak_per_device_json"))
                    writer.writeheader()
                    writer.writerow({"status": "ok",
                        "peak_per_device_json": json.dumps(
                            {"GPU-a": 100, "GPU-b": invalid})})
                with self.assertRaisesRegex(ValueError,
                                            "requested device UUIDs"):
                    verify_devices(memory, mapping)

    def test_uuid_case_does_not_change_device_identity(self):
        with tempfile.TemporaryDirectory() as directory:
            memory = Path(directory) / "gpu_memory.csv"
            mapping = Path(directory) / "gpu_device_map.csv"
            with mapping.open("w", newline="") as stream:
                writer = csv.DictWriter(stream,
                                        ("logical_device", "uuid"))
                writer.writeheader()
                writer.writerows((
                    {"logical_device": 0, "uuid": "GPU-A1"},
                    {"logical_device": 1, "uuid": "GPU-B2"},
                ))
            with memory.open("w", newline="") as stream:
                writer = csv.DictWriter(stream,
                    ("status", "peak_per_device_json"))
                writer.writeheader()
                writer.writerow({"status": "ok",
                    "peak_per_device_json": json.dumps(
                        {"GPU-a1": 100, "GPU-b2": 200})})
            verify_devices(memory, mapping)
            with memory.open("w", newline="") as stream:
                writer = csv.DictWriter(stream,
                    ("status", "peak_per_device_json"))
                writer.writeheader()
                writer.writerow({"status": "ok",
                    "peak_per_device_json": json.dumps(
                        {"GPU-a1": 100, "GPU-A1": 200})})
            with self.assertRaisesRegex(ValueError,
                                        "requested device UUIDs"):
                verify_devices(memory, mapping)
            with memory.open("w", newline="") as stream:
                writer = csv.DictWriter(stream,
                    ("status", "peak_per_device_json"))
                writer.writeheader()
                writer.writerow({"status": "ok",
                    "peak_per_device_json": json.dumps(
                        {"GPU-a1": 100, "GPU-b2": 0})})
            with self.assertRaisesRegex(ValueError,
                                        "requested device UUIDs"):
                verify_devices(memory, mapping)


if __name__ == "__main__":
    unittest.main()
