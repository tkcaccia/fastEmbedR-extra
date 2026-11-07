"""Reject incomplete or unrelated Slurm accounting for dataset waves."""

import unittest

from audit_dataset_wave_v2 import parse_sacct


class DatasetWaveAccountingTests(unittest.TestCase):
    def test_only_exact_numeric_array_indices_are_parsed(self):
        raw = ("1606375_0|fer-v2-coil-cpu1|COMPLETED|0:0\n"
               "1606375_[1-6%1]|fer-v2-coil-cpu1|PENDING|0:0\n"
               "1606376_3|fer-v2-coil-cpu2|FAILED|1:0\n"
               "1609999_0|other|COMPLETED|0:0\n")
        self.assertEqual(parse_sacct(raw, ["1606375", "1606376"]),
                         {("1606375", 0): ("COMPLETED", "0:0"),
                          ("1606376", 3): ("FAILED", "1:0")})


if __name__ == "__main__":
    unittest.main()
