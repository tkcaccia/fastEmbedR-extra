#!/usr/bin/env python3
"""Small tests for the matched GPU audit's resource accounting."""

import csv
import json
import os
import sys
import tempfile
import unittest
from pathlib import Path
from unittest import mock

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))

from deep1b.disk_peak import payload_bytes
import measure_multigpu_knn_matched as audit
from measure_multigpu_knn_matched import (
    expected_uuids, gpu_status, new_peak, observe, tree_rss,
)


class ResourceAccountingTest(unittest.TestCase):
    def test_process_tree_includes_children_and_group(self):
        processes = {
            10: (1, 100),
            11: (10, 200),
            12: (11, 300),
            13: (1, 400),
            14: (13, 500),
            15: (1, 600),
        }
        self.assertEqual(tree_rss(processes, 10, {13}), 1500)

    def test_expected_uuids_use_only_two_gpu_fit(self):
        with tempfile.TemporaryDirectory() as temp:
            path = Path(temp) / "gpu_device_map.csv"
            with path.open("w", newline="") as stream:
                writer = csv.DictWriter(stream, ("fit", "uuid"))
                writer.writeheader()
                writer.writerows([
                    {"fit": "one_gpu", "uuid": "GPU-OTHER"},
                    {"fit": "two_gpu", "uuid": "gpu-A"},
                    {"fit": "two_gpu", "uuid": "GPU-B"},
                ])
            self.assertEqual(expected_uuids(path), {"GPU-A", "GPU-B"})
            self.assertEqual(expected_uuids(path, "one_gpu"),
                             {"GPU-OTHER"})

    def test_unobserved_device_is_not_zero_memory(self):
        peak = new_peak()
        observe(peak, 100, 20, 4096, 1024, True,
                {"gpu-a": 1024}, False)
        self.assertEqual(gpu_status(peak, {"GPU-A"}), "ok")
        self.assertEqual(gpu_status(peak, {"GPU-A", "GPU-B"}),
                         "unavailable")
        self.assertEqual(peak["rss"], 100)
        self.assertEqual(peak["allocated"], 4096)

    def test_generated_work_is_counted(self):
        with tempfile.TemporaryDirectory() as temp:
            root = Path(temp)
            (root / "work").mkdir()
            (root / "work" / "graph.bin").write_bytes(b"test")
            apparent, allocated = payload_bytes(root)
            self.assertEqual(apparent, 4)
            self.assertGreater(allocated, 0)

    def test_sequential_fit_phases_keep_separate_peaks(self):
        with tempfile.TemporaryDirectory() as temp:
            root = Path(temp)
            output = root / "audit"
            runner = root / "fake_rscript"
            runner.write_text("""#!/usr/bin/env python3
import sys
import time
from pathlib import Path
out = Path(sys.argv[5])
(out / 'work').mkdir(parents=True)
(out / 'work' / 'graph.bin').write_bytes(b'graph')
for phase in ('one_gpu', 'two_gpu', 'audit'):
    (out / 'phase.txt').write_text(phase)
    time.sleep(0.65)
(out / 'gpu_device_map.csv').write_text(
    'fit,uuid\\none_gpu,GPU-A\\ntwo_gpu,GPU-A\\ntwo_gpu,GPU-B\\n')
""")
            runner.chmod(0o755)

            def gpu_sample(root_pid, group):
                marker = output / "run" / "phase.txt"
                phase = marker.read_text() if marker.exists() else "setup"
                if phase == "one_gpu":
                    return 1024, True, {"GPU-A": 1024}
                if phase == "two_gpu":
                    return 3072, True, {"GPU-A": 1024,
                                        "GPU-B": 2048}
                return 0, False, {}

            with mock.patch.dict(os.environ, {
                    "FASTEMBEDR_RSCRIPT": str(runner)}), \
                    mock.patch.object(audit, "gpu_sample",
                                      side_effect=gpu_sample), \
                    mock.patch.object(audit, "tree_rss",
                                      return_value=100):
                code = audit.measure(Path("unused.R"),
                                     Path("unused.fbin"), "8", "2",
                                     output, "4")
            self.assertEqual(code, 0)
            with (output / "resource_peak.csv").open(newline="") as f:
                rows = {row["phase"]: row for row in csv.DictReader(f)}
            self.assertEqual(rows["one_gpu"]["gpu_status"], "ok")
            self.assertEqual(rows["two_gpu"]["gpu_status"], "ok")
            self.assertEqual(rows["one_gpu"]["peak_process_gpu_bytes"],
                             "1024")
            self.assertEqual(rows["two_gpu"]["peak_process_gpu_bytes"],
                             "3072")
            self.assertEqual(json.loads(
                rows["two_gpu"]["peak_gpu_per_uuid_json"]),
                {"GPU-A": 1024, "GPU-B": 2048})


if __name__ == "__main__":
    unittest.main()
