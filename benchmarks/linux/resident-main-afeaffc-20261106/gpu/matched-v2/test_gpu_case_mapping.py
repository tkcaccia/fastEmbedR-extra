"""Checks for Slurm GPU index remapping in the resident pilot."""

import importlib.util
from pathlib import Path
import unittest
from unittest.mock import patch


source = Path(__file__).with_name(
    "gpu_case_runner.py")
spec = importlib.util.spec_from_file_location("pilot_v3", source)
pilot = importlib.util.module_from_spec(spec)
spec.loader.exec_module(pilot)


class AllocationMappingTests(unittest.TestCase):
    def setUp(self):
        self.inventory = {"0": "GPU-first", "1": "GPU-second"}

    def test_slurm_host_indices_can_be_remapped(self):
        actual = pilot.resolve_allocated_uuids(
            "1,3", "0,1", self.inventory, 2)
        self.assertEqual(actual, {"GPU-first", "GPU-second"})

    def test_direct_indices_are_valid(self):
        actual = pilot.resolve_allocated_uuids(
            "0,1", "0,1", self.inventory, 2)
        self.assertEqual(actual, {"GPU-first", "GPU-second"})

    def test_unfiltered_inventory_fails_closed(self):
        inventory = {**self.inventory, "2": "GPU-unassigned"}
        with self.assertRaisesRegex(RuntimeError, "Cannot prove"):
            pilot.resolve_allocated_uuids("1,3", "0,1", inventory, 2)

    def test_visible_index_mismatch_fails_closed(self):
        with self.assertRaisesRegex(RuntimeError, "Cannot prove"):
            pilot.resolve_allocated_uuids(
                "1,3", "1,2", self.inventory, 2)

    def test_duplicate_uuid_fails_closed(self):
        inventory = {"0": "GPU-first", "1": "GPU-first"}
        with self.assertRaisesRegex(RuntimeError, "duplicate"):
            pilot.resolve_allocated_uuids("1,3", "0,1", inventory, 2)

    def test_duplicate_allocation_fails_closed(self):
        with self.assertRaisesRegex(RuntimeError, "Cannot prove"):
            pilot.resolve_allocated_uuids(
                "1,1", "0,1", self.inventory, 2)

    def test_one_to_three_devices_with_host_index_remapping(self):
        for count in (1, 2, 3):
            with self.subTest(count=count):
                inventory = {str(index): f"GPU-{index}"
                             for index in range(count)}
                host_ids = ",".join(str(index + 3)
                                    for index in range(count))
                visible = ",".join(inventory)
                actual = pilot.resolve_allocated_uuids(
                    host_ids, visible, inventory, count)
                self.assertEqual(actual, set(inventory.values()))

    def test_count_mismatch_and_four_devices_fail_closed(self):
        for count in (1, 3, 4):
            with self.subTest(count=count):
                with self.assertRaisesRegex(RuntimeError, "Cannot prove"):
                    pilot.resolve_allocated_uuids(
                        "1,3", "0,1", self.inventory, count)

    def test_assigned_gpu_memory_is_complete(self):
        rows = "GPU-first, 100\nGPU-second, 250\n"
        with patch.object(pilot, "checked_command", return_value=rows):
            actual = pilot.gpu_memory_mib(
                {"GPU-first", "GPU-second"})
        self.assertEqual(actual, {"GPU-first": 100,
                                  "GPU-second": 250})

    def test_missing_or_ambiguous_memory_fails_closed(self):
        for rows in ("GPU-first, 100\n",
                     "GPU-first, unknown\nGPU-second, 250\n"):
            with self.subTest(rows=rows), patch.object(
                    pilot, "checked_command", return_value=rows):
                with self.assertRaises(RuntimeError):
                    pilot.gpu_memory_mib(
                        {"GPU-first", "GPU-second"})


if __name__ == "__main__":
    unittest.main()
