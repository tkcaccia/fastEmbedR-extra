"""Verify Slurm's array ID and per-task numeric ID are both retained."""

import unittest

from audit_dataset_wave_v3 import parse_sacct


class DatasetWaveNumericIdsTests(unittest.TestCase):
    def test_exact_array_tasks_keep_numeric_ids(self):
        raw = ("1606375_0|1606385|COMPLETED|0:0\n"
               "1606375_6|1606375|COMPLETED|0:0\n"
               "1606375_[1-5%1]|1606375|PENDING|0:0\n"
               "1609999_0|1609999|COMPLETED|0:0\n")
        self.assertEqual(parse_sacct(raw, ["1606375"]),
                         {("1606375", 0): ("1606385", "COMPLETED", "0:0"),
                          ("1606375", 6): ("1606375", "COMPLETED", "0:0")})


if __name__ == "__main__":
    unittest.main()
