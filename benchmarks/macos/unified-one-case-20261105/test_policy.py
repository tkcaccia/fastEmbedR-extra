"""Pure Python admission and telemetry checks for the Mac case runner."""

import tempfile
import unittest
from pathlib import Path

from policy import valid_case
from run_case import peak_rss


def example():
    root = "/Users/silvanopiazza/Documents/Stefano"
    return dict(case_id="coil20_umap_cpu1_2d_s4_r1",
                dataset="COIL20",
                input_path=root + "/data/COIL20.RData",
                input_sha256="a" * 64,
                source_dir=root + "/source-v1",
                source_sha256="b" * 64,
                dll_sha256="c" * 64,
                output_dir=root + "/results/coil20_umap_cpu1_2d_s4_r1",
                method="UMAP", backend="cpu", cores=1,
                seed=4, repetition=1, dimensions=2, pca_rank=30,
                expected_rows=1440, expected_columns=1024,
                storage_mode="resident", fit_scope="full",
                timeout_seconds=1800, quality_sample=600,
                spill=False, scientific_tests=1, warmup_fits=0)


class PolicyTests(unittest.TestCase):
    def test_valid_resident_case(self):
        self.assertTrue(valid_case(example()))

    def test_hpc_style_streaming_and_spill_are_rejected(self):
        for key, value in (("storage_mode", "file_backed"),
                           ("fit_scope", "landmark"),
                           ("spill", True),
                           ("scientific_tests", 2),
                           ("scientific_tests", True),
                           ("warmup_fits", 1),
                           ("warmup_fits", False)):
            with self.subTest(key=key):
                case = example()
                case[key] = value
                self.assertFalse(valid_case(case))

    def test_metal_and_path_constraints(self):
        case = example()
        case.update(backend="metal", cores=4)
        self.assertFalse(valid_case(case))
        case = example()
        case["input_path"] = "/tmp/COIL20.RData"
        self.assertFalse(valid_case(case))
        case = example()
        case["pca_rank"] = 1024
        self.assertFalse(valid_case(case))

    def test_time_file_has_peak_rss(self):
        with tempfile.TemporaryDirectory() as root:
            path = Path(root) / "time.native"
            path.write_text(" 123456 maximum resident set size\n")
            self.assertEqual(peak_rss(path), 123456)
            path.write_text("time unavailable\n")
            self.assertIsNone(peak_rss(path))


if __name__ == "__main__":
    unittest.main()
