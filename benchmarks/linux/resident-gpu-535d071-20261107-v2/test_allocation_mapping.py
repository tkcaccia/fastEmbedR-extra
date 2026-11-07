"""Reject a bad GPU mapping without rejecting a valid one-GPU allocation."""

import importlib.util
from pathlib import Path
import unittest


SOURCE = Path(__file__).with_name("gpu_case_runner.py")
SPEC = importlib.util.spec_from_file_location("pilot_cuda1_v2", SOURCE)
PILOT = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(PILOT)


class AllocationMappingTests(unittest.TestCase):
    def test_one_gpu_with_slurm_host_index_remapping(self):
        actual = PILOT.resolve_allocated_uuids(
            "3", "0", {"0": "GPU-allocated"})
        self.assertEqual(actual, {"GPU-allocated"})

    def test_one_gpu_with_direct_index(self):
        actual = PILOT.resolve_allocated_uuids(
            "0", "0", {"0": "GPU-allocated"})
        self.assertEqual(actual, {"GPU-allocated"})

    def test_two_slurm_devices_are_rejected(self):
        with self.assertRaisesRegex(RuntimeError, "Cannot prove"):
            PILOT.resolve_allocated_uuids(
                "1,3", "0", {"0": "GPU-allocated"})

    def test_two_visible_devices_are_rejected(self):
        with self.assertRaisesRegex(RuntimeError, "Cannot prove"):
            PILOT.resolve_allocated_uuids(
                "3", "0,1", {"0": "GPU-allocated"})

    def test_unfiltered_inventory_is_rejected(self):
        with self.assertRaisesRegex(RuntimeError, "Cannot prove"):
            PILOT.resolve_allocated_uuids(
                "3", "0", {"0": "GPU-allocated",
                           "1": "GPU-unassigned"})

    def test_non_uuid_identity_is_rejected(self):
        with self.assertRaisesRegex(RuntimeError, "UUID"):
            PILOT.resolve_allocated_uuids("3", "0", {"0": "unknown"})


if __name__ == "__main__":
    unittest.main()
