"""Check that the pilot audit accepts only its two exact Slurm tasks."""

from types import SimpleNamespace
from unittest.mock import patch
import unittest

import audit_pca_shape_pilot as pilot


class PcaShapePilotTests(unittest.TestCase):
    def test_exact_array_tasks(self):
        output = ("1606370_16|fer-v2-pca16|COMPLETED|0:0\n"
                  "1606371_16|fer-v2-pca32|COMPLETED|0:0\n")
        with patch.object(pilot.subprocess, "run",
                          return_value=SimpleNamespace(stdout=output)):
            self.assertEqual(pilot.scheduler_outcomes(),
                             {"1606370": ("COMPLETED", "0:0"),
                              "1606371": ("COMPLETED", "0:0")})

    def test_unrelated_or_missing_task_is_rejected(self):
        output = ("1606370_15|fer-v2-pca16|COMPLETED|0:0\n"
                  "1606371_16|fer-v2-pca32|COMPLETED|0:0\n")
        with patch.object(pilot.subprocess, "run",
                          return_value=SimpleNamespace(stdout=output)):
            with self.assertRaisesRegex(ValueError, "not accounted for"):
                pilot.scheduler_outcomes()


if __name__ == "__main__":
    unittest.main()
