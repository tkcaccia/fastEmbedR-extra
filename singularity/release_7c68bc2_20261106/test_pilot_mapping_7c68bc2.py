"""Checks for Slurm GPU index remapping in the resident pilot."""

import importlib.util
from pathlib import Path
import unittest


source = Path(__file__).with_name(
    "hpc_resident_pilot_runner_7c68bc2.py")
spec = importlib.util.spec_from_file_location("pilot_v3", source)
pilot = importlib.util.module_from_spec(spec)
spec.loader.exec_module(pilot)


class AllocationMappingTests(unittest.TestCase):
    def setUp(self):
        self.inventory = {"0": "GPU-first", "1": "GPU-second"}

    def test_slurm_host_indices_can_be_remapped(self):
        actual = pilot.resolve_allocated_uuids(
            "1,3", "0,1", self.inventory)
        self.assertEqual(actual, {"GPU-first", "GPU-second"})

    def test_direct_indices_are_valid(self):
        actual = pilot.resolve_allocated_uuids(
            "0,1", "0,1", self.inventory)
        self.assertEqual(actual, {"GPU-first", "GPU-second"})

    def test_unfiltered_inventory_fails_closed(self):
        inventory = {**self.inventory, "2": "GPU-unassigned"}
        with self.assertRaisesRegex(RuntimeError, "Cannot prove"):
            pilot.resolve_allocated_uuids("1,3", "0,1", inventory)

    def test_visible_index_mismatch_fails_closed(self):
        with self.assertRaisesRegex(RuntimeError, "Cannot prove"):
            pilot.resolve_allocated_uuids(
                "1,3", "1,2", self.inventory)

    def test_duplicate_uuid_fails_closed(self):
        inventory = {"0": "GPU-first", "1": "GPU-first"}
        with self.assertRaisesRegex(RuntimeError, "duplicate"):
            pilot.resolve_allocated_uuids("1,3", "0,1", inventory)

    def test_duplicate_allocation_fails_closed(self):
        with self.assertRaisesRegex(RuntimeError, "Cannot prove"):
            pilot.resolve_allocated_uuids(
                "1,1", "0,1", self.inventory)


if __name__ == "__main__":
    unittest.main()
