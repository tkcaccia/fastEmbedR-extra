"""Verify CUDA-visible IDs against measured hardware UUIDs."""

import csv
import json
import subprocess
import tempfile
import unittest
from pathlib import Path
from unittest.mock import Mock, patch

from gpu_memory import (monitor, process_running, query_gpu_processes,
                        sample, verify_devices)


class GpuMemoryIdentityTest(unittest.TestCase):
    def test_zombie_is_not_a_running_fit(self):
        with patch("gpu_memory.Path.read_text",
                   return_value="123 (R worker) Z 1 2 3"):
            self.assertFalse(process_running(123))
        with patch("gpu_memory.Path.read_text",
                   return_value="123 (R worker) R 1 2 3"):
            self.assertTrue(process_running(123))
        with patch("gpu_memory.Path.read_text",
                   side_effect=FileNotFoundError):
            self.assertFalse(process_running(123))

    def test_sampling_error_stops_and_marks_measurement_invalid(self):
        with tempfile.TemporaryDirectory() as directory:
            output = Path(directory) / "memory.csv"
            error = subprocess.TimeoutExpired("nvidia-smi", 10)
            with patch("gpu_memory.os.getpgid", return_value=123), \
                    patch("gpu_memory.process_running",
                          side_effect=[True, True]), \
                    patch("gpu_memory.sample", side_effect=[
                        (100, True, {"GPU-A": 100}, {456}), error]), \
                    patch("gpu_memory.time.sleep"):
                self.assertEqual(monitor(123, output), 1)
            with output.open(newline="") as stream:
                result = next(csv.DictReader(stream))
            self.assertEqual(result["status"], "unavailable")
            self.assertEqual(result["errors"], "1")

    def test_fit_exits_before_monitor_starts(self):
        with tempfile.TemporaryDirectory() as directory:
            output = Path(directory) / "memory.csv"
            with patch("gpu_memory.os.getpgid",
                       side_effect=ProcessLookupError), \
                    patch("gpu_memory.process_running",
                          return_value=False):
                self.assertEqual(monitor(123, output), 1)
            with output.open(newline="") as stream:
                result = next(csv.DictReader(stream))
            self.assertEqual(result["status"], "unavailable")
            self.assertEqual(result["samples"], "0")

    def test_single_gpu_sample_is_not_a_peak_measurement(self):
        with tempfile.TemporaryDirectory() as directory:
            output = Path(directory) / "memory.csv"
            with patch("gpu_memory.os.getpgid", return_value=123), \
                    patch("gpu_memory.process_running",
                          side_effect=[True, False]), \
                    patch("gpu_memory.sample", side_effect=[
                        (100, True, {"GPU-A": 100}, {456}),
                        (0, False, {}, set()),
                        (0, False, {}, set())]), \
                    patch("gpu_memory.time.sleep"):
                self.assertEqual(monitor(123, output), 1)
            with output.open(newline="") as stream:
                result = next(csv.DictReader(stream))
            self.assertEqual(result["status"], "unavailable")
            self.assertEqual(result["matched_samples"], "1")

    def test_lingering_gpu_context_blocks_success(self):
        with tempfile.TemporaryDirectory() as directory:
            output = Path(directory) / "memory.csv"
            owned = (100, True, {"GPU-A": 100}, {456})
            with patch("gpu_memory.os.getpgid", return_value=123), \
                    patch("gpu_memory.process_running",
                          side_effect=[True, True, False]), \
                    patch("gpu_memory.sample", side_effect=[owned] * 10), \
                    patch("gpu_memory.time.sleep"):
                self.assertEqual(monitor(123, output), 1)
            with output.open(newline="") as stream:
                result = next(csv.DictReader(stream))
            self.assertEqual(result["cleanup_status"], "contexts_remain")
            self.assertEqual(result["cleanup_checks"], "8")
            self.assertEqual(result["status"], "unavailable")

    def test_context_release_requires_two_clean_observations(self):
        with tempfile.TemporaryDirectory() as directory:
            output = Path(directory) / "memory.csv"
            owned = (100, True, {"GPU-A": 100}, {456})
            clear = (0, False, {}, set())
            with patch("gpu_memory.os.getpgid", return_value=123), \
                    patch("gpu_memory.process_running",
                          side_effect=[True, True, False]), \
                    patch("gpu_memory.sample", side_effect=[
                        owned, owned, owned, clear, clear]), \
                    patch("gpu_memory.time.sleep"):
                self.assertEqual(monitor(123, output), 0)
            with output.open(newline="") as stream:
                result = next(csv.DictReader(stream))
            self.assertEqual(result["cleanup_status"], "observed_clear")
            self.assertEqual(result["cleanup_checks"], "3")
            self.assertEqual(result["owned_pid_count"], "1")

    def test_postfit_telemetry_error_blocks_success(self):
        with tempfile.TemporaryDirectory() as directory:
            output = Path(directory) / "memory.csv"
            owned = (100, True, {"GPU-A": 100}, {456})
            error = subprocess.TimeoutExpired("nvidia-smi", 3)
            with patch("gpu_memory.os.getpgid", return_value=123), \
                    patch("gpu_memory.process_running",
                          side_effect=[True, True, False]), \
                    patch("gpu_memory.sample", side_effect=[
                        owned, owned, error]), \
                    patch("gpu_memory.time.sleep"):
                self.assertEqual(monitor(123, output), 1)
            with output.open(newline="") as stream:
                result = next(csv.DictReader(stream))
            self.assertEqual(result["cleanup_status"], "unknown")
            self.assertEqual(result["status"], "unavailable")

    def test_malformed_gpu_process_rows_fail_closed(self):
        with patch("gpu_memory.query_gpu_processes",
                   return_value="GPU-A,not-a-pid,100\n"):
            with self.assertRaisesRegex(ValueError, "Malformed"):
                sample(123, 123)

    def test_observed_worker_stays_owned_after_reparenting(self):
        rows = "GPU-A,456,100\nGPU-B,789,200\n"
        with patch("gpu_memory.query_gpu_processes", return_value=rows), \
                patch("gpu_memory.belongs_to", return_value=False):
            used, found, devices, pids = sample(123, 123, {456})
        self.assertTrue(found)
        self.assertEqual(pids, {456})
        self.assertEqual(devices, {"GPU-A": 100 * 1024 * 1024})
        self.assertEqual(used, 100 * 1024 * 1024)

    def test_hung_telemetry_has_bounded_final_wait(self):
        process = Mock(pid=456)
        process.communicate.side_effect = subprocess.TimeoutExpired(
            "nvidia-smi", 3)
        process.wait.side_effect = subprocess.TimeoutExpired(
            "nvidia-smi", 2)
        with patch("gpu_memory.subprocess.Popen",
                   return_value=process):
            with self.assertRaisesRegex(RuntimeError,
                                        "PID 456 did not stop"):
                query_gpu_processes(3)
        process.kill.assert_called_once_with()
        process.wait.assert_called_once_with(timeout=2)

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
